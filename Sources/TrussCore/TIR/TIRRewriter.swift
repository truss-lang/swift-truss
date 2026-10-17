import SwiftAbstract

extension TIR {
    open class Rewriter: Visitor {
        private var valueMap: [ObjectIdentifier: TIR.Value] = [:]
        private var blockMap: [ObjectIdentifier: BasicBlock] = [:]
        private var functionMap: [ObjectIdentifier: Function] = [:]
        private var typeMap: [Id.TIRTypeId: Id.TIRTypeId] = [:]
        private var module: Module?
        private var function: Function?
        private var block: BasicBlock?

        public override init() {}

        @discardableResult
        public func rewrite(module: Module) -> Module {
            let moduleGlobals = module.globals
            let functions = module.functions
            self.module = module
            defer {
                self.module = nil
                function = nil
                block = nil
            }
            for index in moduleGlobals.indices {
                let global = rewrite(global: moduleGlobals[index])
                guard global !== moduleGlobals[index] else {
                    continue
                }
                module.globals[index] = global
                module.registry.globals[global.id] = global
            }
            for index in functions.indices {
                let rewritten = rewrite(function: functions[index])
                guard rewritten !== functions[index] else {
                    continue
                }
                module.functions[index] = rewritten
                module.registry.functions[rewritten.id] = rewritten
            }
            return module
        }

        @discardableResult
        public func rewrite(function: Function) -> Function {
            self.function = function
            defer { self.function = nil }
            let blocks = function.basicBlocks
            let ty = rewriteFunctionSignature(function)
            var rebuilt: Function? = ty == function.ty ? nil : makeFunction(function, ty: ty)
            var changed = rebuilt != nil
            for block in blocks {
                let parameters = rewrite(blockArguments: block.parameters)
                guard !allIdentical(block.parameters, parameters) else {
                    continue
                }
                if rebuilt == nil {
                    rebuilt = makeFunction(function, ty: ty)
                }
                guard let owner = rebuilt else {
                    continue
                }
                let shell = BasicBlock(function: owner, name: block.name, parameters: parameters)
                shell.sourceRange = block.sourceRange
                blockMap[ObjectIdentifier(block)] = shell
            }
            if rebuilt != nil {
                changed = true
            }
            var rewrittenBlocks: [BasicBlock] = []
            rewrittenBlocks.reserveCapacity(blocks.count)
            for block in blocks {
                self.block = block
                let instructions = rewrite(instructions: block.instructions)
                if !allIdentical(block.instructions, instructions) {
                    changed = true
                }
                let target = blockMap[ObjectIdentifier(block)] ?? block
                target.instructions = instructions
                rewrittenBlocks.append(target)
            }
            block = nil
            guard changed else {
                return function
            }
            if rebuilt == nil {
                rebuilt = makeFunction(function, ty: ty)
            }
            guard let rebuilt else {
                return function
            }
            rebuilt.basicBlocks = rewrittenBlocks
            for block in rewrittenBlocks {
                block.function = rebuilt
            }
            functionMap[ObjectIdentifier(function)] = rebuilt
            return rebuilt
        }

        @discardableResult
        public func rewrite(block: BasicBlock) -> BasicBlock {
            self.block = block
            defer { self.block = nil }
            let parameters = rewrite(blockArguments: block.parameters)
            let target: BasicBlock
            if let shell = blockMap[ObjectIdentifier(block)] {
                target = shell
            } else if !allIdentical(block.parameters, parameters), let owner = block.function ?? function {
                let rebuilt = BasicBlock(function: owner, name: block.name, parameters: parameters)
                rebuilt.sourceRange = block.sourceRange
                blockMap[ObjectIdentifier(block)] = rebuilt
                target = rebuilt
            } else {
                target = block
            }
            target.instructions = rewrite(instructions: block.instructions)
            return target
        }

        @discardableResult
        public func rewrite(blockArguments: [BlockArgument]) -> [BlockArgument] {
            blockArguments.map { argument in
                rewrite(value: argument) as? BlockArgument ?? argument
            }
        }

        open func rewrite(instructions: [Instruction]) -> [Instruction] {
            instructions.map { rewrite(instruction: $0) }
        }

        @discardableResult
        public func rewrite(instruction: Instruction) -> Instruction {
            visit(instruction) as? Instruction ?? instruction
        }

        @discardableResult
        public func rewrite(value: Value) -> Value {
            visit(value) as? Value ?? value
        }

        @discardableResult
        public func rewrite(global: GlobalVariable) -> GlobalVariable {
            visitGlobal(global) ?? global
        }

