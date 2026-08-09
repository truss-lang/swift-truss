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
    private var nextTypeVariableId: UInt64 = 0

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
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
            }
            for accessor in variableDecl.accessors {
                checkAccessor(accessor, type, at: variableDecl.name)
            }
        } else if let initializer = variableDecl.initializer {
            let inferred = infer(initializer)
            variableDecl.symbol?.type = inferred
            for accessor in variableDecl.accessors {
                if let inferred {
                    checkAccessor(accessor, inferred, at: variableDecl.name)
                } else {
                    visitAccessorStatements(accessor)
                }
            }
        } else {
            for accessor in variableDecl.accessors {
                visitAccessorStatements(accessor)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
    ) -> Any? {
        _ = infer(expressionStatement.expression)
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
            _ = infer(value)
        }
        return nil
    }

    @discardableResult
    public override func visitThrow(_ throwStatement: AST.Throw, additional: Any? = nil)
        -> Any?
    {
        _ = infer(throwStatement.expression)
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil)
        -> Any?
    {
        withScope(whileStatement.scope) {
            super.visitWhile(whileStatement, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        withScope(repeatWhile.scope) {
            super.visitRepeatWhile(repeatWhile, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
        _ = infer(forStatement.sequence)
        if let whereClause = forStatement.whereClause {
            _ = infer(whereClause)
        }
        for statement in forStatement.body {
            visit(statement)
        }
        return nil
    }

    @discardableResult
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        variable.ty = evaluateVariable(variable)
        return nil
    }

    private func visitFunctionBody(
        _ body: AST.FunctionDecl.Body?, expectedReturn: TrussType.TrussType?, at token: Token
    ) {
        guard let body else { return }
        switch body {
        case .Block(let statements):
            for statement in statements {
                visit(statement)
            }
        case .Expression(let expression):
            if let expectedReturn {
                check(expression, expectedReturn, at: token)
            } else {
                _ = infer(expression)
            }
        }
    }

    private func checkAccessor(
        _ accessor: AST.Accessor, _ type: TrussType.TrussType, at token: Token
    ) {
        withScope(accessor.scope) {
            switch accessor.body {
            case .Block(let statements):
                for statement in statements {
                    visit(statement)
                }
            case .Expression(let expression):
                check(expression, type, at: accessor.token ?? token)
            }
        }
    }

    private func visitAccessorStatements(_ accessor: AST.Accessor) {
        withScope(accessor.scope) {
            switch accessor.body {
            case .Block(let statements):
                for statement in statements {
                    visit(statement)
                }
            case .Expression(let expression):
                _ = infer(expression)
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
            protocolType)
    }

    private func lookupOperatorFunctions(_ name: String) -> [Symbol.FunctionSymbol] {
        for scope in scopeStack.reversed() {
            if let entries = scope.values[name] {
                return entries.compactMap { $0 as? Symbol.FunctionSymbol }
            }
        }
        return []
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

    private func resolve(_ type: TrussType.TrussType) -> TrussType.TrussType {
        guard let variable = type as? TrussType.TypeVariableType else {
            return type
        }
        guard let binding = variable.binding else {
            return variable
        }
        guard binding === variable else {
            return variable
        }
        let root = resolve(binding)
        variable.binding = root
        return type
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
        case (let l as TrussType.NominalType, let r as TrussType.NominalType):
            return l.id == r.id
        case (let l as TrussType.TupleType, let r as TrussType.TupleType):
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
        case (let l as TrussType.FunctionType, let r as TrussType.FunctionType):
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
        case (let l as TrussType.VariadicType, let r as TrussType.VariadicType):
            return unify(l.base, r.base, at: token)
        case (let l as TrussType.CompositionType, let r as TrussType.CompositionType):
            for (lm, rm) in zip(l.members, r.members) {
                guard unify(lm, rm, at: token) else {
                    return false
                }
            }
            return true
        case (let l as TrussType.OptionalType, let r as TrussType.OptionalType):
            return unify(l.wrapped, r.wrapped, at: token)
        case (let l as TrussType.GenericInstantiation, let r as TrussType.GenericInstantiation):
            guard unify(l.base, r.base, at: token) else {
                return false
            }
            for (la, ra) in zip(l.arguments, r.arguments) {
                guard unify(la, ra, at: token) else {
                    return false
                }
            }
            return true
        case (let l as TrussType.ForallType, let r as TrussType.ForallType):
            guard l.parameters.count == r.parameters.count else {
                return false
            }
            for (lp, rp) in zip(l.parameters, r.parameters) {
                guard lp.name == rp.name else {
                    return false
                }
            }
            return unify(l.body, r.body, at: token)
        case (let l as TrussType.GenericParamType, let r as TrussType.GenericParamType):
            return l.name == r.name
        default:
            break
        }
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

    private func coerce(
        _ actual: TrussType.TrussType, to expected: TrussType.TrussType, at token: Token
    ) -> Bool {
        // TODO: try unify first; on failure try conversions: optional promotion T->T?, inheritance C->superclass, Never->any, concrete->protocol existential (conformances + superclass chain); emitMismatch on failure
        unify(actual, expected, at: token)
    }

    private func infer(_ expression: AST.Expression) -> TrussType.TrussType? {
        // TODO: per-expression rules; write result to expression.ty; variables look up symbol.type; calls go through resolveOverloads; member resolution via type scope; closures/literals/operators per plan
        expression.ty = nil
        return nil
    }

    private func check(
        _ expression: AST.Expression, _ expected: TrussType.TrussType, at token: Token
    ) {
        // TODO: bidirectional downward; expected type permeates tuple/closure/array-dictionary; leaves go through coerce; write result to expression.ty
        _ = infer(expression)
    }

    private func resolveOverloads(
        _ candidates: [Symbol.FunctionSymbol],
        arguments: [AST.LabeledArgument],
        trailingClosures: [(Token?, AST.Closure)],
        expectedReturn: TrussType.TrussType?,
        at token: Token
    ) -> Symbol.FunctionSymbol? {
        // TODO: filter by count/labels -> try each candidate bidirectionally (parameter check + return unify, generic candidates instantiated) -> single winner; no match emitNoExactMatch; multiple winners emitAmbiguous
        nil
    }

    private func instantiate(_ forall: TrussType.ForallType) -> TrussType.TrussType {
        // TODO: replace GenericParamType in body with fresh type variables (in parameter order)
        forall.body
    }

    private func join(
        _ types: [TrussType.TrussType], at token: Token
    ) -> TrussType.TrussType? {
        // TODO: unify each in turn (fall back to coerce on failure); caller supplies Void for if-without-else
        types.first
    }

    private func checkConstraints(for variable: TrussType.TypeVariableType) {
        // TODO: after variable resolves, verify constraints in current frame (conformances + superclass chain); emitMismatch if not satisfied
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
