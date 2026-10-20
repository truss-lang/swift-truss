import SwiftBetterDiagnostic

public extension TIR {
    final class Verifier {
        public enum FailureKind: String, Sendable, Equatable {
            case Structure
            case Dominance
            case Registry
            case TypeConsistency = "type"
            case Ownership

            public var label: String {
                switch self {
                case .Structure:
                    "structure"
                case .Dominance:
                    "dominance"
                case .Registry:
                    "registry"
                case .TypeConsistency:
                    "type"
                case .Ownership:
                    "ownership"
                }
            }
        }

        public struct Failure: Equatable {
            public let kind: FailureKind
            public let message: String
            public let range: SourceRange

            public init(kind: FailureKind, message: String, range: SourceRange) {
                self.kind = kind
                self.message = message
                self.range = range
            }
        }

        private struct Definition {
            let block: BasicBlock
            let index: Int
        }

        private struct Site {
            let function: Function
            let block: BasicBlock
            let range: SourceRange

            var location: String {
                "block '\(block.name)' of function '\(function.name)'"
            }
        }

        public enum OwnershipMode: Sendable, Equatable {
            case Advisory
            case Strict
        }

        private let context: Context
        private let ownershipMode: OwnershipMode
        private var registry: Registry?
        private var failures: [Failure] = []
        private var failureKeys: Set<String> = []
        private var unresolvedTypeIds: Set<Id.TIRTypeId> = []
        private var unresolvedValueIds: Set<ObjectIdentifier> = []

        public init(context: Context) {
            self.context = context
            ownershipMode = .Advisory
        }

        public init(context: Context, ownershipMode: OwnershipMode) {
            self.context = context
            self.ownershipMode = ownershipMode
        }

        @discardableResult
        public func verify(_ module: Module) -> [Failure] {
            failures.removeAll()
            failureKeys.removeAll()
            unresolvedTypeIds.removeAll()
            unresolvedValueIds.removeAll()
            registry = module.registry
            for global in module.globals {
                verifyGlobal(global)
            }
            for function in module.functions {
                verifyFunction(function)
            }
            verifyRegistry()
            let result = failures
            for failure in result {
                emit(failure)
            }
            registry = nil
            return result
        }

        private var currentRegistry: Registry {
            guard let registry else {
                fatalError("TIR.Verifier.verify(_:) must run before the registry is queried")
            }
            return registry
        }

        private func emit(_ failure: Failure) {
            context.emitError(
                "TIR verification failed: \(failure.kind.label): \(failure.message)", at: failure.range
            )
        }

        private func record(_ kind: FailureKind, _ message: String, at range: SourceRange) {
            let key = "\(kind.rawValue)|\(message)|\(range.start.buffer.filePath):\(range.start.offset)"
            guard failureKeys.insert(key).inserted else {
                return
            }
            failures.append(Failure(kind: kind, message: message, range: range))
        }

        private func isKnown(_ range: SourceRange) -> Bool {
            range.start.buffer.filePath != TIR.unknownSourceRange.start.buffer.filePath
        }

        private func functionRange(_ function: Function) -> SourceRange {
            isKnown(function.sourceRange) ? function.sourceRange : TIR.unknownSourceRange
        }

        private func blockRange(_ block: BasicBlock, in function: Function) -> SourceRange {
            isKnown(block.sourceRange) ? block.sourceRange : functionRange(function)
        }

        private func instructionRange(
            _ instruction: Instruction, in block: BasicBlock, function: Function
        ) -> SourceRange {
            isKnown(instruction.sourceRange) ? instruction.sourceRange : blockRange(block, in: function)
        }

        @discardableResult
        private func resolveType(_ id: Id.TIRTypeId, at range: SourceRange) -> TIRType.TIRType? {
            if let ty = currentRegistry.types[id] {
                return ty
            }
            if unresolvedTypeIds.insert(id).inserted {
                record(.Registry, "\(typeName(id)) is not in registry.types", at: range)
            }
            return nil
        }

        private func isVoidType(_ id: Id.TIRTypeId) -> Bool {
            currentRegistry.types[id] is TIRType.VoidType
        }

        private func isBoolI1(_ id: Id.TIRTypeId) -> Bool {
            guard let ty = currentRegistry.types[id] as? TIRType.PrimitiveType else {
                return false
            }
            return ty.kind == .Bool && ty.bitWidth == 1
        }

        private func verifyGlobal(_ global: GlobalVariable) {
            let range = isKnown(global.sourceRange) ? global.sourceRange : TIR.unknownSourceRange
            resolveType(global.type, at: range)
            if let initializer = global.initializer, currentRegistry.functions[initializer] == nil {
                record(
                    .Registry,
                    "global '\(global.name)' has initializer function id \(initializer.id) that is not in registry.functions",
                    at: range
                )
            }
        }

        private func verifyFunction(_ function: Function) {
            verifyFunctionSignature(function)
            let blocks = function.basicBlocks
            guard !blocks.isEmpty else {
                if !function.isExtern {
                    record(
                        .Structure,
                        "non-extern function '\(function.name)' has no basic blocks",
                        at: functionRange(function)
                    )
                }
                return
            }
            let blockIds = Set(blocks.map { ObjectIdentifier($0) })
            var definitions: [ObjectIdentifier: Definition] = [:]
            for block in blocks {
                for (index, instruction) in block.instructions.enumerated() {
                    for value in TIR.Result.results(of: instruction) {
                        definitions[ObjectIdentifier(value)] = Definition(block: block, index: index)
                    }
                }
            }
            let successors = successorMap(of: function, blockIds: blockIds)
            let dominators = computeDominators(
                entry: ObjectIdentifier(blocks[0]),
                blocks: blocks.map { ObjectIdentifier($0) },
                successors: successors
            )
            for block in blocks {
                verifyBlockStructure(block, function: function, entry: blocks[0], blockIds: blockIds)
            }
            for block in blocks {
                for (index, instruction) in block.instructions.enumerated() {
                    let site = Site(
                        function: function, block: block,
                        range: instructionRange(instruction, in: block, function: function)
                    )
                    verifyInstruction(instruction, at: site)
                    for operand in TIR.Operands.operands(of: instruction) {
                        verifyOperand(
                            operand, useBlock: block, useIndex: index, definitions: definitions,
                            dominators: dominators, at: site
                        )
                    }
                    guard let phi = instruction as? Phi else {
                        continue
                    }
                    for incoming in phi.incomings {
                        verifyOperand(
                            incoming.value, useBlock: incoming.block,
                            useIndex: incoming.block.instructions.count,
                            definitions: definitions, dominators: dominators,
                            at: Site(
                                function: function, block: incoming.block,
                                range: instructionRange(instruction, in: incoming.block, function: function)
                            )
                        )
                    }
                }
            }
            verifyOwnership(function, blocks: blocks, successors: successors)
        }

        private func verifyFunctionSignature(_ function: Function) {
            let range = functionRange(function)
            resolveType(function.returnType, at: range)
            for parameter in function.parameters {
                resolveType(parameter.ty, at: range)
            }
            for block in function.basicBlocks {
                for argument in block.parameters {
                    resolveType(argument.ty, at: range)
                }
            }
            guard let ty = resolveType(function.ty, at: range) else {
                return
            }
            guard let functionType = ty as? TIRType.FunctionType else {
                record(
                    .Registry,
                    "function '\(function.name)' has type \(typeName(function.ty)), expected a function type",
                    at: range
                )
                return
            }
            let parameterTypes = function.parameters.map(\.ty)
            if functionType.parameters != parameterTypes {
                record(
                    .Registry,
                    "function '\(function.name)' has type \(typeName(function.ty)) with parameter types \(describe(parameterTypes)) but the function declares \(describe(functionType.parameters))",
                    at: range
                )
            }
            if functionType.returnType != function.returnType {
                record(
                    .Registry,
                    "function '\(function.name)' has type \(typeName(function.ty)) returning type \(typeName(functionType.returnType)) but the function declares return type \(typeName(function.returnType))",
                    at: range
                )
            }
            if functionType.isVariadic != function.isVariadic {
                record(
                    .Registry,
                    "function '\(function.name)' has type \(typeName(function.ty)) with variadic \(functionType.isVariadic) but the function declares variadic \(function.isVariadic)",
                    at: range
                )
            }
        }

        private func describe(_ ids: [Id.TIRTypeId]) -> String {
            "[" + ids.map { typeName($0) }.joined(separator: ", ") + "]"
        }

        private func typeName(_ id: Id.TIRTypeId) -> String {
            typeName(id, visited: [])
        }

        private func typeName(_ id: Id.TIRTypeId, visited: Set<Id.TIRTypeId>) -> String {
            guard !visited.contains(id), let ty = currentRegistry.types[id] else {
                return "type#\(id.id)"
            }
            let nested = visited.union([id])
            switch ty {
            case is TIRType.VoidType:
                return "void"
            case let primitive as TIRType.PrimitiveType:
                return primitiveName(primitive)
            case let pointer as TIRType.PointerType:
                return "*" + pointeeName(pointer.pointee, visited: nested)
            case let address as TIRType.AddressType:
                return "addr " + pointeeName(address.pointee, visited: nested)
            case is TIRType.MetadataType:
                return "meta"
            case let nominal as TIRType.NominalType:
                return nominalKeyword(nominal) + " " + nominal.displayText
            case let tuple as TIRType.TupleType:
                let elements = tuple.elements.map { element in
                    (element.label.map { $0 + ": " } ?? "") + typeName(element.type, visited: nested)
                }
                return "(" + elements.joined(separator: ",") + ")"
            case let function as TIRType.FunctionType:
                var parameters = function.parameters.map { typeName($0, visited: nested) }
                if function.isVariadic {
                    parameters.append("...")
                }
                return "fn(" + parameters
                    .joined(separator: ",") + ")->" + typeName(function.returnType, visited: nested)
            case let closure as TIRType.ClosureType:
                var parameters = closure.parameters.map { typeName($0, visited: nested) }
                if closure.isVariadic {
                    parameters.append("...")
                }
                return "closure(" + parameters
                    .joined(separator: ",") + ")->" + typeName(closure.returnType, visited: nested)
            case let existential as TIRType.ExistentialType:
                return "any " + existential.name
            default:
                return "type#\(id.id)"
            }
        }

        private func pointeeName(_ id: Id.TIRTypeId, visited: Set<Id.TIRTypeId>) -> String {
            if let nominal = currentRegistry.types[id] as? TIRType.NominalType {
                return nominal.displayText
            }
            return typeName(id, visited: visited)
        }

        private func nominalKeyword(_ ty: TIRType.NominalType) -> String {
            switch ty {
            case is TIRType.StructType:
                "struct"
            case is TIRType.ClassType:
                "class"
            case is TIRType.EnumType:
                "enum"
            default:
                "nominal"
            }
        }

