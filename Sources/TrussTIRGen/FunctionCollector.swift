import TrussCore

final class FunctionCollector {
    private let context: Context
    private let gen: GenerationContext

    init(context: Context, gen: GenerationContext) {
        self.context = context
        self.gen = gen
    }

    func collect(in program: AST.Program) {
        collectStatements(program.statements)
    }

    private func cname(_ attributes: [AST.Attribute]) -> String? {
        guard let attribute = attributes.first(where: { $0.name.value == "cname" }) else {
            return nil
        }
        guard attribute.arguments.count == 1 else {
            context.emitError(
                "cname attribute expects exactly one argument", at: attribute.name
            )
            return nil
        }
        return attribute.arguments.first?.first?.value ?? nil
    }

    private func collectStatements(_ statements: [AST.Statement]) {
        for statement in statements {
            switch statement {
            case let decl as AST.FunctionDecl:
                collectFunction(decl)
            case let decl as AST.InitDecl:
                collectInit(decl)
            case let decl as AST.DeinitDecl:
                collectDeinit(decl)
            case let decl as AST.SubscriptDecl:
                collectSubscript(decl)
            case let decl as AST.VariableDecl:
                collectVariable(decl)
                if let symbol = decl.symbol {
                    let isStatic = decl.modifiers.contains { modifier in
                        if case .Static = modifier.kind { return true }
                        return false
                    }
                    if symbol.memberOf == nil || isStatic {
                        createGlobal(decl, symbol: symbol)
                    }
                }
            case let decl as AST.ModuleDecl:
                if let moduleSymbol = decl.symbol {
                    gen.modulePathStack.append(moduleSymbol)
                }
                collectStatements(decl.body)
                if decl.symbol != nil {
                    gen.modulePathStack.removeLast()
                }
            case let decl as AST.ExternDecl:
                gen.externContextStack.append(decl.convention.value)
                switch decl.body {
                case let .Block(statements):
                    collectStatements(statements)
                case let .Declaration(inner):
                    collectStatements([inner])
                }
                gen.externContextStack.removeLast()
            case let decl as AST.StructDecl:
                collectTypeStackPush(decl.symbol)
                collectStatements(decl.body)
                gen.collectTypeStack.removeLast()
            case let decl as AST.ClassDecl:
                collectTypeStackPush(decl.symbol)
                collectStatements(decl.body)
                gen.collectTypeStack.removeLast()
            case let decl as AST.EnumDecl:
                collectTypeStackPush(decl.symbol)
                collectStatements(decl.body)
                gen.collectTypeStack.removeLast()
            case let decl as AST.ActorDecl:
                collectTypeStackPush(decl.symbol)
                collectStatements(decl.body)
                gen.collectTypeStack.removeLast()
            case let decl as AST.ProtocolDecl:
                collectStatements(decl.body)
            case let decl as AST.ExtensionDecl:
                collectStatements(decl.body)
            default:
                break
            }
        }
    }

    private func collectTypeStackPush(_ symbol: Symbol.NominalTypeSymbol?) {
        let resolved = symbol ?? Symbol.StructSymbol(id: Id.SymbolId(0), name: "")
        gen.collectTypeStack.append(resolved)
    }

    private func collectFunction(_ decl: AST.FunctionDecl) {
        guard let symbol = decl.symbol else { return }
        let functionType = symbol.functionType
        let returnType = functionType.map { gen.typeLower.lower($0.returnType) }
            ?? gen.registry.voidType()
        let inExternContext = !gen.externContextStack.isEmpty
        let name = cname(decl.attributes)
            ?? (inExternContext ? decl.name.value : gen.mangler.mangleFunctionName(
                symbol, baseName: decl.name.value,
                returnType: functionType?.returnType ?? TrussType.VoidType.INSTANCE,
                modulePath: gen.modulePathStack
            ))
        createFunction(
            symbol, name: name, returnType: returnType,
            parameters: decl.parameters, symbolType: symbol,
            isVariadic: decl.varargToken != nil,
            isExtern: inExternContext && decl.body == nil,
            callingConvention: inExternContext ? gen.externContextStack.last : nil
        )
    }

    private func collectInit(_ decl: AST.InitDecl) {
        guard let symbol = decl.symbol else { return }
        let initReturnType = symbol.functionType?.returnType ?? TrussType.VoidType.INSTANCE
        let name = cname(decl.attributes) ?? gen.mangler.mangleFunctionName(
            symbol, baseName: "init", returnType: initReturnType,
            modulePath: gen.modulePathStack
        )
        let ownerSymbol = symbol.memberOf.flatMap { context.id2Symbol[$0] } as? Symbol.NominalTypeSymbol
        let initReturnTypeLowered: TIRType.TIRType
        if let ownerSymbol, let typeId = ownerSymbol.typeId, let type = context.typeTable[typeId] {
            let lowered = gen.typeLower.lower(type)
            initReturnTypeLowered = gen.registry.pointerType(pointee: lowered.id)
        } else {
            initReturnTypeLowered = gen.registry.voidType()
        }
        createFunction(
            symbol, name: name, returnType: initReturnTypeLowered,
            parameters: decl.parameters, symbolType: symbol
        )
    }

