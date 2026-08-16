import SwiftAbstract
import SwiftBetterDiagnostic

public extension AST {
    @abstractClass
    class Expression: AstNode {
        public var ty: TrussType.TrussType? = nil
        public var isLeftValue: Bool = false
        @abstractInit
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }

        public override func copySemantics(from other: AST.AstNode) {
            if let otherExpression = other as? AST.Expression {
                ty = otherExpression.ty
            }
        }
    }

    @abstractClass
    class Literal: Expression {
        @abstractInit
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }
    }

    final class ErrorExpression: Expression {
        public override init(_ sourceRange: SourceRange) {
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitErrorExpression(self, additional: additional)
        }
    }

    final class Parenthetical: Expression {
        public let inner: Expression
        public init(_ inner: Expression, sourceRange: SourceRange) {
            self.inner = inner
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitParenthetical(self, additional: additional)
        }
    }

    final class Variable: Expression {
        public let name: Token
        public var symbol: Symbol.Symbol? = nil
        public var overloads: [Symbol.FunctionSymbol]? = nil
        public init(name: Token, sourceRange: SourceRange) {
            self.name = name
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitVariable(self, additional: additional)
        }

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherVariable = other as? AST.Variable else { return }
            symbol = otherVariable.symbol
            overloads = otherVariable.overloads
        }
    }

    final class GenericApplication: Expression {
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

    final class IntegerLiteral: Literal {
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

    final class FloatLiteral: Literal {
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

    final class StringLiteral: Literal {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange) {
            self.token = token
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStringLiteral(self, additional: additional)
        }
    }

    final class CharLiteral: Literal {
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

    final class BoolLiteral: Literal {
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

    final class NullLiteral: Literal {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange) {
            self.token = token
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitNullLiteral(self, additional: additional)
        }
    }

    final class NullPointerLiteral: Literal {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange) {
            self.token = token
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitNullPointerLiteral(self, additional: additional)
        }
    }

    final class VoidLiteral: Literal {
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

    final class If: Expression {
        public let token: Token
        public let condition: Expression
        public let then: [Statement]
        public let elseKind: ElseKind?
        public var scope: Scope? = nil
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

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherIf = other as? AST.If else { return }
            scope = otherIf.scope
        }

        public enum ElseKind {
            case Block([Statement])
            case If(If)
        }
    }

    final class Match: Expression {
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

    final class Do: Expression {
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

    struct LabeledArgument {
        public let label: Token?
        public let value: Expression
        public let sourceRange: SourceRange
        public init(label: Token?, value: Expression, sourceRange: SourceRange) {
            self.label = label
            self.value = value
            self.sourceRange = sourceRange
        }
    }

    final class Call: Expression {
        public let callee: Expression
        public let arguments: [LabeledArgument]
        public let trailingClosures: [(Token?, Closure)]
        public var symbol: Symbol.FunctionSymbol? = nil
        public var overloads: [Symbol.FunctionSymbol]? = nil
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

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherCall = other as? AST.Call else { return }
            symbol = otherCall.symbol
            overloads = otherCall.overloads
        }
    }

    final class MemberAccess: Expression {
        public let object: Expression
        public let token: Token
        public let member: Token
        public let isOptional: Bool
        public var symbol: Symbol.Symbol? = nil
        public var overloads: [Symbol.FunctionSymbol]? = nil
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

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherMember = other as? AST.MemberAccess else { return }
            symbol = otherMember.symbol
            overloads = otherMember.overloads
        }
    }

    final class SelfType: Expression {
        public let token: Token
        public init(
            _ token: Token, sourceRange: SourceRange
        ) {
            self.token = token
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSelfType(self, additional: additional)
        }
    }

    final class SelfExpression: Expression {
        public let token: Token
        public var symbol: Symbol.Symbol? = nil
        public init(
            _ token: Token, sourceRange: SourceRange
        ) {
            self.token = token
            super.init(sourceRange)
        }

        public override func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSelfExpression(self, additional: additional)
        }

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherSelf = other as? AST.SelfExpression else { return }
            symbol = otherSelf.symbol
        }
    }

    final class SuperExpression: Expression {
        public let token: Token
        public var symbol: Symbol.Symbol? = nil
        public init(
            _ token: Token, sourceRange: SourceRange
        ) {
            self.token = token
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSuperExpression(self, additional: additional)
        }

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherSuper = other as? AST.SuperExpression else { return }
            symbol = otherSuper.symbol
        }
    }

    final class ImplicitMemberAccess: Expression {
        public let token: Token
        public let name: Token
        public var symbol: Symbol.Symbol? = nil
        public var overloads: [Symbol.FunctionSymbol]? = nil
        public init(_ token: Token, _ name: Token, sourceRange: SourceRange) {
            self.token = token
            self.name = name
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitImplicitMemberAccess(self, additional: additional)
        }

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherImplicit = other as? AST.ImplicitMemberAccess else { return }
            symbol = otherImplicit.symbol
            overloads = otherImplicit.overloads
        }
    }

    struct CaptureItem {
        public let specifier: Token?
        public let name: Token
        public init(_ specifier: Token?, _ name: Token) {
            self.specifier = specifier
            self.name = name
        }
    }

    struct ClosureSignature {
        public let captureList: [CaptureItem]
        public let parameters: [FunctionDecl.Parameter]
        public let throwsClause: ThrowsClause?
        public let returnType: Expression?
        public let asyncToken: Token?
        public let inToken: Token
        public init(
            _ captureList: [CaptureItem], _ parameters: [FunctionDecl.Parameter],
            _ throwsClause: ThrowsClause?, _ returnType: Expression?,
            _ asyncToken: Token?, _ inToken: Token
        ) {
            self.captureList = captureList
            self.parameters = parameters
            self.throwsClause = throwsClause
            self.returnType = returnType
            self.asyncToken = asyncToken
            self.inToken = inToken
        }
    }

    final class Closure: Expression {
        public let signature: ClosureSignature?
        public let body: [Statement]
        public var scope: Scope? = nil
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

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherClosure = other as? AST.Closure else { return }
            scope = otherClosure.scope
        }
    }

    final class ClosureType: Expression {
        public let parameters: [Parameter]
        public let asyncToken: Token?
        public let throwsClause: ThrowsClause?
        public let returnType: Expression
        public init(
            _ parameters: [Parameter], _ asyncToken: Token?, _ throwsClause: ThrowsClause?,
            _ returnType: Expression, sourceRange: SourceRange
        ) {
            self.parameters = parameters
            self.asyncToken = asyncToken
            self.throwsClause = throwsClause
            self.returnType = returnType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitClosureType(self, additional: additional)
        }

        public struct Parameter {
            public let label: Token?
            public let type: Expression
            public let sourceRange: SourceRange
            public init(label: Token?, type: Expression, sourceRange: SourceRange) {
                self.label = label
                self.type = type
                self.sourceRange = sourceRange
            }
        }
    }

    final class OptionalType: Expression {
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

    final class PointerType: Expression {
        public let wrappedType: Expression
        public let token: Token
        public let isNonnull: Bool
        public init(
            _ wrappedType: Expression, _ token: Token, isNonnull: Bool = false,
            sourceRange: SourceRange
        ) {
            self.wrappedType = wrappedType
            self.token = token
            self.isNonnull = isNonnull
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitPointerType(self, additional: additional)
        }
    }

    final class VariadicType: Expression {
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

    final class SomeType: Expression {
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

    final class AnyType: Expression {
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

    final class ProtocolCompositionType: Expression {
        public let types: [Expression]
        public init(_ types: [Expression], sourceRange: SourceRange) {
            self.types = types
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitProtocolCompositionType(self, additional: additional)
        }
    }

    final class Tuple: Expression {
        public let elements: [LabeledArgument]
        public init(_ elements: [LabeledArgument], sourceRange: SourceRange) {
            self.elements = elements
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTuple(self, additional: additional)
        }
    }

    final class IsPattern: Expression {
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

    final class AsPattern: Expression {
        public let pattern: Expression
        public let token: Token
        public let typeExpression: Expression
        public init(
            _ pattern: Expression, _ token: Token, _ typeExpression: Expression,
            sourceRange: SourceRange
        ) {
            self.pattern = pattern
            self.token = token
            self.typeExpression = typeExpression
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAsPattern(self, additional: additional)
        }
    }

    final class Sequential: Expression {
        public let ops: [Token]
        public let operands: [Expression]
        public init(_ ops: [Token], _ operands: [Expression], sourceRange: SourceRange) {
            self.ops = ops
            self.operands = operands
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSequential(self, additional: additional)
        }
    }

    final class Binary: Expression {
        public let left: Expression
        public let right: Expression
        public let operatorToken: Token
        public var symbol: Symbol.FunctionSymbol? = nil
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

    final class Prefix: Expression {
        public let operatorToken: Token
        public let expression: Expression
        public var symbol: Symbol.FunctionSymbol? = nil
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

    final class Postfix: Expression {
        public let expression: Expression
        public let operatorToken: Token
        public var symbol: Symbol.FunctionSymbol? = nil
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

    final class Dereference: Expression {
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
            visitor.visitDereference(self, additional: additional)
        }
    }

    final class AddressOf: Expression {
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
            visitor.visitAddressOf(self, additional: additional)
        }
    }

    final class ArrayLiteral: Expression {
        public let elements: [Expression]
        public init(_ elements: [Expression], sourceRange: SourceRange) {
            self.elements = elements
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitArrayLiteral(self, additional: additional)
        }
    }

    final class DictionaryLiteral: Expression {
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

    final class Cast: Expression {
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
            visitor.visitCast(self, additional: additional)
        }

        public enum Kind {
            case As
            case OptionalAs
            case AsExclamation
            case AsBitCast
            case Is
        }
    }

    final class Try: Expression {
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
            visitor.visitTry(self, additional: additional)
        }

        public enum Kind {
            case Try
            case OptionalTry
            case TryExclamation
        }
    }

    final class Await: Expression {
        public let token: Token
        public let expression: Expression
        public init(
            _ token: Token, _ expression: Expression, sourceRange: SourceRange
        ) {
            self.token = token
            self.expression = expression
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAwait(self, additional: additional)
        }
    }

    final class Subscript: Expression {
        public let base: Expression
        public let arguments: [LabeledArgument]
        public var overloads: [Symbol.FunctionSymbol]? = nil
        public var symbol: Symbol.FunctionSymbol? = nil
        public init(base: Expression, arguments: [LabeledArgument], sourceRange: SourceRange) {
            self.base = base
            self.arguments = arguments
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitSubscript(self, additional: additional)
        }

        public override func copySemantics(from other: AST.AstNode) {
            super.copySemantics(from: other)
            guard let otherSubscript = other as? AST.Subscript else { return }
            overloads = otherSubscript.overloads
        }
    }

    final class ForceUnwrap: Expression {
        public let token: Token
        public let expression: Expression
        public init(_ expression: Expression, _ token: Token, sourceRange: SourceRange) {
            self.token = token
            self.expression = expression
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitForceUnwrap(self, additional: additional)
        }
    }

    final class OptionalBinding: Expression {
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

    final class CaseMatch: Expression {
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

    final class BindingPattern: Expression {
        public let token: Token
        public let name: Token
        public let typeExpression: Expression?
        public let subpattern: Expression?
        public init(
            _ token: Token, _ name: Token, _ typeExpression: Expression?,
            _ subpattern: Expression?, sourceRange: SourceRange
        ) {
            self.token = token
            self.name = name
            self.typeExpression = typeExpression
            self.subpattern = subpattern
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBindingPattern(self, additional: additional)
        }
    }

    final class WildcardPattern: Expression {
        public let token: Token
        public init(_ token: Token, sourceRange: SourceRange) {
            self.token = token
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitWildcardPattern(self, additional: additional)
        }
    }

    final class ShorthandArgument: Expression {
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

    final class KeyPathExpression: Expression {
        public final class Component {
            public let dotToken: Token
            public let name: Token
            public let postfix: Token?
            public var symbol: Symbol.Symbol? = nil
            public var overloads: [Symbol.FunctionSymbol]? = nil
            public init(dotToken: Token, name: Token, postfix: Token?) {
                self.dotToken = dotToken
                self.name = name
                self.postfix = postfix
            }
        }

        public let backslashToken: Token
        public let root: Expression?
        public let rootPostfix: Token?
        public let components: [Component]
        public init(
            _ backslashToken: Token, _ root: Expression?, _ rootPostfix: Token?,
            _ components: [Component], sourceRange: SourceRange
        ) {
            self.backslashToken = backslashToken
            self.root = root
            self.rootPostfix = rootPostfix
            self.components = components
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitKeyPathExpression(self, additional: additional)
        }
    }

    enum StringSegment {
        case literal(Token)
        case expression(Expression)
    }

    final class StringInterpolation: Expression {
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

public extension OperatorKind {
    var genericCloseLevels: Int? {
        switch self {
        case .Greater: 1
        case .RightShift: 2
        case .RightShiftLogical: 3
        case .GreaterEqual: 1
        case .RightShiftAssign: 2
        case .RightShiftLogicalAssign: 3
        default: nil
        }
    }
}

public extension AST.Sequential {
    func genericApplicationGroupCloseIndex() -> Int? {
        guard let first = ops.first, case .Operator(.Less) = first.kind else { return nil }
        var depth = 0
        for (index, op) in ops.enumerated() {
            switch op.kind {
            case let .Operator(kind?):
                if kind == .Less {
                    depth += 1
                } else if let levels = kind.genericCloseLevels {
                    depth -= levels
                } else {
                    return nil
                }
            case .Separator(.Comma) where depth > 0:
                continue
            default:
                return nil
            }
            if depth <= 0 {
                return index
            }
        }
        return nil
    }

    func compositionMemberBaseOperands() -> [AST.Expression]? {
        guard !ops.isEmpty else { return nil }
        guard case let .Operator(first?) = ops[0].kind, first == .Less || first == .BitAnd
        else {
            return nil
        }
        guard let firstOperand = operands.first else { return nil }
        var depth = 0
        var members: [AST.Expression] = [firstOperand]
        for op in ops {
            switch op.kind {
            case let .Operator(kind?):
                if kind == .Less {
                    depth += 1
                } else if let levels = kind.genericCloseLevels {
                    depth -= levels
                } else if kind == .BitAnd, depth == 0 {
                    guard
                        let next = operands.first(where: {
                            $0.sourceRange.start.offset > op.pos.pos + op.pos.len
                        })
                    else {
                        return nil
                    }
                    members.append(next)
                } else {
                    return nil
                }
            case .Separator(.Comma) where depth > 0:
                continue
            default:
                return nil
            }
        }
        guard depth == 0 else { return nil }
        return members
    }
}
