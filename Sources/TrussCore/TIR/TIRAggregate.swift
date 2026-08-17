public extension TIR {
    final class StructValue: Instruction {
        public let fields: [Value]
        public init(fields: [Value], ty: Id.TIRTypeId, name: String) {
            self.fields = fields
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStructValue(self, additional: additional)
        }
    }

    final class TupleValue: Instruction {
        public let elements: [Value]
        public init(elements: [Value], ty: Id.TIRTypeId, name: String) {
            self.elements = elements
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTupleValue(self, additional: additional)
        }
    }

    final class EnumValue: Instruction {
        public let caseIndex: Int
        public let payload: Value?
        public init(caseIndex: Int, payload: Value?, ty: Id.TIRTypeId, name: String) {
            self.caseIndex = caseIndex
            self.payload = payload
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEnumValue(self, additional: additional)
        }
    }
}
