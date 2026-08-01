import SwiftAbstract
import SwiftBetterDiagnostic

extension AST {
    @abstractClass
    public class Expression: AstNode {
        public var ty: TrussType.TrussType? = nil
        @abstractInit
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }
    }
    @abstractClass
    public class Literal: Expression {
        @abstractInit
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }
    }
    public final class ErrorExpression: Expression {
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }
    }
    public final class ParentheticalExpression: Expression {
        public let inner: Expression
        public init(_ inner: Expression, sourceRange: SourceRange) {
            self.inner = inner
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitParentheticalExpression(self, additional: additional)
        }
    }
    public final class Variable: Expression {
        public let name: Token
        public var symbol: Symbol.Symbol? = nil
        public init(name: Token, sourceRange: SourceRange) {
            self.name = name
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVariable(self, additional: additional)
        }
    }
    public final class GenericApplication: Expression {
        public let base: Expression
        public let genericArguments: [Expression]
        public init(
            _ base: Expression, _ genericArguments: [Expression],
            sourceRange: SourceRange
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
        public init(_ token: Token, _ value: Int128, sourceRange: SourceRange) {
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
        public init(_ token: Token, _ value: Double, sourceRange: SourceRange) {
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
        public init(_ token: Token, sourceRange: SourceRange) {
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
        public init(_ token: Token, _ value: Character, sourceRange: SourceRange) {
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
        public init(_ token: Token, _ value: Bool, sourceRange: SourceRange) {
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
        public init(_ token: Token, sourceRange: SourceRange) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitNullLiteral(self, additional: additional)
        }
    }
    public final class VoidLiteral: Literal {
        public let openToken: Token
        public let closeToken: Token
        public init(_ openToken: Token, _ closeToken: Token, sourceRange: SourceRange) {
            self.openToken = openToken
            self.closeToken = closeToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVoidLiteral(self, additional: additional)
        }
    }
    public final class If: Expression {
        public let token: Token
        public let condition: Expression
        public let then: [Statement]
        public let elseKind: ElseKind?
        public init(
            _ token: Token, _ condition: Expression, _ then: [Statement], _ elseKind: ElseKind?,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.condition = condition
            self.then = then
            self.elseKind = elseKind
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitIf(self, additional: additional)
        }
        public enum ElseKind {
            case Block([Statement])
            case If(If)
        }
    }
    public final class Match: Expression {
        public let token: Token
        public let subject: Expression
        public let cases: [Case]
        public init(
            _ token: Token, _ subject: Expression, _ cases: [Case], sourceRange: SourceRange
        ) {
            self.token = token
            self.subject = subject
            self.cases = cases
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitMatch(self, additional: additional)
        }
        public struct Case {
            public let patterns: [Expression]
            public let body: [Statement]
            public let sourceRange: SourceRange
            public init(_ patterns: [Expression], _ body: [Statement], sourceRange: SourceRange) {
                self.patterns = patterns
                self.body = body
                self.sourceRange = sourceRange
            }
        }
    }
    public final class Do: Expression {
        public let token: Token
        public let body: [Statement]
        public let catches: [CatchClause]
        public let finallyBody: [Statement]?
        public init(
            _ token: Token, _ body: [Statement], _ catches: [CatchClause],
            _ finallyBody: [Statement]?, sourceRange: SourceRange
        ) {
            self.token = token
            self.body = body
            self.catches = catches
            self.finallyBody = finallyBody
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDo(self, additional: additional)
        }
        public struct CatchClause {
            public let pattern: Expression?
            public let whereToken: Token?
            public let whereCondition: Expression?
            public let body: [Statement]
            public let sourceRange: SourceRange
            public init(
                _ pattern: Expression?, _ whereToken: Token?, _ whereCondition: Expression?,
                _ body: [Statement], sourceRange: SourceRange
            ) {
                self.pattern = pattern
                self.whereToken = whereToken
                self.whereCondition = whereCondition
                self.body = body
                self.sourceRange = sourceRange
            }
        }
    }
    public struct LabeledArgument {
        public let label: Token?
        public let value: Expression
        public let sourceRange: SourceRange
        public init(label: Token?, value: Expression, sourceRange: SourceRange) {
            self.label = label
            self.value = value
            self.sourceRange = sourceRange
        }
    }
    public final class Call: Expression {
        public let callee: Expression
        public let arguments: [LabeledArgument]
        public let trailingClosures: [(Token?, Closure)]
        public init(
            callee: Expression, arguments: [LabeledArgument],
            trailingClosures: [(Token?, Closure)] = [],
            sourceRange: SourceRange
        ) {
            self.callee = callee
            self.arguments = arguments
            self.trailingClosures = trailingClosures
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCall(self, additional: additional)
        }
    }
    public final class MemberAccess: Expression {
        public let object: Expression
        public let token: Token
        public let member: Token
        public let isOptional: Bool
        public init(
            _ object: Expression, _ token: Token, _ member: Token, isOptional: Bool = false,
            sourceRange: SourceRange
        ) {
            self.object = object
            self.token = token
            self.member = member
            self.isOptional = isOptional
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitMemberAccess(self, additional: additional)
        }
    }
    public final class SelfTypeExpression: Expression {
        public let token: Token
        public init(
            _ token: Token, sourceRange: SourceRange
        ) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSelfTypeExpression(self, additional: additional)
        }
    }
    public final class SelfExpression: Expression {
        public let token: Token
        public init(
            _ token: Token, sourceRange: SourceRange
        ) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSelfExpression(self, additional: additional)
        }
    }
    public final class SuperExpression: Expression {
        public let token: Token
        public init(
            _ token: Token, sourceRange: SourceRange
        ) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSuperExpression(self, additional: additional)
        }
    }
    public final class ImplicitMemberAccess: Expression {
        public let token: Token
        public let name: Token
        public init(_ token: Token, _ name: Token, sourceRange: SourceRange) {
            self.token = token
            self.name = name
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitImplicitMemberAccess(self, additional: additional)
        }
    }
    public struct CaptureItem {
        public let specifier: Token?
        public let name: Token
        public init(_ specifier: Token?, _ name: Token) {
            self.specifier = specifier
            self.name = name
        }
    }
    public struct ClosureSignature {
        public let captureList: [CaptureItem]
        public let parameters: [FunctionDecl.Parameter]
        public let throwsClause: ThrowsClause?
        public let returnType: Expression?
        public let inToken: Token
        public init(
            _ captureList: [CaptureItem], _ parameters: [FunctionDecl.Parameter],
            _ throwsClause: ThrowsClause?, _ returnType: Expression?, _ inToken: Token
        ) {
            self.captureList = captureList
            self.parameters = parameters
            self.throwsClause = throwsClause
            self.returnType = returnType
            self.inToken = inToken
        }
    }
    public final class Closure: Expression {
        public let signature: ClosureSignature?
        public let body: [Statement]
        public init(
            _ signature: ClosureSignature?, _ body: [Statement], sourceRange: SourceRange
        ) {
            self.signature = signature
            self.body = body
            super.init(sourceRange)
        }
        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClosure(self, additional: additional)
        }
    }
    public final class ClosureType: Expression {
        public let parameterTypes: Expression
        public let throwsClause: ThrowsClause?
        public let returnType: Expression
        public init(
            _ parameterTypes: Expression, _ throwsClause: ThrowsClause?,
            _ returnType: Expression, sourceRange: SourceRange
        ) {
            self.parameterTypes = parameterTypes
            self.throwsClause = throwsClause
            self.returnType = returnType
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClosureType(self, additional: additional)
        }
    }
    public final class OptionalType: Expression {
        public let wrappedType: Expression
        public let token: Token
        public init(_ wrappedType: Expression, _ token: Token, sourceRange: SourceRange) {
            self.wrappedType = wrappedType
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitOptionalType(self, additional: additional)
        }
    }
    public final class VariadicType: Expression {
        public let base: Expression
        public let token: Token
        public init(_ base: Expression, _ token: Token, sourceRange: SourceRange) {
            self.base = base
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVariadicType(self, additional: additional)
        }
    }
    public final class SomeType: Expression {
        public let token: Token
        public let wrappedType: Expression
        public init(_ token: Token, _ wrappedType: Expression, sourceRange: SourceRange) {
            self.token = token
            self.wrappedType = wrappedType
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSomeType(self, additional: additional)
        }
    }
    public final class AnyType: Expression {
        public let token: Token
        public let wrappedType: Expression
        public init(_ token: Token, _ wrappedType: Expression, sourceRange: SourceRange) {
            self.token = token
            self.wrappedType = wrappedType
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAnyType(self, additional: additional)
        }
    }
    public final class ProtocolCompositionType: Expression {
        public let types: [Expression]
        public init(_ types: [Expression], sourceRange: SourceRange) {
            self.types = types
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitProtocolCompositionType(self, additional: additional)
        }
    }
    public final class TupleExpression: Expression {
        public let elements: [LabeledArgument]
        public init(_ elements: [LabeledArgument], sourceRange: SourceRange) {
            self.elements = elements
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTupleExpression(self, additional: additional)
        }
    }
    public final class IsPattern: Expression {
        public let token: Token
        public let typeExpression: Expression
        public init(_ token: Token, _ typeExpression: Expression, sourceRange: SourceRange) {
            self.token = token
            self.typeExpression = typeExpression
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitIsPattern(self, additional: additional)
        }
    }
    public final class SequentialExpression: Expression {
        public let ops: [Token]
        public let operands: [Expression]
        public init(_ ops: [Token], _ operands: [Expression], sourceRange: SourceRange) {
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
            sourceRange: SourceRange
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
            _ operatorToken: Token, _ expression: Expression, sourceRange: SourceRange
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
            _ expression: Expression, _ operatorToken: Token, sourceRange: SourceRange
        ) {
            self.expression = expression
            self.operatorToken = operatorToken
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPostfix(self, additional: additional)
        }
    }
    public final class ArrayLiteral: Expression {
        public let elements: [Expression]
        public init(_ elements: [Expression], sourceRange: SourceRange) {
            self.elements = elements
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitArrayLiteral(self, additional: additional)
        }
    }
    public final class DictionaryLiteral: Expression {
        public let entries: [Entry]
        public init(_ entries: [Entry], sourceRange: SourceRange) {
            self.entries = entries
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDictionaryLiteral(self, additional: additional)
        }
        public struct Entry {
            public let key: Expression
            public let value: Expression
            public let sourceRange: SourceRange
            public init(key: Expression, value: Expression, sourceRange: SourceRange) {
                self.key = key
                self.value = value
                self.sourceRange = sourceRange
            }
        }
    }
    public final class CastExpression: Expression {
        public let left: Expression
        public let token: Token
        public let right: Expression
        public let kind: Kind
        public init(
            _ left: Expression, _ token: Token, _ right: Expression, _ kind: Kind,
            sourceRange: SourceRange
        ) {
            self.left = left
            self.token = token
            self.right = right
            self.kind = kind
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCastExpression(self, additional: additional)
        }
        public enum Kind {
            case As
            case AsQuestion
            case AsExclamation
            case Is
        }
    }
    public final class TryExpression: Expression {
        public let token: Token
        public let kind: Kind
        public let expression: Expression
        public init(
            _ token: Token, _ kind: Kind, _ expression: Expression,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.kind = kind
            self.expression = expression
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTryExpression(self, additional: additional)
        }
        public enum Kind {
            case Try
            case TryQuestion
            case TryExclamation
        }
    }
    public final class Subscript: Expression {
        public let base: Expression
        public let arguments: [LabeledArgument]
        public init(base: Expression, arguments: [LabeledArgument], sourceRange: SourceRange) {
            self.base = base
            self.arguments = arguments
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSubscript(self, additional: additional)
        }
    }
    public final class OptionalBinding: Expression {
        public let token: Token
        public let name: Token
        public let typeExpression: Expression?
        public let value: Expression
        public init(
            _ token: Token, _ name: Token, _ typeExpression: Expression?, _ value: Expression,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.typeExpression = typeExpression
            self.value = value
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitOptionalBinding(self, additional: additional)
        }
    }
    public final class CaseMatch: Expression {
        public let token: Token
        public let pattern: Expression
        public let subject: Expression
        public init(
            _ token: Token, _ pattern: Expression, _ subject: Expression,
            sourceRange: SourceRange
        ) {
            self.token = token
            self.pattern = pattern
            self.subject = subject
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitCaseMatch(self, additional: additional)
        }
    }
    public final class BindingPattern: Expression {
        public let token: Token
        public let name: Token
        public init(_ token: Token, _ name: Token, sourceRange: SourceRange) {
            self.token = token
            self.name = name
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBindingPattern(self, additional: additional)
        }
    }
    public final class WildcardPattern: Expression {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange) {
            self.token = token
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitWildcardPattern(self, additional: additional)
        }
    }
    public final class ShorthandArgument: Expression {
        public let dollarToken: Token
        public let index: Int
        public init(_ dollarToken: Token, _ index: Int, sourceRange: SourceRange) {
            self.dollarToken = dollarToken
            self.index = index
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitShorthandArgument(self, additional: additional)
        }
    }
    public enum StringSegment {
        case literal(Token)
        case expression(Expression)
    }
    public final class StringInterpolation: Expression {
        public let segments: [StringSegment]
        public init(_ segments: [StringSegment], sourceRange: SourceRange) {
            self.segments = segments
            super.init(sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStringInterpolation(self, additional: additional)
        }
    }
}
