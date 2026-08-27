public extension TIR {
    final class BuildExistential: Instruction {
        public let value: Value
        public let witnesses: [Id.TIRWitnessId]
        public var result: Value
        public init(value: Value, witnesses: [Id.TIRWitnessId], ty: Id.TIRTypeId, name: String) {
            self.value = value
            self.witnesses = witnesses
            result = InstructionResult(ty: ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBuildExistential(self, additional: additional)
        }
    }

    final class OpenExistential: Instruction {
        public let container: Value
        public var result: Value
        public init(container: Value, ty: Id.TIRTypeId, name: String) {
            self.container = container
            result = InstructionResult(ty: ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitOpenExistential(self, additional: additional)
        }
    }

    final class WitnessMethod: Instruction {
        public let witness: Id.TIRWitnessId
        public let index: Int
        public let selfValue: Value
        public let arguments: [Value]
        public var result: Value
        public init(
            witness: Id.TIRWitnessId, index: Int, selfValue: Value, arguments: [Value],
            ty: Id.TIRTypeId, name: String
        ) {
            self.witness = witness
            self.index = index
            self.selfValue = selfValue
            self.arguments = arguments
            result = InstructionResult(ty: ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitWitnessMethod(self, additional: additional)
        }
    }

    final class OpaqueWitnessMethod: Instruction {
        public let container: Value
        public let protocolId: Id.TIRProtocolId
        public let index: Int
        public let selfValue: Value
        public let arguments: [Value]
        public var result: Value
        public init(
            container: Value, protocolId: Id.TIRProtocolId, index: Int, selfValue: Value,
            arguments: [Value], ty: Id.TIRTypeId, name: String
        ) {
            self.container = container
            self.protocolId = protocolId
            self.index = index
            self.selfValue = selfValue
            self.arguments = arguments
            result = InstructionResult(ty: ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitOpaqueWitnessMethod(self, additional: additional)
        }
    }

    final class ExistentialCopy: Instruction {
        public let container: Value
        public var result: Value
        public init(container: Value, ty: Id.TIRTypeId, name: String) {
            self.container = container
            result = InstructionResult(ty: ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExistentialCopy(self, additional: additional)
        }
    }

    final class ExistentialDestroy: Instruction {
        public let container: Value
        public init(container: Value) {
            self.container = container
            super.init(name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExistentialDestroy(self, additional: additional)
        }
    }
}
