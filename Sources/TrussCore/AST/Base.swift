import SwiftAbstract
import SwiftBetterDiagnostic

public enum AST {
    @abstractClass
    public class AstNode {
        public var sourceRange: SourceRange
        @abstractInit
        public init(_ sourceRange: SourceRange) {
            self.sourceRange = sourceRange
        }

        @abstract
        public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any?
    }

    public final class Program: AstNode {
        public let id: Id.SourceId
        public let packageName: String
        public let statements: [Statement]
        public var packageSymbol: Symbol.PackageSymbol? = nil
        public init(
            _ id: Id.SourceId, _ packageName: String, _ statements: [Statement],
            sourceRange: SourceRange
        ) {
            self.id = id
            self.packageName = packageName
            self.statements = statements
            super.init(sourceRange)
        }

        override public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitProgram(self, additional: additional)
        }
    }

    public final class Attribute {
        public let name: Token
        public let arguments: [[Token]]
        public let labeledArguments: [Token: [Token]]
        public let sourceRange: SourceRange
        public init(
            name: Token, arguments: [[Token]], labeledArguments: [Token: [Token]],
            sourceRange: SourceRange
        ) {
            self.name = name
            self.arguments = arguments
            self.labeledArguments = labeledArguments
            self.sourceRange = sourceRange
        }
    }

    public final class Modifier {
        public let token: Token
        public let kind: ModifierKind
        public let sourceRange: SourceRange
        public init(token: Token, kind: ModifierKind, sourceRange: SourceRange) {
            self.token = token
            self.kind = kind
            self.sourceRange = sourceRange
        }
    }

    public enum ModifierKind {
        case Open(setter: Bool)
        case Public(setter: Bool)
        case Protected(setter: Bool)
        case PackagePrivate(setter: Bool)
        case Internal(setter: Bool)
        case FilePrivate(setter: Bool)
        case Private(setter: Bool)
        case Abstract
        case Final
        case Mutating
        case Nonmutating
        case Convenience
        case Override
        case Static
        case Lazy
        case Weak
        case Unowned
        case Indirect
        case Isolated
        case Async
    }

    public final class GenericDecl: AstNode {
        public let begin: Token
        public let generics: [GenericParameter]
        public let end: Token
        public init(
            _ begin: Token, _ generics: [GenericParameter], _ end: Token, sourceRange: SourceRange
        ) {
            self.begin = begin
            self.generics = generics
            self.end = end
            super.init(sourceRange)
        }

        override public func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitGenericDecl(self, additional: additional)
        }
    }

    public final class GenericParameter: AstNode {
        public let eachToken: Token?
        public let name: Token
        public let constraint: Expression?
        public init(
            _ eachToken: Token? = nil, _ name: Token, _ constraint: Expression?,
            sourceRange: SourceRange
        ) {
            self.eachToken = eachToken
            self.name = name
            self.constraint = constraint
            super.init(sourceRange)
        }

        override public func accept(_ visitor: AST.Visitor, additional: Any? = nil) -> Any? {
            visitor.visitGenericParameter(self, additional: additional)
        }
    }

    public struct WhereRequirement {
        public let left: Expression
        public let constraint: Constraint
        public enum Constraint {
            case conformance(Expression)
            case equality(Expression)
        }

        public init(_ left: Expression, _ constraint: Constraint) {
            self.left = left
            self.constraint = constraint
        }
    }
}
