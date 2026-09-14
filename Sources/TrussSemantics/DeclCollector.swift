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
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil) -> Any? {
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
    public override func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil) -> Any? {
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

    private func makeNominalTypeSymbol(
        _ nominalTypeDecl: AST.NominalTypeDecl
    ) -> Symbol.NominalTypeSymbol {
        let id = context.nextSymbolId
        let name = nominalTypeDecl.name.value
        let symbol: Symbol.NominalTypeSymbol = switch nominalTypeDecl {
        case is AST.ClassDecl:
            Symbol.ClassSymbol(id: id, name: name)
        case is AST.StructDecl:
            Symbol.StructSymbol(id: id, name: name)
        case is AST.EnumDecl:
            Symbol.EnumSymbol(id: id, name: name)
        case is AST.ProtocolDecl:
            Symbol.ProtocolSymbol(id: id, name: name)
        case is AST.ActorDecl:
            Symbol.ActorSymbol(id: id, name: name)
        default:
            fatalError("unreachable: unknown nominal type declaration \(type(of: nominalTypeDecl))")
        }
        symbol.isAbstract = nominalTypeDecl.modifiers.contains {
            if case .Abstract = $0.kind { true } else { false }
        }
        symbol.isFinal = nominalTypeDecl.modifiers.contains {
            if case .Final = $0.kind { true } else { false }
        }
        return symbol
    }

    @discardableResult
    public override func visitNominalTypeDecl(
        _ nominalTypeDecl: AST.NominalTypeDecl, additional: Any? = nil
    ) -> Any? {
        let symbol = makeNominalTypeSymbol(nominalTypeDecl)
        registerTypeSymbol(symbol, at: nominalTypeDecl.name, modifiers: nominalTypeDecl.modifiers)
        nominalTypeDecl.symbol = symbol
        if let genericDecl = nominalTypeDecl.genericDecl {
            for param in genericDecl.generics {
                let genericSymbol = Symbol.GenericParamSymbol(
                    id: context.nextSymbolId, name: param.name.value
                )
                context.register(symbol: genericSymbol)
                symbol.scope.registerType(genericSymbol, at: param.name, context: context)
            }
        }
        let lastScope = currentScope
        currentScope = symbol.scope
        typeStack.append(symbol)
        for statement in nominalTypeDecl.body {
            visit(statement, additional: additional)
        }
        typeStack.removeLast()
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil) -> Any? {
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
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
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
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitEnumCaseDecl(_ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil) -> Any? {
        nil
    }
}
