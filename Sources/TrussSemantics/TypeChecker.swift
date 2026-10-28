import SwiftBetterDiagnostic
import TrussCore

public final class TypeChecker: AST.Visitor {
    private let context: Context

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        super.visitProgram(program, additional: additional)
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil) -> Any? {
        if let typeExpression = variableDecl.typeExpression {
            let ty = evaluate(typeExpression)
            variableDecl.symbol!.type = ty
            if let initializer = variableDecl.initializer {
                check(initializer, ty)
            }
        } else if let initializer = variableDecl.initializer {
            let ty = infer(initializer)
        } else {
            // TODO: emit error
        }
        return nil
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
        if let builtin = symbol as? Symbol.BuiltinTypeSymbol {
            switch builtin.name {
            case "Void":
                TrussType.VoidType.INSTANCE
            case "Never":
                TrussType.NeverType.INSTANCE
            default:
                TrussType.BuiltinType(builtin.name)
            }
        } else {
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
        default:
            // TODO:
            fatalError()
        }
    }

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
