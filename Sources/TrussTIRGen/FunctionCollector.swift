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
        let name = cname(decl.attributes) ?? gen.mangler.mangleFunctionName(
            symbol, baseName: "init", returnType: TrussType.VoidType.INSTANCE,
            modulePath: gen.modulePathStack
        )
        let function = createFunction(
            symbol, name: name, returnType: gen.registry.voidType(),
            parameters: decl.parameters, symbolType: symbol
        )
        if let memberOf = symbol.memberOf {
            gen.initFunctionsByType[memberOf] = function
        }
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
        let functionType = symbol.functionType
        let returnType = functionType.map { gen.typeLower.lower($0.returnType) }
            ?? gen.registry.voidType()
        let cnameOverride = cname(decl.attributes)
        let name = cnameOverride ?? gen.mangler.mangleFunctionName(
            symbol, baseName: "subscript",
            returnType: functionType?.returnType ?? TrussType.VoidType.INSTANCE,
            modulePath: gen.modulePathStack
        )
        let getter = createFunction(
            symbol, name: name, returnType: returnType,
            parameters: decl.parameters, symbolType: symbol
        )
        var pair = gen.accessorFunctions[symbol.id] ?? AccessorPair()
        pair.getter = getter
        if decl.accessors.contains(where: { $0.kind == .Set }),
           let owner = ownerSymbol(symbol), let ownerType = owner.typeId.flatMap({ context.typeTable[$0] })
        {
            let selfType = gen.typeLower.lower(ownerType)
            let setterReturn = gen.registry.voidType()
            let setterName = cnameOverride.map { $0 + "Setter" }
                ?? gen.mangler.mangleFunctionName(
                    symbol, baseName: "subscriptSetter",
                    returnType: TrussType.VoidType.INSTANCE,
                    modulePath: gen.modulePathStack
                )
            var tirParameters: [TIR.Parameter] = [TIR.Parameter(ty: selfType.id, name: "self")]
            tirParameters.append(contentsOf: decl.parameters.enumerated().map { index, parameter in
                let ty = symbol.functionType?.parameters[safe: index].map { gen.typeLower.lower($0.type) }
                    ?? (parameter.type?.ty).map { gen.typeLower.lower($0) }
                    ?? gen.registry.voidType()
                return TIR.Parameter(ty: ty.id, name: parameter.name.value)
            })
            tirParameters.append(TIR.Parameter(ty: returnType.id, name: "newValue"))
            let setter = gen.currentModule!.addFunction(
                name: setterName, parameters: tirParameters, returnType: setterReturn.id,
                isVariadic: false, isExtern: false, callingConvention: nil
            )
            pair.setter = setter
        }
        gen.accessorFunctions[symbol.id] = pair
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
        if let memberOf = symbol?.memberOf, !(symbol?.isStatic ?? true),
           let owner = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol,
           let typeId = owner.typeId, let type = context.typeTable[typeId]
        {
            let selfType = gen.typeLower.lower(type)
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
                TIRType.TupleType.Element(label: "ok", type: returnType.id),
                TIRType.TupleType.Element(label: "err", type: errorType.id),
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
        var pair = gen.accessorFunctions[symbol.id] ?? AccessorPair()
        for accessor in decl.accessors {
            switch accessor.kind {
            case .Get:
                if pair.getter == nil {
                    let name = cnameOverride ?? gen.mangler.mangleAccessorName(
                        symbol, suffix: "Getter",
                        returnType: symbol.type ?? TrussType.VoidType.INSTANCE,
                        modulePath: gen.modulePathStack
                    )
                    pair.getter = gen.currentModule!.addFunction(
                        name: name,
                        parameters: isStatic ? [] : [TIR.Parameter(ty: selfType.id, name: "self")],
                        returnType: valueType.id,
                        isVariadic: false, isExtern: false, callingConvention: nil
                    )
                }
            case .Set:
                if pair.setter == nil {
                    let name = cnameOverride.map { $0 + "Setter" } ?? gen.mangler.mangleAccessorName(
                        symbol, suffix: "Setter",
                        returnType: TrussType.VoidType.INSTANCE,
                        modulePath: gen.modulePathStack
                    )
                    var parameters: [TIR.Parameter] = isStatic ? [] : [TIR.Parameter(ty: selfType.id, name: "self")]
                    parameters.append(TIR.Parameter(
                        ty: valueType.id,
                        name: accessor.parameterName?.value ?? "newValue"
                    ))
                    pair.setter = gen.currentModule!.addFunction(
                        name: name, parameters: parameters, returnType: gen.registry.voidType().id,
                        isVariadic: false, isExtern: false, callingConvention: nil
                    )
                }
            case .WillSet:
                if pair.willSet == nil {
                    let name = cnameOverride.map { $0 + "WillSet" } ?? gen.mangler.mangleAccessorName(
                        symbol, suffix: "WillSet",
                        returnType: TrussType.VoidType.INSTANCE,
                        modulePath: gen.modulePathStack
                    )
                    var parameters: [TIR.Parameter] = isStatic ? [] : [TIR.Parameter(ty: selfType.id, name: "self")]
                    parameters.append(TIR.Parameter(
                        ty: valueType.id,
                        name: accessor.parameterName?.value ?? "newValue"
                    ))
                    pair.willSet = gen.currentModule!.addFunction(
                        name: name, parameters: parameters, returnType: gen.registry.voidType().id,
                        isVariadic: false, isExtern: false, callingConvention: nil
                    )
                }
            case .DidSet:
                if pair.didSet == nil {
                    let name = cnameOverride.map { $0 + "DidSet" } ?? gen.mangler.mangleAccessorName(
                        symbol, suffix: "DidSet",
                        returnType: TrussType.VoidType.INSTANCE,
                        modulePath: gen.modulePathStack
                    )
                    var parameters: [TIR.Parameter] = isStatic ? [] : [TIR.Parameter(ty: selfType.id, name: "self")]
                    parameters.append(TIR.Parameter(
                        ty: valueType.id,
                        name: accessor.parameterName?.value ?? "oldValue"
                    ))
                    pair.didSet = gen.currentModule!.addFunction(
                        name: name, parameters: parameters, returnType: gen.registry.voidType().id,
                        isVariadic: false, isExtern: false, callingConvention: nil
                    )
                }
            }
        }
        gen.accessorFunctions[symbol.id] = pair
    }

    private func createGlobal(_ variableDecl: AST.VariableDecl, symbol: Symbol.VariableSymbol) {
        guard gen.globalsBySymbol[symbol.id] == nil else { return }
        let type = symbol.type.map { gen.typeLower.lower($0) }
            ?? (variableDecl.initializer?.ty).map { gen.typeLower.lower($0) }
            ?? gen.registry.voidType()
        let name = cname(variableDecl.attributes) ?? gen.mangler.mangleGlobalName(
            symbol, modulePath: gen.modulePathStack
        )
        let global = gen.currentModule!.addGlobal(
            name: name, type: type.id,
            isExtern: !gen.externContextStack.isEmpty && variableDecl.initializer == nil
        )
        gen.globalsBySymbol[symbol.id] = global
    }
}