        private func primitiveName(_ ty: TIRType.PrimitiveType) -> String {
            switch ty.kind {
            case .Signed:
                "i\(ty.bitWidth)"
            case .Unsigned:
                "u\(ty.bitWidth)"
            case .Float:
                "f\(ty.bitWidth)"
            case .Bool:
                "bool"
            case .Char:
                "char"
            }
        }

        private func verifyBlockStructure(
            _ block: BasicBlock, function: Function, entry: BasicBlock, blockIds: Set<ObjectIdentifier>
        ) {
            var terminatorIndex: Int?
            for (index, instruction) in block.instructions.enumerated() where isTerminator(instruction) {
                if terminatorIndex == nil {
                    terminatorIndex = index
                }
            }
            guard let terminatorIndex else {
                record(
                    .Structure,
                    "block '\(block.name)' of function '\(function.name)' has no terminator instruction",
                    at: blockRange(block, in: function)
                )
                return
            }
            if terminatorIndex != block.instructions.count - 1 {
                record(
                    .Structure,
                    "block '\(block.name)' of function '\(function.name)' has instructions after its terminator",
                    at: instructionRange(block.instructions[terminatorIndex + 1], in: block, function: function)
                )
            }
            verifyControlTransfer(
                block.instructions[terminatorIndex], block: block, function: function, entry: entry,
                blockIds: blockIds
            )
        }

        private func verifyControlTransfer(
            _ instruction: Instruction, block: BasicBlock, function: Function, entry: BasicBlock,
            blockIds: Set<ObjectIdentifier>
        ) {
            switch instruction {
            case let branch as Branch:
                verifyTarget(
                    branch.target, instruction: instruction, block: block, function: function, entry: entry,
                    blockIds: blockIds
                )
                verifyBlockArguments(
                    branch.arguments, target: branch.target, instruction: instruction, block: block,
                    function: function, blockIds: blockIds, opName: "branch"
                )
            case let branch as ConditionalBranch:
                for target in [branch.trueBranch, branch.falseBranch] {
                    verifyTarget(
                        target, instruction: instruction, block: block, function: function, entry: entry,
                        blockIds: blockIds
                    )
                }
                verifyBlockArguments(
                    branch.trueArguments, target: branch.trueBranch, instruction: instruction, block: block,
                    function: function, blockIds: blockIds, opName: "true branch"
                )
                verifyBlockArguments(
                    branch.falseArguments, target: branch.falseBranch, instruction: instruction, block: block,
                    function: function, blockIds: blockIds, opName: "false branch"
                )
            case let switchEnum as SwitchEnum:
                for enumCase in switchEnum.cases {
                    verifyTarget(
                        enumCase.block, instruction: instruction, block: block, function: function, entry: entry,
                        blockIds: blockIds
                    )
                    verifyBlockArguments(
                        enumCase.arguments, target: enumCase.block, instruction: instruction, block: block,
                        function: function, blockIds: blockIds, opName: "switch case"
                    )
                }
                if let defaultBlock = switchEnum.defaultBlock {
                    verifyTarget(
                        defaultBlock, instruction: instruction, block: block, function: function, entry: entry,
                        blockIds: blockIds
                    )
                }
            case let tryCall as TryCall:
                for target in [tryCall.successBlock, tryCall.errorBlock] {
                    verifyTarget(
                        target, instruction: instruction, block: block, function: function, entry: entry,
                        blockIds: blockIds
                    )
                }
            default:
                break
            }
        }

        private func verifyTarget(
            _ target: BasicBlock, instruction: Instruction, block: BasicBlock, function: Function,
            entry: BasicBlock, blockIds: Set<ObjectIdentifier>
        ) {
            let range = instructionRange(instruction, in: block, function: function)
            guard blockIds.contains(ObjectIdentifier(target)) else {
                record(
                    .Structure,
                    "branch target '\(target.name)' is not a basic block of function '\(function.name)'",
                    at: range
                )
                return
            }
            if target === entry {
                record(
                    .Structure,
                    "entry block '\(entry.name)' of function '\(function.name)' is targeted by a branch",
                    at: range
                )
            }
        }

        private func verifyBlockArguments(
            _ arguments: [Value], target: BasicBlock, instruction: Instruction, block: BasicBlock,
            function: Function, blockIds: Set<ObjectIdentifier>, opName: String
        ) {
            guard blockIds.contains(ObjectIdentifier(target)) else {
                return
            }
            let range = instructionRange(instruction, in: block, function: function)
            guard arguments.count == target.parameters.count else {
                record(
                    .Structure,
                    "\(opName) into block '\(target.name)' of function '\(function.name)' passes \(arguments.count) arguments but the block declares \(target.parameters.count) parameters",
                    at: range
                )
                return
            }
            for (index, argument) in arguments.enumerated()
                where argument.ty != target.parameters[index].ty
            {
                record(
                    .Structure,
                    "\(opName) argument \(index) into block '\(target.name)' of function '\(function.name)' has type \(typeName(argument.ty)) but the block parameter declares type \(typeName(target.parameters[index].ty))",
                    at: range
                )
            }
        }

        private func isTerminator(_ instruction: Instruction) -> Bool {
            instruction is Return || instruction is Branch || instruction is ConditionalBranch
                || instruction is SwitchEnum || instruction is Unreachable || instruction is Trap
                || instruction is TryCall
        }

        private func successorMap(
            of function: Function, blockIds: Set<ObjectIdentifier>
        ) -> [ObjectIdentifier: [ObjectIdentifier]] {
            var map: [ObjectIdentifier: [ObjectIdentifier]] = [:]
            for block in function.basicBlocks {
                map[ObjectIdentifier(block)] = successors(of: block)
                    .filter { blockIds.contains(ObjectIdentifier($0)) }
                    .map { ObjectIdentifier($0) }
            }
            return map
        }

        private func successors(of block: BasicBlock) -> [BasicBlock] {
            guard let last = block.instructions.last else {
                return []
            }
            return switch last {
            case let branch as Branch:
                [branch.target]
            case let branch as ConditionalBranch:
                [branch.trueBranch, branch.falseBranch]
            case let switchEnum as SwitchEnum:
                switchEnum.cases.map(\.block) + (switchEnum.defaultBlock.map { [$0] } ?? [])
            case let tryCall as TryCall:
                [tryCall.successBlock, tryCall.errorBlock]
            default:
                []
            }
        }

        private func computeDominators(
            entry: ObjectIdentifier, blocks: [ObjectIdentifier],
            successors: [ObjectIdentifier: [ObjectIdentifier]]
        ) -> [ObjectIdentifier: Set<ObjectIdentifier>] {
            var predecessors: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
            for block in blocks {
                for successor in successors[block] ?? [] {
                    predecessors[successor, default: []].insert(block)
                }
            }
            let allBlocks = Set(blocks)
            var dominators: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
            for block in blocks {
                dominators[block] = block == entry ? [entry] : allBlocks
            }
            var changed = true
            while changed {
                changed = false
                for block in blocks where block != entry {
                    let blockPredecessors = predecessors[block] ?? []
                    guard var computed = blockPredecessors.first.flatMap({ dominators[$0] }) else {
                        continue
                    }
                    for predecessor in blockPredecessors.dropFirst() {
                        guard let predecessorDominators = dominators[predecessor] else {
                            continue
                        }
                        computed.formIntersection(predecessorDominators)
                    }
                    computed.insert(block)
                    if computed != dominators[block] {
                        dominators[block] = computed
                        changed = true
                    }
                }
            }
            return dominators
        }

        private final class OwnershipState: Equatable {
            var balances: [ObjectIdentifier: Int?]
            var allocations: [ObjectIdentifier: Int?]
            var tokens: [ObjectIdentifier: Int?]
            var tokenOwners: [ObjectIdentifier: ObjectIdentifier?]

            init(
                balances: [ObjectIdentifier: Int?] = [:],
                allocations: [ObjectIdentifier: Int?] = [:],
                tokens: [ObjectIdentifier: Int?] = [:],
                tokenOwners: [ObjectIdentifier: ObjectIdentifier?] = [:]
            ) {
                self.balances = balances
                self.allocations = allocations
                self.tokens = tokens
                self.tokenOwners = tokenOwners
            }

            func copy() -> OwnershipState {
                OwnershipState(
                    balances: balances, allocations: allocations, tokens: tokens,
                    tokenOwners: tokenOwners
                )
            }

            static func == (lhs: OwnershipState, rhs: OwnershipState) -> Bool {
                lhs.balances == rhs.balances && lhs.allocations == rhs.allocations
                    && lhs.tokens == rhs.tokens && lhs.tokenOwners == rhs.tokenOwners
            }
        }

        private struct OwnershipFlow {
            let entries: [ObjectIdentifier: OwnershipState]
            let initial: OwnershipState
        }

        private func hasOwnershipInstructions(_ function: Function) -> Bool {
            function.basicBlocks.contains { block in
                block.instructions.contains { instruction in
                    instruction is Retain || instruction is Release || instruction is Destroy
                        || instruction is DeallocStack || instruction is DeallocHeap
                        || instruction is DeallocCell
                }
            }
        }

        private func isReferenceValue(_ id: Id.TIRTypeId) -> Bool {
            isReferenceType(id, visited: [])
        }

        private func isReferenceType(_ id: Id.TIRTypeId, visited: Set<Id.TIRTypeId>) -> Bool {
            guard !visited.contains(id), let ty = currentRegistry.types[id] else {
                return false
            }
            switch ty {
            case is TIRType.ClassType:
                return true
            case let pointer as TIRType.PointerType:
                return currentRegistry.types[pointer.pointee] is TIRType.ClassType
            case let structType as TIRType.StructType:
                let nested = visited.union([id])
                return structType.fields.contains { isReferenceType($0.type, visited: nested) }
            default:
                return false
            }
        }

        private func isClassReference(_ id: Id.TIRTypeId) -> Bool {
            guard let ty = currentRegistry.types[id] else {
                return false
            }
            if ty is TIRType.ClassType {
                return true
            }
            guard let pointer = ty as? TIRType.PointerType else {
                return false
            }
            return currentRegistry.types[pointer.pointee] is TIRType.ClassType
        }

        private func isTeardownValue(_ id: Id.TIRTypeId) -> Bool {
            if isClassReference(id) {
                return true
            }
            guard let structType = currentRegistry.types[id] as? TIRType.StructType else {
                return false
            }
            return structType.fields.contains { isReferenceValue($0.type) }
        }

        private struct CallableSignature {
            let parameters: [Id.TIRTypeId]
            let returnType: Id.TIRTypeId
            let isVariadic: Bool
            let parameterOwnership: [TIR.Ownership]
            let resultOwnership: TIR.Ownership
        }