        public override func visit(
            _ instruction: Instruction, additional: Any? = nil
        ) -> Any? {
            remapInstruction(instruction)
        }

        public override func visit(_ value: Value, additional: Any? = nil) -> Any? {
            replacement(for: value) ?? valueMap[ObjectIdentifier(value)] ?? value
        }

        open func replacement(for instruction: Instruction) -> Instruction? {
            nil
        }

        open func replacement(for value: Value) -> Value? {
            nil
        }

        open func rewriteFunctionSignature(_ function: Function) -> Id.TIRTypeId {
            function.ty
        }

        open func visitGlobal(_ global: GlobalVariable) -> GlobalVariable? {
            nil
        }

        public func value(for value: Value) -> Value {
            valueMap[ObjectIdentifier(value)] ?? value
        }

        public func block(for block: BasicBlock) -> BasicBlock {
            blockMap[ObjectIdentifier(block)] ?? block
        }

        public func function(for function: Function) -> Function {
            functionMap[ObjectIdentifier(function)] ?? function
        }

        public func map(value old: Value, to new: Value) {
            valueMap[ObjectIdentifier(old)] = new
        }

        public func map(block old: BasicBlock, to new: BasicBlock) {
            blockMap[ObjectIdentifier(old)] = new
        }

        public func map(function old: Function, to new: Function) {
            functionMap[ObjectIdentifier(old)] = new
        }

        public func map(type old: Id.TIRTypeId, to new: Id.TIRTypeId) {
            typeMap[old] = new
        }

        public func remap(type id: Id.TIRTypeId) -> Id.TIRTypeId {
            typeMap[id] ?? id
        }

        public func remap(value: Value) -> Value {
            valueMap[ObjectIdentifier(value)] ?? value
        }

        public func remap(values: [Value]) -> [Value] {
            values.map { valueMap[ObjectIdentifier($0)] ?? $0 }
        }

        private var registry: TIR.Registry {
            if let registry = function?.module?.registry ?? module?.registry {
                return registry
            }
            fatalError("TIR.Rewriter must be rewriting a module before its operands can be rewritten")
        }

        private func makeFunction(_ function: Function, ty: Id.TIRTypeId) -> Function? {
            guard let owner = function.module ?? module else {
                return nil
            }
            let rebuilt = Function(
                module: owner, id: function.id, name: function.name, ty: ty,
                parameters: function.parameters, returnType: function.returnType,
                isVariadic: function.isVariadic, isExtern: function.isExtern,
                callingConvention: function.callingConvention
            )
            rebuilt.sourceRange = function.sourceRange
            rebuilt.nextValueIndex = function.nextValueIndex
            return rebuilt
        }

        private func operands(of instruction: TIR.Instruction) -> [TIR.Value] {
            if let phi = instruction as? Phi {
                return phi.incomings.map(\.value)
            }
            return TIR.Operands.operands(of: instruction)
        }

        private func referencesRebuiltBlock(_ instruction: TIR.Instruction) -> Bool {
            guard !blockMap.isEmpty else {
                return false
            }
            switch instruction {
            case let i as Branch:
                return blockMap[ObjectIdentifier(i.target)] != nil
            case let i as ConditionalBranch:
                return blockMap[ObjectIdentifier(i.trueBranch)] != nil
                    || blockMap[ObjectIdentifier(i.falseBranch)] != nil
            case let i as SwitchEnum:
                return i.cases.contains { blockMap[ObjectIdentifier($0.block)] != nil }
                    || i.defaultBlock.map { blockMap[ObjectIdentifier($0)] != nil } ?? false
            case let i as Phi:
                return i.incomings.contains { blockMap[ObjectIdentifier($0.block)] != nil }
            case let i as TryCall:
                return blockMap[ObjectIdentifier(i.successBlock)] != nil
                    || blockMap[ObjectIdentifier(i.errorBlock)] != nil
            default:
                return false
            }
        }

        private func remapInstruction(_ instruction: TIR.Instruction) -> TIR.Instruction {
            let results = TIR.Result.results(of: instruction)
            let current = operands(of: instruction)
            let operands = current.map { valueMap[ObjectIdentifier($0)] ?? $0 }
            let operandsChanged = operands.count != current.count
                || zip(current, operands).contains { $0 !== $1 }
            let rewritten = operandsChanged || !typeMap.isEmpty
                || referencesRebuiltBlock(instruction)
                ? rebuildInstruction(instruction, operands: operands)
                : instruction
            let final = replacement(for: rewritten) ?? rewritten
            guard final !== instruction else {
                return final
            }
            let replacements = TIR.Result.results(of: final)
            guard replacements.count == results.count else {
                return final
            }
            for (old, new) in zip(results, replacements) {
                valueMap[ObjectIdentifier(old)] = new
            }
            return final
        }

