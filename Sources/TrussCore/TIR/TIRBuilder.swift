import SwiftBetterDiagnostic

public extension TIR {
    final class Builder {
        public let registry: Registry
        public var insertPoint: BasicBlock? {
            didSet {
                if let insertPoint, insertPoint.function !== oldValue?.function {
                    nextValueIndex = 0
                }
            }
        }

        private var nextValueIndex: Int = 0
        public var sourceRange: SourceRange = TIR.unknownSourceRange

        public init(registry: Registry) {
            self.registry = registry
        }

        private func attach<T: Instruction>(_ instruction: T, result: Value? = nil) -> T {
            instruction.sourceRange = sourceRange
            result?.sourceRange = sourceRange
            return instruction
        }

        private func freshName(_ name: String?) -> String {
            if let name {
                return name
            }
            let index = nextValueIndex
            nextValueIndex += 1
            return String(index)
        }

        private func voidType() -> Id.TIRTypeId {
            registry.voidType().id
        }

        private func callResultType(_ callee: Value) -> Id.TIRTypeId {
            if let functionType = registry.types[callee.ty] as? TIRType.FunctionType {
                return functionType.returnType
            }
            return voidType()
        }

        @discardableResult
        public func buildReturn(_ value: Value? = nil) -> Return {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Return(value: value)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildBranch(to target: BasicBlock, arguments: [Value] = []) -> Branch {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Branch(target: target, arguments: arguments)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildConditionalBranch(
            condition: Value, trueBranch: BasicBlock, falseBranch: BasicBlock,
            trueArguments: [Value] = [], falseArguments: [Value] = []
        ) -> ConditionalBranch {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.ConditionalBranch(
                condition: condition, trueBranch: trueBranch, falseBranch: falseBranch,
                trueArguments: trueArguments, falseArguments: falseArguments
            )
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildUnreachable() -> Unreachable {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Unreachable()
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildPhi(incomings: [Phi.Incoming], name: String? = nil) -> Phi {
            guard let insertPoint else { fatalError("no insert point") }
            let ty = incomings.first?.value.ty ?? voidType()
            let instruction = TIR.Phi(incomings: incomings, ty: ty, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildSwitchEnum(
            value: Value, cases: [SwitchEnum.Case], defaultBlock: BasicBlock? = nil
        ) -> SwitchEnum {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.SwitchEnum(
                value: value, cases: cases, defaultBlock: defaultBlock
            )
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildExtractPayload(
            value: Value, caseIndex: Int, ty: Id.TIRTypeId, name: String? = nil
        ) -> ExtractPayload {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.ExtractPayload(
                value: value, caseIndex: caseIndex, ty: ty, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildUnaryArith(op: ArithOp, operand: Value, name: String? = nil) -> UnaryArith {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.UnaryArith(op: op, operand: operand, ty: operand.ty, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildBinaryArith(op: ArithOp, lhs: Value, rhs: Value, name: String? = nil) -> BinaryArith {
            guard let insertPoint else { fatalError("no insert point") }
            let ty = if op.isCompare {
                registry.primitiveType(kind: .Bool, bitWidth: 1).id
            } else {
                lhs.ty
            }
            let instruction = TIR.BinaryArith(op: op, lhs: lhs, rhs: rhs, ty: ty, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildAllocStack(allocatedType: Id.TIRTypeId, name: String? = nil) -> AllocStack {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.AllocStack(
                registry: registry, allocatedType: allocatedType, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildDeallocStack(_ value: Value) -> DeallocStack {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.DeallocStack(value: value)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildAllocHeap(allocatedType: Id.TIRTypeId, name: String? = nil) -> AllocHeap {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.AllocHeap(
                registry: registry, allocatedType: allocatedType, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildDeallocHeap(_ value: Value) -> DeallocHeap {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.DeallocHeap(value: value)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildAllocCell(allocatedType: Id.TIRTypeId, name: String? = nil) -> AllocCell {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.AllocCell(
                registry: registry, allocatedType: allocatedType, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildDeallocCell(_ value: Value) -> DeallocCell {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.DeallocCell(value: value)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildLoad(ptr: Value, name: String? = nil) -> Load {
            guard let insertPoint else { fatalError("no insert point") }
            let ty = if let pointerType = registry.types[ptr.ty] as? TIRType.PointerType {
                pointerType.pointee
            } else {
                ptr.ty
            }
            let instruction = TIR.Load(ptr: ptr, ty: ty, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildStore(value: Value, to ptr: Value) -> Store {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Store(value: value, ptr: ptr)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildSizeOf(sizedType: Id.TIRTypeId, name: String? = nil) -> SizeOf {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.SizeOf(registry: registry, sizedType: sizedType, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildGlobalAddr(global: GlobalVariable, name: String? = nil) -> GlobalAddr {
            let value = TIR.GlobalAddr(
                globalId: global.id, ty: registry.pointerType(pointee: global.type).id,
                name: name ?? global.name
            )
            value.sourceRange = sourceRange
            return value
        }

        @discardableResult
        public func buildStructElementAddr(
            base: Value, index: Int, name: String? = nil
        ) -> StructElementAddr {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.StructElementAddr(
                registry: registry, base: base, index: index, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildTupleElementAddr(
            base: Value, index: Int, name: String? = nil
        ) -> TupleElementAddr {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.TupleElementAddr(
                registry: registry, base: base, index: index, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildClassElementAddr(
            base: Value, index: Int, name: String? = nil
        ) -> ClassElementAddr {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.ClassElementAddr(
                registry: registry, base: base, index: index, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildProjectCell(cell: Value, name: String? = nil) -> ProjectCell {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.ProjectCell(registry: registry, cell: cell, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildStructValue(
            fields: [Value], ty: Id.TIRTypeId, name: String? = nil
        ) -> StructValue {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.StructValue(fields: fields, ty: ty, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildTupleValue(
            elements: [Value], ty: Id.TIRTypeId, name: String? = nil
        ) -> TupleValue {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.TupleValue(elements: elements, ty: ty, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildEnumValue(
            caseIndex: Int, payload: Value?, ty: Id.TIRTypeId, name: String? = nil
        ) -> EnumValue {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.EnumValue(
                caseIndex: caseIndex, payload: payload, ty: ty, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildCall(callee: Value, arguments: [Value], name: String? = nil) -> Call {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Call(
                callee: callee, arguments: arguments, ty: callResultType(callee),
                name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildTryCall(
            callee: Value, arguments: [Value], successBlock: BasicBlock, errorBlock: BasicBlock,
            errorCell: Value? = nil, resultTy: Id.TIRTypeId? = nil, name: String? = nil
        ) -> TryCall {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.TryCall(
                callee: callee, arguments: arguments, successBlock: successBlock,
                errorBlock: errorBlock, errorCell: errorCell, ty: resultTy ?? callResultType(callee),
                name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildFunctionRef(function: TIR.Function, name: String? = nil) -> FunctionRef {
            let value = TIR.FunctionRef(
                functionId: function.id, ty: function.ty, name: name ?? function.name
            )
            value.sourceRange = sourceRange
            return value
        }

        @discardableResult
        public func buildClosure(
            function: TIR.Function, captures: [Value], name: String? = nil
        ) -> Closure {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Closure(
                function: function, captures: captures, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildUpcast(value: Value, to targetType: Id.TIRTypeId, name: String? = nil) -> Upcast {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Upcast(
                value: value, targetType: targetType, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildUncheckedRefCast(
            value: Value, to targetType: Id.TIRTypeId, name: String? = nil
        ) -> UncheckedRefCast {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.UncheckedRefCast(
                value: value, targetType: targetType, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildTypeMetadata(value: Value, name: String? = nil) -> TypeMetadata {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.TypeMetadata(
                registry: registry, value: value, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildTypeMetadataConstant(
            type: Id.TIRTypeId, metadata: Id.TIRMetadataId, name: String? = nil
        ) -> TypeMetadataConstant {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.TypeMetadataConstant(
                registry: registry, type: type, metadata: metadata, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildIsInstance(
            metadata: Value, target: Value, name: String? = nil
        ) -> IsInstance {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.IsInstance(
                registry: registry, metadata: metadata, target: target, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildSuperclass(metadata: Value, name: String? = nil) -> Superclass {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Superclass(
                registry: registry, metadata: metadata, name: freshName(name)
            )
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildTrap(message: String? = nil) -> Trap {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Trap(message: message)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildRetain(_ value: Value) -> Retain {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Retain(value: value)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildRelease(_ value: Value) -> Release {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Release(value: value)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildCopy(_ value: Value, name: String? = nil) -> Copy {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Copy(value: value, name: freshName(name))
            insertPoint.instructions.append(attach(instruction, result: instruction.result))
            return instruction
        }

        @discardableResult
        public func buildDestroy(_ value: Value) -> Destroy {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.Destroy(value: value)
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildInlineAsm(
            template: String, constraints: [String], operands: [Value], options: [String]
        ) -> InlineAsm {
            guard let insertPoint else { fatalError("no insert point") }
            let instruction = TIR.InlineAsm(
                template: template, constraints: constraints,
                operands: operands, options: options
            )
            insertPoint.instructions.append(attach(instruction))
            return instruction
        }

        @discardableResult
        public func buildIntegerLiteral(
            value: UInt64, ty: Id.TIRTypeId, name: String? = nil
        ) -> IntegerLiteral {
            let literal = TIR.IntegerLiteral(value: value, ty: ty, name: name ?? "")
            literal.sourceRange = sourceRange
            return literal
        }

        @discardableResult
        public func buildFloatLiteral(
            value: Float64, ty: Id.TIRTypeId, name: String? = nil
        ) -> FloatLiteral {
            let literal = TIR.FloatLiteral(value: value, ty: ty, name: name ?? "")
            literal.sourceRange = sourceRange
            return literal
        }

        @discardableResult
        public func buildCharLiteral(
            value: Character, ty: Id.TIRTypeId, name: String? = nil
        ) -> CharLiteral {
            let literal = TIR.CharLiteral(value: value, ty: ty, name: name ?? "")
            literal.sourceRange = sourceRange
            return literal
        }

        @discardableResult
        public func buildBoolLiteral(value: Bool, ty: Id.TIRTypeId, name: String? = nil) -> BoolLiteral {
            let literal = TIR.BoolLiteral(value: value, ty: ty, name: name ?? "")
            literal.sourceRange = sourceRange
            return literal
        }

        @discardableResult
        public func buildStringLiteral(
            value: String, ty: Id.TIRTypeId, name: String? = nil
        ) -> StringLiteral {
            let literal = TIR.StringLiteral(value: value, ty: ty, name: name ?? "")
            literal.sourceRange = sourceRange
            return literal
        }

        @discardableResult
        public func buildNullptrLiteral(ty: Id.TIRTypeId, name: String? = nil) -> NullptrLiteral {
            let literal = TIR.NullptrLiteral(ty: ty, name: name ?? "")
            literal.sourceRange = sourceRange
            return literal
        }

        @discardableResult
        public func buildVoidLiteral(ty: Id.TIRTypeId, name: String? = nil) -> VoidLiteral {
            let literal = TIR.VoidLiteral(ty: ty, name: name ?? "")
            literal.sourceRange = sourceRange
            return literal
        }
    }
}
