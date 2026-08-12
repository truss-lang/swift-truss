import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class IntegerLiteral: Instruction {
        public let value: Int64
        public let literalType: TIRType.TIRType
        public init(_ value: Int64, type literalType: TIRType.TIRType, sourceRange: SourceRange) {
            self.value = value
            self.literalType = literalType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitIntegerLiteral(self, additional: additional)
        }
    }

    final class FloatLiteral: Instruction {
        public let value: Double
        public let literalType: TIRType.TIRType
        public init(_ value: Double, type literalType: TIRType.TIRType, sourceRange: SourceRange) {
            self.value = value
            self.literalType = literalType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFloatLiteral(self, additional: additional)
        }
    }

    final class StringLiteral: Instruction {
        public let value: String
        public init(_ value: String, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStringLiteral(self, additional: additional)
        }
    }

    final class CharLiteral: Instruction {
        public let value: Character
        public init(_ value: Character, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCharLiteral(self, additional: additional)
        }
    }

    final class BoolLiteral: Instruction {
        public let value: Bool
        public init(_ value: Bool, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBoolLiteral(self, additional: additional)
        }
    }

    final class NullLiteral: Instruction {
        public let literalType: TIRType.TIRType
        public init(type literalType: TIRType.TIRType, sourceRange: SourceRange) {
            self.literalType = literalType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitNullLiteral(self, additional: additional)
        }
    }

    final class VoidLiteral: Instruction {
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVoidLiteral(self, additional: additional)
        }
    }

    final class ArrayValue: Instruction {
        public let elements: [Value]
        public init(elements: [Value], sourceRange: SourceRange) {
            self.elements = elements
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitArrayValue(self, additional: additional)
        }
    }

    final class DictionaryValue: Instruction {
        public struct Entry {
            public let key: Value
            public let value: Value
            public init(key: Value, value: Value) {
                self.key = key
                self.value = value
            }
        }

        public let entries: [Entry]
        public init(entries: [Entry], sourceRange: SourceRange) {
            self.entries = entries
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDictionaryValue(self, additional: additional)
        }
    }
}
