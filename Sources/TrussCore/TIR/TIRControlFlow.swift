public extension TIR {
    final class Return: Instruction {
        public let value: Value?
        public init(value: Value? = nil) {
            self.value = value
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitReturn(self, additional: additional)
        }
    }

    final class Branch: Instruction {
        public let target: BasicBlock
        public let arguments: [Value]
        public init(target: BasicBlock, arguments: [Value] = []) {
            self.target = target
            self.arguments = arguments
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBranch(self, additional: additional)
        }
    }

    final class ConditionalBranch: Instruction {
        public let condition: Value
        public let trueBranch: BasicBlock
        public let falseBranch: BasicBlock
        public let trueArguments: [Value]
        public let falseArguments: [Value]
        public init(
            condition: Value, trueBranch: BasicBlock, falseBranch: BasicBlock,
            trueArguments: [Value] = [], falseArguments: [Value] = []
        ) {
            self.condition = condition
            self.trueBranch = trueBranch
            self.falseBranch = falseBranch
            self.trueArguments = trueArguments
            self.falseArguments = falseArguments
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitConditionalBranch(self, additional: additional)
        }
    }

    final class Unreachable: Instruction {
        public override init() {}

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUnreachable(self, additional: additional)
        }
    }

    final class Phi: Instruction {
        public struct Incoming {
            public let value: Value
            public let block: BasicBlock
            public init(value: Value, block: BasicBlock) {
                self.value = value
                self.block = block
            }
        }

        public let incomings: [Incoming]
        public var result: Value
        public init(incomings: [Incoming], ty: Id.TIRTypeId, name: String) {
            self.incomings = incomings
            result = InstructionResult(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPhi(self, additional: additional)
        }
    }

    final class SwitchEnum: Instruction {
        public struct Case {
            public let tag: Int
            public let block: BasicBlock
            public let arguments: [Value]
            public init(tag: Int, block: BasicBlock, arguments: [Value] = []) {
                self.tag = tag
                self.block = block
                self.arguments = arguments
            }
        }

        public let value: Value
        public let cases: [Case]
        public let defaultBlock: BasicBlock?
        public init(value: Value, cases: [Case], defaultBlock: BasicBlock?) {
            self.value = value
            self.cases = cases
            self.defaultBlock = defaultBlock
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSwitchEnum(self, additional: additional)
        }
    }

    final class ExtractPayload: Instruction {
        public let value: Value
        public let caseIndex: Int
        public var result: Value
        public init(value: Value, caseIndex: Int, ty: Id.TIRTypeId, name: String) {
            self.value = value
            self.caseIndex = caseIndex
            result = InstructionResult(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExtractPayload(self, additional: additional)
        }
    }
}
