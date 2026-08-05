import TrussCore

public final class TypeResolver: AST.Visitor {
    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        let name = variable.name.value
        if name == "Void" {
            variable.ty = TrussType.VoidType.INSTANCE
        } else if name == "Never" {
            variable.ty = TrussType.NeverType.INSTANCE
        }
        return nil
    }
}
