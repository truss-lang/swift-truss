import SwiftAbstract
import SwiftBetterDiagnostic

extension AST {
    @abstractClass
    public class Expression: AstNode {
        public var ty: TrussType.TrussType? = nil
        @abstractInit
        public override init(_ sourceRange: SourceRange? = nil) {
            super.init(sourceRange)
        }
    }
    @abstractClass
    public class TypeExpression: Expression {
        @abstractInit
        public override init(_ sourceRange: SourceRange? = nil) {
            super.init(sourceRange)
        }
    }
    @abstractClass
    public class Literal: Expression {
        @abstractInit
        public override init(_ sourceRange: SourceRange? = nil) {
            super.init(sourceRange)
        }
    }
    public final class ErrorExpression: Expression {
        public override init(_ sourceRange: SourceRange? = nil) {
            super.init(sourceRange)
        }
    }
    public final class Variable: TypeExpression {
        public let name: Token
        public var symbol: Symbol.Symbol? = nil
        public init(name: Token, sourceRange: SourceRange? = nil) {
            self.name = name
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVariable(self, additional: additional)
        }
    }
    public final class GenericApplication: TypeExpression {
        public let base: TypeExpression
        public let genericArguments: [TypeExpression]
        public init(
            base: TypeExpression, _ genericArguments: [TypeExpression],
            sourceRange: SourceRange? = nil
        ) {
            self.base = base
            self.genericArguments = genericArguments
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitGenericApplication(self, additional: additional)
        }
    }
    public final class IntegerLiteral: Literal {
        public let token: Token
        public let value: Int128
        public init(_ token: Token, _ value: Int128, sourceRange: SourceRange? = nil) {
            self.token = token
            self.value = value
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitIntegerLiteral(self, additional: additional)
        }
    }
    public final class FloatLiteral: Literal {
        public let token: Token
        public let value: Double
        public init(_ token: Token, _ value: Double, sourceRange: SourceRange? = nil) {
            self.token = token
            self.value = value
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFloatLiteral(self, additional: additional)
        }
    }
    public final class StringLiteral: Literal {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange? = nil) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStringLiteral(self, additional: additional)
        }
    }
    public final class CharLiteral: Literal {
        public let token: Token
        public let value: Character
        public init(_ token: Token, _ value: Character, sourceRange: SourceRange? = nil) {
            self.token = token
            self.value = value
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCharLiteral(self, additional: additional)
        }
    }
    public final class BoolLiteral: Literal {
        public let token: Token
        public let value: Bool
        public init(_ token: Token, _ value: Bool, sourceRange: SourceRange? = nil) {
            self.token = token
            self.value = value
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBoolLiteral(self, additional: additional)
        }
    }
    public final class NullLiteral: Literal {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange? = nil) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitNullLiteral(self, additional: additional)
        }
    }
    public final class Call: Expression {
        public let callee: Expression
        public let arguments: [Expression]
        public init(callee: Expression, arguments: [Expression], sourceRange: SourceRange? = nil) {
            self.callee = callee
            self.arguments = arguments
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCall(self, additional: additional)
        }
    }
    public final class MemberAccess: TypeExpression {
        public let object: Expression
        public let token: Token
        public let member: Token
        public init(
            _ object: Expression, _ token: Token, _ member: Token, sourceRange: SourceRange? = nil
        ) {
            self.object = object
            self.token = token
            self.member = member
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitMemberAccess(self, additional: additional)
        }
    }
    public final class SelfTypeExpression: TypeExpression {
        public let token: Token
        public init(
            _ token: Token, sourceRange: SourceRange? = nil
        ) {
            self.token = token
            super.init(sourceRange)
        }
    }
    public final class SelfExpression: Expression {
        public let token: Token
        public init(
            _ token: Token, sourceRange: SourceRange? = nil
        ) {
            self.token = token
            super.init(sourceRange)
        }
    }
    public final class SuperExpression: Expression {
        public let token: Token
        public init(
            _ token: Token, sourceRange: SourceRange? = nil
        ) {
            self.token = token
            super.init(sourceRange)
        }
    }
    public final class SequentialExpression: Expression {
        public let ops: [Token]
        public let operands: [Expression]
        public init(_ ops: [Token], _ operands: [Expression], sourceRange: SourceRange? = nil) {
            self.ops = ops
            self.operands = operands
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSequentialExpression(self, additional: additional)
        }
    }
    public final class Binary: Expression {
        public let left: Expression
        public let right: Expression
        public let operatorToken: Token
        public init(
            _ left: Expression, _ right: Expression, _ operatorToken: Token,
            sourceRange: SourceRange? = nil
        ) {
            self.left = left
            self.right = right
            self.operatorToken = operatorToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBinary(self, additional: additional)
        }
    }
    public final class Prefix: Expression {
        public let operatorToken: Token
        public let expression: Expression
        public init(
            _ operatorToken: Token, _ expression: Expression, sourceRange: SourceRange? = nil
        ) {
            self.operatorToken = operatorToken
            self.expression = expression
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPrefix(self, additional: additional)
        }
    }
    public final class Postfix: Expression {
        public let expression: Expression
        public let operatorToken: Token
        public init(
            _ expression: Expression, _ operatorToken: Token, sourceRange: SourceRange? = nil
        ) {
            self.expression = expression
            self.operatorToken = operatorToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPostfix(self, additional: additional)
        }
    }
}
