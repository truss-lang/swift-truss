import SwiftAbstract

extension AST {
    @abstractClass
    public class Statement: AstNode {
        @abstractInit
        override init() {}
    }
    public final class ExpressionStatement: Statement {
        public let expression: Expression
        public init(_ expression: Expression) {
            self.expression = expression
        }
    }
    public final class Return: Statement {
        public let value: Expression?
        public init(_ value: Expression?) {
            self.value = value
        }
    }
    public final class FunctionDecl: Statement {
        public let token: Token
        public let name: Token
        public let returnTypeExpression: TypeExpression?
        public let body: Body
        public init(
            _ token: Token, _ name: Token, _ returnTypeExpression: TypeExpression?, _ body: Body
        ) {
            self.token = token
            self.name = name
            self.returnTypeExpression = returnTypeExpression
            self.body = body
        }
        public enum Body {
            case block([Statement])
            case expression(Expression)
        }
    }
    public final class VariableDecl: Statement {
        public let token: Token
        public let name: Token
        public let typeExpression: TypeExpression?
        public let initializer: Expression?
        public init(
            _ token: Token, _ name: Token, _ typeExpression: TypeExpression?,
            _ initializer: Expression?
        ) {
            self.token = token
            self.name = name
            self.typeExpression = typeExpression
            self.initializer = initializer
        }
    }
}
