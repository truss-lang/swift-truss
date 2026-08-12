import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    struct StructFieldValue {
        public let name: String
        public let value: Value
        public init(name: String, value: Value) {
            self.name = name
            self.value = value
        }
    }

    final class StructValue: Instruction {
        public let structType: TIRType.StructType
        public let fields: [StructFieldValue]
        public init(_ structType: TIRType.StructType, fields: [StructFieldValue], sourceRange: SourceRange) {
            self.structType = structType
            self.fields = fields
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStructValue(self, additional: additional)
        }
    }

    final class TupleValue: Instruction {
        public let elements: [Value]
        public init(elements: [Value], sourceRange: SourceRange) {
            self.elements = elements
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTupleValue(self, additional: additional)
        }
    }

    final class EnumValue: Instruction {
        public let enumType: TIRType.EnumType
        public let caseName: String
        public let payload: Value?
        public init(
            _ enumType: TIRType.EnumType, caseName: String, payload: Value?,
            sourceRange: SourceRange
        ) {
            self.enumType = enumType
            self.caseName = caseName
            self.payload = payload
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEnumValue(self, additional: additional)
        }
    }

    final class InitEnumDataAddr: Instruction {
        public let enumAddress: Value
        public let caseName: String
        public init(_ enumAddress: Value, caseName: String, sourceRange: SourceRange) {
            self.enumAddress = enumAddress
            self.caseName = caseName
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitInitEnumDataAddr(self, additional: additional)
        }
    }

    final class UncheckedEnumData: Instruction {
        public let enumValue: Value
        public let caseName: String
        public init(_ enumValue: Value, caseName: String, sourceRange: SourceRange) {
            self.enumValue = enumValue
            self.caseName = caseName
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUncheckedEnumData(self, additional: additional)
        }
    }
}