        private func callableSignature(of ty: TIRType.TIRType) -> CallableSignature? {
            switch ty {
            case let function as TIRType.FunctionType:
                CallableSignature(
                    parameters: function.parameters,
                    returnType: function.returnType,
                    isVariadic: function.isVariadic,
                    parameterOwnership: function.parameterOwnership,
                    resultOwnership: function.resultOwnership
                )
            case let closure as TIRType.ClosureType:
                CallableSignature(
                    parameters: closure.parameters,
                    returnType: closure.returnType,
                    isVariadic: closure.isVariadic,
                    parameterOwnership: closure.parameterOwnership,
                    resultOwnership: closure.resultOwnership
                )
            default:
                nil
            }
        }

        private func callableSignature(for id: Id.TIRTypeId) -> CallableSignature? {
            guard let ty = currentRegistry.types[id] else {
                return nil
            }
            return callableSignature(of: ty)
        }

        private func seedOwnedResult(
            _ result: Value?, callee: Value, state: OwnershipState
        ) {
            guard let result, isReferenceValue(result.ty) else {
                return
            }
            guard let signature = callableSignature(for: callee.ty),
                  signature.resultOwnership == .Owned
            else {
                return
            }
            setBalance(result, to: 1, in: state)
        }

        private func consumeCallArguments(
            callee: Value, arguments: [Value], state: OwnershipState
        ) {
            guard let signature = callableSignature(for: callee.ty) else {
                return
            }
            for (index, argument) in arguments.enumerated() {
                guard index < signature.parameterOwnership.count,
                      signature.parameterOwnership[index] == .Owned,
                      isReferenceValue(argument.ty)
                else {
                    continue
                }
                adjustBalance(argument, by: -1, in: state)
            }
        }

        private func seedAllocatedResult(_ result: Value, state: OwnershipState) {
            guard isReferenceValue(result.ty) else {
                return
            }
            setBalance(result, to: 1, in: state)
        }

        private func ownershipValues(of function: Function) -> [Value] {
            var seen: Set<ObjectIdentifier> = []
            var values: [Value] = []
            func add(_ value: Value) {
                guard isReferenceValue(value.ty), seen.insert(ObjectIdentifier(value)).inserted else {
                    return
                }
                values.append(value)
            }
            for parameter in function.parameters {
                add(parameter)
            }
            for block in function.basicBlocks {
                for argument in block.parameters {
                    add(argument)
                }
                for instruction in block.instructions {
                    for result in TIR.Result.results(of: instruction) {
                        add(result)
                    }
                    for operand in TIR.Operands.operands(of: instruction) {
                        add(operand)
                    }
                    if let phi = instruction as? Phi {
                        for incoming in phi.incomings {
                            add(incoming.value)
                        }
                    }
                }
            }
            return values
        }

        private func allocationValues(of function: Function) -> [Value] {
            var values: [Value] = []
            for block in function.basicBlocks {
                for instruction in block.instructions {
                    guard let allocation = instruction as? AllocStack else {
                        continue
                    }
                    values.append(allocation.result)
                }
            }
            return values
        }

        private func verifyOwnership(
            _ function: Function, blocks: [BasicBlock],
            successors: [ObjectIdentifier: [ObjectIdentifier]]
        ) {
            if ownershipMode == .Strict {
                guard !function.isExtern else {
                    return
                }
            } else {
                guard hasOwnershipInstructions(function) else {
                    return
                }
            }
            let valueByIdentity = Dictionary(
                uniqueKeysWithValues: ownershipValues(of: function).map { (ObjectIdentifier($0), $0) }
            )
            let allocationByIdentity = Dictionary(
                uniqueKeysWithValues: allocationValues(of: function).map { (ObjectIdentifier($0), $0) }
            )
            let slots = ownershipMode == .Strict ? slotValues(of: function) : SlotTable()
            let slotByIdentity = slots.storages.keys.reduce(into: [ObjectIdentifier: Value]()) { result, key in
                result[key] = valueByIdentity[key]
            }
            guard !valueByIdentity.isEmpty || !allocationByIdentity.isEmpty else {
                return
            }
            let takenLoads = takenLoadResults(of: function, slots: slots)
            let flow = computeOwnershipFlow(
                blocks: blocks, successors: successors, phis: phisByBlock(of: function),
                referenceValues: Set(valueByIdentity.keys),
                allocationValues: Set(allocationByIdentity.keys),
                entryBalances: entryBalances(of: function),
                slots: slots, takenLoads: takenLoads
            )
            for block in blocks {
                let state = (flow.entries[ObjectIdentifier(block)] ?? flow.initial).copy()
                for instruction in block.instructions {
                    let site = Site(
                        function: function, block: block,
                        range: instructionRange(instruction, in: block, function: function)
                    )
                    if let ret = instruction as? Return {
                        verifyReturnOwnership(
                            ret, function: function, state: state,
                            valueByIdentity: valueByIdentity,
                            allocationByIdentity: allocationByIdentity, at: site
                        )
                    }
                    if let dealloc = instruction as? DeallocStack {
                        verifyDeallocStack(dealloc, allocationByIdentity: allocationByIdentity, at: site)
                    }
                    verifyConsumeTarget(instruction, state: state, at: site)
                    verifyTeardownKind(instruction, at: site)
                    verifySlotOwnership(
                        instruction, state: state, slots: slots,
                        slotByIdentity: slotByIdentity, at: site
                    )
                    if ownershipMode == .Strict {
                        verifyDeinitializerDischarge(
                            instruction, function: function, state: state, slots: slots, at: site
                        )
                    }
                    verifyOwnedArguments(instruction, state: state, at: site)
                    transferOwnership(
                        instruction, state: state, slots: slots, takenLoads: takenLoads
                    )
                }
            }
        }

        private func functionType(of function: Function) -> TIRType.FunctionType? {
            currentRegistry.types[function.ty] as? TIRType.FunctionType
        }

        private func parameterOwnership(of function: Function, at index: Int) -> Ownership {
            guard let ownership = functionType(of: function)?.parameterOwnership,
                  ownership.indices.contains(index)
            else {
                return .Owned
            }
            return ownership[index]
        }

        private func resultOwnership(of function: Function) -> Ownership {
            functionType(of: function)?.resultOwnership ?? .Owned
        }

        private func entryBalances(of function: Function) -> [ObjectIdentifier: Int?] {
            var balances: [ObjectIdentifier: Int?] = [:]
            for (index, parameter) in function.parameters.enumerated()
                where isReferenceValue(parameter.ty)
            {
                let owned = parameterOwnership(of: function, at: index) == .Owned
                balances[ObjectIdentifier(parameter)] = owned ? 1 : 0
            }
            return balances
        }

        private enum SlotStorage: Equatable {
            case Stack(ObjectIdentifier)
            case Field
            case Global
        }

        private struct SlotTable {
            var storages: [ObjectIdentifier: SlotStorage] = [:]
            var keys: [ObjectIdentifier: ObjectIdentifier] = [:]
            var addressBases: [ObjectIdentifier: (base: ObjectIdentifier, index: Int)] = [:]

            func key(of value: Value) -> ObjectIdentifier? {
                keys[ObjectIdentifier(value)]
            }

            func storage(of value: Value) -> SlotStorage? {
                guard let key = key(of: value) else {
                    return nil
                }
                return storages[key]
            }

            func addressChain(of key: ObjectIdentifier) -> (root: ObjectIdentifier, path: [Int])? {
                var indices: [Int] = []
                var current = key
                var visited: Set<ObjectIdentifier> = []
                while let step = addressBases[current], visited.insert(current).inserted {
                    indices.append(step.index)
                    current = step.base
                }
                guard !indices.isEmpty else {
                    return nil
                }
                return (current, indices.reversed())
            }
        }

        private func isSlot(_ id: Id.TIRTypeId) -> Bool {
            guard let pointee = addressPointee(of: id) else {
                return false
            }
            return containsReferenceLeaf(pointee)
        }

        private func addressPointee(of id: Id.TIRTypeId) -> Id.TIRTypeId? {
            switch currentRegistry.types[id] {
            case let address as TIRType.AddressType:
                address.pointee
            case let pointer as TIRType.PointerType:
                pointer.pointee
            default:
                nil
            }
        }

        private func containsReferenceLeaf(_ id: Id.TIRTypeId) -> Bool {
            containsReferenceLeaf(id, visited: [])
        }

        private func containsReferenceLeaf(
            _ id: Id.TIRTypeId, visited: Set<Id.TIRTypeId>
        ) -> Bool {
            guard !visited.contains(id), let ty = currentRegistry.types[id] else {
                return false
            }
            if isClassReference(id) {
                return true
            }
            let nested = visited.union([id])
            switch ty {
            case let structType as TIRType.StructType:
                return structType.fields.contains {
                    containsReferenceLeaf($0.type, visited: nested)
                }
            case let tupleType as TIRType.TupleType:
                return tupleType.elements.contains {
                    containsReferenceLeaf($0.type, visited: nested)
                }
            default:
                return false
            }
        }

        private func slotStorage(
            _ value: Value, slots: SlotTable
        ) -> SlotStorage? {
            slots.storage(of: value)
        }

        private func slotValues(of function: Function) -> SlotTable {
            var producers: [ObjectIdentifier: Instruction] = [:]
            var table = SlotTable()
            var globalKeys: [Id.TIRGlobalId: ObjectIdentifier] = [:]
            for block in function.basicBlocks {
                for instruction in block.instructions {
                    for result in TIR.Result.results(of: instruction) {
                        producers[ObjectIdentifier(result)] = instruction
                    }
                    for operand in TIR.Operands.operands(of: instruction) {
                        guard let address = operand as? GlobalAddr, isSlot(address.ty) else {
                            continue
                        }
                        let key = ObjectIdentifier(address)
                        if let canonical = globalKeys[address.globalId] {
                            table.keys[key] = canonical
                            continue
                        }
                        globalKeys[address.globalId] = key
                        table.keys[key] = key
                        table.storages[key] = .Global
                    }
                }
            }
            for block in function.basicBlocks {
                for instruction in block.instructions {
                    let candidate: Value? = switch instruction {
                    case let allocation as AllocStack: allocation.result
                    case let address as StructElementAddr: address.result
                    case let address as TupleElementAddr: address.result
                    case let address as ClassElementAddr: address.result
                    case let cell as ProjectCell: cell.result
                    default: nil
                    }
                    guard let candidate, isSlot(candidate.ty) else {
                        continue
                    }
                    let key = ObjectIdentifier(candidate)
                    table.keys[key] = key
                    switch instruction {
                    case let address as ClassElementAddr:
                        table.addressBases[key] = (
                            base: ObjectIdentifier(address.base), index: address.index
                        )
                    case let address as StructElementAddr:
                        table.addressBases[key] = (
                            base: ObjectIdentifier(address.base), index: address.index
                        )
                    case let address as TupleElementAddr:
                        table.addressBases[key] = (
                            base: ObjectIdentifier(address.base), index: address.index
                        )
                    default:
                        break
                    }
                    if let root = stackSlotRoot(of: candidate, producers: producers) {
                        table.storages[key] = .Stack(root)
                    } else {
                        table.storages[key] = .Field
                    }
                }
            }
            return table
        }

