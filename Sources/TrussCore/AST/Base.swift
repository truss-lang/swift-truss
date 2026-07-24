import SwiftAbstract
import SwiftBetterDiagnosis

public enum AST {
    @abstractClass
    public class AstNode {
        public var sourceRange: SourceRange? = nil
        @abstractInit
        public init(sourceRange: SourceRange? = nil) {
            self.sourceRange = sourceRange
        }
        @abstract
        public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any?
    }
    public final class Program: AstNode {
        public let id: Id.SourceId
        public let packageName: String
        public let statements: [Statement]
        public weak var packageSymbol: Symbol.PackageSymbol? = nil
        public init(
            _ id: Id.SourceId, _ packageName: String, _ statements: [Statement],
            sourceRange: SourceRange? = nil
        ) {
            self.id = id
            self.packageName = packageName
            self.statements = statements
            super.init(sourceRange: sourceRange)
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
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
        case Lazy
        case Weak
        case Unowned
        case Indirect
    }
}
