import SwiftBetterDiagnostic
import TrussCore

public final class TypeChecker: AST.Visitor {
    private let context: Context
    private var collectingTypealiases = false
    private var collectFunctionSignatures = false
    private var collectingSignatures = false
    private var typealiasDecls: [Id.SymbolId: AST.TypeAliasDecl] = [:]
    private var resolvingTypealiases: Set<Id.SymbolId> = []
    private var scopeStack: [Scope] = []
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    private var functionReturnTypes: [TrussType.TrussType] = []
    private var functionThrowsStack: [(isThrowing: Bool, types: [TrussType.TrussType])] = []
    private var tryContextDepth = 0
    private var doThrownTypeStack: [[TrussType.TrussType]] = []
    private var constraintFrames: [[Id.TypeVariableId: [TrussType.ProtocolType]]] = []
    private var closureParameterTypes: [[TrussType.TrussType]] = []
    private var rawTypeStack: [TrussType.TrussType?] = []
    private var nextTypeVariableId: UInt64 = 0
    private var sourceId: Id.SourceId = .init(0)
    private var nullablePointerConstraints: Set<ObjectIdentifier> = []
    private var narrowedPointerTypes: [Id.SymbolId: TrussType.PointerType] = [:]
    private var nullptrLiteralTokens: [ObjectIdentifier: Token] = [:]
    private var reportedNullptrBindings: Set<ObjectIdentifier> = []

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        checkProgram(program, collectingTypealiases: true)
        checkProgram(program, collectingSignatures: true)
        checkProgram(program, collectFunctionSignatures: true)
        checkProgram(program)
        return nil
    }

    public func checkAll(_ programs: [AST.Program]) {
        for program in programs {
            checkProgram(program, collectingTypealiases: true)
            if context.diagnositicEngine.hasErrors { return }
        }
        for program in programs {
            checkProgram(program, collectingSignatures: true)
            if context.diagnositicEngine.hasErrors { return }
        }
        for program in programs {
            checkProgram(program, collectFunctionSignatures: true)
            if context.diagnositicEngine.hasErrors { return }
        }
        for program in programs {
            checkProgram(program)
            if context.diagnositicEngine.hasErrors { return }
        }
    }

    private func checkProgram(
        _ program: AST.Program, collectingTypealiases: Bool = false,
        collectFunctionSignatures: Bool = false, collectingSignatures: Bool = false
    ) {
        sourceId = program.id
        self.collectingTypealiases = collectingTypealiases
        self.collectFunctionSignatures = collectFunctionSignatures
        self.collectingSignatures = collectingSignatures
        withScope(program.packageSymbol?.scope) {
            super.visitProgram(program, additional: nil)
        }
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        withScope(moduleDecl.symbol?.scope) {
            super.visitModuleDecl(moduleDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(
        _ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = typeAliasDecl.symbol else { return nil }
        if collectingTypealiases {
            typealiasDecls[symbol.id] = typeAliasDecl
            return nil
        }
        symbol.targetType = evaluate(typeAliasDecl.typeExpression)
        return super.visitTypeAliasDecl(typeAliasDecl, additional: additional)
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        withTypeContext(structDecl.symbol) {
            collectConstraints(
                in: structDecl.symbol?.scope, genericDecl: structDecl.genericDecl,
                whereClause: structDecl.whereClause
            )
            super.visitStructDecl(structDecl, additional: additional)
            if let symbol = structDecl.symbol {
                checkWitnesses(of: symbol, at: structDecl.token)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        withTypeContext(classDecl.symbol) {
            collectConstraints(
                in: classDecl.symbol?.scope, genericDecl: classDecl.genericDecl,
                whereClause: classDecl.whereClause
            )
            super.visitClassDecl(classDecl, additional: additional)
            if let symbol = classDecl.symbol {
                checkWitnesses(of: symbol, at: classDecl.token)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        withTypeContext(enumDecl.symbol) {
            collectConstraints(
                in: enumDecl.symbol?.scope, genericDecl: enumDecl.genericDecl,
                whereClause: enumDecl.whereClause
            )
            let rawType = rawType(of: enumDecl)
            rawTypeStack.append(rawType)
            super.visitEnumDecl(enumDecl, additional: additional)
            rawTypeStack.removeLast()
            if let symbol = enumDecl.symbol {
                checkWitnesses(of: symbol, at: enumDecl.token)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(
        _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
    ) -> Any? {
        withTypeContext(protocolDecl.symbol) {
            super.visitProtocolDecl(protocolDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        withTypeContext(actorDecl.symbol) {
            collectConstraints(
                in: actorDecl.symbol?.scope, genericDecl: actorDecl.genericDecl,
                whereClause: actorDecl.whereClause
            )
            super.visitActorDecl(actorDecl, additional: additional)
            if let symbol = actorDecl.symbol {
                checkWitnesses(of: symbol, at: actorDecl.token)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(
        _ extensionDecl: AST.ExtensionDecl, additional: Any? = nil
    ) -> Any? {
        let base = resolvedSymbol(extensionDecl.base) as? Symbol.NominalTypeSymbol
        withTypeContext(base) {
            super.visitExtensionDecl(extensionDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitEnumCaseDecl(
        _ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil
    ) -> Any? {
        for (index, element) in enumCaseDecl.elements.enumerated() {
            guard index < enumCaseDecl.symbols.count else { break }
            let symbol = enumCaseDecl.symbols[index]
            symbol.associatedLabels = element.associatedValues.map { $0.label?.value }
            symbol.associatedTypes = element.associatedValues.map { evaluate($0.typeExpression) }
            if let rawValue = element.rawValue {
                guard let rawType = rawTypeStack.last ?? nil else {
                    context.emitError(
                        "raw value requires a raw type", at: element.name
                    )
                    continue
                }
                let rawValueType = infer(rawValue, at: element.name)
                if let rawValueType, !canCoerce(rawValueType, to: rawType, at: element.name) {
                    emitMismatch(at: element.name, expected: rawType, found: rawValueType)
                }
            }
        }
        return super.visitEnumCaseDecl(enumCaseDecl, additional: additional)
    }

    private func fillFunctionSignature(
        parameters: [AST.FunctionDecl.Parameter], varargToken: Token?, asyncToken: Token?,
        throwsClause: AST.ThrowsClause?, returnType: TrussType.TrussType,
        genericDecl: AST.GenericDecl?, symbol: Symbol.FunctionSymbol
    ) {
        let parameterTypes = fillParameterTypes(parameters, into: symbol)
        let functionType = functionType(
            labels: parameters.map { $0.label?.value },
            parameterTypes: parameterTypes,
            varargToken: varargToken,
            asyncToken: asyncToken,
            throwsClause: throwsClause,
            returnType: returnType
        )
        if let genericDecl, !genericDecl.generics.isEmpty {
            symbol.forallType = TrussType.ForallType(
                parameters: genericParams(of: genericDecl), body: functionType
            )
        }
        symbol.functionType = functionType
    }

    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = functionDecl.symbol else { return nil }
        if collectingTypealiases {
            return nil
        }
        if collectFunctionSignatures || collectingSignatures {
            withScope(symbol.scope) {
                collectConstraints(
                    in: symbol.scope, genericDecl: functionDecl.genericDecl, whereClause: nil
                )
                let returnType: TrussType.TrussType =
                    if let typeExpression = functionDecl.returnTypeExpression {
                        evaluate(typeExpression)
                    } else {
                        TrussType.VoidType.INSTANCE
                    }
                fillFunctionSignature(
                    parameters: functionDecl.parameters, varargToken: functionDecl.varargToken,
                    asyncToken: functionDecl.asyncToken, throwsClause: functionDecl.throwsClause,
                    returnType: returnType, genericDecl: functionDecl.genericDecl, symbol: symbol
                )
            }
            return nil
        }
        withScope(symbol.scope) {
            collectConstraints(
                in: symbol.scope, genericDecl: functionDecl.genericDecl, whereClause: nil
            )
            let parameterTypes = fillParameterTypes(functionDecl.parameters, into: symbol)
            let returnType: TrussType.TrussType =
                if let typeExpression = functionDecl.returnTypeExpression {
                    evaluate(typeExpression)
                } else {
                    TrussType.VoidType.INSTANCE
                }
            let functionType = functionType(
                labels: functionDecl.parameters.map { $0.label?.value },
                parameterTypes: parameterTypes,
                varargToken: functionDecl.varargToken,
                asyncToken: functionDecl.asyncToken,
                throwsClause: functionDecl.throwsClause,
                returnType: returnType
            )
            if let genericDecl = functionDecl.genericDecl, !genericDecl.generics.isEmpty {
                symbol.forallType = TrussType.ForallType(
                    parameters: genericParams(of: genericDecl), body: functionType
                )
                symbol.functionType = functionType
            } else {
                symbol.functionType = functionType
            }
            withFunctionReturnType(returnType) {
                withFunctionThrows(functionDecl.throwsClause != nil, functionType.throwsTypes) {
                    visitFunctionBody(
                        functionDecl.body, expectedReturn: returnType, at: functionDecl.name
                    )
                }
            }
        }
        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = initDecl.symbol else {
            return super.visitInitDecl(initDecl, additional: additional)
        }
        if collectingTypealiases {
            return nil
        }
        if collectFunctionSignatures || collectingSignatures {
            withScope(symbol.scope) {
                collectConstraints(
                    in: symbol.scope, genericDecl: initDecl.genericDecl, whereClause: nil
                )
                fillFunctionSignature(
                    parameters: initDecl.parameters,
                    varargToken: nil,
                    asyncToken: initDecl.asyncToken,
                    throwsClause: initDecl.throwsClause,
                    returnType: TrussType.VoidType.INSTANCE,
                    genericDecl: initDecl.genericDecl, symbol: symbol
                )
            }
            return nil
        }
        withScope(symbol.scope) {
            collectConstraints(
                in: symbol.scope, genericDecl: initDecl.genericDecl, whereClause: nil
            )
            let parameterTypes = fillParameterTypes(initDecl.parameters, into: symbol)
            let functionType = functionType(
                labels: initDecl.parameters.map { $0.label?.value },
                parameterTypes: parameterTypes,
                varargToken: nil,
                asyncToken: initDecl.asyncToken,
                throwsClause: initDecl.throwsClause,
                returnType: TrussType.VoidType.INSTANCE
            )
            if let genericDecl = initDecl.genericDecl, !genericDecl.generics.isEmpty {
                symbol.forallType = TrussType.ForallType(
                    parameters: genericParams(of: genericDecl), body: functionType
                )
            }
            symbol.functionType = functionType
            withFunctionReturnType(TrussType.VoidType.INSTANCE) {
                withFunctionThrows(initDecl.throwsClause != nil, functionType.throwsTypes) {
                    visitFunctionBody(
                        .Block(initDecl.body), expectedReturn: nil, at: initDecl.token
                    )
                }
            }
        }
        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = subscriptDecl.symbol else {
            return super.visitSubscriptDecl(subscriptDecl, additional: additional)
        }
        if collectingTypealiases {
            return nil
        }
        if collectFunctionSignatures || collectingSignatures {
            withScope(symbol.scope) {
                fillFunctionSignature(
                    parameters: subscriptDecl.parameters,
                    varargToken: nil,
                    asyncToken: subscriptDecl.asyncToken,
                    throwsClause: subscriptDecl.throwsClause,
                    returnType: evaluate(subscriptDecl.returnType),
                    genericDecl: subscriptDecl.genericDecl, symbol: symbol
                )
            }
            return nil
        }
        withScope(symbol.scope) {
            let parameterTypes = fillParameterTypes(subscriptDecl.parameters, into: symbol)
            let returnType: TrussType.TrussType = evaluate(subscriptDecl.returnType)
            let functionType = functionType(
                labels: subscriptDecl.parameters.map { $0.label?.value },
                parameterTypes: parameterTypes,
                varargToken: nil,
                asyncToken: subscriptDecl.asyncToken,
                throwsClause: subscriptDecl.throwsClause,
                returnType: returnType
            )
            symbol.functionType = functionType
            if subscriptDecl.accessors.contains(where: { $0.kind == .Set }) {
                let setterFunctionType = TrussType.FunctionType(
                    parameters: (subscriptDecl.parameters.map { $0.label?.value } + [nil])
                        .enumerated()
                        .map { index, label in
                            TrussType.FunctionType.Parameter(
                                label: label, type: index < parameterTypes.count
                                    ? parameterTypes[index]
                                    : returnType
                            )
                        },
                    isVariadic: false,
                    isAsync: subscriptDecl.asyncToken != nil,
                    isThrowing: subscriptDecl.throwsClause != nil,
                    throwsTypes: (subscriptDecl.throwsClause?.types ?? []).map(evaluate),
                    returnType: TrussType.VoidType.INSTANCE
                )
                symbol.setterType =
                    if let forallType = symbol.forallType {
                        TrussType.ForallType(parameters: forallType.parameters, body: setterFunctionType)
                    } else {
                        setterFunctionType
                    }
            }
            withFunctionReturnType(returnType) {
                withFunctionThrows(subscriptDecl.throwsClause != nil, functionType.throwsTypes) {
                    for accessor in subscriptDecl.accessors {
                        checkAccessor(accessor, returnType, at: subscriptDecl.token)
                    }
                }
            }
        }
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil)
        -> Any?
    {
        withScope(deinitDecl.scope) {
            super.visitDeinitDecl(deinitDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        if collectingTypealiases {
            if let typeExpression = variableDecl.typeExpression {
                variableDecl.symbol?.type = evaluate(typeExpression)
            }
            return nil
        }
        if collectFunctionSignatures || collectingSignatures {
            if let typeExpression = variableDecl.typeExpression {
                variableDecl.symbol?.type = evaluate(typeExpression)
            } else if !collectingSignatures, let initializer = variableDecl.initializer {
                let inferred = infer(initializer, at: variableDecl.name)
                if let inferred, isResolved(inferred) {
                    variableDecl.symbol?.type = inferred
                }
            }
            return nil
        }
        let type: TrussType.TrussType? =
            if let typeExpr = variableDecl.typeExpression {
                evaluate(typeExpr)
            } else {
                nil
            }
        if let type {
            variableDecl.symbol?.type = type
            if variableDecl.initializer == nil, !functionReturnTypes.isEmpty,
               variableDecl.token.value == "let"
            {
                context.emitError(
                    "missing initializer in let declaration", at: variableDecl.name
                )
            }
            if let initializer = variableDecl.initializer {
                check(initializer, type, at: variableDecl.name)
                if let variable = type as? TrussType.TypeVariableType {
                    checkConstraints(for: variable, at: variableDecl.name)
                }
            }
            for accessor in variableDecl.accessors {
                checkAccessor(accessor, type, at: variableDecl.name)
            }
        } else if let initializer = variableDecl.initializer {
            let inferred = infer(initializer, at: variableDecl.name)
            variableDecl.symbol?.type = inferred
            for accessor in variableDecl.accessors {
                if let inferred {
                    checkAccessor(accessor, inferred, at: variableDecl.name)
                } else {
                    visitAccessorStatements(accessor, at: variableDecl.name)
                }
            }
        } else {
            for accessor in variableDecl.accessors {
                visitAccessorStatements(accessor, at: variableDecl.name)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
    ) -> Any? {
        _ = infer(
            expressionStatement.expression, at: syntheticToken(for: expressionStatement.expression)
        )
        return nil
    }

    @discardableResult
    public override func visitReturn(_ returnStatement: AST.Return, additional: Any? = nil)
        -> Any?
    {
        guard let value = returnStatement.value else { return nil }
        if let expected = functionReturnTypes.last {
            check(value, expected, at: returnStatement.token)
        } else {
            _ = infer(value, at: returnStatement.token)
        }
        return nil
    }

    @discardableResult
    public override func visitThrow(_ throwStatement: AST.Throw, additional: Any? = nil)
        -> Any?
    {
        let thrownType = infer(throwStatement.expression, at: throwStatement.token)
        if let thrownType, !doThrownTypeStack.isEmpty {
            doThrownTypeStack[doThrownTypeStack.count - 1].append(thrownType)
        }
        if let throwsContext = functionThrowsStack.last {
            if !throwsContext.isThrowing {
                context.emitError(
                    "throwing statement in non-throwing function", at: throwStatement.token
                )
            } else if let thrownType, !throwsContext.types.isEmpty,
                      !throwsContext.types.contains(where: {
                          canCoerce(thrownType, to: $0, at: throwStatement.token)
                      })
            {
                emitMismatch(
                    at: throwStatement.token, expected: throwsContext.types.first,
                    found: thrownType
                )
            }
        }
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil)
        -> Any?
    {
        withScope(whileStatement.scope) {
            checkBoolCondition(whileStatement.condition, at: whileStatement.token)
            super.visitWhile(whileStatement, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitGuard(_ guardStatement: AST.Guard, additional: Any? = nil)
        -> Any?
    {
        checkBoolCondition(guardStatement.condition, at: guardStatement.token)
        for statement in guardStatement.body {
            visit(statement)
        }
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        withScope(repeatWhile.scope) {
            checkBoolCondition(repeatWhile.condition, at: repeatWhile.token)
            super.visitRepeatWhile(repeatWhile, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
        withScope(forStatement.scope) {
            let sequenceType = infer(forStatement.sequence, at: forStatement.token)
            checkPattern(forStatement.pattern, against: sequenceType, at: forStatement.token)
            if let whereClause = forStatement.whereClause {
                _ = infer(whereClause, at: forStatement.token)
            }
            for statement in forStatement.body {
                visit(statement)
            }
        }
        return nil
    }

    private func precollectLocalVariableTypes(_ statements: [AST.Statement]) {
        for statement in statements {
            guard let variableDecl = statement as? AST.VariableDecl else { continue }
            let symbol = variableDecl.symbol
            guard symbol?.type == nil else { continue }
            if let typeExpression = variableDecl.typeExpression {
                symbol?.type = evaluate(typeExpression)
            } else if let initializer = variableDecl.initializer {
                let inferred = infer(initializer, at: variableDecl.name)
                if let inferred, isResolved(inferred) {
                    symbol?.type = inferred
                }
            }
        }
    }

    private func visitFunctionBody(
        _ body: AST.FunctionDecl.Body?, expectedReturn: TrussType.TrussType?, at token: Token
    ) {
        guard let body else { return }
        switch body {
        case let .Block(statements):
            precollectLocalVariableTypes(statements)
            for statement in statements {
                visit(statement)
            }
            if let expectedReturn, !(expectedReturn is TrussType.VoidType),
               let last = statements.last as? AST.ExpressionStatement
            {
                check(last.expression, expectedReturn, at: token)
            }
        case let .Expression(expression):
            if let expectedReturn {
                check(expression, expectedReturn, at: token)
            } else {
                _ = infer(expression, at: token)
            }
        }
    }

    private func checkAccessor(
        _ accessor: AST.Accessor, _ type: TrussType.TrussType, at token: Token
    ) {
        withScope(accessor.scope) {
            if let parameterName = accessor.parameterName {
                if let variable =
                    accessor.scope?.values[parameterName.value]?.first
                        as? Symbol.VariableSymbol
                {
                    variable.type = type
                }
            }
            switch accessor.kind {
            case .Get:
                withFunctionReturnType(type) {
                    switch accessor.body {
                    case let .Block(statements):
                        for statement in statements {
                            visit(statement)
                        }
                        if let last = statements.last as? AST.ExpressionStatement {
                            check(last.expression, type, at: accessor.token ?? token)
                        } else if !(statements.last is AST.Return),
                                  !(statements.last is AST.Throw),
                                  join([TrussType.VoidType.INSTANCE, type], at: token) == nil
                        {
                            emitMismatch(
                                at: token, expected: type, found: TrussType.VoidType.INSTANCE
                            )
                        }
                    case let .Expression(expression):
                        check(expression, type, at: accessor.token ?? token)
                    }
                }
            case .Set, .WillSet, .DidSet:
                visitAccessorStatements(accessor, at: token)
            }
        }
    }

    private func visitAccessorStatements(_ accessor: AST.Accessor, at token: Token) {
        withScope(accessor.scope) {
            switch accessor.body {
            case let .Block(statements):
                for statement in statements {
                    visit(statement)
                }
            case let .Expression(expression):
                _ = infer(expression, at: token)
            }
        }
    }

    private func fillParameterTypes(
        _ parameters: [AST.FunctionDecl.Parameter], into symbol: Symbol.FunctionSymbol
    ) -> [TrussType.TrussType] {
        var types: [TrussType.TrussType] = []
        for parameter in parameters {
            let type: TrussType.TrussType =
                if let ty = parameter.type {
                    evaluate(ty)
                } else {
                    TrussType.ErrorType.INSTANCE
                }
            let variable =
                symbol.scope.values[parameter.name.value]?.first
                    as? Symbol.VariableSymbol
            variable?.type = type
            types.append(type)
            if let defaultValue = parameter.defaultValue {
                check(defaultValue, type, at: parameter.name)
            }
        }
        return types
    }

    private func rawType(of enumDecl: AST.EnumDecl) -> TrussType.TrussType? {
        for expression in enumDecl.conformances {
            let type = evaluate(expression)
            if type is TrussType.ErrorType {
                continue
            }
            if let composition = type as? TrussType.CompositionType {
                for member in composition.members {
                    if !(member is TrussType.ProtocolType) {
                        return member
                    }
                }
                continue
            }
            if type is TrussType.ProtocolType {
                continue
            }
            return type
        }
        return nil
    }

    private func genericParams(of genericDecl: AST.GenericDecl) -> [Symbol.GenericParamSymbol] {
        var params: [Symbol.GenericParamSymbol] = []
        for generic in genericDecl.generics {
            if let symbol = scopeStack.last?.types[generic.name.value]
                as? Symbol.GenericParamSymbol
            {
                params.append(symbol)
            }
        }
        return params
    }

    private func collectConstraints(
        in scope: Scope?,
        genericDecl: AST.GenericDecl?,
        whereClause: [AST.WhereRequirement]?
    ) {
        guard let scope, let genericDecl else { return }
        for generic in genericDecl.generics {
            guard let symbol = scope.types[generic.name.value]
                as? Symbol.GenericParamSymbol
            else {
                continue
            }
            if let constraint = generic.constraint {
                let type = evaluate(constraint)
                if !(type is TrussType.ErrorType) {
                    symbol.constraints.append(
                        Symbol.GenericParamSymbol.Constraint.conformance(type)
                    )
                }
            }
        }
        for requirement in whereClause ?? [] {
            guard let variable = requirement.left as? AST.Variable,
                  let symbol = scope.types[variable.name.value]
                  as? Symbol.GenericParamSymbol
            else {
                continue
            }
            switch requirement.constraint {
            case let .conformance(expression):
                let type = evaluate(expression)
                if !(type is TrussType.ErrorType) {
                    symbol.constraints.append(
                        Symbol.GenericParamSymbol.Constraint.conformance(type)
                    )
                }
            case let .equality(expression):
                let type = evaluate(expression)
                if !(type is TrussType.ErrorType) {
                    symbol.constraints.append(
                        Symbol.GenericParamSymbol.Constraint.equality(type)
                    )
                }
            }
        }
    }

    private func functionType(
        labels: [String?],
        parameterTypes: [TrussType.TrussType],
        varargToken: Token?,
        asyncToken: Token?,
        throwsClause: AST.ThrowsClause?,
        returnType: TrussType.TrussType
    ) -> TrussType.FunctionType {
        TrussType.FunctionType(
            parameters: zip(labels, parameterTypes).map { label, type in
                TrussType.FunctionType.Parameter(label: label, type: type)
            },
            isVariadic: varargToken != nil,
            isAsync: asyncToken != nil,
            isThrowing: throwsClause != nil,
            throwsTypes: (throwsClause?.types ?? []).map(evaluate),
            returnType: returnType
        )
    }

    private func evaluate(_ expression: AST.Expression) -> TrussType.TrussType {
        let result: TrussType.TrussType
        switch expression {
        case let variable as AST.Variable:
            if let evaluated = evaluateVariable(variable) {
                result = evaluated
            } else {
                context.emitError("cannot find type '\(variable.name.value)'", at: variable.name)
                result = TrussType.ErrorType.INSTANCE
            }
        case let member as AST.MemberAccess:
            if let symbol = member.symbol, let evaluated = evaluateSymbol(symbol) {
                result = evaluated
            } else {
                context.emitError("cannot find type '\(member.member.value)'", at: member.member)
                result = TrussType.ErrorType.INSTANCE
            }
        case let parenthetical as AST.Parenthetical:
            result = evaluate(parenthetical.inner)
        case let optionalType as AST.OptionalType:
            let wrapped = evaluate(optionalType.wrappedType)
            result =
                wrapped is TrussType.ErrorType
                    ? TrussType.ErrorType.INSTANCE : TrussType.OptionalType(wrapped)
        case let pointerType as AST.PointerType:
            let pointee = evaluate(pointerType.wrappedType)
            result =
                pointee is TrussType.ErrorType
                    ? TrussType.ErrorType.INSTANCE
                    : TrussType.PointerType(pointee, isNonnull: pointerType.isNonnull)
        case let variadicType as AST.VariadicType:
            let base = evaluate(variadicType.base)
            result =
                base is TrussType.ErrorType
                    ? TrussType.ErrorType.INSTANCE : TrussType.VariadicType(base)
        case let closureType as AST.ClosureType:
            var parameters: [TrussType.TrussType] = []
            var failed = false
            for parameter in closureType.parameters {
                let type = evaluate(parameter.type)
                if type is TrussType.ErrorType {
                    failed = true
                    break
                }
                parameters.append(type)
            }
            let returnType = evaluate(closureType.returnType)
            if failed || returnType is TrussType.ErrorType {
                result = TrussType.ErrorType.INSTANCE
            } else {
                result = functionType(
                    labels: closureType.parameters.map { $0.label?.value },
                    parameterTypes: parameters,
                    varargToken: nil,
                    asyncToken: closureType.asyncToken,
                    throwsClause: closureType.throwsClause,
                    returnType: returnType
                )
            }
        case let tupleExpression as AST.Tuple:
            var elements: [TrussType.TupleType.Element] = []
            var failed = false
            for argument in tupleExpression.elements {
                let type = evaluate(argument.value)
                if type is TrussType.ErrorType {
                    failed = true
                    break
                }
                elements.append(
                    TrussType.TupleType.Element(label: argument.label?.value, type: type)
                )
            }
            result = failed ? TrussType.ErrorType.INSTANCE : TrussType.TupleType(elements)
        case let composition as AST.ProtocolCompositionType:
            var members: [TrussType.TrussType] = []
            var failed = false
            for type in composition.types {
                let member = evaluate(type)
                if member is TrussType.ErrorType {
                    failed = true
                    break
                }
                members.append(member)
            }
            result = failed ? TrussType.ErrorType.INSTANCE : TrussType.CompositionType(members)
        case let composition as AST.ProtocolCompositionType:
            var members: [TrussType.TrussType] = []
            var failed = false
            for type in composition.types {
                let member = evaluate(type)
                if member is TrussType.ErrorType {
                    failed = true
                    break
                }
                members.append(member)
            }
            result = failed ? TrussType.ErrorType.INSTANCE : TrussType.CompositionType(members)
        case let genericApplication as AST.GenericApplication:
            result = evaluateGenericApplication(genericApplication)
        case let sequential as AST.Sequential
            where sequential.ops.allSatisfy({ op in
                if case .Operator(.BitAnd) = op.kind { return true }
                return false
            }):
            var members: [TrussType.TrussType] = []
            var failed = false
            for operand in sequential.operands {
                let member = evaluate(operand)
                if member is TrussType.ErrorType {
                    failed = true
                    break
                }
                members.append(member)
            }
            result = failed ? TrussType.ErrorType.INSTANCE : TrussType.CompositionType(members)
        case let anyType as AST.AnyType:
            let wrapped = evaluate(anyType.wrappedType)
            result =
                wrapped is TrussType.ErrorType ? TrussType.ErrorType.INSTANCE : wrapped
        case let someType as AST.SomeType:
            result = evaluateOpaque(someType)
        case is AST.VoidLiteral:
            result = TrussType.VoidType.INSTANCE
        default:
            result = TrussType.ErrorType.INSTANCE
        }
        expression.ty = result
        return result
    }

    private func evaluateOpaque(_ someType: AST.SomeType) -> TrussType.TrussType {
        let inner = evaluate(someType.wrappedType)
        if inner is TrussType.ErrorType {
            return TrussType.ErrorType.INSTANCE
        }
        let variable = freshTypeVariable()
        for member in compositionMembers(inner) {
            if let protocolType = member as? TrussType.ProtocolType {
                addConstraint(variable, protocolType)
            }
        }
        return variable
    }

    private func compositionMembers(_ type: TrussType.TrussType) -> [TrussType.TrussType] {
        if let composition = type as? TrussType.CompositionType {
            return composition.members
        }
        return [type]
    }

    private func evaluateVariable(_ variable: AST.Variable) -> TrussType.TrussType? {
        if let symbol = variable.symbol {
            return evaluateSymbol(symbol)
        }
        switch variable.name.value {
        case "Void": return TrussType.VoidType.INSTANCE
        case "Never": return TrussType.NeverType.INSTANCE
        default: return nil
        }
    }

    private func stdType(named name: String) -> TrussType.TrussType? {
        guard let package = context.name2Package[Builtin.packageName],
              let symbol = package.scope.types[name]
        else {
            return nil
        }
        return evaluateSymbol(symbol)
    }

    private func checkBoolCondition(_ condition: AST.Expression, at token: Token) {
        let unwrapped = unwrapParentheses(condition)
        if let binding = unwrapped as? AST.OptionalBinding {
            bindOptionalBindingVariable(binding, at: token)
            _ = infer(binding, at: token)
            return
        }
        if let boolType = stdType(named: "Bool") {
            check(condition, boolType, at: token)
        } else {
            _ = infer(condition, at: token)
        }
    }

    private func unwrapParentheses(_ expression: AST.Expression) -> AST.Expression {
        if let parenthetical = expression as? AST.Parenthetical {
            return unwrapParentheses(parenthetical.inner)
        }
        return expression
    }

    private func bindOptionalBindingVariable(
        _ optionalBinding: AST.OptionalBinding, at token: Token
    ) {
        guard let valueType = infer(optionalBinding.value, at: token),
              let variableSymbol = scopeStack.last?.values[optionalBinding.name.value]?
              .first as? Symbol.VariableSymbol
        else {
            return
        }
        let unwrapped = (valueType as? TrussType.OptionalType)?.wrapped ?? valueType
        if let existing = variableSymbol.type {
            _ = unify(existing, unwrapped, at: token)
        } else {
            variableSymbol.type = unwrapped
        }
    }

    private func evaluateSymbol(_ symbol: Symbol.Symbol) -> TrussType.TrussType? {
        if let nominal = symbol as? Symbol.NominalTypeSymbol {
            return nominal.typeId.flatMap { context.typeTable[$0] }
        }
        if let builtin = symbol as? Symbol.BuiltinTypeSymbol {
            return TrussType.BuiltinType(builtin.name)
        }
        if let typeAlias = symbol as? Symbol.TypeAliasSymbol {
            return resolveTypealias(typeAlias)
        }
        if let genericParam = symbol as? Symbol.GenericParamSymbol {
            return TrussType.GenericParamType(genericParam.name, genericParam)
        }
        return nil
    }

    private func evaluateGenericApplication(
        _ genericApplication: AST.GenericApplication
    ) -> TrussType.TrussType {
        guard let base = evaluate(genericApplication.base) as? TrussType.NominalType else {
            return TrussType.ErrorType.INSTANCE
        }
        var arguments: [TrussType.TrussType] = []
        for argument in genericApplication.genericArguments {
            let resolved = evaluate(argument)
            if resolved is TrussType.ErrorType {
                return TrussType.ErrorType.INSTANCE
            }
            arguments.append(resolved)
        }
        let result = TrussType.GenericInstantiation(base: base, arguments: arguments)
        checkGenericArguments(
            of: base, arguments: arguments,
            at: syntheticToken(for: genericApplication)
        )
        return result
    }

    private func resolveTypealias(_ symbol: Symbol.TypeAliasSymbol) -> TrussType.TrussType {
        if let target = symbol.targetType { return target }
        if resolvingTypealiases.contains(symbol.id) {
            if let token = symbol.sourceToken {
                context.emitError(
                    "circular reference to typealias '\(symbol.name)'", at: token
                )
            }
            return TrussType.ErrorType.INSTANCE
        }
        guard let decl = typealiasDecls[symbol.id] else {
            return TrussType.ErrorType.INSTANCE
        }
        resolvingTypealiases.insert(symbol.id)
        defer { resolvingTypealiases.remove(symbol.id) }
        symbol.targetType = evaluate(decl.typeExpression)
        return symbol.targetType ?? TrussType.ErrorType.INSTANCE
    }

    private func resolvedSymbol(_ expression: AST.Expression) -> Symbol.Symbol? {
        if let variable = expression as? AST.Variable {
            return variable.symbol
        }
        if let member = expression as? AST.MemberAccess {
            return member.symbol
        }
        if let selfExpression = expression as? AST.SelfExpression {
            return selfExpression.symbol
        }
        if let superExpression = expression as? AST.SuperExpression {
            return superExpression.symbol
        }
        if let generic = expression as? AST.GenericApplication {
            return resolvedSymbol(generic.base)
        }
        if let sequential = expression as? AST.Sequential,
           sequential.genericApplicationGroupCloseIndex() != nil,
           let base = sequential.operands.first
        {
            return resolvedSymbol(base)
        }
        return nil
    }

    private func baseName(of expression: AST.Expression) -> String? {
        if let variable = expression as? AST.Variable {
            return variable.name.value
        }
        if let member = expression as? AST.MemberAccess {
            return member.member.value
        }
        if let generic = expression as? AST.GenericApplication {
            return baseName(of: generic.base)
        }
        if let sequential = expression as? AST.Sequential,
           sequential.genericApplicationGroupCloseIndex() != nil,
           let base = sequential.operands.first
        {
            return baseName(of: base)
        }
        return nil
    }

    private func withScope(_ scope: Scope?, _ body: () -> Void) {
        guard let scope else {
            body()
            return
        }
        scopeStack.append(scope)
        constraintFrames.append([:])
        body()
        constraintFrames.removeLast()
        scopeStack.removeLast()
    }

    private func withTypeContext(_ symbol: Symbol.NominalTypeSymbol?, _ body: () -> Void) {
        guard let symbol else {
            body()
            return
        }
        typeStack.append(symbol)
        body()
        typeStack.removeLast()
    }

    private func withFunctionReturnType(_ type: TrussType.TrussType, _ body: () -> Void) {
        functionReturnTypes.append(type)
        body()
        functionReturnTypes.removeLast()
    }

    private func withFunctionThrows(
        _ isThrowing: Bool, _ types: [TrussType.TrussType], _ body: () -> Void
    ) {
        functionThrowsStack.append((isThrowing, types))
        body()
        functionThrowsStack.removeLast()
    }

    private func freshTypeVariable(_ name: String? = nil) -> TrussType.TypeVariableType {
        let variable = TrussType.TypeVariableType(Id.TypeVariableId(nextTypeVariableId), name)
        nextTypeVariableId += 1
        return variable
    }

    private func addConstraint(
        _ variable: TrussType.TypeVariableType, _ protocolType: TrussType.ProtocolType
    ) {
        guard !constraintFrames.isEmpty else { return }
        constraintFrames[constraintFrames.count - 1][variable.id, default: []].append(
            protocolType
        )
    }

    private func lookupOperatorFunctions(_ name: String) -> [Symbol.FunctionSymbol] {
        for scope in scopeStack.reversed() {
            if let entries = scope.values[name] {
                return entries.compactMap { $0 as? Symbol.FunctionSymbol }
            }
        }
        return []
    }

    private func memberOperatorCandidates(
        _ name: String, in type: TrussType.TrussType?, isStatic: Bool
    ) -> [Symbol.FunctionSymbol] {
        let base = (type as? TrussType.OptionalType)?.wrapped ?? type
        guard let nominal = base as? TrussType.NominalType, let symbol = nominal.symbol else {
            return []
        }
        var current: Symbol.NominalTypeSymbol? = symbol
        while let currentType = current {
            if let entries = currentType.scope.values[name] {
                let filtered = entries.compactMap { $0 as? Symbol.FunctionSymbol }
                    .filter { $0.isStatic == isStatic }
                if !filtered.isEmpty {
                    return filtered
                }
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return []
    }

    private func resolveSubscriptAssignment(
        _ subscriptExpression: AST.Subscript, rhs: AST.Expression, at token: Token
    ) {
        _ = infer(subscriptExpression.base, at: token)
        for argument in subscriptExpression.arguments {
            _ = infer(argument.value, at: token)
        }
        _ = infer(rhs, at: token)
        if let pointer = subscriptExpression.base.ty.flatMap({
            resolve($0) as? TrussType.PointerType
        }), subscriptExpression.arguments.count == 1 {
            subscriptExpression.ty = pointer.pointee
            return
        }
        var candidates = subscriptExpression.overloads ?? []
        let baseType: TrussType.TrussType? = subscriptExpression.base.ty
        if candidates.isEmpty, baseType != nil {
            candidates = memberFunctionSymbols(of: "subscript", in: baseType)
        }
        if candidates.isEmpty {
            emitNoExactMatch(at: token, name: "subscript", candidates: [])
            return
        }
        let setterCandidates = candidates.filter { $0.setterType != nil }
        guard !setterCandidates.isEmpty else {
            context.emitError("cannot assign to subscript: is read-only", at: token)
            return
        }
        var arguments = subscriptExpression.arguments
        arguments.append(
            AST.LabeledArgument(label: nil, value: rhs, sourceRange: rhs.sourceRange)
        )
        if let resolved = resolveOverloads(
            setterCandidates, arguments: arguments, trailingClosures: [],
            expectedReturn: nil, at: token, fallbackName: "subscript", setterContext: true
        ) {
            subscriptExpression.symbol = resolved.symbol
            subscriptExpression.ty = returnType(of: resolved.symbol)
        }
    }

    private func memberFunctionSymbols(
        of name: String, in type: TrussType.TrussType?
    ) -> [Symbol.FunctionSymbol] {
        let base = (type as? TrussType.OptionalType)?.wrapped ?? type
        if let genericParam = base as? TrussType.GenericParamType {
            guard let symbol = genericParam.symbol else { return [] }
            var result: [Symbol.FunctionSymbol] = []
            for constraint in symbol.constraints {
                guard case let .conformance(declared) = constraint else { continue }
                result.append(contentsOf: memberFunctionSymbols(of: name, in: declared))
            }
            return result
        }
        let nominal: TrussType.NominalType
        if let generic = base as? TrussType.GenericInstantiation {
            nominal = generic.base
        } else if let plain = base as? TrussType.NominalType {
            nominal = plain
        } else {
            return []
        }
        guard let symbol = nominal.symbol else { return [] }
        var result: [Symbol.FunctionSymbol] = []
        var current: Symbol.NominalTypeSymbol? = symbol
        while let currentType = current {
            if let entries = currentType.scope.values[name] {
                result.append(contentsOf: entries.compactMap { $0 as? Symbol.FunctionSymbol })
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return result
    }

    private func memberFunctionSymbols(
        of name: String, in declared: TrussType.TrussType
    ) -> [Symbol.FunctionSymbol] {
        if let composition = declared as? TrussType.CompositionType {
            return composition.members.flatMap { memberFunctionSymbols(of: name, in: $0) }
        }
        if let protocolType = declared as? TrussType.ProtocolType {
            return memberFunctionSymbols(of: name, in: protocolType)
        }
        return []
    }

    private func memberSymbol(of name: String, in type: TrussType.TrussType?) -> Symbol.Symbol? {
        let base = (type as? TrussType.OptionalType)?.wrapped ?? type
        let nominal: TrussType.NominalType
        if let generic = base as? TrussType.GenericInstantiation {
            nominal = generic.base
        } else if let plain = base as? TrussType.NominalType {
            nominal = plain
        } else {
            return nil
        }
        guard let symbol = nominal.symbol else { return nil }
        var current: Symbol.NominalTypeSymbol? = symbol
        while let currentType = current {
            if let typeEntry = currentType.scope.types[name] {
                return typeEntry
            }
            if let entries = currentType.scope.values[name], let first = entries.first {
                return first
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return nil
    }

    private func memberType(of name: String, in type: TrussType.TrussType?) -> TrussType.TrussType? {
        let base = (type as? TrussType.OptionalType)?.wrapped ?? type
        if let genericParam = base as? TrussType.GenericParamType {
            return memberType(of: name, in: genericParam)
        }
        let nominal: TrussType.NominalType
        let genericArguments: [TrussType.TrussType]
        if let generic = base as? TrussType.GenericInstantiation {
            nominal = generic.base
            genericArguments = generic.arguments
        } else if let plain = base as? TrussType.NominalType {
            nominal = plain
            genericArguments = []
        } else {
            return nil
        }
        guard let symbol = nominal.symbol else { return nil }
        var current: Symbol.NominalTypeSymbol? = symbol
        while let currentType = current {
            if let typeSymbol = currentType.scope.types[name] {
                let memberType =
                    (typeSymbol as? Symbol.NominalTypeSymbol)?.typeId
                        .flatMap { context.typeTable[$0] }
                if let memberType {
                    return replaceGenericArguments(memberType, of: symbol, with: genericArguments)
                }
            }
            if let entries = currentType.scope.values[name] {
                if let function = entries.first as? Symbol.FunctionSymbol {
                    return replaceGenericArguments(
                        function.forallType ?? function.functionType ?? TrussType.ErrorType.INSTANCE,
                        of: symbol, with: genericArguments
                    )
                }
                if let variable = entries.first as? Symbol.VariableSymbol {
                    return replaceGenericArguments(
                        variable.type ?? TrussType.ErrorType.INSTANCE,
                        of: symbol, with: genericArguments
                    )
                }
                if let caseSymbol = entries.first as? Symbol.CaseSymbol,
                   let memberOf = caseSymbol.memberOf,
                   let enumSymbol = context.id2Symbol[memberOf] as? Symbol.EnumSymbol,
                   let typeId = enumSymbol.typeId, let enumType = context.typeTable[typeId]
                {
                    return replaceGenericArguments(
                        enumType, of: symbol, with: genericArguments
                    )
                }
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return nil
    }

    private func genericParameterNames(of symbol: Symbol.NominalTypeSymbol) -> [String] {
        symbol.scope.types.values.compactMap { $0 as? Symbol.GenericParamSymbol }.map(\.name)
    }

    private func memberType(
        of name: String, in genericParam: TrussType.GenericParamType
    ) -> TrussType.TrussType? {
        guard let symbol = genericParam.symbol else { return nil }
        for constraint in symbol.constraints {
            guard case let .conformance(declared) = constraint else { continue }
            if let member = memberType(of: name, in: declared) {
                return member
            }
        }
        return nil
    }

    private func memberType(
        of name: String, in declared: TrussType.TrussType
    ) -> TrussType.TrussType? {
        if let composition = declared as? TrussType.CompositionType {
            for member in composition.members {
                if let type = memberType(of: name, in: member) {
                    return type
                }
            }
            return nil
        }
        if let protocolType = declared as? TrussType.ProtocolType {
            return memberType(of: name, in: protocolType)
        }
        return nil
    }

    private func replaceGenericArguments(
        _ type: TrussType.TrussType, of symbol: Symbol.NominalTypeSymbol,
        with arguments: [TrussType.TrussType]
    ) -> TrussType.TrussType {
        let parameterNames = genericParameterNames(of: symbol)
        return replacingGenericParam(type) { genericParam in
            if let index = parameterNames.firstIndex(of: genericParam.name),
               index < arguments.count
            {
                return arguments[index]
            }
            return genericParam
        }
    }

    private func valueType(of symbol: Symbol.Symbol) -> TrussType.TrussType? {
        if let variable = symbol as? Symbol.VariableSymbol {
            return variable.type
        }
        if let function = symbol as? Symbol.FunctionSymbol {
            return function.forallType ?? function.functionType
        }
        return nil
    }

    private func genericArguments(of callee: AST.Expression) -> [AST.Expression]? {
        if let generic = callee as? AST.GenericApplication {
            return generic.genericArguments
        }
        if let sequential = callee as? AST.Sequential,
           sequential.genericApplicationGroupCloseIndex() != nil
        {
            return Array(sequential.operands.dropFirst())
        }
        return nil
    }

    private func returnType(of symbol: Symbol.FunctionSymbol) -> TrussType.TrussType {
        symbol.functionType?.returnType ?? TrussType.VoidType.INSTANCE
    }

    private func labelToken(_ value: String, at token: Token) -> Token {
        Token(value: value, kind: .Identifier, pos: token.pos, id: token.id)
    }

    private func syntheticToken(for expression: AST.Expression) -> Token {
        let range = expression.sourceRange
        return Token(
            value: "", kind: .Identifier,
            pos: Position(
                pos: range.start.offset, line: range.start.line, col: range.start.column,
                len: max(1, range.end.offset - range.start.offset)
            ),
            id: sourceId
        )
    }

    private func typeText(_ type: TrussType.TrussType?) -> String {
        guard let type else { return "unknown" }
        switch type {
        case is TrussType.VoidType: return "Void"
        case is TrussType.NeverType: return "Never"
        case is TrussType.ErrorType: return "_"
        case let nominal as TrussType.NominalType:
            return nominal.name
        case let builtin as TrussType.BuiltinType:
            return "\(Builtin.packageName).\(builtin.name)"
        case let optional as TrussType.OptionalType:
            return "\(typeText(optional.wrapped))?"
        case let pointer as TrussType.PointerType:
            return "\(typeText(pointer.pointee))*\(pointer.isNonnull ? "!" : "")"
        case let variable as TrussType.TypeVariableType:
            if let binding = variable.binding {
                return typeText(resolve(binding))
            }
            return variable.name ?? "T\(variable.id.id)"
        case let genericParam as TrussType.GenericParamType:
            return genericParam.name
        case let forall as TrussType.ForallType:
            return "forall " + forall.parameters.map(\.name).joined(separator: ", ")
        default:
            return "unknown"
        }
    }

    private func resolve(_ type: TrussType.TrussType) -> TrussType.TrussType {
        guard let variable = type as? TrussType.TypeVariableType else {
            return type
        }
        guard let binding = variable.binding else {
            return variable
        }
        guard binding !== variable else {
            return variable
        }
        let root = resolve(binding)
        variable.binding = root
        return root
    }

    private func unify(
        _ a: TrussType.TrussType, _ b: TrussType.TrussType, at token: Token
    ) -> Bool {
        if a is TrussType.ErrorType || b is TrussType.ErrorType {
            return true
        }
        if a === b {
            return true
        }
        if let variable = a as? TrussType.TypeVariableType {
            guard !occurs(variable, in: b) else {
                emitMismatch(at: token, expected: a, found: b)
                return false
            }
            if !checkNullptrBinding(variable, to: b, at: token) {
                return false
            }
            variable.binding = b
            return true
        }
        if let variable = b as? TrussType.TypeVariableType {
            guard !occurs(variable, in: a) else {
                emitMismatch(at: token, expected: a, found: b)
                return false
            }
            if !checkNullptrBinding(variable, to: a, at: token) {
                return false
            }
            variable.binding = a
            return true
        }
        switch (a, b) {
        case let (l as TrussType.NominalType, r as TrussType.NominalType):
            return l.id == r.id
        case let (l as TrussType.BuiltinType, r as TrussType.BuiltinType):
            return l.name == r.name
        case let (l as TrussType.GenericInstantiation, r as TrussType.NominalType):
            return l.arguments.isEmpty && l.base.id == r.id
        case let (l as TrussType.NominalType, r as TrussType.GenericInstantiation):
            return r.arguments.isEmpty && l.id == r.base.id
        case let (l as TrussType.TupleType, r as TrussType.TupleType):
            guard l.elements.count == r.elements.count else {
                return false
            }
            for (le, re) in zip(l.elements, r.elements) {
                if le.label != re.label {
                    return false
                }
                if !unify(le.type, re.type, at: token) {
                    return false
                }
            }
            return true
        case let (l as TrussType.FunctionType, r as TrussType.FunctionType):
            guard l.parameters.count == r.parameters.count, l.isAsync == r.isAsync,
                  l.isThrowing == r.isThrowing, l.throwsTypes.count == r.throwsTypes.count
            else {
                return false
            }
            for (lp, rp) in zip(l.parameters, r.parameters) {
                guard lp.label == rp.label, !unify(lp.type, rp.type, at: token) else {
                    return false
                }
            }
            for (lt, rt) in zip(l.throwsTypes, r.throwsTypes) {
                guard unify(lt, rt, at: token) else {
                    return false
                }
            }
            return unify(l.returnType, r.returnType, at: token)
        case let (l as TrussType.VariadicType, r as TrussType.VariadicType):
            return unify(l.base, r.base, at: token)
        case let (l as TrussType.CompositionType, r as TrussType.CompositionType):
            for (lm, rm) in zip(l.members, r.members) {
                guard unify(lm, rm, at: token) else {
                    return false
                }
            }
            return true
        case let (l as TrussType.OptionalType, r as TrussType.OptionalType):
            return unify(l.wrapped, r.wrapped, at: token)
        case let (l as TrussType.PointerType, r as TrussType.PointerType):
            guard l.isNonnull == r.isNonnull else {
                return false
            }
            return unify(l.pointee, r.pointee, at: token)
        case let (l as TrussType.GenericInstantiation, r as TrussType.GenericInstantiation):
            guard unify(l.base, r.base, at: token) else {
                return false
            }
            for (la, ra) in zip(l.arguments, r.arguments) {
                guard unify(la, ra, at: token) else {
                    return false
                }
            }
            return true
        case let (l as TrussType.ForallType, r as TrussType.ForallType):
            guard l.parameters.count == r.parameters.count else {
                return false
            }
            var mapping: [String: TrussType.GenericParamType] = [:]
            for (index, lParam) in l.parameters.enumerated() {
                mapping[lParam.name] = TrussType.GenericParamType(
                    r.parameters[index].name, r.parameters[index]
                )
            }
            let substituted = replacingGenericParam(l.body) { genericParam in
                mapping[genericParam.name] ?? genericParam
            }
            return unify(substituted, r.body, at: token)
        case let (l as TrussType.GenericParamType, r as TrussType.GenericParamType):
            return l.name == r.name
        default:
            return false
        }
    }

    private func checkNullptrBinding(
        _ variable: TrussType.TypeVariableType, to type: TrussType.TrussType, at token: Token
    ) -> Bool {
        guard nullablePointerConstraints.contains(ObjectIdentifier(variable)) else {
            return true
        }
        let resolved = resolve(type)
        let errorToken = nullptrLiteralTokens[ObjectIdentifier(variable)] ?? token
        if let pointer = resolved as? TrussType.PointerType {
            if pointer.isNonnull {
                context.emitError(
                    "nullptr cannot be used with non-null pointer type '\(typeText(resolved))'",
                    at: errorToken
                )
                reportedNullptrBindings.insert(ObjectIdentifier(variable))
                return false
            }
            return true
        }
        if resolved is TrussType.TypeVariableType || resolved is TrussType.ErrorType {
            return true
        }
        context.emitError(
            "nullptr requires a pointer type, found '\(typeText(resolved))'", at: errorToken
        )
        reportedNullptrBindings.insert(ObjectIdentifier(variable))
        return false
    }

    private func occurs(
        _ variable: TrussType.TypeVariableType, in type: TrussType.TrussType
    ) -> Bool {
        let resolved = resolve(type)
        if resolved === variable {
            return true
        }
        switch resolved {
        case let optional as TrussType.OptionalType:
            return occurs(variable, in: optional.wrapped)
        case let pointer as TrussType.PointerType:
            return occurs(variable, in: pointer.pointee)
        case let tuple as TrussType.TupleType:
            return tuple.elements.contains { occurs(variable, in: $0.type) }
        case let function as TrussType.FunctionType:
            return function.parameters.contains { occurs(variable, in: $0.type) }
                || occurs(variable, in: function.returnType)
                || function.throwsTypes.contains { occurs(variable, in: $0) }
        case let variadic as TrussType.VariadicType:
            return occurs(variable, in: variadic.base)
        case let composition as TrussType.CompositionType:
            return composition.members.contains { occurs(variable, in: $0) }
        case let generic as TrussType.GenericInstantiation:
            return generic.arguments.contains { occurs(variable, in: $0) }
        case let forall as TrussType.ForallType:
            return occurs(variable, in: forall.body)
        default:
            return false
        }
    }

    private func replacingGenericParam(
        _ type: TrussType.TrussType,
        _ replace: (TrussType.GenericParamType) -> TrussType.TrussType
    ) -> TrussType.TrussType {
        switch type {
        case let genericParam as TrussType.GenericParamType:
            replace(genericParam)
        case let optional as TrussType.OptionalType:
            TrussType.OptionalType(replacingGenericParam(optional.wrapped, replace))
        case let pointer as TrussType.PointerType:
            TrussType.PointerType(
                replacingGenericParam(pointer.pointee, replace), isNonnull: pointer.isNonnull
            )
        case let tuple as TrussType.TupleType:
            TrussType.TupleType(
                tuple.elements.map { element in
                    TrussType.TupleType.Element(
                        label: element.label,
                        type: replacingGenericParam(element.type, replace)
                    )
                }
            )
        case let function as TrussType.FunctionType:
            TrussType.FunctionType(
                parameters: function.parameters.map { parameter in
                    TrussType.FunctionType.Parameter(
                        label: parameter.label,
                        type: replacingGenericParam(parameter.type, replace)
                    )
                },
                isAsync: function.isAsync,
                isThrowing: function.isThrowing,
                throwsTypes: function.throwsTypes.map { replacingGenericParam($0, replace) },
                returnType: replacingGenericParam(function.returnType, replace)
            )
        case let variadic as TrussType.VariadicType:
            TrussType.VariadicType(replacingGenericParam(variadic.base, replace))
        case let composition as TrussType.CompositionType:
            TrussType.CompositionType(
                composition.members.map { replacingGenericParam($0, replace) }
            )
        case let generic as TrussType.GenericInstantiation:
            TrussType.GenericInstantiation(
                base: generic.base,
                arguments: generic.arguments.map { replacingGenericParam($0, replace) }
            )
        case let forall as TrussType.ForallType:
            TrussType.ForallType(
                parameters: forall.parameters,
                body: replacingGenericParam(forall.body, replace)
            )
        default:
            type
        }
    }

    private func coerce(
        _ actual: TrussType.TrussType, to expected: TrussType.TrussType, at token: Token
    ) -> Bool {
        if canCoerce(actual, to: expected, at: token) {
            return true
        }
        emitMismatch(at: token, expected: expected, found: actual)
        return false
    }

    private func canCoerce(
        _ actual: TrussType.TrussType, to expected: TrussType.TrussType, at token: Token
    ) -> Bool {
        if unify(actual, expected, at: token) {
            return true
        }
        if actual is TrussType.NeverType {
            return true
        }
        if let expectedPointer = expected as? TrussType.PointerType,
           let actualPointer = actual as? TrussType.PointerType,
           !expectedPointer.isNonnull, actualPointer.isNonnull
        {
            return canCoerce(actualPointer.pointee, to: expectedPointer.pointee, at: token)
        }
        if let optional = expected as? TrussType.OptionalType {
            return canCoerce(actual, to: optional.wrapped, at: token)
        }
        if let variadic = expected as? TrussType.VariadicType {
            return canCoerce(actual, to: variadic.base, at: token)
        }
        if let actualClass = nominalBase(of: actual) as? TrussType.ClassType,
           let expectedClass = expected as? TrussType.ClassType
        {
            for superclass in superclassChain(of: actualClass) {
                if unify(superclass, expectedClass, at: token) {
                    return true
                }
            }
        }
        if let expectedProtocol = expected as? TrussType.ProtocolType,
           let genericParam = actual as? TrussType.GenericParamType
        {
            return satisfiesConformance(genericParam, to: expectedProtocol)
        }
        if let expectedProtocol = expected as? TrussType.ProtocolType,
           let actualNominal = nominalBase(of: actual)
        {
            return conformsTo(actualNominal, expectedProtocol)
        }
        if let expectedComposition = expected as? TrussType.CompositionType,
           let genericParam = actual as? TrussType.GenericParamType
        {
            return expectedComposition.members.allSatisfy { member in
                guard let protocolType = member as? TrussType.ProtocolType else {
                    return false
                }
                return satisfiesConformance(genericParam, to: protocolType)
            }
        }
        if let expectedComposition = expected as? TrussType.CompositionType,
           let actualNominal = nominalBase(of: actual)
        {
            return expectedComposition.members.allSatisfy { member in
                guard let protocolType = member as? TrussType.ProtocolType else {
                    return false
                }
                return conformsTo(actualNominal, protocolType)
            }
        }
        return false
    }

    private func nominalBase(of type: TrussType.TrussType) -> TrussType.NominalType? {
        if let nominal = type as? TrussType.NominalType {
            return nominal
        }
        if let generic = type as? TrussType.GenericInstantiation {
            return generic.base
        }
        return nil
    }

    private func satisfiesConformance(
        _ genericParam: TrussType.GenericParamType, to required: TrussType.ProtocolType
    ) -> Bool {
        guard let symbol = genericParam.symbol else { return false }
        for constraint in symbol.constraints {
            guard case let .conformance(declared) = constraint else { continue }
            if declaredConformance(declared, includes: required) {
                return true
            }
        }
        return false
    }

    private func declaredConformance(
        _ declared: TrussType.TrussType, includes required: TrussType.ProtocolType
    ) -> Bool {
        if let composition = declared as? TrussType.CompositionType {
            return composition.members.contains { member in
                (member as? TrussType.ProtocolType)?.id == required.id
            }
        }
        return (declared as? TrussType.ProtocolType)?.id == required.id
    }

    private func emitMismatch(
        at token: Token, expected: TrussType.TrussType?, found: TrussType.TrussType?
    ) {
        if let foundVariable = found as? TrussType.TypeVariableType,
           reportedNullptrBindings.contains(ObjectIdentifier(foundVariable))
        {
            return
        }
        if let expectedVariable = expected as? TrussType.TypeVariableType,
           reportedNullptrBindings.contains(ObjectIdentifier(expectedVariable))
        {
            return
        }
        context.emitError(
            "expected '\(typeText(expected))', found '\(typeText(found))'", at: token
        )
    }

    private func emitMissingAnnotation(at token: Token, kind: String, name: String) {
        context.emitError(
            "\(kind) '\(name)' requires an explicit type annotation", at: token
        )
    }

    private func emitNoMember(at token: Token, type: String, member: String) {
        context.emitError("type '\(type)' has no member '\(member)'", at: token)
    }

    private func emitNoExactMatch(
        at token: Token, name: String, candidates: [Symbol.FunctionSymbol]
    ) {
        var notes: [Diagnostic] = []
        for candidate in candidates {
            if let noteToken = candidate.sourceToken {
                notes.append(
                    Diagnostic(
                        severity: .note, message: "candidate: \(candidate.name)",
                        range: noteToken.sourceRange(
                            in: context.sourceTable[noteToken.id]!.stringSourceBuffer
                        )
                    )
                )
            }
        }
        context.emitError(
            "no exact matches in call to '\(name)'", at: token, notes: notes
        )
    }

    private func emitAmbiguous(at token: Token, name: String) {
        context.emitError("ambiguous use of '\(name)'", at: token)
    }

    private func emitOperatorNoImplementation(at token: Token, name: String) {
        context.emitError("operator '\(name)' has no function declaration", at: token)
    }

    private func infer(_ expression: AST.Expression, at token: Token) -> TrussType.TrussType? {
        switch expression {
        case let call as AST.Call:
            if call.symbol == nil {
                var overloads = call.overloads ?? []
                if overloads.isEmpty, let member = call.callee as? AST.MemberAccess,
                   let builtinSymbol = member.symbol as? Symbol.FunctionSymbol,
                   builtinSymbol.isBuiltin
                {
                    overloads = [builtinSymbol]
                }
                if overloads.isEmpty, let member = call.callee as? AST.MemberAccess,
                   let objectType = infer(member.object, at: token)
                {
                    overloads = memberFunctionSymbols(of: member.member.value, in: objectType)
                }
                let calleeMemberFailed: Bool = if let member = call.callee as? AST.MemberAccess {
                    member.ty == nil && overloads.isEmpty
                } else {
                    false
                }
                if !calleeMemberFailed,
                   let resolved = resolveOverloads(
                       overloads, arguments: call.arguments,
                       trailingClosures: call.trailingClosures,
                       expectedReturn: nil, at: token,
                       fallbackName: callTargetName(call.callee)
                   )
                {
                    call.symbol = resolved.symbol
                    if resolved.symbol.name == "init",
                       let typeSymbol = resolvedSymbol(call.callee)
                       as? Symbol.NominalTypeSymbol,
                       let typeId = typeSymbol.typeId,
                       let nominal = context.typeTable[typeId] as? TrussType.NominalType
                    {
                        let arguments = resolved.type.parameters.map { resolve($0.type) }
                        expression.ty = TrussType.GenericInstantiation(
                            base: nominal, arguments: arguments
                        )
                    } else {
                        expression.ty = resolved.type.returnType
                        if let forallType = resolved.symbol.forallType,
                           let explicit = genericArguments(of: call.callee),
                           explicit.count != forallType.parameters.count
                        {
                            context.emitError(
                                "wrong number of type arguments: expected "
                                    + "\(forallType.parameters.count), got \(explicit.count)",
                                at: token
                            )
                        }
                    }
                }
            } else if expression.ty == nil, let symbol = call.symbol {
                expression.ty = returnType(of: symbol)
            }
            guard call.symbol != nil else {
                return nil
            }
            if let symbol = call.symbol,
               symbol.functionType?.isThrowing == true,
               tryContextDepth == 0
            {
                context.emitError(
                    "call to throwing function must be tried", at: token
                )
            }
            if let member = call.callee as? AST.MemberAccess, member.isOptional,
               let ty = expression.ty
            {
                expression.ty = TrussType.OptionalType(ty)
            }
            return expression.ty.map { resolve($0) }
        case let variable as AST.Variable:
            if let symbol = variable.symbol {
                if let narrowed = narrowedPointerTypes[symbol.id] {
                    expression.ty = narrowed
                } else {
                    expression.ty = valueType(of: symbol)
                }
            } else if variable.overloads?.count == 1, let overload = variable.overloads?.first {
                expression.ty = overload.forallType ?? overload.functionType
            } else if let overloads = variable.overloads, overloads.count > 1 {
                emitAmbiguous(at: variable.name, name: variable.name.value)
            } else {
                context.emitError(
                    "cannot find '\(variable.name.value)' in this scope", at: variable.name
                )
            }
        case let tupleExpression as AST.Tuple:
            var elements: [TrussType.TupleType.Element] = []
            for argument in tupleExpression.elements {
                let type = infer(argument.value, at: token)
                if type is TrussType.ErrorType {
                    break
                }
                guard let type else {
                    break
                }
                elements.append(
                    TrussType.TupleType.Element(label: argument.label?.value, type: type)
                )
            }
            expression.ty = TrussType.TupleType(elements)
        case let ifExpression as AST.If:
            withScope(ifExpression.scope) {
                checkBoolCondition(ifExpression.condition, at: ifExpression.token)
                let narrowed: (id: Id.SymbolId, type: TrussType.PointerType)? =
                    if let binary = ifExpression.condition as? AST.Binary,
                    binary.operatorToken.value == "!=",
                    binary.right is AST.NullptrLiteral,
                    let variable = binary.left as? AST.Variable,
                    let symbol = variable.symbol,
                    let pointer = binary.left.ty.map({ resolve($0) })
                    as? TrussType.PointerType,
                    !pointer.isNonnull {
                        (symbol.id, TrussType.PointerType(pointer.pointee, isNonnull: true))
                    } else {
                        nil
                    }
                if let narrowed {
                    narrowedPointerTypes[narrowed.id] = narrowed.type
                }
                for statement in ifExpression.then {
                    visit(statement)
                }
                if let narrowed {
                    narrowedPointerTypes[narrowed.id] = nil
                }
                let thenType: TrussType.TrussType =
                    if let expressionStatement = ifExpression.then.last as? AST.ExpressionStatement,
                    let ty = infer(expressionStatement.expression, at: token) {
                        ty
                    } else {
                        TrussType.VoidType.INSTANCE
                    }
                let elseType: TrussType.TrussType?
                switch ifExpression.elseKind {
                case let .Block(statements):
                    for statement in statements {
                        visit(statement)
                    }
                    elseType =
                        if let expressionStatement = statements.last as? AST.ExpressionStatement,
                        let ty = infer(expressionStatement.expression, at: token) {
                            ty
                        } else {
                            TrussType.VoidType.INSTANCE
                        }
                case let .If(innerIf):
                    elseType = infer(innerIf, at: token) ?? TrussType.VoidType.INSTANCE
                case nil:
                    elseType = nil
                }
                if let elseType {
                    expression.ty = join([thenType, elseType], at: token)
                } else {
                    expression.ty = TrussType.VoidType.INSTANCE
                }
            }
        case let matchExpression as AST.Match:
            let subjectType = infer(matchExpression.subject, at: token)
            var caseTypes: [TrussType.TrussType] = []
            for caseItem in matchExpression.cases {
                for pattern in caseItem.patterns {
                    checkPattern(pattern, against: subjectType, at: matchExpression.token)
                }
                for statement in caseItem.body {
                    visit(statement)
                }
                if let expressionStatement = caseItem.body.last as? AST.ExpressionStatement, let caseType = infer(
                    expressionStatement.expression,
                    at: token
                ) {
                    caseTypes.append(caseType)
                } else {
                    caseTypes.append(TrussType.VoidType.INSTANCE)
                }
            }
            expression.ty = join(caseTypes, at: token)
            checkMatchExhaustive(
                subjectType: subjectType, cases: matchExpression.cases,
                at: matchExpression.token
            )
        case let caseMatch as AST.CaseMatch:
            let subjectType = infer(caseMatch.subject, at: token)
            checkPattern(caseMatch.pattern, against: subjectType, at: caseMatch.token)
            expression.ty = stdType(named: "Bool")
        case let doExpression as AST.Do:
            doThrownTypeStack.append([])
            for statement in doExpression.body {
                visit(statement)
            }
            let bodyType = if let last = doExpression.body.last as? AST.ExpressionStatement, let ty = infer(
                last.expression,
                at: token
            ) {
                ty
            } else {
                TrussType.VoidType.INSTANCE
            }
            var catchTypes: [TrussType.TrussType] = []
            let thrownTypes = doThrownTypeStack.last ?? []
            for catchClause in doExpression.catches {
                if let pattern = catchClause.pattern {
                    var matched = false
                    for thrownType in thrownTypes {
                        if checkPattern(pattern, against: thrownType, at: token, reportErrors: false) {
                            matched = true
                            break
                        }
                    }
                    if !matched, let first = thrownTypes.first {
                        _ = checkPattern(pattern, against: first, at: token)
                    }
                }
                if let whereCondition = catchClause.whereCondition {
                    _ = infer(whereCondition, at: catchClause.whereToken ?? token)
                }
                for statement in catchClause.body {
                    visit(statement)
                }
                if let last = catchClause.body.last as? AST.ExpressionStatement, let ty = infer(
                    last.expression,
                    at: token
                ) {
                    catchTypes.append(ty)
                } else {
                    catchTypes.append(TrussType.VoidType.INSTANCE)
                }
            }
            if let finallyClauseBody = doExpression.finallyBody {
                for statement in finallyClauseBody {
                    visit(statement)
                }
                expression.ty =
                    if let last = finallyClauseBody.last as? AST.ExpressionStatement,
                    let ty = infer(last.expression, at: token) {
                        ty
                    } else {
                        TrussType.VoidType.INSTANCE
                    }
            } else {
                expression.ty = join([bodyType] + catchTypes, at: token)
            }
            doThrownTypeStack.removeLast()
        case let memberAccess as AST.MemberAccess:
            memberAccess.object.isLeftValue = true
            _ = infer(memberAccess.object, at: token)
            let objectType = memberAccess.object.ty
            if let caseSymbol = memberAccess.symbol as? Symbol.CaseSymbol,
               let memberOf = caseSymbol.memberOf,
               let enumSymbol = context.id2Symbol[memberOf] as? Symbol.EnumSymbol,
               let typeId = enumSymbol.typeId, let enumType = context.typeTable[typeId]
            {
                expression.ty = enumType
            } else if let ty = memberType(of: memberAccess.member.value, in: objectType) {
                expression.ty = ty
                if memberAccess.symbol == nil {
                    memberAccess.symbol = memberSymbol(
                        of: memberAccess.member.value, in: objectType
                    )
                }
            } else if let symbol = memberAccess.symbol {
                expression.ty = valueType(of: symbol)
            } else if let overloads = memberAccess.overloads, overloads.count == 1,
                      let overload = overloads.first
            {
                expression.ty = overload.forallType ?? overload.functionType
            }
            if memberAccess.isOptional {
                if let objectType,
                   !(objectType is TrussType.OptionalType),
                   !(objectType is TrussType.ErrorType)
                {
                    context.emitError(
                        "left side of '?.' is not optional", at: memberAccess.token
                    )
                }
                if let ty = expression.ty {
                    expression.ty = TrussType.OptionalType(ty)
                }
            }
            if expression.ty == nil, let objectType {
                emitNoMember(
                    at: memberAccess.member, type: typeText(objectType),
                    member: memberAccess.member.value
                )
            }
        case let implicitMemberAccess as AST.ImplicitMemberAccess:
            context.emitError(
                "cannot infer type of implicit member access '.\(implicitMemberAccess.name.value)'",
                at: implicitMemberAccess.token
            )
        case let subscriptExpression as AST.Subscript:
            _ = infer(subscriptExpression.base, at: token)
            if let pointer = subscriptExpression.base.ty.flatMap({
                resolve($0) as? TrussType.PointerType
            }), subscriptExpression.arguments.count == 1 {
                _ = infer(subscriptExpression.arguments[0].value, at: token)
                expression.ty = pointer.pointee
                return expression.ty.map { resolve($0) }
            }
            if subscriptExpression.symbol == nil {
                var candidates = subscriptExpression.overloads ?? []
                let baseType: TrussType.TrussType? = subscriptExpression.base.ty
                if candidates.isEmpty, baseType != nil {
                    candidates = memberFunctionSymbols(of: "subscript", in: baseType)
                }
                if let resolved = resolveOverloads(
                    candidates, arguments: subscriptExpression.arguments, trailingClosures: [],
                    expectedReturn: nil, at: token, fallbackName: "subscript"
                ) {
                    subscriptExpression.symbol = resolved.symbol
                    expression.ty = resolved.type.returnType
                }
            } else if expression.ty == nil, let symbol = subscriptExpression.symbol {
                expression.ty = returnType(of: symbol)
            }
            guard subscriptExpression.symbol != nil else {
                return nil
            }
            return expression.ty.map { resolve($0) }
        case is AST.SelfExpression:
            if let typeId = typeStack.last?.typeId {
                expression.ty = context.typeTable[typeId]
            }
        case is AST.SuperExpression:
            if let classSymbol = typeStack.last as? Symbol.ClassSymbol,
               let typeId = classSymbol.superclass?.typeId
            {
                expression.ty = context.typeTable[typeId]
            }
        case let parentheticalExpression as AST.Parenthetical:
            expression.ty = infer(parentheticalExpression.inner, at: token)
        case let castExpression as AST.Cast:
            let leftType = infer(castExpression.left, at: token)
            let target = evaluate(castExpression.right)
            switch castExpression.kind {
            case .Is:
                if let leftType, !canCoerce(leftType, to: target, at: token) {
                    emitMismatch(at: token, expected: target, found: leftType)
                }
            case .As:
                if let leftType, !canCoerce(leftType, to: target, at: token) {
                    emitMismatch(at: token, expected: target, found: leftType)
                }
                expression.ty = target
            case .AsExclamation:
                expression.ty = target
            case .AsBitCast:
                expression.ty = target
            case .OptionalAs:
                expression.ty = TrussType.OptionalType(target)
            }
        case let tryExpression as AST.Try:
            tryContextDepth += 1
            let inferred = infer(tryExpression.expression, at: token)
            tryContextDepth -= 1
            if tryExpression.kind == .OptionalTry, let inferred {
                expression.ty = TrussType.OptionalType(inferred)
            } else {
                expression.ty = inferred
            }
            if let call = tryExpression.expression as? AST.Call,
               let symbol = call.symbol,
               let functionType = symbol.functionType
            {
                if !functionType.throwsTypes.isEmpty, !doThrownTypeStack.isEmpty {
                    doThrownTypeStack[doThrownTypeStack.count - 1].append(
                        contentsOf: functionType.throwsTypes
                    )
                }
                if functionType.isThrowing == false {
                    context.emitError(
                        "try used on call to non-throwing function", at: tryExpression.token
                    )
                }
            }
        case let awaitExpression as AST.Await:
            expression.ty = infer(awaitExpression.expression, at: token)
            if let call = awaitExpression.expression as? AST.Call,
               let symbol = call.symbol,
               symbol.functionType?.isAsync == false
            {
                context.emitError(
                    "await used on call to non-async function", at: awaitExpression.token
                )
            }
        case let genericApplication as AST.GenericApplication:
            let baseSymbol = resolvedSymbol(genericApplication.base)
                as? Symbol.NominalTypeSymbol
            if let typeSymbol = baseSymbol,
               let typeId = typeSymbol.typeId,
               let nominal = context.typeTable[typeId] as? TrussType.NominalType
            {
                var arguments: [TrussType.TrussType] = []
                var ok = true
                for argument in genericApplication.genericArguments {
                    let argumentType = evaluate(argument)
                    if argumentType is TrussType.ErrorType {
                        ok = false
                        break
                    }
                    arguments.append(argumentType)
                }
                if ok {
                    checkGenericArguments(
                        of: nominal, arguments: arguments, at: token
                    )
                    expression.ty = TrussType.GenericInstantiation(
                        base: nominal, arguments: arguments
                    )
                }
            } else if baseSymbol == nil {
                if let name = baseName(of: genericApplication.base) {
                    context.emitError(
                        "cannot find type '\(name)'",
                        at: syntheticToken(for: genericApplication)
                    )
                }
            }
        case let shorthandArgument as AST.ShorthandArgument:
            if let parameters = closureParameterTypes.last,
               shorthandArgument.index < parameters.count
            {
                expression.ty = parameters[shorthandArgument.index]
            } else {
                context.emitError(
                    "cannot infer type of '$\(shorthandArgument.index)'",
                    at: shorthandArgument.dollarToken
                )
            }
        case is AST.SelfType:
            if let typeId = typeStack.last?.typeId {
                expression.ty = context.typeTable[typeId]
            } else {
                context.emitError(
                    "cannot use 'Self' outside of a type context", at: token
                )
            }
        case let keyPathExpression as AST.KeyPathExpression:
            var baseType: TrussType.TrussType?
            if let root = keyPathExpression.root {
                baseType = infer(root, at: token)
            } else {
                context.emitError(
                    "key path requires a root type",
                    at: keyPathExpression.backslashToken
                )
                return nil
            }
            for component in keyPathExpression.components {
                guard let current = baseType else { break }
                if let name = component.name, name.kind == .Keyword(.SelfKw) {
                    baseType = current
                    continue
                }
                if let name = component.name, component.arguments.isEmpty {
                    if let member = memberType(of: name.value, in: current) {
                        component.symbol = memberSymbol(of: name.value, in: current)
                        baseType = member
                    } else if let symbol = memberSymbol(of: name.value, in: current) {
                        component.symbol = symbol
                        baseType = valueType(of: symbol)
                    } else {
                        baseType = nil
                    }
                } else {
                    let candidates = memberFunctionSymbols(
                        of: "subscript", in: current as TrussType.TrussType?
                    )
                    for argument in component.arguments {
                        _ = infer(argument.value, at: token)
                    }
                    if let resolved = resolveOverloads(
                        candidates, arguments: component.arguments, trailingClosures: [],
                        expectedReturn: nil, at: token, fallbackName: "subscript"
                    ) {
                        component.symbol = resolved.symbol
                        component.overloads = candidates
                        baseType = resolved.type.returnType
                    } else {
                        baseType = nil
                    }
                }
                if component.postfix != nil, let current = baseType {
                    baseType = TrussType.OptionalType(current)
                }
            }
            expression.ty = baseType
        case let sizeofExpression as AST.SizeofExpression:
            let type = evaluate(sizeofExpression.type)
            sizeofExpression.typeType = type
            if type is TrussType.ProtocolType {
                context.emitError(
                    "cannot determine size of protocol type '\(typeText(type))'",
                    at: sizeofExpression.token
                )
            }
            expression.ty = TrussType.BuiltinType("UInt64")
        case let forceUnwrap as AST.ForceUnwrap:
            if let inner = infer(forceUnwrap.expression, at: token) {
                if let optional = inner as? TrussType.OptionalType {
                    expression.ty = optional.wrapped
                } else if let pointer = resolve(inner) as? TrussType.PointerType,
                          !pointer.isNonnull
                {
                    expression.ty = TrussType.PointerType(pointer.pointee, isNonnull: true)
                } else if !(inner is TrussType.ErrorType) {
                    context.emitError(
                        "cannot force unwrap value of non-optional type '\(typeText(inner))'",
                        at: forceUnwrap.token
                    )
                }
            }
        case let dereference as AST.Dereference:
            if let inner = infer(dereference.expression, at: token) {
                if let pointer = resolve(inner) as? TrussType.PointerType {
                    expression.ty = pointer.pointee
                } else if !(inner is TrussType.ErrorType) {
                    context.emitError(
                        "cannot dereference non-pointer type '\(typeText(inner))'",
                        at: dereference.operatorToken
                    )
                }
            }
        case let addressOf as AST.AddressOf:
            addressOf.expression.isLeftValue = true
            if let inner = infer(addressOf.expression, at: token) {
                expression.ty = TrussType.PointerType(inner, isNonnull: true)
            }
        case let nullPointer as AST.NullptrLiteral:
            let variable = freshTypeVariable("nullptr")
            nullablePointerConstraints.insert(ObjectIdentifier(variable))
            nullptrLiteralTokens[ObjectIdentifier(variable)] = nullPointer.token
            expression.ty = variable
        case is AST.IntegerLiteral:
            expression.ty = stdType(named: "Int32")
        case is AST.FloatLiteral:
            expression.ty = stdType(named: "Float64")
        case is AST.BoolLiteral:
            expression.ty = stdType(named: "Bool")
        case is AST.CharLiteral:
            expression.ty = stdType(named: "Char")
        case let optionalBinding as AST.OptionalBinding:
            _ = infer(optionalBinding.value, at: token)
            expression.ty = stdType(named: "Bool")
        case is AST.VoidLiteral:
            expression.ty = TrussType.VoidType.INSTANCE
        case let interpolation as AST.StringInterpolation:
            for segment in interpolation.segments {
                if case let .expression(expression) = segment {
                    _ = infer(expression, at: token)
                }
            }
            expression.ty = nil
        case let arrayLiteral as AST.ArrayLiteral:
            for element in arrayLiteral.elements {
                _ = infer(element, at: token)
            }
            expression.ty = nil
        case let dictionaryLiteral as AST.DictionaryLiteral:
            for entry in dictionaryLiteral.entries {
                _ = infer(entry.key, at: token)
                _ = infer(entry.value, at: token)
            }
            expression.ty = nil
        case let binary as AST.Binary:
            if binary.operatorToken.value == "=" {
                if let subscriptExpr = binary.left as? AST.Subscript {
                    resolveSubscriptAssignment(
                        subscriptExpr, rhs: binary.right, at: binary.operatorToken
                    )
                    binary.ty = subscriptExpr.ty
                    break
                }
                binary.left.isLeftValue = true
            }
            _ = infer(binary.left, at: token)
            _ = infer(binary.right, at: token)
            if binary.operatorToken.value == "=" {
                if let leftType = binary.left.ty, let rightType = binary.right.ty,
                   !canCoerce(rightType, to: leftType, at: token)
                {
                    emitMismatch(at: binary.operatorToken, expected: leftType, found: rightType)
                }
                binary.ty = binary.left.ty
                break
            }
            let freeCandidates = lookupOperatorFunctions(binary.operatorToken.value)
            let leftStaticCandidates = memberOperatorCandidates(
                binary.operatorToken.value, in: binary.left.ty, isStatic: true
            )
            let leftInstanceCandidates = memberOperatorCandidates(
                binary.operatorToken.value, in: binary.left.ty, isStatic: false
            )
            let rightStaticCandidates = memberOperatorCandidates(
                binary.operatorToken.value, in: binary.right.ty, isStatic: true
            )
            let rightInstanceCandidates = memberOperatorCandidates(
                binary.operatorToken.value, in: binary.right.ty, isStatic: false
            )
            let staticCandidates =
                freeCandidates + leftStaticCandidates + rightStaticCandidates
            guard
                !staticCandidates.isEmpty || !leftInstanceCandidates.isEmpty
                || !rightInstanceCandidates.isEmpty
            else {
                emitOperatorNoImplementation(
                    at: binary.operatorToken, name: binary.operatorToken.value
                )
                return nil
            }
            var resolved: (symbol: Symbol.FunctionSymbol, type: TrussType.FunctionType)?
            if !staticCandidates.isEmpty {
                resolved = resolveOverloads(
                    staticCandidates,
                    arguments: [
                        AST.LabeledArgument(
                            label: labelToken("lhs", at: binary.operatorToken),
                            value: binary.left,
                            sourceRange: binary.left.sourceRange
                        ),
                        AST.LabeledArgument(
                            label: labelToken("rhs", at: binary.operatorToken),
                            value: binary.right,
                            sourceRange: binary.right.sourceRange
                        ),
                    ],
                    trailingClosures: [],
                    expectedReturn: nil,
                    at: token,
                    reportErrors: false
                )
            }
            if resolved == nil, !leftInstanceCandidates.isEmpty {
                resolved = resolveOverloads(
                    leftInstanceCandidates,
                    arguments: [
                        AST.LabeledArgument(
                            label: labelToken("rhs", at: binary.operatorToken),
                            value: binary.right,
                            sourceRange: binary.right.sourceRange
                        ),
                    ],
                    trailingClosures: [],
                    expectedReturn: nil,
                    at: token,
                    reportErrors: false
                )
            }
            if resolved == nil, !rightInstanceCandidates.isEmpty {
                resolved = resolveOverloads(
                    rightInstanceCandidates,
                    arguments: [
                        AST.LabeledArgument(
                            label: labelToken("lhs", at: binary.operatorToken),
                            value: binary.left,
                            sourceRange: binary.left.sourceRange
                        ),
                    ],
                    trailingClosures: [],
                    expectedReturn: nil,
                    at: token,
                    reportErrors: false
                )
            }
            if let resolved {
                binary.symbol = resolved.symbol
                binary.ty = resolved.type.returnType
                if binary.isAssignment, let subscriptExpr = binary.left as? AST.Subscript {
                    if let symbol = subscriptExpr.symbol, symbol.setterType == nil {
                        context.emitError(
                            "cannot assign to subscript: is read-only",
                            at: binary.operatorToken
                        )
                    } else {
                        let resultType = resolved.type.returnType
                        if let elementType = subscriptExpr.ty,
                           !canCoerce(resultType, to: elementType, at: binary.operatorToken)
                        {
                            emitMismatch(
                                at: binary.operatorToken, expected: elementType, found: resultType
                            )
                        }
                    }
                }
            }
        case let prefixExpression as AST.Prefix:
            _ = infer(prefixExpression.expression, at: token)
            let freeCandidates = lookupOperatorFunctions(prefixExpression.operatorToken.value)
            let staticCandidates = freeCandidates + memberOperatorCandidates(
                prefixExpression.operatorToken.value, in: prefixExpression.expression.ty, isStatic: true
            )
            let instanceCandidates = memberOperatorCandidates(
                prefixExpression.operatorToken.value, in: prefixExpression.expression.ty, isStatic: false
            )
            guard !staticCandidates.isEmpty || !instanceCandidates.isEmpty else {
                emitOperatorNoImplementation(
                    at: prefixExpression.operatorToken, name: prefixExpression.operatorToken.value
                )
                return nil
            }
            var resolved: (symbol: Symbol.FunctionSymbol, type: TrussType.FunctionType)?
            if !staticCandidates.isEmpty {
                resolved = resolveOverloads(
                    staticCandidates,
                    arguments: [AST.LabeledArgument(
                        label: labelToken("prefixValue", at: prefixExpression.operatorToken),
                        value: prefixExpression.expression,
                        sourceRange: prefixExpression.expression.sourceRange
                    )],
                    trailingClosures: [],
                    expectedReturn: nil,
                    at: token,
                    reportErrors: false
                )
            }
            if resolved == nil, !instanceCandidates.isEmpty {
                resolved = resolveOverloads(
                    instanceCandidates,
                    arguments: [],
                    trailingClosures: [],
                    expectedReturn: nil,
                    at: token,
                    reportErrors: false
                )
            }
            if let resolved {
                prefixExpression.symbol = resolved.symbol
                prefixExpression.ty = resolved.type.returnType
            }
        case let postfixExpression as AST.Postfix:
            _ = infer(postfixExpression.expression, at: token)
            let freeCandidates = lookupOperatorFunctions(postfixExpression.operatorToken.value)
            let staticCandidates = freeCandidates + memberOperatorCandidates(
                postfixExpression.operatorToken.value, in: postfixExpression.expression.ty, isStatic: true
            )
            let instanceCandidates = memberOperatorCandidates(
                postfixExpression.operatorToken.value, in: postfixExpression.expression.ty, isStatic: false
            )
            guard !staticCandidates.isEmpty || !instanceCandidates.isEmpty else {
                emitOperatorNoImplementation(
                    at: postfixExpression.operatorToken, name: postfixExpression.operatorToken.value
                )
                return nil
            }
            var resolved: (symbol: Symbol.FunctionSymbol, type: TrussType.FunctionType)?
            if !staticCandidates.isEmpty {
                resolved = resolveOverloads(
                    staticCandidates,
                    arguments: [AST.LabeledArgument(
                        label: labelToken("postfixValue", at: postfixExpression.operatorToken),
                        value: postfixExpression.expression,
                        sourceRange: postfixExpression.expression.sourceRange
                    )],
                    trailingClosures: [],
                    expectedReturn: nil,
                    at: token,
                    reportErrors: false
                )
            }
            if resolved == nil, !instanceCandidates.isEmpty {
                resolved = resolveOverloads(
                    instanceCandidates,
                    arguments: [],
                    trailingClosures: [],
                    expectedReturn: nil,
                    at: token,
                    reportErrors: false
                )
            }
            if let resolved {
                postfixExpression.symbol = resolved.symbol
                postfixExpression.ty = resolved.type.returnType
            }
        case let closure as AST.Closure:
            if let signature = closure.signature,
               signature.parameters.allSatisfy({ $0.type != nil })
            {
                withScope(closure.scope) {
                    let parameterTypes: [TrussType.TrussType] = signature.parameters.map {
                        parameter in
                        if let ty = parameter.type {
                            evaluate(ty)
                        } else {
                            TrussType.ErrorType.INSTANCE
                        }
                    }
                    for (parameter, type) in zip(signature.parameters, parameterTypes) {
                        let variable =
                            closure.scope?.values[parameter.name.value]?.first
                                as? Symbol.VariableSymbol
                        variable?.type = type
                    }
                    let returnType: TrussType.TrussType =
                        if let returnTypeExpression = signature.returnType {
                            evaluate(returnTypeExpression)
                        } else {
                            TrussType.VoidType.INSTANCE
                        }
                    let functionType = functionType(
                        labels: signature.parameters.map { $0.label?.value },
                        parameterTypes: parameterTypes,
                        varargToken: nil,
                        asyncToken: signature.asyncToken,
                        throwsClause: signature.throwsClause,
                        returnType: returnType
                    )
                    closureParameterTypes.append(parameterTypes)
                    withFunctionReturnType(returnType) {
                        withFunctionThrows(signature.throwsClause != nil, functionType.throwsTypes) {
                            for statement in closure.body {
                                visit(statement)
                            }
                        }
                    }
                    closureParameterTypes.removeLast()
                    expression.ty = functionType
                }
            } else {
                emitMissingAnnotation(at: syntheticToken(for: closure), kind: "closure", name: "")
            }
        default:
            expression.ty = nil
        }
        return expression.ty.map { resolve($0) }
    }

    @discardableResult
    private func checkPattern(
        _ pattern: AST.Expression, against subjectType: TrussType.TrussType?, at token: Token,
        reportErrors: Bool = true
    ) -> Bool {
        var matched = true
        switch pattern {
        case let binding as AST.BindingPattern:
            matched =
                bindPatternVariable(
                    binding, type: subjectType, at: token, reportErrors: reportErrors
                ) && matched
            if let subpattern = binding.subpattern {
                matched =
                    checkPattern(
                        subpattern, against: subjectType, at: token,
                        reportErrors: reportErrors
                    ) && matched
            }
        case let asPattern as AST.AsPattern:
            let target = evaluate(asPattern.typeExpression)
            if let subjectType, !canCoerce(subjectType, to: target, at: token) {
                if reportErrors {
                    emitMismatch(at: token, expected: target, found: subjectType)
                }
                matched = false
            }
            matched =
                checkPattern(
                    asPattern.pattern, against: target, at: token, reportErrors: reportErrors
                ) && matched
        case let isPattern as AST.IsPattern:
            let target = evaluate(isPattern.typeExpression)
            if let subjectType, !canCoerce(subjectType, to: target, at: token) {
                if reportErrors {
                    emitMismatch(at: token, expected: target, found: subjectType)
                }
                matched = false
            }
        case is AST.WildcardPattern:
            break
        case let call as AST.Call:
            matched =
                checkEnumCasePattern(
                    call, against: subjectType, at: token, reportErrors: reportErrors
                ) && matched
        case let member as AST.MemberAccess:
            matched =
                checkEnumCasePattern(
                    member, against: subjectType, at: token, reportErrors: reportErrors
                ) && matched
        case let implicit as AST.ImplicitMemberAccess:
            matched =
                checkEnumCasePattern(
                    implicit, against: subjectType, at: token, reportErrors: reportErrors
                ) && matched
        case let variable as AST.Variable:
            if let subjectType, let nominal = nominalBase(of: subjectType),
               let symbol = nominal.symbol,
               symbol.scope.values[variable.name.value]?
               .contains(where: { $0 is Symbol.CaseSymbol }) == true
            {
                matched =
                    checkEnumCasePattern(
                        variable, against: subjectType, at: token, reportErrors: reportErrors
                    ) && matched
            } else if let subjectType, let declared = evaluateVariable(variable) {
                if !canCoerce(subjectType, to: declared, at: token) {
                    if reportErrors {
                        emitMismatch(at: token, expected: declared, found: subjectType)
                    }
                    matched = false
                }
            }
        default:
            break
        }
        return matched
    }

    private func bindPatternVariable(
        _ binding: AST.BindingPattern, type: TrussType.TrussType?, at token: Token,
        reportErrors: Bool = true
    ) -> Bool {
        if let type,
           let variable = scopeStack.last?.values[binding.name.value]?.first
           as? Symbol.VariableSymbol
        {
            if let existing = variable.type {
                _ = unify(existing, type, at: token)
            } else {
                variable.type = type
            }
        }
        if let typeExpression = binding.typeExpression {
            let declared = evaluate(typeExpression)
            if let type, !canCoerce(type, to: declared, at: token) {
                if reportErrors {
                    emitMismatch(at: token, expected: declared, found: type)
                }
                return false
            }
        }
        return true
    }

    private func checkEnumCasePattern(
        _ pattern: AST.Expression, against subjectType: TrussType.TrussType?, at token: Token,
        reportErrors: Bool = true
    ) -> Bool {
        let caseName: String?
        var arguments: [AST.LabeledArgument] = []
        var caseType: TrussType.TrussType? = nil
        var symbolTarget: AST.Expression? = nil
        switch pattern {
        case let call as AST.Call:
            if let implicit = call.callee as? AST.ImplicitMemberAccess {
                caseName = implicit.name.value
                arguments = call.arguments
                caseType = subjectType
                symbolTarget = implicit
            } else if let member = call.callee as? AST.MemberAccess {
                caseName = member.member.value
                arguments = call.arguments
                caseType = evaluate(member.object)
                symbolTarget = member
            } else if let variable = call.callee as? AST.Variable {
                caseName = variable.name.value
                arguments = call.arguments
                caseType = subjectType
                symbolTarget = variable
            } else {
                return true
            }
        case let member as AST.MemberAccess:
            caseName = member.member.value
            caseType = evaluate(member.object)
            symbolTarget = member
        case let implicit as AST.ImplicitMemberAccess:
            caseName = implicit.name.value
            caseType = subjectType
            symbolTarget = implicit
        case let variable as AST.Variable:
            caseName = variable.name.value
            caseType = subjectType
            symbolTarget = variable
        default:
            return true
        }
        guard let caseName else { return true }
        let baseType = (caseType as? TrussType.OptionalType)?.wrapped ?? caseType
        let nominal = (baseType as? TrussType.GenericInstantiation)?.base
            ?? (baseType as? TrussType.NominalType)
        guard let nominal else {
            if let caseType, !(caseType is TrussType.ErrorType) {
                if reportErrors {
                    context.emitError(
                        "cannot match against non-enum type '\(typeText(caseType))'", at: token
                    )
                }
                return false
            }
            return true
        }
        guard let symbol = nominal.symbol else { return true }
        guard let caseSymbol = symbol.scope.values[caseName]?.first as? Symbol.CaseSymbol else {
            if reportErrors {
                emitNoMember(at: token, type: typeText(nominal), member: caseName)
            }
            return false
        }
        symbolTarget.map { target in
            switch target {
            case let implicit as AST.ImplicitMemberAccess:
                implicit.symbol = caseSymbol
            case let member as AST.MemberAccess:
                member.symbol = caseSymbol
            case let variable as AST.Variable:
                variable.symbol = caseSymbol
            default:
                break
            }
        }
        let expectedTypes = caseSymbol.associatedTypes
        let expectedLabels = caseSymbol.associatedLabels
        if arguments.isEmpty {
            if !expectedTypes.isEmpty {
                if reportErrors {
                    context.emitError(
                        "case '\(caseName)' has \(expectedTypes.count) associated value(s), "
                            + "but none given",
                        at: token
                    )
                }
                return false
            }
            return true
        }
        var mapped: [Int] = []
        var used = [Bool](repeating: false, count: expectedLabels.count)
        for argument in arguments {
            if let label = argument.label?.value {
                guard let index = expectedLabels.firstIndex(of: label), !used[index] else {
                    if reportErrors {
                        context.emitError(
                            "case '\(caseName)' has no associated value labeled '\(label)'",
                            at: token
                        )
                    }
                    return false
                }
                used[index] = true
                mapped.append(index)
            } else {
                let index = mapped.count
                guard index < expectedLabels.count else {
                    if reportErrors {
                        context.emitError(
                            "case '\(caseName)' has \(expectedLabels.count) associated value(s), "
                                + "but more given",
                            at: token
                        )
                    }
                    return false
                }
                used[index] = true
                mapped.append(index)
            }
        }
        if mapped.count < expectedTypes.count {
            if reportErrors {
                context.emitError(
                    "case '\(caseName)' has \(expectedTypes.count) associated value(s), "
                        + "but \(mapped.count) given",
                    at: token
                )
            }
            return false
        }
        var matched = true
        for (argumentIndex, parameterIndex) in mapped.enumerated() {
            matched =
                checkPattern(
                    arguments[argumentIndex].value, against: expectedTypes[parameterIndex],
                    at: token, reportErrors: reportErrors
                ) && matched
        }
        return matched
    }

    private func check(
        _ expression: AST.Expression, _ expected: TrussType.TrussType, at token: Token
    ) {
        switch expression {
        case let closure as AST.Closure:
            guard let functionType = expected as? TrussType.FunctionType else {
                if let actual = infer(expression, at: token) {
                    if !canCoerce(actual, to: expected, at: token) {
                        emitMismatch(at: token, expected: expected, found: actual)
                    }
                }
                return
            }
            let parameterTypes = functionType.parameters.map(\.type)
            withScope(closure.scope) {
                if let signature = closure.signature {
                    for (index, parameter) in signature.parameters.enumerated() {
                        guard index < parameterTypes.count else { break }
                        let variable =
                            closure.scope?.values[parameter.name.value]?.first
                                as? Symbol.VariableSymbol
                        variable?.type = parameterTypes[index]
                    }
                }
                closureParameterTypes.append(parameterTypes)
                withFunctionReturnType(functionType.returnType) {
                    withFunctionThrows(functionType.isThrowing, functionType.throwsTypes) {
                        for statement in closure.body.dropLast() {
                            visit(statement)
                        }
                        if let lastStatement = closure.body.last as? AST.ExpressionStatement {
                            check(lastStatement.expression, functionType.returnType, at: token)
                        } else if let lastStatement = closure.body.last {
                            visit(lastStatement)
                        }
                    }
                }
                closureParameterTypes.removeLast()
            }
            expression.ty = functionType
        case let tupleExpression as AST.Tuple:
            if let tupleType = expected as? TrussType.TupleType {
                for (index, element) in tupleExpression.elements.enumerated() {
                    guard index < tupleType.elements.count else { break }
                    check(element.value, tupleType.elements[index].type, at: token)
                }
            } else {
                if let actual = infer(expression, at: token) {
                    if !canCoerce(actual, to: expected, at: token) {
                        emitMismatch(at: token, expected: expected, found: actual)
                    }
                }
            }
        case let call as AST.Call:
            if call.symbol == nil {
                if let resolved = resolveOverloads(
                    call.overloads ?? [], arguments: call.arguments,
                    trailingClosures: call.trailingClosures, expectedReturn: expected,
                    at: token, fallbackName: callTargetName(call.callee)
                ) {
                    call.symbol = resolved.symbol
                    if resolved.symbol.name == "init",
                       let typeSymbol = resolvedSymbol(call.callee)
                       as? Symbol.NominalTypeSymbol,
                       let typeId = typeSymbol.typeId,
                       let nominal = context.typeTable[typeId] as? TrussType.NominalType
                    {
                        let arguments = resolved.type.parameters.map { resolve($0.type) }
                        expression.ty = TrussType.GenericInstantiation(
                            base: nominal, arguments: arguments
                        )
                    } else {
                        expression.ty = resolved.type.returnType
                    }
                    if resolved.symbol.name != "init",
                       let forallType = resolved.symbol.forallType,
                       let explicit = genericArguments(of: call.callee),
                       explicit.count != forallType.parameters.count
                    {
                        context.emitError(
                            "wrong number of type arguments: expected "
                                + "\(forallType.parameters.count), got \(explicit.count)",
                            at: token
                        )
                    }
                }
            }
            if let actual = expression.ty.map({ resolve($0) }) {
                if !canCoerce(actual, to: expected, at: token) {
                    emitMismatch(at: token, expected: expected, found: actual)
                }
            }
        case is AST.IntegerLiteral:
            if let kind = builtinPrimitiveKind(of: expected),
               kind == .Signed || kind == .Unsigned || kind == .Float
            {
                expression.ty = expected
            } else if let actual = infer(expression, at: token) {
                if !canCoerce(actual, to: expected, at: token) {
                    emitMismatch(at: token, expected: expected, found: actual)
                }
            }
        case is AST.FloatLiteral:
            if let kind = builtinPrimitiveKind(of: expected), kind == .Float {
                expression.ty = expected
            } else if let actual = infer(expression, at: token) {
                if !canCoerce(actual, to: expected, at: token) {
                    emitMismatch(at: token, expected: expected, found: actual)
                }
            }
        default:
            if let actual = infer(expression, at: token) {
                if !canCoerce(actual, to: expected, at: token) {
                    emitMismatch(at: token, expected: expected, found: actual)
                }
            }
        }
    }

    private func builtinPrimitiveKind(of type: TrussType.TrussType) -> TIRType.PrimitiveKind? {
        guard let builtin = type as? TrussType.BuiltinType,
              let info = Builtin.typeInfos.first(where: { $0.name == builtin.name })
        else {
            return nil
        }
        return info.kind
    }

    private func callTargetName(_ expression: AST.Expression) -> String? {
        switch expression {
        case let variable as AST.Variable:
            variable.name.value
        case let member as AST.MemberAccess:
            member.member.value
        case let implicit as AST.ImplicitMemberAccess:
            implicit.name.value
        case let application as AST.GenericApplication:
            callTargetName(application.base)
        default:
            nil
        }
    }

    private func isResolved(_ type: TrussType.TrussType) -> Bool {
        switch type {
        case is TrussType.TypeVariableType, is TrussType.GenericParamType:
            false
        case let optional as TrussType.OptionalType:
            isResolved(optional.wrapped)
        case let tuple as TrussType.TupleType:
            tuple.elements.allSatisfy { isResolved($0.type) }
        case let function as TrussType.FunctionType:
            function.parameters.allSatisfy { isResolved($0.type) }
                && isResolved(function.returnType)
        case let instantiation as TrussType.GenericInstantiation:
            isResolved(instantiation.base)
                && instantiation.arguments.allSatisfy { isResolved($0) }
        case let composition as TrussType.CompositionType:
            composition.members.allSatisfy { isResolved($0) }
        case let variadic as TrussType.VariadicType:
            isResolved(variadic.base)
        default:
            true
        }
    }

    private func resolveOverloads(
        _ candidates: [Symbol.FunctionSymbol],
        arguments: [AST.LabeledArgument],
        trailingClosures: [(Token?, AST.Closure)],
        expectedReturn: TrussType.TrussType?,
        at token: Token,
        reportErrors: Bool = true,
        fallbackName: String? = nil,
        setterContext: Bool = false
    ) -> (symbol: Symbol.FunctionSymbol, type: TrussType.FunctionType)? {
        let allArguments = arguments + trailingClosures.map { label, closure in
            AST.LabeledArgument(label: label, value: closure, sourceRange: closure.sourceRange)
        }
        var matched: [(Symbol.FunctionSymbol, TrussType.FunctionType)] = []
        var constraintFailure: String? = nil
        for candidate in candidates {
            var typeMapping: [String: TrussType.TypeVariableType] = [:]
            var genericParameters: [Symbol.GenericParamSymbol] = []
            var bindingSnapshots: [(TrussType.TypeVariableType, TrussType.TrussType?)] = []
            for argument in allArguments {
                if let actual = infer(argument.value, at: token) {
                    collectTypeVariables(actual, into: &bindingSnapshots)
                }
            }
            let ty: TrussType.FunctionType
            let setterForall = setterContext ? (candidate.setterType as? TrussType.ForallType) : nil
            let setterPlain = setterContext ? (candidate.setterType as? TrussType.FunctionType) : nil
            if let forallType = setterForall ?? (setterContext ? nil : candidate.forallType) {
                genericParameters = forallType.parameters
                if let functionType = instantiate(forallType, mapping: &typeMapping)
                    as? TrussType.FunctionType
                {
                    ty = functionType
                } else {
                    continue
                }
            } else if let functionType = setterPlain
                ?? (setterContext ? nil : candidate.functionType)
            {
                genericParameters = genericParamSymbols(in: functionType)
                ty = instantiateGenerics(functionType, mapping: &typeMapping)
                    as! TrussType.FunctionType
            } else {
                continue
            }
            let signature: Symbol.FunctionSignature =
                if setterContext {
                    Symbol.FunctionSignature(
                        labels: ty.parameters.map(\.label),
                        hasDefaults: [Bool](repeating: false, count: ty.parameters.count),
                        isVararg: [Bool](repeating: false, count: ty.parameters.count),
                        isVariadic: ty.isVariadic
                    )
                } else {
                    candidate.signature
                }
            guard let argumentMapping = mapArguments(allArguments, to: signature) else {
                continue
            }
            var ok = true
            for (index, argument) in allArguments.enumerated() {
                let parameterIndex = argumentMapping[index]
                guard parameterIndex < ty.parameters.count else {
                    continue
                }
                let parameterType = ty.parameters[parameterIndex].type
                if let actual = infer(argument.value, at: token) {
                    if !canCoerce(actual, to: parameterType, at: token) {
                        ok = false
                        break
                    }
                } else {
                    check(argument.value, parameterType, at: token)
                }
            }
            if ok, !genericParameters.isEmpty {
                let (passed, failure) = checkGenericConstraints(
                    of: genericParameters, mapping: typeMapping, at: token
                )
                if !passed {
                    ok = false
                    for (variable, binding) in bindingSnapshots {
                        variable.binding = binding
                    }
                    if constraintFailure == nil {
                        constraintFailure = failure
                    }
                }
            }
            if ok {
                matched.append((candidate, ty))
            }
        }
        if let expectedReturn {
            let filtered = matched.filter {
                canCoerce($0.1.returnType, to: expectedReturn, at: token)
            }
            if !filtered.isEmpty {
                matched = filtered
            }
        }
        if matched.count > 1 {
            let nonGeneric = matched.filter { !isGenericCandidate($0.0) }
            if !nonGeneric.isEmpty {
                matched = nonGeneric
            }
        }
        let name = candidates.first?.name ?? fallbackName ?? "<unknown>"
        switch matched.count {
        case 0:
            if reportErrors {
                if let constraintFailure {
                    context.emitError(constraintFailure, at: token)
                } else {
                    emitNoExactMatch(at: token, name: name, candidates: candidates)
                }
            }
            return nil
        case 1:
            return matched[0]
        default:
            if reportErrors {
                emitAmbiguous(at: token, name: name)
            }
            return nil
        }
    }

    private func isGenericCandidate(_ symbol: Symbol.FunctionSymbol) -> Bool {
        if symbol.forallType != nil { return true }
        if let functionType = symbol.functionType,
           !genericParamSymbols(in: functionType).isEmpty
        {
            return true
        }
        return false
    }

    private func mapArguments(
        _ arguments: [AST.LabeledArgument], to signature: Symbol.FunctionSignature
    ) -> [Int]? {
        let paramCount = signature.labels.count
        var used = [Bool](repeating: false, count: paramCount)
        var mapping: [Int] = []
        var varargIndex: Int?

        for argument in arguments {
            if let label = argument.label?.value {
                var found: Int?
                for (i, paramLabel) in signature.labels.enumerated()
                    where paramLabel == label && !used[i]
                {
                    found = i
                    break
                }
                guard let index = found else { return nil }
                used[index] = true
                mapping.append(index)
                if signature.isVararg[index] {
                    varargIndex = index
                }
            } else if let varargIndex {
                mapping.append(varargIndex)
            } else {
                var found: Int?
                for (i, isUsed) in used.enumerated() where !isUsed {
                    found = i
                    break
                }
                guard let index = found else { return nil }
                used[index] = true
                mapping.append(index)
                if signature.isVararg[index] {
                    varargIndex = index
                }
            }
        }

        for (i, hasDefault) in signature.hasDefaults.enumerated() {
            if !hasDefault, !used[i], !signature.isVararg[i] {
                return nil
            }
        }
        return mapping
    }

    private func instantiateGenerics(
        _ type: TrussType.TrussType,
        mapping: inout [String: TrussType.TypeVariableType]
    ) -> TrussType.TrussType {
        replacingGenericParam(type) { genericParam in
            if let existing = mapping[genericParam.name] { return existing }
            let fresh = freshTypeVariable()
            mapping[genericParam.name] = fresh
            return fresh
        }
    }

    private func instantiate(
        _ forall: TrussType.ForallType,
        mapping: inout [String: TrussType.TypeVariableType]
    ) -> TrussType.TrussType {
        for param in forall.parameters {
            mapping[param.name] = freshTypeVariable()
        }
        return replacingGenericParam(forall.body) { genericParam in
            mapping[genericParam.name] ?? genericParam
        }
    }

    private func checkMatchExhaustive(
        subjectType: TrussType.TrussType?, cases: [AST.Match.Case], at token: Token
    ) {
        guard let subjectType else { return }
        let resolved = resolve(subjectType)
        let nominal = (resolved as? TrussType.GenericInstantiation)?.base
            ?? resolved as? TrussType.NominalType
        guard let nominal, let symbol = nominal.symbol as? Symbol.EnumSymbol else { return }
        let enumCaseNames = Set(
            symbol.scope.values.compactMap { $0.value.first as? Symbol.CaseSymbol }.map(\.name)
        )
        guard !enumCaseNames.isEmpty else { return }
        var covered: Set<String> = []
        var hasWildcard = false
        for caseItem in cases {
            for pattern in caseItem.patterns {
                if pattern is AST.WildcardPattern || pattern is AST.BindingPattern {
                    hasWildcard = true
                } else if let caseName = enumCaseName(of: pattern, in: enumCaseNames) {
                    covered.insert(caseName)
                } else if pattern is AST.Variable {
                    hasWildcard = true
                }
            }
        }
        if hasWildcard { return }
        let missing = enumCaseNames.subtracting(covered)
        if !missing.isEmpty {
            context.emitError(
                "match is not exhaustive: missing case(s) "
                    + missing.sorted().map { "'\($0)'" }.joined(separator: ", "),
                at: token
            )
        }
    }

    private func enumCaseName(of pattern: AST.Expression, in enumCaseNames: Set<String>) -> String? {
        switch pattern {
        case let call as AST.Call:
            if let implicit = call.callee as? AST.ImplicitMemberAccess {
                return implicit.name.value
            }
            if let member = call.callee as? AST.MemberAccess {
                return member.member.value
            }
            if let variable = call.callee as? AST.Variable,
               enumCaseNames.contains(variable.name.value)
            {
                return variable.name.value
            }
        case let member as AST.MemberAccess:
            if enumCaseNames.contains(member.member.value) {
                return member.member.value
            }
        case let implicit as AST.ImplicitMemberAccess:
            if enumCaseNames.contains(implicit.name.value) {
                return implicit.name.value
            }
        case let variable as AST.Variable:
            if enumCaseNames.contains(variable.name.value) {
                return variable.name.value
            }
        default:
            break
        }
        return nil
    }

    private func join(
        _ types: [TrussType.TrussType], at token: Token
    ) -> TrussType.TrussType? {
        guard let first = types.first else { return nil }
        var result = first
        for type in types.dropFirst() {
            if unify(result, type, at: token) {
                continue
            }
            if canCoerce(result, to: type, at: token) {
                result = type
                continue
            }
            if canCoerce(type, to: result, at: token) {
                continue
            }
            emitMismatch(at: token, expected: result, found: type)
            return nil
        }
        return result
    }

    private func checkConstraints(
        for variable: TrussType.TypeVariableType, at token: Token
    ) {
        guard let binding = resolve(variable) as? TrussType.NominalType else {
            return
        }
        for frame in constraintFrames {
            guard let protocols = frame[variable.id], !protocols.isEmpty else { continue }
            for protocolType in protocols {
                if !conformsTo(binding, protocolType) {
                    context.emitError(
                        "type '\(typeText(binding))' does not conform to protocol "
                            + "'\(protocolType.name)'",
                        at: token
                    )
                }
            }
        }
    }

    private func checkGenericArguments(
        of nominal: TrussType.NominalType,
        arguments: [TrussType.TrussType],
        at token: Token
    ) {
        guard let symbol = nominal.symbol else { return }
        let parameters = symbol.scope.types.values.compactMap {
            $0 as? Symbol.GenericParamSymbol
        }
        for (index, argument) in arguments.enumerated() where index < parameters.count {
            let parameter = parameters[index]
            guard !parameter.constraints.isEmpty else { continue }
            for constraint in parameter.constraints {
                switch constraint {
                case let .conformance(protocolType):
                    if !canCoerce(argument, to: protocolType, at: token) {
                        context.emitError(
                            "type '\(typeText(argument))' does not conform to protocol "
                                + "'\(typeText(protocolType))'",
                            at: token
                        )
                    }
                case let .equality(target):
                    let instantiated = replacingGenericParam(target) { genericParam in
                        if let targetIndex = parameters.firstIndex(where: {
                            $0.name == genericParam.name
                        }), targetIndex < arguments.count {
                            return arguments[targetIndex]
                        }
                        return genericParam
                    }
                    if !unify(argument, instantiated, at: token) {
                        emitMismatch(at: token, expected: instantiated, found: argument)
                    }
                }
            }
        }
    }

    private func checkWitnesses(of symbol: Symbol.NominalTypeSymbol, at token: Token) {
        for protocolSymbol in symbol.conformances {
            var missing: [String] = []
            var visited: Set<Id.SymbolId> = []
            collectMissingWitnesses(
                protocolSymbol, typeSymbol: symbol, missing: &missing, visited: &visited
            )
            if !missing.isEmpty {
                context.emitError(
                    "type '\(symbol.name)' does not conform to protocol "
                        + "'\(protocolSymbol.name)': missing witness(es) "
                        + missing.map { "'\($0)'" }.joined(separator: ", "),
                    at: token
                )
            }
        }
    }

    private func collectMissingWitnesses(
        _ protocolSymbol: Symbol.ProtocolSymbol,
        typeSymbol: Symbol.NominalTypeSymbol,
        missing: inout [String],
        visited: inout Set<Id.SymbolId>
    ) {
        guard visited.insert(protocolSymbol.id).inserted else { return }
        for (name, symbols) in protocolSymbol.scope.values {
            for symbol in symbols {
                let implemented: Bool
                switch symbol {
                case is Symbol.FunctionSymbol:
                    implemented = hasMember(
                        name, matching: { $0 is Symbol.FunctionSymbol }, in: typeSymbol
                    )
                case is Symbol.VariableSymbol:
                    implemented = hasMember(
                        name, matching: { $0 is Symbol.VariableSymbol }, in: typeSymbol
                    )
                default:
                    continue
                }
                if !implemented, !missing.contains(name) {
                    missing.append(name)
                }
            }
        }
        for (name, symbol) in protocolSymbol.scope.types {
            if symbol is Symbol.AssociatedTypeSymbol, !hasTypeMember(name, in: typeSymbol),
               !missing.contains(name)
            {
                missing.append(name)
            }
        }
        for inherited in protocolSymbol.conformances {
            collectMissingWitnesses(
                inherited, typeSymbol: typeSymbol, missing: &missing, visited: &visited
            )
        }
    }

    private func hasMember(
        _ name: String,
        matching predicate: (Symbol.Symbol) -> Bool,
        in typeSymbol: Symbol.NominalTypeSymbol
    ) -> Bool {
        var current: Symbol.NominalTypeSymbol? = typeSymbol
        while let currentType = current {
            if currentType.scope.values[name]?.contains(where: predicate) == true {
                return true
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return false
    }

    private func hasTypeMember(
        _ name: String, in typeSymbol: Symbol.NominalTypeSymbol
    ) -> Bool {
        var current: Symbol.NominalTypeSymbol? = typeSymbol
        while let currentType = current {
            if currentType.scope.types[name] != nil {
                return true
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return false
    }

    private func collectTypeVariables(
        _ type: TrussType.TrussType,
        into snapshots: inout [(TrussType.TypeVariableType, TrussType.TrussType?)]
    ) {
        if let variable = type as? TrussType.TypeVariableType {
            if !snapshots.contains(where: { $0.0 === variable }) {
                snapshots.append((variable, variable.binding))
            }
            if let binding = variable.binding {
                collectTypeVariables(binding, into: &snapshots)
            }
            return
        }
        switch type {
        case let optional as TrussType.OptionalType:
            collectTypeVariables(optional.wrapped, into: &snapshots)
        case let tuple as TrussType.TupleType:
            for element in tuple.elements {
                collectTypeVariables(element.type, into: &snapshots)
            }
        case let function as TrussType.FunctionType:
            for parameter in function.parameters {
                collectTypeVariables(parameter.type, into: &snapshots)
            }
            collectTypeVariables(function.returnType, into: &snapshots)
        case let generic as TrussType.GenericInstantiation:
            for argument in generic.arguments {
                collectTypeVariables(argument, into: &snapshots)
            }
        case let composition as TrussType.CompositionType:
            for member in composition.members {
                collectTypeVariables(member, into: &snapshots)
            }
        default:
            break
        }
    }

    private func checkGenericConstraints(
        of parameters: [Symbol.GenericParamSymbol],
        mapping: [String: TrussType.TypeVariableType],
        at token: Token
    ) -> (Bool, String?) {
        for parameter in parameters {
            guard let variable = mapping[parameter.name] else { continue }
            let resolvedBound = resolve(variable)
            let bound: TrussType.NominalType? =
                if let nominal = resolvedBound as? TrussType.NominalType {
                    nominal
                } else if let generic = resolvedBound as? TrussType.GenericInstantiation {
                    generic.base
                } else {
                    nil
                }
            guard let bound else { continue }
            for constraint in parameter.constraints {
                switch constraint {
                case let .conformance(protocolType):
                    if !canCoerce(bound, to: protocolType, at: token) {
                        return (
                            false,
                            "type '\(typeText(bound))' does not conform to protocol "
                                + "'\(typeText(protocolType))'"
                        )
                    }
                case let .equality(target):
                    let instantiated = replacingGenericParam(target) { genericParam in
                        mapping[genericParam.name] ?? genericParam
                    }
                    if !unify(resolvedBound, instantiated, at: token) {
                        return (
                            false,
                            "expected '\(typeText(instantiated))', found '\(typeText(resolvedBound))'"
                        )
                    }
                }
            }
        }
        return (true, nil)
    }

    private func genericParamSymbols(
        in type: TrussType.TrussType
    ) -> [Symbol.GenericParamSymbol] {
        var seen: Set<ObjectIdentifier> = []
        var result: [Symbol.GenericParamSymbol] = []
        _ = replacingGenericParam(type) { genericParam in
            if let symbol = genericParam.symbol {
                let identifier = ObjectIdentifier(symbol)
                if !seen.contains(identifier) {
                    seen.insert(identifier)
                    result.append(symbol)
                }
            }
            return genericParam
        }
        return result
    }

    private func conformsTo(_ type: TrussType.NominalType, _ protocolType: TrussType.ProtocolType)
        -> Bool
    {
        guard let symbol = type.symbol else {
            return false
        }
        if symbol.conformances.contains(where: { $0.typeId == protocolType.id }) {
            return true
        }
        if let classSymbol = symbol as? Symbol.ClassSymbol,
           let superclass = classSymbol.superclass,
           let superclassType = superclass.typeId.flatMap({ context.typeTable[$0] })
           as? TrussType.NominalType
        {
            return conformsTo(superclassType, protocolType)
        }
        return false
    }

    private func superclassChain(of type: TrussType.ClassType) -> [TrussType.ClassType] {
        guard let classSymbol = type.symbol as? Symbol.ClassSymbol,
              let superclass = classSymbol.superclass,
              let superclassType = superclass.typeId.flatMap({ context.typeTable[$0] })
              as? TrussType.ClassType
        else {
            return []
        }
        return [superclassType] + superclassChain(of: superclassType)
    }
}
