import SwiftBetterDiagnostic
import TrussCore

public final class TypeResolver: AST.Visitor {
    private let context: Context
    private var collectingTypealiases = false
    private var typealiasDecls: [Id.SymbolId: AST.TypeAliasDecl] = [:]
    private var resolvingTypealiases: Set<Id.SymbolId> = []
    private var scopeStack: [Scope] = []
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    private var functionReturnTypes: [TrussType.TrussType] = []
    private var constraintFrames: [[Id.TypeVariableId: [TrussType.ProtocolType]]] = []
    private var closureParameterTypes: [[TrussType.TrussType]] = []
    private var nextTypeVariableId: UInt64 = 0
    private var sourceId: Id.SourceId = .init(id: 0)

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        sourceId = program.id
        collectingTypealiases = true
        withScope(program.packageSymbol?.scope) {
            super.visitProgram(program, additional: additional)
        }
        collectingTypealiases = false
        withScope(program.packageSymbol?.scope) {
            super.visitProgram(program, additional: additional)
        }
        return nil
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
            super.visitStructDecl(structDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        withTypeContext(classDecl.symbol) {
            super.visitClassDecl(classDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        withTypeContext(enumDecl.symbol) {
            super.visitEnumDecl(enumDecl, additional: additional)
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
            super.visitActorDecl(actorDecl, additional: additional)
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
        for element in enumCaseDecl.elements {
            for associatedValue in element.associatedValues {
                _ = evaluate(associatedValue.typeExpression)
            }
        }
        return super.visitEnumCaseDecl(enumCaseDecl, additional: additional)
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = functionDecl.symbol else { return nil }
        withScope(symbol.scope) {
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
                visitFunctionBody(
                    functionDecl.body, expectedReturn: returnType, at: functionDecl.name
                )
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
        withScope(symbol.scope) {
            let parameterTypes = fillParameterTypes(initDecl.parameters, into: symbol)
            let functionType = functionType(
                labels: initDecl.parameters.map { $0.label?.value },
                parameterTypes: parameterTypes,
                asyncToken: initDecl.asyncToken,
                throwsClause: initDecl.throwsClause,
                returnType: TrussType.VoidType.INSTANCE
            )
            symbol.functionType = functionType
            withFunctionReturnType(TrussType.VoidType.INSTANCE) {
                visitFunctionBody(
                    .Block(initDecl.body), expectedReturn: nil, at: initDecl.token
                )
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
        withScope(symbol.scope) {
            let parameterTypes = fillParameterTypes(subscriptDecl.parameters, into: symbol)
            let returnType: TrussType.TrussType = evaluate(subscriptDecl.returnType)
            let functionType = functionType(
                labels: subscriptDecl.parameters.map { $0.label?.value },
                parameterTypes: parameterTypes,
                asyncToken: subscriptDecl.asyncToken,
                throwsClause: subscriptDecl.throwsClause,
                returnType: returnType
            )
            symbol.functionType = functionType
            withFunctionReturnType(returnType) {
                visitFunctionBody(
                    .Block(subscriptDecl.body), expectedReturn: returnType,
                    at: subscriptDecl.token
                )
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
        let type: TrussType.TrussType? =
            if let typeExpr = variableDecl.typeExpression {
                evaluate(typeExpr)
            } else {
                nil
            }
        if let type {
            variableDecl.symbol?.type = type
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
        _ = infer(throwStatement.expression, at: throwStatement.token)
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil)
        -> Any?
    {
        withScope(whileStatement.scope) {
            _ = infer(whileStatement.condition, at: whileStatement.token)
            super.visitWhile(whileStatement, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        withScope(repeatWhile.scope) {
            _ = infer(repeatWhile.condition, at: repeatWhile.token)
            super.visitRepeatWhile(repeatWhile, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
        _ = infer(forStatement.sequence, at: forStatement.token)
        if let whereClause = forStatement.whereClause {
            _ = infer(whereClause, at: forStatement.token)
        }
        for statement in forStatement.body {
            visit(statement)
        }
        return nil
    }

    private func visitFunctionBody(
        _ body: AST.FunctionDecl.Body?, expectedReturn: TrussType.TrussType?, at token: Token
    ) {
        guard let body else { return }
        switch body {
        case let .Block(statements):
            for statement in statements {
                visit(statement)
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
            switch accessor.body {
            case let .Block(statements):
                for statement in statements {
                    visit(statement)
                }
                if let last = statements.last as? AST.ExpressionStatement {
                    check(last.expression, type, at: accessor.token ?? token)
                } else if join([TrussType.VoidType.INSTANCE, type], at: token) == nil {
                    emitMismatch(at: token, expected: type, found: TrussType.VoidType.INSTANCE)
                }
            case let .Expression(expression):
                check(expression, type, at: accessor.token ?? token)
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
        }
        return types
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

    private func functionType(
        labels: [String?],
        parameterTypes: [TrussType.TrussType],
        asyncToken: Token?,
        throwsClause: AST.ThrowsClause?,
        returnType: TrussType.TrussType
    ) -> TrussType.FunctionType {
        TrussType.FunctionType(
            parameters: zip(labels, parameterTypes).map { label, type in
                TrussType.FunctionType.Parameter(label: label, type: type)
            },
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
        case let parenthetical as AST.ParentheticalExpression:
            result = evaluate(parenthetical.inner)
        case let optionalType as AST.OptionalType:
            let wrapped = evaluate(optionalType.wrappedType)
            result =
                wrapped is TrussType.ErrorType
                    ? TrussType.ErrorType.INSTANCE : TrussType.OptionalType(wrapped)
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
                    asyncToken: closureType.asyncToken,
                    throwsClause: closureType.throwsClause,
                    returnType: returnType
                )
            }
        case let tupleExpression as AST.TupleExpression:
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
        case let genericApplication as AST.GenericApplication:
            result = evaluateGenericApplication(genericApplication)
        case let sequential as AST.SequentialExpression
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

    private func evaluateSymbol(_ symbol: Symbol.Symbol) -> TrussType.TrussType? {
        if let nominal = symbol as? Symbol.NominalTypeSymbol {
            return nominal.typeId.flatMap { context.typeTable[$0] }
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
        return TrussType.GenericInstantiation(base: base, arguments: arguments)
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

    private func freshTypeVariable(_ name: String? = nil) -> TrussType.TypeVariableType {
        let variable = TrussType.TypeVariableType(Id.TypeVariableId(id: nextTypeVariableId), name)
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

    private func memberType(of name: String, in type: TrussType.TrussType?) -> TrussType.TrussType? {
        let base = (type as? TrussType.OptionalType)?.wrapped ?? type
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
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return nil
    }

    private func genericParameterNames(of symbol: Symbol.NominalTypeSymbol) -> [String] {
        symbol.scope.types.values.compactMap { $0 as? Symbol.GenericParamSymbol }.map(\.name)
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
        if let sequential = callee as? AST.SequentialExpression,
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
        case let optional as TrussType.OptionalType:
            return "\(typeText(optional.wrapped))?"
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
            variable.binding = b
            return true
        }
        if let variable = b as? TrussType.TypeVariableType {
            guard !occurs(variable, in: a) else {
                emitMismatch(at: token, expected: a, found: b)
                return false
            }
            variable.binding = a
            return true
        }
        switch (a, b) {
        case let (l as TrussType.NominalType, r as TrussType.NominalType):
            return l.id == r.id
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
        if let optional = expected as? TrussType.OptionalType {
            return canCoerce(actual, to: optional.wrapped, at: token)
        }
        if let variadic = expected as? TrussType.VariadicType {
            return canCoerce(actual, to: variadic.base, at: token)
        }
        if let actualClass = actual as? TrussType.ClassType,
           let expectedClass = expected as? TrussType.ClassType
        {
            for superclass in superclassChain(of: actualClass) {
                if unify(superclass, expectedClass, at: token) {
                    return true
                }
            }
        }
        if let expectedProtocol = expected as? TrussType.ProtocolType,
           let actualNominal = actual as? TrussType.NominalType
        {
            return conformsTo(actualNominal, expectedProtocol)
        }
        if let expectedComposition = expected as? TrussType.CompositionType,
           let actualNominal = actual as? TrussType.NominalType
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

    private func emitMismatch(
        at token: Token, expected: TrussType.TrussType?, found: TrussType.TrussType?
    ) {
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
                let calleeMemberFailed: Bool = if let member = call.callee as? AST.MemberAccess {
                    member.ty == nil
                } else {
                    false
                }
                if !calleeMemberFailed,
                   let resolved = resolveOverloads(
                       call.overloads ?? [], arguments: call.arguments,
                       trailingClosures: call.trailingClosures,
                       expectedReturn: nil, at: token
                   )
                {
                    call.symbol = resolved.symbol
                    if resolved.symbol.name == "init",
                       let calleeVariable = call.callee as? AST.Variable,
                       let typeSymbol = calleeVariable.symbol as? Symbol.NominalTypeSymbol,
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
            return expression.ty.map { resolve($0) }
        case let variable as AST.Variable:
            if let symbol = variable.symbol {
                expression.ty = valueType(of: symbol)
            } else if variable.overloads?.count == 1, let overload = variable.overloads?.first {
                expression.ty = overload.forallType ?? overload.functionType
            } else if let overloads = variable.overloads, overloads.count > 1 {
                emitAmbiguous(at: variable.name, name: variable.name.value)
            } else {
                context.emitError(
                    "cannot find '\(variable.name.value)' in this scope", at: variable.name
                )
            }
        case let tupleExpression as AST.TupleExpression:
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
            _ = infer(ifExpression.condition, at: token)
            for statement in ifExpression.then {
                visit(statement)
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
        case let matchExpression as AST.Match:
            _ = infer(matchExpression.subject, at: token)
            var caseTypes: [TrussType.TrussType] = []
            for caseItem in matchExpression.cases {
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
        case let doExpression as AST.Do:
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
            for catchClause in doExpression.catches {
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
        case let memberAccess as AST.MemberAccess:
            _ = infer(memberAccess.object, at: token)
            if let symbol = memberAccess.symbol {
                expression.ty = valueType(of: symbol)
            } else if let overloads = memberAccess.overloads, overloads.count == 1,
                      let overload = overloads.first
            {
                expression.ty = overload.forallType ?? overload.functionType
            } else if let ty = memberType(of: memberAccess.member.value, in: memberAccess.object.ty) {
                expression.ty = ty
            }
            if memberAccess.isOptional, let ty = expression.ty {
                expression.ty = TrussType.OptionalType(ty)
            }
            if expression.ty == nil, let objectType = memberAccess.object.ty {
                emitNoMember(
                    at: memberAccess.member, type: typeText(objectType),
                    member: memberAccess.member.value
                )
            }
        case let implicitMemberAccess as AST.ImplicitMemberAccess:
            if let typeId = typeStack.last?.typeId, let selfType = context.typeTable[typeId] {
                if let member = memberType(of: implicitMemberAccess.name.value, in: selfType) {
                    expression.ty = member
                } else {
                    emitNoMember(
                        at: implicitMemberAccess.token, type: typeText(selfType),
                        member: implicitMemberAccess.name.value
                    )
                }
            }
        case let subscriptExpression as AST.Subscript:
            _ = infer(subscriptExpression.base, at: token)
            if subscriptExpression.symbol == nil {
                if let resolved = resolveOverloads(
                    subscriptExpression.overloads ?? [], arguments: subscriptExpression.arguments, trailingClosures: [],
                    expectedReturn: nil, at: token
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
        case let parentheticalExpression as AST.ParentheticalExpression:
            expression.ty = infer(parentheticalExpression.inner, at: token)
        case let castExpression as AST.CastExpression:
            if castExpression.kind == .Is {
                _ = infer(castExpression.left, at: token)
            } else {
                expression.ty = evaluate(castExpression.right)
                if castExpression.kind == .OptionalAs {
                    expression.ty = TrussType.OptionalType(expression.ty!)
                }
            }
        case let sequential as AST.SequentialExpression:
            for operand in sequential.operands {
                _ = infer(operand, at: token)
            }
            for op in sequential.ops {
                if lookupOperatorFunctions(op.value).isEmpty {
                    emitOperatorNoImplementation(at: op, name: op.value)
                }
            }
            expression.ty = sequential.operands.last?.ty
        case let tryExpression as AST.TryExpression:
            expression.ty = infer(tryExpression.expression, at: token)
            if let call = tryExpression.expression as? AST.Call,
                let symbol = call.symbol,
                symbol.functionType?.isThrowing == false
            {
                context.emitError(
                    "try used on call to non-throwing function", at: tryExpression.token
                )
            }
        case let awaitExpression as AST.AwaitExpression:
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
            if let variable = genericApplication.base as? AST.Variable,
               let typeSymbol = variable.symbol as? Symbol.NominalTypeSymbol,
               let typeId = typeSymbol.typeId,
               let nominal = context.typeTable[typeId] as? TrussType.NominalType
            {
                var arguments: [TrussType.TrussType] = []
                var ok = true
                for argument in genericApplication.genericArguments {
                    if let argumentVariable = argument as? AST.Variable,
                       let argumentSymbol = argumentVariable.symbol as? Symbol.NominalTypeSymbol,
                       let argumentTypeId = argumentSymbol.typeId,
                       let argumentType = context.typeTable[argumentTypeId]
                    {
                        arguments.append(argumentType)
                    } else if let argumentVariable = argument as? AST.Variable,
                        argumentVariable.symbol == nil
                    {
                        context.emitError(
                            "cannot find type '\(argumentVariable.name.value)'",
                            at: argumentVariable.name
                        )
                        ok = false
                        break
                    } else {
                        ok = false
                        break
                    }
                }
                if ok {
                    expression.ty = TrussType.GenericInstantiation(
                        base: nominal, arguments: arguments
                    )
                }
            } else if let variable = genericApplication.base as? AST.Variable {
                context.emitError(
                    "cannot find type '\(variable.name.value)'", at: variable.name
                )
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
        case is AST.SelfTypeExpression:
            if let typeId = typeStack.last?.typeId {
                expression.ty = context.typeTable[typeId]
            } else {
                context.emitError(
                    "cannot use 'Self' outside of a type context", at: token
                )
            }
        case let keyPathExpression as AST.KeyPathExpression:
            if let root = keyPathExpression.root {
                _ = infer(root, at: token)
            }
        case is AST.VoidLiteral:
            expression.ty = TrussType.VoidType.INSTANCE
        case let binary as AST.Binary:
            _ = infer(binary.left, at: token)
            _ = infer(binary.right, at: token)
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
                    expression.ty = functionType(
                        labels: signature.parameters.map { $0.label?.value },
                        parameterTypes: parameterTypes,
                        asyncToken: signature.asyncToken,
                        throwsClause: signature.throwsClause,
                        returnType: returnType
                    )
                }
            } else {
                emitMissingAnnotation(at: syntheticToken(for: closure), kind: "closure", name: "")
            }
        default:
            expression.ty = nil
        }
        return expression.ty.map { resolve($0) }
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
            if let lastStatement = closure.body.last as? AST.ExpressionStatement {
                check(lastStatement.expression, functionType.returnType, at: token)
            }
            closureParameterTypes.removeLast()
            expression.ty = functionType
        case let tupleExpression as AST.TupleExpression:
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
                    trailingClosures: call.trailingClosures, expectedReturn: expected, at: token
                ) {
                    call.symbol = resolved.symbol
                    expression.ty = resolved.type.returnType
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
        default:
            if let actual = infer(expression, at: token) {
                if !canCoerce(actual, to: expected, at: token) {
                    emitMismatch(at: token, expected: expected, found: actual)
                }
            }
        }
    }

    private func resolveOverloads(
        _ candidates: [Symbol.FunctionSymbol],
        arguments: [AST.LabeledArgument],
        trailingClosures: [(Token?, AST.Closure)],
        expectedReturn: TrussType.TrussType?,
        at token: Token,
        reportErrors: Bool = true
    ) -> (symbol: Symbol.FunctionSymbol, type: TrussType.FunctionType)? {
        let allArguments = arguments + trailingClosures.map { label, closure in
            AST.LabeledArgument(label: label, value: closure, sourceRange: closure.sourceRange)
        }
        var matched: [(Symbol.FunctionSymbol, TrussType.FunctionType)] = []
        for candidate in candidates {
            let ty: TrussType.FunctionType
            if let forallType = candidate.forallType {
                if let functionType = instantiate(forallType) as? TrussType.FunctionType {
                    ty = functionType
                } else {
                    continue
                }
            } else if let functionType = candidate.functionType {
                ty = instantiateGenerics(functionType) as! TrussType.FunctionType
            } else {
                continue
            }
            guard let mapping = mapArguments(allArguments, to: candidate.signature) else {
                continue
            }
            var ok = true
            for (index, argument) in allArguments.enumerated() {
                let parameterIndex = mapping[index]
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
        let name = candidates.first?.name ?? "<unknown>"
        switch matched.count {
        case 0:
            if reportErrors {
                emitNoExactMatch(at: token, name: name, candidates: candidates)
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

    private func instantiateGenerics(_ type: TrussType.TrussType) -> TrussType.TrussType {
        var mapping: [String: TrussType.TypeVariableType] = [:]
        return replacingGenericParam(type) { genericParam in
            if let existing = mapping[genericParam.name] { return existing }
            let fresh = freshTypeVariable()
            mapping[genericParam.name] = fresh
            return fresh
        }
    }

    private func instantiate(_ forall: TrussType.ForallType) -> TrussType.TrussType {
        var mapping: [String: TrussType.TypeVariableType] = [:]
        for param in forall.parameters {
            mapping[param.name] = freshTypeVariable()
        }
        return replacingGenericParam(forall.body) { genericParam in
            mapping[genericParam.name] ?? genericParam
        }
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
