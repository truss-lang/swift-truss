import TrussCore

public final class Enter: AST.Visitor {
    private let context: Context
    private var currentScope: Scope? = nil
    private var currentPackageSymbol: Symbol.PackageSymbol? = nil
    private var currentModuleSymbol: Symbol.ModuleSymbol? = nil
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    private var moduleScope: Scope? = nil
    public init(context: Context) {
        self.context = context
    }

    private func registerValueSymbol(_ symbol: Symbol.Symbol, at token: Token) {
        AccessExtractor.record(
            symbol, package: currentPackageSymbol, module: currentModuleSymbol
        )
        symbol.memberOf = typeStack.last?.id
        context.register(symbol: symbol)
        currentScope!.registerValue(symbol, at: token, context: context)
    }

    private func registerMemberSymbol(
        _ symbol: Symbol.Symbol, at token: Token, modifiers: [AST.Modifier]
    ) {
        AccessExtractor.apply(to: symbol, modifiers: modifiers, context: context)
        symbol.isAbstract = modifiers.contains { modifier in
            if case .Abstract = modifier.kind { return true }
            return false
        }
        symbol.isFinal = modifiers.contains { modifier in
            if case .Final = modifier.kind { return true }
            return false
        }
        registerValueSymbol(symbol, at: token)
    }

    private func registerSubscriptSymbol(
        _ symbol: Symbol.SubscriptSymbol, at token: Token, modifiers: [AST.Modifier]
    ) {
        AccessExtractor.apply(to: symbol, modifiers: modifiers, context: context)
        symbol.memberOf = typeStack.last?.id
        AccessExtractor.record(
            symbol, package: currentPackageSymbol, module: currentModuleSymbol
        )
        symbol.sourceToken = token
        context.register(symbol: symbol)
        currentScope!.values[symbol.name, default: []].append(symbol)
    }

    private func registerAccessorSymbol(
        _ symbol: Symbol.FunctionSymbol, at token: Token?, of owner: Symbol.Symbol
    ) {
        symbol.memberOf = owner.memberOf
        AccessExtractor.record(
            symbol, package: currentPackageSymbol, module: currentModuleSymbol
        )
        symbol.sourceToken = token
        context.register(symbol: symbol)
    }

    private func accessorSignature(_ accessor: AST.Accessor) -> Symbol.FunctionSignature {
        if accessor.kind == .Get {
            return Symbol.FunctionSignature(
                labels: [], hasDefaults: [], isVararg: [], isVariadic: false
            )
        }
        return Symbol.FunctionSignature(
            labels: [nil], hasDefaults: [false], isVararg: [false], isVariadic: false
        )
    }

