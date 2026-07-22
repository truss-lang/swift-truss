import TrussCore

public final class NameResolver: AST.Visitor {
    private let context: Context
    private var scopeStack: [Scope] = []
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        scopeStack.append(program.packageSymbol!.scope)
        super.visitProgram(program, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil)
        -> Any?
    {
        scopeStack.append(functionDecl.symbol!.scope)

        super.visitFunctionDecl(functionDecl, additional: additional)

        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        variable.symbol = lookupName(variable.name.value)
        return nil
    }

    private func lookupName(_ name: String) -> Symbol.Symbol? {
        for scope in scopeStack.reversed() {
            if let symbol = scope.name2Symbol[name] {
                return symbol
            }
        }
        return nil
    }
}