        private func stackSlotRoot(
            of value: Value, producers: [ObjectIdentifier: Instruction]
        ) -> ObjectIdentifier? {
            guard let producer = producers[ObjectIdentifier(value)] else {
                return nil
            }
            switch producer {
            case is AllocStack:
                return ObjectIdentifier(value)
            case let address as StructElementAddr:
                return stackSlotRoot(of: address.base, producers: producers)
            case let address as TupleElementAddr:
                return stackSlotRoot(of: address.base, producers: producers)
            default:
                return nil
            }
        }

        private func phisByBlock(of function: Function) -> [ObjectIdentifier: [Phi]] {
            var map: [ObjectIdentifier: [Phi]] = [:]
            for block in function.basicBlocks {
                let phis = block.instructions.compactMap { $0 as? Phi }
                if !phis.isEmpty {
                    map[ObjectIdentifier(block)] = phis
                }
            }
            return map
        }

        private func computeOwnershipFlow(
            blocks: [BasicBlock], successors: [ObjectIdentifier: [ObjectIdentifier]],
            phis: [ObjectIdentifier: [Phi]],
            referenceValues: Set<ObjectIdentifier>, allocationValues: Set<ObjectIdentifier>,
            entryBalances: [ObjectIdentifier: Int?],
            slots: SlotTable, takenLoads: Set<ObjectIdentifier>
        ) -> OwnershipFlow {
            var balances = Dictionary(uniqueKeysWithValues: referenceValues.map { ($0, 0 as Int?) })
            for (key, balance) in entryBalances {
                balances[key] = balance
            }
            var tokens: [ObjectIdentifier: Int?] = [:]
            var tokenOwners: [ObjectIdentifier: ObjectIdentifier?] = [:]
            for (key, storage) in slots.storages {
                switch storage {
                case .Stack:
                    tokens[key] = 0
                case .Field, .Global:
                    tokens[key] = 1
                }
                tokenOwners[key] = ObjectIdentifier?.none
            }
            let initial = OwnershipState(
                balances: balances,
                allocations: Dictionary(uniqueKeysWithValues: allocationValues.map { ($0, 0 as Int?) }),
                tokens: tokens,
                tokenOwners: tokenOwners
            )
            let entryKey = ObjectIdentifier(blocks[0])
            var entries: [ObjectIdentifier: OwnershipState] = [:]
            var exits: [ObjectIdentifier: OwnershipState] = [:]
            var changed = true
            while changed {
                changed = false
                for block in blocks {
                    let key = ObjectIdentifier(block)
                    let state: OwnershipState
                    if key == entryKey {
                        state = initial
                    } else if let propagated = entries[key] {
                        state = propagated
                    } else {
                        continue
                    }
                    let outgoing = state.copy()
                    for instruction in block.instructions {
                        transferOwnership(
                            instruction, state: outgoing, slots: slots, takenLoads: takenLoads
                        )
                    }
                    if exits[key] != outgoing {
                        exits[key] = outgoing
                        changed = true
                    }
                    guard let terminator = block.instructions.last else {
                        continue
                    }
                    for successor in successors[key] ?? [] where successor != entryKey {
                        let edgeState = outgoing.copy()
                        if let target = blocks.first(where: { ObjectIdentifier($0) == successor }) {
                            applyEdgeTransfers(
                                terminator, predecessor: block, to: target,
                                phis: phis[successor] ?? [], state: edgeState
                            )
                        }
                        let next = entries[successor].map { joinOwnership($0, edgeState) } ?? edgeState
                        if entries[successor] != next {
                            entries[successor] = next
                            changed = true
                        }
                    }
                }
            }
            return OwnershipFlow(entries: entries, initial: initial)
        }

        private func joinOwnership(_ lhs: OwnershipState, _ rhs: OwnershipState) -> OwnershipState {
            var balances: [ObjectIdentifier: Int?] = [:]
            for (key, value) in lhs.balances {
                balances[key] = value != nil && value == (rhs.balances[key] ?? nil) ? value : nil
            }
            var allocations: [ObjectIdentifier: Int?] = [:]
            for (key, value) in lhs.allocations {
                allocations[key] = value != nil && value == (rhs.allocations[key] ?? nil) ? value : nil
            }
            var tokens: [ObjectIdentifier: Int?] = [:]
            for (key, value) in lhs.tokens {
                tokens[key] = value != nil && value == (rhs.tokens[key] ?? nil) ? value : nil
            }
            var tokenOwners: [ObjectIdentifier: ObjectIdentifier?] = [:]
            for (key, value) in lhs.tokenOwners {
                let other = rhs.tokenOwners[key] ?? nil
                tokenOwners[key] = value != nil && value == other ? value : nil
            }
            return OwnershipState(
                balances: balances, allocations: allocations, tokens: tokens, tokenOwners: tokenOwners
            )
        }

        private func transferOwnership(
            _ instruction: Instruction, state: OwnershipState,
            slots: SlotTable, takenLoads: Set<ObjectIdentifier>
        ) {
            if !(instruction is Phi) {
                for result in TIR.Result.results(of: instruction) {
                    resetBalance(result, in: state)
                }
            }
            if let allocation = instruction as? AllocStack {
                state.allocations[ObjectIdentifier(allocation.result)] = 1
            }
            switch instruction {
            case let retain as Retain:
                adjustBalance(retain.value, by: 1, in: state)
            case let release as Release:
                adjustBalance(release.value, by: -1, in: state)
            case let destroy as Destroy where isTeardownValue(destroy.value.ty):
                adjustBalance(destroy.value, by: -1, in: state)
            case let store as Store:
                transferStore(store, state: state, slots: slots)
            case let load as Load:
                transferLoad(load, state: state, slots: slots, takenLoads: takenLoads)
            case let dealloc as DeallocStack:
                adjustAllocation(dealloc.value, by: -1, in: state)
            case let cast as Upcast:
                transferCast(cast.value, result: cast.result, state: state)
            case let cast as UncheckedRefCast:
                transferCast(cast.value, result: cast.result, state: state)
            case let cast as BitCast:
                transferCast(cast.value, result: cast.result, state: state)
            case let copy as Copy:
                if isReferenceValue(copy.value.ty) {
                    setBalance(copy.result, to: 1, in: state)
                }
            case let call as Call:
                consumeCallArguments(callee: call.callee, arguments: call.arguments, state: state)
                seedOwnedResult(call.result, callee: call.callee, state: state)
            case let call as TryCall:
                consumeCallArguments(callee: call.callee, arguments: call.arguments, state: state)
                seedOwnedResult(call.result, callee: call.callee, state: state)
            case let allocation as AllocHeap:
                seedAllocatedResult(allocation.result, state: state)
            case let allocation as AllocCell:
                seedAllocatedResult(allocation.result, state: state)
            default:
                break
            }
        }

        private func applyEdgeTransfers(
            _ terminator: Instruction, predecessor: BasicBlock, to target: BasicBlock,
            phis: [Phi], state: OwnershipState
        ) {
            switch terminator {
            case let branch as Branch where branch.target === target:
                transferBlockArguments(target, arguments: branch.arguments, state: state)
            case let conditional as ConditionalBranch:
                if conditional.trueBranch === target {
                    transferBlockArguments(
                        target, arguments: conditional.trueArguments, state: state
                    )
                }
                if conditional.falseBranch === target {
                    transferBlockArguments(
                        target, arguments: conditional.falseArguments, state: state
                    )
                }
            case let switchEnum as SwitchEnum:
                for enumCase in switchEnum.cases where enumCase.block === target {
                    transferBlockArguments(target, arguments: enumCase.arguments, state: state)
                }
                if let defaultBlock = switchEnum.defaultBlock, defaultBlock === target {
                    transferBlockArguments(target, arguments: [], state: state)
                }
            default:
                break
            }
            transferPhiIncomings(from: predecessor, phis: phis, state: state)
        }

        private func transferPhiIncomings(
            from predecessor: BasicBlock, phis: [Phi], state: OwnershipState
        ) {
            for phi in phis {
                guard let incoming = phi.incomings.first(where: { $0.block === predecessor }) else {
                    continue
                }
                if isReferenceValue(incoming.value.ty) {
                    adjustBalance(incoming.value, by: -1, in: state)
                }
                if isReferenceValue(phi.result.ty) {
                    setBalance(phi.result, to: 1, in: state)
                }
            }
        }

        private func transferBlockArguments(
            _ target: BasicBlock, arguments: [Value], state: OwnershipState
        ) {
            for (index, argument) in arguments.enumerated() {
                guard isReferenceValue(argument.ty) else {
                    continue
                }
                adjustBalance(argument, by: -1, in: state)
                guard index < target.parameters.count else {
                    continue
                }
                let parameter = target.parameters[index]
                guard isReferenceValue(parameter.ty) else {
                    continue
                }
                adjustBalance(parameter, by: 1, in: state)
            }
        }

        private func transferStore(
            _ store: Store, state: OwnershipState,
            slots: SlotTable
        ) {
            guard let key = slotStorage(store.ptr, slots: slots) != nil ? slots.key(of: store.ptr) : nil
            else {
                return
            }
            adjustBalance(store.value, by: -1, in: state)
            state.tokens[key] = 1
            state.tokenOwners[key] = ObjectIdentifier(store.value)
        }

        private func transferLoad(
            _ load: Load, state: OwnershipState,
            slots: SlotTable, takenLoads: Set<ObjectIdentifier>
        ) {
            guard let key = slots.key(of: load.ptr),
                  let storage = slotStorage(load.ptr, slots: slots)
            else {
                return
            }
            switch storage {
            case .Stack:
                switch state.tokens[key] ?? nil {
                case .some(1):
                    setBalance(load.result, to: 1, in: state)
                    state.tokens[key] = 0
                    state.tokenOwners[key] = ObjectIdentifier?.none
                case let .some(token):
                    setBalance(load.result, to: token, in: state)
                    state.tokens[key] = 0
                    state.tokenOwners[key] = ObjectIdentifier?.none
                case .none:
                    setBalance(load.result, to: nil, in: state)
                    state.tokens[key] = 0
                    state.tokenOwners[key] = ObjectIdentifier?.none
                }
            case .Field, .Global:
                if takenLoads.contains(ObjectIdentifier(load.result)),
                   (state.tokens[key] ?? nil) == 1
                {
                    setBalance(load.result, to: 1, in: state)
                    state.tokens[key] = 0
                    state.tokenOwners[key] = ObjectIdentifier?.none
                } else {
                    setBalance(load.result, to: 0, in: state)
                }
            }
        }

        private func transferCast(_ value: Value, result: Value, state: OwnershipState) {
            guard isReferenceValue(value.ty) else {
                return
            }
            let key = ObjectIdentifier(value)
            guard let current = state.balances[key] else {
                return
            }
            state.balances[key] = 0
            setBalance(result, to: current, in: state)
        }

