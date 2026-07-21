import SwiftAbstract

public enum AST {
    @abstractClass
    public class AstNode {
        @abstract
        public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any?
        @abstractInit
        public init() {}
    }
    public class Program: AstNode {
        public let id: Id.SourceId
        public let statements: [Statement]
        public init(_ id: Id.SourceId, _ statements: [Statement]) {
            self.id = id
            self.statements = statements
        }
        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitProgram(self, additional: additional)
        }
    }
}
