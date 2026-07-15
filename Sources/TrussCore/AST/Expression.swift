import SwiftAbstract

extension AST {
    @abstractClass
    public class Expression: AstNode {
        @abstractInit
        override init() {}
    }
    @abstractClass
    public class TypeExpression: Expression {
        @abstractInit
        override init() {}
    }
    public final class IntegerLiteral: Expression {
        public let token: Token
        public let value: Int128
        public init(_ token: Token, _ value: Int128) {
            self.token = token
            self.value = value
        }
    }
    public final class FloatLiteral: Expression {
        public let token: Token
        public let value: Double
        public init(_ token: Token, _ value: Double) {
            self.token = token
            self.value = value
        }
    }
    public final class StringLiteral: Expression {
        public let token: Token
        public init(_ token: Token) {
            self.token = token
        }
    }
    public final class CharLiteral: Expression {
        public let token: Token
        public let value: Character
        public init(_ token: Token, _ value: Character) {
            self.token = token
            self.value = value
        }
    }
    public final class Variable: TypeExpression {
        public let name: Token
        public init(name: Token) {
            self.name = name
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
    public final class GenericApplication: TypeExpression {
        public let base: TypeExpression
        public let genericArguments: [TypeExpression]
        public init(base: TypeExpression, genericArguments: [TypeExpression]) {
            self.base = base
            self.genericArguments = genericArguments
        }
    }
}