        private struct BlockPoint: Hashable {
            let block: ObjectIdentifier
            let index: Int
        }

        private func takenLoadResults(
            of function: Function, slots: SlotTable
        ) -> Set<ObjectIdentifier> {
            guard !slots.storages.isEmpty else {
                return []
            }
            let edges = aliasEdges(of: function)
            let blockByIdentity = Dictionary(
                uniqueKeysWithValues: function.basicBlocks.map { (ObjectIdentifier($0), $0) }
            )
            var taken: Set<ObjectIdentifier> = []
            for block in function.basicBlocks {
                for (index, instruction) in block.instructions.enumerated() {
                    guard let load = instruction as? Load, isReferenceValue(load.result.ty) else {
                        continue
                    }
                    switch slotStorage(load.ptr, slots: slots) {
                    case .Field, .Global:
                        break
                    default:
                        continue
                    }
                    let family = valueFamily(of: load.result, edges: edges)
                    guard hasDischarge(of: family, in: function),
                          !hasBorrowUse(of: family, in: function),
                          dischargesOnEveryPath(
                              from: block, index: index + 1, family: family,
                              blockByIdentity: blockByIdentity
                          )
                    else {
                        continue
                    }
                    taken.insert(ObjectIdentifier(load.result))
                }
            }
            return taken
        }

        private func aliasEdges(of function: Function) -> [ObjectIdentifier: Set<ObjectIdentifier>] {
            var edges: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
            func connect(_ lhs: Value, _ rhs: Value) {
                guard isReferenceValue(lhs.ty), isReferenceValue(rhs.ty) else {
                    return
                }
                edges[ObjectIdentifier(lhs), default: []].insert(ObjectIdentifier(rhs))
                edges[ObjectIdentifier(rhs), default: []].insert(ObjectIdentifier(lhs))
            }
            for block in function.basicBlocks {
                for instruction in block.instructions {
                    switch instruction {
                    case let cast as Upcast:
                        connect(cast.value, cast.result)
                    case let cast as UncheckedRefCast:
                        connect(cast.value, cast.result)
                    case let cast as BitCast:
                        connect(cast.value, cast.result)
                    case let branch as Branch:
                        for (index, argument) in branch.arguments.enumerated()
                            where index < branch.target.parameters.count
                        {
                            connect(argument, branch.target.parameters[index])
                        }
                    case let branch as ConditionalBranch:
                        for (index, argument) in branch.trueArguments.enumerated()
                            where index < branch.trueBranch.parameters.count
                        {
                            connect(argument, branch.trueBranch.parameters[index])
                        }
                        for (index, argument) in branch.falseArguments.enumerated()
                            where index < branch.falseBranch.parameters.count
                        {
                            connect(argument, branch.falseBranch.parameters[index])
                        }
                    case let switchEnum as SwitchEnum:
                        for enumCase in switchEnum.cases {
                            for (index, argument) in enumCase.arguments.enumerated()
                                where index < enumCase.block.parameters.count
                            {
                                connect(argument, enumCase.block.parameters[index])
                            }
                        }
                    case let phi as Phi:
                        for incoming in phi.incomings {
                            connect(incoming.value, phi.result)
                        }
                    default:
                        break
                    }
                }
            }
            return edges
        }

        private func valueFamily(
            of value: Value, edges: [ObjectIdentifier: Set<ObjectIdentifier>]
        ) -> Set<ObjectIdentifier> {
            let start = ObjectIdentifier(value)
            var family: Set<ObjectIdentifier> = [start]
            var worklist = [start]
            while let current = worklist.popLast() {
                for neighbor in edges[current] ?? [] where family.insert(neighbor).inserted {
                    worklist.append(neighbor)
                }
            }
            return family
        }

        private func hasDischarge(
            of family: Set<ObjectIdentifier>, in function: Function
        ) -> Bool {
            function.basicBlocks.contains { block in
                block.instructions.contains { instruction in
                    discharges(instruction, family: family)
                }
            }
        }

        private func hasBorrowUse(
            of family: Set<ObjectIdentifier>, in function: Function
        ) -> Bool {
            for block in function.basicBlocks {
                for instruction in block.instructions {
                    switch instruction {
                    case let retain as Retain where family.contains(ObjectIdentifier(retain.value)):
                        return true
                    case let copy as Copy where family.contains(ObjectIdentifier(copy.value)):
                        return true
                    case let store as Store where family.contains(ObjectIdentifier(store.value)):
                        return true
                    case let ret as Return:
                        if let value = ret.value, family.contains(ObjectIdentifier(value)) {
                            return true
                        }
                    case let call as Call:
                        if passesOwnedArgument(call.callee, call.arguments, family: family) {
                            return true
                        }
                    case let call as TryCall:
                        if passesOwnedArgument(call.callee, call.arguments, family: family) {
                            return true
                        }
                    default:
                        break
                    }
                }
            }
            return false
        }

        private func passesOwnedArgument(
            _ callee: Value, _ arguments: [Value], family: Set<ObjectIdentifier>
        ) -> Bool {
            guard let signature = callableSignature(for: callee.ty) else {
                return false
            }
            for (index, argument) in arguments.enumerated() {
                guard index < signature.parameterOwnership.count,
                      signature.parameterOwnership[index] == .Owned,
                      family.contains(ObjectIdentifier(argument))
                else {
                    continue
                }
                return true
            }
            return false
        }

        private func discharges(_ instruction: Instruction, family: Set<ObjectIdentifier>) -> Bool {
            switch instruction {
            case let release as Release:
                family.contains(ObjectIdentifier(release.value))
            case let destroy as Destroy:
                family.contains(ObjectIdentifier(destroy.value))
            default:
                false
            }
        }

        private func dischargesOnEveryPath(
            from block: BasicBlock, index: Int, family: Set<ObjectIdentifier>,
            blockByIdentity: [ObjectIdentifier: BasicBlock]
        ) -> Bool {
            var visited: Set<BlockPoint> = []
            var worklist = [BlockPoint(block: ObjectIdentifier(block), index: index)]
            while let point = worklist.popLast() {
                guard visited.insert(point).inserted, let current = blockByIdentity[point.block]
                else {
                    continue
                }
                var position = point.index
                while position < current.instructions.count {
                    let instruction = current.instructions[position]
                    if discharges(instruction, family: family) {
                        break
                    }
                    guard isTerminator(instruction) else {
                        position += 1
                        continue
                    }
                    switch instruction {
                    case is Return, is Unreachable, is Trap:
                        return false
                    case let branch as Branch:
                        worklist.append(BlockPoint(block: ObjectIdentifier(branch.target), index: 0))
                    case let branch as ConditionalBranch:
                        worklist.append(
                            BlockPoint(block: ObjectIdentifier(branch.trueBranch), index: 0)
                        )
                        worklist.append(
                            BlockPoint(block: ObjectIdentifier(branch.falseBranch), index: 0)
                        )
                    case let switchEnum as SwitchEnum:
                        for enumCase in switchEnum.cases {
                            worklist.append(
                                BlockPoint(block: ObjectIdentifier(enumCase.block), index: 0)
                            )
                        }
                        if let defaultBlock = switchEnum.defaultBlock {
                            worklist.append(
                                BlockPoint(block: ObjectIdentifier(defaultBlock), index: 0)
                            )
                        }
                    case let tryCall as TryCall:
                        worklist.append(
                            BlockPoint(block: ObjectIdentifier(tryCall.successBlock), index: 0)
                        )
                        worklist.append(
                            BlockPoint(block: ObjectIdentifier(tryCall.errorBlock), index: 0)
                        )
                    default:
                        break
                    }
                    break
                }
            }
            return true
        }

        private func setBalance(_ value: Value, to balance: Int?, in state: OwnershipState) {
            let key = ObjectIdentifier(value)
            guard state.balances.index(forKey: key) != nil else {
                return
            }
            state.balances[key] = balance
        }

        private func resetBalance(_ value: Value, in state: OwnershipState) {
            let key = ObjectIdentifier(value)
            guard state.balances.index(forKey: key) != nil else {
                return
            }
            state.balances[key] = 0
        }

        private func adjustBalance(_ value: Value, by delta: Int, in state: OwnershipState) {
            let key = ObjectIdentifier(value)
            guard let current = state.balances[key], let balance = current else {
                return
            }
            state.balances[key] = balance + delta
        }

        private func adjustAllocation(_ value: Value, by delta: Int, in state: OwnershipState) {
            let key = ObjectIdentifier(value)
            guard let current = state.allocations[key], let count = current else {
                return
            }
            state.allocations[key] = count + delta
        }

        private func verifyReturnOwnership(
            _ instruction: Return, function: Function, state: OwnershipState,
            valueByIdentity: [ObjectIdentifier: Value],
            allocationByIdentity: [ObjectIdentifier: Value], at site: Site
        ) {
            let returned = instruction.value.map { ObjectIdentifier($0) }
            let transfersOwnedResult = resultOwnership(of: function) == .Owned
            let balances = state.balances.sorted {
                (valueByIdentity[$0.key]?.name ?? "") < (valueByIdentity[$1.key]?.name ?? "")
            }
            for (key, balance) in balances {
                if key == returned, transfersOwnedResult {
                    guard balance != 1 else {
                        continue
                    }
                    guard let value = valueByIdentity[key] else {
                        continue
                    }
                    let text = balance.map { String($0) } ?? "unknown"
                    record(
                        .Ownership,
                        "reference value '\(value.name)' in \(site.location) is transferred as an owned result with retain/release balance \(text), expected 1",
                        at: site.range
                    )
                } else {
                    guard balance != 0 else {
                        continue
                    }
                    guard let value = valueByIdentity[key] else {
                        continue
                    }
                    let text = balance.map { String($0) } ?? "unknown"
                    record(
                        .Ownership,
                        "reference value '\(value.name)' in \(site.location) has retain/release balance \(text) at the return, expected 0",
                        at: site.range
                    )
                }
            }
            let allocations = state.allocations.sorted {
                (allocationByIdentity[$0.key]?.name ?? "") < (allocationByIdentity[$1.key]?.name ?? "")
            }
            for (key, count) in allocations where count != 0 {
                guard let value = allocationByIdentity[key] else {
                    continue
                }
                let text = if count == nil {
                    "is not deallocated exactly once on every path to this return"
                } else if count == 1 {
                    "is not deallocated on every path to this return"
                } else {
                    "is deallocated more than once on some path to this return"
                }
                record(
                    .Ownership,
                    "stack allocation '\(value.name)' in \(site.location) \(text)",
                    at: site.range
                )
            }
        }

