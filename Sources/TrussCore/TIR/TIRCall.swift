public extension TIR {
    final class FunctionRef: Value {
        public let functionId: Id.TIRFunctionId
        public init(functionId: Id.TIRFunctionId, ty: Id.TIRTypeId, name: String) {
            self.functionId = functionId
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFunctionRef(self, additional: additional)
        }
    }

    final class Call: Instruction {
        public let callee: Value
        public let arguments: [Value]
        public var result: Value?
        public init(callee: Value, arguments: [Value], ty: Id.TIRTypeId, name: String) {
            self.callee = callee
            self.arguments = arguments
            super.init(name: name)
            result = InstructionResult(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCall(self, additional: additional)
        }
    }

    final class TryCall: Instruction {
        public let callee: Value
        public let arguments: [Value]
        public let successBlock: BasicBlock
        public let errorBlock: BasicBlock
        public let errorCell: Value?
        public var result: Value?
        public init(
            callee: Value, arguments: [Value], successBlock: BasicBlock, errorBlock: BasicBlock,
            errorCell: Value?, ty: Id.TIRTypeId, name: String
        ) {
            self.callee = callee
            self.arguments = arguments
            self.successBlock = successBlock
            self.errorBlock = errorBlock
            self.errorCell = errorCell
            super.init(name: name)
            result = InstructionResult(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTryCall(self, additional: additional)
        }
    }

    final class Closure: Instruction {
        public let function: TIR.Function
        public let captures: [Value]
        public var result: Value
        public init(function: TIR.Function, captures: [Value], name: String) {
            self.function = function
            self.captures = captures
            result = InstructionResult(ty: function.ty, name: name)
            super.init(name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClosure(self, additional: additional)
        }
    }
}
