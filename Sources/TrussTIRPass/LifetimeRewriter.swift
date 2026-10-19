import SwiftBetterDiagnostic
import TrussCore

final class LifetimeRewriter: TIR.Rewriter {
    private let registry: TIR.Registry
    private let presplitDischarges: [ObjectIdentifier: [PresplitDischarge]]
    private var plan: LifetimePlan?
    private var currentFunction: TIR.Function?
    init(registry: TIR.Registry, presplitDischarges: [ObjectIdentifier: [PresplitDischarge]]) {
        self.registry = registry
        self.presplitDischarges = presplitDischarges
        super.init()
    }

    override func rewriteFunctionSignature(_ function: TIR.Function) -> Id.TIRTypeId {
        currentFunction = function
        plan = LifetimePlan(
            function: function, registry: registry,
            presplitDischarges: presplitDischarges[ObjectIdentifier(function)] ?? []
        )
        return function.ty
    }

    override func rewrite(instructions: [TIR.Instruction]) -> [TIR.Instruction] {
        let rewritten = super.rewrite(instructions: instructions)
        guard let plan else {
            return rewritten
        }
        var output: [TIR.Instruction] = []
        for (index, instruction) in rewritten.enumerated() {
            let original = index < instructions.count ? instructions[index] : instruction
            output.append(contentsOf: materialize(plan.insertions(before: original), anchor: instruction))
            output.append(instruction)
            output.append(contentsOf: materialize(plan.insertions(after: original), anchor: instruction))
        }
        return output
    }

    private func materialize(_ actions: [LifetimeAction], anchor: TIR.Instruction) -> [TIR.Instruction] {
        actions.flatMap { action -> [TIR.Instruction] in
            switch action {
            case let .Retain(value):
                [located(TIR.Retain(value: remap(value: value)), anchor: anchor)]
            case let .Release(value):
                [located(TIR.Release(value: remap(value: value)), anchor: anchor)]
            case let .Destroy(value):
                [located(TIR.Destroy(value: remap(value: value)), anchor: anchor)]
            case let .DeallocStack(value):
                [located(TIR.DeallocStack(value: remap(value: value)), anchor: anchor)]
            case let .SlotDischarge(slot, destroying):
                slotDischarge(slot: remap(value: slot), destroying: destroying, anchor: anchor)
            case let .FieldDischarge(base, structTypeId, startIndex):
                fieldDischarge(
                    base: remap(value: base), typeId: structTypeId, startIndex: startIndex,
                    visited: [], anchor: anchor
                )
            }
        }
    }

    private func slotDischarge(
        slot: TIR.Value, destroying: Bool, anchor: TIR.Instruction
    ) -> [TIR.Instruction] {
        let pointee: Id.TIRTypeId? = switch registry.types[slot.ty] {
        case let address as TIRType.AddressType:
            address.pointee
        case let pointer as TIRType.PointerType:
            pointer.pointee
        default:
            nil
        }
        guard let pointee else {
            return []
        }
        let load = TIR.Load(ptr: slot, ty: pointee, name: freshName())
        return [
            located(load, anchor: anchor),
            located(consume(destroying: destroying, value: load.result), anchor: anchor),
        ]
    }

    private func fieldDischarge(
        base: TIR.Value, typeId: Id.TIRTypeId, startIndex: Int,
        visited: Set<Id.TIRTypeId>, anchor: TIR.Instruction
    ) -> [TIR.Instruction] {
        guard !visited.contains(typeId), let type = registry.types[typeId] else {
            return []
        }
        var nested = visited
        nested.insert(typeId)
        var output: [TIR.Instruction] = []
        for (index, field) in fields(of: type).enumerated()
            where index >= startIndex && TIRFacts.isReferenceValue(field.type, registry: registry)
        {
            let element: TIR.Value
            if type is TIRType.ClassType {
                let address = TIR.ClassElementAddr(
                    registry: registry, base: base, index: index, name: freshName()
                )
                output.append(located(address, anchor: anchor))
                element = address.result
            } else {
                let address = TIR.StructElementAddr(
                    registry: registry, base: base, index: index, name: freshName()
                )
                output.append(located(address, anchor: anchor))
                element = address.result
            }
            if TIRFacts.structType(of: field.type, registry: registry) != nil,
               TIRFacts.hasReferenceFields(field.type, registry: registry)
            {
                output.append(
                    contentsOf: fieldDischarge(
                        base: element, typeId: field.type, startIndex: 0, visited: nested,
                        anchor: anchor
                    )
                )
                continue
            }
            let load = TIR.Load(ptr: element, ty: field.type, name: freshName())
            output.append(located(load, anchor: anchor))
            output.append(
                located(
                    consume(
                        destroying: TIRFacts.needsTeardown(field.type, registry: registry),
                        value: load.result
                    ),
                    anchor: anchor
                )
            )
        }
        return output
    }

    private func consume(destroying: Bool, value: TIR.Value) -> TIR.Instruction {
        destroying ? TIR.Destroy(value: value) : TIR.Release(value: value)
    }

    private func fields(of type: TIRType.TIRType) -> [(name: String, type: Id.TIRTypeId)] {
        if let structType = type as? TIRType.StructType {
            return structType.fields
        }
        if let classType = type as? TIRType.ClassType {
            return classType.fields
        }
        return []
    }

    private func located<T: TIR.Instruction>(_ instruction: T, anchor: TIR.Instruction) -> T {
        instruction.sourceRange = anchor.sourceRange
        return instruction
    }

    private func freshName() -> String {
        guard let function = currentFunction else {
            return ""
        }
        let index = function.nextValueIndex
        function.nextValueIndex += 1
        return String(index)
    }
}