        private func verifyConsumeTarget(
            _ instruction: Instruction, state: OwnershipState, at site: Site
        ) {
            let value: Value?
            let opName: String
            switch instruction {
            case let release as Release:
                value = release.value
                opName = "release"
            case let destroy as Destroy:
                value = destroy.value
                opName = "destroy"
            default:
                return
            }
            guard let value else {
                return
            }
            let key = ObjectIdentifier(value)
            guard state.balances.index(forKey: key) != nil, let balance = state.balances[key] ?? nil
            else {
                return
            }
            guard balance <= 0 else {
                return
            }
            record(
                .Ownership,
                "reference value '\(value.name)' in \(site.location) is consumed by \(opName) with no owned instance left (retain/release balance \(balance))",
                at: site.range
            )
        }

        private func verifyOwnedArguments(
            _ instruction: Instruction, state: OwnershipState, at site: Site
        ) {
            let callee: Value
            let arguments: [Value]
            switch instruction {
            case let call as Call:
                callee = call.callee
                arguments = call.arguments
            case let call as TryCall:
                callee = call.callee
                arguments = call.arguments
            default:
                return
            }
            guard let signature = callableSignature(for: callee.ty) else {
                return
            }
            for (index, argument) in arguments.enumerated() {
                guard index < signature.parameterOwnership.count,
                      signature.parameterOwnership[index] == .Owned,
                      isReferenceValue(argument.ty)
                else {
                    continue
                }
                let balance = state.balances[ObjectIdentifier(argument)] ?? nil
                guard balance != 1 else {
                    continue
                }
                let text = balance.map { String($0) } ?? "unknown"
                record(
                    .Ownership,
                    "reference value '\(argument.name)' in \(site.location) is passed as an owned argument to '\(callee.name)' with retain/release balance \(text), expected 1",
                    at: site.range
                )
            }
        }

        private func verifyDeinitializerDischarge(
            _ instruction: Instruction, function: Function, state: OwnershipState,
            slots: SlotTable, at site: Site
        ) {
            let isExit = instruction is Return || instruction is Unreachable || instruction is Trap
            guard isExit, let classType = deinitializerClass(of: function) else {
                return
            }
            guard let selfParameter = function.parameters.first else {
                return
            }
            let selfKey = ObjectIdentifier(selfParameter)
            let startIndex = inheritedFieldCount(of: classType)
            for (index, field) in classType.fields.enumerated() where index >= startIndex {
                for path in referenceLeafPaths(of: field.type, path: [index], visited: []) {
                    let matching = slots.keys.keys.compactMap { valueKey -> ObjectIdentifier? in
                        guard let chain = slots.addressChain(of: valueKey),
                              chain.root == selfKey, chain.path == path
                        else {
                            return nil
                        }
                        return slots.keys[valueKey]
                    }
                    let name = fieldPathName(path)
                    guard !matching.isEmpty else {
                        record(
                            .Ownership,
                            "deinitializer '\(function.name)' in \(site.location) does not discharge reference field \(name) of '\(classType.displayText)'",
                            at: site.range
                        )
                        continue
                    }
                    let holding = matching.filter { (state.tokens[$0] ?? nil) != 0 }
                    for _ in holding {
                        record(
                            .Ownership,
                            "deinitializer '\(function.name)' in \(site.location) still holds a reference in field \(name) of '\(classType.displayText)' at this exit",
                            at: site.range
                        )
                    }
                }
            }
        }

        private func fieldPathName(_ path: [Int]) -> String {
            "#" + path.map(String.init).joined(separator: ".")
        }

        private func referenceLeafPaths(
            of id: Id.TIRTypeId, path: [Int], visited: Set<Id.TIRTypeId>
        ) -> [[Int]] {
            guard !visited.contains(id) else {
                return []
            }
            if isClassReference(id) {
                return [path]
            }
            let nested = visited.union([id])
            switch currentRegistry.types[id] {
            case let structType as TIRType.StructType:
                return structType.fields.enumerated().flatMap { index, field in
                    referenceLeafPaths(of: field.type, path: path + [index], visited: nested)
                }
            case let tupleType as TIRType.TupleType:
                return tupleType.elements.enumerated().flatMap { index, element in
                    referenceLeafPaths(of: element.type, path: path + [index], visited: nested)
                }
            default:
                return []
            }
        }

        private func classMetadata(of classType: TIRType.ClassType) -> TIR.MetadataRecord? {
            if let record = currentRegistry.metadatas.values.first(where: {
                $0.typeId == classType.id
            }) {
                return record
            }
            return currentRegistry.metadatas.values.first {
                $0.typeId == nil && $0.name == classType.displayText
            }
        }

        private func classTypeForMetadata(_ record: TIR.MetadataRecord) -> TIRType.ClassType? {
            guard let typeId = record.typeId else {
                return nil
            }
            return currentRegistry.types[typeId] as? TIRType.ClassType
        }

        private func deinitializerClass(of function: Function) -> TIRType.ClassType? {
            guard function.parameters.count == 1,
                  let pointeeId = (
                      currentRegistry.types[function.parameters[0].ty]
                          as? TIRType.PointerType
                  )?.pointee,
                  let classType = currentRegistry.types[pointeeId] as? TIRType.ClassType,
                  let record = classMetadata(of: classType),
                  record.vtable.first?.function == function.id
            else {
                return nil
            }
            return classType
        }

        private func inheritedFieldCount(of classType: TIRType.ClassType) -> Int {
            inheritedFieldCount(of: classType, visited: [])
        }

        private func inheritedFieldCount(
            of classType: TIRType.ClassType, visited: Set<Id.TIRTypeId>
        ) -> Int {
            guard !visited.contains(classType.id),
                  let record = classMetadata(of: classType),
                  let superclassId = record.superclass,
                  let superclassRecord = currentRegistry.metadatas[superclassId],
                  let superclassType = classTypeForMetadata(superclassRecord)
            else {
                return 0
            }
            return superclassType.fields.count + inheritedFieldCount(
                of: superclassType, visited: visited.union([classType.id])
            )
        }

        private func classReference(of id: Id.TIRTypeId) -> TIRType.ClassType? {
            if let classType = currentRegistry.types[id] as? TIRType.ClassType {
                return classType
            }
            guard let pointee = addressPointee(of: id) else {
                return nil
            }
            return currentRegistry.types[pointee] as? TIRType.ClassType
        }

        private func classNeedsTeardown(
            _ classType: TIRType.ClassType, visited: Set<Id.TIRTypeId>
        ) -> Bool {
            guard !visited.contains(classType.id) else {
                return false
            }
            let record = classMetadata(of: classType)
            if record?.hasRealDeinitializer == true {
                return true
            }
            if classType.fields.contains(where: { isReferenceValue($0.type) }) {
                return true
            }
            guard let superclassId = record?.superclass,
                  let superclassRecord = currentRegistry.metadatas[superclassId],
                  let superclassType = classTypeForMetadata(superclassRecord)
            else {
                return false
            }
            return classNeedsTeardown(
                superclassType, visited: visited.union([classType.id])
            )
        }

        private func verifyTeardownKind(_ instruction: Instruction, at site: Site) {
            let value: Value
            let destroyed: Bool
            switch instruction {
            case let release as Release:
                value = release.value
                destroyed = false
            case let destroy as Destroy:
                value = destroy.value
                destroyed = true
            default:
                return
            }
            guard let classType = classReference(of: value.ty),
                  let metadata = classMetadata(of: classType),
                  let metadataClass = classTypeForMetadata(metadata)
            else {
                return
            }
            let needsTeardown = classNeedsTeardown(metadataClass, visited: [])
            if destroyed, !needsTeardown {
                record(
                    .Ownership,
                    "reference value '\(value.name)' in \(site.location) is destroyed but '\(metadata.name)' has no real deinitializer, release is required",
                    at: site.range
                )
            } else if !destroyed, needsTeardown {
                record(
                    .Ownership,
                    "reference value '\(value.name)' in \(site.location) is released but '\(metadata.name)' has a real deinitializer, destroy is required",
                    at: site.range
                )
            }
        }

        private func verifySlotOwnership(
            _ instruction: Instruction, state: OwnershipState,
            slots: SlotTable,
            slotByIdentity: [ObjectIdentifier: Value], at site: Site
        ) {
            switch instruction {
            case let store as Store:
                guard let key = slots.key(of: store.ptr), (state.tokens[key] ?? nil) != 0 else {
                    return
                }
                record(
                    .Ownership,
                    "store of '\(store.value.name)' into slot '\(store.ptr.name)' in \(site.location) overwrites a reference held by the slot that is not discharged first",
                    at: site.range
                )
            case let dealloc as DeallocStack:
                verifySlotDischarge(
                    dealloc, state: state, slots: slots, slotByIdentity: slotByIdentity, at: site
                )
            case let destroy as Destroy where isTeardownValue(destroy.value.ty):
                verifyDestroyAgainstSlots(
                    destroy, state: state, slotByIdentity: slotByIdentity, at: site
                )
            default:
                break
            }
        }

        private func verifySlotDischarge(
            _ instruction: DeallocStack, state: OwnershipState,
            slots: SlotTable,
            slotByIdentity: [ObjectIdentifier: Value], at site: Site
        ) {
            let root = ObjectIdentifier(instruction.value)
            let holding = slots.storages.keys.filter { key in
                guard case let .Stack(slotRoot)? = slots.storages[key], slotRoot == root else {
                    return false
                }
                return (state.tokens[key] ?? nil) != 0
            }.sorted { (slotByIdentity[$0]?.name ?? "") < (slotByIdentity[$1]?.name ?? "") }
            for key in holding {
                let name = slotByIdentity[key]?.name ?? "slot"
                record(
                    .Ownership,
                    "stack slot '\(name)' in \(site.location) still holds a reference that is not discharged before this deallocstack",
                    at: site.range
                )
            }
        }

        private func verifyDestroyAgainstSlots(
            _ instruction: Destroy, state: OwnershipState,
            slotByIdentity: [ObjectIdentifier: Value], at site: Site
        ) {
            let owned = ObjectIdentifier(instruction.value)
            let holding = state.tokens.keys.filter { key in
                (state.tokens[key] ?? nil) != 0 && (state.tokenOwners[key] ?? nil) == owned
            }.sorted { (slotByIdentity[$0]?.name ?? "") < (slotByIdentity[$1]?.name ?? "") }
            for key in holding {
                let name = slotByIdentity[key]?.name ?? "slot"
                record(
                    .Ownership,
                    "reference value '\(instruction.value.name)' in \(site.location) is destroyed while slot '\(name)' still holds a reference to it",
                    at: site.range
                )
            }
        }

        private func verifyDeallocStack(
            _ instruction: DeallocStack, allocationByIdentity: [ObjectIdentifier: Value], at site: Site
        ) {
            guard allocationByIdentity[ObjectIdentifier(instruction.value)] == nil else {
                return
            }
            record(
                .Ownership,
                "deallocstack operand '\(instruction.value.name)' in \(site.location) is not a stack allocation of function '\(site.function.name)'",
                at: site.range
            )
        }