    private func registerAccessorSymbols(
        _ variableDecl: AST.VariableDecl, of owner: Symbol.VariableSymbol
    ) {
        let kind: Symbol.FunctionSymbol.Kind = variableDecl.modifiers.contains { modifier in
            if case .Static = modifier.kind { return true }
            return false
        } ? .StaticMethod : .Method
        for accessor in variableDecl.accessors {
            let scope = accessor.scope ?? Scope()
            let symbol = Symbol.FunctionSymbol(
                id: context.nextSymbolId, name: variableDecl.name.value,
                locals: locals(of: scope), scope: scope,
                signature: accessorSignature(accessor), kind: kind
            )
            symbol.access = accessor.kind == .Get
                ? owner.access : (owner.setterAccess ?? owner.access)
            registerAccessorSymbol(
                symbol, at: accessor.token ?? accessor.parameterName, of: owner
            )
            accessor.symbol = symbol
        }
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

    private func locals(of scope: Scope) -> [Symbol.VariableSymbol] {
        scope.values.values.flatMap { $0 }.filter { $0 is Symbol.VariableSymbol }.map {
            $0 as! Symbol.VariableSymbol
        }
    }

    private func signature(
        of parameters: [AST.FunctionDecl.Parameter], isVariadic: Bool
    ) -> Symbol.FunctionSignature {
        var labels: [String?] = []
        var hasDefaults: [Bool] = []
        var isVararg: [Bool] = []
        for parameter in parameters {
            labels.append(parameter.label?.value)
            hasDefaults.append(parameter.defaultValue != nil)
            isVararg.append(parameter.type is AST.VariadicType)
        }
        return Symbol.FunctionSignature(
            labels: labels, hasDefaults: hasDefaults, isVararg: isVararg, isVariadic: isVariadic
        )
    }

    @discardableResult
    private func registerLocal(_ name: Token) -> Symbol.VariableSymbol {
        let symbol = Symbol.VariableSymbol(id: context.nextSymbolId, name: name.value)
        registerValueSymbol(symbol, at: name)
        return symbol
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        guard let packageSymbol = program.packageSymbol else { return nil }
        let lastScope = currentScope
        let lastPackage = currentPackageSymbol
        let lastModule = currentModuleSymbol
        let lastModuleScope = moduleScope
        currentScope = packageSymbol.scope
        currentPackageSymbol = packageSymbol
        currentModuleSymbol = nil
        moduleScope = packageSymbol.scope
        super.visitProgram(program, additional: additional)
        currentScope = lastScope
        currentPackageSymbol = lastPackage
        currentModuleSymbol = lastModule
        moduleScope = lastModuleScope
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        guard let moduleSymbol = moduleDecl.symbol else { return nil }
        let lastScope = currentScope
        let lastModule = currentModuleSymbol
        let lastModuleScope = moduleScope
        currentScope = moduleSymbol.scope
        currentModuleSymbol = moduleSymbol
        moduleScope = moduleSymbol.scope
        super.visitModuleDecl(moduleDecl, additional: additional)
        currentScope = lastScope
        currentModuleSymbol = lastModule
        moduleScope = lastModuleScope
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
        typeStack.append(symbol)
        visitTypeBody(structDecl.body, additional: additional)
        typeStack.removeLast()
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
        typeStack.append(symbol)
        visitTypeBody(classDecl.body, additional: additional)
        typeStack.removeLast()
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
        typeStack.append(symbol)
        visitTypeBody(enumDecl.body, additional: additional)
        typeStack.removeLast()
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
        typeStack.append(symbol)
        visitTypeBody(protocolDecl.body, additional: additional)
        typeStack.removeLast()
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
        typeStack.append(symbol)
        visitTypeBody(actorDecl.body, additional: additional)
        typeStack.removeLast()
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil)
        -> Any?
    {
        let lastScope = currentScope
        let scope = Scope()
        currentScope = scope

        registerGenericParams(functionDecl.genericDecl, into: scope)
        for (index, parameter) in functionDecl.parameters.enumerated() {
            let symbol = registerLocal(parameter.name)
            functionDecl.parameters[index].symbol = symbol
        }
        super.visitFunctionDecl(functionDecl, additional: additional)

        currentScope = lastScope

        let isStatic = functionDecl.modifiers.contains { modifier in
            if case .Static = modifier.kind { return true }
            return false
        }
        let kind: Symbol.FunctionSymbol.Kind = if isStatic {
            .StaticMethod
        } else if typeStack.last != nil {
            .Method
        } else {
            .Function
        }
        let symbol = Symbol.FunctionSymbol(
            id: context.nextSymbolId,
            name: functionDecl.name.value,
            locals: locals(of: scope),
            scope: scope,
            signature: signature(
                of: functionDecl.parameters,
                isVariadic: functionDecl.varargToken != nil
            ),
            kind: kind,
        )
        registerMemberSymbol(symbol, at: functionDecl.name, modifiers: functionDecl.modifiers)
        functionDecl.symbol = symbol

        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        let lastScope = currentScope
        let scope = Scope()
        currentScope = scope

        registerGenericParams(initDecl.genericDecl, into: scope)
        for (index, parameter) in initDecl.parameters.enumerated() {
            let symbol = registerLocal(parameter.name)
            initDecl.parameters[index].symbol = symbol
        }
        super.visitInitDecl(initDecl, additional: additional)

        currentScope = lastScope

        let symbol = Symbol.FunctionSymbol(
            id: context.nextSymbolId,
            name: "init",
            locals: locals(of: scope),
            scope: scope,
            signature: signature(of: initDecl.parameters, isVariadic: false),
            kind: .Initializer
        )
        registerMemberSymbol(symbol, at: initDecl.token, modifiers: initDecl.modifiers)
        initDecl.symbol = symbol
        typeStack.last?.initializers.append(symbol)

        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        let lastScope = currentScope
        let scope = Scope()
        currentScope = scope

        registerGenericParams(subscriptDecl.genericDecl, into: scope)
        for (index, parameter) in subscriptDecl.parameters.enumerated() {
            let symbol = registerLocal(parameter.name)
            subscriptDecl.parameters[index].symbol = symbol
        }
        super.visitSubscriptDecl(subscriptDecl, additional: additional)

        currentScope = lastScope

        let kind: Symbol.FunctionSymbol.Kind = subscriptDecl.modifiers.contains { modifier in
            if case .Static = modifier.kind { return true }
            return false
        } ? .StaticMethod : .Method
        let getter = Symbol.FunctionSymbol(
            id: context.nextSymbolId, name: "subscript", locals: locals(of: scope), scope: scope,
            signature: signature(of: subscriptDecl.parameters, isVariadic: false),
            kind: kind
        )
        let getAccessor = subscriptDecl.accessors.first { $0.kind == .Get }
        let setAccessor = subscriptDecl.accessors.first { $0.kind == .Set }
        let setter: Symbol.FunctionSymbol?
        if let setAccessor {
            let setterScope = setAccessor.scope ?? Scope()
            let valueLabels = subscriptDecl.parameters.map { $0.label?.value } + [nil]
            setter = Symbol.FunctionSymbol(
                id: context.nextSymbolId, name: "subscript",
                locals: locals(of: setterScope), scope: setterScope,
                signature: Symbol.FunctionSignature(
                    labels: valueLabels,
                    hasDefaults: [Bool](repeating: false, count: valueLabels.count),
                    isVararg: [Bool](repeating: false, count: valueLabels.count),
                    isVariadic: false
                ),
                kind: kind
            )
        } else {
            setter = nil
        }

        let subscriptSymbol = Symbol.SubscriptSymbol(
            id: context.nextSymbolId, getter: getter, setter: setter
        )
        registerSubscriptSymbol(
            subscriptSymbol, at: subscriptDecl.token, modifiers: subscriptDecl.modifiers
        )
        getter.access = subscriptSymbol.access
        getter.setterAccess = subscriptSymbol.setterAccess
        registerAccessorSymbol(getter, at: subscriptDecl.token, of: subscriptSymbol)
        getAccessor?.symbol = getter
        if let setter, let setAccessor {
            setter.access = subscriptSymbol.setterAccess ?? subscriptSymbol.access
            registerAccessorSymbol(
                setter, at: setAccessor.parameterName ?? setAccessor.token, of: subscriptSymbol
            )
            setAccessor.symbol = setter
        }

        subscriptDecl.symbol = subscriptSymbol

        return nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil)
        -> Any?
    {
        super.visitVariableDecl(variableDecl, additional: additional)
        let symbol = Symbol.VariableSymbol(id: context.nextSymbolId, name: variableDecl.name.value)
        AccessExtractor.apply(to: symbol, modifiers: variableDecl.modifiers, context: context)
        if case .Keyword(.Let) = variableDecl.token.kind {
            symbol.isMutable = false
        }
        symbol.isAbstract = variableDecl.modifiers.contains { modifier in
            if case .Abstract = modifier.kind { return true }
            return false
        }
        symbol.isFinal = variableDecl.modifiers.contains { modifier in
            if case .Final = modifier.kind { return true }
            return false
        }
        registerValueSymbol(symbol, at: variableDecl.name)
        variableDecl.symbol = symbol
        registerAccessorSymbols(variableDecl, of: symbol)
        return nil
    }

    @discardableResult
    public override func visitAccessor(_ accessor: AST.Accessor, additional: Any? = nil)
        -> Any?
    {
        let lastScope = currentScope
        let scope = Scope()
        currentScope = scope
        if accessor.kind != .Get {
            let name = accessor.parameterName?.value
                ?? (accessor.kind == .DidSet ? "oldValue" : "newValue")
            if let token = accessor.parameterName ?? accessor.token {
                let symbol = Symbol.VariableSymbol(id: context.nextSymbolId, name: name)
                context.register(symbol: symbol)
                currentScope!.registerValue(symbol, at: token, context: context)
            }
        }
        super.visitAccessor(accessor, additional: additional)
        currentScope = lastScope
        accessor.scope = scope
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil)
        -> Any?
    {
        let lastScope = currentScope
        let scope = Scope()
        currentScope = scope
        super.visitDeinitDecl(deinitDecl, additional: additional)
        currentScope = lastScope
        deinitDecl.scope = scope
        let symbol = Symbol.FunctionSymbol(
            id: context.nextSymbolId,
            name: "deinit",
            locals: [],
            scope: scope,
            signature: Symbol.FunctionSignature(
                labels: [], hasDefaults: [], isVararg: [], isVariadic: false
            ),
            kind: .Deinitializer
        )
        registerMemberSymbol(symbol, at: deinitDecl.token, modifiers: deinitDecl.modifiers)
        typeStack.last?.deinitializer = symbol
        return nil
    }

    @discardableResult
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        let lastScope = currentScope
        let scope = Scope()
        currentScope = scope
        closure.scope = scope
        if let signature = closure.signature {
            for parameter in signature.parameters {
                registerLocal(parameter.name)
            }
        }
        super.visitClosure(closure, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitIf(_ ifExpr: AST.If, additional: Any? = nil) -> Any? {
        let scope = Scope()
        ifExpr.scope = scope
        let lastScope = currentScope
        currentScope = scope
        super.visitIf(ifExpr, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStmt: AST.While, additional: Any? = nil) -> Any? {
        let scope = Scope()
        whileStmt.scope = scope
        let lastScope = currentScope
        currentScope = scope
        super.visitWhile(whileStmt, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitLoop(_ loopStmt: AST.Loop, additional: Any? = nil) -> Any? {
        let scope = Scope()
        loopStmt.scope = scope
        let lastScope = currentScope
        currentScope = scope
        super.visitLoop(loopStmt, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        let scope = Scope()
        repeatWhile.scope = scope
        let lastScope = currentScope
        currentScope = scope
        super.visitRepeatWhile(repeatWhile, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStmt: AST.For, additional: Any? = nil) -> Any? {
        let scope = Scope()
        forStmt.scope = scope
        let lastScope = currentScope
        currentScope = scope
        if let variable = forStmt.pattern as? AST.Variable {
            registerLocal(variable.name)
        }
        super.visitFor(forStmt, additional: additional)
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitOptionalBinding(
        _ optionalBinding: AST.OptionalBinding, additional: Any? = nil
    ) -> Any? {
        registerLocal(optionalBinding.name)
        return super.visitOptionalBinding(optionalBinding, additional: additional)
    }

    @discardableResult
    public override func visitBindingPattern(
        _ bindingPattern: AST.BindingPattern, additional: Any? = nil
    ) -> Any? {
        registerLocal(bindingPattern.name)
        return super.visitBindingPattern(bindingPattern, additional: additional)
    }

    @discardableResult
    public override func visitAsPattern(
        _ asPattern: AST.AsPattern, additional: Any? = nil
    ) -> Any? {
        if let binding = asPattern.pattern as? AST.BindingPattern {
            registerLocal(binding.name)
        } else if let variable = asPattern.pattern as? AST.Variable {
            registerLocal(variable.name)
        }
        return super.visitAsPattern(asPattern, additional: additional)
    }

    @discardableResult
    public override func visitEnumCaseDecl(_ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil)
        -> Any?
    {
        for element in enumCaseDecl.elements {
            let symbol = Symbol.CaseSymbol(
                id: context.nextSymbolId, name: element.name.value
            )
            registerMemberSymbol(
                symbol, at: element.name, modifiers: enumCaseDecl.modifiers
            )
            enumCaseDecl.symbols.append(symbol)
        }
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil)
        -> Any?
    {
        nil
    }

    @discardableResult
    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        nil
    }

    @discardableResult
    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil)
        -> Any?
    {
        if currentScope !== moduleScope {
            context.emitError("extern declaration must be at top level", at: externDecl.token)
            return nil
        }
        return super.visitExternDecl(externDecl, additional: additional)
    }
}
