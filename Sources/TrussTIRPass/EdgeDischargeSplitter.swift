import SwiftBetterDiagnostic
import TrussCore

final class EdgeDischargeSplitter {
    private let registry: TIR.Registry
    private let attemptLimit: Int

    init(registry: TIR.Registry, attemptLimit: Int = 16) {
        self.registry = registry
        self.attemptLimit = attemptLimit
    }

    private(set) var failures: [TIRPassFailure] = []

    func split(module: TIR.Module) -> [ObjectIdentifier: [PresplitDischarge]] {
        var result: [ObjectIdentifier: [PresplitDischarge]] = [:]
        failures = []
        for function in module.functions where !function.isExtern && !function.basicBlocks.isEmpty {
            let discharges = split(function: function)
            guard !discharges.isEmpty else {
                continue
            }
            result[ObjectIdentifier(function)] = discharges
        }
        return result
    }

    private func split(function: TIR.Function) -> [PresplitDischarge] {
        var discharges: [PresplitDischarge] = []
        var attempts = 0
        var unsplit: [EdgeDischarge] = []
        var settled = false
        while attempts < attemptLimit {
            attempts += 1
            let plan = LifetimePlan(
                function: function, registry: registry, presplitDischarges: discharges
            )
            let pending = plan.pendingEdgeDischarges()
            guard !pending.isEmpty else {
                settled = true
                break
            }
            var cleanupBlocks: [EdgeKey: TIR.BasicBlock] = [:]
            var split = false
            for discharge in pending {
                let edge = EdgeKey(discharge.block, discharge.successor)
                if let cleanup = cleanupBlocks[edge] {
                    discharges.append(PresplitDischarge(block: cleanup, slot: discharge.slot))
                    continue
                }
                guard let cleanup = splitEdge(from: discharge.block, to: discharge.successor) else {
                    continue
                }
                cleanupBlocks[edge] = cleanup
                discharges.append(PresplitDischarge(block: cleanup, slot: discharge.slot))
                split = true
            }
            guard split else {
                unsplit = pending
                settled = true
                break
            }
        }
        if !settled {
            unsplit = LifetimePlan(
                function: function, registry: registry, presplitDischarges: discharges
            ).pendingEdgeDischarges()
        }
        appendFailures(for: unsplit, in: function)
        return discharges
    }

    private func appendFailures(for pending: [EdgeDischarge], in function: TIR.Function) {
        for discharge in pending {
            failures.append(
                TIRPassFailure(
                    functionName: function.name, slotName: discharge.slot.name,
                    fromBlockName: discharge.block.name,
                    toBlockName: discharge.successor.name,
                    sourceRange: failureRange(from: discharge.block, in: function)
                )
            )
        }
    }

    private func failureRange(from block: TIR.BasicBlock, in function: TIR.Function) -> SourceRange {
        if let anchor = block.instructions.last, isKnown(anchor.sourceRange) {
            return anchor.sourceRange
        }
        if isKnown(block.sourceRange) {
            return block.sourceRange
        }
        return function.sourceRange
    }

    private func isKnown(_ range: SourceRange) -> Bool {
        range.start.buffer.filePath != TIR.unknownSourceRange.start.buffer.filePath
    }

    private func splitEdge(
        from block: TIR.BasicBlock, to successor: TIR.BasicBlock
    ) -> TIR.BasicBlock? {
        guard let function = block.function, let terminator = block.instructions.last else {
            return nil
        }
        let cleanup: TIR.BasicBlock
        switch terminator {
        case let branch as TIR.Branch:
            guard branch.target === successor else {
                return nil
            }
            cleanup = makeCleanupBlock(
                in: function, forwarding: successor, arguments: branch.arguments, anchor: terminator
            )
            replaceTerminator(
                of: block, with: located(TIR.Branch(target: cleanup), anchor: terminator)
            )
        case let conditional as TIR.ConditionalBranch:
            let toTrue = conditional.trueBranch === successor
            let toFalse = conditional.falseBranch === successor
            guard toTrue || toFalse else {
                return nil
            }
            if toTrue, toFalse {
                guard conditional.trueArguments.isEmpty, conditional.falseArguments.isEmpty else {
                    return nil
                }
                cleanup = makeCleanupBlock(
                    in: function, forwarding: successor, arguments: [], anchor: terminator
                )
                let replacement = TIR.ConditionalBranch(
                    condition: conditional.condition,
                    trueBranch: cleanup,
                    falseBranch: cleanup
                )
                replaceTerminator(of: block, with: located(replacement, anchor: terminator))
                retargetPhis(in: successor, from: block, to: cleanup)
                return cleanup
            }
            cleanup = makeCleanupBlock(
                in: function, forwarding: successor,
                arguments: toTrue ? conditional.trueArguments : conditional.falseArguments,
                anchor: terminator
            )
            let replacement = TIR.ConditionalBranch(
                condition: conditional.condition,
                trueBranch: toTrue ? cleanup : conditional.trueBranch,
                falseBranch: toFalse ? cleanup : conditional.falseBranch,
                trueArguments: toTrue ? [] : conditional.trueArguments,
                falseArguments: toFalse ? [] : conditional.falseArguments
            )
            replaceTerminator(of: block, with: located(replacement, anchor: terminator))
        case let switchEnum as TIR.SwitchEnum:
            guard let created = splitSwitch(
                switchEnum, of: block, successor: successor, in: function
            ) else {
                return nil
            }
            cleanup = created
        default:
            return nil
        }
        retargetPhis(in: successor, from: block, to: cleanup)
        return cleanup
    }

