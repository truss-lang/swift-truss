import SwiftBetterDiagnostic
import TrussCore

final class TIREmitter: AST.Visitor {
    private let context: Context
    private let gen: GenerationContext

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

    private struct ExceptionHandler {
        let catchEntry: TIR.BasicBlock?
        let errorSlot: TIR.Value?
        let deferDepth: Int
    }

    private var currentFunction: TIR.Function?
    private var currentFunctionIsThrowing = false
    private var blockCounter = 0
    private var deferStack: [DeferFrame] = []
    private var handlerStack: [ExceptionHandler] = []
    private var loopStack: [LoopContext] = []
    private var labelMap: [String: LabelTarget] = [:]
    private var closureParamStack: [[TIR.Value]] = []
    private var closureCounter = 0
    private var existentialLocalStack: [[Id.SymbolId]] = []

    init(context: Context, gen: GenerationContext) {
        self.context = context
        self.gen = gen
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

    private func ownerOf(_ id: Id.SymbolId?) -> Symbol.NominalTypeSymbol? {
        guard let id else { return nil }
        return gen.context.id2Symbol[id] as? Symbol.NominalTypeSymbol
    }

    private func isReferenceType(_ type: TrussType.TrussType?) -> Bool {
        type is TrussType.ClassType || type is TrussType.ActorType
    }

    private func isInitPointerSelf(_ ty: Id.TIRTypeId) -> Bool {
        gen.registry.types[ty] is TIRType.PointerType
    }

    private func isExistentialType(_ type: TrussType.TrussType?) -> Bool {
        guard let type else { return false }
        return type is TrussType.ProtocolType || type is TrussType.CompositionType
    }

    private func existentialBoxedValue(
        value: TIR.Value, valueType: TrussType.TrussType?, targetType: TrussType.TrussType?,
        boxKey: Id.SymbolId, sourceSymbolId: Id.SymbolId?, sourceRange: SourceRange
    ) -> TIR.Value? {
        guard let builder, isExistentialType(targetType) else { return value }
        if isExistentialType(valueType) {
            let result = builder.buildExistentialCopy(
                container: value, ty: lowerType(valueType).id
            ).result
            if let sourceSymbolId, let sourceBox = gen.existentialBoxes[sourceSymbolId] {
                gen.existentialBoxes[boxKey] = sourceBox
                if !existentialLocalStack.isEmpty {
                    existentialLocalStack[existentialLocalStack.count - 1].append(boxKey)
                }
            }
            return result
        }
        guard let concrete = nominalType(of: valueType) else { return nil }
        let containerType = gen.typeLower.lower(targetType!)
        var witnesses: [Id.TIRProtocolId: Id.TIRWitnessId] = [:]
        for protocolType in protocols(of: targetType) {
            guard concreteConforms(concrete, to: protocolType),
                  let witness = witnessRecord(
                      concreteType: concrete, protocolType: protocolType
                  )
            else {
                continue
            }
            witnesses[gen.typeLower.protocolId(for: protocolType)] = witness.id
        }
        let boxed = builder.buildBuildExistential(
            value: value, witnesses: Array(witnesses.values), ty: containerType.id
        ).result
        gen.existentialBoxes[boxKey] = GenerationContext.ExistentialBox(
            witnesses: witnesses,
            concreteType: gen.typeLower.lower(concrete).id,
            containerType: containerType.id
        )
        if !existentialLocalStack.isEmpty {
            existentialLocalStack[existentialLocalStack.count - 1].append(boxKey)
        }
        return boxed
    }

    private func protocols(of type: TrussType.TrussType?) -> [TrussType.ProtocolType] {
        guard let type else { return [] }
        if let protocolType = type as? TrussType.ProtocolType { return [protocolType] }
        if let composition = type as? TrussType.CompositionType {
            var seen = Set<Id.ASTTypeId>()
            return composition.members.flatMap { protocols(of: $0) }.filter {
                seen.insert($0.id).inserted
            }
        }
        return []
    }

    private func nominalType(of type: TrussType.TrussType?) -> TrussType.NominalType? {
        guard let type else { return nil }
        if let nominal = type as? TrussType.NominalType { return nominal }
        if let generic = type as? TrussType.GenericInstantiation { return generic.base }
        if let variable = type as? TrussType.TypeVariableType, let binding = variable.binding {
            return nominalType(of: binding)
        }
        return nil
    }

    private func targetProtocol(
        of type: TrussType.TrussType?, conformedBy concrete: TrussType.NominalType
    ) -> TrussType.ProtocolType? {
        let members: [TrussType.TrussType]
        if let composition = type as? TrussType.CompositionType {
            members = composition.members
        } else if let protocolType = type as? TrussType.ProtocolType {
            members = [protocolType]
        } else {
            return nil
        }
        for member in members {
            guard let protocolType = member as? TrussType.ProtocolType else { continue }
            if concreteConforms(concrete, to: protocolType) {
                return protocolType
            }
        }
        return nil
    }

    private func concreteConforms(
        _ concrete: TrussType.NominalType, to protocolType: TrussType.ProtocolType
    ) -> Bool {
        guard let symbol = concrete.symbol else { return false }
        return symbol.conformances.contains(where: { $0.typeId == protocolType.id })
    }

    private func witnessRecord(
        concreteType: TrussType.NominalType, protocolType: TrussType.ProtocolType
    ) -> TIR.WitnessRecord? {
        let protocolId = gen.typeLower.protocolId(for: protocolType)
        let concreteId = gen.typeLower.lower(concreteType).id
        let witness = gen.registry.addWitness(protocolId: protocolId, concreteType: concreteId)
        if witness.entries.isEmpty {
            if let protocolRecord = gen.registry.protocols[protocolId],
               let symbol = concreteType.symbol
            {
                for requirement in protocolRecord.requirements {
                    if let function = witnessImplementation(
                        requirement, in: symbol
                    ) {
                        witness.entries.append(
                            TIR.WitnessEntry(name: requirement, function: function.id)
                        )
                    }
                }
            }
        }
        return witness
    }

    private func witnessImplementation(
        _ name: String, in type: Symbol.NominalTypeSymbol
    ) -> TIR.Function? {
        var current: Symbol.NominalTypeSymbol? = type
        while let currentType = current {
            if let entries = currentType.scope.values[name] {
                if let functionSymbol = entries.first as? Symbol.FunctionSymbol,
                   let function = gen.functionsBySymbol[functionSymbol.id]
                {
                    return function
                }
                if let variableSymbol = entries.first as? Symbol.VariableSymbol,
                   let getter = gen.accessorFunctions[variableSymbol.id]?.getter
                {
                    return getter
                }
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return nil
    }

    private func existentialBox(for symbolId: Id.SymbolId?) -> GenerationContext.ExistentialBox? {
        guard let symbolId else { return nil }
        return gen.existentialBoxes[symbolId]
    }

    private func objectSymbol(of expression: AST.Expression) -> Id.SymbolId? {
        switch expression {
        case let variable as AST.Variable:
            variable.symbol?.id
        case let member as AST.MemberAccess:
            member.symbol?.id
        case let parenthetical as AST.Parenthetical:
            objectSymbol(of: parenthetical.inner)
        default:
            nil
        }
    }

    private func emitWitnessDispatch(
        _ memberAccess: AST.MemberAccess, arguments: [AST.LabeledArgument]
    ) -> TIR.Value? {
        guard let objectValue = visitExpression(memberAccess.object)
        else {
            return nil
        }
        if let box = existentialBox(for: objectSymbol(of: memberAccess.object)),
           let dispatched = emitBoxedWitnessDispatch(
               memberAccess, arguments: arguments, objectValue: objectValue, box: box
           )
        {
            return dispatched
        }
        return emitOpaqueWitnessDispatch(
            memberAccess, arguments: arguments, objectValue: objectValue
        )
    }

    private func emitBoxedWitnessDispatch(
        _ memberAccess: AST.MemberAccess, arguments: [AST.LabeledArgument],
        objectValue: TIR.Value, box: GenerationContext.ExistentialBox
    ) -> TIR.Value? {
        guard let builder else { return nil }
        let protocolId = declaringProtocolId(of: memberAccess)
            ?? protocolIdForRequirement(memberAccess.member.value, in: box)
        guard let protocolId else { return nil }
        guard let witnessId = box.witnesses[protocolId] else { return nil }
        guard let witness = gen.registry.witnesses[witnessId] else { return nil }
        guard let index = requirementIndex(of: memberAccess.member.value, in: witness) else {
            return nil
        }
        let opened = builder.buildOpenExistential(
            container: objectValue, ty: box.concreteType
        ).result
        let argValues: [TIR.Value] = arguments.compactMap { visitExpression($0.value) }
        let resultTy = witnessReturnType(of: witness, index: index)
            ?? memberAccess.ty.flatMap { lowerType($0).id }
        guard let resultTy else { return nil }
        return builder.buildWitnessMethod(
            witness: witnessId, index: index, selfValue: opened, arguments: argValues,
            ty: resultTy
        ).result
    }

    private func emitOpaqueWitnessDispatch(
        _ memberAccess: AST.MemberAccess, arguments: [AST.LabeledArgument],
        objectValue: TIR.Value
    ) -> TIR.Value? {
        guard let builder else { return nil }
        guard let protocolId = opaqueProtocolId(
            of: memberAccess, objectType: memberAccess.object.ty
        ) else {
            return nil
        }
        guard let record = gen.registry.protocols[protocolId] else { return nil }
        guard let index = record.requirements.firstIndex(of: memberAccess.member.value) else {
            return nil
        }
        let argValues: [TIR.Value] = arguments.compactMap { visitExpression($0.value) }
        let resultTy = opaqueReturnType(of: memberAccess, protocolId: protocolId)
            ?? memberAccess.ty.flatMap { lowerType($0).id }
        guard let resultTy else { return nil }
        return builder.buildOpaqueWitnessMethod(
            container: objectValue, protocolId: protocolId, index: index,
            selfValue: objectValue, arguments: argValues, ty: resultTy
        ).result
    }

    private func opaqueReturnType(
        of memberAccess: AST.MemberAccess, protocolId: Id.TIRProtocolId
    ) -> Id.TIRTypeId? {
        guard let symbol = gen.typeLower.protocolSymbol(protocolId),
              let fn = symbol.scope.values[memberAccess.member.value]?
              .compactMap({ $0 as? Symbol.FunctionSymbol }).first,
              let functionType = fn.functionType
        else {
            return nil
        }
        return lowerType(functionType.returnType).id
    }

    private func opaqueProtocolId(
        of memberAccess: AST.MemberAccess, objectType: TrussType.TrussType?
    ) -> Id.TIRProtocolId? {
        if let declared = declaringProtocolId(of: memberAccess) {
            return declared
        }
        let protocolTypes = protocols(of: objectType)
        if protocolTypes.count == 1, let single = protocolTypes.first {
            return gen.typeLower.protocolId(for: single)
        }
        for protocolType in protocolTypes {
            let protocolId = gen.typeLower.protocolId(for: protocolType)
            if let record = gen.registry.protocols[protocolId],
               record.requirements.contains(memberAccess.member.value)
            {
                return protocolId
            }
        }
        return nil
    }

    private func declaringProtocolId(of memberAccess: AST.MemberAccess) -> Id.TIRProtocolId? {
        guard let memberOf = memberAccess.symbol?.memberOf,
              let owner = context.id2Symbol[memberOf] as? Symbol.ProtocolSymbol,
              let typeId = owner.typeId,
              let protocolType = context.typeTable[typeId] as? TrussType.ProtocolType
        else {
            return nil
        }
        return gen.typeLower.protocolId(for: protocolType)
    }

    private func protocolIdForRequirement(
        _ name: String, in box: GenerationContext.ExistentialBox
    ) -> Id.TIRProtocolId? {
        if box.witnesses.count == 1 {
            return box.witnesses.keys.first
        }
        for (protocolId, witnessId) in box.witnesses {
            guard let witness = gen.registry.witnesses[witnessId],
                  witness.entries.contains(where: { $0.name == name })
            else {
                continue
            }
            return protocolId
        }
        return nil
    }

    private func requirementIndex(of name: String, in witness: TIR.WitnessRecord) -> Int? {
        witness.entries.firstIndex(where: { $0.name == name })
    }

    private func witnessReturnType(
        of witness: TIR.WitnessRecord, index: Int
    ) -> Id.TIRTypeId? {
        guard index < witness.entries.count else { return nil }
        let functionId = witness.entries[index].function
        guard let function = gen.registry.functions[functionId] else { return nil }
        return function.returnType
    }

    private func loadFrom(_ address: TIR.Value, range: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        return builder.buildLoad(ptr: address).result
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
            hasSelf: symbol.memberOf != nil, owner: ownerOf(symbol.memberOf), range: functionDecl.sourceRange
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
            parameters: initDecl.parameters, hasSelf: true, owner: ownerOf(symbol.memberOf),
            range: initDecl.sourceRange
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
        currentFunctionIsThrowing = symbol?.functionType?.isThrowing == true
        blockCounter = 0
        deferStack = []
        handlerStack = []
        loopStack = []
        labelMap = [:]
        deferStack.append(DeferFrame())
        existentialLocalStack = [[]]
        if currentFunctionIsThrowing {
            handlerStack.append(ExceptionHandler(catchEntry: nil, errorSlot: nil, deferDepth: 0))
        }

        bindParameters(
            function: function, symbol: symbol, parameters: parameters,
            hasSelf: hasSelf, owner: owner
        )

        switch body {
        case let .Block(statements):
            let savedLabelInsert = b.insertPoint
            collectForwardLabels(statements)
            b.insertPoint = savedLabelInsert
            visitBodyStatements(statements, implicitReturn: shouldImplicitReturn(symbol?.functionType?.returnType))
        case let .Expression(expression):
            if let value = visitExpression(expression) {
                emitReturn(value, range: range)
            } else {
                emitReturn(nil, range: range)
            }
        }
        destroyActiveExistentials()
        ensureTerminator(range: range)

        builder = savedBuilder
        env = savedEnv
        gen.modulePathStack = savedModulePath
    }

    private func bindParameters(
        function: TIR.Function, symbol: Symbol.FunctionSymbol?, parameters: [AST.FunctionDecl.Parameter],
        hasSelf: Bool, owner: Symbol.NominalTypeSymbol?
    ) {
        guard let builder else { return }
        var selfIndex = 0
        if hasSelf, let owner, let selfParameter = function.parameters.first {
            if isInitPointerSelf(selfParameter.ty) {
                env[owner.id] = selfParameter
                selfIndex = 1
            } else {
                let alloc = builder.buildAllocStack(
                    allocatedType: selfParameter.ty, name: selfParameter.name
                )
                builder.buildStore(value: selfParameter, to: alloc.result)
                env[owner.id] = alloc.result
                selfIndex = 1
            }
        }
        for (index, parameter) in parameters.enumerated() {
            let paramType = lowerType(
                symbol?.functionType?.parameters[safe: index].map(\.type)
                    ?? parameter.type?.ty
            )
            let argument = function.parameters[safe: index + selfIndex] ?? TIR.Parameter(
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
    public override func visitThrow(_ throwStatement: AST.Throw, additional: Any? = nil) -> Any? {
        guard let errValue = visitExpression(throwStatement.expression) else { return nil }
        routeToExceptionHandler(errValue, at: throwStatement.sourceRange)
        return nil
    }

    @discardableResult
    public override func visitTry(_ tryExpression: AST.Try, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        guard let call = tryExpression.expression as? AST.Call,
              let symbol = AST.Expression.resolvedFunctionSymbol(of: call.callee),
              symbol.functionType?.isThrowing == true,
              let calleeValue = lowerCallee(call.callee, at: call.sourceRange),
              let okType = call.ty,
              let errType = symbol.functionType?.throwsTypes.first
        else {
            return visitExpression(tryExpression.expression)
        }
        let arguments: [TIR.Value] = call.arguments.compactMap { visitExpression($0.value) }
        let okTypeId = lowerType(okType).id
        let errTypeId = lowerType(errType).id

        let errorSlot = builder.buildAllocStack(allocatedType: errTypeId, name: "$error")
        let preBlock = builder.insertPoint!
        let successBlock = newBlock()
        let errorBlock = newBlock()
        builder.insertPoint = preBlock
        let tryCall = builder.buildTryCall(
            callee: calleeValue, arguments: arguments,
            successBlock: successBlock, errorBlock: errorBlock,
            errorCell: errorSlot.result, resultTy: okTypeId
        )

        switch tryExpression.kind {
        case .Try:
            builder.insertPoint = errorBlock
            let errValue = builder.buildLoad(ptr: errorSlot.result).result
            routeToExceptionHandler(errValue, at: tryExpression.sourceRange)
            builder.insertPoint = successBlock
            return tryCall.result
        case .OptionalTry:
            let optionalType = lowerType(makeOptional(okType)).id
            let someIndex = optionalCaseIndex(optionalType, name: "Some")
            let noneIndex = optionalCaseIndex(optionalType, name: "None")
            let joinBlock = newBlock()
            var incomings: [TIR.Phi.Incoming] = []
            builder.insertPoint = errorBlock
            let none = builder.buildEnumValue(caseIndex: noneIndex, payload: nil, ty: optionalType)
            incomings.append(TIR.Phi.Incoming(value: none.result, block: errorBlock))
            builder.buildBranch(to: joinBlock)
            builder.insertPoint = successBlock
            if let okResult = tryCall.result {
                let some = builder.buildEnumValue(caseIndex: someIndex, payload: okResult, ty: optionalType)
                incomings.append(TIR.Phi.Incoming(value: some.result, block: successBlock))
            }
            builder.buildBranch(to: joinBlock)
            builder.insertPoint = joinBlock
            if incomings.count >= 2 {
                return builder.buildPhi(incomings: incomings).result
            }
            return incomings.first?.value
        case .TryExclamation:
            builder.insertPoint = errorBlock
            builder.buildTrap(message: "error thrown")
            builder.buildUnreachable()
            builder.insertPoint = successBlock
            return tryCall.result
        }
    }

    @discardableResult
    public override func visitDo(_ doExpression: AST.Do, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let producesValue = doExpression.ty.map { type in
            !(type is TrussType.VoidType) && !(type is TrussType.NeverType)
        } ?? false
        let hasCatches = !doExpression.catches.isEmpty
        let preBlock = builder.insertPoint!
        let doFrameDepth = deferStack.count
        pushDeferFrame()
        if let finallyBody = doExpression.finallyBody {
            deferStack[doFrameDepth].bodies.append(finallyBody)
        }
        if hasCatches {
            let errorSlotType = doErrorSlotTypeId(doExpression.catches)
                ?? doBodyErrorTypeId(doExpression.body)
                ?? throwingTupleTypes()?.err
                ?? gen.registry.voidType().id
            let errorSlot = builder.buildAllocStack(allocatedType: errorSlotType, name: "$error").result
            let dispatchBlock = newBlock()
            let joinBlock = newBlock()
            handlerStack.append(ExceptionHandler(
                catchEntry: dispatchBlock, errorSlot: errorSlot, deferDepth: doFrameDepth + 1
            ))
            builder.insertPoint = preBlock
            var incomings: [TIR.Phi.Incoming] = []
            let bodyValue = visitValueStatements(doExpression.body)
            emitDefersDownTo(deferStack.count - 1)
            if !blockTerminated() {
                if producesValue, let bodyValue {
                    incomings.append(TIR.Phi.Incoming(value: bodyValue, block: builder.insertPoint!))
                }
                builder.buildBranch(to: joinBlock)
            }
            builder.insertPoint = dispatchBlock
            emitCatchDispatch(
                catches: doExpression.catches, errorSlot: errorSlot, entryBlock: dispatchBlock,
                joinBlock: joinBlock, incomings: &incomings, producesValue: producesValue,
                doFrameDepth: doFrameDepth
            )
            handlerStack.removeLast()
            builder.insertPoint = joinBlock
            if producesValue {
                if incomings.count >= 2 {
                    let value = builder.buildPhi(incomings: incomings).result
                    popDeferFrame()
                    return value
                } else if incomings.count == 1 {
                    popDeferFrame()
                    return incomings[0].value
                }
            }
            popDeferFrame()
            return nil
        }
        builder.insertPoint = preBlock
        let value = visitValueStatements(doExpression.body)
        emitDefersDownTo(deferStack.count - 1)
        popDeferFrame()
        return producesValue ? value : nil
    }

    private func emitCatchDispatch(
        catches: [AST.Do.CatchClause], errorSlot: TIR.Value, entryBlock: TIR.BasicBlock,
        joinBlock: TIR.BasicBlock, incomings: inout [TIR.Phi.Incoming], producesValue: Bool,
        doFrameDepth: Int
    ) {
        guard let builder else { return }
        let clauseBlocks: [TIR.BasicBlock] = [entryBlock] + (1 ..< catches.count).map { _ in newBlock() }
        let trapBlock = newBlock()
        for (index, catchClause) in catches.enumerated() {
            let clauseBlock = clauseBlocks[index]
            builder.insertPoint = clauseBlock
            let isLast = index == catches.count - 1
            let nextBlock = isLast ? trapBlock : clauseBlocks[index + 1]
            let errValue = builder.buildLoad(ptr: errorSlot).result
            let condition = catchMatchCondition(catchClause.pattern, subject: errValue)
            let bodyBlock = newBlock()
            builder.insertPoint = clauseBlock
            if let condition {
                builder.buildConditionalBranch(
                    condition: condition, trueBranch: bodyBlock, falseBranch: nextBlock
                )
            } else {
                builder.buildBranch(to: bodyBlock)
            }
            builder.insertPoint = bodyBlock
            if let pattern = catchClause.pattern {
                bindCatchPattern(pattern, subject: errValue, body: catchClause.body)
            }
            if let whereCondition = catchClause.whereCondition,
               let cond = visitExpression(whereCondition)
            {
                let passBlock = newBlock()
                builder.insertPoint = bodyBlock
                builder.buildConditionalBranch(
                    condition: cond, trueBranch: passBlock, falseBranch: nextBlock
                )
                builder.insertPoint = passBlock
            }
            pushDeferFrame()
            let catchValue = visitValueStatements(catchClause.body)
            emitDefersDownTo(doFrameDepth)
            if !blockTerminated() {
                if producesValue, let catchValue {
                    incomings.append(TIR.Phi.Incoming(value: catchValue, block: builder.insertPoint!))
                }
                builder.buildBranch(to: joinBlock)
            }
            popDeferFrame()
        }
        builder.insertPoint = trapBlock
        builder.buildTrap(message: "uncaught error")
        builder.buildUnreachable()
    }

    private func catchMatchCondition(_ pattern: AST.Expression?, subject: TIR.Value) -> TIR.Value? {
        guard let pattern else { return nil }
        if let binding = pattern as? AST.BindingPattern, let subpattern = binding.subpattern {
            return catchMatchCondition(subpattern, subject: subject)
        }
        if let variable = pattern as? AST.Variable,
           let symbol = variable.symbol as? Symbol.NominalTypeSymbol,
           let typeId = symbol.typeId, let type = context.typeTable[typeId]
        {
            return emitTypeTestForType(subject, type)
        }
        return emitTypeTestPattern(pattern, subject: subject)
    }

    private func emitTypeTestForType(_ value: TIR.Value, _ type: TrussType.TrussType) -> TIR.Value? {
        guard let builder else { return nil }
        let typeId = lowerType(type).id
        if type is TrussType.ClassType {
            return emitIsInstanceCheck(value: value, target: type, targetId: typeId)?.result
        }
        return builder.buildBoolLiteral(value: value.ty == typeId, ty: boolTypeId())
    }

    private func bindCatchPattern(
        _ pattern: AST.Expression, subject: TIR.Value, body: [AST.Statement]
    ) {
        switch pattern {
        case let asPattern as AST.AsPattern:
            bindAsPattern(asPattern, subject: subject, body: body)
        case let binding as AST.BindingPattern:
            bindCatchValue(binding.name.value, subject: subject, body: body)
            if let subpattern = binding.subpattern {
                bindCatchPattern(subpattern, subject: subject, body: body)
            }
        case let variable as AST.Variable:
            if variable.symbol is Symbol.NominalTypeSymbol { return }
            bindCatchValue(variable.name.value, subject: subject, body: body)
        default:
            break
        }
    }

    private func bindCatchValue(_ name: String, subject: TIR.Value, body: [AST.Statement]) {
        guard let builder, let symbol = findVariableSymbol(name: name, in: body) else { return }
        let alloc = builder.buildAllocStack(allocatedType: subject.ty, name: name)
        builder.buildStore(value: subject, to: alloc.result)
        env[symbol.id] = alloc.result
    }

    private func doErrorSlotTypeId(_ catches: [AST.Do.CatchClause]) -> Id.TIRTypeId? {
        for catchClause in catches {
            if let pattern = catchClause.pattern, let type = catchPatternType(pattern),
               let cls = nominalClassType(of: type)
            {
                return lowerType(cls).id
            }
            if let pattern = catchClause.pattern, let binding = pattern as? AST.BindingPattern,
               let symbol = findVariableSymbol(name: binding.name.value, in: catchClause.body),
               let type = symbol.type, let cls = nominalClassType(of: type)
            {
                return lowerType(cls).id
            }
        }
        return nil
    }

    private func doBodyErrorTypeId(_ statements: [AST.Statement]) -> Id.TIRTypeId? {
        for statement in statements {
            if let expressionStatement = statement as? AST.ExpressionStatement,
               let tryExpression = expressionStatement.expression as? AST.Try,
               let call = tryExpression.expression as? AST.Call,
               let symbol = AST.Expression.resolvedFunctionSymbol(of: call.callee),
               let errType = symbol.functionType?.throwsTypes.first,
               let cls = nominalClassType(of: errType)
            {
                return lowerType(cls).id
            }
        }
        return nil
    }

    private func catchPatternType(_ pattern: AST.Expression) -> TrussType.TrussType? {
        switch pattern {
        case let asPattern as AST.AsPattern:
            return asPattern.typeExpression.ty
        case let isPattern as AST.IsPattern:
            return isPattern.typeExpression.ty
        case let binding as AST.BindingPattern:
            if let sub = binding.subpattern { return catchPatternType(sub) }
            return binding.typeExpression?.ty
        case let variable as AST.Variable:
            if let symbol = variable.symbol as? Symbol.NominalTypeSymbol,
               let typeId = symbol.typeId
            {
                return context.typeTable[typeId]
            }
            return nil
        default:
            return nil
        }
    }

    private func optionalCaseIndex(_ optionalTypeId: Id.TIRTypeId, name: String) -> Int {
        if let enumType = gen.registry.types[optionalTypeId] as? TIRType.EnumType,
           let index = enumType.cases.firstIndex(where: { $0.name == name })
        {
            return index
        }
        return name == "None" ? 0 : 1
    }

    @discardableResult
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = variableDecl.symbol else { return nil }
        if symbol.memberOf != nil, !variableDecl.accessors.isEmpty {
            generateMemberAccessorBodies(variableDecl, symbol: symbol)
            return nil
        }
        guard let builder else { return nil }
        let type = lowerType(symbol.type)
        let alloc = builder.buildAllocStack(allocatedType: type.id, name: symbol.name)
        let address = alloc.result
        env[symbol.id] = address
        if let initializer = variableDecl.initializer, let value = visitExpression(initializer) {
            let storedValue = existentialBoxedValue(
                value: value, valueType: initializer.ty, targetType: symbol.type,
                boxKey: symbol.id, sourceSymbolId: objectSymbol(of: initializer),
                sourceRange: initializer.sourceRange
            )
            if let storedValue {
                builder.buildStore(value: storedValue, to: address)
            }
        }
        return nil
    }

    private func generateMemberAccessorBodies(
        _ variableDecl: AST.VariableDecl, symbol: Symbol.VariableSymbol
    ) {
        guard let pair = gen.accessorFunctions[symbol.id] else { return }
        let owner = ownerOf(symbol.memberOf)
        for accessor in variableDecl.accessors {
            switch accessor.kind {
            case .Get:
                if let getter = pair.getter {
                    generateAccessorBody(
                        accessor, function: getter, owner: owner,
                        implicitParamName: nil, implicitReturn: true
                    )
                }
            case .Set:
                if let setter = pair.setter {
                    generateAccessorBody(
                        accessor, function: setter, owner: owner,
                        implicitParamName: accessor.parameterName?.value ?? "newValue",
                        implicitReturn: false
                    )
                }
            case .WillSet:
                if let willSet = pair.willSet {
                    generateAccessorBody(
                        accessor, function: willSet, owner: owner,
                        implicitParamName: accessor.parameterName?.value ?? "newValue",
                        implicitReturn: false
                    )
                }
            case .DidSet:
                if let didSet = pair.didSet {
                    generateAccessorBody(
                        accessor, function: didSet, owner: owner,
                        implicitParamName: accessor.parameterName?.value ?? "oldValue",
                        implicitReturn: false
                    )
                }
            }
        }
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = subscriptDecl.symbol else { return nil }
        guard let pair = gen.accessorFunctions[symbol.id] else { return nil }
        let owner = ownerOf(symbol.memberOf)
        for accessor in subscriptDecl.accessors {
            switch accessor.kind {
            case .Get:
                if let getter = pair.getter {
                    generateAccessorBody(
                        accessor, function: getter, owner: owner,
                        implicitParamName: nil, implicitReturn: true
                    )
                }
            case .Set:
                if let setter = pair.setter {
                    generateAccessorBody(
                        accessor, function: setter, owner: owner,
                        implicitParamName: accessor.parameterName?.value ?? "newValue",
                        implicitReturn: false
                    )
                }
            default:
                break
            }
        }
        return nil
    }

    private func generateAccessorBody(
        _ accessor: AST.Accessor, function: TIR.Function, owner: Symbol.NominalTypeSymbol?,
        implicitParamName: String?, implicitReturn: Bool
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
        currentFunctionIsThrowing = false
        blockCounter = 0
        deferStack = []
        handlerStack = []
        loopStack = []
        labelMap = [:]
        deferStack.append(DeferFrame())

        if let owner {
            if let selfParameter = function.parameters.first {
                let alloc = b.buildAllocStack(
                    allocatedType: selfParameter.ty, name: selfParameter.name
                )
                b.buildStore(value: selfParameter, to: alloc.result)
                env[owner.id] = alloc.result
            }
        }
        if let implicitParamName {
            if let variableSymbol = accessor.scope?.values[implicitParamName]?.compactMap({
                $0 as? Symbol.VariableSymbol
            }).first {
                if let implicitParameter = function.parameters.last {
                    let alloc = b.buildAllocStack(
                        allocatedType: implicitParameter.ty, name: implicitParameter.name
                    )
                    b.buildStore(value: implicitParameter, to: alloc.result)
                    env[variableSymbol.id] = alloc.result
                }
            }
        }

        switch accessor.body {
        case let .Block(statements):
            let savedLabelInsert = b.insertPoint
            collectForwardLabels(statements)
            b.insertPoint = savedLabelInsert
            visitBodyStatements(statements, implicitReturn: implicitReturn)
        case let .Expression(expression):
            if let value = visitExpression(expression) {
                emitReturn(value, range: accessor.sourceRange)
            } else if implicitReturn {
                emitReturn(nil, range: accessor.sourceRange)
            }
        }
        ensureTerminator(range: accessor.sourceRange)

        builder = savedBuilder
        env = savedEnv
        gen.modulePathStack = savedModulePath
    }

    private func emitReturn(_ value: TIR.Value?, range: SourceRange) {
        guard let builder else { return }
        if blockTerminated() { return }
        emitDefersDownTo(0)
        if blockTerminated() { return }
        destroyActiveExistentials()
        if let types = throwingTupleTypes() {
            let okValue = value ?? makePlaceholder(types.ok)
            let errValue = builder.buildNullptrLiteral(ty: types.err)
            let tuple = buildResultTuple(ok: okValue, err: errValue, types: types)
            builder.buildReturn(tuple)
        } else {
            builder.buildReturn(value)
        }
    }

    private func destroyActiveExistentials() {
        guard let builder, let frame = existentialLocalStack.last else { return }
        for symbolId in frame {
            guard let address = env[symbolId] else { continue }
            let container = builder.buildLoad(ptr: address).result
            builder.buildExistentialDestroy(container: container)
        }
    }

    private func destroyExistential(_ container: TIR.Value) {
        guard let builder else { return }
        builder.buildExistentialDestroy(container: container)
    }

    private func emitThrowReturn(_ errValue: TIR.Value, at range: SourceRange) {
        guard let builder else { return }
        if blockTerminated() { return }
        emitDefersDownTo(0)
        if blockTerminated() { return }
        if let types = throwingTupleTypes() {
            let okValue = makePlaceholder(types.ok)
            let tuple = buildResultTuple(ok: okValue, err: errValue, types: types)
            builder.buildReturn(tuple)
        } else {
            context.emitError("'throw' outside of a throwing function", at: range)
            builder.buildReturn(nil)
        }
    }

    private func buildResultTuple(
        ok: TIR.Value, err: TIR.Value, types: (ok: Id.TIRTypeId, err: Id.TIRTypeId)
    ) -> TIR.Value {
        guard let builder else {
            fatalError("unreachable")
        }
        let ty = gen.registry.tupleType(elements: [
            TIRType.TupleType.Element(label: "ok", type: types.ok),
            TIRType.TupleType.Element(label: "err", type: types.err),
        ])
        return builder.buildTupleValue(elements: [ok, err], ty: ty.id).result
    }

    private func throwingTupleTypes() -> (ok: Id.TIRTypeId, err: Id.TIRTypeId)? {
        guard currentFunctionIsThrowing, let function = currentFunction else { return nil }
        guard let tuple = gen.registry.types[function.returnType] as? TIRType.TupleType,
              tuple.elements.count == 2
        else { return nil }
        return (tuple.elements[0].type, tuple.elements[1].type)
    }

    private func makePlaceholder(_ typeId: Id.TIRTypeId) -> TIR.Value {
        guard let builder else {
            fatalError("unreachable")
        }
        let alloc = builder.buildAllocStack(allocatedType: typeId, name: "$undef")
        return builder.buildLoad(ptr: alloc.result).result
    }

    private func routeToExceptionHandler(_ errValue: TIR.Value?, at range: SourceRange) {
        guard let builder else { return }
        guard let handler = handlerStack.last else {
            context.emitError("thrown error is not caught by any handler", at: range)
            return
        }
        if let catchEntry = handler.catchEntry {
            emitDefersDownTo(handler.deferDepth)
            if blockTerminated() { return }
            if let slot = handler.errorSlot, let errValue {
                builder.buildStore(value: errValue, to: slot)
            }
            builder.buildBranch(to: catchEntry)
        } else if let errValue {
            emitThrowReturn(errValue, at: range)
        }
    }

    private func isTerminator(_ instruction: TIR.Instruction) -> Bool {
        instruction is TIR.Return || instruction is TIR.Branch
            || instruction is TIR.ConditionalBranch || instruction is TIR.SwitchEnum
            || instruction is TIR.Unreachable || instruction is TIR.Trap
    }

    private func ensureTerminator(range: SourceRange) {
        guard let builder, let insertPoint = builder.insertPoint else { return }
        if let last = insertPoint.instructions.last, isTerminator(last) {
            return
        }
        if let types = throwingTupleTypes() {
            let okValue = makePlaceholder(types.ok)
            let errValue = builder.buildNullptrLiteral(ty: types.err)
            let tuple = buildResultTuple(ok: okValue, err: errValue, types: types)
            builder.buildReturn(tuple)
        } else {
            builder.buildReturn(nil)
        }
    }

    private func shouldImplicitReturn(_ type: TrussType.TrussType?) -> Bool {
        guard let type else { return false }
        return !(type is TrussType.VoidType)
    }

    private func newBlock(_ name: String? = nil) -> TIR.BasicBlock {
        guard let builder else {
            fatalError("unreachable")
        }
        let function = currentFunction!
        let blockName = name ?? "bb\(blockCounter)"
        blockCounter += 1
        let block = function.addBasicBlock(name: blockName)
        builder.insertPoint = block
        return block
    }

    private func blockTerminated() -> Bool {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let block = builder.insertPoint, let last = block.instructions.last else { return false }
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
        if let binding = ifExpression.condition as? AST.OptionalBinding {
            return lowerIfOptionalBinding(
                ifExpression, binding: binding, producesValue: producesValue, additional: additional
            )
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

    private func lowerIfOptionalBinding(
        _ ifExpression: AST.If, binding: AST.OptionalBinding, producesValue: Bool, additional: Any?
    ) -> Any? {
        guard let builder else { return nil }
        let hasElse = ifExpression.elseKind != nil
        guard let optionalValue = visitExpression(binding.value),
              let enumType = gen.registry.types[optionalValue.ty] as? TIRType.EnumType,
              let someIndex = enumType.cases.firstIndex(where: { $0.name == "Some" }),
              let noneIndex = enumType.cases.firstIndex(where: { $0.name == "None" }),
              let payloadType = enumType.cases[someIndex].associatedTypes.first
        else {
            return nil
        }
        let preBlock = builder.insertPoint!
        let thenBlock = newBlock()
        let elseBlock = hasElse ? newBlock() : nil
        let joinBlock = newBlock()
        builder.insertPoint = preBlock
        builder.buildSwitchEnum(
            value: optionalValue,
            cases: [
                TIR.SwitchEnum.Case(tag: someIndex, block: thenBlock),
                TIR.SwitchEnum.Case(tag: noneIndex, block: elseBlock ?? joinBlock),
            ]
        )

        var incomings: [TIR.Phi.Incoming] = []
        builder.insertPoint = thenBlock
        pushDeferFrame()
        if let symbol = findVariableSymbol(name: binding.name.value, in: ifExpression.then) {
            let extract = builder.buildExtractPayload(
                value: optionalValue, caseIndex: someIndex, ty: payloadType, name: binding.name.value
            )
            let alloc = builder.buildAllocStack(
                allocatedType: payloadType, name: binding.name.value
            )
            builder.buildStore(value: extract.result, to: alloc.result)
            env[symbol.id] = alloc.result
        }
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
    public override func visitMatch(_ match: AST.Match, additional: Any? = nil) -> Any? {
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
                if let isPattern = pattern as? AST.IsPattern {
                    guard let condition = emitTypeTestPattern(
                        isPattern, subject: subject
                    ) else { continue }
                    let nextBlock = newBlock()
                    builder.insertPoint = current
                    builder.buildConditionalBranch(
                        condition: condition, trueBranch: bodyBlock, falseBranch: nextBlock
                    )
                    current = nextBlock
                    builder.insertPoint = current
                    continue
                }
                if let asPattern = pattern as? AST.AsPattern {
                    guard let condition = emitTypeTestPattern(
                        asPattern, subject: subject
                    ) else { continue }
                    let nextBlock = newBlock()
                    builder.insertPoint = current
                    builder.buildConditionalBranch(
                        condition: condition, trueBranch: bodyBlock, falseBranch: nextBlock
                    )
                    current = nextBlock
                    builder.insertPoint = current
                    continue
                }
                guard let patternValue = visitExpression(pattern) else { continue }
                let eq = builder.buildBinaryArith(op: .Eq, lhs: subject, rhs: patternValue)
                let nextBlock = newBlock()
                builder.insertPoint = current
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
            for pattern in matchCase.patterns {
                if let asPattern = pattern as? AST.AsPattern {
                    bindAsPattern(asPattern, subject: subject, body: matchCase.body)
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

    private func emitTypeTestPattern(
        _ pattern: AST.Expression, subject: TIR.Value
    ) -> TIR.Value? {
        guard let builder else { return nil }
        let typeExpression: AST.Expression? = switch pattern {
        case let isPattern as AST.IsPattern:
            isPattern.typeExpression
        case let asPattern as AST.AsPattern:
            asPattern.typeExpression
        default:
            nil
        }
        guard let typeExpression, let target = typeExpression.ty else { return nil }
        let targetId = lowerType(target).id
        if target is TrussType.ClassType {
            return emitIsInstanceCheck(
                value: subject, target: target, targetId: targetId
            )?.result
        }
        let same = subject.ty == targetId
        return builder.buildBoolLiteral(value: same, ty: boolTypeId())
    }

    private func bindAsPattern(
        _ asPattern: AST.AsPattern, subject: TIR.Value, body: [AST.Statement]
    ) {
        guard let builder else { return }
        guard let target = asPattern.typeExpression.ty,
              let targetId = lowerType(target).id as Id.TIRTypeId?,
              let name = asPatternBindingName(asPattern),
              let symbol = findVariableSymbol(name: name, in: body)
        else { return }
        let casted = builder.buildUncheckedRefCast(value: subject, to: targetId)
        let alloc = builder.buildAllocStack(allocatedType: targetId, name: name)
        builder.buildStore(value: casted.result, to: alloc.result)
        env[symbol.id] = alloc.result
    }

    private func asPatternBindingName(_ asPattern: AST.AsPattern) -> String? {
        if let binding = asPattern.pattern as? AST.BindingPattern {
            return binding.name.value
        }
        if let variable = asPattern.pattern as? AST.Variable {
            return variable.name.value
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
        return call.arguments.compactMap { $0.value as? AST.BindingPattern }.first?.name.value
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
        let extract = builder.buildExtractPayload(
            value: subject, caseIndex: index, ty: payloadType, name: name
        )
        let alloc = builder.buildAllocStack(allocatedType: payloadType, name: name)
        builder.buildStore(value: extract.result, to: alloc.result)
        env[symbol.id] = alloc.result
    }

    private func findVariableSymbol(name: String, in statements: [AST.Statement]) -> Symbol.VariableSymbol? {
        statements.lazy.compactMap { self.findVariableSymbol(name: name, in: $0) }.first
    }

    private func findVariableSymbol(name: String, in statement: AST.Statement) -> Symbol.VariableSymbol? {
        if let expressionStatement = statement as? AST.ExpressionStatement {
            return findVariableSymbol(name: name, in: expressionStatement.expression)
        }
        if let variableDecl = statement as? AST.VariableDecl {
            return findVariableSymbol(name: name, in: variableDecl.initializer)
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
        if let member = expression as? AST.MemberAccess {
            return findVariableSymbol(name: name, in: member.object)
        }
        if let call = expression as? AST.Call {
            for argument in call.arguments {
                if let found = findVariableSymbol(name: name, in: argument.value) {
                    return found
                }
            }
            return findVariableSymbol(name: name, in: call.callee)
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
    public override func visitNullLiteral(
        _ nullLiteral: AST.NullLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let ty = lowerType(nullLiteral.ty).id
        return builder.buildNullptrLiteral(ty: ty)
    }

    @discardableResult
    public override func visitVoidLiteral(
        _ voidLiteral: AST.VoidLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        return builder.buildVoidLiteral(ty: lowerType(voidLiteral.ty).id)
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
        if let memberOf = symbol.memberOf, let selfAddress = env[memberOf],
           let ownerType = (context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol)?.typeId
           .flatMap({ context.typeTable[$0] }),
           let fieldAddress = memberFieldAddress(
               base: selfAddress, baseType: ownerType, memberName: symbol.name
           )
        {
            if variable.isLeftValue, !isReferenceType(variable.ty) {
                return fieldAddress
            }
            return loadFrom(fieldAddress, range: variable.sourceRange)
        }
        return nil
    }

    private func functionRefValue(_ symbol: Symbol.FunctionSymbol, at range: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        let function: TIR.Function
        if let existing = gen.functionsBySymbol[symbol.id] {
            function = existing
        } else {
            guard let module = gen.currentModule else { return nil }
            let functionType = symbol.functionType
            let parameters: [TIR.Parameter] = (functionType?.parameters ?? []).enumerated().map {
                index, parameter in
                TIR.Parameter(ty: gen.typeLower.lower(parameter.type).id, name: "arg\(index)")
            }
            let returnType = functionType.map { gen.typeLower.lower($0.returnType) }
                ?? gen.registry.voidType()
            let tirReturnType: TIRType.TIRType
            if functionType?.isThrowing == true, let throwsType = functionType?.throwsTypes.first {
                let errorType = gen.typeLower.lower(throwsType)
                tirReturnType = gen.registry.tupleType(elements: [
                    TIRType.TupleType.Element(label: "ok", type: returnType.id),
                    TIRType.TupleType.Element(label: "err", type: errorType.id),
                ])
            } else {
                tirReturnType = returnType
            }
            function = module.addFunction(
                name: symbol.name,
                parameters: parameters,
                returnType: tirReturnType.id,
                isVariadic: false,
                isExtern: true,
                callingConvention: nil
            )
            gen.functionsBySymbol[symbol.id] = function
        }
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
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        guard let builder, let functionType = closure.ty as? TrussType.FunctionType else {
            return nil
        }
        let captureEntries = closureCaptures(closure)
        let closureFunction = createClosureFunction(closure, functionType: functionType, captures: captureEntries)
        let captureValues = buildCaptureValues(captureEntries, at: closure.sourceRange)
        emitClosureBody(closure, function: closureFunction, functionType: functionType, captures: captureEntries)
        return builder.buildClosure(function: closureFunction, captures: captureValues).result
    }

    private func closureCaptures(_ closure: AST.Closure) -> [(symbol: Symbol.VariableSymbol, mutable: Bool)] {
        let scanner = ClosureCaptureScanner()
        var excluding: Set<Id.SymbolId> = []
        if let scope = closure.scope {
            for symbols in scope.values.values {
                for symbol in symbols {
                    excluding.insert(symbol.id)
                }
            }
        }
        let scan = scanner.scan(statements: closure.body, excluding: excluding)
        var entries: [(Symbol.VariableSymbol, Bool)] = []
        var seen = Set<Id.SymbolId>()
        let referenceIds = scan.referenced.filter { env[$0] != nil }
        for id in referenceIds {
            guard let symbol = context.id2Symbol[id] as? Symbol.VariableSymbol else { continue }
            if seen.contains(id) { continue }
            seen.insert(id)
            entries.append((symbol, scan.mutated.contains(id)))
        }
        if let signature = closure.signature {
            for item in signature.captureList {
                if item.specifier != nil {
                    context.emitError(
                        "unsupported: weak/unowned capture is not supported yet", at: item.name
                    )
                    continue
                }
                if let symbol = context.id2Symbol.values.compactMap({ $0 as? Symbol.VariableSymbol })
                    .first(where: { $0.name == item.name.value }),
                    !seen.contains(symbol.id)
                {
                    seen.insert(symbol.id)
                    entries.append((symbol, scan.mutated.contains(symbol.id)))
                }
            }
        }
        return entries
    }

    private func createClosureFunction(
        _ closure: AST.Closure, functionType: TrussType.FunctionType,
        captures: [(symbol: Symbol.VariableSymbol, mutable: Bool)]
    ) -> TIR.Function {
        let baseName = (currentFunction?.name ?? "") + "_closure_\(closureCounter)"
        closureCounter += 1
        var parameters: [TIR.Parameter] = captures.map { capture in
            let valueType = lowerType(capture.symbol.type).id
            let paramType = capture.mutable
                ? gen.registry.pointerType(pointee: valueType).id
                : valueType
            return TIR.Parameter(ty: paramType, name: capture.symbol.name)
        }
        parameters.append(contentsOf: functionType.parameters.enumerated().map { index, parameter in
            let ty = gen.typeLower.lower(parameter.type).id
            let name = closure.signature?.parameters[safe: index]?.name.value ?? "arg(index)"
            return TIR.Parameter(ty: ty, name: name)
        })
        let returnType = gen.typeLower.lower(functionType.returnType)
        return gen.currentModule!.addFunction(
            name: baseName, parameters: parameters, returnType: returnType.id,
            isVariadic: functionType.isVariadic, isExtern: false, callingConvention: nil
        )
    }

    private func buildCaptureValues(
        _ captures: [(symbol: Symbol.VariableSymbol, mutable: Bool)], at range: SourceRange
    ) -> [TIR.Value] {
        guard let builder else { return [] }
        var values: [TIR.Value] = []
        for capture in captures {
            guard let address = env[capture.symbol.id] else { continue }
            if capture.mutable {
                let cell = builder.buildAllocCell(allocatedType: lowerType(capture.symbol.type).id)
                if let value = loadFrom(address, range: range) {
                    builder.buildStore(value: value, to: cell.result)
                }
                values.append(cell.result)
            } else {
                if let value = loadFrom(address, range: range) {
                    values.append(value)
                }
            }
        }
        return values
    }

    private func emitClosureBody(
        _ closure: AST.Closure, function: TIR.Function, functionType: TrussType.FunctionType,
        captures: [(symbol: Symbol.VariableSymbol, mutable: Bool)]
    ) {
        guard gen.builder != nil else { return }
        let savedBuilder = builder
        let savedEnv = env
        let savedModulePath = gen.modulePathStack

        let entryBlock = function.addBasicBlock(name: "entry")
        let b = TIR.Builder(registry: gen.registry)
        b.insertPoint = entryBlock
        builder = b
        env = [:]
        currentFunction = function
        currentFunctionIsThrowing = functionType.isThrowing
        blockCounter = 0
        deferStack = []
        handlerStack = []
        loopStack = []
        labelMap = [:]
        deferStack.append(DeferFrame())
        if currentFunctionIsThrowing {
            handlerStack.append(ExceptionHandler(catchEntry: nil, errorSlot: nil, deferDepth: 0))
        }

        for (index, capture) in captures.enumerated() {
            guard let param = function.parameters[safe: index] else { continue }
            if capture.mutable {
                let address = b.buildProjectCell(cell: param).result
                env[capture.symbol.id] = address
            } else {
                let alloc = b.buildAllocStack(
                    allocatedType: lowerType(capture.symbol.type).id, name: capture.symbol.name
                )
                b.buildStore(value: param, to: alloc.result)
                env[capture.symbol.id] = alloc.result
            }
        }

        let userStart = captures.count
        var paramAddresses: [TIR.Value] = []
        if let signature = closure.signature {
            for (index, parameter) in signature.parameters.enumerated() {
                let paramType = lowerType(
                    functionType.parameters[safe: index].map(\.type) ?? parameter.type?.ty
                )
                let argument = function.parameters[safe: userStart + index] ?? TIR.Parameter(
                    ty: paramType.id, name: parameter.name.value
                )
                let alloc = b.buildAllocStack(allocatedType: paramType.id, name: parameter.name.value)
                b.buildStore(value: argument, to: alloc.result)
                paramAddresses.append(alloc.result)
                let variableSymbol = closureParameterVariableSymbol(closure, parameter.name.value)
                if let variableSymbol {
                    env[variableSymbol.id] = alloc.result
                }
            }
        }
        closureParamStack.append(paramAddresses)

        let savedLabelInsert = b.insertPoint
        collectForwardLabels(closure.body)
        b.insertPoint = savedLabelInsert
        visitBodyStatements(closure.body, implicitReturn: shouldImplicitReturn(functionType.returnType))
        ensureTerminator(range: closure.sourceRange)
        closureParamStack.removeLast()

        builder = savedBuilder
        env = savedEnv
        gen.modulePathStack = savedModulePath
    }

    private func closureParameterVariableSymbol(
        _ closure: AST.Closure, _ name: String
    ) -> Symbol.VariableSymbol? {
        closure.scope?.values[name]?.compactMap { $0 as? Symbol.VariableSymbol }.first
    }

    @discardableResult
    public override func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        if let arith = builtinArithInfo(of: call.callee) {
            let arguments: [TIR.Value] = call.arguments.compactMap { visitExpression($0.value) }
            return emitBuiltinArith(arith, arguments: arguments)
        }
        if let constructed = emitObjectConstruction(call) {
            return constructed
        }
        if let member = call.callee as? AST.MemberAccess,
           isExistentialType(member.object.ty),
           let dispatched = emitWitnessDispatch(member, arguments: call.arguments)
        {
            return dispatched
        }
        guard let calleeValue = lowerCallee(call.callee, at: call.sourceRange) else { return nil }
        var arguments: [TIR.Value] = call.arguments.map { visitExpression($0.value) }.compactMap { $0 }
        arguments.append(contentsOf: call.trailingClosures.compactMap { visitExpression($0.1) })
        return builder.buildCall(callee: calleeValue, arguments: arguments).result
    }

    private func emitObjectConstruction(_ call: AST.Call) -> TIR.Value? {
        guard let builder,
              let typeSymbol = nominalTypeSymbol(of: call.callee),
              let initFunction = gen.initFunctionsByType[typeSymbol.id],
              let typeId = typeSymbol.typeId,
              let nominal = context.typeTable[typeId] as? TrussType.NominalType
        else {
            return nil
        }
        let arguments: [TIR.Value] = call.arguments.compactMap { visitExpression($0.value) }
        let lowered = gen.typeLower.lower(nominal)
        if nominal is TrussType.ClassType {
            let alloc = builder.buildAllocHeap(allocatedType: lowered.id, name: "$object")
            let objectRef = builder.buildUncheckedRefCast(
                value: alloc.result, to: lowered.id
            ).result
            let callee = builder.buildFunctionRef(function: initFunction)
            builder.buildCall(callee: callee, arguments: [objectRef] + arguments)
            return objectRef
        }
        let alloc = builder.buildAllocStack(allocatedType: lowered.id, name: "$object")
        let address = alloc.result
        let callee = builder.buildFunctionRef(function: initFunction)
        builder.buildCall(callee: callee, arguments: [address] + arguments)
        return loadFrom(address, range: call.sourceRange)
    }

    private func nominalTypeSymbol(of expression: AST.Expression) -> Symbol.NominalTypeSymbol? {
        switch expression {
        case let variable as AST.Variable:
            variable.symbol as? Symbol.NominalTypeSymbol
        case let application as AST.GenericApplication:
            nominalTypeSymbol(of: application.base)
        default:
            nil
        }
    }

    @discardableResult
    public override func visitCast(_ cast: AST.Cast, additional: Any? = nil) -> Any? {
        guard let left = visitExpression(cast.left) else { return nil }
        guard let target = cast.right.ty else { return nil }
        let targetId = lowerType(target).id
        switch cast.kind {
        case .Is:
            return emitIsCast(left: left, target: target, targetId: targetId, at: cast.sourceRange)
        case .As:
            return emitAsCast(
                left: left, leftType: cast.left.ty, target: target, targetId: targetId,
                at: cast.sourceRange
            )
        case .AsExclamation:
            return emitForceCast(left: left, target: target, targetId: targetId)
        case .AsBitCast:
            return emitBitCast(left: left, target: target, targetId: targetId)
        case .OptionalAs:
            return emitOptionalAs(
                left: left, leftType: cast.left.ty, target: target, targetId: targetId,
                at: cast.sourceRange
            )
        }
    }

    private func emitIsCast(
        left: TIR.Value, target: TrussType.TrussType, targetId: Id.TIRTypeId, at range: SourceRange
    ) -> TIR.Value? {
        guard let builder else { return nil }
        if target is TrussType.ClassType {
            return emitIsInstanceCheck(value: left, target: target, targetId: targetId)?.result
        }
        let same = left.ty == targetId
        return builder.buildBoolLiteral(value: same, ty: boolTypeId())
    }

    private func emitAsCast(
        left: TIR.Value, leftType: TrussType.TrussType?, target: TrussType.TrussType,
        targetId: Id.TIRTypeId, at range: SourceRange
    ) -> TIR.Value? {
        guard let builder else { return nil }
        guard target is TrussType.ClassType else { return left }
        if isStaticUpcast(leftType, to: target) {
            return builder.buildUpcast(value: left, to: targetId).result
        }
        return emitCheckedDowncast(value: left, target: target, targetId: targetId, at: range)
    }

    private func emitForceCast(
        left: TIR.Value, target: TrussType.TrussType, targetId: Id.TIRTypeId
    ) -> TIR.Value? {
        guard let builder else { return nil }
        guard target is TrussType.ClassType else { return left }
        return builder.buildUncheckedRefCast(value: left, to: targetId).result
    }

    private func emitBitCast(
        left: TIR.Value, target: TrussType.TrussType, targetId: Id.TIRTypeId
    ) -> TIR.Value? {
        guard let builder else { return nil }
        guard target is TrussType.ClassType else { return left }
        return builder.buildUncheckedRefCast(value: left, to: targetId).result
    }

    private func emitOptionalAs(
        left: TIR.Value, leftType: TrussType.TrussType?, target: TrussType.TrussType,
        targetId: Id.TIRTypeId, at range: SourceRange
    ) -> TIR.Value? {
        guard let builder else { return nil }
        let optionalType = lowerType(makeOptional(target)).id
        if target is TrussType.ClassType {
            if isStaticUpcast(leftType, to: target) {
                let casted = builder.buildUncheckedRefCast(value: left, to: targetId)
                return builder.buildEnumValue(
                    caseIndex: 1, payload: casted.result, ty: optionalType
                ).result
            }
            return emitOptionalDowncast(
                value: left, target: target, targetId: targetId, optionalType: optionalType,
                at: range
            )
        }
        return builder.buildEnumValue(caseIndex: 1, payload: left, ty: optionalType).result
    }

    private func emitIsInstanceCheck(
        value: TIR.Value, target: TrussType.TrussType, targetId: Id.TIRTypeId
    ) -> TIR.IsInstance? {
        guard let builder else { return nil }
        let instanceMetadata = builder.buildTypeMetadata(value: value)
        guard let metadataId = metadataId(for: target) else { return nil }
        let targetMetadata = builder.buildTypeMetadataConstant(type: targetId, metadata: metadataId)
        return builder.buildIsInstance(metadata: instanceMetadata.result, target: targetMetadata.result)
    }

    private func emitCheckedDowncast(
        value: TIR.Value, target: TrussType.TrussType, targetId: Id.TIRTypeId, at range: SourceRange
    ) -> TIR.Value? {
        guard let builder, let check = emitIsInstanceCheck(value: value, target: target, targetId: targetId)
        else { return nil }
        let successBlock = newBlock()
        let failBlock = newBlock()
        builder.buildConditionalBranch(
            condition: check.result, trueBranch: successBlock, falseBranch: failBlock
        )
        builder.insertPoint = successBlock
        let casted = builder.buildUncheckedRefCast(value: value, to: targetId)
        builder.insertPoint = failBlock
        builder.buildTrap(message: "cast to \(typeName(of: target)) failed")
        builder.buildUnreachable()
        builder.insertPoint = successBlock
        return casted.result
    }

    private func emitOptionalDowncast(
        value: TIR.Value, target: TrussType.TrussType, targetId: Id.TIRTypeId,
        optionalType: Id.TIRTypeId, at range: SourceRange
    ) -> TIR.Value? {
        guard let builder, let check = emitIsInstanceCheck(value: value, target: target, targetId: targetId)
        else { return nil }
        let joinBlock = newBlock()
        let successBlock = newBlock()
        let failBlock = newBlock()
        builder.buildConditionalBranch(
            condition: check.result, trueBranch: successBlock, falseBranch: failBlock
        )
        var incomings: [TIR.Phi.Incoming] = []
        builder.insertPoint = successBlock
        let casted = builder.buildUncheckedRefCast(value: value, to: targetId)
        let some = builder.buildEnumValue(caseIndex: 1, payload: casted.result, ty: optionalType)
        incomings.append(TIR.Phi.Incoming(value: some.result, block: successBlock))
        builder.buildBranch(to: joinBlock)
        builder.insertPoint = failBlock
        let none = builder.buildEnumValue(caseIndex: 0, payload: nil, ty: optionalType)
        incomings.append(TIR.Phi.Incoming(value: none.result, block: failBlock))
        builder.buildBranch(to: joinBlock)
        builder.insertPoint = joinBlock
        if incomings.count >= 2 {
            return builder.buildPhi(incomings: incomings).result
        }
        return incomings.first?.value
    }

    private func metadataId(for type: TrussType.TrussType) -> Id.TIRMetadataId? {
        let nominal: TrussType.NominalType? = switch type {
        case let nominal as TrussType.NominalType:
            nominal
        case let generic as TrussType.GenericInstantiation:
            generic.base
        default:
            nil
        }
        guard let nominal else { return nil }
        return gen.typeLower.metadataId(for: nominal)
    }

    private func isStaticUpcast(
        _ leftType: TrussType.TrussType?, to target: TrussType.TrussType
    ) -> Bool {
        guard let leftClass = nominalClassType(of: leftType),
              let targetClass = nominalClassType(of: target)
        else {
            return false
        }
        var current: TrussType.ClassType? = leftClass
        while let cls = current {
            if cls.id == targetClass.id {
                return true
            }
            current = superclassClassType(of: cls)
        }
        return false
    }

    private func nominalClassType(of type: TrussType.TrussType?) -> TrussType.ClassType? {
        guard let type else { return nil }
        switch type {
        case let cls as TrussType.ClassType:
            return cls
        case let generic as TrussType.GenericInstantiation:
            return generic.base as? TrussType.ClassType
        default:
            return nil
        }
    }

    private func superclassClassType(of type: TrussType.ClassType) -> TrussType.ClassType? {
        guard let symbol = type.symbol as? Symbol.ClassSymbol,
              let superclassSymbol = symbol.superclass,
              let typeId = superclassSymbol.typeId
        else {
            return nil
        }
        return gen.context.typeTable[typeId] as? TrussType.ClassType
    }

    private func boolTypeId() -> Id.TIRTypeId {
        gen.registry.primitiveType(kind: .Bool, bitWidth: 1).id
    }

    private func makeOptional(_ wrapped: TrussType.TrussType) -> TrussType.TrussType {
        TrussType.GenericInstantiation(
            base: TrussType.EnumType(id: Id.ASTTypeId(UInt64.max), name: "Optional"),
            arguments: [wrapped]
        )
    }

    private func typeName(of type: TrussType.TrussType) -> String {
        if let nominal = nominalClassType(of: type) {
            return nominal.name
        }
        if let nominal = type as? TrussType.NominalType {
            return nominal.name
        }
        return "value"
    }

    private struct BuiltinArith {
        let op: TIR.ArithOp
        let arity: Int
    }

    private func builtinArithInfo(of callee: AST.Expression) -> BuiltinArith? {
        var expr = callee
        if let app = expr as? AST.GenericApplication {
            expr = app.base
        }
        let symbol: Symbol.FunctionSymbol? = if let variable = expr as? AST.Variable {
            variable.symbol as? Symbol.FunctionSymbol ?? variable.overloads?.first
        } else if let member = expr as? AST.MemberAccess {
            member.symbol as? Symbol.FunctionSymbol ?? member.overloads?.first
        } else {
            nil
        }
        guard let symbol, symbol.isBuiltin else { return nil }
        guard let info = Builtin.builtinFunctionInfo(named: symbol.name) else { return nil }
        guard let op = arithOp(named: info.opName) else { return nil }
        let arity = Builtin.unaryArithOpNames.contains(info.opName) ? 1 : 2
        return BuiltinArith(op: op, arity: arity)
    }

    private func arithOp(named name: String) -> TIR.ArithOp? {
        switch name {
        case "add": .Add
        case "sub": .Sub
        case "mul": .Mul
        case "div": .SDiv
        case "rem": .SRem
        case "neg": .Neg
        case "not": .Not
        case "bitnot": .Bitnot
        case "eq": .Eq
        case "ne": .Ne
        case "lt": .Lt
        case "le": .Le
        case "gt": .Gt
        case "ge": .Ge
        default: nil
        }
    }

    private func emitBuiltinArith(_ arith: BuiltinArith, arguments: [TIR.Value]) -> Any? {
        guard let builder else { return nil }
        if arith.arity == 1, let operand = arguments.first {
            return builder.buildUnaryArith(op: arith.op, operand: operand).result
        }
        if arguments.count >= 2 {
            return builder.buildBinaryArith(op: arith.op, lhs: arguments[0], rhs: arguments[1]).result
        }
        return nil
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

    @discardableResult
    public override func visitBinary(_ binary: AST.Binary, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        if binary.isAssignment || binary.operatorToken.value == "=" {
            return lowerAssignment(binary)
        }
        let opName = binary.operatorToken.value
        if opName == "&&" || opName == "||" {
            if isBoolType(binary.left.ty) {
                return lowerShortCircuit(binary)
            }
        }
        if let symbol = binary.symbol, symbol.isBuiltin {
            if let arith = arithOp(named: builtinOpName(of: symbol)) {
                guard let lhs = visitExpression(binary.left), let rhs = visitExpression(binary.right)
                else { return nil }
                return builder.buildBinaryArith(op: arith, lhs: lhs, rhs: rhs).result
            }
        }
        guard let symbol = binary.symbol, let callee = functionRefValue(symbol, at: binary.sourceRange) else {
            return nil
        }
        guard let lhs = visitExpression(binary.left), let rhs = visitExpression(binary.right) else { return nil }
        return builder.buildCall(callee: callee, arguments: [lhs, rhs]).result
    }

    private func builtinOpName(of symbol: Symbol.FunctionSymbol) -> String {
        symbol.name.hasPrefix("builtin_") ? String(symbol.name.dropFirst("builtin_".count).prefix { $0 != "_" })
            : ""
    }

    private func lowerAssignment(_ binary: AST.Binary) -> Any? {
        guard let builder else { return nil }
        guard let value = visitExpression(binary.right) else { return nil }
        binary.left.isLeftValue = true
        if let subscriptTarget = binary.left as? AST.Subscript {
            if let symbol = subscriptTarget.symbol,
               let setter = gen.accessorFunctions[symbol.id]?.setter
            {
                subscriptTarget.base.isLeftValue = true
                guard let base = visitExpression(subscriptTarget.base) else { return nil }
                let callee = builder.buildFunctionRef(function: setter)
                var arguments: [TIR.Value] = [base]
                arguments.append(contentsOf: subscriptTarget.arguments.compactMap {
                    visitExpression($0.value)
                })
                arguments.append(value)
                builder.buildCall(callee: callee, arguments: arguments)
                return nil
            }
        }
        if let memberTarget = binary.left as? AST.MemberAccess,
           let symbol = memberTarget.symbol as? Symbol.VariableSymbol,
           let pair = gen.accessorFunctions[symbol.id]
        {
            if let setter = pair.setter {
                memberTarget.object.isLeftValue = true
                guard let base = visitExpression(memberTarget.object) else { return nil }
                let callee = builder.buildFunctionRef(function: setter)
                builder.buildCall(callee: callee, arguments: [base, value])
                return nil
            }
            if let willSet = pair.willSet, let didSet = pair.didSet {
                memberTarget.object.isLeftValue = true
                guard let base = visitExpression(memberTarget.object) else { return nil }
                guard let address = memberAddress(memberTarget) else { return nil }
                let oldValue = loadFrom(address, range: binary.sourceRange)
                let willCallee = builder.buildFunctionRef(function: willSet)
                builder.buildCall(callee: willCallee, arguments: [base, oldValue ?? value])
                builder.buildStore(value: value, to: address)
                let didCallee = builder.buildFunctionRef(function: didSet)
                builder.buildCall(callee: didCallee, arguments: [base, value])
                return nil
            }
        }
        guard let address = lvalueAddress(binary.left) else { return nil }
        let stored: TIR.Value =
            isExistentialType(binary.right.ty)
                ? builder.buildExistentialCopy(container: value, ty: value.ty).result
                : value
        builder.buildStore(value: stored, to: address)
        return nil
    }

    private func lvalueAddress(_ expression: AST.Expression) -> TIR.Value? {
        switch expression {
        case let variable as AST.Variable:
            return visitVariable(variable) as? TIR.Value
        case let parenthetical as AST.Parenthetical:
            parenthetical.inner.isLeftValue = true
            return lvalueAddress(parenthetical.inner)
        case let member as AST.MemberAccess:
            member.isLeftValue = true
            return memberAddress(member)
        case let deref as AST.Dereference:
            return visitExpression(deref.expression)
        default:
            return visitExpression(expression)
        }
    }

    private func lowerShortCircuit(_ binary: AST.Binary) -> Any? {
        guard let builder else { return nil }
        let isAnd = binary.operatorToken.value == "&&"
        guard let lhs = visitExpression(binary.left) else { return nil }
        let preBlock = builder.insertPoint!
        let rhsBlock = newBlock()
        let constBlock = newBlock()
        let joinBlock = newBlock()
        builder.insertPoint = preBlock
        builder.buildConditionalBranch(
            condition: lhs, trueBranch: isAnd ? rhsBlock : constBlock,
            falseBranch: isAnd ? constBlock : rhsBlock
        )
        var incomings: [TIR.Phi.Incoming] = []
        builder.insertPoint = rhsBlock
        if let rhs = visitExpression(binary.right) {
            incomings.append(TIR.Phi.Incoming(value: rhs, block: rhsBlock))
        }
        if !blockTerminated() { builder.buildBranch(to: joinBlock) }
        builder.insertPoint = constBlock
        let constTy = lowerType(binary.ty).id
        let constValue = builder.buildBoolLiteral(value: !isAnd, ty: constTy)
        incomings.append(TIR.Phi.Incoming(value: constValue, block: constBlock))
        builder.buildBranch(to: joinBlock)
        builder.insertPoint = joinBlock
        if incomings.count >= 2 {
            return builder.buildPhi(incomings: incomings).result
        }
        return incomings.first?.value
    }

    private func isBoolType(_ type: TrussType.TrussType?) -> Bool {
        guard let builtin = type as? TrussType.BuiltinType else { return false }
        return builtin.name == "Bool"
    }

    @discardableResult
    public override func visitPrefix(_ prefix: AST.Prefix, additional: Any? = nil) -> Any? {
        guard let builder, let symbol = prefix.symbol else { return nil }
        if symbol.isBuiltin {
            if let arith = arithOp(named: builtinOpName(of: symbol)) {
                guard let operand = visitExpression(prefix.expression) else { return nil }
                return builder.buildUnaryArith(op: arith, operand: operand).result
            }
        }
        guard let callee = functionRefValue(symbol, at: prefix.sourceRange),
              let operand = visitExpression(prefix.expression)
        else { return nil }
        return builder.buildCall(callee: callee, arguments: [operand]).result
    }

    @discardableResult
    public override func visitPostfix(_ postfix: AST.Postfix, additional: Any? = nil) -> Any? {
        guard let builder, let symbol = postfix.symbol else { return nil }
        guard let callee = functionRefValue(symbol, at: postfix.sourceRange),
              let operand = visitExpression(postfix.expression)
        else { return nil }
        return builder.buildCall(callee: callee, arguments: [operand]).result
    }

    @discardableResult
    public override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        guard let symbol = selfExpression.symbol as? Symbol.NominalTypeSymbol else { return nil }
        if let address = env[symbol.id] {
            if selfExpression.isLeftValue, !isReferenceType(selfExpression.ty) {
                return address
            }
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
    public override func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        if let functionSymbol = implicitMemberAccess.symbol as? Symbol.FunctionSymbol
            ?? implicitMemberAccess.overloads?.first
        {
            return functionRefValue(functionSymbol, at: implicitMemberAccess.sourceRange)
        }
        if let caseSymbol = implicitMemberAccess.symbol as? Symbol.CaseSymbol {
            return enumValue(for: caseSymbol, sourceRange: implicitMemberAccess.sourceRange)
        }
        return nil
    }

    @discardableResult
    public override func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        if let functionSymbol = memberAccess.symbol as? Symbol.FunctionSymbol
            ?? memberAccess.overloads?.first
        {
            return functionRefValue(functionSymbol, at: memberAccess.sourceRange)
        }
        if let caseSymbol = memberAccess.symbol as? Symbol.CaseSymbol {
            return enumValue(for: caseSymbol, sourceRange: memberAccess.sourceRange)
        }
        if let symbol = memberAccess.symbol as? Symbol.VariableSymbol,
           let getter = gen.accessorFunctions[symbol.id]?.getter,
           !memberAccess.isLeftValue
        {
            memberAccess.object.isLeftValue = true
            guard let base = visitExpression(memberAccess.object) else { return nil }
            let callee = builder.buildFunctionRef(function: getter)
            return builder.buildCall(callee: callee, arguments: [base]).result
        }
        if let address = memberAddress(memberAccess) {
            if memberAccess.isLeftValue {
                return address
            }
            return loadFrom(address, range: memberAccess.sourceRange)
        }
        return nil
    }

    @discardableResult
    public override func visitSubscript(
        _ subscriptExpression: AST.Subscript, additional: Any? = nil
    ) -> Any? {
        guard let builder, let symbol = subscriptExpression.symbol else { return nil }
        guard let pair = gen.accessorFunctions[symbol.id], let getter = pair.getter else {
            return nil
        }
        subscriptExpression.base.isLeftValue = true
        guard let base = visitExpression(subscriptExpression.base) else { return nil }
        let callee = builder.buildFunctionRef(function: getter)
        var arguments: [TIR.Value] = [base]
        arguments.append(contentsOf: subscriptExpression.arguments.map { visitExpression($0.value) }.compactMap { $0 })
        return builder.buildCall(callee: callee, arguments: arguments).result
    }

    private func memberAddress(_ memberAccess: AST.MemberAccess) -> TIR.Value? {
        guard let base = visitExpression(memberAccess.object),
              let baseType = memberAccess.object.ty
        else { return nil }
        return memberFieldAddress(base: base, baseType: baseType, memberName: memberAccess.member.value)
    }

    private func memberFieldAddress(
        base: TIR.Value, baseType: TrussType.TrussType?, memberName: String
    ) -> TIR.Value? {
        guard let builder else { return nil }
        guard let baseTIR = gen.registry.types[lowerType(baseType).id] else { return nil }
        if let classType = baseTIR as? TIRType.ClassType,
           let index = classType.fields.firstIndex(where: { $0.name == memberName })
        {
            return builder.buildClassElementAddr(base: base, index: index).result
        }
        guard let structType = baseTIR as? TIRType.StructType,
              let index = structType.fields.firstIndex(where: { $0.name == memberName })
        else { return nil }
        return builder.buildStructElementAddr(base: base, index: index).result
    }

    private func enumValue(for caseSymbol: Symbol.CaseSymbol, sourceRange: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        guard let parentId = caseSymbol.memberOf, let parent = context.id2Symbol[parentId],
              let parentType = (parent as? Symbol.NominalTypeSymbol)?.typeId.flatMap({ context.typeTable[$0] }),
              let enumType = gen.registry.types[gen.typeLower.lower(parentType).id] as? TIRType.EnumType,
              let tag = enumType.cases.firstIndex(where: { $0.name == caseSymbol.name })
        else { return nil }
        return builder.buildEnumValue(caseIndex: tag, payload: nil, ty: enumType.id).result
    }

    @discardableResult
    public override func visitDereference(
        _ dereference: AST.Dereference, additional: Any? = nil
    ) -> Any? {
        dereference.expression.isLeftValue = true
        guard let ptr = visitExpression(dereference.expression) else { return nil }
        return loadFrom(ptr, range: dereference.sourceRange)
    }

    @discardableResult
    public override func visitAddressOf(_ addressOf: AST.AddressOf, additional: Any? = nil) -> Any? {
        addressOf.expression.isLeftValue = true
        return lvalueAddress(addressOf.expression)
    }

    @discardableResult
    public override func visitTuple(_ tuple: AST.Tuple, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let elements = tuple.elements.map { visitExpression($0.value) }.compactMap { $0 }
        let ty = lowerType(tuple.ty).id
        return builder.buildTupleValue(elements: elements, ty: ty).result
    }

    @discardableResult
    public override func visitSizeofExpression(
        _ sizeofExpression: AST.SizeofExpression, additional: Any? = nil
    ) -> Any? {
        guard let builder, let type = sizeofExpression.typeType else { return nil }
        let ty = gen.typeLower.lower(type).id
        return builder.buildSizeOf(sizedType: ty).result
    }

    @discardableResult
    public override func visitShorthandArgument(
        _ shorthandArgument: AST.ShorthandArgument, additional: Any? = nil
    ) -> Any? {
        guard let parameters = closureParamStack.last,
              shorthandArgument.index < parameters.count
        else { return nil }
        return loadFrom(parameters[shorthandArgument.index], range: shorthandArgument.sourceRange)
    }

    @discardableResult
    public override func visitForceUnwrap(
        _ forceUnwrap: AST.ForceUnwrap, additional: Any? = nil
    ) -> Any? {
        guard let builder, let value = visitExpression(forceUnwrap.expression),
              let enumType = gen.registry.types[value.ty] as? TIRType.EnumType,
              let someIndex = enumType.cases.firstIndex(where: { $0.name == "Some" }),
              let payloadType = enumType.cases[someIndex].associatedTypes.first
        else { return nil }
        return builder.buildExtractPayload(
            value: value, caseIndex: someIndex, ty: payloadType
        ).result
    }

    @discardableResult
    public override func visitOptionalBinding(
        _ optionalBinding: AST.OptionalBinding, additional: Any? = nil
    ) -> Any? {
        guard let builder, let value = visitExpression(optionalBinding.value),
              let enumType = gen.registry.types[value.ty] as? TIRType.EnumType,
              let someIndex = enumType.cases.firstIndex(where: { $0.name == "Some" }),
              let noneIndex = enumType.cases.firstIndex(where: { $0.name == "None" })
        else { return nil }
        let boolType = gen.registry.primitiveType(kind: .Bool, bitWidth: 1).id
        let preBlock = builder.insertPoint!
        let someBlock = newBlock()
        let noneBlock = newBlock()
        let joinBlock = newBlock()
        builder.insertPoint = preBlock
        builder.buildSwitchEnum(
            value: value,
            cases: [
                TIR.SwitchEnum.Case(tag: someIndex, block: someBlock),
                TIR.SwitchEnum.Case(tag: noneIndex, block: noneBlock),
            ]
        )
        builder.insertPoint = someBlock
        let trueValue = builder.buildBoolLiteral(value: true, ty: boolType)
        builder.buildBranch(to: joinBlock)
        builder.insertPoint = noneBlock
        let falseValue = builder.buildBoolLiteral(value: false, ty: boolType)
        builder.buildBranch(to: joinBlock)
        builder.insertPoint = joinBlock
        return builder.buildPhi(
            incomings: [
                TIR.Phi.Incoming(value: trueValue, block: someBlock),
                TIR.Phi.Incoming(value: falseValue, block: noneBlock),
            ]
        ).result
    }

    @discardableResult
    public override func visitAsm(_ asmStatement: AST.Asm, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        let template = asmStatement.templates.map(\.token.value).joined(separator: " ")
        let constraints = asmStatement.bindings.map(\.constraint.value)
        var operands: [TIR.Value] = []
        for binding in asmStatement.bindings {
            guard let local = binding.local,
                  let symbol = findAsmLocalSymbol(named: local.value)
            else { continue }
            let kind = binding.kind.value
            if kind == "in" {
                if let address = env[symbol.id], let loaded = loadFrom(address, range: binding.sourceRange) {
                    operands.append(loaded)
                }
            } else if let address = env[symbol.id] {
                operands.append(address)
            }
        }
        builder.buildInlineAsm(
            template: template, constraints: constraints,
            operands: operands, options: asmStatement.options.map(\.value)
        )
        return nil
    }

    private func findAsmLocalSymbol(named name: String) -> Symbol.VariableSymbol? {
        for symbol in gen.env.keys {
            if let resolved = gen.context.id2Symbol[symbol] as? Symbol.VariableSymbol,
               resolved.name == name
            {
                return resolved
            }
        }
        return nil
    }

    private func emitUnsupported(_ node: AST.Expression) -> Any? {
        context.emitError(
            "unsupported: cannot lower this syntax to TIR yet", at: node.sourceRange
        )
        return nil
    }

    @discardableResult
    public override func visitArrayLiteral(
        _ arrayLiteral: AST.ArrayLiteral, additional: Any? = nil
    ) -> Any? {
        emitUnsupported(arrayLiteral)
    }

    @discardableResult
    public override func visitDictionaryLiteral(
        _ dictionaryLiteral: AST.DictionaryLiteral, additional: Any? = nil
    ) -> Any? {
        emitUnsupported(dictionaryLiteral)
    }

    @discardableResult
    public override func visitStringInterpolation(
        _ stringInterpolation: AST.StringInterpolation, additional: Any? = nil
    ) -> Any? {
        emitUnsupported(stringInterpolation)
    }

    public override func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
        context.emitError(
            "unsupported: 'for' loops are not supported yet", at: forStatement.token
        )
        return nil
    }

    @discardableResult
    public override func visitAwait(_ awaitExpression: AST.Await, additional: Any? = nil) -> Any? {
        emitUnsupported(awaitExpression)
    }

    @discardableResult
    public override func visitKeyPathExpression(
        _ keyPathExpression: AST.KeyPathExpression, additional: Any? = nil
    ) -> Any? {
        emitUnsupported(keyPathExpression)
    }
}

private final class ClosureCaptureScanner: AST.Visitor {
    private var referencedOrder: [Id.SymbolId] = []
    private var referencedSet: Set<Id.SymbolId> = []
    private var mutated: Set<Id.SymbolId> = []
    private var excluding: Set<Id.SymbolId> = []

    func scan(statements: [AST.Statement],
              excluding excluded: Set<Id.SymbolId>) -> (referenced: [Id.SymbolId], mutated: Set<Id.SymbolId>)
    {
        excluding = excluded
        referencedOrder = []
        referencedSet = []
        mutated = []
        for statement in statements {
            visit(statement)
        }
        return (referencedOrder, mutated)
    }

    private func recordReference(_ symbol: Symbol.Symbol?) {
        guard let symbol, !excluding.contains(symbol.id), !referencedSet.contains(symbol.id) else {
            return
        }
        referencedSet.insert(symbol.id)
        referencedOrder.append(symbol.id)
    }

    private func recordMutation(_ symbol: Symbol.Symbol?) {
        recordReference(symbol)
        guard let symbol else { return }
        mutated.insert(symbol.id)
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        recordReference(variable.symbol)
        return super.visitVariable(variable, additional: additional)
    }

    @discardableResult
    public override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        recordReference(selfExpression.symbol)
        return super.visitSelfExpression(selfExpression, additional: additional)
    }

    @discardableResult
    public override func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        recordReference(memberAccess.symbol)
        return super.visitMemberAccess(memberAccess, additional: additional)
    }

    @discardableResult
    public override func visitSubscript(
        _ subscriptExpression: AST.Subscript, additional: Any? = nil
    ) -> Any? {
        recordReference(subscriptExpression.symbol)
        return super.visitSubscript(subscriptExpression, additional: additional)
    }

    @discardableResult
    public override func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        recordReference(implicitMemberAccess.symbol)
        return super.visitImplicitMemberAccess(implicitMemberAccess, additional: additional)
    }

    @discardableResult
    public override func visitBinary(_ binary: AST.Binary, additional: Any? = nil) -> Any? {
        if binary.isAssignment {
            markAssignmentTarget(binary.left)
        }
        return super.visitBinary(binary, additional: additional)
    }

    private func markAssignmentTarget(_ expression: AST.Expression) {
        switch expression {
        case let variable as AST.Variable:
            recordMutation(variable.symbol)
        case let member as AST.MemberAccess:
            markAssignmentTarget(member.object)
        case let subscriptExpr as AST.Subscript:
            markAssignmentTarget(subscriptExpr.base)
        case let deref as AST.Dereference:
            markAssignmentTarget(deref.expression)
        case let parenthetical as AST.Parenthetical:
            markAssignmentTarget(parenthetical.inner)
        case let tuple as AST.Tuple:
            for element in tuple.elements {
                markAssignmentTarget(element.value)
            }
        default:
            visitExpressionTargets(expression)
        }
    }

    private func visitExpressionTargets(_ expression: AST.Expression) {
        let scanner = ClosureCaptureScanner()
        _ = scanner.scan(statements: [AST.ExpressionStatement(expression)], excluding: excluding)
        mutated.formUnion(scanner.mutated)
        for id in scanner.referencedOrder {
            if !referencedSet.contains(id) {
                referencedSet.insert(id)
                referencedOrder.append(id)
            }
        }
    }
}
