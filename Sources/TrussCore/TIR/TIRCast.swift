public extension TIR {
    final class Upcast: Instruction {
        public let value: Value
        public let targetType: Id.TIRTypeId
        public init(value: Value, targetType: Id.TIRTypeId, name: String) {
            self.value = value
            self.targetType = targetType
            super.init(ty: targetType, name: name)
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
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUncheckedRefCast(self, additional: additional)
        }
    }
}
