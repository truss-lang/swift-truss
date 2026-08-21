public extension TIR {
    final class Upcast: Instruction {
        public let value: Value
        public let targetType: Id.TIRTypeId
        public init(value: Value, targetType: Id.TIRTypeId, name: String) {
            self.value = value
            self.targetType = targetType
            super.init(ty: targetType, name: name)
            result = InstructionResult(ty: targetType, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUpcast(self, additional: additional)
        }
    }

    final class UncheckedRefCast: Instruction {
        public let value: Value
        public let targetType: Id.TIRTypeId
        public init(value: Value, targetType: Id.TIRTypeId, name: String) {
            self.value = value
            self.targetType = targetType
            super.init(ty: targetType, name: name)
            result = InstructionResult(ty: targetType, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUncheckedRefCast(self, additional: additional)
        }
    }

    final class SizeOf: Instruction {
        public let sizedType: Id.TIRTypeId
        public init(registry: Registry, sizedType: Id.TIRTypeId, name: String) {
            self.sizedType = sizedType
            super.init(ty: registry.integerType(isSigned: true, bitWidth: 64).id, name: name)
            result = InstructionResult(ty: ty, name: self.name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSizeOf(self, additional: additional)
        }
    }
}
