public extension TIR {
    final class Retain: Instruction {
        public let value: Value
        public init(value: Value) {
            self.value = value
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitRetain(self, additional: additional)
        }
    }

    final class Release: Instruction {
        public let value: Value
        public init(value: Value) {
            self.value = value
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitRelease(self, additional: additional)
        }
    }

    final class Copy: Instruction {
        public let value: Value
        public var result: Value
        public init(value: Value, name: String) {
            self.value = value
            result = InstructionResult(ty: value.ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCopy(self, additional: additional)
        }
    }

    final class Destroy: Instruction {
        public let value: Value
        public init(value: Value) {
            self.value = value
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDestroy(self, additional: additional)
        }
    }
}
