import SwiftAbstract

public enum AST {
    @abstractClass
    public class AstNode {
    }
    public class Program: AstNode {
        public let id: Id.SourceId
        public let statements: [Statement]
        public init(_ id: Id.SourceId, _ statements: [Statement]) {
            self.id = id
            self.statements = statements
        }
    }
}
