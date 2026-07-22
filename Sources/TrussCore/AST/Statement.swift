import SwiftAbstract

extension AST {
    @abstractClass
    public class Statement: AstNode {
        @abstractInit
        public override init()
    }
    public final class EmptyStatement: Statement {
        public let token: Token
        public init(_ token: Token) {
            self.token = token
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEmptyStatement(self, additional: additional)
        }
    }
    public final class ErrorStatement: Statement {
        public override init() {}
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitErrorStatement(self, additional: additional)
        }
    }
    public final class ExpressionStatement: Statement {
        public let expression: Expression
        public init(_ expression: Expression) {
            self.expression = expression
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExpressionStatement(self, additional: additional)
        }
    }
    public final class Return: Statement {
        public let token: Token
        public let value: Expression?
        public init(_ token: Token, _ value: Expression?) {
            self.token = token
            self.value = value
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitReturn(self, additional: additional)
        }
    }
    public final class FunctionDecl: Statement {
        public let token: Token
        public let name: Token
        public let returnTypeExpression: Expression?
        public let body: Body
        public init(
            _ token: Token, _ name: Token, _ returnTypeExpression: Expression?, _ body: Body
        ) {
            self.token = token
            self.name = name
            self.returnTypeExpression = returnTypeExpression
            self.body = body
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFunctionDecl(self, additional: additional)
        }

        public enum Body {
            case Block([Statement])
            case Expression(Expression)
        }
    }
    public final class VariableDecl: Statement {
        public let token: Token
        public let name: Token
        public let typeExpression: Expression?
        public let initializer: Expression?
        public init(
            _ token: Token, _ name: Token, _ typeExpression: Expression?,
            _ initializer: Expression?
        ) {
            self.token = token
            self.name = name
            self.typeExpression = typeExpression
            self.initializer = initializer
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVariableDecl(self, additional: additional)
        }
    }
}