        private func allIdentical(_ lhs: [BlockArgument], _ rhs: [BlockArgument]) -> Bool {
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
        }

        private func allIdentical(_ lhs: [TIR.Instruction], _ rhs: [TIR.Instruction]) -> Bool {
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
        }

        private func rebuildInstruction(
            _ instruction: TIR.Instruction, operands: [Value]
        ) -> TIR.Instruction {
            switch instruction {
            case is Return:
                return Return(value: operands.first)
            case let i as Branch:
                return Branch(target: block(for: i.target), arguments: operands)
            case let i as ConditionalBranch:
                return ConditionalBranch(
                    condition: operands[0], trueBranch: block(for: i.trueBranch),
                    falseBranch: block(for: i.falseBranch),
                    trueArguments: Array(operands.dropFirst().prefix(i.trueArguments.count)),
                    falseArguments: Array(operands.dropFirst(1 + i.trueArguments.count))
                )
            case is Unreachable:
                return instruction
            case let i as Phi:
                let incomings = i.incomings.enumerated().map { index, incoming in
                    Phi.Incoming(value: operands[index], block: block(for: incoming.block))
                }
                return Phi(incomings: incomings, ty: remap(type: i.result.ty), name: resultName(of: i.result))
            case let i as SwitchEnum:
                var index = 1
                let cases = i.cases.map { enumCase in
                    let arguments = Array(operands.dropFirst(index).prefix(enumCase.arguments.count))
                    index += enumCase.arguments.count
                    return SwitchEnum.Case(
                        tag: enumCase.tag, block: block(for: enumCase.block), arguments: arguments
                    )
                }
                let defaultBlock = i.defaultBlock.map { block(for: $0) }
                return SwitchEnum(value: operands[0], cases: cases, defaultBlock: defaultBlock)
            case let i as ExtractPayload:
                return ExtractPayload(
                    value: operands[0], caseIndex: i.caseIndex, ty: remap(type: i.result.ty),
                    name: resultName(of: i.result)
                )
            case let i as UnaryArith:
                return UnaryArith(
                    op: i.op, operand: operands[0], ty: remap(type: i.result.ty), name: resultName(of: i.result)
                )
            case let i as BinaryArith:
                return BinaryArith(
                    op: i.op, lhs: operands[0], rhs: operands[1], ty: remap(type: i.result.ty),
                    name: resultName(of: i.result)
                )
            case let i as AllocStack:
                return AllocStack(
                    registry: registry, allocatedType: remap(type: i.allocatedType), name: resultName(of: i.result)
                )
            case is DeallocStack:
                return DeallocStack(value: operands[0])
            case let i as AllocHeap:
                return AllocHeap(
                    registry: registry, allocatedType: remap(type: i.allocatedType), name: resultName(of: i.result)
                )
            case is DeallocHeap:
                return DeallocHeap(value: operands[0])
            case let i as AllocCell:
                return AllocCell(
                    registry: registry, allocatedType: remap(type: i.allocatedType), name: resultName(of: i.result)
                )
            case is DeallocCell:
                return DeallocCell(value: operands[0])
            case let i as Load:
                return Load(ptr: operands[0], ty: remap(type: i.result.ty), name: resultName(of: i.result))
            case is Store:
                return Store(value: operands[0], ptr: operands[1])
            case let i as SizeOf:
                return SizeOf(
                    registry: registry, sizedType: remap(type: i.sizedType), name: resultName(of: i.result)
                )
            case let i as StructElementAddr:
                return StructElementAddr(
                    registry: registry, base: operands[0], index: i.index,
                    name: resultName(of: i.result)
                )
            case let i as TupleElementAddr:
                return TupleElementAddr(
                    registry: registry, base: operands[0], index: i.index,
                    name: resultName(of: i.result)
                )
            case let i as ClassElementAddr:
                return ClassElementAddr(
                    registry: registry, base: operands[0], index: i.index,
                    name: resultName(of: i.result)
                )
            case let i as ProjectCell:
                return ProjectCell(
                    registry: registry, cell: operands[0], name: resultName(of: i.result)
                )
            case let i as StructValue:
                return StructValue(fields: operands, ty: remap(type: i.result.ty), name: resultName(of: i.result))
            case let i as TupleValue:
                return TupleValue(elements: operands, ty: remap(type: i.result.ty), name: resultName(of: i.result))
            case let i as EnumValue:
                return EnumValue(
                    caseIndex: i.caseIndex, payload: operands.first, ty: remap(type: i.result.ty),
                    name: resultName(of: i.result)
                )
            case let i as Call:
                return Call(
                    callee: operands[0], arguments: Array(operands.dropFirst()),
                    ty: remap(type: i.result?.ty ?? registry.voidType().id),
                    name: resultName(of: i.result), hasResult: i.result != nil
                )
            case let i as TryCall:
                let errorCellIndex = 1 + i.arguments.count
                let errorCell = i.errorCell.map { _ in operands[errorCellIndex] }
                return TryCall(
                    callee: operands[0], arguments: Array(operands.dropFirst().prefix(i.arguments.count)),
                    successBlock: block(for: i.successBlock), errorBlock: block(for: i.errorBlock),
                    errorCell: errorCell, ty: remap(type: i.result?.ty ?? registry.voidType().id),
                    name: resultName(of: i.result), hasResult: i.result != nil
                )
            case let i as Closure:
                return Closure(
                    function: operands[0] as! FunctionRef, captures: Array(operands.dropFirst()),
                    name: resultName(of: i.result)
                )
            case let i as Upcast:
                return Upcast(
                    value: operands[0], targetType: remap(type: i.targetType), name: resultName(of: i.result)
                )
            case let i as UncheckedRefCast:
                return UncheckedRefCast(
                    value: operands[0], targetType: remap(type: i.targetType), name: resultName(of: i.result)
                )
            case let i as NumericCast:
                return NumericCast(
                    value: operands[0], op: i.op, targetType: remap(type: i.targetType),
                    name: resultName(of: i.result)
                )
            case let i as BitCast:
                return BitCast(
                    value: operands[0], targetType: remap(type: i.targetType), name: resultName(of: i.result)
                )
            case let i as TypeMetadata:
                return TypeMetadata(
                    registry: registry, value: operands[0], name: resultName(of: i.result)
                )
            case let i as TypeMetadataConstant:
                return TypeMetadataConstant(
                    registry: registry, type: remap(type: i.type), metadata: i.metadata,
                    name: resultName(of: i.result)
                )
            case let i as IsInstance:
                return IsInstance(
                    registry: registry, metadata: operands[0], target: operands[1],
                    name: resultName(of: i.result)
                )
            case let i as Superclass:
                return Superclass(
                    registry: registry, metadata: operands[0], name: resultName(of: i.result)
                )
            case is Trap:
                return instruction
            case is Retain:
                return Retain(value: operands[0])
            case is Release:
                return Release(value: operands[0])
            case let i as Copy:
                return Copy(value: operands[0], name: resultName(of: i.result))
            case is Destroy:
                return Destroy(value: operands[0])
            case let i as InlineAsm:
                return InlineAsm(
                    template: i.template, constraints: i.constraints, operands: operands,
                    options: i.options
                )
            case let i as BuildExistential:
                return BuildExistential(
                    value: operands[0], witnesses: i.witnesses, ty: remap(type: i.result.ty),
                    name: resultName(of: i.result)
                )
            case let i as OpenExistential:
                return OpenExistential(
                    container: operands[0], ty: remap(type: i.result.ty), name: resultName(of: i.result)
                )
            case let i as WitnessMethod:
                return WitnessMethod(
                    witness: i.witness, index: i.index, ty: remap(type: i.result.ty),
                    name: resultName(of: i.result)
                )
            case let i as OpaqueWitnessMethod:
                return OpaqueWitnessMethod(
                    container: operands[0], protocolId: i.protocolId, index: i.index,
                    ty: remap(type: i.result.ty), name: resultName(of: i.result)
                )
            case let i as VirtualMethod:
                return VirtualMethod(
                    metadata: i.metadata, index: i.index, selfValue: operands[0],
                    ty: remap(type: i.result.ty), name: resultName(of: i.result)
                )
            case let i as ExistentialCopy:
                return ExistentialCopy(
                    container: operands[0], ty: remap(type: i.result.ty), name: resultName(of: i.result)
                )
            case is ExistentialDestroy:
                return ExistentialDestroy(container: operands[0])
            default:
                return instruction
            }
        }

        private func resultName(of result: TIR.Value?) -> String {
            result?.name ?? ""
        }
    }
}
