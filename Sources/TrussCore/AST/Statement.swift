import SwiftAbstract
import SwiftBetterDiagnostic

extension AST {
    @abstractClass
    public class Statement: AstNode {
        @abstractInit
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }
    }
    @abstractClass
    public class Decl: Statement {
        public let modifiers: [AST.Modifier]
        public let attributes: [AST.Attribute]
        @abstractInit
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute],
            sourceRange: SourceRange
        ) {
            self.modifiers = modifiers
            self.attributes = attributes
            super.init(sourceRange)
        }
    }
    public final class EmptyStatement: Statement {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEmptyStatement(self, additional: additional)
        }
    }
    public final class ErrorStatement: Statement {
        public init(sourceRange: SourceRange) {
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitErrorStatement(self, additional: additional)
        }
    }
    public enum PathComponent {
        case identifier(Token)
        case self_(Token)
    }
    public struct ImportPath {
        public let components: [PathComponent]
        public init(_ components: [PathComponent]) {
            self.components = components
        }
    }
    public struct ImportItem {
        public let kind: Kind
        public let alias: Token?
        public init(_ kind: Kind, alias: Token? = nil) {
            self.kind = kind
            self.alias = alias
        }
        public enum Kind {
            case self_(Token)
            case name(Token)
        }
    }
    public enum ImportSelector {
        case wholeModule(alias: Token?)
        case wildcard
        case explicit([ImportItem])
    }
    public final class ImportDecl: Statement {
        public let token: Token
        public let path: ImportPath
        public let selector: ImportSelector
        public init(
            _ token: Token, _ path: ImportPath, _ selector: ImportSelector,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.path = path
            self.selector = selector
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitImportDecl(self, additional: additional)
        }
    }
    public final class ExpressionStatement: Statement {
        public let expression: Expression
        public init(_ expression: Expression) {
            self.expression = expression
            super.init(expression.sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExpressionStatement(self, additional: additional)
        }
    }
    public final class TypeAliasDecl: Decl {
        public let token: Token
        public let name: Token
        public let typeExpression: Expression
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ typeExpression: Expression, sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.typeExpression = typeExpression
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTypeAliasDecl(self, additional: additional)
        }
    }
    public final class ModuleDecl: Decl {
        public let token: Token
        public let name: Token
        public let body: [AST.Statement]
        public var symbol: Symbol.ModuleSymbol? = nil
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ body: [AST.Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitModuleDecl(self, additional: additional)
        }
    }
    public final class PrecedenceGroupDecl: Decl {
        public let token: Token
        public let name: Token
        public let higherThanTokens: [Token]
        public let higherThan: [Expression]
        public let lowerThanTokens: [Token]
        public let lowerThan: [Expression]
        public let associativityToken: Token?
        public let associativity: Associativity
        public let assignmentToken: Token?
        public let assignment: Bool
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ higherThanTokens: [Token], _ higherThan: [Expression],
            _ lowerThanTokens: [Token], _ lowerThan: [Expression], _ associativityToken: Token?,
            _ associativity: Associativity, _ assignmentToken: Token?, _ assignment: Bool,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.higherThanTokens = higherThanTokens
            self.higherThan = higherThan
            self.lowerThanTokens = lowerThanTokens
            self.lowerThan = lowerThan
            self.associativityToken = associativityToken
            self.associativity = associativity
            self.assignmentToken = assignmentToken
            self.assignment = assignment
            super.init(modifiers, attributes, sourceRange: sourceRange)
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
    public final class StructDecl: Decl {
        public let token: Token
        public let name: Token
        public let genericDecl: GenericDecl?
        public let conformances: [Expression]
        public let body: [AST.Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ genericDecl: GenericDecl?, _ conformances: [Expression],
            _ body: [AST.Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.genericDecl = genericDecl
            self.conformances = conformances
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStructDecl(self, additional: additional)
        }
    }
    public final class ClassDecl: Decl {
        public let token: Token
        public let name: Token
        public let genericDecl: GenericDecl?
        public let inheritanceClauses: [Expression]
        public let body: [AST.Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ genericDecl: GenericDecl?, _ conformances: [Expression],
            _ body: [AST.Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.genericDecl = genericDecl
            self.inheritanceClauses = conformances
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClassDecl(self, additional: additional)
        }
    }
    public final class ActorDecl: Decl {
        public let token: Token
        public let name: Token
        public let genericDecl: GenericDecl?
        public let conformances: [Expression]
        public let body: [AST.Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ genericDecl: GenericDecl?, _ conformances: [Expression],
            _ body: [AST.Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.genericDecl = genericDecl
            self.conformances = conformances
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitActorDecl(self, additional: additional)
        }
    }
    public final class ProtocolDecl: Decl {
        public let token: Token
        public let name: Token
        public let genericDecl: GenericDecl?
        public let conformances: [Expression]
        public let body: [AST.Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ genericDecl: GenericDecl?, _ conformances: [Expression],
            _ body: [AST.Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.genericDecl = genericDecl
            self.conformances = conformances
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitProtocolDecl(self, additional: additional)
        }
    }
    public final class ExtensionDecl: Decl {
        public let token: Token
        public let base: Expression
        public let conformances: [Expression]
        public let body: [AST.Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ base: Expression, _ conformances: [Expression], _ body: [AST.Statement],
            sourceRange: SourceRange
        ) {
            self.token = token
            self.base = base
            self.conformances = conformances
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExtensionDecl(self, additional: additional)
        }
    }
    public final class InitDecl: Decl {
        public let token: Token
        public let optionalToken: Token?
        public let body: [Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ optionalToken: Token?, _ body: [Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.optionalToken = optionalToken
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitInitDecl(self, additional: additional)
        }
    }
    public final class DeinitDecl: Decl {
        public let token: Token
        public let body: [Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ body: [Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeinitDecl(self, additional: additional)
        }
    }
    public final class FunctionDecl: Decl {
        public let token: Token
        public let name: Token
        public let returnTypeExpression: Expression?
        public let body: Body?
        public var symbol: Symbol.FunctionSymbol? = nil
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ returnTypeExpression: Expression?, _ body: Body?,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.returnTypeExpression = returnTypeExpression
            self.body = body
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFunctionDecl(self, additional: additional)
        }

        public enum Body {
            case Block([Statement])
            case Expression(Expression)
        }
    }
    public final class VariableDecl: Decl {
        public let token: Token
        public let name: Token
        public let typeExpression: Expression?
        public let initializer: Expression?
        public let accessors: [Accessor]
        public var symbol: Symbol.VariableSymbol? = nil
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ typeExpression: Expression?, _ initializer: Expression?,
            _ accessors: [Accessor], sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.typeExpression = typeExpression
            self.initializer = initializer
            self.accessors = accessors
            super.init(modifiers, attributes, sourceRange: sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVariableDecl(self, additional: additional)
        }
    }
    public final class Return: Statement {
        public let token: Token
        public let value: Expression?
        public init(_ token: Token, _ value: Expression?, sourceRange: SourceRange) {
            self.token = token
            self.value = value
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitReturn(self, additional: additional)
        }
    }
    public final class While: Statement {
        public let token: Token
        public let condition: Expression
        public let beginToken: Token
        public let body: [Statement]
        public let endToken: Token
        public init(
            _ token: Token, _ condition: Expression, _ beginToken: Token, _ body: [Statement],
            _ endToken: Token, sourceRange: SourceRange
        ) {
            self.token = token
            self.condition = condition
            self.beginToken = beginToken
            self.body = body
            self.endToken = endToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitWhile(self, additional: additional)
        }
    }
    public final class RepeatWhile: Statement {
        public let token: Token
        public let beginToken: Token
        public let body: [Statement]
        public let endToken: Token
        public let whileToken: Token
        public let condition: Expression
        public init(
            _ token: Token, _ beginToken: Token, _ body: [Statement], _ endToken: Token,
            _ whileToken: Token, _ condition: Expression, sourceRange: SourceRange
        ) {
            self.token = token
            self.beginToken = beginToken
            self.body = body
            self.endToken = endToken
            self.whileToken = whileToken
            self.condition = condition
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitRepeatWhile(self, additional: additional)
        }
    }
    public final class Guard: Statement {
        public let token: Token
        public let condition: Expression
        public let beginToken: Token
        public let body: [Statement]
        public let endToken: Token
        public init(
            _ token: Token, _ condition: Expression, _ beginToken: Token, _ body: [Statement],
            _ endToken: Token, sourceRange: SourceRange
        ) {
            self.token = token
            self.condition = condition
            self.beginToken = beginToken
            self.body = body
            self.endToken = endToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitGuard(self, additional: additional)
        }
    }
    public final class Defer: Statement {
        public let token: Token
        public let beginToken: Token
        public let body: [Statement]
        public let endToken: Token
        public init(
            _ token: Token, _ beginToken: Token, _ body: [Statement], _ endToken: Token,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.beginToken = beginToken
            self.body = body
            self.endToken = endToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDefer(self, additional: additional)
        }
    }
    public final class Break: Statement {
        public let token: Token
        public let label: Token?
        public init(_ token: Token, _ label: Token?, sourceRange: SourceRange) {
            self.token = token
            self.label = label
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBreak(self, additional: additional)
        }
    }
    public final class Continue: Statement {
        public let token: Token
        public let label: Token?
        public init(_ token: Token, _ label: Token?, sourceRange: SourceRange) {
            self.token = token
            self.label = label
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitContinue(self, additional: additional)
        }
    }
    public final class Goto: Statement {
        public let token: Token
        public let label: Token
        public init(_ token: Token, _ label: Token, sourceRange: SourceRange) {
            self.token = token
            self.label = label
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitGoto(self, additional: additional)
        }
    }
    public final class Accessor: AstNode {
        public let modifiers: [AST.Modifier]
        public let attributes: [AST.Attribute]
        public let token: Token?
        public let parameterName: Token?
        public let body: FunctionDecl.Body
        public let kind: Kind
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token?,
            _ parameterName: Token?, _ body: FunctionDecl.Body, kind: Kind, sourceRange: SourceRange
        ) {
            self.modifiers = modifiers
            self.attributes = attributes
            self.token = token
            self.parameterName = parameterName
            self.body = body
            self.kind = kind
            super.init(sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAccessor(self, additional: additional)
        }
        public enum Kind {
            case Get
            case Set
            case WillSet
            case DidSet
        }
    }
}
