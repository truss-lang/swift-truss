import SwiftBetterDiagnostic
import TrussCore

public final class TIRGen: AST.Visitor {
    private let context: Context
    private let typeLower: TypeLower
    private var module = TIR.Module()
    private var builder: TIRBuilder? = nil
    private var functionsBySymbol: [Id.SymbolId: TIR.Function] = [:]
    private var env: [Id.SymbolId: TIR.Value] = [:]
    private var capturedCells: Set<Id.SymbolId> = []
    private var breakStack: [BreakTarget] = []
    private var deferStack: [[AST.Statement]] = []
    private var errorTargets: [ErrorTarget] = []
    private var closureParamValues: [[TIR.Value]] = []
    private var closureCounter = 0
    private var semanticScopes: [Scope] = []
    private var pendingLoopLabel: String? = nil
    private var labelBlocks: [String: TIR.BasicBlock] = [:]
    private var globalsBySymbol: [Id.SymbolId: TIR.GlobalVariable] = [:]
    private var globalNamesBySymbol: [Id.SymbolId: String] = [:]
    private var propertyInitializers: [Id.SymbolId: [(Symbol.VariableSymbol, AST.Expression)]] = [:]
    private var accessorFunctions: [Id.SymbolId: [String: TIR.Function]] = [:]
    private var initFunctionsByType: [Id.SymbolId: TIR.Function] = [:]
    private var deinitFunctions: [ObjectIdentifier: TIR.Function] = [:]
    private var deinitOwners: [ObjectIdentifier: Symbol.NominalTypeSymbol] = [:]
    private var deinitFunctionsByType: [Id.TypeId: TIR.Function] = [:]
    private var scopeStack: [[LocalBinding]] = []
    private var staticVariableSymbols: Set<Id.SymbolId> = []
    private var collectTypeStack: [Symbol.NominalTypeSymbol] = []
    private var modulePathStack: [Symbol.ModuleSymbol] = []
    private var externContextDepth = 0

    private struct BreakTarget {
        let label: String?
        let breakBlock: TIR.BasicBlock
        let continueBlock: TIR.BasicBlock?
        let scopeDepth: Int
    }

    private struct LocalBinding {
        let symbol: Id.SymbolId
        let type: TIRType.TIRType
        let address: TIR.Value
    }

    private struct ErrorTarget {
        let block: TIR.BasicBlock
        let scopeDepth: Int
    }

    public init(context: Context) {
        self.context = context
        typeLower = TypeLower(context: context)
    }

    public func generate(_ program: AST.Program) -> TIR.Module {
        generateAll([program])[0]
    }

    public func generateAll(_ programs: [AST.Program]) -> [TIR.Module] {
        functionsBySymbol = [:]
        globalNamesBySymbol = [:]
        staticVariableSymbols = []
        deinitFunctionsByType = [:]
        var modules: [TIR.Module] = []
        for program in programs {
            let programModule = TIR.Module()
            modules.append(programModule)
            module = programModule
            collectFunctions(in: program)
        }
        for _ in 0 ..< 2 {
            for (index, program) in programs.enumerated() {
                module = modules[index]
                collectGlobalInitializers(in: program)
            }
        }
        for (index, program) in programs.enumerated() {
            module = modules[index]
            builder = nil
            env = [:]
            capturedCells = []
            breakStack = []
            deferStack = []
            errorTargets = []
            closureParamValues = []
            scopeStack = []
            semanticScopes = []
            pendingLoopLabel = nil
            labelBlocks = [:]
            visitProgram(program)
        }
        return modules
    }

    private func collectGlobalInitializers(in program: AST.Program) {
        for statement in program.statements {
            collectGlobalInitializerStatements([statement])
        }
    }

    private func collectGlobalInitializerStatements(_ statements: [AST.Statement]) {
        for statement in statements {
            switch statement {
            case let decl as AST.VariableDecl:
                if let symbol = decl.symbol {
                    let isStatic = decl.modifiers.contains { modifier in
                        if case .Static = modifier.kind { return true }
                        return false
                    }
                    if symbol.memberOf == nil || isStatic {
                        lowerGlobalInitializer(decl, symbol: symbol)
                    }
                }
            case let decl as AST.ModuleDecl:
                collectGlobalInitializerStatements(decl.body)
            default:
                break
            }
        }
    }

