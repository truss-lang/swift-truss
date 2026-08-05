import TrussCore

public final class DeclCollector: AST.Visitor {
    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        for statement in program.statements {
            if let decl = statement as? AST.PrecedenceGroupDecl {
                visitPrecedenceGroupDecl(decl, additional: additional)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitPrecedenceGroupDecl(
        _ precedenceGroupDecl: AST.PrecedenceGroupDecl, additional: Any? = nil
    ) -> Any? {
        fatalError()
    }
}