    private func collectDeinit(_ decl: AST.DeinitDecl) {
        guard let owner = gen.collectTypeStack.last else { return }
        let name = cname(decl.attributes) ?? gen.mangler.mangleDeinitName(
            owner, modulePath: gen.modulePathStack
        )
        let function = createFunction(nil, name: name, returnType: gen.registry.voidType())
        gen.deinitFunctions[ObjectIdentifier(decl)] = function
        gen.deinitOwners[ObjectIdentifier(decl)] = owner
    }

    private func collectSubscript(_ decl: AST.SubscriptDecl) {
        guard let symbol = decl.symbol else { return }
        let getterSymbol = symbol.getter
        let functionType = getterSymbol.functionType
        let returnType = functionType.map { gen.typeLower.lower($0.returnType) }
            ?? gen.registry.voidType()
        let cnameOverride = cname(decl.attributes)
        let name = cnameOverride ?? gen.mangler.mangleFunctionName(
            getterSymbol, baseName: "subscript",
            returnType: functionType?.returnType ?? TrussType.VoidType.INSTANCE,
            modulePath: gen.modulePathStack
        )
        createFunction(
            getterSymbol, name: name, returnType: returnType,
            parameters: decl.parameters, symbolType: getterSymbol
        )
        if let setterSymbol = symbol.setter,
           let owner = ownerSymbol(getterSymbol),
           let ownerType = owner.typeId.flatMap({ context.typeTable[$0] })
        {
            let selfType = gen.typeLower.lower(ownerType)
            let setterReturn = gen.registry.voidType()
            let setterName = cnameOverride.map { $0 + "Setter" }
                ?? gen.mangler.mangleFunctionName(
                    setterSymbol, baseName: "subscriptSetter",
                    returnType: TrussType.VoidType.INSTANCE,
                    modulePath: gen.modulePathStack
                )
            var tirParameters: [TIR.Parameter] = []
            if setterSymbol.kind != .StaticMethod {
                tirParameters.append(TIR.Parameter(ty: selfType.id, name: "self"))
            }
            tirParameters.append(contentsOf: decl.parameters.enumerated().map { index, parameter in
                let ty = setterSymbol.functionType?.parameters[safe: index].map {
                    gen.typeLower.lower($0.type)
                }
                    ?? (parameter.type?.ty).map { gen.typeLower.lower($0) }
                    ?? gen.registry.voidType()
                return TIR.Parameter(ty: ty.id, name: parameter.name.value)
            })
            tirParameters.append(TIR.Parameter(ty: returnType.id, name: "newValue"))
            let setter = gen.currentModule!.addFunction(
                name: setterName, parameters: tirParameters, returnType: setterReturn.id,
                isVariadic: false, isExtern: false, callingConvention: nil
            )
            gen.functionsBySymbol[setterSymbol.id] = setter
        }
    }

    private func ownerSymbol(_ symbol: Symbol.FunctionSymbol) -> Symbol.NominalTypeSymbol? {
        guard let memberOf = symbol.memberOf else { return nil }
        return context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol
    }

    @discardableResult
    private func createFunction(
        _ symbol: Symbol.FunctionSymbol?, name: String, returnType: TIRType.TIRType,
        parameters: [AST.FunctionDecl.Parameter] = [], symbolType: Symbol.FunctionSymbol? = nil,
        isVariadic: Bool = false, isExtern: Bool = false, callingConvention: String? = nil
    ) -> TIR.Function {
        var tirParameters: [TIR.Parameter] = []
        if let memberOf = symbol?.memberOf, (symbol?.kind ?? .StaticMethod) != .StaticMethod,
           let owner = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol,
           let typeId = owner.typeId, let type = context.typeTable[typeId]
        {
            let selfType = gen.registry.pointerType(pointee: gen.typeLower.lower(type).id)
            tirParameters.append(TIR.Parameter(ty: selfType.id, name: "self"))
        }
        tirParameters.append(contentsOf: parameters.enumerated().map { index, parameter in
            let ty = symbolType?.functionType?.parameters[safe: index].map { gen.typeLower.lower($0.type) }
                ?? (parameter.type?.ty).map { gen.typeLower.lower($0) }
                ?? gen.registry.voidType()
            return TIR.Parameter(ty: ty.id, name: parameter.name.value)
        })
        let tirReturnType: TIRType.TIRType
        if let throwsType = throwingErrorType(symbol) {
            let errorType = gen.typeLower.lower(throwsType)
            tirReturnType = gen.registry.tupleType(elements: [
                .init(label: "ok", type: returnType.id),
                .init(label: "err", type: errorType.id),
            ])
        } else {
            tirReturnType = returnType
        }
        let function = gen.currentModule!.addFunction(
            name: name, parameters: tirParameters, returnType: tirReturnType.id,
            isVariadic: isVariadic, isExtern: isExtern, callingConvention: callingConvention
        )
        if let symbol {
            gen.functionsBySymbol[symbol.id] = function
        }
        return function
    }

