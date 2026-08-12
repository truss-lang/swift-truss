import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class Branch: Instruction {
        public let target: BasicBlock
        public init(_ target: BasicBlock, sourceRange: SourceRange) {
            self.target = target
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBranch(self, additional: additional)
        }
    }

    final class CondBranch: Instruction {
        public let condition: Value
        public let trueBlock: BasicBlock
        public let falseBlock: BasicBlock
        public init(
            condition: Value, trueBlock: BasicBlock, falseBlock: BasicBlock,
            sourceRange: SourceRange
        ) {
            self.condition = condition
            self.trueBlock = trueBlock
            self.falseBlock = falseBlock
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCondBranch(self, additional: additional)
        }
    }

    struct EnumCaseBranch {
        public let caseName: String
        public let block: BasicBlock
        public init(caseName: String, block: BasicBlock) {
            self.caseName = caseName
            self.block = block
        }
    }

    final class SwitchEnum: Instruction {
        public let value: Value
        public let cases: [EnumCaseBranch]
        public let defaultBlock: BasicBlock?
        public init(
            _ value: Value, cases: [EnumCaseBranch], defaultBlock: BasicBlock?,
            sourceRange: SourceRange
        ) {
            self.value = value
            self.cases = cases
            self.defaultBlock = defaultBlock
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSwitchEnum(self, additional: additional)
        }
    }

    struct ValueCaseBranch {
        public let literal: Value
        public let block: BasicBlock
        public init(literal: Value, block: BasicBlock) {
            self.literal = literal
            self.block = block
        }
    }

    final class SwitchValue: Instruction {
        public let value: Value
        public let cases: [ValueCaseBranch]
        public let defaultBlock: BasicBlock?
        public init(
            _ value: Value, cases: [ValueCaseBranch], defaultBlock: BasicBlock?,
            sourceRange: SourceRange
        ) {
            self.value = value
            self.cases = cases
            self.defaultBlock = defaultBlock
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSwitchValue(self, additional: additional)
        }
    }

    final class Return: Instruction {
        public let value: Value?
        public init(_ value: Value? = nil, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitReturn(self, additional: additional)
        }
    }

    final class Throw: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitThrow(self, additional: additional)
        }
    }

    final class Unreachable: Instruction {
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUnreachable(self, additional: additional)
        }
    }

    final class Trap: Instruction {
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTrap(self, additional: additional)
        }
    }

    struct PhiIncoming {
        public let value: Value
        public let block: BasicBlock
        public init(value: Value, block: BasicBlock) {
            self.value = value
            self.block = block
        }
    }

    final class Phi: Instruction {
        public let incomings: [PhiIncoming]
        public init(incomings: [(Value, BasicBlock)], sourceRange: SourceRange) {
            self.incomings = incomings.map { PhiIncoming(value: $0.0, block: $0.1) }
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPhi(self, additional: additional)
        }
    }
}
