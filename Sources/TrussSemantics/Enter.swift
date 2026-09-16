import TrussCore

public final class Enter: AST.Visitor {
    private let context: Context
    private var currentScope: Scope? = nil
    private var currentPackageSymbol: Symbol.PackageSymbol? = nil
    private var currentModuleSymbol: Symbol.ModuleSymbol? = nil
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    private var moduleScope: Scope? = nil
    private var inFunctionBody = 0
    private var inExtension = 0

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        let packageSymbol = program.packageSymbol!
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
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil) -> Any? {
        let moduleSymbol = moduleDecl.symbol!
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
    public override func visitExtensionDecl(
        _ extensionDecl: AST.ExtensionDecl, additional: Any? = nil
    ) -> Any? {
        let virtualScope = extensionDecl.virtualScope!
        let lastScope = currentScope
        currentScope = virtualScope
        inExtension += 1
        for statement in extensionDecl.body {
            visit(statement, additional: additional)
        }
        inExtension -= 1
        currentScope = lastScope
        return nil
    }

    @discardableResult
    public override func visitNominalTypeDecl(
        _ nominalTypeDecl: AST.NominalTypeDecl, additional: Any? = nil
    ) -> Any? {
        let symbol = nominalTypeDecl.symbol!
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
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
        let hasSelf = isMemberImplementation && functionDecl.body != nil
            && !containsStatic(functionDecl.modifiers)
            && !containsAbstract(functionDecl.modifiers)
        let scope = withFunctionBody {
            withScope { scope in
                if hasSelf {
                    registerSelfSymbol(in: scope, at: functionDecl.name)
                }
                registerGenericParams(functionDecl.genericDecl, into: scope)
                for (index, parameter) in functionDecl.parameters.enumerated() {
                    functionDecl.parameters[index].symbol = registerLocal(parameter.name)
                }
                super.visitFunctionDecl(functionDecl, additional: additional)
            }
        }
        let isStatic = containsStatic(functionDecl.modifiers)
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
        let hasSelf = isMemberImplementation && !containsAbstract(initDecl.modifiers)
        let scope = withFunctionBody {
            withScope { scope in
                if hasSelf {
                    registerSelfSymbol(in: scope, at: initDecl.token)
                }
                registerGenericParams(initDecl.genericDecl, into: scope)
                for (index, parameter) in initDecl.parameters.enumerated() {
                    initDecl.parameters[index].symbol = registerLocal(parameter.name)
                }
                super.visitInitDecl(initDecl, additional: additional)
            }
        }
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
        let hasSelf = isMemberImplementation && !containsStatic(subscriptDecl.modifiers)
            && !containsAbstract(subscriptDecl.modifiers)
        let scope = withFunctionBody {
            withScope { scope in
                registerGenericParams(subscriptDecl.genericDecl, into: scope)
                for (index, parameter) in subscriptDecl.parameters.enumerated() {
                    subscriptDecl.parameters[index].symbol = registerLocal(parameter.name)
                }
                super.visitSubscriptDecl(subscriptDecl, additional: additional)
            }
        }
        let isStatic = containsStatic(subscriptDecl.modifiers)
        let kind: Symbol.FunctionSymbol.Kind = isStatic ? .StaticMethod : .Method
        let memberOf = typeStack.last?.id
        let getter = Symbol.FunctionSymbol(
            id: context.nextSymbolId, name: "subscript", locals: locals(of: scope), scope: scope,
            signature: signature(of: subscriptDecl.parameters, isVariadic: false),
            kind: kind
        )
        registerAccessorSymbol(getter, at: subscriptDecl.token, memberOf: memberOf)
        if hasSelf {
            registerSelfSymbol(in: scope, at: subscriptDecl.token)
        }
        let getAccessor = subscriptDecl.accessors.first { $0.kind == .Get }
        let setAccessor = subscriptDecl.accessors.first { $0.kind == .Set }
        let setter: Symbol.FunctionSymbol?
        if let setAccessor {
            let setterScope = setAccessor.scope ?? Scope()
            let valueLabels = subscriptDecl.parameters.map { $0.label?.value } + [nil]
            let accessorSymbol = Symbol.FunctionSymbol(
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
            registerAccessorSymbol(
                accessorSymbol, at: setAccessor.parameterName ?? setAccessor.token,
                memberOf: memberOf
            )
            if hasSelf, let accessorScope = setAccessor.scope {
                registerSelfSymbol(
                    in: accessorScope,
                    at: setAccessor.parameterName ?? setAccessor.token ?? subscriptDecl.token
                )
            }
            setter = accessorSymbol
        } else {
            setter = nil
        }

        let subscriptSymbol = Symbol.SubscriptSymbol(
            id: context.nextSymbolId, getter: getter, setter: setter
        )
        AccessExtractor.apply(
            to: subscriptSymbol, modifiers: subscriptDecl.modifiers, context: context
        )
        subscriptSymbol.memberOf = memberOf
        AccessExtractor.record(
            subscriptSymbol, package: currentPackageSymbol, module: currentModuleSymbol
        )
        subscriptSymbol.sourceToken = subscriptDecl.token
        context.register(symbol: subscriptSymbol)
        currentScope!.values[subscriptSymbol.name, default: []].append(subscriptSymbol)
        getter.access = subscriptSymbol.access
        getter.setterAccess = subscriptSymbol.setterAccess
        getAccessor?.symbol = getter
        if let setter, let setAccessor {
            setter.access = subscriptSymbol.setterAccess ?? subscriptSymbol.access
            setAccessor.symbol = setter
        }

        subscriptDecl.symbol = subscriptSymbol

        return nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil) -> Any? {
        super.visitVariableDecl(variableDecl, additional: additional)
        let kind: Symbol.VariableSymbol.Kind = if inFunctionBody > 0 {
            .Local
        } else if typeStack.last != nil || inExtension > 0 {
            containsStatic(variableDecl.modifiers) ? .StaticProperty : .Property
        } else {
            .Global
        }
        let symbol = Symbol.VariableSymbol(
            kind: kind, id: context.nextSymbolId, name: variableDecl.name.value
        )
        AccessExtractor.apply(to: symbol, modifiers: variableDecl.modifiers, context: context)
        if case .Keyword(.Let) = variableDecl.token.kind {
            symbol.isMutable = false
        }
        symbol.isAbstract = containsAbstract(variableDecl.modifiers)
        symbol.isFinal = variableDecl.modifiers.contains { if case .Final = $0.kind { true } else { false } }
        registerValueSymbol(symbol, at: variableDecl.name)
        variableDecl.symbol = symbol
        let isStatic = containsStatic(variableDecl.modifiers)
        let accessorKind: Symbol.FunctionSymbol.Kind = isStatic ? .StaticMethod : .Method
        for accessor in variableDecl.accessors {
            let scope = accessor.scope ?? Scope()
            let signature: Symbol.FunctionSignature = accessor.kind == .Get
                ? Symbol.FunctionSignature(
                    labels: [], hasDefaults: [], isVararg: [], isVariadic: false
                )
                : Symbol.FunctionSignature(
                    labels: [nil], hasDefaults: [false], isVararg: [false], isVariadic: false
                )
            let accessorSymbol = Symbol.FunctionSymbol(
                id: context.nextSymbolId, name: variableDecl.name.value,
                locals: locals(of: scope), scope: scope, signature: signature, kind: accessorKind
            )
            accessorSymbol.access = accessor.kind == .Get
                ? symbol.access : (symbol.setterAccess ?? symbol.access)
            registerAccessorSymbol(
                accessorSymbol, at: accessor.token ?? accessor.parameterName,
                memberOf: symbol.memberOf
            )
            accessor.symbol = accessorSymbol
            if isMemberImplementation, !isStatic, !containsAbstract(variableDecl.modifiers) {
                registerSelfSymbol(
                    in: scope, at: accessor.token ?? accessor.parameterName ?? variableDecl.name
                )
            }
        }
        return nil
    }

    @discardableResult
    public override func visitAccessor(_ accessor: AST.Accessor, additional: Any? = nil) -> Any? {
        withFunctionBody {
            withScope { scope in
                if accessor.kind != .Get {
                    let name = accessor.parameterName?.value
                        ?? (accessor.kind == .DidSet ? "oldValue" : "newValue")
                    if let token = accessor.parameterName ?? accessor.token {
                        let symbol = Symbol.VariableSymbol(
                            kind: .Local, id: context.nextSymbolId, name: name
                        )
                        context.register(symbol: symbol)
                        scope.registerValue(symbol, at: token, context: context)
                    }
                }
                super.visitAccessor(accessor, additional: additional)
                accessor.scope = scope
            }
        }
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        guard let owner = typeStack.last else {
            context.emitError("deinitializer is not allowed in an extension", at: deinitDecl.token)
            return nil
        }
        let hasSelf = isMemberImplementation && !containsAbstract(deinitDecl.modifiers)
        let scope = withFunctionBody {
            withScope { scope in
                if hasSelf {
                    registerSelfSymbol(in: scope, at: deinitDecl.token)
                }
                super.visitDeinitDecl(deinitDecl, additional: additional)
            }
        }
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
        owner.deinitializer = symbol
        return nil
    }

    @discardableResult
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        withFunctionBody {
            withScope { scope in
                closure.scope = scope
                if let signature = closure.signature {
                    for (index, parameter) in signature.parameters.enumerated() {
                        closure.signature?.parameters[index].symbol = registerLocal(parameter.name)
                    }
                }
                super.visitClosure(closure, additional: additional)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitIf(_ ifExpr: AST.If, additional: Any? = nil) -> Any? {
        withScope { scope in
            ifExpr.scope = scope
            super.visitIf(ifExpr, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStmt: AST.While, additional: Any? = nil) -> Any? {
        withScope { scope in
            whileStmt.scope = scope
            super.visitWhile(whileStmt, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitLoop(_ loopStmt: AST.Loop, additional: Any? = nil) -> Any? {
        withScope { scope in
            loopStmt.scope = scope
            super.visitLoop(loopStmt, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        withScope { scope in
            repeatWhile.scope = scope
            super.visitRepeatWhile(repeatWhile, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStmt: AST.For, additional: Any? = nil) -> Any? {
        withScope { scope in
            forStmt.scope = scope
            if let variable = forStmt.pattern as? AST.Variable {
                registerLocal(variable.name)
            }
            super.visitFor(forStmt, additional: additional)
        }
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
    public override func visitEnumCaseDecl(_ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil) -> Any? {
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
    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        nil
    }

    @discardableResult
    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil) -> Any? {
        if currentScope !== moduleScope {
            context.emitError("extern declaration must be at top level", at: externDecl.token)
            return nil
        }
        return super.visitExternDecl(externDecl, additional: additional)
    }

    private func containsAbstract(_ modifiers: [AST.Modifier]) -> Bool {
        modifiers.contains { if case .Abstract = $0.kind { true } else { false } }
    }

    private func containsStatic(_ modifiers: [AST.Modifier]) -> Bool {
        modifiers.contains { if case .Static = $0.kind { true } else { false } }
    }

    private var isMemberImplementation: Bool {
        inFunctionBody == 0 && (typeStack.last != nil || inExtension > 0)
            && !(typeStack.last is Symbol.ProtocolSymbol)
    }

    private func registerValueSymbol(_ symbol: Symbol.Symbol, at token: Token) {
        AccessExtractor.record(
            symbol, package: currentPackageSymbol, module: currentModuleSymbol
        )
        if inFunctionBody == 0 {
            symbol.memberOf = typeStack.last?.id
        }
        context.register(symbol: symbol)
        currentScope!.registerValue(symbol, at: token, context: context)
    }

    private func registerSelfSymbol(in scope: Scope, at token: Token) {
        let symbol = Symbol.SelfSymbol(kind: .Local, id: context.nextSymbolId, name: "self")
        symbol.memberOf = typeStack.last?.id
        context.register(symbol: symbol)
        scope.registerValue(symbol, at: token, context: context)
    }

    private func registerMemberSymbol(
        _ symbol: Symbol.Symbol, at token: Token, modifiers: [AST.Modifier]
    ) {
        AccessExtractor.apply(to: symbol, modifiers: modifiers, context: context)
        symbol.isAbstract = containsAbstract(modifiers)
        symbol.isFinal = modifiers.contains { if case .Final = $0.kind { true } else { false } }
        registerValueSymbol(symbol, at: token)
    }

    private func registerAccessorSymbol(
        _ symbol: Symbol.FunctionSymbol, at token: Token?, memberOf: Id.SymbolId?
    ) {
        symbol.memberOf = memberOf
        AccessExtractor.record(
            symbol, package: currentPackageSymbol, module: currentModuleSymbol
        )
        symbol.sourceToken = token
        context.register(symbol: symbol)
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
        scope.values.values.flatMap { $0 }.compactMap { $0 as? Symbol.VariableSymbol }
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
        let symbol = Symbol.VariableSymbol(kind: .Local, id: context.nextSymbolId, name: name.value)
        registerValueSymbol(symbol, at: name)
        return symbol
    }

    @discardableResult
    private func withScope(_ body: (Scope) -> Void) -> Scope {
        let scope = Scope()
        let lastScope = currentScope
        currentScope = scope
        body(scope)
        currentScope = lastScope
        return scope
    }

    @discardableResult
    private func withFunctionBody<T>(_ body: () -> T) -> T {
        inFunctionBody += 1
        defer { inFunctionBody -= 1 }
        return body()
    }
}
