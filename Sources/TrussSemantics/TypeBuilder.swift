import TrussCore

public final class TypeBuilder: AST.Visitor {
    /* This method currently does nothing because Truss doesn't
     * have any custom types yet. All types are built-in types.
     */
    @discardableResult
    override public func visitProgram(_: AST.Program, additional _: Any? = nil) -> Any? {
        nil
    }
}
