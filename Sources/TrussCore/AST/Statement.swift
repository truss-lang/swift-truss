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
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ sourceRange: SourceRange
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
    public final class Import: Statement {
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
            visitor.visitImport(self, additional: additional)
        }
    }
    public final class ExternDecl: Decl {
        public let token: Token
        public let convention: Token
        public let body: Body
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ convention: Token, _ body: Body, sourceRange: SourceRange
        ) {
            self.token = token
            self.convention = convention
            self.body = body
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExternDecl(self, additional: additional)
        }
        public enum Body {
            case Block([Statement])
            case Declaration(Decl)
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
            super.init(modifiers, attributes, sourceRange)
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
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitModuleDecl(self, additional: additional)
        }
    }
    public final class OperatorDecl: Decl {
        public let token: Token
        public let name: Token
        public let kind: Kind
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ kind: Kind, sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.kind = kind
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitOperatorDecl(self, additional: additional)
        }
        public enum Kind {
            case Infix(Token)
            case Prefix(Token)
            case Postfix(Token)
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
            super.init(modifiers, attributes, sourceRange)
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
            super.init(modifiers, attributes, sourceRange)
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
            super.init(modifiers, attributes, sourceRange)
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
            super.init(modifiers, attributes, sourceRange)
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
            super.init(modifiers, attributes, sourceRange)
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
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitExtensionDecl(self, additional: additional)
        }
    }
    public final class EnumDecl: Decl {
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
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEnumDecl(self, additional: additional)
        }
    }
    public final class EnumCaseDecl: Decl {
        public let token: Token
        public let elements: [Element]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ elements: [Element], sourceRange: SourceRange
        ) {
            self.token = token
            self.elements = elements
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitEnumCaseDecl(self, additional: additional)
        }
        public struct Element {
            public let name: Token
            public let associatedValues: [AssociatedValue]
            public let rawValue: Expression?
            public let sourceRange: SourceRange
            public init(
                name: Token, associatedValues: [AssociatedValue], rawValue: Expression?,
                sourceRange: SourceRange
            ) {
                self.name = name
                self.associatedValues = associatedValues
                self.rawValue = rawValue
                self.sourceRange = sourceRange
            }
        }
        public struct AssociatedValue {
            public let label: Token?
            public let typeExpression: Expression
            public let sourceRange: SourceRange
            public init(label: Token?, typeExpression: Expression, sourceRange: SourceRange) {
                self.label = label
                self.typeExpression = typeExpression
                self.sourceRange = sourceRange
            }
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
            super.init(modifiers, attributes, sourceRange)
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
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeinitDecl(self, additional: additional)
        }
    }
    public final class FunctionDecl: Decl {
        public let token: Token
        public let name: Token
        public let parameters: [Parameter]
        public let returnTypeExpression: Expression?
        public let body: Body?
        public var symbol: Symbol.FunctionSymbol? = nil
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ parameters: [Parameter], _ returnTypeExpression: Expression?,
            _ body: Body?, sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.parameters = parameters
            self.returnTypeExpression = returnTypeExpression
            self.body = body
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFunctionDecl(self, additional: additional)
        }

        public enum Body {
            case Block([Statement])
            case Expression(Expression)
        }

        public struct Parameter {
            public let label: Token?
            public let name: Token
            public let type: Expression?
            public let defaultValue: Expression?
            public let sourceRange: SourceRange
            public init(
                label: Token?, name: Token, type: Expression?, defaultValue: Expression?,
                sourceRange: SourceRange
            ) {
                self.label = label
                self.name = name
                self.type = type
                self.defaultValue = defaultValue
                self.sourceRange = sourceRange
            }
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
            super.init(modifiers, attributes, sourceRange)
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
    public final class For: Statement {
        public let token: Token
        public let pattern: Expression
        public let inToken: Token
        public let sequence: Expression
        public let beginToken: Token
        public let body: [Statement]
        public let endToken: Token
        public init(
            _ token: Token, _ pattern: Expression, _ inToken: Token,
            _ sequence: Expression, _ beginToken: Token, _ body: [Statement],
            _ endToken: Token, sourceRange: SourceRange
        ) {
            self.token = token
            self.pattern = pattern
            self.inToken = inToken
            self.sequence = sequence
            self.beginToken = beginToken
            self.body = body
            self.endToken = endToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitFor(self, additional: additional)
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
    public final class LabeledStatement: Statement {
        public let label: Token
        public let body: Statement
        public init(_ label: Token, _ body: Statement, sourceRange: SourceRange) {
            self.label = label
            self.body = body
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitLabeledStatement(self, additional: additional)
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
    public final class SubscriptDecl: Decl {
        public let token: Token
        public let parameters: [FunctionDecl.Parameter]
        public let returnType: Expression
        public let body: [Statement]
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ parameters: [FunctionDecl.Parameter], _ returnType: Expression,
            _ body: [Statement], sourceRange: SourceRange
        ) {
            self.token = token
            self.parameters = parameters
            self.returnType = returnType
            self.body = body
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSubscriptDecl(self, additional: additional)
        }
    }
    public final class AssociatedTypeDecl: Decl {
        public let token: Token
        public let name: Token
        public let constraint: Expression?
        public let whereClause: [AST.WhereRequirement]?
        public init(
            _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], _ token: Token,
            _ name: Token, _ constraint: Expression?,
            _ whereClause: [AST.WhereRequirement]?, sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.constraint = constraint
            self.whereClause = whereClause
            super.init(modifiers, attributes, sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAssociatedTypeDecl(self, additional: additional)
        }
    }
}
