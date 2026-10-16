import SwiftBetterDiagnostic

public extension TIR {
    final class Verifier {
        public enum FailureKind: String, Sendable, Equatable {
            case Structure
            case Dominance
            case Registry
            case TypeConsistency = "type"

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

        private let context: Context
        private var registry: Registry?
        private var failures: [Failure] = []
        private var failureKeys: Set<String> = []
        private var unresolvedTypeIds: Set<Id.TIRTypeId> = []
        private var unresolvedValueIds: Set<ObjectIdentifier> = []

        public init(context: Context) {
            self.context = context
        }

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
                    for value in results(of: instruction) {
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
                    for operand in operands(of: instruction) {
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
                verifyAllocation(result: i.result, allocatedType: i.allocatedType, opName: "alloca", at: site)
            case let i as AllocHeap:
                verifyAllocation(result: i.result, allocatedType: i.allocatedType, opName: "heap alloc", at: site)
            case let i as AllocCell:
                verifyAllocation(result: i.result, allocatedType: i.allocatedType, opName: "cell alloc", at: site)
            case let i as Upcast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "upcast", at: site)
            case let i as UncheckedRefCast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "unchecked ref cast", at: site)
            case let i as NumericCast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "numeric cast", at: site)
            case let i as BitCast:
                verifyCast(result: i.result, targetType: i.targetType, opName: "bit cast", at: site)
            case let i as StructElementAddr:
                verifyElementAddress(base: i.base, index: i.index, opName: "struct element address", at: site)
            case let i as TupleElementAddr:
                verifyElementAddress(base: i.base, index: i.index, opName: "tuple element address", at: site)
            case let i as ClassElementAddr:
                verifyElementAddress(base: i.base, index: i.index, opName: "class element address", at: site)
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
            guard let pointer = ty as? TIRType.PointerType else {
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) has type \(typeName(id)), expected a pointer type",
                    at: site.range
                )
                return nil
            }
            return pointer.pointee
        }

        private func verifyCallee(
            _ callee: Value, arguments: [Value], result: Value?, opName: String, at site: Site
        ) {
            guard let ty = resolveType(callee.ty, at: site.range) else {
                return
            }
            guard let functionType = ty as? TIRType.FunctionType else {
                record(
                    .TypeConsistency,
                    "\(opName) callee in \(site.location) has type \(typeName(callee.ty)), expected a function type",
                    at: site.range
                )
                return
            }
            verifyCallArguments(arguments, functionType: functionType, opName: opName, at: site)
            if isVoidType(functionType.returnType) {
                if result != nil {
                    record(
                        .TypeConsistency,
                        "\(opName) in \(site.location) calls a function returning void but produces a result",
                        at: site.range
                    )
                }
            } else if let result {
                if result.ty != functionType.returnType {
                    record(
                        .TypeConsistency,
                        "\(opName) result in \(site.location) has type \(typeName(result.ty)) but the callee returns type \(typeName(functionType.returnType))",
                        at: site.range
                    )
                }
            } else {
                record(
                    .TypeConsistency,
                    "\(opName) in \(site.location) calls a function returning type \(typeName(functionType.returnType)) but produces no result",
                    at: site.range
                )
            }
        }

        private func verifyCallArguments(
            _ arguments: [Value], functionType: TIRType.FunctionType, opName: String, at site: Site
        ) {
            let parameters = functionType.parameters
            if functionType.isVariadic {
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
            guard let pointer = ty as? TIRType.PointerType else {
                record(
                    .TypeConsistency,
                    "\(opName) result in \(site.location) has type \(typeName(result.ty)), expected a pointer to type \(typeName(allocatedType))",
                    at: site.range
                )
                return
            }
            if pointer.pointee != allocatedType {
                record(
                    .TypeConsistency,
                    "\(opName) result in \(site.location) points to type \(typeName(pointer.pointee)) but the instruction allocates type \(typeName(allocatedType))",
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

        private func verifyElementAddress(base: Value, index: Int, opName: String, at site: Site) {
            guard let baseType = resolveType(base.ty, at: site.range) else {
                return
            }
            let aggregateId = (baseType as? TIRType.PointerType)?.pointee ?? base.ty
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
                    "\(opName) base in \(site.location) has type \(typeName(base.ty)), expected a pointer to a struct, class or tuple",
                    at: site.range
                )
                return
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
            case let function as TIRType.FunctionType:
                for parameter in function.parameters {
                    resolveType(parameter, at: range)
                }
                resolveType(function.returnType, at: range)
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

        private func results(of instruction: Instruction) -> [Value] {
            switch instruction {
            case let i as Phi:
                [i.result]
            case let i as ExtractPayload:
                [i.result]
            case let i as UnaryArith:
                [i.result]
            case let i as BinaryArith:
                [i.result]
            case let i as AllocStack:
                [i.result]
            case let i as AllocHeap:
                [i.result]
            case let i as AllocCell:
                [i.result]
            case let i as Load:
                [i.result]
            case let i as StructElementAddr:
                [i.result]
            case let i as TupleElementAddr:
                [i.result]
            case let i as ClassElementAddr:
                [i.result]
            case let i as ProjectCell:
                [i.result]
            case let i as StructValue:
                [i.result]
            case let i as TupleValue:
                [i.result]
            case let i as EnumValue:
                [i.result]
            case let i as Call:
                i.result.map { [$0] } ?? []
            case let i as TryCall:
                i.result.map { [$0] } ?? []
            case let i as Closure:
                [i.result]
            case let i as VirtualMethod:
                [i.result]
            case let i as Upcast:
                [i.result]
            case let i as UncheckedRefCast:
                [i.result]
            case let i as NumericCast:
                [i.result]
            case let i as BitCast:
                [i.result]
            case let i as SizeOf:
                [i.result]
            case let i as TypeMetadata:
                [i.result]
            case let i as TypeMetadataConstant:
                [i.result]
            case let i as IsInstance:
                [i.result]
            case let i as Superclass:
                [i.result]
            case let i as Copy:
                [i.result]
            case let i as BuildExistential:
                [i.result]
            case let i as OpenExistential:
                [i.result]
            case let i as WitnessMethod:
                [i.result]
            case let i as OpaqueWitnessMethod:
                [i.result]
            case let i as ExistentialCopy:
                [i.result]
            default:
                []
            }
        }

        private func operands(of instruction: Instruction) -> [Value] {
            switch instruction {
            case let i as Return:
                i.value.map { [$0] } ?? []
            case let i as Branch:
                i.arguments
            case let i as ConditionalBranch:
                [i.condition] + i.trueArguments + i.falseArguments
            case let i as SwitchEnum:
                [i.value] + i.cases.flatMap(\.arguments)
            case let i as ExtractPayload:
                [i.value]
            case let i as UnaryArith:
                [i.operand]
            case let i as BinaryArith:
                [i.lhs, i.rhs]
            case let i as DeallocStack:
                [i.value]
            case let i as DeallocHeap:
                [i.value]
            case let i as DeallocCell:
                [i.value]
            case let i as Load:
                [i.ptr]
            case let i as Store:
                [i.value, i.ptr]
            case let i as StructElementAddr:
                [i.base]
            case let i as TupleElementAddr:
                [i.base]
            case let i as ClassElementAddr:
                [i.base]
            case let i as ProjectCell:
                [i.cell]
            case let i as StructValue:
                i.fields
            case let i as TupleValue:
                i.elements
            case let i as EnumValue:
                i.payload.map { [$0] } ?? []
            case let i as Call:
                [i.callee] + i.arguments
            case let i as TryCall:
                [i.callee] + i.arguments + (i.errorCell.map { [$0] } ?? [])
            case let i as Closure:
                [i.function] + i.captures
            case let i as VirtualMethod:
                [i.selfValue]
            case let i as Upcast:
                [i.value]
            case let i as UncheckedRefCast:
                [i.value]
            case let i as NumericCast:
                [i.value]
            case let i as BitCast:
                [i.value]
            case let i as TypeMetadata:
                [i.value]
            case let i as IsInstance:
                [i.metadata, i.target]
            case let i as Superclass:
                [i.metadata]
            case let i as Retain:
                [i.value]
            case let i as Release:
                [i.value]
            case let i as Copy:
                [i.value]
            case let i as Destroy:
                [i.value]
            case let i as InlineAsm:
                i.operands
            case let i as BuildExistential:
                [i.value]
            case let i as OpenExistential:
                [i.container]
            case let i as OpaqueWitnessMethod:
                [i.container]
            case let i as ExistentialCopy:
                [i.container]
            case let i as ExistentialDestroy:
                [i.container]
            default:
                []
            }
        }
    }
}
