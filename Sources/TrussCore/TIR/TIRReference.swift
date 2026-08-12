import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    struct Substitution {
        public let genericParam: Symbol.GenericParamSymbol?
        public let concreteType: TIRType.TIRType
        public init(genericParam: Symbol.GenericParamSymbol?, concreteType: TIRType.TIRType) {
            self.genericParam = genericParam
            self.concreteType = concreteType
        }
    }

    final class FunctionRef: Instruction {
        public let function: Function
        public init(_ function: Function, sourceRange: SourceRange) {
            self.function = function
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFunctionRef(self, additional: additional)
        }
    }

    final class Closure: Instruction {
        public let function: Function
        public let captures: [Value]
        public init(_ function: Function, captures: [Value], sourceRange: SourceRange) {
            self.function = function
            self.captures = captures
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClosure(self, additional: additional)
        }
    }

    final class ClassMethod: Instruction {
        public let reference: Value
        public let methodSymbol: Symbol.FunctionSymbol
        public init(_ reference: Value, methodSymbol: Symbol.FunctionSymbol, sourceRange: SourceRange) {
            self.reference = reference
            self.methodSymbol = methodSymbol
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClassMethod(self, additional: additional)
        }
    }

    final class SuperMethod: Instruction {
        public let reference: Value
        public let methodSymbol: Symbol.FunctionSymbol
        public init(_ reference: Value, methodSymbol: Symbol.FunctionSymbol, sourceRange: SourceRange) {
            self.reference = reference
            self.methodSymbol = methodSymbol
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSuperMethod(self, additional: additional)
        }
    }

    final class WitnessMethod: Instruction {
        public let protocolSymbol: Symbol.ProtocolSymbol
        public let methodSymbol: Symbol.FunctionSymbol
        public init(
            protocolSymbol: Symbol.ProtocolSymbol, methodSymbol: Symbol.FunctionSymbol,
            sourceRange: SourceRange
        ) {
            self.protocolSymbol = protocolSymbol
            self.methodSymbol = methodSymbol
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
