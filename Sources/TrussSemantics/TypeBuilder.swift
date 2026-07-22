import TrussCore

public final class TypeBuilder: AST.Visitor {
    /* his method currently does nothing because Truss doesn't
     * have any custom types yet. All types are built-in types.
     */
    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        return nil
    }
}

