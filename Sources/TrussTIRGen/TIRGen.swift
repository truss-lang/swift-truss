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
    private var errorTargets: [TIR.BasicBlock] = []
    private var closureParamValues: [[TIR.Value]] = []
    private var closureCounter = 0

    private struct BreakTarget {
        let label: String?
        let breakBlock: TIR.BasicBlock
        let continueBlock: TIR.BasicBlock?
    }

    public init(context: Context) {
        self.context = context
        typeLower = TypeLower(context: context)
    }

    public func generate(_ program: AST.Program) -> TIR.Module {
        module = TIR.Module()
        functionsBySymbol = [:]
        collectFunctions(in: program)
        visitProgram(program)
        return module
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
            case let decl as AST.ModuleDecl:
                collectStatements(decl.body)
            case let decl as AST.StructDecl:
                collectStatements(decl.body)
            case let decl as AST.ClassDecl:
                collectStatements(decl.body)
            case let decl as AST.EnumDecl:
                collectStatements(decl.body)
            case let decl as AST.ActorDecl:
                collectStatements(decl.body)
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
        let returnType = functionType.map { typeLower.lower($0.returnType) } ?? TIRType.TupleType([])
        let throwsTypes = functionType?.throwsTypes.map { typeLower.lower($0) } ?? []
        createFunction(
            symbol, name: decl.name.value, returnType: returnType,
            isAsync: decl.asyncToken != nil, isThrowing: functionType?.isThrowing ?? false,
            throwsTypes: throwsTypes
        )
    }

    private func collectInit(_ decl: AST.InitDecl) {
        guard let symbol = decl.symbol else { return }
        let throwsTypes = symbol.functionType?.throwsTypes.map { typeLower.lower($0) } ?? []
        createFunction(
            symbol, name: "init", returnType: TIRType.TupleType([]),
            isAsync: decl.asyncToken != nil, isThrowing: symbol.functionType?.isThrowing ?? false,
            throwsTypes: throwsTypes
        )
    }

    private func collectDeinit(_ decl: AST.DeinitDecl) {
        createFunction(nil, name: "deinit", returnType: TIRType.TupleType([]))
    }

    private func collectSubscript(_ decl: AST.SubscriptDecl) {
        guard let symbol = decl.symbol else { return }
        let functionType = symbol.functionType
        let returnType = functionType.map { typeLower.lower($0.returnType) } ?? TIRType.TupleType([])
        let throwsTypes = functionType?.throwsTypes.map { typeLower.lower($0) } ?? []
        createFunction(
            symbol, name: "subscript", returnType: returnType,
            isAsync: decl.asyncToken != nil, isThrowing: functionType?.isThrowing ?? false,
            throwsTypes: throwsTypes
        )
    }

    @discardableResult
    private func createFunction(
        _ symbol: Symbol.FunctionSymbol?, name: String, returnType: TIRType.TIRType,
        isAsync: Bool = false, isThrowing: Bool = false, throwsTypes: [TIRType.TIRType] = []
    ) -> TIR.Function {
        let function = TIR.Function(
            name: name, returnType: returnType, isAsync: isAsync, isThrowing: isThrowing,
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
            parameters: initDecl.parameters, hasSelf: true, range: initDecl.sourceRange
        )
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        guard let function = module.functions.first(where: { $0.name == "deinit" && $0.symbol == nil })
        else {
            return nil
        }
        generateBody(
            .Block(deinitDecl.body), function: function, symbol: nil, parameters: [],
            hasSelf: true, range: deinitDecl.sourceRange
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
        parameters: [AST.FunctionDecl.Parameter], hasSelf: Bool, range: SourceRange
    ) {
        let savedBuilder = builder
        let savedEnv = env
        let savedCaptured = capturedCells
        let savedBreak = breakStack
        let savedDefer = deferStack
        let savedError = errorTargets
        let savedClosureParams = closureParamValues

        builder = TIRBuilder(function: function)
        env = [:]
        capturedCells = []
        breakStack = []
        deferStack = []
        errorTargets = []
        closureParamValues = []

        bindSelfIfNeeded(function: function, symbol: symbol, hasSelf: hasSelf)
        bindParameters(function: function, symbol: symbol, parameters: parameters)

        switch body {
        case let .Block(statements):
            for statement in statements {
                visit(statement)
            }
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
    }

    private func bindSelfIfNeeded(function: TIR.Function, symbol: Symbol.FunctionSymbol?, hasSelf: Bool) {
        guard let builder else { return }
        guard hasSelf, let symbol, let memberOf = symbol.memberOf,
              let owner = context.id2Symbol[memberOf]
        else {
            return
        }
        let selfType = ownerType(owner) ?? TIRType.TupleType([])
        let argument = builder.createArgument(type: selfType, ownership: typeLower.ownership(for: selfType))
        function.arguments.append(argument)
        let address = builder.emitWithResult(
            TIR.AllocStack(selfType, sourceRange: emptyRange),
            type: TIRType.AddressType(selfType), ownership: .Inout
        )
        builder.emit(TIR.Store(argument, to: address, sourceRange: emptyRange))
        env[symbol.id] = address
        env[memberOf] = address
    }

    private func bindParameters(
        function: TIR.Function, symbol: Symbol.FunctionSymbol?, parameters: [AST.FunctionDecl.Parameter]
    ) {
        guard let builder else { return }
        let paramTypes: [TIRType.TIRType] = parameters.enumerated().map { index, parameter in
            let type = symbol?.functionType?.parameters[safe: index].map { typeLower.lower($0.type) }
            return type ?? (parameter.type?.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
                type: TIRType.AddressType(paramType), ownership: .Inout
            )
            builder.emit(TIR.Store(argument, to: address, sourceRange: parameter.sourceRange))
            if let variableSymbol = parameterVariableSymbol(symbol, parameter.name.value) {
                env[variableSymbol.id] = address
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
        guard let builder, let symbol = variableDecl.symbol else { return nil }
        let type = symbol.type.map { typeLower.lower($0) }
            ?? (variableDecl.initializer?.ty).map { typeLower.lower($0) }
            ?? TIRType.TupleType([])
        let address = builder.emitWithResult(
            TIR.AllocStack(type, sourceRange: variableDecl.sourceRange),
            type: TIRType.AddressType(type), ownership: .Inout
        )
        env[symbol.id] = address
        if let initializer = variableDecl.initializer, let value = visitExpression(initializer) {
            builder.emit(TIR.Store(value, to: address, sourceRange: variableDecl.sourceRange))
        }
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
    public override func visitThrow(_ throwStatement: AST.Throw, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let value = visitExpression(throwStatement.expression)
        runDeferred()
        if let value {
            builder.emit(TIR.Throw(value, sourceRange: throwStatement.sourceRange))
        }
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
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
        breakStack.append(
            BreakTarget(label: nil, breakBlock: exitBlock, continueBlock: condBlock)
        )
        for statement in whileStatement.body {
            visit(statement)
        }
        breakStack.removeLast()
        builder.emit(TIR.Branch(condBlock, sourceRange: whileStatement.sourceRange))
        builder.switchToBlock(exitBlock)
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let bodyBlock = builder.createBlock()
        let condBlock = builder.createBlock()
        let exitBlock = builder.createBlock()
        builder.emit(TIR.Branch(bodyBlock, sourceRange: repeatWhile.sourceRange))
        builder.switchToBlock(bodyBlock)
        breakStack.append(
            BreakTarget(label: nil, breakBlock: exitBlock, continueBlock: condBlock)
        )
        for statement in repeatWhile.body {
            visit(statement)
        }
        breakStack.removeLast()
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
            builder.emit(TIR.Branch(continueBlock, sourceRange: continueStatement.sourceRange))
        }
        return nil
    }

    @discardableResult
    public override func visitGoto(_ gotoStatement: AST.Goto, additional: Any? = nil) -> Any? {
        builder?.emit(TIR.Trap(gotoStatement.sourceRange))
        return nil
    }

    @discardableResult
    public override func visitAsm(_ asmStatement: AST.Asm, additional: Any? = nil) -> Any? {
        builder?.emit(TIR.Trap(asmStatement.sourceRange))
        return nil
    }

    private func visitCondition(
        _ condition: AST.Expression, trueBlock: TIR.BasicBlock, falseBlock: TIR.BasicBlock,
        range: SourceRange
    ) {
        guard let builder else { return }
        if let binding = condition as? AST.OptionalBinding {
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

    @discardableResult
    public override func visitIf(_ ifExpression: AST.If, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let thenBlock = builder.createBlock()
        let elseBlock = builder.createBlock()
        let joinBlock = builder.createBlock()
        visitCondition(
            ifExpression.condition, trueBlock: thenBlock, falseBlock: elseBlock,
            range: ifExpression.sourceRange
        )
        builder.switchToBlock(thenBlock)
        for statement in ifExpression.then {
            visit(statement)
        }
        builder.emit(TIR.Branch(joinBlock, sourceRange: ifExpression.sourceRange))
        builder.switchToBlock(elseBlock)
        if let elseKind = ifExpression.elseKind {
            switch elseKind {
            case let .Block(statements):
                for statement in statements {
                    visit(statement)
                }
                builder.emit(TIR.Branch(joinBlock, sourceRange: ifExpression.sourceRange))
            case let .If(nested):
                visitIf(nested)
                builder.emit(TIR.Branch(joinBlock, sourceRange: ifExpression.sourceRange))
            }
        } else {
            builder.emit(TIR.Branch(joinBlock, sourceRange: ifExpression.sourceRange))
        }
        builder.switchToBlock(joinBlock)
        return nil
    }

    @discardableResult
    public override func visitMatch(_ matchExpression: AST.Match, additional: Any? = nil) -> Any? {
        guard let builder, let subject = visitExpression(matchExpression.subject) else { return nil }
        let joinBlock = builder.createBlock()
        var testBlock = builder.currentBlock
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
            for statement in matchCase.body {
                visit(statement)
            }
            builder.emit(TIR.Branch(joinBlock, sourceRange: matchExpression.sourceRange))
        }
        builder.switchToBlock(testBlock)
        builder.emit(TIR.Unreachable(matchExpression.sourceRange))
        builder.switchToBlock(joinBlock)
        return nil
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
            let caseName = member.name.value
            guard let enumType = subject.type as? TIRType.EnumType else {
                builder.emit(TIR.Branch(failBlock, sourceRange: range))
                return
            }
            builder.emit(
                TIR.SwitchEnum(
                    subject,
                    cases: [
                        TIR.EnumCaseBranch(caseName: caseName, block: successBlock),
                    ],
                    defaultBlock: failBlock, sourceRange: range
                )
            )
        case let call as AST.Call:
            let caseName = (call.callee as? AST.ImplicitMemberAccess)?.name.value
                ?? (call.callee as? AST.Variable)?.name.value
            guard let enumType = subject.type as? TIRType.EnumType, let caseName else {
                builder.emit(TIR.Branch(failBlock, sourceRange: range))
                return
            }
            let payloadBlock = builder.createBlock()
            builder.emit(
                TIR.SwitchEnum(
                    subject,
                    cases: [
                        TIR.EnumCaseBranch(caseName: caseName, block: payloadBlock),
                    ],
                    defaultBlock: failBlock, sourceRange: range
                )
            )
            builder.switchToBlock(payloadBlock)
            if !call.arguments.isEmpty {
                let payload = builder.emitWithResult(
                    TIR.UncheckedEnumData(subject, caseName: caseName, sourceRange: range),
                    type: payloadType(caseName), ownership: .Trivial
                )
                let elementAddress = builder.emitWithResult(
                    TIR.TupleElementAddr(payload, index: 0, sourceRange: range),
                    type: TIRType.AddressType(TIRType.TupleType([])), ownership: .Inout
                )
                _ = elementAddress
                for (index, argument) in call.arguments.enumerated() {
                    let element = builder.emitWithResult(
                        TIR.TupleElementAddr(payload, index: index, sourceRange: range),
                        type: TIRType.AddressType(TIRType.TupleType([])), ownership: .Inout
                    )
                    let elementValue = builder.emitWithResult(
                        TIR.Load(element, sourceRange: range), type: TIRType.TupleType([]),
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
                type: TIRType.AddressType(subject.type), ownership: .Inout
            )
            builder.emit(TIR.Store(subject, to: tupleAddress, sourceRange: range))
            for (index, element) in tuple.elements.enumerated() {
                let elementAddress = builder.emitWithResult(
                    TIR.TupleElementAddr(tupleAddress, index: index, sourceRange: range),
                    type: TIRType.AddressType(TIRType.TupleType([])), ownership: .Inout
                )
                let elementValue = builder.emitWithResult(
                    TIR.Load(elementAddress, sourceRange: range), type: TIRType.TupleType([]),
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
                ?? TIRType.TupleType([])
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

    private func payloadType(_ caseName: String) -> TIRType.TIRType {
        TIRType.TupleType([])
    }

    private func bindPatternValue(name: String, value: TIR.Value, at range: SourceRange) {
        guard let builder else { return }
        let address = builder.emitWithResult(
            TIR.AllocStack(value.type, sourceRange: range),
            type: TIRType.AddressType(value.type), ownership: .Inout
        )
        builder.emit(TIR.Store(value, to: address, sourceRange: range))
        if let variableSymbol = currentScopeVariable(named: name) {
            env[variableSymbol.id] = address
        }
    }

    private func currentScopeVariable(named name: String) -> Symbol.VariableSymbol? {
        nil
    }

    @discardableResult
    public override func visitDo(_ doExpression: AST.Do, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let joinBlock = builder.createBlock()
        let errorBlock = builder.createBlock()
        errorTargets.append(errorBlock)
        for statement in doExpression.body {
            visit(statement)
        }
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
                for statement in catchClause.body {
                    visit(statement)
                }
                builder.emit(TIR.Branch(joinBlock, sourceRange: doExpression.sourceRange))
            }
            builder.switchToBlock(testBlock)
            builder.emit(TIR.Unreachable(doExpression.sourceRange))
        }
        if let finallyBody = doExpression.finallyBody {
            builder.switchToBlock(joinBlock)
            for statement in finallyBody {
                visit(statement)
            }
            builder.switchToBlock(joinBlock)
        } else {
            builder.switchToBlock(joinBlock)
        }
        return nil
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
        let type = (integerLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let type = (floatLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let type = (stringLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let type = (charLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let type = (boolLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let type = (nullLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
        return builder.emitWithResult(
            TIR.NullLiteral(type: type, sourceRange: nullLiteral.sourceRange),
            type: type, ownership: .Trivial
        )
    }

    @discardableResult
    public override func visitVoidLiteral(
        _ voidLiteral: AST.VoidLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let type = TIRType.TupleType([])
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
        if let address = env[symbol.id] {
            let loaded = loadFrom(address, range: variable.sourceRange)
            if capturedCells.contains(symbol.id) {
                let projected = builder.emitWithResult(
                    TIR.ProjectCell(address, sourceRange: variable.sourceRange),
                    type: address.type, ownership: .Inout
                )
                return loadFrom(projected, range: variable.sourceRange)
            }
            return loaded
        }
        return nil
    }

    private func loadFrom(_ address: TIR.Value, range: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        let pointee = (address.type as? TIRType.AddressType)?.pointee ?? TIRType.TupleType([])
        return builder.emitWithResult(
            TIR.Load(address, sourceRange: range), type: pointee,
            ownership: typeLower.ownership(for: pointee)
        )
    }

    @discardableResult
    public override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
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
        let type = (tuple.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let substitutions = substitutionsFor(call)
        let resultType = (call.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
            return TIRType.TupleType([])
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
        symbol.functionType.map { typeLower.lower($0) } ?? TIRType.TupleType([])
    }

    private func functionRefValue(_ symbol: Symbol.FunctionSymbol, at range: SourceRange) -> TIR.Value? {
        guard let builder, let function = functionsBySymbol[symbol.id] else { return nil }
        let functionType = symbol.functionType.map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        guard let object = visitExpression(memberAccess.object) else { return nil }
        let memberType = variableSymbolType(symbol) ?? TIRType.TupleType([])
        let isClass = isReferenceType(memberAccess.object.ty)
        let address: TIR.Value = if isClass {
            builder.emitWithResult(
                TIR.RefElementAddr(
                    object, fieldIndex: 0, fieldName: memberAccess.member.value,
                    sourceRange: memberAccess.sourceRange
                ),
                type: TIRType.AddressType(memberType), ownership: .Inout
            )
        } else {
            builder.emitWithResult(
                TIR.StructElementAddr(
                    object, fieldIndex: 0, fieldName: memberAccess.member.value,
                    sourceRange: memberAccess.sourceRange
                ),
                type: TIRType.AddressType(memberType), ownership: .Inout
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
        let resultType = (binary.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let resultType = (prefix.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let resultType = (postfix.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
    public override func visitArrayLiteral(
        _ arrayLiteral: AST.ArrayLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let elements = arrayLiteral.elements.compactMap { visitExpression($0) }
        let type = (arrayLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let type = (dictionaryLiteral.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
            ?? TIRType.TupleType([])
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
            let type = (cast.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let errorBlock = errorTargets.last ?? builder?.createBlock()
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
            ?? TIRType.TupleType([])
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
        let resultType = (forceUnwrap.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
        return builder.emitWithResult(
            TIR.UncheckedEnumData(value, caseName: "some", sourceRange: forceUnwrap.sourceRange),
            type: resultType, ownership: .Trivial
        )
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
                    type: TIRType.AddressType(type), ownership: .Inout
                )
                let loaded = loadFrom(value, range: closure.sourceRange) ?? value
                builder.emit(TIR.Store(loaded, to: cell, sourceRange: closure.sourceRange))
                captureCells.append(cell)
            }
        }
        let closureType = (closure.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
        let returnType = (closureType as? TIRType.FunctionType)?.returnType ?? TIRType.TupleType([])
        let isThrowing = (closureType as? TIRType.FunctionType)?.isThrowing ?? false
        let throwsTypes = (closureType as? TIRType.FunctionType)?.throwsTypes ?? []
        let name = "closure-\(closureCounter)"
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

        self.builder = TIRBuilder(function: function)
        env = [:]
        capturedCells = []
        breakStack = []
        deferStack = []
        errorTargets = []
        closureParamValues = []

        for (index, (symbol, type)) in captured.enumerated() {
            if index < captureCells.count {
                let cellArgument = builder.createArgument(
                    type: TIRType.AddressType(type), ownership: .Inout
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
                ?? TIRType.TupleType([])
            let argument = builder.createArgument(
                type: paramType, ownership: typeLower.ownership(for: paramType)
            )
            function.arguments.append(argument)
            let address = builder.emitWithResult(
                TIR.AllocStack(paramType, sourceRange: parameter.sourceRange),
                type: TIRType.AddressType(paramType), ownership: .Inout
            )
            builder.emit(TIR.Store(argument, to: address, sourceRange: parameter.sourceRange))
            paramValues.append(argument)
            if let variableSymbol = closure.scope?.values[parameter.name.value]?
                .compactMap({ $0 as? Symbol.VariableSymbol }).first
            {
                env[variableSymbol.id] = address
            }
            _ = index
        }
        if !paramValues.isEmpty {
            closureParamValues.append(paramValues)
        }
        for statement in closure.body {
            visit(statement)
        }
        ensureTerminator(range: closure.sourceRange)

        self.builder = savedBuilder
        env = savedEnv
        capturedCells = savedCaptured
        breakStack = savedBreak
        deferStack = savedDefer
        errorTargets = savedError
        closureParamValues = savedClosureParams

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
                let type = (variable.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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
        let type = (interpolation.ty).map { typeLower.lower($0) } ?? TIRType.TupleType([])
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

    private func emitReturn(_ value: TIR.Value?, range: SourceRange) {
        runDeferred()
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
