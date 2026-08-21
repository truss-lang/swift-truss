public extension TIR {
    final class Return: Instruction {
        public let value: Value?
        public init(value: Value? = nil) {
            self.value = value
            super.init(name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitReturn(self, additional: additional)
        }
    }

    final class Branch: Instruction {
        public let target: BasicBlock
        public init(target: BasicBlock) {
            self.target = target
            super.init(name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBranch(self, additional: additional)
        }
    }

    final class ConditionalBranch: Instruction {
        public let condition: Value
        public let trueBranch: BasicBlock
        public let falseBranch: BasicBlock
        public init(condition: Value, trueBranch: BasicBlock, falseBranch: BasicBlock) {
            self.condition = condition
            self.trueBranch = trueBranch
            self.falseBranch = falseBranch
            super.init(name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitConditionalBranch(self, additional: additional)
        }
    }

    final class Unreachable: Instruction {
        public init() {
            super.init(name: "")
        }

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
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPhi(self, additional: additional)
        }
    }

    final class SwitchEnum: Instruction {
        public struct Case {
            public let tag: Int
            public let block: BasicBlock
            public init(tag: Int, block: BasicBlock) {
                self.tag = tag
                self.block = block
            }
        }

        public let value: Value
        public let cases: [Case]
        public let defaultBlock: BasicBlock?
        public init(value: Value, cases: [Case], defaultBlock: BasicBlock?) {
            self.value = value
            self.cases = cases
            self.defaultBlock = defaultBlock
            super.init(name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSwitchEnum(self, additional: additional)
        }
    }

    final class ExtractPayload: Instruction {
        public let value: Value
        public var result: Value
        public init(value: Value, ty: Id.TIRTypeId, name: String) {
            self.value = value
            result = InstructionResult(ty: ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExtractPayload(self, additional: additional)
        }
    }
}
