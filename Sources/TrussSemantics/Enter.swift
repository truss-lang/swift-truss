import TrussCore

public final class Enter: AST.Visitor {
    private let context: Context
    private var currentScope: Scope? = nil
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        if let packageSymbol = context.name2Package[program.packageName] {
            program.packageSymbol = packageSymbol
            self.currentScope = packageSymbol.scope
        } else {
            let packageSymbol = Symbol.PackageSymbol(
                id: context.nextSymbolId, name: program.packageName)
            context.register(packageSymbol: packageSymbol)
            program.packageSymbol = packageSymbol
            self.currentScope = packageSymbol.scope
        }
        super.visitProgram(program, additional: additional)
        for symbol in program.packageSymbol!.scope.name2Symbol.values {
            symbol.parent = program.packageSymbol!.id
        }
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        let lastScope = currentScope
        if let moduleSymbol = lastScope!.name2Symbol[moduleDecl.name.value]
            as? Symbol.ModuleSymbol
        {
            moduleDecl.symbol = moduleSymbol
            currentScope = moduleSymbol.scope
        } else {
            let moduleSymbol = Symbol.ModuleSymbol(
                id: context.nextSymbolId, name: moduleDecl.name.value)
            context.register(symbol: moduleSymbol)
            moduleDecl.symbol = moduleSymbol
            lastScope!.name2Symbol[moduleSymbol.name] = moduleSymbol
            currentScope = moduleSymbol.scope
        }
        super.visitModuleDecl(moduleDecl, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
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
        functionDecl.symbol = symbol
        self.currentScope!.name2Symbol[symbol.name] = symbol

        return nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil)
        -> Any?
    {
        super.visitVariableDecl(variableDecl, additional: additional)
        let symbol = Symbol.VariableSymbol(
            id: context.nextSymbolId, name: variableDecl.name.value)
        context.register(symbol: symbol)
        variableDecl.symbol = symbol
        self.currentScope!.name2Symbol[symbol.name] = symbol
        return nil
    }
}
