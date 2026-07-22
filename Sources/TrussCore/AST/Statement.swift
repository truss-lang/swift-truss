import SwiftAbstract
import TrussDiagnosis

extension AST {
    @abstractClass
    public class Statement: AstNode {
        @abstractInit
        public override init(sourceRange: SourceRange? = nil) {
            super.init(sourceRange: sourceRange)
        }
    }
    public final class EmptyStatement: Statement {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange? = nil) {
            self.token = token
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEmptyStatement(self, additional: additional)
        }
    }
    public final class ErrorStatement: Statement {
        public override init(sourceRange: SourceRange? = nil) {
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitErrorStatement(self, additional: additional)
        }
    }
    public final class ExpressionStatement: Statement {
        public let expression: Expression
        public init(_ expression: Expression, sourceRange: SourceRange? = nil) {
            self.expression = expression
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExpressionStatement(self, additional: additional)
        }
    }
    public final class Return: Statement {
        public let token: Token
        public let value: Expression?
        public init(_ token: Token, _ value: Expression?, sourceRange: SourceRange? = nil) {
            self.token = token
            self.value = value
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitReturn(self, additional: additional)
        }
    }
    public final class ModuleDecl: Statement {
        public let token: Token
        public let name: Token
        public let body: [AST.Statement]
        public var symbol: Symbol.ModuleSymbol? = nil
        public init(
            _ token: Token, _ name: Token, _ body: [AST.Statement], sourceRange: SourceRange? = nil
        ) {
            self.token = token
            self.name = name
            self.body = body
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitModuleDecl(self, additional: additional)
        }
    }
    public final class PrecedenceGroupDecl: Statement {
        public let token: Token
        public let name: Token
        public let higherThanToken: Token?
        public let higherThan: [TypeExpression]
        public let lowerThanToken: Token?
        public let lowerThan: [TypeExpression]
        public let associativityToken: Token?
        public let associativity: Associativity
        public let assignmentToken: Token?
        public let assignment: Bool
        public init(
            _ token: Token, _ name: Token, _ higherThanToken: Token?,
            _ higherThan: [TypeExpression],
            _ lowerThanToken: Token?, _ lowerThan: [TypeExpression], _ associativityToken: Token?,
            _ associativity: Associativity, _ assignmentToken: Token?, _ assignment: Bool,
            sourceRange: SourceRange? = nil
        ) {
            self.token = token
            self.name = name
            self.higherThanToken = higherThanToken
            self.higherThan = higherThan
            self.lowerThanToken = lowerThanToken
            self.lowerThan = lowerThan
            self.associativityToken = associativityToken
            self.associativity = associativity
            self.assignmentToken = assignmentToken
            self.assignment = assignment
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPrecedenceGroupDecl(self, additional: additional)
        }

        public enum Associativity {
            case Left
            case Right
            case None
        }
    }
    public final class FunctionDecl: Statement {
        public let token: Token
        public let name: Token
        public let returnTypeExpression: Expression?
        public let body: Body
        public var symbol: Symbol.FunctionSymbol? = nil
        public init(
            _ token: Token, _ name: Token, _ returnTypeExpression: Expression?, _ body: Body,
            sourceRange: SourceRange? = nil
        ) {
            self.token = token
            self.name = name
            self.returnTypeExpression = returnTypeExpression
            self.body = body
            super.init(sourceRange: sourceRange)
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
        public var symbol: Symbol.VariableSymbol? = nil
        public init(
            _ token: Token, _ name: Token, _ typeExpression: Expression?,
            _ initializer: Expression?,
            sourceRange: SourceRange? = nil
        ) {
            self.token = token
            self.name = name
            self.typeExpression = typeExpression
            self.initializer = initializer
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVariableDecl(self, additional: additional)
        }
    }
}
