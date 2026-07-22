import TrussCore

public final class Enter: AST.Visitor {
    private let context: Context
    private var currentPackageSymbol: Symbol.PackageSymbol?
    private var currentScope: Scope? = nil
    public init(ctx: Context) {
        self.context = ctx
    }
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        if let packageSymbol = context.name2Package[program.packageName] {
            program.packageSymbol = packageSymbol
            self.currentPackageSymbol = packageSymbol
            self.currentScope = packageSymbol.scope
        } else {
            let packageSymbol = Symbol.PackageSymbol(
                id: context.nextSymbolId, name: program.packageName)
            context.register(packageSymbol: packageSymbol)
            program.packageSymbol = packageSymbol
            self.currentPackageSymbol = packageSymbol
            self.currentScope = packageSymbol.scope
        }
        return super.visitProgram(program, additional: additional)
    }
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil)
        -> Any?
    {
        let lastScope = self.currentScope
        let scope = Scope()
        self.currentScope = scope

        super.visitFunctionDecl(functionDecl, additional: additional)

        self.currentScope = lastScope

        let locals = scope.name2Symbol.values.filter { $0 is Symbol.VariableSymbol }.map {
            $0 as! Symbol.VariableSymbol
        }
        let symbol = Symbol.FunctionSymbol(
            id: context.nextSymbolId, name: functionDecl.name.value, locals: locals,
            scope: scope)
        context.register(symbol: symbol)
        self.currentScope!.name2Symbol[symbol.name] = symbol

        return nil
    }

    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil)
        -> Any?
    {
        super.visitVariableDecl(variableDecl, additional: additional)
        let symbol = Symbol.VariableSymbol(
            id: context.nextSymbolId, name: variableDecl.name.value)
        context.register(symbol: symbol)
        self.currentScope!.name2Symbol[symbol.name] = symbol
        return nil
    }
}
