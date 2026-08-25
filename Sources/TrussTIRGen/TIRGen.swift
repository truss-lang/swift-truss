import SwiftBetterDiagnostic
import TrussCore

public final class TIRGen: AST.Visitor {
    private let context: Context
    private let gen: GenerationContext
    private let collector: TypeCollector

    public init(context: Context) {
        self.context = context
        let mangler = TypeMangler(context: context)
        let typeLower = TypeLower(context: context, mangler: mangler)
        gen = GenerationContext(context: context, mangler: mangler, typeLower: typeLower)
        collector = TypeCollector(context: context)
    }

    public func generate(_ program: AST.Program) -> TIR.Module {
        generateAll([program])[0]
    }

    public func generateAll(_ programs: [AST.Program]) -> [TIR.Module] {
        for program in programs {
            collector.collect(program)
        }
        gen.typeLower.setStoredProperties(collector.storedProperties)
        gen.typeLower.setEnumCases(collector.enumCases)
        var modules: [TIR.Module] = []
        for program in programs {
            let module = gen.makeModule()
            modules.append(module)
            collectFunctions(in: program)
        }
        for program in programs {
            gen.builder = nil
            gen.env = [:]
            gen.modulePathStack = []
            gen.externContextStack = []
            gen.collectTypeStack = []
            gen.typeLower.setModulePath([])
            visitProgram(program)
        }
        return modules
    }

    private func cname(_ attributes: [AST.Attribute]) -> String? {
        for attribute in attributes {
            guard attribute.name.value == "cname" else { continue }
            guard attribute.arguments.count == 1 else {
                context.emitError(
                    "cname attribute expects exactly one argument", at: attribute.name
                )
                return nil
            }
            return attribute.arguments.first?.first?.value ?? nil
        }
        return nil
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
        let name = cname(decl.attributes) ?? gen.mangler.mangleFunctionName(
            symbol, baseName: "subscript",
            returnType: functionType?.returnType ?? TrussType.VoidType.INSTANCE,
            modulePath: gen.modulePathStack
        )
        createFunction(
            symbol, name: name, returnType: returnType,
            parameters: decl.parameters, symbolType: symbol
        )
    }

