import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class CopyValue: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCopyValue(self, additional: additional)
        }
    }

    final class DestroyValue: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDestroyValue(self, additional: additional)
        }
    }

    final class RetainValue: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitRetainValue(self, additional: additional)
        }
    }

    final class ReleaseValue: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitReleaseValue(self, additional: additional)
        }
    }

    final class BorrowValue: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBorrowValue(self, additional: additional)
        }
    }

    final class EndBorrow: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEndBorrow(self, additional: additional)
        }
    }

    final class MoveValue: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitMoveValue(self, additional: additional)
        }
    }
}
