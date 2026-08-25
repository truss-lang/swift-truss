import SwiftBetterDiagnostic
import TrussCore

public final class TIRGen: AST.Visitor {
    private let context: Context
    private let gen: GenerationContext
    private let collector: TypeCollector

    private struct DeferFrame {
        var bodies: [[AST.Statement]] = []
    }

    private struct LoopContext {
        let breakTarget: TIR.BasicBlock
        let continueTarget: TIR.BasicBlock
        let bodyDeferDepth: Int
    }

    private struct LabelTarget {
        let block: TIR.BasicBlock
        let loop: LoopContext?
    }

    private var currentFunction: TIR.Function?
    private var blockCounter = 0
    private var deferStack: [DeferFrame] = []
    private var loopStack: [LoopContext] = []
    private var labelMap: [String: LabelTarget] = [:]

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
        let modules: [TIR.Module] = programs.map {
            let module = gen.makeModule()
            collectFunctions(in: $0)
            return module
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

    @discardableResult
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
        guard let builder else { return }
        if blockTerminated() { return }
        emitDefersDownTo(0)
        builder.buildReturn(value)
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
        currentFunction = function
        blockCounter = 0
        deferStack = []
        loopStack = []
        labelMap = [:]
        deferStack.append(DeferFrame())

        bindParameters(function: function, symbol: symbol, parameters: parameters)

        switch body {
        case let .Block(statements):
            let savedLabelInsert = builder?.insertPoint
            collectForwardLabels(statements)
            builder?.insertPoint = savedLabelInsert
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
            if blockTerminated() {
                _ = newBlock()
            }
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

    private func newBlock(_ name: String? = nil) -> TIR.BasicBlock {
        let function = currentFunction!
        let blockName = name ?? "bb\(blockCounter)"
        blockCounter += 1
        let block = function.addBasicBlock(name: blockName)
        builder?.insertPoint = block
        return block
    }

    private func blockTerminated() -> Bool {
        guard let block = builder?.insertPoint, let last = block.instructions.last else { return false }
        return isTerminator(last)
    }

    private func pushDeferFrame() {
        deferStack.append(DeferFrame())
    }

    private func popDeferFrame() {
        deferStack.removeLast()
    }

    private func emitDefersDownTo(_ minDepth: Int) {
        guard !deferStack.isEmpty, minDepth < deferStack.count else { return }
        if blockTerminated() { return }
        for index in stride(from: deferStack.count - 1, through: minDepth, by: -1) {
            let frame = deferStack[index]
            for body in frame.bodies.reversed() {
                for statement in body {
                    visit(statement)
                    if blockTerminated() { return }
                }
            }
        }
    }

    private func deferBodyHasExit(_ body: [AST.Statement]) -> Bool {
        body.contains { statement in
            statement is AST.Return || statement is AST.Break || statement is AST.Continue
                || statement is AST.Goto
        }
    }

    private func visitValueStatements(_ statements: [AST.Statement]) -> TIR.Value? {
        var lastValue: TIR.Value? = nil
        for statement in statements {
            if blockTerminated() { _ = newBlock() }
            if let expressionStatement = statement as? AST.ExpressionStatement {
                lastValue = visitExpression(expressionStatement.expression)
            } else {
                visit(statement)
                lastValue = nil
            }
        }
        return lastValue
    }

    private func collectForwardLabels(inIf ifExpr: AST.If) {
        collectForwardLabels(ifExpr.then)
        if let elseKind = ifExpr.elseKind {
            switch elseKind {
            case let .Block(statements):
                collectForwardLabels(statements)
            case let .If(elseIf):
                collectForwardLabels(inIf: elseIf)
            }
        }
    }

    private func collectForwardLabels(_ statements: [AST.Statement]) {
        for statement in statements {
            if let labeled = statement as? AST.LabeledStatement {
                let isLoop = labeled.body is AST.While || labeled.body is AST.RepeatWhile
                if !isLoop, labelMap[labeled.label.value] == nil {
                    let block = newBlock("label_\(labeled.label.value)")
                    labelMap[labeled.label.value] = LabelTarget(block: block, loop: nil)
                }
                collectForwardLabels([labeled.body])
            } else if let expressionStatement = statement as? AST.ExpressionStatement,
                      let ifNode = expressionStatement.expression as? AST.If
            {
                collectForwardLabels(inIf: ifNode)
            } else if let expressionStatement = statement as? AST.ExpressionStatement,
                      let matchNode = expressionStatement.expression as? AST.Match
            {
                for caseNode in matchNode.cases {
                    collectForwardLabels(caseNode.body)
                }
            } else if let whileStmt = statement as? AST.While {
                collectForwardLabels(whileStmt.body)
            } else if let repeatWhile = statement as? AST.RepeatWhile {
                collectForwardLabels(repeatWhile.body)
            } else if let guardStmt = statement as? AST.Guard {
                collectForwardLabels(guardStmt.body)
            }
        }
    }

    @discardableResult
    public override func visitIf(_ ifExpression: AST.If, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let producesValue = ifExpression.ty.map { type in
            !(type is TrussType.VoidType) && !(type is TrussType.NeverType)
        } ?? false
        let hasElse = ifExpression.elseKind != nil
        if producesValue, !hasElse {
            context.emitError("if used as a value must have an else branch", at: ifExpression.token)
        }
        guard let cond = visitExpression(ifExpression.condition) else { return nil }
        let preBlock = builder.insertPoint!

        let thenBlock = newBlock()
        let elseBlock = hasElse ? newBlock() : nil
        let joinBlock = newBlock()
        builder.insertPoint = preBlock
        builder.buildConditionalBranch(
            condition: cond, trueBranch: thenBlock, falseBranch: elseBlock ?? joinBlock
        )

        var incomings: [TIR.Phi.Incoming] = []

        builder.insertPoint = thenBlock
        pushDeferFrame()
        let thenValue = visitValueStatements(ifExpression.then)
        emitDefersDownTo(deferStack.count - 1)
        if !blockTerminated() {
            if producesValue, let thenValue {
                incomings.append(TIR.Phi.Incoming(value: thenValue, block: thenBlock))
            }
            builder.buildBranch(to: joinBlock)
        }
        popDeferFrame()

        if let elseBlock {
            builder.insertPoint = elseBlock
            switch ifExpression.elseKind {
            case let .Block(statements)?:
                pushDeferFrame()
                let elseValue = visitValueStatements(statements)
                emitDefersDownTo(deferStack.count - 1)
                if !blockTerminated() {
                    if producesValue, let elseValue {
                        incomings.append(TIR.Phi.Incoming(value: elseValue, block: elseBlock))
                    }
                    builder.buildBranch(to: joinBlock)
                }
                popDeferFrame()
            case let .If(elseIf)?:
                let elseValue = visitExpression(elseIf)
                if !blockTerminated() {
                    if producesValue, let elseValue {
                        incomings.append(
                            TIR.Phi.Incoming(value: elseValue, block: builder.insertPoint!)
                        )
                    }
                    builder.buildBranch(to: joinBlock)
                }
            case nil:
                break
            }
        }

        builder.insertPoint = joinBlock
        if producesValue {
            if incomings.count >= 2 {
                return builder.buildPhi(incomings: incomings).result
            } else if incomings.count == 1 {
                return incomings[0].value
            }
        }
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
        lowerWhile(whileStatement, label: nil, additional: additional)
        return nil
    }

    private func lowerWhile(_ whileStatement: AST.While, label: String?, additional: Any?) {
        guard let builder else { return }
        let preBlock = builder.insertPoint!
        let condBlock = newBlock()
        let bodyBlock = newBlock()
        let exitBlock = newBlock()
        let bodyDeferDepth = deferStack.count
        builder.insertPoint = preBlock
        builder.buildBranch(to: condBlock)

        let loop = LoopContext(
            breakTarget: exitBlock, continueTarget: condBlock, bodyDeferDepth: bodyDeferDepth
        )
        loopStack.append(loop)
        if let label, labelMap[label] == nil {
            labelMap[label] = LabelTarget(block: condBlock, loop: loop)
        }

        builder.insertPoint = bodyBlock
        pushDeferFrame()
        visitBodyStatements(whileStatement.body, implicitReturn: false)
        emitDefersDownTo(deferStack.count - 1)
        if !blockTerminated() {
            builder.buildBranch(to: condBlock)
        }
        popDeferFrame()

        builder.insertPoint = condBlock
        if let cond = visitExpression(whileStatement.condition) {
            builder.buildConditionalBranch(
                condition: cond, trueBranch: bodyBlock, falseBranch: exitBlock
            )
        } else {
            builder.buildBranch(to: exitBlock)
        }

        builder.insertPoint = exitBlock
        loopStack.removeLast()
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        lowerRepeatWhile(repeatWhile, label: nil, additional: additional)
        return nil
    }

    private func lowerRepeatWhile(_ repeatWhile: AST.RepeatWhile, label: String?, additional: Any?) {
        guard let builder else { return }
        let preBlock = builder.insertPoint!
        let bodyBlock = newBlock()
        let condBlock = newBlock()
        let exitBlock = newBlock()
        let bodyDeferDepth = deferStack.count
        builder.insertPoint = preBlock
        builder.buildBranch(to: bodyBlock)

        let loop = LoopContext(
            breakTarget: exitBlock, continueTarget: condBlock, bodyDeferDepth: bodyDeferDepth
        )
        loopStack.append(loop)
        if let label, labelMap[label] == nil {
            labelMap[label] = LabelTarget(block: bodyBlock, loop: loop)
        }

        builder.insertPoint = bodyBlock
        pushDeferFrame()
        visitBodyStatements(repeatWhile.body, implicitReturn: false)
        emitDefersDownTo(deferStack.count - 1)
        if !blockTerminated() {
            builder.buildBranch(to: condBlock)
        }
        popDeferFrame()

        builder.insertPoint = condBlock
        if let cond = visitExpression(repeatWhile.condition) {
            builder.buildConditionalBranch(
                condition: cond, trueBranch: bodyBlock, falseBranch: exitBlock
            )
        } else {
            builder.buildBranch(to: exitBlock)
        }

        builder.insertPoint = exitBlock
        loopStack.removeLast()
    }

    @discardableResult
    public override func visitGuard(_ guardStatement: AST.Guard, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        guard let cond = visitExpression(guardStatement.condition) else { return nil }
        let preBlock = builder.insertPoint!
        let failureBlock = newBlock()
        let continueBlock = newBlock()
        builder.insertPoint = preBlock
        builder.buildConditionalBranch(
            condition: cond, trueBranch: continueBlock, falseBranch: failureBlock
        )
        builder.insertPoint = failureBlock
        pushDeferFrame()
        visitBodyStatements(guardStatement.body, implicitReturn: false)
        if !blockTerminated() {
            context.emitError("guard's else body must not fall through", at: guardStatement.token)
            emitDefersDownTo(deferStack.count - 1)
            builder.buildBranch(to: continueBlock)
        }
        popDeferFrame()
        builder.insertPoint = continueBlock
        return nil
    }

    @discardableResult
    public override func visitDefer(_ deferStatement: AST.Defer, additional: Any? = nil) -> Any? {
        guard !deferStack.isEmpty else { return nil }
        if deferBodyHasExit(deferStatement.body) {
            context.emitError(
                "defer body must not contain return, break, continue, or goto",
                at: deferStatement.token
            )
        }
        deferStack[deferStack.count - 1].bodies.append(deferStatement.body)
        return nil
    }

    @discardableResult
    public override func visitBreak(_ breakStatement: AST.Break, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        if let labelToken = breakStatement.label {
            guard let target = labelMap[labelToken.value] else {
                context.emitError("use of undeclared label '\(labelToken.value)'", at: labelToken)
                return nil
            }
            guard let loop = target.loop else {
                context.emitError("label '\(labelToken.value)' is not a loop", at: labelToken)
                return nil
            }
            emitDefersDownTo(loop.bodyDeferDepth)
            if !blockTerminated() { builder.buildBranch(to: loop.breakTarget) }
            return nil
        }
        guard let loop = loopStack.last else {
            context.emitError("'break' outside of a loop", at: breakStatement.token)
            return nil
        }
        emitDefersDownTo(loop.bodyDeferDepth)
        if !blockTerminated() { builder.buildBranch(to: loop.breakTarget) }
        return nil
    }

    @discardableResult
    public override func visitContinue(
        _ continueStatement: AST.Continue, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        if let labelToken = continueStatement.label {
            guard let target = labelMap[labelToken.value] else {
                context.emitError("use of undeclared label '\(labelToken.value)'", at: labelToken)
                return nil
            }
            guard let loop = target.loop else {
                context.emitError("label '\(labelToken.value)' is not a loop", at: labelToken)
                return nil
            }
            emitDefersDownTo(loop.bodyDeferDepth)
            if !blockTerminated() { builder.buildBranch(to: loop.continueTarget) }
            return nil
        }
        guard let loop = loopStack.last else {
            context.emitError("'continue' outside of a loop", at: continueStatement.token)
            return nil
        }
        emitDefersDownTo(loop.bodyDeferDepth)
        if !blockTerminated() { builder.buildBranch(to: loop.continueTarget) }
        return nil
    }

    @discardableResult
    public override func visitGoto(_ gotoStatement: AST.Goto, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let name = gotoStatement.label.value
        guard let target = labelMap[name] else {
            context.emitError("use of undeclared label '\(name)'", at: gotoStatement.label)
            return nil
        }
        if deferStack.contains(where: { !$0.bodies.isEmpty }) {
            context.emitError(
                "cannot use 'goto' to jump out of a scope containing 'defer'",
                at: gotoStatement.label
            )
            return nil
        }
        if !blockTerminated() { builder.buildBranch(to: target.block) }
        return nil
    }

    @discardableResult
    public override func visitLabeledStatement(
        _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let name = labeledStatement.label.value
        if let loop = labeledStatement.body as? AST.While {
            lowerWhile(loop, label: name, additional: additional)
        } else if let loop = labeledStatement.body as? AST.RepeatWhile {
            lowerRepeatWhile(loop, label: name, additional: additional)
        } else {
            if let existing = labelMap[name] {
                builder.insertPoint = existing.block
            } else {
                let block = newBlock("label_\(name)")
                labelMap[name] = LabelTarget(block: block, loop: nil)
            }
            visit(labeledStatement.body)
        }
        return nil
    }

    @discardableResult
    public override func visitMatch(_ match: AST.Match, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let producesValue = match.ty.map { type in
            !(type is TrussType.VoidType) && !(type is TrussType.NeverType)
        } ?? false
        guard let subject = visitExpression(match.subject) else { return nil }
        if let enumType = gen.registry.types[subject.ty] as? TIRType.EnumType {
            return lowerEnumMatch(
                match, subject: subject, enumType: enumType, producesValue: producesValue,
                additional: additional
            )
        }
        return lowerValueMatch(
            match, subject: subject, producesValue: producesValue, additional: additional
        )
    }

    private func lowerEnumMatch(
        _ match: AST.Match, subject: TIR.Value, enumType: TIRType.EnumType,
        producesValue: Bool, additional: Any?
    ) -> Any? {
        guard let builder else { return nil }
        let preBlock = builder.insertPoint!
        let joinBlock = newBlock()
        var incomings: [TIR.Phi.Incoming] = []
        var switchCases: [TIR.SwitchEnum.Case] = []
        var defaultBlock: TIR.BasicBlock? = nil
        var bodyBlocks: [(TIR.BasicBlock, AST.Match.Case)] = []

        for matchCase in match.cases {
            let bodyBlock = newBlock()
            bodyBlocks.append((bodyBlock, matchCase))
            for pattern in matchCase.patterns {
                if isWildcard(pattern) {
                    defaultBlock = bodyBlock
                    continue
                }
                if let name = caseName(from: pattern),
                   let tag = enumType.cases.firstIndex(where: { $0.name == name })
                {
                    switchCases.append(TIR.SwitchEnum.Case(tag: tag, block: bodyBlock))
                }
            }
        }

        let coveredTags = Set(switchCases.map(\.tag))
        let allCovered = coveredTags.count == enumType.cases.count
        builder.insertPoint = preBlock
        builder.buildSwitchEnum(value: subject, cases: switchCases, defaultBlock: defaultBlock)
        if defaultBlock == nil, !allCovered {
            context.emitError("non-exhaustive match", at: match.token)
            builder.buildUnreachable()
        }

        for (bodyBlock, matchCase) in bodyBlocks {
            builder.insertPoint = bodyBlock
            pushDeferFrame()
            for pattern in matchCase.patterns {
                if let name = bindingName(from: pattern) {
                    bindMatchPayload(
                        name: name,
                        from: pattern,
                        subject: subject,
                        enumType: enumType,
                        body: matchCase.body
                    )
                }
            }
            let caseValue = visitValueStatements(matchCase.body)
            emitDefersDownTo(deferStack.count - 1)
            if !blockTerminated() {
                if producesValue, let caseValue {
                    incomings.append(TIR.Phi.Incoming(value: caseValue, block: bodyBlock))
                }
                builder.buildBranch(to: joinBlock)
            }
            popDeferFrame()
        }

        builder.insertPoint = joinBlock
        if producesValue {
            if incomings.count >= 2 {
                return builder.buildPhi(incomings: incomings).result
            } else if incomings.count == 1 {
                return incomings[0].value
            }
        }
        return nil
    }

    private func lowerValueMatch(
        _ match: AST.Match, subject: TIR.Value, producesValue: Bool, additional: Any?
    ) -> Any? {
        guard let builder else { return nil }
        let joinBlock = newBlock()
        var incomings: [TIR.Phi.Incoming] = []
        var current = builder.insertPoint!
        var defaultBlock: TIR.BasicBlock? = nil
        var bodyBlocks: [(TIR.BasicBlock, AST.Match.Case)] = []

        for matchCase in match.cases {
            let bodyBlock = newBlock()
            bodyBlocks.append((bodyBlock, matchCase))
            let isDefault = matchCase.patterns.contains { isWildcard($0) }
            if isDefault {
                defaultBlock = bodyBlock
                continue
            }
            builder.insertPoint = current
            for pattern in matchCase.patterns where !isWildcard(pattern) {
                guard let patternValue = visitExpression(pattern) else { continue }
                let eq = builder.buildBinaryArith(op: .Eq, lhs: subject, rhs: patternValue)
                let nextBlock = newBlock()
                builder.buildConditionalBranch(
                    condition: eq.result, trueBranch: bodyBlock, falseBranch: nextBlock
                )
                current = nextBlock
                builder.insertPoint = current
            }
        }

        builder.insertPoint = current
        if let defaultBlock {
            builder.buildBranch(to: defaultBlock)
        } else {
            context.emitError("non-exhaustive match", at: match.token)
            builder.buildUnreachable()
        }

        for (bodyBlock, matchCase) in bodyBlocks {
            builder.insertPoint = bodyBlock
            pushDeferFrame()
            let caseValue = visitValueStatements(matchCase.body)
            emitDefersDownTo(deferStack.count - 1)
            if !blockTerminated() {
                if producesValue, let caseValue {
                    incomings.append(TIR.Phi.Incoming(value: caseValue, block: bodyBlock))
                }
                builder.buildBranch(to: joinBlock)
            }
            popDeferFrame()
        }

        builder.insertPoint = joinBlock
        if producesValue {
            if incomings.count >= 2 {
                return builder.buildPhi(incomings: incomings).result
            } else if incomings.count == 1 {
                return incomings[0].value
            }
        }
        return nil
    }

    private func isWildcard(_ pattern: AST.Expression) -> Bool {
        pattern is AST.WildcardPattern
    }

    private func caseName(from pattern: AST.Expression) -> String? {
        if let implicit = pattern as? AST.ImplicitMemberAccess {
            return implicit.symbol?.name
        }
        if let member = pattern as? AST.MemberAccess {
            return member.member.value
        }
        if let variable = pattern as? AST.Variable, let caseSymbol = variable.symbol as? Symbol.CaseSymbol {
            return caseSymbol.name
        }
        if let call = pattern as? AST.Call {
            return caseName(from: call.callee)
        }
        return nil
    }

    private func bindingName(from pattern: AST.Expression) -> String? {
        guard let call = pattern as? AST.Call else { return nil }
        for argument in call.arguments {
            if let binding = argument.value as? AST.BindingPattern {
                return binding.name.value
            }
        }
        return nil
    }

    private func bindMatchPayload(
        name: String, from pattern: AST.Expression, subject: TIR.Value, enumType: TIRType.EnumType,
        body: [AST.Statement]
    ) {
        guard let builder, let caseName = caseName(from: pattern),
              let index = enumType.cases.firstIndex(where: { $0.name == caseName }),
              let payloadType = enumType.cases[index].associatedTypes.first
        else {
            return
        }
        guard let symbol = findVariableSymbol(name: name, in: body) else { return }
        let extract = builder.buildExtractPayload(value: subject, ty: payloadType, name: name)
        let alloc = builder.buildAllocStack(allocatedType: payloadType, name: name)
        builder.buildStore(value: extract.result, to: alloc.result)
        env[symbol.id] = alloc.result
    }

    private func findVariableSymbol(name: String, in statements: [AST.Statement]) -> Symbol.VariableSymbol? {
        for statement in statements {
            if let symbol = findVariableSymbol(name: name, in: statement) { return symbol }
        }
        return nil
    }

    private func findVariableSymbol(name: String, in statement: AST.Statement) -> Symbol.VariableSymbol? {
        if let expressionStatement = statement as? AST.ExpressionStatement {
            return findVariableSymbol(name: name, in: expressionStatement.expression)
        }
        if let variableDecl = statement as? AST.VariableDecl {
            return findVariableSymbol(name: name, in: variableDecl.initializer)
        }
        if let ifExpression = statement as? AST.If {
            for s in ifExpression.then {
                if let symbol = findVariableSymbol(name: name, in: s) { return symbol }
            }
            return nil
        }
        if let returnStatement = statement as? AST.Return {
            return findVariableSymbol(name: name, in: returnStatement.value)
        }
        return nil
    }

    private func findVariableSymbol(name: String, in expression: AST.Expression?) -> Symbol.VariableSymbol? {
        guard let expression else { return nil }
        if let variable = expression as? AST.Variable,
           variable.name.value == name,
           let symbol = variable.symbol as? Symbol.VariableSymbol
        {
            return symbol
        }
        if let parenthetical = expression as? AST.Parenthetical {
            return findVariableSymbol(name: name, in: parenthetical.inner)
        }
        return nil
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
