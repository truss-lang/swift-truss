import SwiftBetterDiagnostic
import TrussCore

public final class TypeChecker: AST.Visitor {
    public enum State: CaseIterable {
        case CollectingTypealias
        case Checking
    }

    public var state: State = .CollectingTypealias
    private let context: Context
    private var typealiasDecls: [Id.SymbolId: AST.TypeAliasDecl] = [:]
    private var resolvingTypealiases: Set<Id.SymbolId> = []
    private var functionReturnTypes: [TrussType.TrussType] = []
    private var scopeStack: [Scope] = []

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        super.visitProgram(program, additional: additional)
    }

    @discardableResult
    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil) -> Any? {
        let symbol = typeAliasDecl.symbol!
        if state == .CollectingTypealias {
            typealiasDecls[symbol.id] = typeAliasDecl
        }
        symbol.targetType = evaluate(typeAliasDecl.typeExpression)
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
        guard state == .Checking else {
            return nil
        }
        let symbol = functionDecl.symbol!
        withScope(symbol.scope) {
            let parameterTypes = evaluateParameterTypes(functionDecl.parameters, in: symbol)
            let returnType = if let returnTypeExpression = functionDecl.returnTypeExpression {
                evaluate(returnTypeExpression)
            } else {
                TrussType.VoidType.INSTANCE
            }
            let functionType = functionType(
                labels: functionDecl.parameters.map { $0.label?.value },
                parameterTypes: parameterTypes,
                isVariadic: functionDecl.varargToken != nil,
                asyncToken: functionDecl.asyncToken,
                throwsClause: functionDecl.throwsClause,
                returnType: returnType
            )
            symbol.functionType = functionType
            functionReturnTypes.append(returnType)
            switch functionDecl.body {
            case let .Block(statements):
                for statement in statements {
                    visit(statement)
                }
                if !(returnType is TrussType.VoidType), let last = statements.last as? AST.ExpressionStatement {
                    check(last.expression, returnType)
                }
            case let .Expression(expression):
                if returnType is TrussType.VoidType {
                    infer(expression)
                } else {
                    check(expression, returnType)
                }
            default:
                break
            }
            functionReturnTypes.removeLast()
        }
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil) -> Any? {
        guard state == .Checking else {
            return nil
        }
        let symbol = variableDecl.symbol!
        if let typeExpression = variableDecl.typeExpression {
            let ty = evaluate(typeExpression)
            symbol.type = ty
            if let initializer = variableDecl.initializer {
                check(initializer, ty)
            }
        } else if let initializer = variableDecl.initializer {
            let ty = infer(initializer)
            symbol.type = ty
        } else {
            // TODO: emit error
        }
        return nil
    }

    @discardableResult
    public override func visitReturn(_ returnStatement: AST.Return, additional: Any? = nil) -> Any? {
        if let value = returnStatement.value {
            if let expected = functionReturnTypes.last {
                check(value, expected)
            } else {
                infer(value)
            }
        }
        return nil
    }

    private func evaluateParameterTypes(
        _ parameters: [AST.FunctionDecl.Parameter],
        in symbol: Symbol.FunctionSymbol
    ) -> [TrussType.TrussType] {
        var types: [TrussType.TrussType] = []
        for parameter in parameters {
            let type: TrussType.TrussType =
                if let ty = parameter.typeExpression {
                    evaluate(ty)
                } else {
                    TrussType.ErrorType.INSTANCE
                }
            let variable = symbol.scope.values[parameter.name.value]!.first as! Symbol.VariableSymbol
            variable.type = type
            types.append(type)
            if let defaultValue = parameter.defaultValue {
                check(defaultValue, type)
            }
        }
        return types
    }

    private func evaluate(_ expression: AST.Expression) -> TrussType.TrussType {
        let result: TrussType.TrussType
        switch expression {
        case let variable as AST.Variable:
            if let symbol = variable.symbol {
                result = evaluateSymbol(symbol)
            } else {
                context.emitError("cannot find type '\(variable.name.value)'", at: variable.name)
                result = TrussType.ErrorType.INSTANCE
            }
        case let member as AST.MemberAccess:
            if let symbol = member.symbol {
                result = evaluateSymbol(symbol)
            } else {
                context.emitError("cannot find type '\(member.member.value)'", at: member.member)
                result = TrussType.ErrorType.INSTANCE
            }
        case let implicit as AST.ImplicitMemberAccess:
            if let symbol = implicit.symbol {
                result = evaluateSymbol(symbol)
            } else {
                context.emitError("cannot find type '\(implicit.name.value)'", at: implicit.name)
                result = TrussType.ErrorType.INSTANCE
            }
        case let parenthetical as AST.Parenthetical:
            result = evaluate(parenthetical.inner)
        case let pointerType as AST.PointerType:
            let pointee = evaluate(pointerType.wrappedType)
            result = pointee is TrussType.ErrorType ? TrussType.ErrorType.INSTANCE : TrussType.PointerType(
                pointee,
                isNonnull: pointerType.isNonnull
            )
        case is AST.VoidLiteral:
            result = TrussType.VoidType.INSTANCE
        default:
            result = TrussType.ErrorType.INSTANCE
        }
        expression.ty = result
        return result
    }

    private func evaluateSymbol(_ symbol: Symbol.Symbol) -> TrussType.TrussType {
        switch symbol {
        case let nominal as Symbol.NominalTypeSymbol:
            return context.typeTable[nominal.typeId!]!
        case let typeAlias as Symbol.TypeAliasSymbol:
            if let target = typeAlias.targetType {
                return target
            }
            if resolvingTypealiases.contains(symbol.id) {
                context.emitError(
                    "circular reference to typealias '\(symbol.name)'", at: symbol.sourceToken!
                )
                return TrussType.ErrorType.INSTANCE
            }
            guard let decl = typealiasDecls[symbol.id] else {
                return TrussType.ErrorType.INSTANCE
            }
            resolvingTypealiases.insert(symbol.id)
            defer {
                resolvingTypealiases.remove(symbol.id)
            }
            typeAlias.targetType = evaluate(decl.typeExpression)
            return typeAlias.targetType ?? TrussType.ErrorType.INSTANCE
        case let builtin as Symbol.BuiltinTypeSymbol:
            return switch builtin.name {
            case "Void":
                TrussType.VoidType.INSTANCE
            case "Never":
                TrussType.NeverType.INSTANCE
            default:
                TrussType.BuiltinType(builtin.name)
            }
        default:
            fatalError()
        }
    }

    private func check(_ expression: AST.Expression, _ expected: TrussType.TrussType) {
        switch expression {
        case let parenthetical as AST.Parenthetical:
            check(parenthetical.inner, expected)
            parenthetical.ty = parenthetical.inner.ty
        case is AST.IntegerLiteral:
            if let kind = builtinPrimitiveKind(of: expected),
               kind == .Signed || kind == .Unsigned || kind == .Float
            {
                expression.ty = expected
            }
        case is AST.FloatLiteral:
            if let kind = builtinPrimitiveKind(of: expected), kind == .Float {
                expression.ty = expected
            }
        default:
            // TODO:
            fatalError()
        }
    }

    @discardableResult
    private func infer(_ expression: AST.Expression) -> TrussType.TrussType {
        fatalError()
    }

    private func builtinPrimitiveKind(of type: TrussType.TrussType) -> TIRType.PrimitiveKind? {
        guard let builtin = type as? TrussType.BuiltinType,
              let info = Builtin.typeInfos.first(where: { $0.name == builtin.name })
        else {
            return nil
        }
        return info.kind
    }

    private func functionType(
        selfType: TrussType.TrussType? = nil,
        labels: [String?],
        parameterTypes: [TrussType.TrussType],
        isVariadic: Bool,
        asyncToken: Token?,
        throwsClause: AST.ThrowsClause?,
        returnType: TrussType.TrussType
    ) -> TrussType.FunctionType {
        TrussType.FunctionType(
            selfType: selfType,
            parameters: zip(labels, parameterTypes).map { label, type in
                TrussType.FunctionType.Parameter(label: label, type: type)
            },
            isVariadic: isVariadic,
            isAsync: asyncToken != nil,
            isThrowing: throwsClause != nil,
            throwsTypes: (throwsClause?.types ?? []).map(evaluate),
            returnType: returnType
        )
    }

    private func withScope(_ scope: Scope?, _ body: () -> Void) {
        guard let scope else {
            body()
            return
        }
        scopeStack.append(scope)
        body()
        scopeStack.removeLast()
    }

    public static func resolvedFunctionSymbol(of expression: AST.Expression) -> Symbol.FunctionSymbol? {
        if let variable = expression as? AST.Variable {
            return variable.symbol as? Symbol.FunctionSymbol
        }
        if let member = expression as? AST.MemberAccess {
            return member.symbol as? Symbol.FunctionSymbol
        }
        if let implicit = expression as? AST.ImplicitMemberAccess {
            return implicit.symbol as? Symbol.FunctionSymbol
        }
        if let generic = expression as? AST.GenericApplication {
            return resolvedFunctionSymbol(of: generic.base)
        }
        return nil
    }

    public static func resolvedFunctionSymbols(of expression: AST.Expression) -> [Symbol.FunctionSymbol] {
        if let variable = expression as? AST.Variable {
            return variable.overloads ?? []
        }
        if let member = expression as? AST.MemberAccess {
            return member.overloads ?? []
        }
        if let implicit = expression as? AST.ImplicitMemberAccess {
            return implicit.overloads ?? []
        }
        if let generic = expression as? AST.GenericApplication {
            return resolvedFunctionSymbols(of: generic.base)
        }
        return []
    }
}
