import TrussCore

public final class DeclCollector: AST.Visitor {
    private let context: Context
    private var currentScope: Scope? = nil
    private var currentPackageSymbol: Symbol.PackageSymbol? = nil
    private var currentModuleSymbol: Symbol.ModuleSymbol? = nil
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    public init(context: Context) {
        self.context = context
    }

    private func registerTypeSymbol(
        _ symbol: Symbol.Symbol, at token: Token, modifiers: [AST.Modifier]
    ) {
        AccessExtractor.record(
            symbol, package: currentPackageSymbol, module: currentModuleSymbol
        )
        symbol.memberOf = typeStack.last?.id
        AccessExtractor.apply(to: symbol, modifiers: modifiers, context: context)
        context.register(symbol: symbol)
        currentScope!.registerType(symbol, at: token, context: context)
    }

    private func registerGenericParams(_ genericDecl: AST.GenericDecl?, into scope: Scope) {
        guard let genericDecl else { return }
        for param in genericDecl.generics {
            let symbol = Symbol.GenericParamSymbol(
                id: context.nextSymbolId, name: param.name.value
            )
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
                id: context.nextSymbolId, name: program.packageName
            )
            context.register(packageSymbol: packageSymbol)
            program.packageSymbol = packageSymbol
        }
        let lastScope = currentScope
        let lastPackage = currentPackageSymbol
        let lastModule = currentModuleSymbol
        currentScope = program.packageSymbol!.scope
        currentPackageSymbol = program.packageSymbol
        currentModuleSymbol = nil
        super.visitProgram(program, additional: additional)
        currentScope = lastScope
        currentPackageSymbol = lastPackage
        currentModuleSymbol = lastModule
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        let lastScope = currentScope
        let lastModule = currentModuleSymbol
        if let moduleSymbol = currentScope!.modules[moduleDecl.name.value] {
            moduleDecl.symbol = moduleSymbol
        } else {
            let moduleSymbol = Symbol.ModuleSymbol(
                id: context.nextSymbolId, name: moduleDecl.name.value
            )
            context.register(symbol: moduleSymbol)
            currentScope!.registerModule(moduleSymbol)
            moduleDecl.symbol = moduleSymbol
        }
        currentScope = moduleDecl.symbol!.scope
        currentModuleSymbol = moduleDecl.symbol
        super.visitModuleDecl(moduleDecl, additional: additional)
        currentScope = lastScope
        currentModuleSymbol = lastModule
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
        let symbol = Symbol.StructSymbol(id: context.nextSymbolId, name: structDecl.name.value)
        registerTypeSymbol(symbol, at: structDecl.name, modifiers: structDecl.modifiers)
        structDecl.symbol = symbol
        registerGenericParams(structDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        typeStack.append(symbol)
        for statement in structDecl.body {
            visit(statement, additional: additional)
        }
        typeStack.removeLast()
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.ClassSymbol(id: context.nextSymbolId, name: classDecl.name.value)
        symbol.isAbstract = classDecl.modifiers.contains { modifier in
            if case .Abstract = modifier.kind { return true }
            return false
        }
        symbol.isFinal = classDecl.modifiers.contains { modifier in
            if case .Final = modifier.kind { return true }
            return false
        }
        registerTypeSymbol(symbol, at: classDecl.name, modifiers: classDecl.modifiers)
        classDecl.symbol = symbol
        registerGenericParams(classDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        typeStack.append(symbol)
        for statement in classDecl.body {
            visit(statement, additional: additional)
        }
        typeStack.removeLast()
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.EnumSymbol(id: context.nextSymbolId, name: enumDecl.name.value)
        registerTypeSymbol(symbol, at: enumDecl.name, modifiers: enumDecl.modifiers)
        enumDecl.symbol = symbol
        registerGenericParams(enumDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        typeStack.append(symbol)
        for statement in enumDecl.body {
            visit(statement, additional: additional)
        }
        typeStack.removeLast()
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.ProtocolSymbol(id: context.nextSymbolId, name: protocolDecl.name.value)
        registerTypeSymbol(symbol, at: protocolDecl.name, modifiers: protocolDecl.modifiers)
        protocolDecl.symbol = symbol
        registerGenericParams(protocolDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        typeStack.append(symbol)
        for statement in protocolDecl.body {
            visit(statement, additional: additional)
        }
        typeStack.removeLast()
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.ActorSymbol(id: context.nextSymbolId, name: actorDecl.name.value)
        registerTypeSymbol(symbol, at: actorDecl.name, modifiers: actorDecl.modifiers)
        actorDecl.symbol = symbol
        registerGenericParams(actorDecl.genericDecl, into: symbol.scope)
        let lastScope = currentScope
        currentScope = symbol.scope
        typeStack.append(symbol)
        for statement in actorDecl.body {
            visit(statement, additional: additional)
        }
        typeStack.removeLast()
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.TypeAliasSymbol(
            id: context.nextSymbolId, name: typeAliasDecl.name.value
        )
        registerTypeSymbol(symbol, at: typeAliasDecl.name, modifiers: typeAliasDecl.modifiers)
        typeAliasDecl.symbol = symbol
        return nil
    }

    @discardableResult
    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        let symbol = Symbol.AssociatedTypeSymbol(
            id: context.nextSymbolId, name: associatedTypeDecl.name.value
        )
        registerTypeSymbol(symbol, at: associatedTypeDecl.name, modifiers: associatedTypeDecl.modifiers)
        associatedTypeDecl.symbol = symbol
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    public override func visitEnumCaseDecl(_ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil)
        -> Any?
    {
        nil
    }
}
