import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class ExistentialMetatype: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExistentialMetatype(self, additional: additional)
        }
    }

    final class GenericMetatype: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitGenericMetatype(self, additional: additional)
        }
    }

    final class OpenArchetype: Instruction {
        public let value: Value
        public let archetype: TIRType.ArchetypeType
        public init(_ value: Value, archetype: TIRType.ArchetypeType, sourceRange: SourceRange) {
            self.value = value
            self.archetype = archetype
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitOpenArchetype(self, additional: additional)
        }
    }
}
