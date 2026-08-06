import TrussCore

public final class TypeResolver: AST.Visitor {
    private let context: Context
    private var collectingTypealiases = false
    private var typealiasDecls: [Id.SymbolId: AST.TypeAliasDecl] = [:]
    private var resolvingTypealiases: Set<Id.SymbolId> = []
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        collectingTypealiases = true
        super.visitProgram(program, additional: additional)
        collectingTypealiases = false
        return super.visitProgram(program, additional: additional)
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
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        let type = evaluate(variableDecl.typeExpression)
        variableDecl.symbol?.type = type
        return super.visitVariableDecl(variableDecl, additional: additional)
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = functionDecl.symbol else {
            return super.visitFunctionDecl(functionDecl, additional: additional)
        }
        fillParameterTypes(functionDecl.parameters, into: symbol)
        symbol.functionType = functionType(
            labels: functionDecl.parameters.map { $0.label?.value },
            parameterTypes: functionDecl.parameters.map(\.type),
            asyncToken: functionDecl.asyncToken,
            throwsClause: functionDecl.throwsClause,
            returnType: functionDecl.returnTypeExpression,
            fallbackReturnType: TrussType.VoidType.INSTANCE
        )
        return super.visitFunctionDecl(functionDecl, additional: additional)
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = initDecl.symbol else {
            return super.visitInitDecl(initDecl, additional: additional)
        }
        fillParameterTypes(initDecl.parameters, into: symbol)
        symbol.functionType = functionType(
            labels: initDecl.parameters.map { $0.label?.value },
            parameterTypes: initDecl.parameters.map(\.type),
            asyncToken: initDecl.asyncToken,
            throwsClause: initDecl.throwsClause,
            returnType: nil,
            fallbackReturnType: TrussType.VoidType.INSTANCE
        )
        return super.visitInitDecl(initDecl, additional: additional)
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = subscriptDecl.symbol else {
            return super.visitSubscriptDecl(subscriptDecl, additional: additional)
        }
        fillParameterTypes(subscriptDecl.parameters, into: symbol)
        symbol.functionType = functionType(
            labels: subscriptDecl.parameters.map { $0.label?.value },
            parameterTypes: subscriptDecl.parameters.map(\.type),
            asyncToken: subscriptDecl.asyncToken,
            throwsClause: subscriptDecl.throwsClause,
            returnType: subscriptDecl.returnType
        )
        return super.visitSubscriptDecl(subscriptDecl, additional: additional)
    }

    @discardableResult
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        if let signature = closure.signature {
            closure.ty = functionType(
                labels: signature.parameters.map { $0.label?.value },
                parameterTypes: signature.parameters.map(\.type),
                asyncToken: signature.asyncToken,
                throwsClause: signature.throwsClause,
                returnType: signature.returnType
            )
        }
        return super.visitClosure(closure, additional: additional)
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
    public override func visitCastExpression(
        _ castExpression: AST.CastExpression, additional: Any? = nil
    ) -> Any? {
        _ = evaluate(castExpression.right)
        return super.visitCastExpression(castExpression, additional: additional)
    }

    @discardableResult
    public override func visitIsPattern(_ isPattern: AST.IsPattern, additional: Any? = nil)
        -> Any?
    {
        _ = evaluate(isPattern.typeExpression)
        return super.visitIsPattern(isPattern, additional: additional)
    }

    @discardableResult
    public override func visitAsPattern(_ asPattern: AST.AsPattern, additional: Any? = nil)
        -> Any?
    {
        _ = evaluate(asPattern.typeExpression)
        return super.visitAsPattern(asPattern, additional: additional)
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        let name = variable.name.value
        if name == "Void" {
            variable.ty = TrussType.VoidType.INSTANCE
        } else if name == "Never" {
            variable.ty = TrussType.NeverType.INSTANCE
        }
        return nil
    }

    private func fillParameterTypes(
        _ parameters: [AST.FunctionDecl.Parameter], into symbol: Symbol.FunctionSymbol
    ) {
        for parameter in parameters {
            let type = evaluate(parameter.type)
            let variable = symbol.scope.values[parameter.name.value]?.first
                as? Symbol.VariableSymbol
            variable?.type = type
        }
    }

    private func functionType(
        labels: [String?],
        parameterTypes: [AST.Expression?],
        asyncToken: Token?,
        throwsClause: AST.ThrowsClause?,
        returnType: AST.Expression?,
        fallbackReturnType: TrussType.TrussType? = nil
    ) -> TrussType.FunctionType {
        for type in throwsClause?.types ?? [] {
            _ = evaluate(type)
        }
        let resolvedReturnType: TrussType.TrussType? =
            if let returnType {
                evaluate(returnType)
            } else {
                fallbackReturnType
            }
        return TrussType.FunctionType(
            parameters: zip(labels, parameterTypes).map { label, type in
                TrussType.FunctionType.Parameter(label: label, type: evaluate(type))
            },
            isAsync: asyncToken != nil,
            isThrowing: throwsClause != nil,
            returnType: resolvedReturnType
        )
    }

    private func evaluate(_ expression: AST.Expression?) -> TrussType.TrussType? {
        guard let expression else { return nil }
        let result: TrussType.TrussType?
        switch expression {
        case let variable as AST.Variable:
            result = evaluateVariable(variable)
        case let parenthetical as AST.ParentheticalExpression:
            result = evaluate(parenthetical.inner)
        case let optionalType as AST.OptionalType:
            result = evaluate(optionalType.wrappedType).map(TrussType.OptionalType.init)
        case let variadicType as AST.VariadicType:
            result = evaluate(variadicType.base).map(TrussType.VariadicType.init)
        case let closureType as AST.ClosureType:
            result = functionType(
                labels: closureType.parameters.map { $0.label?.value },
                parameterTypes: closureType.parameters.map(\.type),
                asyncToken: closureType.asyncToken,
                throwsClause: closureType.throwsClause,
                returnType: closureType.returnType
            )
        case let tupleExpression as AST.TupleExpression:
            var elements: [TrussType.TupleType.Element] = []
            var ok = true
            for argument in tupleExpression.elements {
                guard let type = evaluate(argument.value) else {
                    ok = false
                    break
                }
                elements.append(
                    TrussType.TupleType.Element(label: argument.label?.value, type: type))
            }
            result = ok ? TrussType.TupleType(elements) : nil
        case let composition as AST.ProtocolCompositionType:
            var members: [TrussType.TrussType] = []
            var ok = true
            for type in composition.types {
                guard let member = evaluate(type) else {
                    ok = false
                    break
                }
                members.append(member)
            }
            result = ok ? TrussType.CompositionType(members) : nil
        case let genericApplication as AST.GenericApplication:
            result = evaluateGenericApplication(genericApplication)
        case let sequential as AST.SequentialExpression
            where sequential.ops.allSatisfy({ op in
                if case .Operator(.BitAnd) = op.kind { return true }
                return false
            }):
            var members: [TrussType.TrussType] = []
            var ok = true
            for operand in sequential.operands {
                guard let member = evaluate(operand) else {
                    ok = false
                    break
                }
                members.append(member)
            }
            result = ok ? TrussType.CompositionType(members) : nil
        case is AST.VoidLiteral:
            result = TrussType.VoidType.INSTANCE
        default:
            result = nil
        }
        expression.ty = result
        return result
    }

    private func evaluateVariable(_ variable: AST.Variable) -> TrussType.TrussType? {
        if let symbol = variable.symbol {
            if let nominal = symbol as? Symbol.NominalTypeSymbol {
                return nominal.typeId.flatMap { context.typeTable[$0] }
            }
            if let typeAlias = symbol as? Symbol.TypeAliasSymbol {
                return resolveTypealias(typeAlias)
            }
            return nil
        }
        switch variable.name.value {
        case "Void": return TrussType.VoidType.INSTANCE
        case "Never": return TrussType.NeverType.INSTANCE
        default: return nil
        }
    }

    private func resolveTypealias(_ symbol: Symbol.TypeAliasSymbol) -> TrussType.TrussType? {
        if let target = symbol.targetType { return target }
        if resolvingTypealiases.contains(symbol.id) { return nil }
        guard let decl = typealiasDecls[symbol.id] else { return nil }
        resolvingTypealiases.insert(symbol.id)
        defer { resolvingTypealiases.remove(symbol.id) }
        symbol.targetType = evaluate(decl.typeExpression)
        return symbol.targetType
    }

    private func evaluateGenericApplication(
        _ genericApplication: AST.GenericApplication
    ) -> TrussType.TrussType? {
        guard let base = evaluate(genericApplication.base) as? TrussType.NominalType else {
            return nil
        }
        var arguments: [TrussType.TrussType] = []
        for argument in genericApplication.genericArguments {
            guard let resolved = evaluate(argument) else { return nil }
            arguments.append(resolved)
        }
        return TrussType.GenericInstantiation(base: base, arguments: arguments)
    }
}
