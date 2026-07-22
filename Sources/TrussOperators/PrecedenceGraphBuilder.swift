import TrussCore

public final class PrecedenceGraphBuilder: AST.Visitor {
    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        for statement in program.statements {
            if let decl = statement as? AST.PrecedenceGroupDecl {
                visitPrecedenceGroupDecl(decl, additional: additional)
            }
        }
        return nil
    }
}
