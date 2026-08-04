import TrussCore

public final class Enter: AST.Visitor {
    private let context: Context
    private var currentScope: Scope? = nil
    public init(context: Context) {
        self.context = context
    }

    private func registerValueSymbol(_ symbol: Symbol.Symbol, at token: Token) {
        context.register(symbol: symbol)
        currentScope!.registerValue(symbol, at: token, context: context)
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

    private func locals(of scope: Scope) -> [Symbol.VariableSymbol] {
        scope.values.values.flatMap { $0 }.filter { $0 is Symbol.VariableSymbol }.map {
            $0 as! Symbol.VariableSymbol
        }
    }

    private func signature(
        of parameters: [AST.FunctionDecl.Parameter], varargToken: Token?
    ) -> Symbol.FunctionSignature {
        var labels: [String?] = []
        var hasDefaults: [Bool] = []
        var isVararg: [Bool] = []
        for parameter in parameters {
            labels.append(parameter.label?.value)
            hasDefaults.append(parameter.defaultValue != nil)
            isVararg.append(parameter.type is AST.VariadicType)
        }
        if varargToken != nil {
            labels.append(nil)
            hasDefaults.append(false)
            isVararg.append(true)
        }
        return Symbol.FunctionSignature(
            labels: labels, hasDefaults: hasDefaults, isVararg: isVararg)
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        guard let packageSymbol = program.packageSymbol else { return nil }
        let lastScope = currentScope
        currentScope = packageSymbol.scope
        super.visitProgram(program, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        guard let moduleSymbol = moduleDecl.symbol else { return nil }
        let lastScope = currentScope
        currentScope = moduleSymbol.scope
        super.visitModuleDecl(moduleDecl, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil)
        -> Any?
    {
        guard let virtualScope = extensionDecl.virtualScope else { return nil }
        let lastScope = currentScope
        currentScope = virtualScope
        for statement in extensionDecl.body {
            visit(statement, additional: additional)
        }
        currentScope = lastScope
        return nil
    }

    private func visitTypeBody(_ body: [AST.Statement], additional: Any?) {
        for statement in body {
            visit(statement, additional: additional)
        }
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = structDecl.symbol else { return nil }
        let lastScope = currentScope
        currentScope = symbol.scope
        visitTypeBody(structDecl.body, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = classDecl.symbol else { return nil }
        let lastScope = currentScope
        currentScope = symbol.scope
        visitTypeBody(classDecl.body, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = enumDecl.symbol else { return nil }
        let lastScope = currentScope
        currentScope = symbol.scope
        visitTypeBody(enumDecl.body, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = protocolDecl.symbol else { return nil }
        let lastScope = currentScope
        currentScope = symbol.scope
        visitTypeBody(protocolDecl.body, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = actorDecl.symbol else { return nil }
        let lastScope = currentScope
        currentScope = symbol.scope
        visitTypeBody(actorDecl.body, additional: additional)
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

        registerGenericParams(functionDecl.genericDecl, into: scope)
        super.visitFunctionDecl(functionDecl, additional: additional)

        self.currentScope = lastScope

        let symbol = Symbol.FunctionSymbol(
            id: context.nextSymbolId, name: functionDecl.name.value, locals: locals(of: scope),
            scope: scope,
            signature: signature(
                of: functionDecl.parameters, varargToken: functionDecl.varargToken))
        context.register(symbol: symbol)
        functionDecl.symbol = symbol
        currentScope!.registerValue(symbol, at: functionDecl.name, context: context)

        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        let lastScope = self.currentScope
        let scope = Scope()
        self.currentScope = scope

        registerGenericParams(initDecl.genericDecl, into: scope)
        super.visitInitDecl(initDecl, additional: additional)

        self.currentScope = lastScope

        let symbol = Symbol.FunctionSymbol(
            id: context.nextSymbolId, name: "init", locals: locals(of: scope), scope: scope,
            signature: signature(of: initDecl.parameters, varargToken: nil))
        context.register(symbol: symbol)
        initDecl.symbol = symbol
        currentScope!.registerValue(symbol, at: initDecl.token, context: context)

        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        let lastScope = self.currentScope
        let scope = Scope()
        self.currentScope = scope

        registerGenericParams(subscriptDecl.genericDecl, into: scope)
        super.visitSubscriptDecl(subscriptDecl, additional: additional)

        self.currentScope = lastScope

        let symbol = Symbol.FunctionSymbol(
            id: context.nextSymbolId, name: "subscript", locals: locals(of: scope), scope: scope,
            signature: signature(of: subscriptDecl.parameters, varargToken: nil))
        context.register(symbol: symbol)
        subscriptDecl.symbol = symbol
        currentScope!.registerValue(symbol, at: subscriptDecl.token, context: context)

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
        currentScope!.registerValue(symbol, at: variableDecl.name, context: context)
        return nil
    }

    @discardableResult
    public override func visitEnumCaseDecl(_ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil)
        -> Any?
    {
        for element in enumCaseDecl.elements {
            let symbol = Symbol.CaseSymbol(
                id: context.nextSymbolId, name: element.name.value)
            context.register(symbol: symbol)
            currentScope!.registerValue(symbol, at: element.name, context: context)
            enumCaseDecl.symbols.append(symbol)
        }
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil)
        -> Any?
    {
        return nil
    }

    @discardableResult
    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        return nil
    }
}