        private func verifyOperand(
            _ value: Value, useBlock: BasicBlock, useIndex: Int,
            definitions: [ObjectIdentifier: Definition],
            dominators: [ObjectIdentifier: Set<ObjectIdentifier>], at site: Site
        ) {
            resolveType(value.ty, at: site.range)
            verifyValueReferences(value, at: site.range)
            let identifier = ObjectIdentifier(value)
            if let definition = definitions[identifier] {
                if definition.block === useBlock {
                    if definition.index >= useIndex {
                        record(
                            .Dominance,
                            "value '\(value.name)' is used in \(site.location) before its definition",
                            at: site.range
                        )
                    }
                } else if let blockDominators = dominators[ObjectIdentifier(useBlock)],
                          !blockDominators.contains(ObjectIdentifier(definition.block))
                {
                    record(
                        .Dominance,
                        "value '\(value.name)' defined in block '\(definition.block.name)' does not dominate its use in \(site.location)",
                        at: site.range
                    )
                }
                return
            }
            if isConstantLike(value) {
                return
            }
            guard value is InstructionResult else {
                return
            }
            if unresolvedValueIds.insert(identifier).inserted {
                record(
                    .Dominance,
                    "value '\(value.name)' used in \(site.location) has no definition",
                    at: site.range
                )
            }
        }

        private func isConstantLike(_ value: Value) -> Bool {
            value is Literal || value is Parameter || value is BlockArgument || value is FunctionRef
                || value is GlobalAddr
        }

        private func verifyValueReferences(_ value: Value, at range: SourceRange) {
            switch value {
            case let reference as FunctionRef:
                if currentRegistry.functions[reference.functionId] == nil {
                    record(
                        .Registry,
                        "function reference '\(reference.name)' uses function id \(reference.functionId.id) that is not in registry.functions",
                        at: range
                    )
                }
            case let address as GlobalAddr:
                if currentRegistry.globals[address.globalId] == nil {
                    record(
                        .Registry,
                        "global address '\(address.name)' uses global id \(address.globalId.id) that is not in registry.globals",
                        at: range
                    )
                }
            default:
                break
            }
        }