    private func collectFunctions(in program: AST.Program) {
        collectStatements(program.statements)
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
                    modulePathStack.append(moduleSymbol)
                }
                collectStatements(decl.body)
                if decl.symbol != nil {
                    modulePathStack.removeLast()
                }
            case let decl as AST.ExternDecl:
                externContextDepth += 1
                switch decl.body {
                case let .Block(statements):
                    collectStatements(statements)
                case let .Declaration(inner):
                    collectStatements([inner])
                }
                externContextDepth -= 1
            case let decl as AST.StructDecl:
                collectTypeStack.append(decl.symbol ?? Symbol.StructSymbol(id: Id.SymbolId(id: 0), name: ""))
                collectStatements(decl.body)
                collectTypeStack.removeLast()
            case let decl as AST.ClassDecl:
                collectTypeStack.append(decl.symbol ?? Symbol.ClassSymbol(id: Id.SymbolId(id: 0), name: ""))
                collectStatements(decl.body)
                collectTypeStack.removeLast()
            case let decl as AST.EnumDecl:
                collectTypeStack.append(decl.symbol ?? Symbol.EnumSymbol(id: Id.SymbolId(id: 0), name: ""))
                collectStatements(decl.body)
                collectTypeStack.removeLast()
            case let decl as AST.ActorDecl:
                collectTypeStack.append(decl.symbol ?? Symbol.ActorSymbol(id: Id.SymbolId(id: 0), name: ""))
                collectStatements(decl.body)
                collectTypeStack.removeLast()
            case let decl as AST.ProtocolDecl:
                collectStatements(decl.body)
            case let decl as AST.ExtensionDecl:
                collectStatements(decl.body)
            default:
                break
            }
        }
    }

    private func collectFunction(_ decl: AST.FunctionDecl) {
        guard let symbol = decl.symbol else { return }
        let functionType = symbol.functionType
        let returnType = functionType.map { typeLower.lower($0.returnType) } ?? TIRType.VoidType()
        let throwsTypes = functionType?.throwsTypes.map { typeLower.lower($0) } ?? []
        let name = cname(decl.attributes)
            ?? (externContextDepth > 0 ? decl.name.value : mangleFunctionName(
                symbol, baseName: decl.name.value,
                returnType: functionType?.returnType ?? TrussType.VoidType.INSTANCE
            ))
        createFunction(
            symbol, name: name,
            returnType: returnType,
            isVariadic: decl.varargToken != nil,
            isAsync: decl.asyncToken != nil,
            isThrowing: functionType?.isThrowing ?? false,
            throwsTypes: throwsTypes
        )
    }

    private func collectInit(_ decl: AST.InitDecl) {
        guard let symbol = decl.symbol else { return }
        let throwsTypes = symbol.functionType?.throwsTypes.map { typeLower.lower($0) } ?? []
        let name = if let cname = cname(decl.attributes) {
            cname
        } else {
            mangleFunctionName(
                symbol, baseName: "init",
                returnType: TrussType.VoidType.INSTANCE
            )
        }
        let function = createFunction(
            symbol, name: name,
            returnType: TIRType.VoidType(),
            isAsync: decl.asyncToken != nil,
            isThrowing: symbol.functionType?.isThrowing ?? false,
            throwsTypes: throwsTypes
        )
        if let memberOf = symbol.memberOf {
            initFunctionsByType[memberOf] = function
        }
    }

    private func collectDeinit(_ decl: AST.DeinitDecl) {
        guard let owner = collectTypeStack.last else { return }
        let name = if let cname = cname(decl.attributes) {
            cname
        } else {
            mangleDeinitName(owner)
        }
        let function = createFunction(
            nil, name: name, returnType: TIRType.VoidType()
        )
        deinitFunctions[ObjectIdentifier(decl)] = function
        deinitOwners[ObjectIdentifier(decl)] = owner
        if let typeId = owner.typeId {
            deinitFunctionsByType[typeId] = function
        }
    }

    private func mangleDeinitName(_ owner: Symbol.NominalTypeSymbol) -> String {
        var result = "$t"
        result += mangleIdentifier("main")
        for moduleSymbol in modulePathStack {
            result += mangleIdentifier(moduleSymbol.name)
        }
        result += "_"
        result += mangleIdentifier(owner.name)
        result += "_"
        result += mangleIdentifier("deinit")
        result += "_"
        result += mangleIdentifier("Void")
        return result
    }

    private func collectSubscript(_ decl: AST.SubscriptDecl) {
        guard let symbol = decl.symbol else { return }
        let functionType = symbol.functionType
        let returnType = functionType.map { typeLower.lower($0.returnType) } ?? TIRType.VoidType()
        let throwsTypes = functionType?.throwsTypes.map { typeLower.lower($0) } ?? []
        let name = if let cname = cname(decl.attributes) {
            cname
        } else {
            mangleFunctionName(
                symbol, baseName: "subscript",
                returnType: functionType?.returnType ?? TrussType.VoidType.INSTANCE
            )
        }
        createFunction(
            symbol, name: name,
            returnType: returnType,
            isAsync: decl.asyncToken != nil, isThrowing: functionType?.isThrowing ?? false,
            throwsTypes: throwsTypes
        )
    }

    private func collectVariable(_ decl: AST.VariableDecl) {
        guard let symbol = decl.symbol else { return }
        let isStatic = decl.modifiers.contains { modifier in
            if case .Static = modifier.kind { return true }
            return false
        }
        if isStatic {
            staticVariableSymbols.insert(symbol.id)
        }
        if symbol.memberOf == nil || isStatic, decl.accessors.isEmpty {
            globalNamesBySymbol[symbol.id] = cname(decl.attributes)
                ?? (externContextDepth > 0 ? decl.name.value : mangleGlobalName(symbol))
        }
        guard !decl.accessors.isEmpty else { return }
        let propertyType = symbol.type.map { typeLower.lower($0) } ?? TIRType.VoidType()
        for accessor in decl.accessors {
            let (kindName, suffix): (String, String)
            switch accessor.kind {
            case .Get:
                kindName = "get"
                suffix = "Getter"
            case .Set:
                kindName = "set"
                suffix = "Setter"
            case .WillSet:
                kindName = "willSet"
                suffix = "WillSet"
            case .DidSet:
                kindName = "didSet"
                suffix = "DidSet"
            }
            let function: TIR.Function = if accessor.kind == .Get {
                createFunction(
                    nil, name: mangleAccessorName(
                        symbol, suffix: suffix, returnType: symbol.type ?? TrussType.VoidType.INSTANCE
                    ),
                    returnType: propertyType
                )
            } else {
                createFunction(
                    nil, name: mangleAccessorName(symbol, suffix: suffix, returnType: TrussType.VoidType.INSTANCE),
                    returnType: TIRType.VoidType()
                )
            }
            accessorFunctions[symbol.id, default: [:]][kindName] = function
            lowerAccessorBody(
                accessor, function: function, propertySymbol: symbol, propertyType: propertyType
            )
        }
    }

    private func lowerAccessorBody(
        _ accessor: AST.Accessor, function: TIR.Function,
        propertySymbol: Symbol.VariableSymbol, propertyType: TIRType.TIRType
    ) {
        guard let typeSymbol = collectTypeStack.last else { return }
        let savedBuilder = builder
        let savedEnv = env
        let savedCaptured = capturedCells
        let savedBreak = breakStack
        let savedDefer = deferStack
        let savedError = errorTargets
        let savedClosureParams = closureParamValues
        let savedSemanticScopes = semanticScopes

        let builder = TIRBuilder(function: function)
        self.builder = builder
        env = [:]
        capturedCells = []
        breakStack = []
        deferStack = []
        errorTargets = []
        closureParamValues = []
        pushScope()
        if let scope = accessor.scope {
            semanticScopes.append(scope)
        }

        let selfType = ownerType(typeSymbol) ?? TIRType.VoidType()
        let selfArgument = builder.createArgument(
            type: selfType, ownership: typeLower.ownership(for: selfType)
        )
        function.arguments.append(selfArgument)
        let selfAddress = builder.emitWithResult(
            TIR.AllocStack(selfType, sourceRange: emptyRange),
            type: TIRType.AddressType(selfType), ownership: .MutableBorrowing
        )
        builder.emit(TIR.Store(selfArgument, to: selfAddress, sourceRange: emptyRange))
        env[typeSymbol.id] = selfAddress
        if needsRelease(selfType) {
            registerBinding(LocalBinding(symbol: typeSymbol.id, type: selfType, address: selfAddress))
        }

        if accessor.kind != .Get {
            let parameterName = accessor.parameterName?.value
                ?? (accessor.kind == .DidSet ? "oldValue" : "newValue")
            let newValueArgument = builder.createArgument(
                type: propertyType, ownership: typeLower.ownership(for: propertyType)
            )
            function.arguments.append(newValueArgument)
            let newValueAddress = builder.emitWithResult(
                TIR.AllocStack(propertyType, sourceRange: emptyRange),
                type: TIRType.AddressType(propertyType), ownership: .MutableBorrowing
            )
            builder.emit(
                TIR.Store(newValueArgument, to: newValueAddress, sourceRange: emptyRange)
            )
            let newValueSymbol = accessor.scope?.values[parameterName]?
                .compactMap { $0 as? Symbol.VariableSymbol }.first
            if let newValueSymbol {
                env[newValueSymbol.id] = newValueAddress
            }
            if needsRelease(propertyType) {
                registerBinding(
                    LocalBinding(
                        symbol: newValueSymbol?.id ?? Id.SymbolId(id: 0), type: propertyType,
                        address: newValueAddress
                    )
                )
            }
        }

        switch accessor.body {
        case let .Block(statements):
            visitBodyStatements(statements, implicitReturn: accessor.kind == .Get)
        case let .Expression(expression):
            if let value = visitExpression(expression) {
                emitReturn(value, range: emptyRange)
            } else {
                emitReturn(nil, range: emptyRange)
            }
        }
        ensureTerminator(range: emptyRange)

        self.builder = savedBuilder
        env = savedEnv
        capturedCells = savedCaptured
        breakStack = savedBreak
        deferStack = savedDefer
        errorTargets = savedError
        closureParamValues = savedClosureParams
        semanticScopes = savedSemanticScopes
    }

    private func cname(_ attributes: [AST.Attribute]) -> String? {
        guard let attribute = attributes.first(where: { $0.name.value == "cname" }) else {
            return nil
        }
        guard attribute.arguments.count == 1 else {
            context.emitError(
                "cname attribute expects exactly one argument", at: attribute.name
            )
            return "unknown"
        }
        return attribute.arguments.first!.first?.value ?? "unknown"
    }

    private func functionName(
        for decl: AST.FunctionDecl, symbol: Symbol.FunctionSymbol,
        functionType: TrussType.FunctionType?
    ) -> String {
        if let cname = cname(decl.attributes) {
            return cname
        }
        return mangleFunctionName(
            symbol, baseName: decl.name.value,
            returnType: functionType?.returnType ?? TrussType.VoidType.INSTANCE
        )
    }

    private func mangleFunctionName(
        _ symbol: Symbol.FunctionSymbol, baseName: String, returnType: TrussType.TrussType
    ) -> String {
        var result = "$t"
        let packageName = symbol.packageId.flatMap { context.id2Symbol[$0]?.name } ?? "main"
        result += mangleIdentifier(packageName)
        for moduleSymbol in modulePathStack {
            result += mangleIdentifier(moduleSymbol.name)
        }
        if let memberOf = symbol.memberOf, let owner = context.id2Symbol[memberOf] {
            result += "_"
            result += mangleIdentifier(owner.name)
        }
        result += "_"
        result += mangleIdentifier(baseName)
        if let functionType = symbol.functionType {
            let labels = symbol.signature.labels
            for (index, parameter) in functionType.parameters.enumerated() {
                let label = index < labels.count ? labels[index] : nil
                result += "_"
                result += mangleIdentifier(label ?? "_")
                result += mangleIdentifier(typeName(parameter.type))
            }
        }
        result += "_"
        result += mangleIdentifier(typeName(returnType))
        return result
    }

    private func mangleIdentifier(_ name: String) -> String {
        "\(name.count)\(name)"
    }

    private func typeName(_ type: TrussType.TrussType) -> String {
        switch type {
        case is TrussType.VoidType:
            return "Void"
        case is TrussType.NeverType:
            return "Never"
        case is TrussType.ErrorType:
            return "E"
        case let builtin as TrussType.BuiltinType:
            return "B" + builtin.name
        case let nominal as TrussType.NominalType:
            return TypeMangler.nominalPath(nominal, context: context)
        case let optional as TrussType.OptionalType:
            return "O" + typeName(optional.wrapped)
        case let pointer as TrussType.PointerType:
            return "P" + (pointer.isNonnull ? "n" : "u") + typeName(pointer.pointee)
        case let tuple as TrussType.TupleType:
            var result = "T"
            for element in tuple.elements {
                result += typeName(element.type)
            }
            return result
        case let function as TrussType.FunctionType:
            var result = "F"
            for parameter in function.parameters {
                result += typeName(parameter.type)
            }
            result += "R"
            result += typeName(function.returnType)
            if function.isAsync {
                result += "A"
            }
            if function.isThrowing {
                result += "T"
            }
            if !function.throwsTypes.isEmpty {
                result += "E"
                for throwsType in function.throwsTypes {
                    result += typeName(throwsType)
                }
            }
            return result
        case let composition as TrussType.CompositionType:
            var result = "C"
            for member in composition.members {
                result += typeName(member)
            }
            return result
        case let variadic as TrussType.VariadicType:
            return "V" + typeName(variadic.base)
        case let instantiation as TrussType.GenericInstantiation:
            var result = "G"
            result += typeName(instantiation.base)
            for argument in instantiation.arguments {
                result += typeName(argument)
            }
            return result
        case let forall as TrussType.ForallType:
            return "A" + typeName(forall.body)
        case let genericParam as TrussType.GenericParamType:
            return "p" + genericParam.name
        case let variable as TrussType.TypeVariableType:
            if let binding = variable.binding {
                return typeName(binding)
            } else {
                return "v\(variable.id.id)"
            }
        default:
            return "x"
        }
    }

    @discardableResult
    private func createFunction(
        _ symbol: Symbol.FunctionSymbol?, name: String, returnType: TIRType.TIRType,
        isVariadic: Bool = false, isAsync: Bool = false,
        isThrowing: Bool = false, throwsTypes: [TIRType.TIRType] = []
    ) -> TIR.Function {
        let function = TIR.Function(
            name: name, returnType: returnType, isVariadic: isVariadic, isAsync: isAsync, isThrowing: isThrowing,
            throwsTypes: throwsTypes
        )
        function.symbol = symbol
        module.functions.append(function)
        if let symbol {
            functionsBySymbol[symbol.id] = function
        }
        return function
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        super.visitProgram(program, additional: additional)
        return module
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = functionDecl.symbol, let function = functionsBySymbol[symbol.id] else {
            return nil
        }
        guard let body = functionDecl.body else { return nil }
        generateBody(
            body, function: function, symbol: symbol, parameters: functionDecl.parameters,
            hasSelf: symbol.memberOf != nil, range: functionDecl.sourceRange
        )
        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        guard let symbol = initDecl.symbol, let function = functionsBySymbol[symbol.id] else {
            return nil
        }
        generateBody(
            .Block(initDecl.body), function: function, symbol: symbol,
            parameters: initDecl.parameters, hasSelf: true, initializeProperties: true,
            range: initDecl.sourceRange
        )
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        let key = ObjectIdentifier(deinitDecl)
        guard let function = deinitFunctions[key], let owner = deinitOwners[key] else {
            return nil
        }
        generateBody(
            .Block(deinitDecl.body), function: function, symbol: nil, parameters: [],
            hasSelf: true, owner: owner, range: deinitDecl.sourceRange
        )
        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = subscriptDecl.symbol, let function = functionsBySymbol[symbol.id] else {
            return nil
        }
        generateBody(
            .Block(subscriptDecl.body), function: function, symbol: symbol,
            parameters: subscriptDecl.parameters, hasSelf: true, range: subscriptDecl.sourceRange
        )
        return nil
    }

    private func generateBody(
        _ body: AST.FunctionDecl.Body, function: TIR.Function, symbol: Symbol.FunctionSymbol?,
        parameters: [AST.FunctionDecl.Parameter], hasSelf: Bool,
        owner: Symbol.NominalTypeSymbol? = nil, initializeProperties: Bool = false,
        range: SourceRange
    ) {
        let savedBuilder = builder
        let savedEnv = env
        let savedCaptured = capturedCells
        let savedBreak = breakStack
        let savedDefer = deferStack
        let savedError = errorTargets
        let savedClosureParams = closureParamValues
        let savedSemanticScopes = semanticScopes
        let savedLabelBlocks = labelBlocks

        builder = TIRBuilder(function: function)
        env = [:]
        capturedCells = []
        breakStack = []
        deferStack = []
        errorTargets = []
        closureParamValues = []
        labelBlocks = [:]
        pushScope()
        if let scope = symbol?.scope {
            semanticScopes.append(scope)
        }

        bindSelfIfNeeded(function: function, symbol: symbol, hasSelf: hasSelf, owner: owner)
        bindParameters(function: function, symbol: symbol, parameters: parameters)
        if initializeProperties {
            initializeStoredProperties(
                function: function, symbol: symbol, hasSelf: hasSelf, range: range
            )
        }

        switch body {
        case let .Block(statements):
            visitBodyStatements(
                statements, implicitReturn: shouldImplicitReturn(symbol?.functionType?.returnType)
            )
        case let .Expression(expression):
            if let value = visitExpression(expression) {
                emitReturn(value, range: range)
            } else {
                emitReturn(nil, range: range)
            }
        }
        ensureTerminator(range: range)

        builder = savedBuilder
        env = savedEnv
        capturedCells = savedCaptured
        breakStack = savedBreak
        deferStack = savedDefer
        errorTargets = savedError
        closureParamValues = savedClosureParams
        semanticScopes = savedSemanticScopes
        labelBlocks = savedLabelBlocks
    }

    private func bindSelfIfNeeded(
        function: TIR.Function, symbol: Symbol.FunctionSymbol?, hasSelf: Bool,
        owner: Symbol.NominalTypeSymbol? = nil
    ) {
        guard let builder else { return }
        guard hasSelf else { return }
        let ownerSymbol: Symbol.Symbol
        if let owner {
            ownerSymbol = owner
        } else if let symbol, let memberOf = symbol.memberOf,
                  let resolved = context.id2Symbol[memberOf]
        {
            ownerSymbol = resolved
        } else {
            return
        }
        let selfType = ownerType(ownerSymbol) ?? TIRType.VoidType()
        let argument = builder.createArgument(type: selfType, ownership: typeLower.ownership(for: selfType))
        function.arguments.append(argument)
        let address = builder.emitWithResult(
            TIR.AllocStack(selfType, sourceRange: emptyRange),
            type: TIRType.AddressType(selfType), ownership: .MutableBorrowing
        )
        builder.emit(TIR.Store(argument, to: address, sourceRange: emptyRange))
        if let symbol {
            env[symbol.id] = address
        }
        env[ownerSymbol.id] = address
        if needsRelease(selfType) {
            registerBinding(LocalBinding(symbol: ownerSymbol.id, type: selfType, address: address))
        }
    }

    private func bindParameters(
        function: TIR.Function, symbol: Symbol.FunctionSymbol?, parameters: [AST.FunctionDecl.Parameter]
    ) {
        guard let builder else { return }
        let paramTypes: [TIRType.TIRType] = parameters.enumerated().map { index, parameter in
            let type = symbol?.functionType?.parameters[safe: index].map { typeLower.lower($0.type) }
            return type ?? (parameter.type?.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        }
        var values: [TIR.Value] = []
        for (index, parameter) in parameters.enumerated() {
            let paramType = paramTypes[index]
            let argument = builder.createArgument(
                type: paramType, ownership: typeLower.ownership(for: paramType)
            )
            function.arguments.append(argument)
            let address = builder.emitWithResult(
                TIR.AllocStack(paramType, sourceRange: parameter.sourceRange),
                type: TIRType.AddressType(paramType), ownership: .MutableBorrowing
            )
            builder.emit(TIR.Store(argument, to: address, sourceRange: parameter.sourceRange))
            let variableSymbol = parameterVariableSymbol(symbol, parameter.name.value)
            if let variableSymbol {
                env[variableSymbol.id] = address
            }
            if needsRelease(paramType) {
                registerBinding(
                    LocalBinding(
                        symbol: variableSymbol?.id ?? Id.SymbolId(id: 0), type: paramType,
                        address: address
                    )
                )
            }
            values.append(argument)
        }
        if !parameters.isEmpty {
            closureParamValues.append(values)
        }
    }

    private func parameterVariableSymbol(
        _ symbol: Symbol.FunctionSymbol?, _ name: String
    ) -> Symbol.VariableSymbol? {
        guard let symbol else { return nil }
        return symbol.scope.values[name]?.compactMap { $0 as? Symbol.VariableSymbol }.first
    }

    private func initializeStoredProperties(
        function: TIR.Function, symbol: Symbol.FunctionSymbol?, hasSelf: Bool, range: SourceRange
    ) {
        guard let builder, hasSelf, let symbol, let memberOf = symbol.memberOf,
              let initializers = propertyInitializers[memberOf], !initializers.isEmpty,
              let owner = context.id2Symbol[memberOf]
        else {
            return
        }
        guard let selfAddress = env[memberOf] else { return }
        let isClass = owner is Symbol.ClassSymbol || owner is Symbol.ActorSymbol
        for (propertySymbol, initializer) in initializers {
            let propertyType = propertySymbol.type.map { typeLower.lower($0) }
                ?? (initializer.ty).map { typeLower.lower($0) }
                ?? TIRType.VoidType()
            let fieldAddress: TIR.Value = if isClass {
                builder.emitWithResult(
                    TIR.RefElementAddr(
                        selfAddress, fieldIndex: 0, fieldName: propertySymbol.name,
                        sourceRange: range
                    ),
                    type: TIRType.AddressType(propertyType), ownership: .MutableBorrowing
                )
            } else {
                builder.emitWithResult(
                    TIR.StructElementAddr(
                        selfAddress, fieldIndex: 0, fieldName: propertySymbol.name,
                        sourceRange: range
                    ),
                    type: TIRType.AddressType(propertyType), ownership: .MutableBorrowing
                )
            }
            if let value = visitExpression(initializer) {
                emitRetainIfNeeded(value, range: range)
                builder.emit(TIR.Store(value, to: fieldAddress, sourceRange: range))
            }
        }
    }

    private func ownerType(_ owner: Symbol.Symbol) -> TIRType.TIRType? {
        guard let nominal = owner as? Symbol.NominalTypeSymbol, let typeId = nominal.typeId,
              let type = context.typeTable[typeId]
        else {
            return nil
        }
        return typeLower.lower(type)
    }

    private func ensureTerminator(range: SourceRange) {
        guard let builder else { return }
        if let last = builder.currentBlock.instructions.last, isTerminator(last) {
            return
        }
        releaseAllScopes(range: range)
        builder.emit(TIR.Return(nil, sourceRange: range))
    }

    private func isTerminator(_ instruction: TIR.Instruction) -> Bool {
        instruction is TIR.Return || instruction is TIR.Throw || instruction is TIR.Branch
            || instruction is TIR.CondBranch || instruction is TIR.SwitchEnum
            || instruction is TIR.SwitchValue || instruction is TIR.Unreachable
            || instruction is TIR.Trap || instruction is TIR.TryApply
    }

    @discardableResult
    public override func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
    ) -> Any? {
        _ = visitExpression(expressionStatement.expression)
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = variableDecl.symbol else { return nil }
        if builder == nil {
            if symbol.memberOf != nil {
                if staticVariableSymbols.contains(symbol.id) {
                    createGlobal(variableDecl, symbol: symbol)
                    lowerGlobalInitializer(variableDecl, symbol: symbol)
                    return nil
                }
                if let initializer = variableDecl.initializer {
                    propertyInitializers[symbol.memberOf!, default: []].append(
                        (symbol, initializer)
                    )
                }
                return nil
            }
            createGlobal(variableDecl, symbol: symbol)
            lowerGlobalInitializer(variableDecl, symbol: symbol)
            return nil
        }
        guard let builder else { return nil }
        let type = symbol.type.map { typeLower.lower($0) }
            ?? (variableDecl.initializer?.ty).map { typeLower.lower($0) }
            ?? TIRType.VoidType()
        let address = builder.emitWithResult(
            TIR.AllocStack(type, sourceRange: variableDecl.sourceRange),
            type: TIRType.AddressType(type), ownership: .MutableBorrowing
        )
        env[symbol.id] = address
        if let initializer = variableDecl.initializer, let value = visitExpression(initializer) {
            emitRetainIfNeeded(value, range: variableDecl.sourceRange)
            builder.emit(TIR.Store(value, to: address, sourceRange: variableDecl.sourceRange))
        }
        if needsRelease(type) {
            registerBinding(LocalBinding(symbol: symbol.id, type: type, address: address))
        }
        return nil
    }

    private func createGlobal(_ variableDecl: AST.VariableDecl, symbol: Symbol.VariableSymbol) {
        guard globalsBySymbol[symbol.id] == nil else { return }
        let type = symbol.type.map { typeLower.lower($0) }
            ?? (variableDecl.initializer?.ty).map { typeLower.lower($0) }
            ?? TIRType.VoidType()
        let global = TIR.GlobalVariable(
            name: globalNamesBySymbol[symbol.id] ?? mangleGlobalName(symbol), type: type
        )
        global.symbol = symbol
        module.globals.append(global)
        globalsBySymbol[symbol.id] = global
    }

    private func lowerGlobalInitializer(
        _ variableDecl: AST.VariableDecl, symbol: Symbol.VariableSymbol
    ) {
        guard let global = globalsBySymbol[symbol.id], global.initializer.isEmpty else { return }
        guard let initializer = variableDecl.initializer else { return }
        let initFunction = TIR.Function(
            name: mangleGlobalName(symbol) + "_" + mangleIdentifier("init"), returnType: global.type
        )
        let savedBuilder = builder
        let savedEnv = env
        let initBuilder = TIRBuilder(function: initFunction)
        builder = initBuilder
        env = [:]
        if let value = visitExpression(initializer) {
            let address = initBuilder.emitWithResult(
                TIR.GlobalAddr(global, sourceRange: variableDecl.sourceRange),
                type: TIRType.AddressType(global.type), ownership: .MutableBorrowing
            )
            emitRetainIfNeeded(value, range: variableDecl.sourceRange)
            initBuilder.emit(
                TIR.Store(value, to: address, sourceRange: variableDecl.sourceRange)
            )
        }
        global.initializer = initFunction.entryBlock.instructions
        builder = savedBuilder
        env = savedEnv
    }

    private func mangleGlobalName(_ symbol: Symbol.VariableSymbol) -> String {
        let packageName = symbol.packageId.flatMap { context.id2Symbol[$0]?.name } ?? "main"
        var result = "$t" + mangleIdentifier(packageName)
        for moduleSymbol in modulePathStack {
            result += mangleIdentifier(moduleSymbol.name)
        }
        if let memberOf = symbol.memberOf, let owner = context.id2Symbol[memberOf] {
            result += "_"
            result += mangleIdentifier(owner.name)
        }
        result += "_"
        result += mangleIdentifier(symbol.name)
        return result
    }

    private func mangleAccessorName(
        _ symbol: Symbol.VariableSymbol, suffix: String, returnType: TrussType.TrussType
    ) -> String {
        var result = "$t"
        let packageName = symbol.packageId.flatMap { context.id2Symbol[$0]?.name } ?? "main"
        result += mangleIdentifier(packageName)
        for moduleSymbol in modulePathStack {
            result += mangleIdentifier(moduleSymbol.name)
        }
        if let memberOf = symbol.memberOf, let owner = context.id2Symbol[memberOf] {
            result += "_"
            result += mangleIdentifier(owner.name)
        }
        result += "_"
        result += mangleIdentifier(symbol.name)
        result += suffix
        result += "_"
        result += mangleIdentifier(typeName(returnType))
        return result
    }

    @discardableResult
    public override func visitReturn(_ returnStatement: AST.Return, additional: Any? = nil) -> Any? {
        var value: TIR.Value? = nil
        if let expression = returnStatement.value {
            value = visitExpression(expression)
        }
        emitReturn(value, range: returnStatement.sourceRange)
        return nil
    }

    @discardableResult
    public override func visitThrow(_ throwStatement: AST.Throw, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let value = visitExpression(throwStatement.expression)
        runDeferred()
        if let target = errorTargets.last {
            releaseScopes(upTo: target.scopeDepth, range: throwStatement.sourceRange)
        } else {
            releaseAllScopes(range: throwStatement.sourceRange)
        }
        if let value {
            builder.emit(TIR.Throw(value, sourceRange: throwStatement.sourceRange))
        }
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        if let scope = whileStatement.scope {
            semanticScopes.append(scope)
        }
        let condBlock = builder.createBlock()
        let bodyBlock = builder.createBlock()
        let exitBlock = builder.createBlock()
        builder.emit(TIR.Branch(condBlock, sourceRange: whileStatement.sourceRange))
        builder.switchToBlock(condBlock)
        visitCondition(
            whileStatement.condition, trueBlock: bodyBlock, falseBlock: exitBlock,
            range: whileStatement.sourceRange
        )
        builder.switchToBlock(bodyBlock)
        let label = pendingLoopLabel
        pendingLoopLabel = nil
        breakStack.append(
            BreakTarget(
                label: label, breakBlock: exitBlock, continueBlock: condBlock,
                scopeDepth: scopeStack.count
            )
        )
        visitScopedStatements(whileStatement.body, range: whileStatement.sourceRange)
        breakStack.removeLast()
        if whileStatement.scope != nil {
            semanticScopes.removeLast()
        }
        builder.emit(TIR.Branch(condBlock, sourceRange: whileStatement.sourceRange))
        builder.switchToBlock(exitBlock)
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        if let scope = repeatWhile.scope {
            semanticScopes.append(scope)
        }
        let bodyBlock = builder.createBlock()
        let condBlock = builder.createBlock()
        let exitBlock = builder.createBlock()
        builder.emit(TIR.Branch(bodyBlock, sourceRange: repeatWhile.sourceRange))
        builder.switchToBlock(bodyBlock)
        let label = pendingLoopLabel
        pendingLoopLabel = nil
        breakStack.append(
            BreakTarget(
                label: label, breakBlock: exitBlock, continueBlock: condBlock,
                scopeDepth: scopeStack.count
            )
        )
        visitScopedStatements(repeatWhile.body, range: repeatWhile.sourceRange)
        breakStack.removeLast()
        if repeatWhile.scope != nil {
            semanticScopes.removeLast()
        }
        builder.emit(TIR.Branch(condBlock, sourceRange: repeatWhile.sourceRange))
        builder.switchToBlock(condBlock)
        visitCondition(
            repeatWhile.condition, trueBlock: bodyBlock, falseBlock: exitBlock,
            range: repeatWhile.sourceRange
        )
        builder.switchToBlock(exitBlock)
        return nil
    }

    @discardableResult
    public override func visitGuard(_ guardStatement: AST.Guard, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let failBlock = builder.createBlock()
        let continueBlock = builder.createBlock()
        visitCondition(
            guardStatement.condition, trueBlock: continueBlock, falseBlock: failBlock,
            range: guardStatement.sourceRange
        )
        builder.switchToBlock(failBlock)
        runDeferred()
        releaseAllScopes(range: guardStatement.sourceRange)
        builder.emit(TIR.Return(nil, sourceRange: guardStatement.sourceRange))
        builder.switchToBlock(continueBlock)
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        _ = visitExpression(forStatement.sequence)
        builder.emit(TIR.Trap(forStatement.sourceRange))
        return nil
    }

    @discardableResult
    public override func visitDefer(_ deferStatement: AST.Defer, additional: Any? = nil) -> Any? {
        deferStack.append(deferStatement.body)
        return nil
    }

    @discardableResult
    public override func visitBreak(_ breakStatement: AST.Break, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let label = breakStatement.label?.value
        let target = breakStack.last { $0.label == label } ?? breakStack.last
        if let target {
            releaseScopes(upTo: target.scopeDepth, range: breakStatement.sourceRange)
            builder.emit(TIR.Branch(target.breakBlock, sourceRange: breakStatement.sourceRange))
        }
        return nil
    }

    @discardableResult
    public override func visitContinue(
        _ continueStatement: AST.Continue, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let label = continueStatement.label?.value
        let target = breakStack.last { $0.label == label } ?? breakStack.last
        if let target, let continueBlock = target.continueBlock {
            releaseScopes(upTo: target.scopeDepth, range: continueStatement.sourceRange)
            builder.emit(TIR.Branch(continueBlock, sourceRange: continueStatement.sourceRange))
        }
        return nil
    }

    @discardableResult
    public override func visitLabeledStatement(
        _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
    ) -> Any? {
        let isLoop = labeledStatement.body is AST.While
            || labeledStatement.body is AST.RepeatWhile
            || labeledStatement.body is AST.For
        if isLoop {
            let savedLabel = pendingLoopLabel
            pendingLoopLabel = labeledStatement.label.value
            _ = visit(labeledStatement.body, additional: additional)
            pendingLoopLabel = savedLabel
            return nil
        }
        guard let builder else { return nil }
        let continuation = builder.currentBlock
        let target = labelBlocks[labeledStatement.label.value] ?? builder.createBlock()
        labelBlocks[labeledStatement.label.value] = target
        builder.switchToBlock(target)
        _ = visit(labeledStatement.body, additional: additional)
        if let last = builder.currentBlock.instructions.last, !isTerminator(last) {
            builder.emit(TIR.Branch(continuation, sourceRange: labeledStatement.sourceRange))
        }
        builder.switchToBlock(continuation)
        return nil
    }

    @discardableResult
    public override func visitGoto(_ gotoStatement: AST.Goto, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let target = labelBlocks[gotoStatement.label.value] ?? builder.createBlock()
        labelBlocks[gotoStatement.label.value] = target
        builder.emit(TIR.Branch(target, sourceRange: gotoStatement.sourceRange))
        return nil
    }

    @discardableResult
    public override func visitAsm(_ asmStatement: AST.Asm, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let template = asmStatement.templates.map(\.token.value).joined(separator: " ")
        let constraints = asmStatement.bindings.map(\.constraint.value)
        let options = asmStatement.options.map(\.value)
        var operands: [TIR.Value] = []
        for binding in asmStatement.bindings {
            guard let local = binding.local,
                  let symbol = currentScopeVariable(named: local.value),
                  let address = env[symbol.id],
                  let value = loadFrom(address, range: binding.sourceRange)
            else {
                continue
            }
            operands.append(value)
        }
        builder.emit(
            TIR.InlineAsm(
                template: template, constraints: constraints, operands: operands,
                options: options, sourceRange: asmStatement.sourceRange
            )
        )
        return nil
    }

    private func visitCondition(
        _ condition: AST.Expression, trueBlock: TIR.BasicBlock, falseBlock: TIR.BasicBlock,
        range: SourceRange
    ) {
        guard let builder else { return }
        let unwrapped = unwrapParentheses(condition)
        if let binding = unwrapped as? AST.OptionalBinding {
            guard let value = visitExpression(binding.value) else { return }
            let someBlock = builder.createBlock()
            let noneBlock = builder.createBlock()
            builder.emit(
                TIR.SwitchEnum(
                    value,
                    cases: [
                        TIR.EnumCaseBranch(caseName: "some", block: someBlock),
                        TIR.EnumCaseBranch(caseName: "none", block: noneBlock),
                    ],
                    defaultBlock: nil, sourceRange: range
                )
            )
            builder.switchToBlock(someBlock)
            bindPatternValue(name: binding.name.value, value: value, at: binding.sourceRange)
            builder.emit(TIR.Branch(trueBlock, sourceRange: range))
            builder.switchToBlock(noneBlock)
            builder.emit(TIR.Branch(falseBlock, sourceRange: range))
            builder.switchToBlock(trueBlock)
            return
        }
        if let value = visitExpression(condition) {
            builder.emit(
                TIR.CondBranch(
                    condition: value, trueBlock: trueBlock, falseBlock: falseBlock,
                    sourceRange: range
                )
            )
        }
        builder.switchToBlock(trueBlock)
    }

    private func unwrapParentheses(_ expression: AST.Expression) -> AST.Expression {
        if let parenthetical = expression as? AST.Parenthetical {
            return unwrapParentheses(parenthetical.inner)
        }
        return expression
    }

    @discardableResult
    public override func visitIf(_ ifExpression: AST.If, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        if let scope = ifExpression.scope {
            semanticScopes.append(scope)
        }
        let thenBlock = builder.createBlock()
        let elseBlock = builder.createBlock()
        let joinBlock = builder.createBlock()
        var incomings: [(TIR.Value, TIR.BasicBlock)] = []
        visitCondition(
            ifExpression.condition, trueBlock: thenBlock, falseBlock: elseBlock,
            range: ifExpression.sourceRange
        )
        builder.switchToBlock(thenBlock)
        emitBranchValue(
            ifExpression.then, incomings: &incomings, joinBlock: joinBlock,
            range: ifExpression.sourceRange
        )
        builder.switchToBlock(elseBlock)
        if let elseKind = ifExpression.elseKind {
            switch elseKind {
            case let .Block(statements):
                emitBranchValue(
                    statements, incomings: &incomings, joinBlock: joinBlock,
                    range: ifExpression.sourceRange
                )
            case let .If(nested):
                if let value = visitIf(nested) as? TIR.Value {
                    incomings.append((value, builder.currentBlock))
                }
                builder.emit(TIR.Branch(joinBlock, sourceRange: ifExpression.sourceRange))
            }
        } else {
            builder.emit(TIR.Branch(joinBlock, sourceRange: ifExpression.sourceRange))
            incomings = []
        }
        builder.switchToBlock(joinBlock)
        if ifExpression.scope != nil {
            semanticScopes.removeLast()
        }
        return emitPhi(incomings, range: ifExpression.sourceRange)
    }

    private func emitBranchValue(
        _ statements: [AST.Statement], incomings: inout [(TIR.Value, TIR.BasicBlock)],
        joinBlock: TIR.BasicBlock, range: SourceRange
    ) {
        guard let builder else { return }
        pushScope()
        if let last = statements.last as? AST.ExpressionStatement {
            for statement in statements.dropLast() {
                visit(statement)
            }
            if let value = visitExpression(last.expression) {
                incomings.append((value, builder.currentBlock))
            }
        } else {
            for statement in statements {
                visit(statement)
            }
        }
        popScope(range: range)
        builder.emit(TIR.Branch(joinBlock, sourceRange: range))
    }

    private func emitPhi(
        _ incomings: [(TIR.Value, TIR.BasicBlock)], range: SourceRange
    ) -> TIR.Value? {
        guard let builder, let first = incomings.first else { return nil }
        return builder.emitWithResult(
            TIR.Phi(incomings: incomings, sourceRange: range),
            type: first.0.type, ownership: typeLower.ownership(for: first.0.type)
        )
    }

    @discardableResult
    public override func visitMatch(_ matchExpression: AST.Match, additional: Any? = nil) -> Any? {
        visitMatch(matchExpression, implicitReturn: false)
    }

    @discardableResult
    public override func visitCaseMatch(
        _ caseMatch: AST.CaseMatch, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        guard let subject = visitExpression(caseMatch.subject) else { return nil }
        let boolType = (caseMatch.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        let successBlock = builder.createBlock()
        let failBlock = builder.createBlock()
        emitPatternMatch(
            caseMatch.pattern, subject: subject, successBlock: successBlock,
            failBlock: failBlock, range: caseMatch.sourceRange
        )
        let joinBlock = builder.createBlock()
        var incomings: [(TIR.Value, TIR.BasicBlock)] = []
        builder.switchToBlock(successBlock)
        let trueValue = builder.emitWithResult(
            TIR.BoolLiteral(true, sourceRange: caseMatch.sourceRange),
            type: boolType, ownership: .Trivial
        )
        incomings.append((trueValue, successBlock))
        builder.emit(TIR.Branch(joinBlock, sourceRange: caseMatch.sourceRange))
        builder.switchToBlock(failBlock)
        let falseValue = builder.emitWithResult(
            TIR.BoolLiteral(false, sourceRange: caseMatch.sourceRange),
            type: boolType, ownership: .Trivial
        )
        incomings.append((falseValue, failBlock))
        builder.emit(TIR.Branch(joinBlock, sourceRange: caseMatch.sourceRange))
        builder.switchToBlock(joinBlock)
        return emitPhi(incomings, range: caseMatch.sourceRange)
    }

    @discardableResult
    private func visitMatch(_ matchExpression: AST.Match, implicitReturn: Bool) -> TIR.Value? {
        guard let builder, let subject = visitExpression(matchExpression.subject) else { return nil }
        let joinBlock = builder.createBlock()
        var testBlock = builder.currentBlock
        var incomings: [(TIR.Value, TIR.BasicBlock)] = []
        for matchCase in matchExpression.cases {
            let caseBody = builder.createBlock()
            builder.switchToBlock(testBlock)
            for pattern in matchCase.patterns {
                let fail = builder.createBlock()
                emitPatternMatch(
                    pattern, subject: subject, successBlock: caseBody, failBlock: fail,
                    range: matchCase.sourceRange
                )
                builder.switchToBlock(fail)
            }
            testBlock = builder.currentBlock
            builder.switchToBlock(caseBody)
            let statements = matchCase.body
            pushScope()
            if let last = statements.last as? AST.ExpressionStatement {
                for statement in statements.dropLast() {
                    visit(statement)
                }
                if implicitReturn {
                    visitImplicitReturnExpression(last.expression, range: last.sourceRange)
                } else {
                    if let value = visitExpression(last.expression) {
                        incomings.append((value, builder.currentBlock))
                    }
                    popScope(range: matchCase.sourceRange)
                    builder.emit(TIR.Branch(joinBlock, sourceRange: matchCase.sourceRange))
                }
            } else {
                for statement in statements {
                    visit(statement)
                }
                popScope(range: matchCase.sourceRange)
                builder.emit(TIR.Branch(joinBlock, sourceRange: matchCase.sourceRange))
            }
        }
        builder.switchToBlock(testBlock)
        builder.emit(TIR.Unreachable(matchExpression.sourceRange))
        builder.switchToBlock(joinBlock)
        return emitPhi(incomings, range: matchExpression.sourceRange)
    }

    private func emitPatternMatch(
        _ pattern: AST.Expression, subject: TIR.Value, successBlock: TIR.BasicBlock,
        failBlock: TIR.BasicBlock, range: SourceRange
    ) {
        guard let builder else { return }
        switch pattern {
        case let binding as AST.BindingPattern:
            bindPatternValue(name: binding.name.value, value: subject, at: binding.sourceRange)
            builder.emit(TIR.Branch(successBlock, sourceRange: range))
        case is AST.WildcardPattern:
            builder.emit(TIR.Branch(successBlock, sourceRange: range))
        case let variable as AST.Variable where variable.symbol == nil:
            bindPatternValue(name: variable.name.value, value: subject, at: variable.sourceRange)
            builder.emit(TIR.Branch(successBlock, sourceRange: range))
        case let member as AST.ImplicitMemberAccess:
            guard let caseSymbol = member.symbol as? Symbol.CaseSymbol,
                  enumTypeValue(for: caseSymbol) != nil
            else {
                builder.emit(TIR.Branch(failBlock, sourceRange: range))
                return
            }
            builder.emit(
                TIR.SwitchEnum(
                    subject,
                    cases: [
                        TIR.EnumCaseBranch(caseName: caseSymbol.name, block: successBlock),
                    ],
                    defaultBlock: failBlock, sourceRange: range
                )
            )
        case let call as AST.Call:
            let calleeSymbol = (call.callee as? AST.ImplicitMemberAccess)?.symbol
                ?? (call.callee as? AST.Variable)?.symbol
            guard let caseSymbol = calleeSymbol as? Symbol.CaseSymbol,
                  enumTypeValue(for: caseSymbol) != nil
            else {
                builder.emit(TIR.Branch(failBlock, sourceRange: range))
                return
            }
            let payloadBlock = builder.createBlock()
            builder.emit(
                TIR.SwitchEnum(
                    subject,
                    cases: [
                        TIR.EnumCaseBranch(caseName: caseSymbol.name, block: payloadBlock),
                    ],
                    defaultBlock: failBlock, sourceRange: range
                )
            )
            builder.switchToBlock(payloadBlock)
            if !call.arguments.isEmpty {
                let payload = builder.emitWithResult(
                    TIR.UncheckedEnumData(subject, caseName: caseSymbol.name, sourceRange: range),
                    type: payloadType(caseSymbol), ownership: .Trivial
                )
                _ = builder.emitWithResult(
                    TIR.TupleElementAddr(payload, index: 0, sourceRange: range),
                    type: TIRType.AddressType(TIRType.VoidType()), ownership: .MutableBorrowing
                )
                for (index, argument) in call.arguments.enumerated() {
                    let element = builder.emitWithResult(
                        TIR.TupleElementAddr(payload, index: index, sourceRange: range),
                        type: TIRType.AddressType(TIRType.VoidType()), ownership: .MutableBorrowing
                    )
                    let elementValue = builder.emitWithResult(
                        TIR.Load(element, sourceRange: range), type: TIRType.VoidType(),
                        ownership: .Trivial
                    )
                    emitPatternMatch(
                        argument.value, subject: elementValue, successBlock: successBlock,
                        failBlock: failBlock, range: range
                    )
                    if index < call.arguments.count - 1 {
                        builder.switchToBlock(failBlock)
                    }
                }
            } else {
                builder.emit(TIR.Branch(successBlock, sourceRange: range))
            }
        case let tuple as AST.Tuple:
            let tupleAddress = builder.emitWithResult(
                TIR.AllocStack(subject.type, sourceRange: range),
                type: TIRType.AddressType(subject.type), ownership: .MutableBorrowing
            )
            builder.emit(TIR.Store(subject, to: tupleAddress, sourceRange: range))
            for (index, element) in tuple.elements.enumerated() {
                let elementAddress = builder.emitWithResult(
                    TIR.TupleElementAddr(tupleAddress, index: index, sourceRange: range),
                    type: TIRType.AddressType(TIRType.VoidType()), ownership: .MutableBorrowing
                )
                let elementValue = builder.emitWithResult(
                    TIR.Load(elementAddress, sourceRange: range), type: TIRType.VoidType(),
                    ownership: .Trivial
                )
                emitPatternMatch(
                    element.value, subject: elementValue, successBlock: successBlock,
                    failBlock: failBlock, range: range
                )
                if index < tuple.elements.count - 1 {
                    builder.switchToBlock(failBlock)
                }
            }
        case let isPattern as AST.IsPattern:
            let targetType = (isPattern.typeExpression.ty).map { typeLower.lower($0) }
                ?? TIRType.VoidType()
            _ = builder.emitWithResult(
                TIR.UncheckedRefCast(subject, to: targetType, sourceRange: range),
                type: targetType, ownership: .Trivial
            )
            builder.emit(TIR.Branch(successBlock, sourceRange: range))
        default:
            if let literal = visitExpression(pattern) {
                let matchBlock = builder.createBlock()
                builder.emit(
                    TIR.SwitchValue(
                        subject,
                        cases: [
                            TIR.ValueCaseBranch(literal: literal, block: matchBlock),
                        ],
                        defaultBlock: failBlock, sourceRange: range
                    )
                )
                builder.switchToBlock(matchBlock)
                builder.emit(TIR.Branch(successBlock, sourceRange: range))
            } else {
                builder.emit(TIR.Branch(failBlock, sourceRange: range))
            }
        }
    }

    private func payloadType(_ caseSymbol: Symbol.CaseSymbol) -> TIRType.TIRType {
        if let first = caseSymbol.associatedTypes.first {
            return typeLower.lower(first)
        }
        return TIRType.VoidType()
    }

    private func bindPatternValue(name: String, value: TIR.Value, at range: SourceRange) {
        guard let builder else { return }
        let address = builder.emitWithResult(
            TIR.AllocStack(value.type, sourceRange: range),
            type: TIRType.AddressType(value.type), ownership: .MutableBorrowing
        )
        builder.emit(TIR.Store(value, to: address, sourceRange: range))
        if let variableSymbol = currentScopeVariable(named: name) {
            env[variableSymbol.id] = address
        }
    }

    private func currentScopeVariable(named name: String) -> Symbol.VariableSymbol? {
        for scope in semanticScopes.reversed() {
            if let symbol = scope.values[name]?.first(where: { $0 is Symbol.VariableSymbol })
                as? Symbol.VariableSymbol
            {
                return symbol
            }
        }
        return nil
    }

    @discardableResult
    public override func visitDo(_ doExpression: AST.Do, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let joinBlock = builder.createBlock()
        let errorBlock = builder.createBlock()
        var incomings: [(TIR.Value, TIR.BasicBlock)] = []
        errorTargets.append(ErrorTarget(block: errorBlock, scopeDepth: scopeStack.count))
        let bodyStatements = doExpression.body
        pushScope()
        if let last = bodyStatements.last as? AST.ExpressionStatement {
            for statement in bodyStatements.dropLast() {
                visit(statement)
            }
            if let value = visitExpression(last.expression) {
                incomings.append((value, builder.currentBlock))
            }
        } else {
            for statement in bodyStatements {
                visit(statement)
            }
        }
        popScope(range: doExpression.sourceRange)
        errorTargets.removeLast()
        builder.emit(TIR.Branch(joinBlock, sourceRange: doExpression.sourceRange))
        builder.switchToBlock(errorBlock)
        let errorValue = errorBlock.arguments.last
        if doExpression.catches.isEmpty {
            builder.emit(TIR.Unreachable(doExpression.sourceRange))
        } else {
            var testBlock = builder.currentBlock
            for catchClause in doExpression.catches {
                let catchBody = builder.createBlock()
                builder.switchToBlock(testBlock)
                if let errorValue {
                    if let pattern = catchClause.pattern {
                        let fail = builder.createBlock()
                        emitPatternMatch(
                            pattern, subject: errorValue, successBlock: catchBody,
                            failBlock: fail, range: catchClause.sourceRange
                        )
                        builder.switchToBlock(fail)
                    } else {
                        builder.emit(TIR.Branch(catchBody, sourceRange: catchClause.sourceRange))
                    }
                } else {
                    builder.emit(TIR.Branch(catchBody, sourceRange: catchClause.sourceRange))
                }
                testBlock = builder.currentBlock
                builder.switchToBlock(catchBody)
                let catchStatements = catchClause.body
                pushScope()
                if let last = catchStatements.last as? AST.ExpressionStatement {
                    for statement in catchStatements.dropLast() {
                        visit(statement)
                    }
                    if let value = visitExpression(last.expression) {
                        incomings.append((value, builder.currentBlock))
                    }
                } else {
                    for statement in catchStatements {
                        visit(statement)
                    }
                }
                popScope(range: catchClause.sourceRange)
                builder.emit(TIR.Branch(joinBlock, sourceRange: doExpression.sourceRange))
            }
            builder.switchToBlock(testBlock)
            builder.emit(TIR.Unreachable(doExpression.sourceRange))
        }
        if let finallyBody = doExpression.finallyBody {
            builder.switchToBlock(joinBlock)
            visitScopedStatements(finallyBody, range: doExpression.sourceRange)
            builder.switchToBlock(joinBlock)
        } else {
            builder.switchToBlock(joinBlock)
        }
        return emitPhi(incomings, range: doExpression.sourceRange)
    }

    @discardableResult
    private func visitExpression(_ expression: AST.Expression) -> TIR.Value? {
        visit(expression) as? TIR.Value
    }

    private func visitExpressionList(_ expressions: [AST.Expression]) -> [TIR.Value] {
        expressions.compactMap { visitExpression($0) }
    }

    @discardableResult
    public override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = (integerLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.IntegerLiteral(Int64(integerLiteral.value), type: type, sourceRange: integerLiteral.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitFloatLiteral(
        _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = (floatLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.FloatLiteral(floatLiteral.value, type: type, sourceRange: floatLiteral.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitStringLiteral(
        _ stringLiteral: AST.StringLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = (stringLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.StringLiteral(stringLiteral.token.value, sourceRange: stringLiteral.sourceRange),
            type: type, ownership: .Owned
        )
    }

    @discardableResult
    public override func visitCharLiteral(
        _ charLiteral: AST.CharLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = (charLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.CharLiteral(charLiteral.value, sourceRange: charLiteral.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitBoolLiteral(
        _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = (boolLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.BoolLiteral(boolLiteral.value, sourceRange: boolLiteral.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitNullLiteral(
        _ nullLiteral: AST.NullLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = (nullLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.NullLiteral(type: type, sourceRange: nullLiteral.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitNullPointerLiteral(
        _ nullPointerLiteral: AST.NullPointerLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = (nullPointerLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.NullLiteral(type: type, sourceRange: nullPointerLiteral.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitVoidLiteral(
        _ voidLiteral: AST.VoidLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = TIRType.VoidType()
        return builder.emitWithResult(
            TIR.VoidLiteral(voidLiteral.sourceRange), type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitVariable(
        _ variable: AST.Variable, additional: Any? = nil
    ) -> Any? {
        guard let builder, let symbol = variable.symbol else { return nil }
        if let functionSymbol = symbol as? Symbol.FunctionSymbol {
            return functionRefValue(functionSymbol, at: variable.sourceRange)
        }
        if let caseSymbol = symbol as? Symbol.CaseSymbol {
            return enumValue(caseSymbol, payload: nil, at: variable.sourceRange)
        }
        if let global = globalsBySymbol[symbol.id] {
            let address = builder.emitWithResult(
                TIR.GlobalAddr(global, sourceRange: variable.sourceRange),
                type: TIRType.AddressType(global.type), ownership: .MutableBorrowing
            )
            return loadFrom(address, range: variable.sourceRange)
        }
        if let address = env[symbol.id] {
            let loaded = loadFrom(address, range: variable.sourceRange)
            if capturedCells.contains(symbol.id) {
                let projected = builder.emitWithResult(
                    TIR.ProjectCell(address, sourceRange: variable.sourceRange),
                    type: address.type, ownership: .MutableBorrowing
                )
                return loadFrom(projected, range: variable.sourceRange)
            }
            return loaded
        }
        if let memberOf = symbol.memberOf, let selfAddress = env[memberOf],
           let property = symbol as? Symbol.VariableSymbol
        {
            return loadImplicitProperty(property, selfAddress: selfAddress, at: variable.sourceRange)
        }
        return nil
    }

    private func loadImplicitProperty(
        _ symbol: Symbol.VariableSymbol, selfAddress: TIR.Value, at range: SourceRange
    ) -> TIR.Value? {
        guard let builder else { return nil }
        if let getter = accessorFunctions[symbol.id]?["get"] {
            let selfValue = loadFrom(selfAddress, range: range) ?? selfAddress
            let callee = builder.emitWithResult(
                TIR.FunctionRef(getter, sourceRange: range),
                type: accessorType(getter, withValue: false), ownership: .Trivial
            )
            return builder.emitWithResult(
                TIR.Apply(
                    callee: callee, arguments: [selfValue], substitutions: [],
                    sourceRange: range
                ),
                type: getter.returnType, ownership: typeLower.ownership(for: getter.returnType)
            )
        }
        let propertyType = symbol.type.map { typeLower.lower($0) } ?? TIRType.VoidType()
        guard let address = implicitPropertyElementAddress(
            symbol, selfAddress: selfAddress, propertyType: propertyType, range: range
        ) else {
            return nil
        }
        return loadFrom(address, range: range)
    }

    private func implicitPropertyElementAddress(
        _ symbol: Symbol.VariableSymbol, selfAddress: TIR.Value, propertyType: TIRType.TIRType,
        range: SourceRange
    ) -> TIR.Value? {
        guard let builder, let memberOf = symbol.memberOf,
              let owner = context.id2Symbol[memberOf]
        else {
            return nil
        }
        let isClass = owner is Symbol.ClassSymbol || owner is Symbol.ActorSymbol
        return builder.emitWithResult(
            isClass
                ? TIR.RefElementAddr(
                    selfAddress, fieldIndex: 0, fieldName: symbol.name, sourceRange: range
                )
                : TIR.StructElementAddr(
                    selfAddress, fieldIndex: 0, fieldName: symbol.name, sourceRange: range
                ),
            type: TIRType.AddressType(propertyType), ownership: .MutableBorrowing
        )
    }

    private func pushScope() {
        scopeStack.append([])
    }

    private func visitScopedStatements(_ statements: [AST.Statement], range: SourceRange) {
        pushScope()
        for statement in statements {
            visit(statement)
        }
        popScope(range: range)
    }

    private func popScope(range: SourceRange) {
        guard let scope = scopeStack.popLast() else { return }
        releaseScope(scope, range: range)
    }

    private func registerBinding(_ binding: LocalBinding) {
        if !scopeStack.isEmpty {
            scopeStack[scopeStack.count - 1].append(binding)
        }
    }

    private func releaseScopes(upTo depth: Int, range: SourceRange) {
        while scopeStack.count > depth {
            if let scope = scopeStack.popLast() {
                releaseScope(scope, range: range)
            }
        }
    }

    private func releaseAllScopes(range: SourceRange) {
        while let scope = scopeStack.popLast() {
            releaseScope(scope, range: range)
        }
    }

    private func needsRelease(_ type: TIRType.TIRType) -> Bool {
        if type is TIRType.ReferenceType { return true }
        if let structType = type as? TIRType.StructType {
            return deinitFunctionsByType[structType.id] != nil
        }
        return false
    }

    private func emitRetainIfNeeded(_ value: TIR.Value, range: SourceRange) {
        guard let builder else { return }
        guard value.type is TIRType.ReferenceType else { return }
        guard value.definingInstruction is TIR.Load || value.definingInstruction is TIR.Phi
        else {
            return
        }
        builder.emit(TIR.RetainValue(value, sourceRange: range))
    }

    private func releaseScope(_ scope: [LocalBinding], range: SourceRange) {
        guard let builder else { return }
        for binding in scope.reversed() {
            if capturedCells.contains(binding.symbol) { continue }
            if binding.type is TIRType.ReferenceType {
                if let value = loadFrom(binding.address, range: range) {
                    builder.emit(TIR.ReleaseValue(value, sourceRange: range))
                }
            } else if let structType = binding.type as? TIRType.StructType,
                      let deinitFunction = deinitFunctionsByType[structType.id]
            {
                emitDeinitCall(deinitFunction, selfAddress: binding.address, range: range)
            }
        }
    }

    private func emitDeinitCall(
        _ deinitFunction: TIR.Function, selfAddress: TIR.Value, range: SourceRange
    ) {
        guard let builder else { return }
        let callee = builder.emitWithResult(
            TIR.FunctionRef(deinitFunction, sourceRange: range),
            type: initFunctionType(deinitFunction), ownership: .Trivial
        )
        let selfValue = loadFrom(selfAddress, range: range) ?? selfAddress
        builder.emit(TIR.Apply(callee: callee, arguments: [selfValue], substitutions: [], sourceRange: range))
    }

    private func loadFrom(_ address: TIR.Value, range: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        let pointee = (address.type as? TIRType.AddressType)?.pointee ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.Load(address, sourceRange: range), type: pointee,
            ownership: typeLower.ownership(for: pointee)
        )
    }

    @discardableResult
    public override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        if let symbol = selfExpression.symbol, let address = env[symbol.id] {
            return loadFrom(address, range: selfExpression.sourceRange)
        }
        if let address = env.values.first {
            return loadFrom(address, range: selfExpression.sourceRange)
        }
        return nil
    }

    @discardableResult
    public override func visitSuperExpression(
        _ superExpression: AST.SuperExpression, additional: Any? = nil
    ) -> Any? {
        visitSelfExpression(
            AST.SelfExpression(superExpression.token, sourceRange: superExpression.sourceRange)
        )
    }

    @discardableResult
    public override func visitParenthetical(
        _ parenthetical: AST.Parenthetical, additional: Any? = nil
    ) -> Any? {
        visitExpression(parenthetical.inner)
    }

    @discardableResult
    public override func visitTuple(_ tuple: AST.Tuple, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let elements = tuple.elements.compactMap { visitExpression($0.value) }
        let type = (tuple.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.TupleValue(elements: elements, sourceRange: tuple.sourceRange), type: type,
            ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        emitCall(call, tryErrorBlock: nil)
    }

    private func emitCall(_ call: AST.Call, tryErrorBlock: TIR.BasicBlock?) -> TIR.Value? {
        guard let builder else { return nil }
        guard let calleeValue = lowerCallee(call.callee, at: call.sourceRange) else { return nil }
        let resolvedSymbol = call.symbol ?? call.overloads?.first
        var arguments: [TIR.Value] = []
        if let initFunction = initFunctionFor(call, resolvedSymbol: resolvedSymbol),
           let selfType = initFunction.arguments.first?.type
        {
            let selfAddress = if let refType = selfType as? TIRType.ReferenceType {
                builder.emitWithResult(
                    TIR.AllocRef(refType, sourceRange: call.sourceRange),
                    type: TIRType.AddressType(selfType), ownership: .MutableBorrowing
                )
            } else {
                builder.emitWithResult(
                    TIR.AllocStack(selfType, sourceRange: call.sourceRange),
                    type: TIRType.AddressType(selfType), ownership: .MutableBorrowing
                )
            }
            arguments.append(selfAddress)
        }
        if let member = call.callee as? AST.MemberAccess, let functionSymbol = resolvedSymbol,
           !functionSymbol.isStatic, let object = visitExpression(member.object),
           !isReferenceType(member.object.ty)
        {
            arguments.append(object)
        }
        arguments.append(contentsOf: call.arguments.compactMap { visitExpression($0.value) })
        for (_, closure) in call.trailingClosures {
            if let value = visitExpression(closure) {
                arguments.append(value)
            }
        }
        for argument in arguments {
            emitRetainIfNeeded(argument, range: call.sourceRange)
        }
        let substitutions = substitutionsFor(call)
        let resultType = (call.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        let resultOwnership = typeLower.ownership(for: resultType)
        if let errorBlock = tryErrorBlock, resolvedSymbol?.functionType?.isThrowing == true {
            let successBlock = builder.createBlock()
            let errorType = errorArgumentType(resolvedSymbol)
            let errorArgument = TIR.Argument(name: "error", type: errorType, ownership: .Owned)
            errorBlock.arguments.append(errorArgument)
            let instruction = TIR.TryApply(
                callee: calleeValue, arguments: arguments, substitutions: substitutions,
                successBlock: successBlock, errorBlock: errorBlock,
                sourceRange: call.sourceRange
            )
            let result = builder.emitWithResult(
                instruction, type: resultType, ownership: resultOwnership
            )
            builder.switchToBlock(successBlock)
            return result
        }
        return builder.emitWithResult(
            TIR.Apply(
                callee: calleeValue, arguments: arguments, substitutions: substitutions,
                sourceRange: call.sourceRange
            ),
            type: resultType, ownership: resultOwnership
        )
    }

    private func errorArgumentType(_ symbol: Symbol.FunctionSymbol?) -> TIRType.TIRType {
        guard let symbol, let first = symbol.functionType?.throwsTypes.first else {
            return TIRType.VoidType()
        }
        return typeLower.lower(first)
    }

    private func isReferenceType(_ type: TrussType.TrussType?) -> Bool {
        type is TrussType.ClassType || type is TrussType.ActorType
    }

    private func substitutionsFor(_ call: AST.Call) -> [TIR.Substitution] {
        guard let application = call.callee as? AST.GenericApplication else { return [] }
        return application.genericArguments.compactMap { argument in
            argument.ty.map {
                TIR.Substitution(genericParam: nil, concreteType: typeLower.lower($0))
            }
        }
    }

    private func lowerCallee(_ callee: AST.Expression, at range: SourceRange) -> TIR.Value? {
        switch callee {
        case let variable as AST.Variable:
            if let functionSymbol = variable.symbol as? Symbol.FunctionSymbol
                ?? variable.overloads?.first
            {
                return functionRefValue(functionSymbol, at: range)
            }
            if let typeSymbol = variable.symbol as? Symbol.NominalTypeSymbol,
               let initFunction = initFunctionsByType[typeSymbol.id]
            {
                return builder?.emitWithResult(
                    TIR.FunctionRef(initFunction, sourceRange: range),
                    type: initFunctionType(initFunction), ownership: .Trivial
                )
            }
            return visitExpression(callee)
        case let member as AST.MemberAccess:
            if let functionSymbol = member.symbol as? Symbol.FunctionSymbol
                ?? member.overloads?.first
            {
                if functionSymbol.isStatic {
                    return functionRefValue(functionSymbol, at: range)
                }
                guard let object = visitExpression(member.object) else { return nil }
                if isReferenceType(member.object.ty) {
                    return builder?.emitWithResult(
                        TIR.ClassMethod(object, methodSymbol: functionSymbol, sourceRange: range),
                        type: methodType(functionSymbol), ownership: .Trivial
                    )
                }
                return functionRefValue(functionSymbol, at: range)
            }
            return visitExpression(callee)
        case let application as AST.GenericApplication:
            return lowerCallee(application.base, at: range)
        default:
            return visitExpression(callee)
        }
    }

    private func methodType(_ symbol: Symbol.FunctionSymbol) -> TIRType.TIRType {
        symbol.functionType.map { typeLower.lower($0) } ?? TIRType.VoidType()
    }

    private func getterType(_ getter: TIR.Function) -> TIRType.TIRType {
        let selfType = getter.arguments.first?.type ?? TIRType.VoidType()
        return TIRType.FunctionType(
            parameters: [TIRType.FunctionType.Parameter(label: nil, type: selfType)],
            returnType: getter.returnType
        )
    }

    private func accessorType(_ function: TIR.Function, withValue: Bool) -> TIRType.TIRType {
        let selfType = function.arguments.first?.type ?? TIRType.VoidType()
        var parameters = [TIRType.FunctionType.Parameter(label: nil, type: selfType)]
        if withValue, let valueType = function.arguments[safe: 1]?.type {
            parameters.append(TIRType.FunctionType.Parameter(label: nil, type: valueType))
        }
        return TIRType.FunctionType(parameters: parameters, returnType: function.returnType)
    }

    private func initFunctionFor(
        _ call: AST.Call, resolvedSymbol: Symbol.FunctionSymbol?
    ) -> TIR.Function? {
        guard resolvedSymbol?.name == "init", let symbol = resolvedSymbol,
              let function = functionsBySymbol[symbol.id], !function.arguments.isEmpty
        else {
            return nil
        }
        return function
    }

    private func initFunctionType(_ function: TIR.Function) -> TIRType.TIRType {
        let parameters = function.arguments.map {
            TIRType.FunctionType.Parameter(label: nil, type: $0.type)
        }
        return TIRType.FunctionType(parameters: parameters, returnType: function.returnType)
    }

    private func functionRefValue(_ symbol: Symbol.FunctionSymbol, at range: SourceRange) -> TIR.Value? {
        guard let builder, let function = functionsBySymbol[symbol.id] else { return nil }
        let functionType = symbol.functionType.map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.FunctionRef(function, sourceRange: range), type: functionType, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        guard let builder, let symbol = memberAccess.symbol else { return nil }
        if let functionSymbol = symbol as? Symbol.FunctionSymbol {
            if functionSymbol.isStatic {
                return functionRefValue(functionSymbol, at: memberAccess.sourceRange)
            }
            guard let object = visitExpression(memberAccess.object) else { return nil }
            if isReferenceType(memberAccess.object.ty) {
                return builder.emitWithResult(
                    TIR.ClassMethod(object, methodSymbol: functionSymbol, sourceRange: memberAccess.sourceRange),
                    type: methodType(functionSymbol), ownership: .Trivial
                )
            }
            return functionRefValue(functionSymbol, at: memberAccess.sourceRange)
        }
        if let caseSymbol = symbol as? Symbol.CaseSymbol {
            return enumValue(caseSymbol, payload: nil, at: memberAccess.sourceRange)
        }
        if let variableSymbol = symbol as? Symbol.VariableSymbol,
           staticVariableSymbols.contains(variableSymbol.id)
        {
            guard let global = globalsBySymbol[variableSymbol.id] else { return nil }
            let address = builder.emitWithResult(
                TIR.GlobalAddr(global, sourceRange: memberAccess.sourceRange),
                type: TIRType.AddressType(global.type), ownership: .MutableBorrowing
            )
            return loadFrom(address, range: memberAccess.sourceRange)
        }
        guard let object = visitExpression(memberAccess.object) else { return nil }
        if let variableSymbol = symbol as? Symbol.VariableSymbol,
           let getter = accessorFunctions[variableSymbol.id]?["get"]
        {
            let callee = builder.emitWithResult(
                TIR.FunctionRef(getter, sourceRange: memberAccess.sourceRange),
                type: getterType(getter), ownership: .Trivial
            )
            return builder.emitWithResult(
                TIR.Apply(
                    callee: callee, arguments: [object], substitutions: [],
                    sourceRange: memberAccess.sourceRange
                ),
                type: getter.returnType, ownership: typeLower.ownership(for: getter.returnType)
            )
        }
        let memberType = variableSymbolType(symbol) ?? TIRType.VoidType()
        let isClass = isReferenceType(memberAccess.object.ty)
        let address: TIR.Value = if isClass {
            builder.emitWithResult(
                TIR.RefElementAddr(
                    object, fieldIndex: 0, fieldName: memberAccess.member.value,
                    sourceRange: memberAccess.sourceRange
                ),
                type: TIRType.AddressType(memberType), ownership: .MutableBorrowing
            )
        } else {
            builder.emitWithResult(
                TIR.StructElementAddr(
                    object, fieldIndex: 0, fieldName: memberAccess.member.value,
                    sourceRange: memberAccess.sourceRange
                ),
                type: TIRType.AddressType(memberType), ownership: .MutableBorrowing
            )
        }
        return loadFrom(address, range: memberAccess.sourceRange)
    }

    private func variableSymbolType(_ symbol: Symbol.Symbol) -> TIRType.TIRType? {
        if let variableSymbol = symbol as? Symbol.VariableSymbol, let type = variableSymbol.type {
            return typeLower.lower(type)
        }
        if let caseSymbol = symbol as? Symbol.CaseSymbol {
            return typeLower.lower(caseSymbol.associatedTypes.first ?? TrussType.VoidType.INSTANCE)
        }
        return nil
    }

    @discardableResult
    public override func visitImplicitMemberAccess(
        _ implicitMember: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        guard let symbol = implicitMember.symbol else { return nil }
        if let caseSymbol = symbol as? Symbol.CaseSymbol {
            return enumValue(caseSymbol, payload: nil, at: implicitMember.sourceRange)
        }
        return nil
    }

    private func enumValue(
        _ caseSymbol: Symbol.CaseSymbol, payload: TIR.Value?, at range: SourceRange
    ) -> TIR.Value? {
        guard let builder, let enumType = enumTypeValue(for: caseSymbol) else { return nil }
        return builder.emitWithResult(
            TIR.EnumValue(
                enumType, caseName: caseSymbol.name, payload: payload, sourceRange: range
            ),
            type: enumType, ownership: typeLower.ownership(for: enumType)
        )
    }

    private func enumTypeValue(for caseSymbol: Symbol.CaseSymbol) -> TIRType.EnumType? {
        guard let memberOf = caseSymbol.memberOf,
              let enumSymbol = context.id2Symbol[memberOf] as? Symbol.EnumSymbol,
              let typeId = enumSymbol.typeId, let type = context.typeTable[typeId]
        else {
            return nil
        }
        return typeLower.lower(type) as? TIRType.EnumType
    }

    @discardableResult
    public override func visitBinary(_ binary: AST.Binary, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        if binary.operatorToken.value == "=" {
            return emitAssignment(binary)
        }
        if binary.operatorToken.value == "&&" {
            return emitShortCircuitAnd(binary)
        }
        let left = visitExpression(binary.left)
        let right = visitExpression(binary.right)
        guard let functionSymbol = binary.symbol, let function = functionsBySymbol[functionSymbol.id]
        else {
            return nil
        }
        let callee = builder.emitWithResult(
            TIR.FunctionRef(function, sourceRange: binary.sourceRange),
            type: methodType(functionSymbol), ownership: .Trivial
        )
        let resultType = (binary.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        var arguments: [TIR.Value] = []
        if let left { arguments.append(left) }
        if let right { arguments.append(right) }
        return builder.emitWithResult(
            TIR.Apply(
                callee: callee, arguments: arguments, substitutions: [],
                sourceRange: binary.sourceRange
            ),
            type: resultType, ownership: typeLower.ownership(for: resultType)
        )
    }

    private func emitShortCircuitAnd(_ binary: AST.Binary) -> TIR.Value? {
        guard let builder, let left = visitExpression(binary.left) else { return nil }
        let resultType = (binary.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        let rhsBlock = builder.createBlock()
        let falseBlock = builder.createBlock()
        let joinBlock = builder.createBlock()
        builder.emit(
            TIR.CondBranch(
                condition: left, trueBlock: rhsBlock, falseBlock: falseBlock,
                sourceRange: binary.sourceRange
            )
        )
        var incomings: [(TIR.Value, TIR.BasicBlock)] = []
        builder.switchToBlock(rhsBlock)
        if let right = visitExpression(binary.right) {
            incomings.append((right, rhsBlock))
        } else {
            let falseValue = builder.emitWithResult(
                TIR.BoolLiteral(false, sourceRange: binary.sourceRange),
                type: resultType, ownership: .Trivial
            )
            incomings.append((falseValue, rhsBlock))
        }
        builder.emit(TIR.Branch(joinBlock, sourceRange: binary.sourceRange))
        builder.switchToBlock(falseBlock)
        let falseValue = builder.emitWithResult(
            TIR.BoolLiteral(false, sourceRange: binary.sourceRange),
            type: resultType, ownership: .Trivial
        )
        incomings.append((falseValue, falseBlock))
        builder.emit(TIR.Branch(joinBlock, sourceRange: binary.sourceRange))
        builder.switchToBlock(joinBlock)
        return emitPhi(incomings, range: binary.sourceRange)
    }

    private func emitAssignment(_ binary: AST.Binary) -> TIR.Value? {
        guard let builder else { return nil }
        let range = binary.sourceRange
        guard let value = visitExpression(binary.right) else { return nil }
        if let member = binary.left as? AST.MemberAccess,
           let symbol = member.symbol as? Symbol.VariableSymbol
        {
            return emitPropertyAssignment(member, symbol: symbol, value: value, range: range)
        }
        if let variable = binary.left as? AST.Variable, let symbol = variable.symbol {
            if let address = env[symbol.id] {
                emitRetainIfNeeded(value, range: range)
                builder.emit(TIR.Store(value, to: address, sourceRange: range))
                return value
            }
            if let memberOf = symbol.memberOf, let selfAddress = env[memberOf],
               let property = symbol as? Symbol.VariableSymbol
            {
                return emitImplicitPropertyAssignment(
                    property, selfAddress: selfAddress, value: value, range: range
                )
            }
        }
        return nil
    }

    private func emitImplicitPropertyAssignment(
        _ symbol: Symbol.VariableSymbol, selfAddress: TIR.Value, value: TIR.Value,
        range: SourceRange
    ) -> TIR.Value? {
        guard let builder else { return nil }
        let accessors = accessorFunctions[symbol.id] ?? [:]
        let selfValue = loadFrom(selfAddress, range: range) ?? selfAddress
        if let setter = accessors["set"] {
            emitAccessorCall(setter, arguments: [selfValue, value], range: range)
            return value
        }
        if accessors["get"] != nil {
            return nil
        }
        let propertyType = symbol.type.map { typeLower.lower($0) } ?? TIRType.VoidType()
        guard let address = implicitPropertyElementAddress(
            symbol, selfAddress: selfAddress, propertyType: propertyType, range: range
        ) else {
            return nil
        }
        if let willSet = accessors["willSet"] {
            emitAccessorCall(willSet, arguments: [selfValue, value], range: range)
        }
        if let didSet = accessors["didSet"] {
            let oldValue = builder.emitWithResult(
                TIR.Load(address, sourceRange: range),
                type: propertyType, ownership: typeLower.ownership(for: propertyType)
            )
            emitRetainIfNeeded(value, range: range)
            builder.emit(TIR.Store(value, to: address, sourceRange: range))
            emitAccessorCall(didSet, arguments: [selfValue, oldValue], range: range)
        } else {
            emitRetainIfNeeded(value, range: range)
            builder.emit(TIR.Store(value, to: address, sourceRange: range))
        }
        return value
    }

    private func emitPropertyAssignment(
        _ member: AST.MemberAccess, symbol: Symbol.VariableSymbol, value: TIR.Value,
        range: SourceRange
    ) -> TIR.Value? {
        guard let builder else { return nil }
        if staticVariableSymbols.contains(symbol.id) {
            guard let global = globalsBySymbol[symbol.id] else { return nil }
            let address = builder.emitWithResult(
                TIR.GlobalAddr(global, sourceRange: range),
                type: TIRType.AddressType(global.type), ownership: .MutableBorrowing
            )
            emitRetainIfNeeded(value, range: range)
            builder.emit(TIR.Store(value, to: address, sourceRange: range))
            return value
        }
        let accessors = accessorFunctions[symbol.id] ?? [:]
        if accessors["set"] != nil, let object = visitExpression(member.object) {
            emitAccessorCall(accessors["set"]!, arguments: [object, value], range: range)
            return value
        }
        if accessors["get"] != nil {
            return nil
        }
        guard let object = visitExpression(member.object) else { return nil }
        let propertyType = symbol.type.map { typeLower.lower($0) } ?? TIRType.VoidType()
        let base: TIR.Value = if let variable = member.object as? AST.Variable,
                                 let variableSymbol = variable.symbol,
                                 let address = env[variableSymbol.id]
        {
            address
        } else {
            object
        }
        guard let address = propertyElementAddress(
            member, base: base, propertyType: propertyType, range: range
        ) else {
            return nil
        }
        if let willSet = accessors["willSet"] {
            emitAccessorCall(willSet, arguments: [object, value], range: range)
        }
        if let didSet = accessors["didSet"] {
            let oldValue = builder.emitWithResult(
                TIR.Load(address, sourceRange: range),
                type: propertyType, ownership: typeLower.ownership(for: propertyType)
            )
            emitRetainIfNeeded(value, range: range)
            builder.emit(TIR.Store(value, to: address, sourceRange: range))
            emitAccessorCall(didSet, arguments: [object, oldValue], range: range)
        } else {
            emitRetainIfNeeded(value, range: range)
            builder.emit(TIR.Store(value, to: address, sourceRange: range))
        }
        return value
    }

    private func emitAccessorCall(
        _ function: TIR.Function, arguments: [TIR.Value], range: SourceRange
    ) {
        guard let builder else { return }
        let callee = builder.emitWithResult(
            TIR.FunctionRef(function, sourceRange: range),
            type: accessorType(function, withValue: !arguments.isEmpty), ownership: .Trivial
        )
        builder.emitWithResult(
            TIR.Apply(
                callee: callee, arguments: arguments, substitutions: [],
                sourceRange: range
            ),
            type: TIRType.VoidType(), ownership: .Trivial
        )
    }

    private func propertyElementAddress(
        _ member: AST.MemberAccess, base: TIR.Value, propertyType: TIRType.TIRType,
        range: SourceRange
    ) -> TIR.Value? {
        guard let builder else { return nil }
        let isClass = isReferenceType(member.object.ty)
        return builder.emitWithResult(
            isClass
                ? TIR.RefElementAddr(
                    base, fieldIndex: 0, fieldName: member.member.value,
                    sourceRange: range
                )
                : TIR.StructElementAddr(
                    base, fieldIndex: 0, fieldName: member.member.value,
                    sourceRange: range
                ),
            type: TIRType.AddressType(propertyType), ownership: .MutableBorrowing
        )
    }

    @discardableResult
    public override func visitPrefix(_ prefix: AST.Prefix, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let operand = visitExpression(prefix.expression)
        guard let functionSymbol = prefix.symbol, let function = functionsBySymbol[functionSymbol.id]
        else {
            return nil
        }
        let callee = builder.emitWithResult(
            TIR.FunctionRef(function, sourceRange: prefix.sourceRange),
            type: methodType(functionSymbol), ownership: .Trivial
        )
        let resultType = (prefix.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        var arguments: [TIR.Value] = []
        if let operand { arguments.append(operand) }
        return builder.emitWithResult(
            TIR.Apply(
                callee: callee, arguments: arguments, substitutions: [],
                sourceRange: prefix.sourceRange
            ),
            type: resultType, ownership: typeLower.ownership(for: resultType)
        )
    }

    @discardableResult
    public override func visitPostfix(_ postfix: AST.Postfix, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let operand = visitExpression(postfix.expression)
        guard let functionSymbol = postfix.symbol, let function = functionsBySymbol[functionSymbol.id]
        else {
            return nil
        }
        let callee = builder.emitWithResult(
            TIR.FunctionRef(function, sourceRange: postfix.sourceRange),
            type: methodType(functionSymbol), ownership: .Trivial
        )
        let resultType = (postfix.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        var arguments: [TIR.Value] = []
        if let operand { arguments.append(operand) }
        return builder.emitWithResult(
            TIR.Apply(
                callee: callee, arguments: arguments, substitutions: [],
                sourceRange: postfix.sourceRange
            ),
            type: resultType, ownership: typeLower.ownership(for: resultType)
        )
    }

    @discardableResult
    public override func visitDereference(
        _ dereference: AST.Dereference, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        guard let pointer = visitExpression(dereference.expression) else { return nil }
        let type = (dereference.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.Load(pointer, sourceRange: dereference.sourceRange),
            type: type, ownership: typeLower.ownership(for: type)
        )
    }

    @discardableResult
    public override func visitAddressOf(_ addressOf: AST.AddressOf, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        guard let address = addressValue(addressOf.expression, range: addressOf.sourceRange) else {
            return nil
        }
        let type = (addressOf.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.AddressToPointer(address, sourceRange: addressOf.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    private func addressValue(_ expression: AST.Expression, range: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        switch expression {
        case let variable as AST.Variable:
            guard let symbol = variable.symbol else { return nil }
            if let global = globalsBySymbol[symbol.id] {
                return builder.emitWithResult(
                    TIR.GlobalAddr(global, sourceRange: range),
                    type: TIRType.AddressType(global.type), ownership: .MutableBorrowing
                )
            }
            if let address = env[symbol.id] {
                return address
            }
            if let memberOf = symbol.memberOf, let selfAddress = env[memberOf],
               let property = symbol as? Symbol.VariableSymbol
            {
                let propertyType = property.type.map { typeLower.lower($0) }
                    ?? TIRType.VoidType()
                return implicitPropertyElementAddress(
                    property, selfAddress: selfAddress, propertyType: propertyType, range: range
                )
            }
            return nil
        case let member as AST.MemberAccess:
            guard let variableSymbol = member.symbol as? Symbol.VariableSymbol,
                  accessorFunctions[variableSymbol.id]?["get"] == nil,
                  let object = visitExpression(member.object)
            else {
                return nil
            }
            let memberType = variableSymbolType(variableSymbol) ?? TIRType.VoidType()
            let isClass = isReferenceType(member.object.ty)
            return builder.emitWithResult(
                isClass
                    ? TIR.RefElementAddr(
                        object, fieldIndex: 0, fieldName: member.member.value,
                        sourceRange: range
                    )
                    : TIR.StructElementAddr(
                        object, fieldIndex: 0, fieldName: member.member.value,
                        sourceRange: range
                    ),
                type: TIRType.AddressType(memberType), ownership: .MutableBorrowing
            )
        case let dereference as AST.Dereference:
            return visitExpression(dereference.expression)
        default:
            return nil
        }
    }

    @discardableResult
    public override func visitArrayLiteral(
        _ arrayLiteral: AST.ArrayLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let elements = arrayLiteral.elements.compactMap { visitExpression($0) }
        let type = (arrayLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.ArrayValue(elements: elements, sourceRange: arrayLiteral.sourceRange), type: type,
            ownership: typeLower.ownership(for: type)
        )
    }

    @discardableResult
    public override func visitDictionaryLiteral(
        _ dictionaryLiteral: AST.DictionaryLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let entries = dictionaryLiteral.entries.compactMap { entry -> TIR.DictionaryValue.Entry? in
            guard let key = visitExpression(entry.key), let value = visitExpression(entry.value)
            else {
                return nil
            }
            return TIR.DictionaryValue.Entry(key: key, value: value)
        }
        let type = (dictionaryLiteral.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.DictionaryValue(entries: entries, sourceRange: dictionaryLiteral.sourceRange),
            type: type, ownership: typeLower.ownership(for: type)
        )
    }

    @discardableResult
    public override func visitCast(_ cast: AST.Cast, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        guard let value = visitExpression(cast.left) else { return nil }
        let targetType = (cast.right.ty).map { typeLower.lower($0) }
            ?? (cast.ty).map { typeLower.lower($0) }
            ?? TIRType.VoidType()
        switch cast.kind {
        case .As:
            if cast.right.ty is TrussType.ProtocolType
                || cast.right.ty is TrussType.CompositionType
            {
                guard let existential = targetType as? TIRType.ExistentialType else {
                    return builder.emitWithResult(
                        TIR.Upcast(value, to: targetType, sourceRange: cast.sourceRange),
                        type: targetType, ownership: .Trivial
                    )
                }
                return builder.emitWithResult(
                    TIR.InitExistential(value, to: existential, sourceRange: cast.sourceRange),
                    type: targetType, ownership: .Owned
                )
            }
            return builder.emitWithResult(
                TIR.Upcast(value, to: targetType, sourceRange: cast.sourceRange), type: targetType,
                ownership: .Trivial
            )
        case .OptionalAs:
            let optionalType = TIRType.OptionalType(targetType)
            return builder.emitWithResult(
                TIR.Upcast(value, to: optionalType, sourceRange: cast.sourceRange),
                type: optionalType, ownership: .Trivial
            )
        case .AsExclamation, .AsBitCast:
            return builder.emitWithResult(
                TIR.UncheckedRefCast(value, to: targetType, sourceRange: cast.sourceRange),
                type: targetType, ownership: .Trivial
            )
        case .Is:
            let type = (cast.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
            return builder.emitWithResult(
                TIR.BoolLiteral(true, sourceRange: cast.sourceRange), type: type,
                ownership: .Trivial
            )
        }
    }

    @discardableResult
    public override func visitTry(_ tryExpression: AST.Try, additional: Any? = nil) -> Any? {
        guard let call = tryExpression.expression as? AST.Call else {
            return visitExpression(tryExpression.expression)
        }
        let errorBlock = errorTargets.last?.block ?? builder?.createBlock()
        let result = emitCall(call, tryErrorBlock: errorBlock)
        if errorTargets.isEmpty {
            builder?.emit(TIR.Unreachable(tryExpression.sourceRange))
        }
        return result
    }

    @discardableResult
    public override func visitAwait(_ awaitExpression: AST.Await, additional: Any? = nil) -> Any? {
        visitExpression(awaitExpression.expression)
    }

    @discardableResult
    public override func visitSubscript(
        _ subscriptExpression: AST.Subscript, additional: Any? = nil
    ) -> Any? {
        guard let builder, let base = visitExpression(subscriptExpression.base),
              let functionSymbol = subscriptExpression.symbol,
              let function = functionsBySymbol[functionSymbol.id]
        else {
            return nil
        }
        let callee = builder.emitWithResult(
            TIR.FunctionRef(function, sourceRange: subscriptExpression.sourceRange),
            type: methodType(functionSymbol), ownership: .Trivial
        )
        var arguments = [base]
        arguments.append(
            contentsOf: subscriptExpression.arguments.compactMap { visitExpression($0.value) }
        )
        let resultType = (subscriptExpression.ty).map { typeLower.lower($0) }
            ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.Apply(
                callee: callee, arguments: arguments, substitutions: [],
                sourceRange: subscriptExpression.sourceRange
            ),
            type: resultType, ownership: typeLower.ownership(for: resultType)
        )
    }

    @discardableResult
    public override func visitForceUnwrap(
        _ forceUnwrap: AST.ForceUnwrap, additional: Any? = nil
    ) -> Any? {
        guard let builder, let value = visitExpression(forceUnwrap.expression) else { return nil }
        let resultType = (forceUnwrap.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.UncheckedEnumData(value, caseName: "some", sourceRange: forceUnwrap.sourceRange),
            type: resultType, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitOptionalBinding(
        _ optionalBinding: AST.OptionalBinding, additional: Any? = nil
    ) -> Any? {
        guard let builder, let value = visitExpression(optionalBinding.value) else { return nil }
        let boolType = (optionalBinding.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        let someBlock = builder.createBlock()
        let noneBlock = builder.createBlock()
        builder.emit(
            TIR.SwitchEnum(
                value,
                cases: [
                    TIR.EnumCaseBranch(caseName: "some", block: someBlock),
                    TIR.EnumCaseBranch(caseName: "none", block: noneBlock),
                ],
                defaultBlock: nil, sourceRange: optionalBinding.sourceRange
            )
        )
        let joinBlock = builder.createBlock()
        var incomings: [(TIR.Value, TIR.BasicBlock)] = []
        builder.switchToBlock(someBlock)
        let trueValue = builder.emitWithResult(
            TIR.BoolLiteral(true, sourceRange: optionalBinding.sourceRange),
            type: boolType, ownership: .Trivial
        )
        incomings.append((trueValue, someBlock))
        builder.emit(TIR.Branch(joinBlock, sourceRange: optionalBinding.sourceRange))
        builder.switchToBlock(noneBlock)
        let falseValue = builder.emitWithResult(
            TIR.BoolLiteral(false, sourceRange: optionalBinding.sourceRange),
            type: boolType, ownership: .Trivial
        )
        incomings.append((falseValue, noneBlock))
        builder.emit(TIR.Branch(joinBlock, sourceRange: optionalBinding.sourceRange))
        builder.switchToBlock(joinBlock)
        return emitPhi(incomings, range: optionalBinding.sourceRange)
    }

    @discardableResult
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let captured = analyzeCaptures(closure.body)
        var captureCells: [TIR.Value] = []
        for (symbol, type) in captured {
            if let value = env[symbol.id] {
                let cell = builder.emitWithResult(
                    TIR.AllocCell(type, sourceRange: closure.sourceRange),
                    type: TIRType.AddressType(type), ownership: .MutableBorrowing
                )
                let loaded = loadFrom(value, range: closure.sourceRange) ?? value
                emitRetainIfNeeded(loaded, range: closure.sourceRange)
                builder.emit(TIR.Store(loaded, to: cell, sourceRange: closure.sourceRange))
                captureCells.append(cell)
            }
        }
        let closureType = (closure.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        let returnType = (closureType as? TIRType.FunctionType)?.returnType ?? TIRType.VoidType()
        let isThrowing = (closureType as? TIRType.FunctionType)?.isThrowing ?? false
        let throwsTypes = (closureType as? TIRType.FunctionType)?.throwsTypes ?? []
        let ownerName = builder.function.name
        let name = ownerName + "_closure_" + String(closureCounter)
        closureCounter += 1
        let function = createFunction(
            nil, name: name, returnType: returnType, isAsync: false, isThrowing: isThrowing,
            throwsTypes: throwsTypes
        )
        let savedBuilder = builder
        let savedEnv = env
        let savedCaptured = capturedCells
        let savedBreak = breakStack
        let savedDefer = deferStack
        let savedError = errorTargets
        let savedClosureParams = closureParamValues
        let savedSemanticScopes = semanticScopes

        self.builder = TIRBuilder(function: function)
        env = [:]
        capturedCells = []
        breakStack = []
        deferStack = []
        errorTargets = []
        closureParamValues = []
        pushScope()
        if let scope = closure.scope {
            semanticScopes.append(scope)
        }

        for (index, (symbol, type)) in captured.enumerated() {
            if index < captureCells.count {
                let cellArgument = builder.createArgument(
                    type: TIRType.AddressType(type), ownership: .MutableBorrowing
                )
                function.arguments.append(cellArgument)
                env[symbol.id] = cellArgument
                capturedCells.insert(symbol.id)
            }
        }
        let parameters = closure.signature?.parameters ?? []
        var paramValues: [TIR.Value] = []
        for (index, parameter) in parameters.enumerated() {
            let paramType = (parameter.type?.ty).map { typeLower.lower($0) }
                ?? TIRType.VoidType()
            let argument = builder.createArgument(
                type: paramType, ownership: typeLower.ownership(for: paramType)
            )
            function.arguments.append(argument)
            let address = builder.emitWithResult(
                TIR.AllocStack(paramType, sourceRange: parameter.sourceRange),
                type: TIRType.AddressType(paramType), ownership: .MutableBorrowing
            )
            builder.emit(TIR.Store(argument, to: address, sourceRange: parameter.sourceRange))
            paramValues.append(argument)
            let variableSymbol = closure.scope?.values[parameter.name.value]?
                .compactMap { $0 as? Symbol.VariableSymbol }.first
            if let variableSymbol {
                env[variableSymbol.id] = address
            }
            if needsRelease(paramType) {
                registerBinding(
                    LocalBinding(
                        symbol: variableSymbol?.id ?? Id.SymbolId(id: 0), type: paramType,
                        address: address
                    )
                )
            }
            _ = index
        }
        if !paramValues.isEmpty {
            closureParamValues.append(paramValues)
        }
        let implicitReturn = !(returnType is TIRType.VoidType)
        visitBodyStatements(closure.body, implicitReturn: implicitReturn)
        ensureTerminator(range: closure.sourceRange)

        self.builder = savedBuilder
        env = savedEnv
        capturedCells = savedCaptured
        breakStack = savedBreak
        deferStack = savedDefer
        errorTargets = savedError
        closureParamValues = savedClosureParams
        semanticScopes = savedSemanticScopes

        return builder.emitWithResult(
            TIR.Closure(function, captures: captureCells, sourceRange: closure.sourceRange),
            type: closureType, ownership: .Owned
        )
    }

    private func analyzeCaptures(_ statements: [AST.Statement]) -> [(Symbol.Symbol, TIRType.TIRType)] {
        var result: [(Symbol.Symbol, TIRType.TIRType)] = []
        var seen = Set<Id.SymbolId>()
        collectCaptureCandidates(statements, into: &result, seen: &seen)
        return result
    }

    private func collectCaptureCandidates(
        _ statements: [AST.Statement], into result: inout [(Symbol.Symbol, TIRType.TIRType)],
        seen: inout Set<Id.SymbolId>
    ) {
        for statement in statements {
            switch statement {
            case let expressionStatement as AST.ExpressionStatement:
                collectExpressionCandidates(
                    expressionStatement.expression, into: &result, seen: &seen
                )
            case let variableDecl as AST.VariableDecl:
                if let initializer = variableDecl.initializer {
                    collectExpressionCandidates(initializer, into: &result, seen: &seen)
                }
            case let returnStatement as AST.Return:
                if let value = returnStatement.value {
                    collectExpressionCandidates(value, into: &result, seen: &seen)
                }
            case let throwStatement as AST.Throw:
                collectExpressionCandidates(throwStatement.expression, into: &result, seen: &seen)
            case let whileStatement as AST.While:
                collectExpressionCandidates(whileStatement.condition, into: &result, seen: &seen)
                collectCaptureCandidates(whileStatement.body, into: &result, seen: &seen)
            case let repeatWhile as AST.RepeatWhile:
                collectExpressionCandidates(repeatWhile.condition, into: &result, seen: &seen)
                collectCaptureCandidates(repeatWhile.body, into: &result, seen: &seen)
            case let guardStatement as AST.Guard:
                collectExpressionCandidates(guardStatement.condition, into: &result, seen: &seen)
                collectCaptureCandidates(guardStatement.body, into: &result, seen: &seen)
            case let forStatement as AST.For:
                collectExpressionCandidates(forStatement.sequence, into: &result, seen: &seen)
                if let whereClause = forStatement.whereClause {
                    collectExpressionCandidates(whereClause, into: &result, seen: &seen)
                }
                collectCaptureCandidates(forStatement.body, into: &result, seen: &seen)
            case let deferStatement as AST.Defer:
                collectCaptureCandidates(deferStatement.body, into: &result, seen: &seen)
            default:
                break
            }
        }
    }

    private func collectExpressionCandidates(
        _ expression: AST.Expression, into result: inout [(Symbol.Symbol, TIRType.TIRType)],
        seen: inout Set<Id.SymbolId>
    ) {
        switch expression {
        case let variable as AST.Variable:
            if let symbol = variable.symbol, env[symbol.id] != nil, !seen.contains(symbol.id) {
                seen.insert(symbol.id)
                let type = (variable.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
                result.append((symbol, type))
            }
        case let parenthetical as AST.Parenthetical:
            collectExpressionCandidates(parenthetical.inner, into: &result, seen: &seen)
        case let call as AST.Call:
            collectExpressionCandidates(call.callee, into: &result, seen: &seen)
            for argument in call.arguments {
                collectExpressionCandidates(argument.value, into: &result, seen: &seen)
            }
            for (_, closure) in call.trailingClosures {
                collectExpressionCandidates(closure, into: &result, seen: &seen)
            }
        case let member as AST.MemberAccess:
            collectExpressionCandidates(member.object, into: &result, seen: &seen)
        case let tuple as AST.Tuple:
            for element in tuple.elements {
                collectExpressionCandidates(element.value, into: &result, seen: &seen)
            }
        case let binary as AST.Binary:
            collectExpressionCandidates(binary.left, into: &result, seen: &seen)
            collectExpressionCandidates(binary.right, into: &result, seen: &seen)
        case let prefix as AST.Prefix:
            collectExpressionCandidates(prefix.expression, into: &result, seen: &seen)
        case let postfix as AST.Postfix:
            collectExpressionCandidates(postfix.expression, into: &result, seen: &seen)
        case let ifExpression as AST.If:
            collectExpressionCandidates(ifExpression.condition, into: &result, seen: &seen)
            collectCaptureCandidates(ifExpression.then, into: &result, seen: &seen)
            if let elseKind = ifExpression.elseKind {
                switch elseKind {
                case let .Block(statements):
                    collectCaptureCandidates(statements, into: &result, seen: &seen)
                case let .If(nested):
                    collectExpressionCandidates(nested, into: &result, seen: &seen)
                }
            }
        case let matchExpression as AST.Match:
            collectExpressionCandidates(matchExpression.subject, into: &result, seen: &seen)
            for matchCase in matchExpression.cases {
                for pattern in matchCase.patterns {
                    collectExpressionCandidates(pattern, into: &result, seen: &seen)
                }
                collectCaptureCandidates(matchCase.body, into: &result, seen: &seen)
            }
        case let doExpression as AST.Do:
            collectCaptureCandidates(doExpression.body, into: &result, seen: &seen)
            for catchClause in doExpression.catches {
                if let pattern = catchClause.pattern {
                    collectExpressionCandidates(pattern, into: &result, seen: &seen)
                }
                collectCaptureCandidates(catchClause.body, into: &result, seen: &seen)
            }
            if let finallyBody = doExpression.finallyBody {
                collectCaptureCandidates(finallyBody, into: &result, seen: &seen)
            }
        case let closure as AST.Closure:
            collectCaptureCandidates(closure.body, into: &result, seen: &seen)
        case let arrayLiteral as AST.ArrayLiteral:
            for element in arrayLiteral.elements {
                collectExpressionCandidates(element, into: &result, seen: &seen)
            }
        case let dictionaryLiteral as AST.DictionaryLiteral:
            for entry in dictionaryLiteral.entries {
                collectExpressionCandidates(entry.key, into: &result, seen: &seen)
                collectExpressionCandidates(entry.value, into: &result, seen: &seen)
            }
        case let cast as AST.Cast:
            collectExpressionCandidates(cast.left, into: &result, seen: &seen)
        case let tryExpression as AST.Try:
            collectExpressionCandidates(tryExpression.expression, into: &result, seen: &seen)
        case let awaitExpression as AST.Await:
            collectExpressionCandidates(awaitExpression.expression, into: &result, seen: &seen)
        case let subscriptExpression as AST.Subscript:
            collectExpressionCandidates(subscriptExpression.base, into: &result, seen: &seen)
            for argument in subscriptExpression.arguments {
                collectExpressionCandidates(argument.value, into: &result, seen: &seen)
            }
        case let forceUnwrap as AST.ForceUnwrap:
            collectExpressionCandidates(forceUnwrap.expression, into: &result, seen: &seen)
        case let optionalBinding as AST.OptionalBinding:
            collectExpressionCandidates(optionalBinding.value, into: &result, seen: &seen)
        case let stringInterpolation as AST.StringInterpolation:
            for segment in stringInterpolation.segments {
                if case let .expression(expression) = segment {
                    collectExpressionCandidates(expression, into: &result, seen: &seen)
                }
            }
        default:
            break
        }
    }

    @discardableResult
    public override func visitStringInterpolation(
        _ interpolation: AST.StringInterpolation, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        var text = ""
        for segment in interpolation.segments {
            switch segment {
            case let .literal(token):
                text += token.value
            case let .expression(expression):
                _ = visitExpression(expression)
            }
        }
        let type = (interpolation.ty).map { typeLower.lower($0) } ?? TIRType.VoidType()
        return builder.emitWithResult(
            TIR.StringLiteral(text, sourceRange: interpolation.sourceRange), type: type,
            ownership: .Owned
        )
    }

    @discardableResult
    public override func visitShorthandArgument(
        _ shorthand: AST.ShorthandArgument, additional: Any? = nil
    ) -> Any? {
        guard let values = closureParamValues.last, shorthand.index < values.count else {
            return nil
        }
        return values[shorthand.index]
    }

    @discardableResult
    public override func visitKeyPathExpression(
        _ keyPath: AST.KeyPathExpression, additional: Any? = nil
    ) -> Any? {
        builder?.emit(TIR.Trap(keyPath.sourceRange))
        return nil
    }

    @discardableResult
    public override func visitErrorExpression(
        _ errorExpression: AST.ErrorExpression, additional: Any? = nil
    ) -> Any? {
        nil
    }

    private func visitBodyStatements(_ statements: [AST.Statement], implicitReturn: Bool) {
        for (index, statement) in statements.enumerated() {
            if implicitReturn, index == statements.count - 1,
               let expressionStatement = statement as? AST.ExpressionStatement
            {
                visitImplicitReturnExpression(
                    expressionStatement.expression, range: expressionStatement.sourceRange
                )
                return
            }
            visit(statement)
        }
    }

    private func visitImplicitReturnExpression(_ expression: AST.Expression, range: SourceRange) {
        if let match = expression as? AST.Match {
            visitMatch(match, implicitReturn: true)
        } else if let value = visitExpression(expression) {
            emitReturn(value, range: range)
        }
    }

    private func shouldImplicitReturn(_ type: TrussType.TrussType?) -> Bool {
        guard let type else { return false }
        return !(type is TrussType.VoidType)
    }

    private func emitReturn(_ value: TIR.Value?, range: SourceRange) {
        runDeferred()
        releaseAllScopes(range: range)
        builder?.emit(TIR.Return(value, sourceRange: range))
    }

    private func runDeferred() {
        for statements in deferStack.reversed() {
            for statement in statements {
                visit(statement)
            }
        }
    }

    private var emptyRange: SourceRange {
        let buffer = StringSourceBuffer(filePath: "", content: "")
        let location = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
        return SourceRange(start: location, end: location)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
