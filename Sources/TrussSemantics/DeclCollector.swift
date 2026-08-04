import TrussCore

public final class DeclCollector: AST.Visitor {
    private let context: Context
    private var currentScope: Scope? = nil
    public init(context: Context) {
        self.context = context
    }

    private func registerTypeSymbol(_ symbol: Symbol.Symbol, at token: Token) {
        context.register(symbol: symbol)
        currentScope!.registerType(symbol, at: token, context: context)
    }

    private func registerGenericParams(_ genericDecl: AST.GenericDecl?, into scope: Scope) {
        guard let genericDecl = genericDecl else { return }
        for param in genericDecl.generics {
            let symbol = Symbol.GenericParamSymbol(
                id: context.nextSymbolId, name: param.name.value)
            context.register(symbol: symbol)
            scope.registerType(symbol, at: param.name, context: context)
        }
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        if let packageSymbol = context.name2Package[program.packageName] {
            program.packageSymbol = packageSymbol
        } else {
            let packageSymbol = Symbol.PackageSymbol(
                id: context.nextSymbolId, name: program.packageName)
            context.register(packageSymbol: packageSymbol)
            program.packageSymbol = packageSymbol
        }
        let lastScope = currentScope
        currentScope = program.packageSymbol!.scope
        super.visitProgram(program, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        let lastScope = currentScope
        if let moduleSymbol = currentScope!.modules[moduleDecl.name.value] {
            moduleDecl.symbol = moduleSymbol
        } else {
            let moduleSymbol = Symbol.ModuleSymbol(
                id: context.nextSymbolId, name: moduleDecl.name.value)
            context.register(symbol: moduleSymbol)
            currentScope!.registerModule(moduleSymbol)
            moduleDecl.symbol = moduleSymbol
        }
        currentScope = moduleDecl.symbol!.scope
        super.visitModuleDecl(moduleDecl, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil)
        -> Any?
    {
        if extensionDecl.virtualScope == nil {
            extensionDecl.virtualScope = Scope()
        }
        let lastScope = currentScope
        currentScope = extensionDecl.virtualScope!
        for statement in extensionDecl.body {
            visit(statement, additional: additional)
        }
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: structDecl.name.value)
        registerTypeSymbol(symbol, at: structDecl.name)
        structDecl.symbol = symbol
        registerGenericParams(structDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        for statement in structDecl.body {
            visit(statement, additional: additional)
        }
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: classDecl.name.value)
        registerTypeSymbol(symbol, at: classDecl.name)
        classDecl.symbol = symbol
        registerGenericParams(classDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        for statement in classDecl.body {
            visit(statement, additional: additional)
        }
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: enumDecl.name.value)
        registerTypeSymbol(symbol, at: enumDecl.name)
        enumDecl.symbol = symbol
        registerGenericParams(enumDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        for statement in enumDecl.body {
            visit(statement, additional: additional)
        }
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: protocolDecl.name.value)
        registerTypeSymbol(symbol, at: protocolDecl.name)
        protocolDecl.symbol = symbol
        registerGenericParams(protocolDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        for statement in protocolDecl.body {
            visit(statement, additional: additional)
        }
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: actorDecl.name.value)
        registerTypeSymbol(symbol, at: actorDecl.name)
        actorDecl.symbol = symbol
        registerGenericParams(actorDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        for statement in actorDecl.body {
            visit(statement, additional: additional)
        }
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.TypeAliasSymbol(
            id: context.nextSymbolId, name: typeAliasDecl.name.value)
        registerTypeSymbol(symbol, at: typeAliasDecl.name)
        typeAliasDecl.symbol = symbol
        return nil
    }

    @discardableResult
    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: associatedTypeDecl.name.value)
        registerTypeSymbol(symbol, at: associatedTypeDecl.name)
        associatedTypeDecl.symbol = symbol
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil)
        -> Any?
    {
        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil)
        -> Any?
    {
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil)
        -> Any?
    {
        return nil
    }

    @discardableResult
    public override func visitEnumCaseDecl(_ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil)
        -> Any?
    {
        return nil
    }

    @discardableResult
    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil)
        -> Any?
    {
        return nil
    }
}
