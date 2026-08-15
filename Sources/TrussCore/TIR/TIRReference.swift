import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    struct Substitution {
        public let concreteType: TIRType.TIRType
        public init(concreteType: TIRType.TIRType) {
            self.concreteType = concreteType
        }
    }

    final class FunctionRef: Instruction {
        public let functionId: Int
        public init(functionId: Int, sourceRange: SourceRange) {
            self.functionId = functionId
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFunctionRef(self, additional: additional)
        }
    }

    final class Closure: Instruction {
        public let functionId: Int
        public let captures: [Value]
        public init(functionId: Int, captures: [Value], sourceRange: SourceRange) {
            self.functionId = functionId
            self.captures = captures
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClosure(self, additional: additional)
        }
    }

    final class ClassMethod: Instruction {
        public let reference: Value
        public let methodName: String
        public init(_ reference: Value, methodName: String, sourceRange: SourceRange) {
            self.reference = reference
            self.methodName = methodName
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClassMethod(self, additional: additional)
        }
    }

    final class SuperMethod: Instruction {
        public let reference: Value
        public let methodName: String
        public init(_ reference: Value, methodName: String, sourceRange: SourceRange) {
            self.reference = reference
            self.methodName = methodName
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSuperMethod(self, additional: additional)
        }
    }

    final class WitnessMethod: Instruction {
        public let protocolName: String
        public let methodName: String
        public init(
            protocolName: String, methodName: String,
            sourceRange: SourceRange
        ) {
            self.protocolName = protocolName
            self.methodName = methodName
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitWitnessMethod(self, additional: additional)
        }
    }

    final class Apply: Instruction {
        public let callee: Value
        public let arguments: [Value]
        public let substitutions: [Substitution]
        public init(
            callee: Value, arguments: [Value], substitutions: [Substitution],
            sourceRange: SourceRange
        ) {
            self.callee = callee
            self.arguments = arguments
            self.substitutions = substitutions
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitApply(self, additional: additional)
        }
    }

    final class TryApply: Instruction {
        public let callee: Value
        public let arguments: [Value]
        public let substitutions: [Substitution]
        public let successBlock: BasicBlock
        public let errorBlock: BasicBlock
        public init(
            callee: Value, arguments: [Value], substitutions: [Substitution],
            successBlock: BasicBlock, errorBlock: BasicBlock, sourceRange: SourceRange
        ) {
            self.callee = callee
            self.arguments = arguments
            self.substitutions = substitutions
            self.successBlock = successBlock
            self.errorBlock = errorBlock
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTryApply(self, additional: additional)
        }
    }

    final class PartialApply: Instruction {
        public let callee: Value
        public let arguments: [Value]
        public init(callee: Value, arguments: [Value], sourceRange: SourceRange) {
            self.callee = callee
            self.arguments = arguments
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPartialApply(self, additional: additional)
        }
    }

    final class Upcast: Instruction {
        public let value: Value
        public let targetType: TIRType.TIRType
        public init(_ value: Value, to targetType: TIRType.TIRType, sourceRange: SourceRange) {
            self.value = value
            self.targetType = targetType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUpcast(self, additional: additional)
        }
    }

    final class UncheckedRefCast: Instruction {
        public let value: Value
        public let targetType: TIRType.TIRType
        public init(_ value: Value, to targetType: TIRType.TIRType, sourceRange: SourceRange) {
            self.value = value
            self.targetType = targetType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUncheckedRefCast(self, additional: additional)
        }
    }

    final class InitExistential: Instruction {
        public let value: Value
        public let existentialType: TIRType.ExistentialType
        public init(_ value: Value, to existentialType: TIRType.ExistentialType, sourceRange: SourceRange) {
            self.value = value
            self.existentialType = existentialType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitInitExistential(self, additional: additional)
        }
    }

    final class OpenExistential: Instruction {
        public let value: Value
        public init(_ value: Value, sourceRange: SourceRange) {
            self.value = value
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitOpenExistential(self, additional: additional)
        }
    }
}