    private func createFunction(
        _ symbol: Symbol.FunctionSymbol?, name: String, returnType: TIRType.TIRType,
        parameters: [AST.FunctionDecl.Parameter] = [], symbolType: Symbol.FunctionSymbol? = nil,
        isVariadic: Bool = false, isExtern: Bool = false, callingConvention: String? = nil
    ) -> TIR.Function {
        let tirParameters: [TIR.Parameter] = parameters.enumerated().map { index, parameter in
            let ty = symbolType?.functionType?.parameters[safe: index].map { gen.typeLower.lower($0.type) }
                ?? (parameter.type?.ty).map { gen.typeLower.lower($0) }
                ?? gen.registry.voidType()
            return TIR.Parameter(ty: ty.id, name: parameter.name.value)
        }
        let function = gen.currentModule!.addFunction(
            name: name, parameters: tirParameters, returnType: returnType.id,
            isVariadic: isVariadic, isExtern: isExtern, callingConvention: callingConvention
        )
        if let symbol {
            gen.functionsBySymbol[symbol.id] = function
        }
        return function
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
        let _ = memberOf
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

    private func isStaticDecl(_ decl: AST.VariableDecl) -> Bool {
        decl.modifiers.contains { modifier in
            if case .Static = modifier.kind { return true }
            return false
        }
    }

    private var builder: TIR.Builder? {
        get { gen.builder }
        set { gen.builder = newValue }
    }

    private var env: [Id.SymbolId: TIR.Value] {
        get { gen.env }
        set { gen.env = newValue }
    }

    private func visitExpression(_ expression: AST.Expression) -> TIR.Value? {
        visit(expression) as? TIR.Value
    }

    private func lowerType(_ type: TrussType.TrussType?) -> TIRType.TIRType {
        type.map { gen.typeLower.lower($0) } ?? gen.registry.voidType()
    }

    private func emitReturn(_ value: TIR.Value?, range: SourceRange) {
        builder?.buildReturn(value)
    }

    private func isTerminator(_ instruction: TIR.Instruction) -> Bool {
        instruction is TIR.Return || instruction is TIR.Branch
            || instruction is TIR.ConditionalBranch || instruction is TIR.SwitchEnum
            || instruction is TIR.Unreachable
    }

    private func ensureTerminator(range: SourceRange) {
        guard let builder, let insertPoint = builder.insertPoint else { return }
        if let last = insertPoint.instructions.last, isTerminator(last) {
            return
        }
        builder.buildReturn(nil)
    }

    private func shouldImplicitReturn(_ type: TrussType.TrussType?) -> Bool {
        guard let type else { return false }
        return !(type is TrussType.VoidType)
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = functionDecl.symbol, let function = gen.functionsBySymbol[symbol.id] else {
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
        guard let symbol = initDecl.symbol, let function = gen.functionsBySymbol[symbol.id] else {
            return nil
        }
        generateBody(
            .Block(initDecl.body), function: function, symbol: symbol,
            parameters: initDecl.parameters, hasSelf: true, range: initDecl.sourceRange
        )
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        let key = ObjectIdentifier(deinitDecl)
        guard let function = gen.deinitFunctions[key], let owner = gen.deinitOwners[key] else {
            return nil
        }
        generateBody(
            .Block(deinitDecl.body), function: function, symbol: nil, parameters: [],
            hasSelf: true, owner: owner, range: deinitDecl.sourceRange
        )
        return nil
    }

    private func generateBody(
        _ body: AST.FunctionDecl.Body, function: TIR.Function, symbol: Symbol.FunctionSymbol?,
        parameters: [AST.FunctionDecl.Parameter], hasSelf: Bool,
        owner: Symbol.NominalTypeSymbol? = nil, range: SourceRange
    ) {
        let savedBuilder = builder
        let savedEnv = env
        let savedModulePath = gen.modulePathStack

        let entryBlock = function.addBasicBlock(name: "entry")
        let b = TIR.Builder(registry: gen.registry)
        b.insertPoint = entryBlock
        builder = b
        env = [:]

        bindParameters(function: function, symbol: symbol, parameters: parameters)

        switch body {
        case let .Block(statements):
            visitBodyStatements(statements, implicitReturn: shouldImplicitReturn(symbol?.functionType?.returnType))
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
        gen.modulePathStack = savedModulePath
    }

    private func bindParameters(
        function: TIR.Function, symbol: Symbol.FunctionSymbol?, parameters: [AST.FunctionDecl.Parameter]
    ) {
        guard let builder else { return }
        for (index, parameter) in parameters.enumerated() {
            let paramType = lowerType(
                symbol?.functionType?.parameters[safe: index].map(\.type)
                    ?? parameter.type?.ty
            )
            let argument = function.parameters[safe: index] ?? TIR.Parameter(
                ty: paramType.id, name: parameter.name.value
            )
            let alloc = builder.buildAllocStack(allocatedType: paramType.id, name: parameter.name.value)
            let address = alloc.result
            builder.buildStore(value: argument, to: address)
            let variableSymbol = parameterVariableSymbol(symbol, parameter.name.value)
            if let variableSymbol {
                env[variableSymbol.id] = address
            }
        }
    }

    private func parameterVariableSymbol(
        _ symbol: Symbol.FunctionSymbol?, _ name: String
    ) -> Symbol.VariableSymbol? {
        guard let symbol else { return nil }
        return symbol.scope.values[name]?.compactMap { $0 as? Symbol.VariableSymbol }.first
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
        if let value = visitExpression(expression) {
            emitReturn(value, range: range)
        }
    }

    private func loadFrom(_ address: TIR.Value, range: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        return builder.buildLoad(ptr: address).result
    }

    @discardableResult
    public override func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
    ) -> Any? {
        _ = visitExpression(expressionStatement.expression)
        return nil
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
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = variableDecl.symbol else { return nil }
        guard builder != nil else { return nil }
        let type = lowerType(symbol.type)
        let alloc = builder!.buildAllocStack(allocatedType: type.id, name: symbol.name)
        let address = alloc.result
        env[symbol.id] = address
        if let initializer = variableDecl.initializer, let value = visitExpression(initializer) {
            builder!.buildStore(value: value, to: address)
        }
        return nil
    }

    @discardableResult
    public override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = lowerType(integerLiteral.ty)
        return builder.buildIntegerLiteral(
            value: UInt64(integerLiteral.value), ty: type.id
        )
    }

    @discardableResult
    public override func visitFloatLiteral(
        _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = lowerType(floatLiteral.ty)
        return builder.buildFloatLiteral(value: floatLiteral.value, ty: type.id)
    }

    @discardableResult
    public override func visitBoolLiteral(
        _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = lowerType(boolLiteral.ty)
        return builder.buildBoolLiteral(value: boolLiteral.value, ty: type.id)
    }

    @discardableResult
    public override func visitCharLiteral(
        _ charLiteral: AST.CharLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = lowerType(charLiteral.ty)
        return builder.buildCharLiteral(value: charLiteral.value, ty: type.id)
    }

    @discardableResult
    public override func visitStringLiteral(
        _ stringLiteral: AST.StringLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = lowerType(stringLiteral.ty)
        return builder.buildStringLiteral(value: stringLiteral.token.value, ty: type.id)
    }

    @discardableResult
    public override func visitNullptrLiteral(
        _ nullPointerLiteral: AST.NullptrLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = lowerType(nullPointerLiteral.ty)
        return builder.buildNullptrLiteral(ty: type.id)
    }

    @discardableResult
    public override func visitVariable(
        _ variable: AST.Variable, additional: Any? = nil
    ) -> Any? {
        guard let builder, let symbol = variable.symbol else { return nil }
        if let functionSymbol = symbol as? Symbol.FunctionSymbol {
            return functionRefValue(functionSymbol, at: variable.sourceRange)
        }
        if let global = gen.globalsBySymbol[symbol.id] {
            let address = builder.buildGlobalAddr(global: global)
            if variable.isLeftValue, !isReferenceType(variable.ty) {
                return address
            }
            return loadFrom(address, range: variable.sourceRange)
        }
        if let address = env[symbol.id] {
            if variable.isLeftValue, !isReferenceType(variable.ty) {
                return address
            }
            return loadFrom(address, range: variable.sourceRange)
        }
        return nil
    }

    private func functionRefValue(_ symbol: Symbol.FunctionSymbol, at range: SourceRange) -> TIR.Value? {
        guard let builder, let function = gen.functionsBySymbol[symbol.id] else { return nil }
        return builder.buildFunctionRef(function: function)
    }

    @discardableResult
    public override func visitParenthetical(
        _ parenthetical: AST.Parenthetical, additional: Any? = nil
    ) -> Any? {
        if parenthetical.isLeftValue {
            parenthetical.inner.isLeftValue = true
        }
        return visitExpression(parenthetical.inner)
    }

    @discardableResult
    public override func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        guard let calleeValue = lowerCallee(call.callee, at: call.sourceRange) else { return nil }
        let arguments: [TIR.Value] = call.arguments.compactMap { visitExpression($0.value) }
        return builder.buildCall(callee: calleeValue, arguments: arguments)
    }

    private func lowerCallee(_ callee: AST.Expression, at range: SourceRange) -> TIR.Value? {
        switch callee {
        case let variable as AST.Variable:
            if let functionSymbol = variable.symbol as? Symbol.FunctionSymbol
                ?? variable.overloads?.first
            {
                return functionRefValue(functionSymbol, at: range)
            }
            return visitExpression(callee)
        case let member as AST.MemberAccess:
            if let functionSymbol = member.symbol as? Symbol.FunctionSymbol
                ?? member.overloads?.first
            {
                return functionRefValue(functionSymbol, at: range)
            }
            return visitExpression(callee)
        case let application as AST.GenericApplication:
            return lowerCallee(application.base, at: range)
        default:
            return visitExpression(callee)
        }
    }

    private func isReferenceType(_ type: TrussType.TrussType?) -> Bool {
        type is TrussType.ClassType || type is TrussType.ActorType
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