    private func splitSwitch(
        _ instruction: TIR.SwitchEnum, of block: TIR.BasicBlock, successor: TIR.BasicBlock,
        in function: TIR.Function
    ) -> TIR.BasicBlock? {
        let matchingCases = instruction.cases.filter { $0.block === successor }
        let matchingDefault = instruction.defaultBlock === successor
        guard matchingCases.count + (matchingDefault ? 1 : 0) == 1 else {
            return nil
        }
        let arguments = matchingCases.first?.arguments ?? []
        let cleanup = makeCleanupBlock(
            in: function, forwarding: successor, arguments: arguments, anchor: instruction
        )
        let cases = instruction.cases.map { enumCase in
            guard enumCase.block === successor else {
                return enumCase
            }
            return TIR.SwitchEnum.Case(tag: enumCase.tag, block: cleanup)
        }
        let defaultBlock = instruction.defaultBlock === successor ? cleanup : instruction.defaultBlock
        let replacement = TIR.SwitchEnum(
            value: instruction.value, cases: cases, defaultBlock: defaultBlock
        )
        replaceTerminator(of: block, with: located(replacement, anchor: instruction))
        return cleanup
    }

    private func makeCleanupBlock(
        in function: TIR.Function, forwarding successor: TIR.BasicBlock,
        arguments: [TIR.Value], anchor: TIR.Instruction
    ) -> TIR.BasicBlock {
        let cleanup = function.addBasicBlock(name: "cleanup")
        cleanup.sourceRange = anchor.sourceRange
        cleanup.instructions = [
            located(TIR.Branch(target: successor, arguments: arguments), anchor: anchor),
        ]
        return cleanup
    }

    private func replaceTerminator(of block: TIR.BasicBlock, with instruction: TIR.Instruction) {
        guard !block.instructions.isEmpty else {
            return
        }
        block.instructions[block.instructions.count - 1] = instruction
    }

    private func retargetPhis(
        in successor: TIR.BasicBlock, from block: TIR.BasicBlock, to cleanup: TIR.BasicBlock
    ) {
        for (index, instruction) in successor.instructions.enumerated() {
            guard let phi = instruction as? TIR.Phi,
                  phi.incomings.contains(where: { $0.block === block })
            else {
                continue
            }
            let incomings = phi.incomings.map { incoming in
                guard incoming.block === block else {
                    return incoming
                }
                return TIR.Phi.Incoming(value: incoming.value, block: cleanup)
            }
            let rebuilt = TIR.Phi(incomings: incomings, ty: phi.result.ty, name: phi.result.name)
            rebuilt.result = phi.result
            rebuilt.sourceRange = phi.sourceRange
            successor.instructions[index] = rebuilt
        }
    }

    private func located<T: TIR.Instruction>(_ instruction: T, anchor: TIR.Instruction) -> T {
        instruction.sourceRange = anchor.sourceRange
        return instruction
    }

    private struct EdgeKey: Hashable {
        let from: ObjectIdentifier
        let to: ObjectIdentifier

        init(_ from: TIR.BasicBlock, _ to: TIR.BasicBlock) {
            self.from = ObjectIdentifier(from)
            self.to = ObjectIdentifier(to)
        }
    }
}

public extension TIRPassFailure {
    var diagnostic: Diagnostic {
        Diagnostic(severity: .error, message: message, range: sourceRange)
    }
}

public extension TIRPass {
    static func emitFailures(_ failures: [TIRPassFailure], in context: Context) {
        for failure in failures {
            context.diagnosticEngine.emit(failure.diagnostic)
        }
    }
}
