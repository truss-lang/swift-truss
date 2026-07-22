import SwiftAbstract
import TrussDiagnosis

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
    public class Program: AstNode {
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
}
