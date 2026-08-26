public extension TIR {
    final class Upcast: Instruction {
        public let value: Value
        public let targetType: Id.TIRTypeId
        public var result: Value
        public init(value: Value, targetType: Id.TIRTypeId, name: String) {
            self.value = value
            self.targetType = targetType
            result = InstructionResult(ty: targetType, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUpcast(self, additional: additional)
        }
    }

    final class UncheckedRefCast: Instruction {
        public let value: Value
        public let targetType: Id.TIRTypeId
        public var result: Value
        public init(value: Value, targetType: Id.TIRTypeId, name: String) {
            self.value = value
            self.targetType = targetType
            result = InstructionResult(ty: targetType, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUncheckedRefCast(self, additional: additional)
        }
    }

    final class SizeOf: Instruction {
        public let sizedType: Id.TIRTypeId
        public var result: Value
        public init(registry: Registry, sizedType: Id.TIRTypeId, name: String) {
            self.sizedType = sizedType
            let ty = registry.integerType(isSigned: true, bitWidth: 64).id
            result = InstructionResult(ty: ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSizeOf(self, additional: additional)
        }
    }

    final class TypeMetadata: Instruction {
        public let value: Value
        public var result: Value
        public init(registry: Registry, value: Value, name: String) {
            self.value = value
            result = InstructionResult(ty: registry.metadataType().id, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTypeMetadata(self, additional: additional)
        }
    }

    final class TypeMetadataConstant: Instruction {
        public let type: Id.TIRTypeId
        public let metadata: Id.TIRMetadataId
        public var result: Value
        public init(registry: Registry, type: Id.TIRTypeId, metadata: Id.TIRMetadataId, name: String) {
            self.type = type
            self.metadata = metadata
            result = InstructionResult(ty: registry.metadataType().id, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTypeMetadataConstant(self, additional: additional)
        }
    }

    final class IsInstance: Instruction {
        public let metadata: Value
        public let target: Value
        public var result: Value
        public init(registry: Registry, metadata: Value, target: Value, name: String) {
            self.metadata = metadata
            self.target = target
            result = InstructionResult(
                ty: registry.primitiveType(kind: .Bool, bitWidth: 1).id, name: name
            )
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitIsInstance(self, additional: additional)
        }
    }

    final class Superclass: Instruction {
        public let metadata: Value
        public var result: Value
        public init(registry: Registry, metadata: Value, name: String) {
            self.metadata = metadata
            result = InstructionResult(ty: registry.metadataType().id, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSuperclass(self, additional: additional)
        }
    }

    final class Trap: Instruction {
        public let message: String?
        public init(message: String?) {
            self.message = message
            super.init(name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTrap(self, additional: additional)
        }
    }
}