    private func throwingErrorType(_ symbol: Symbol.FunctionSymbol?) -> TrussType.TrussType? {
        guard symbol?.functionType?.isThrowing == true else { return nil }
        return symbol?.functionType?.throwsTypes.first
    }

    private func collectVariable(_ decl: AST.VariableDecl) {
        guard let symbol = decl.symbol, let memberOf = symbol.memberOf else { return }
        let isStatic = decl.modifiers.contains { modifier in
            if case .Static = modifier.kind { return true }
            return false
        }
        if isStatic {
            gen.staticVariableSymbols.insert(symbol.id)
        }
        collectVariableAccessors(decl, symbol: symbol, isStatic: isStatic)
        _ = memberOf
    }

    private func collectVariableAccessors(
        _ decl: AST.VariableDecl, symbol: Symbol.VariableSymbol, isStatic: Bool
    ) {
        guard let memberOf = symbol.memberOf,
              let owner = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol,
              let ownerType = owner.typeId.flatMap({ context.typeTable[$0] })
        else { return }
        let selfType = gen.typeLower.lower(ownerType)
        let valueType = symbol.type.map { gen.typeLower.lower($0) }
            ?? (decl.initializer?.ty).map { gen.typeLower.lower($0) }
            ?? gen.registry.voidType()
        let cnameOverride = cname(decl.attributes)
        for accessor in decl.accessors {
            guard let accessorSymbol = symbol.accessors[accessor.kind],
                  gen.functionsBySymbol[accessorSymbol.id] == nil
            else { continue }
            let suffix: String
            let returnType: TIRType.TIRType
            var parameters: [TIR.Parameter] = isStatic ? [] : [TIR.Parameter(ty: selfType.id, name: "self")]
            switch accessor.kind {
            case .Get:
                suffix = "Getter"
                returnType = valueType
            case .Set:
                suffix = "Setter"
                returnType = gen.registry.voidType()
                parameters.append(TIR.Parameter(
                    ty: valueType.id, name: accessor.parameterName?.value ?? "newValue"
                ))
            case .WillSet:
                suffix = "WillSet"
                returnType = gen.registry.voidType()
                parameters.append(TIR.Parameter(
                    ty: valueType.id, name: accessor.parameterName?.value ?? "newValue"
                ))
            case .DidSet:
                suffix = "DidSet"
                returnType = gen.registry.voidType()
                parameters.append(TIR.Parameter(
                    ty: valueType.id, name: accessor.parameterName?.value ?? "oldValue"
                ))
            }
            let name = cnameOverride.map { $0 + suffix } ?? gen.mangler.mangleAccessorName(
                symbol, suffix: suffix,
                returnType: accessor.kind == .Get
                    ? (symbol.type ?? TrussType.VoidType.INSTANCE) : TrussType.VoidType.INSTANCE,
                modulePath: gen.modulePathStack
            )
            gen.functionsBySymbol[accessorSymbol.id] = gen.currentModule!.addFunction(
                name: name, parameters: parameters, returnType: returnType.id,
                isVariadic: false, isExtern: false, callingConvention: nil
            )
        }
    }

    private func createGlobal(_ variableDecl: AST.VariableDecl, symbol: Symbol.VariableSymbol) {
        guard let currentModule = gen.currentModule else {
            fatalError("unreachable")
        }
        guard gen.globalsBySymbol[symbol.id] == nil else { return }
        let type = symbol.type.map { gen.typeLower.lower($0) }
            ?? (variableDecl.initializer?.ty).map { gen.typeLower.lower($0) }
            ?? gen.registry.voidType()
        let name = cname(variableDecl.attributes) ?? gen.mangler.mangleGlobalName(
            symbol, modulePath: gen.modulePathStack
        )
        let global = currentModule.addGlobal(
            name: name,
            type: type.id,
            isExtern: !gen.externContextStack.isEmpty && variableDecl.initializer == nil,
            hasInitializer: variableDecl.initializer != nil
        )
        gen.globalsBySymbol[symbol.id] = global
    }
}