        private func verifyInstruction(_ instruction: Instruction, at site: Site) {
            switch instruction {
            case let i as Return:
                verifyReturn(i, at: site)
            case let i as ConditionalBranch:
                if !isBoolI1(i.condition.ty) {
                    record(
                        .TypeConsistency,
                        "conditional branch condition in \(site.location) has type \(typeName(i.condition.ty)), expected bool",
                        at: site.range
                    )
                }
            case let i as UnaryArith:
                if i.result.ty != i.operand.ty {
                    record(
                        .TypeConsistency,
                        "\(i.op.rawValue) result in \(site.location) has type \(typeName(i.result.ty)) but its operand has type \(typeName(i.operand.ty))",
                        at: site.range
                    )
                }
            case let i as BinaryArith:
                if i.lhs.ty != i.rhs.ty {
                    record(
                        .TypeConsistency,
                        "\(i.op.rawValue) operands in \(site.location) have type \(typeName(i.lhs.ty)) and \(typeName(i.rhs.ty))",
                        at: site.range
                    )
                }
                if i.op.isCompare, !isBoolI1(i.result.ty) {
                    record(
                        .TypeConsistency,
                        "comparison result in \(site.location) has type \(typeName(i.result.ty)), expected bool",
                        at: site.range
                    )
                }
            case let i as Load:
                verifyLoad(i, at: site)
            case let i as Store:
                verifyStore(i, at: site)
            case let i as Call:
                verifyCallee(i.callee, arguments: i.arguments, result: i.result, opName: "call", at: site)
            case let i as TryCall:
                verifyCallee(i.callee, arguments: i.arguments, result: i.result, opName: "try call", at: site)
            case let i as AllocStack:
                verifyAllocation(
                    result: i.result, allocatedType: i.allocatedType,
                    opName: "stack alloc", at: site
                )
            case let i as AllocHeap:
                resolveType(i.allocatedType, at: site.range)
                let ty = resolveType(i.result.ty, at: site.range)!
                if ty.id != i.allocatedType {
                    record(
                        .TypeConsistency,
                        "heap alloc result in \(site.location) is type \(typeName(ty.id)) but the instruction allocates type \(typeName(i.allocatedType))",
                        at: site.range
                    )
                }
            case let i as AllocCell:
                verifyAllocation(
                    result: i.result, allocatedType: i.allocatedType,
                    opName: "cell alloc", at: site
                )
            case let i as AddressToPointer:
                verifyAddressConversion(
                    i.address,
                    result: i.result,
                    toAddress: false,
                    opName: "address to pointer",
                    at: site
                )
            case let i as PointerToAddress:
                verifyAddressConversion(
                    i.pointer,
                    result: i.result,
                    toAddress: true,
                    opName: "pointer to address",
                    at: site
                )
            case let i as Upcast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "upcast", at: site)
            case let i as UncheckedRefCast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "unchecked ref cast", at: site)
            case let i as NumericCast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "numeric cast", at: site)
            case let i as BitCast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "bit cast", at: site)
            case let i as StructElementAddr:
                verifyElementAddress(
                    base: i.base, result: i.result, index: i.index,
                    opName: "struct element address", at: site
                )
            case let i as TupleElementAddr:
                verifyElementAddress(
                    base: i.base, result: i.result, index: i.index,
                    opName: "tuple element address", at: site
                )
            case let i as ClassElementAddr:
                verifyElementAddress(
                    base: i.base, result: i.result, index: i.index,
                    opName: "class element address", at: site
                )
            case let i as EnumValue:
                verifyEnumValue(i, at: site)
            case let i as ExtractPayload:
                verifyExtractPayload(i, at: site)
            case let i as SizeOf:
                resolveType(i.sizedType, at: site.range)
            case let i as TypeMetadataConstant:
                resolveType(i.type, at: site.range)
                verifyMetadata(i.metadata, opName: "type metadata constant", at: site)
            case let i as VirtualMethod:
                verifyMetadata(i.metadata, opName: "virtual method", at: site)
            case let i as WitnessMethod:
                verifyWitness(i.witness, opName: "witness method", at: site)
            case let i as BuildExistential:
                for witness in i.witnesses {
                    verifyWitness(witness, opName: "build existential", at: site)
                }
            case let i as OpaqueWitnessMethod:
                verifyProtocol(i.protocolId, opName: "opaque witness method", at: site)
            default:
                break
            }
        }

        private func verifyReturn(_ instruction: Return, at site: Site) {
            let returnType = site.function.returnType
            guard let ty = resolveType(returnType, at: site.range) else {
                return
            }
            if ty is TIRType.VoidType {
                if let value = instruction.value, !isVoidType(value.ty) {
                    record(
                        .TypeConsistency,
                        "function '\(site.function.name)' returns void but its return instruction in \(site.location) yields type \(typeName(value.ty))",
                        at: site.range
                    )
                }
                return
            }
            guard let value = instruction.value else {
                record(
                    .TypeConsistency,
                    "function '\(site.function.name)' returns type \(typeName(returnType)) but its return instruction in \(site.location) has no value",
                    at: site.range
                )
                return
            }
            if value.ty != returnType {
                record(
                    .TypeConsistency,
                    "function '\(site.function.name)' returns type \(typeName(returnType)) but its return instruction in \(site.location) yields type \(typeName(value.ty))",
                    at: site.range
                )
            }
        }

        private func verifyLoad(_ instruction: Load, at site: Site) {
            guard let pointee = pointeeType(of: instruction.ptr.ty, opName: "load pointer", at: site) else {
                return
            }
            verifyAddressOperand(
                instruction.ptr, opName: "load pointer", allowClassReference: true, at: site
            )
            if instruction.result.ty != pointee {
                record(
                    .TypeConsistency,
                    "load result in \(site.location) has type \(typeName(instruction.result.ty)) but the pointer points to type \(typeName(pointee))",
                    at: site.range
                )
            }
        }

        private func verifyStore(_ instruction: Store, at site: Site) {
            guard let pointee = pointeeType(of: instruction.ptr.ty, opName: "store pointer", at: site) else {
                return
            }
            verifyAddressOperand(
                instruction.ptr, opName: "store pointer", allowClassReference: false, at: site
            )
            if instruction.value.ty != pointee {
                record(
                    .TypeConsistency,
                    "store value in \(site.location) has type \(typeName(instruction.value.ty)) but the pointer points to type \(typeName(pointee))",
                    at: site.range
                )
            }
        }

        private func pointeeType(of id: Id.TIRTypeId, opName: String, at site: Site) -> Id.TIRTypeId? {
            guard let ty = resolveType(id, at: site.range) else {
                return nil
            }
            switch ty {
            case let address as TIRType.AddressType:
                return address.pointee
            case let pointer as TIRType.PointerType:
                return pointer.pointee
            default:
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) has type \(typeName(id)), expected an address or pointer type",
                    at: site.range
                )
                return nil
            }
        }

        private func verifyAddressOperand(
            _ value: Value, opName: String, allowClassReference: Bool, at site: Site
        ) {
            guard let ty = resolveType(value.ty, at: site.range) else {
                return
            }
            switch ty {
            case is TIRType.AddressType:
                return
            case let pointer as TIRType.PointerType:
                if allowClassReference, currentRegistry.types[pointer.pointee] is TIRType.ClassType {
                    return
                }
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) has pointer type \(typeName(value.ty)), expected an address type",
                    at: site.range
                )
            default:
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) has type \(typeName(value.ty)), expected an address type",
                    at: site.range
                )
            }
        }

        private func verifyCallee(
            _ callee: Value, arguments: [Value], result: Value?, opName: String, at site: Site
        ) {
            guard let ty = resolveType(callee.ty, at: site.range) else {
                return
            }
            guard let signature = callableSignature(of: ty) else {
                record(
                    .TypeConsistency,
                    "\(opName) callee in \(site.location) has type \(typeName(callee.ty)), expected a function type",
                    at: site.range
                )
                return
            }
            verifyCallArguments(arguments, signature: signature, opName: opName, at: site)
            if isVoidType(signature.returnType) {
                if result != nil {
                    record(
                        .TypeConsistency,
                        "\(opName) in \(site.location) calls a function returning void but produces a result",
                        at: site.range
                    )
                }
            } else if let result {
                if result.ty != signature.returnType {
                    record(
                        .TypeConsistency,
                        "\(opName) result in \(site.location) has type \(typeName(result.ty)) but the callee returns type \(typeName(signature.returnType))",
                        at: site.range
                    )
                }
            } else {
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) calls a function returning type \(typeName(signature.returnType)) but produces no result",
                    at: site.range
                )
            }
        }

        private func verifyCallArguments(
            _ arguments: [Value], signature: CallableSignature, opName: String, at site: Site
        ) {
            let parameters = signature.parameters
            if signature.isVariadic {
                if arguments.count < parameters.count {
                    record(
                        .TypeConsistency,
                        "\(opName) in \(site.location) passes \(arguments.count) arguments but the callee declares \(parameters.count) parameters",
                        at: site.range
                    )
                    return
                }
            } else if arguments.count != parameters.count {
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) passes \(arguments.count) arguments but the callee declares \(parameters.count) parameters",
                    at: site.range
                )
                return
            }
            for (index, argument) in arguments.enumerated() where index < parameters.count {
                if argument.ty != parameters[index] {
                    record(
                        .TypeConsistency,
                        "\(opName) argument \(index) in \(site.location) has type \(typeName(argument.ty)) but the callee declares type \(typeName(parameters[index]))",
                        at: site.range
                    )
                }
            }
        }

        private func verifyAllocation(
            result: Value, allocatedType: Id.TIRTypeId, opName: String, at site: Site
        ) {
            resolveType(allocatedType, at: site.range)
            guard let ty = resolveType(result.ty, at: site.range) else {
                return
            }
            let pointee = (ty as? TIRType.AddressType)?.pointee
            guard let pointee else {
                record(
                    .TypeConsistency,
                    "\(opName) result in \(site.location) has type \(typeName(result.ty)), expected an address of type \(typeName(allocatedType))",
                    at: site.range
                )
                return
            }
            if pointee != allocatedType {
                record(
                    .TypeConsistency,
                    "\(opName) result in \(site.location) points to type \(typeName(pointee)) but the instruction allocates type \(typeName(allocatedType))",
                    at: site.range
                )
            }
        }

        private func verifyCast(result: Value, targetType: Id.TIRTypeId, opName: String, at site: Site) {
            resolveType(targetType, at: site.range)
            if result.ty != targetType {
                record(
                    .TypeConsistency,
                    "\(opName) result in \(site.location) has type \(typeName(result.ty)) but the instruction casts to type \(typeName(targetType))",
                    at: site.range
                )
            }
        }

        private func verifyAddressConversion(
            _ operand: Value, result: Value, toAddress: Bool, opName: String, at site: Site
        ) {
            guard let operandType = resolveType(operand.ty, at: site.range) else {
                return
            }
            let pointee: Id.TIRTypeId? = if toAddress {
                (operandType as? TIRType.PointerType)?.pointee
            } else {
                (operandType as? TIRType.AddressType)?.pointee
            }
            guard let pointee else {
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) operates on type \(typeName(operand.ty)), expected "
                        + (toAddress ? "a pointer type" : "an address type"),
                    at: site.range
                )
                return
            }
            let expected = if toAddress {
                currentRegistry.addressType(pointee: pointee).id
            } else {
                currentRegistry.pointerType(pointee: pointee).id
            }
            if result.ty != expected {
                record(
                    .TypeConsistency,
                    "\(opName) result in \(site.location) has type \(typeName(result.ty)) but the conversion produces type \(typeName(expected))",
                    at: site.range
                )
            }
        }

        private func verifyElementAddress(
            base: Value, result: Value, index: Int, opName: String, at site: Site
        ) {
            guard let baseType = resolveType(base.ty, at: site.range) else {
                return
            }
            let aggregateId = addressPointee(of: base.ty) ?? base.ty
            guard let aggregate = resolveType(aggregateId, at: site.range) else {
                return
            }
            let elementCount: Int? = switch aggregate {
            case let structType as TIRType.StructType:
                structType.fields.count
            case let classType as TIRType.ClassType:
                classType.fields.count
            case let tupleType as TIRType.TupleType:
                tupleType.elements.count
            default:
                nil
            }
            guard let elementCount else {
                record(
                    .TypeConsistency,
                    "\(opName) base in \(site.location) has type \(typeName(base.ty)), expected an address or pointer to a struct, class or tuple",
                    at: site.range
                )
                return
            }
            let elementType: Id.TIRTypeId? = switch aggregate {
            case let structType as TIRType.StructType where structType.fields.indices.contains(index):
                structType.fields[index].type
            case let classType as TIRType.ClassType where classType.fields.indices.contains(index):
                classType.fields[index].type
            case let tupleType as TIRType.TupleType where tupleType.elements.indices.contains(index):
                tupleType.elements[index].type
            default:
                nil
            }
            if let elementType {
                let expected = currentRegistry.addressType(pointee: elementType).id
                if result.ty != expected {
                    record(
                        .TypeConsistency,
                        "\(opName) result in \(site.location) has type \(typeName(result.ty)) but the element has type \(typeName(elementType))",
                        at: site.range
                    )
                }
            }
            if index < 0 || index >= elementCount {
                record(
                    .TypeConsistency,
                    "\(opName) index \(index) in \(site.location) is out of range for type \(typeName(aggregateId)) with \(elementCount) elements",
                    at: site.range
                )
            }
        }

        private func verifyEnumValue(_ instruction: EnumValue, at site: Site) {
            guard let ty = resolveType(instruction.result.ty, at: site.range) else {
                return
            }
            guard let enumType = ty as? TIRType.EnumType else {
                record(
                    .TypeConsistency,
                    "enum value in \(site.location) has type \(typeName(instruction.result.ty)), expected an enum type",
                    at: site.range
                )
                return
            }
            verifyCaseIndex(instruction.caseIndex, of: enumType, opName: "enum value", at: site)
        }

        private func verifyExtractPayload(_ instruction: ExtractPayload, at site: Site) {
            guard let ty = resolveType(instruction.value.ty, at: site.range) else {
                return
            }
            guard let enumType = ty as? TIRType.EnumType else {
                record(
                    .TypeConsistency,
                    "extract payload in \(site.location) reads type \(typeName(instruction.value.ty)), expected an enum type",
                    at: site.range
                )
                return
            }
            verifyCaseIndex(instruction.caseIndex, of: enumType, opName: "extract payload", at: site)
        }

        private func verifyCaseIndex(
            _ index: Int, of enumType: TIRType.EnumType, opName: String, at site: Site
        ) {
            if index < 0 || index >= enumType.cases.count {
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) uses case index \(index) but enum '\(enumType.name)' declares \(enumType.cases.count) cases",
                    at: site.range
                )
            }
        }

        private func verifyMetadata(_ id: Id.TIRMetadataId, opName: String, at site: Site) {
            if currentRegistry.metadatas[id] == nil {
                record(
                    .Registry,
                    "\(opName) in \(site.location) references metadata id \(id.id) that is not in registry.metadatas",
                    at: site.range
                )
            }
        }

        private func verifyWitness(_ id: Id.TIRWitnessId, opName: String, at site: Site) {
            if currentRegistry.witnesses[id] == nil {
                record(
                    .Registry,
                    "\(opName) in \(site.location) references witness id \(id.id) that is not in registry.witnesses",
                    at: site.range
                )
            }
        }

        private func verifyProtocol(_ id: Id.TIRProtocolId, opName: String, at site: Site) {
            if currentRegistry.protocols[id] == nil {
                record(
                    .Registry,
                    "\(opName) in \(site.location) references protocol id \(id.id) that is not in registry.protocols",
                    at: site.range
                )
            }
        }

        private func verifyRegistry() {
            let registry = currentRegistry
            let range = TIR.unknownSourceRange
            for (id, ty) in registry.types {
                if ty.id != id {
                    record(
                        .Registry,
                        "registry.types[\(id.id)] holds a type declaring id \(ty.id)",
                        at: range
                    )
                } else if registry.types[ty.id] !== ty {
                    record(
                        .Registry,
                        "the type declaring id \(ty.id.id) is not stored under that id",
                        at: range
                    )
                }
                verifyTypeReferences(of: ty, at: range)
            }
            for (_, metadata) in registry.metadatas {
                if let superclass = metadata.superclass, registry.metadatas[superclass] == nil {
                    record(
                        .Registry,
                        "metadata '\(metadata.name)' has superclass id \(superclass.id) that is not in registry.metadatas",
                        at: range
                    )
                }
                for protocolId in metadata.conformedProtocols where registry.protocols[protocolId] == nil {
                    record(
                        .Registry,
                        "metadata '\(metadata.name)' conforms to protocol id \(protocolId.id) that is not in registry.protocols",
                        at: range
                    )
                }
                for entry in metadata.vtable {
                    resolveType(entry.signature, at: range)
                    if registry.functions[entry.function] == nil {
                        record(
                            .Registry,
                            "vtable entry '\(entry.name)' of metadata '\(metadata.name)' references function id \(entry.function.id) that is not in registry.functions",
                            at: range
                        )
                    }
                }
            }
            for (_, witness) in registry.witnesses {
                if registry.protocols[witness.protocolId] == nil {
                    record(
                        .Registry,
                        "witness \(witness.id.id) references protocol id \(witness.protocolId.id) that is not in registry.protocols",
                        at: range
                    )
                }
                resolveType(witness.concreteType, at: range)
                for entry in witness.entries where registry.functions[entry.function] == nil {
                    record(
                        .Registry,
                        "witness \(witness.id.id) entry '\(entry.name)' references function id \(entry.function.id) that is not in registry.functions",
                        at: range
                    )
                }
                let valueWitnessFunctions = [
                    witness.valueWitness.initFunction, witness.valueWitness.copy,
                    witness.valueWitness.destroy,
                ].compactMap { $0 }
                for function in valueWitnessFunctions where registry.functions[function] == nil {
                    record(
                        .Registry,
                        "witness \(witness.id.id) value witness references function id \(function.id) that is not in registry.functions",
                        at: range
                    )
                }
            }
        }

        private func verifyTypeReferences(of ty: TIRType.TIRType, at range: SourceRange) {
            switch ty {
            case let pointer as TIRType.PointerType:
                resolveType(pointer.pointee, at: range)
            case let address as TIRType.AddressType:
                resolveType(address.pointee, at: range)
            case let function as TIRType.FunctionType:
                for parameter in function.parameters {
                    resolveType(parameter, at: range)
                }
                resolveType(function.returnType, at: range)
            case let closure as TIRType.ClosureType:
                for parameter in closure.parameters {
                    resolveType(parameter, at: range)
                }
                resolveType(closure.returnType, at: range)
            case let structType as TIRType.StructType:
                for field in structType.fields {
                    resolveType(field.type, at: range)
                }
            case let classType as TIRType.ClassType:
                for field in classType.fields {
                    resolveType(field.type, at: range)
                }
            case let enumType as TIRType.EnumType:
                for enumCase in enumType.cases {
                    for associatedType in enumCase.associatedTypes {
                        resolveType(associatedType, at: range)
                    }
                }
            case let tupleType as TIRType.TupleType:
                for element in tupleType.elements {
                    resolveType(element.type, at: range)
                }
            case let existential as TIRType.ExistentialType:
                for protocolId in existential.protocols where currentRegistry.protocols[protocolId] == nil {
                    record(
                        .Registry,
                        "existential type \(typeName(existential.id)) references protocol id \(protocolId.id) that is not in registry.protocols",
                        at: range
                    )
                }
            default:
                break
            }
        }
    }
}
