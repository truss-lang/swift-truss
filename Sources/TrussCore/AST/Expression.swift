import SwiftAbstract

extension AST {
    @abstractClass
    public class Expression: AstNode {
        @abstractInit
        override init() {}
    }
    @abstractClass
    public class Literal: Expression {
        @abstractInit
        override init() {}
    }
    public final class Variable: Expression {
        public let name: Token
        public init(name: Token) {
            self.name = name
        }
    }
    public final class GenericApplication: Expression {
        public let base: Expression
        public let genericArguments: [Expression]
        public init(base: Expression, _ genericArguments: [Expression]) {
            self.base = base
            self.genericArguments = genericArguments
        }
    }
    public final class IntegerLiteral: Literal {
        public let token: Token
        public let value: Int128
        public init(_ token: Token, _ value: Int128) {
            self.token = token
            self.value = value
        }
    }
    public final class FloatLiteral: Literal {
        public let token: Token
        public let value: Double
        public init(_ token: Token, _ value: Double) {
            self.token = token
            self.value = value
        }
    }
    public final class StringLiteral: Literal {
        public let token: Token
        public init(_ token: Token) {
            self.token = token
        }
    }
    public final class CharLiteral: Literal {
        public let token: Token
        public let value: Character
        public init(_ token: Token, _ value: Character) {
            self.token = token
            self.value = value
        }
    }
    public final class BoolLiteral: Literal {
        public let token: Token
        public let value: Bool
        public init(_ token: Token, _ value: Bool) {
            self.token = token
            self.value = value
        }
    }
    public final class NullLiteral: Literal {
        public let token: Token
        public init(_ token: Token) {
            self.token = token
        }
    }
    public final class Call: Expression {
        public let callee: Expression
        public let arguments: [Expression]
        public init(callee: Expression, arguments: [Expression]) {
            self.callee = callee
            self.arguments = arguments
        }
    }
    public final class MemberAccess: Expression {
        public let object: Expression
        public let token: Token
        public let member: Token
        public init(_ object: Expression, _ token: Token, _ member: Token) {
            self.object = object
            self.token = token
            self.member = member
        }
    }
    public final class Infix: Expression {
        public let ops: [Token]
        public let operands: [Expression]
        public init(_ ops: [Token], _ operands: [Expression]) {
            self.ops = ops
            self.operands = operands
        }
    }
    public final class Binary: Expression {
        public let left: Expression
        public let right: Expression
        public let operatorToken: Token
        public let kind: Kind
        public init(_ left: Expression, _ right: Expression, _ operatorToken: Token, _ kind: Kind) {
            self.left = left
            self.right = right
            self.operatorToken = operatorToken
            self.kind = kind
        }
        public enum Kind {
            case Assignment
            case Plus
        }
    }
    public final class Prefix: Expression {
        public let operatorToken: Token
        public let expression: Expression
        public init(_ operatorToken: Token, _ expression: Expression) {
            self.operatorToken = operatorToken
            self.expression = expression
        }
    }
    public final class Postfix: Expression {
        public let expression: Expression
        public let operatorToken: Token
        public init(_ expression: Expression, _ operatorToken: Token) {
            self.expression = expression
            self.operatorToken = operatorToken
        }
    }
    public final class ErrorExpression: Expression {
        public override init() {}
    }
}
