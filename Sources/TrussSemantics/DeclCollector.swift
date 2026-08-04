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
    override public func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
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
        currentScope = program.packageSymbol!.scope
        super.visitProgram(program, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    override public func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        let lastScope = currentScope
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
        super.visitModuleDecl(moduleDecl, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    override public func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil)
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
    override public func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: structDecl.name.value, kind: Symbol.TypeKind.structDecl
        )
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
    override public func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: classDecl.name.value, kind: Symbol.TypeKind.classDecl
        )
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
    override public func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: enumDecl.name.value, kind: Symbol.TypeKind.enumDecl
        )
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
    override public func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: protocolDecl.name.value,
            kind: Symbol.TypeKind.protocolDecl
        )
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
    override public func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: actorDecl.name.value, kind: Symbol.TypeKind.actorDecl
        )
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
    override public func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional _: Any? = nil)
        -> Any?
    {
        let symbol = Symbol.TypeAliasSymbol(
            id: context.nextSymbolId, name: typeAliasDecl.name.value
        )
        registerTypeSymbol(symbol, at: typeAliasDecl.name)
        typeAliasDecl.symbol = symbol
        return nil
    }

    @discardableResult
    override public func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional _: Any? = nil
    ) -> Any? {
        let symbol = Symbol.NominalTypeSymbol(
            id: context.nextSymbolId, name: associatedTypeDecl.name.value,
            kind: Symbol.TypeKind.protocolDecl
        )
        registerTypeSymbol(symbol, at: associatedTypeDecl.name)
        associatedTypeDecl.symbol = symbol
        return nil
    }

    @discardableResult
    override public func visitFunctionDecl(_: AST.FunctionDecl, additional _: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    override public func visitInitDecl(_: AST.InitDecl, additional _: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    override public func visitSubscriptDecl(
        _: AST.SubscriptDecl, additional _: Any? = nil
    ) -> Any? {
        nil
    }

    @discardableResult
    override public func visitDeinitDecl(_: AST.DeinitDecl, additional _: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    override public func visitVariableDecl(_: AST.VariableDecl, additional _: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    override public func visitEnumCaseDecl(_: AST.EnumCaseDecl, additional _: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    override public func visitExternDecl(_: AST.ExternDecl, additional _: Any? = nil)
        -> Any?
    {
        nil
    }
}
