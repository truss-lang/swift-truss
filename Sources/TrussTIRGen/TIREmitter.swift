import SwiftBetterDiagnostic
import TrussCore

public final class TIREmitter: AST.Visitor {
    private struct BuiltinArith {
        let op: TIR.ArithOp
        let arity: Int
    }

    private let context: Context
    private let gen: GenerationContext
    private var currentFunction: TIR.Function?
    private var variableMap: [ObjectIdentifier: [String: [String]]] = [:]

    private var currentModule: TIR.Module? {
        get {
            gen.currentModule
        }
        set {
            gen.currentModule = newValue
        }
    }

    private var builder: TIR.Builder? {
        get { gen.builder }
        set { gen.builder = newValue }
    }

    init(context: Context, gen: GenerationContext) {
        self.context = context
        self.gen = gen
    }

    private func visitExpression(_ expression: AST.Expression) -> TIR.Value? {
        visit(expression) as? TIR.Value
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
        guard let symbol = functionDecl.symbol,
              let fn = gen.functionsBySymbol[symbol.id],
              let builder
        else {
            fatalError("unreachable")
        }
        guard let body = functionDecl.body else {
            return nil
        }
        let lastFunction = currentFunction

        currentFunction = fn
        variableMap[ObjectIdentifier(fn)] = [:]

        newBlock("entry")

        let parameterStartIndex = 0
        let parameterAllocs = functionDecl.parameters.enumerated().map { index, parameter in
            let name = mangleVariable(parameter.name.value)
            let alloc = builder.buildAllocStack(allocatedType: lowerType(parameter.symbol!.type).id, name: name)
            builder.buildStore(value: fn.parameters[parameterStartIndex + index], to: alloc.result)
            return alloc
        }

        switch body {
        case let .Block(statements):
            for statement in statements {
                visit(statement)
            }
        case let .Expression(expression):
            emitReturn(visitExpression(expression))
        }

        currentFunction = lastFunction
        variableMap.removeValue(forKey: ObjectIdentifier(fn))
        return nil
    }

    @discardableResult
    public override func visitReturn(_ ret: AST.Return, additional: Any? = nil) -> Any? {
        if let v = ret.value {
            emitReturn(visitExpression(v))
        } else {
            emitReturn()
        }
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil) -> Any? {
        guard let builder, let currentFunction, let symbol = variableDecl.symbol else {
            fatalError("unreachable")
        }
        let alloc = builder.buildAllocStack(
            allocatedType: lowerType(symbol.type).id,
            name: mangleVariable(variableDecl.name.value)
        )
        if let initializer = variableDecl.initializer {
            builder.buildStore(value: visitExpression(initializer)!, to: alloc.result)
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
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        guard let builder, let symbol = variable.symbol else { return nil }
        if let functionSymbol = symbol as? Symbol.FunctionSymbol {
            return functionRefValue(functionSymbol, at: variable.sourceRange)
        }
        return nil
    }

    @discardableResult
    public override func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        if let arith = builtinArithInfo(of: call.callee) {
            let arguments: [TIR.Value] = call.arguments.compactMap { visitExpression($0.value) }
            return emitBuiltinArith(arith, arguments: arguments)
        }
        guard let callee = visitExpression(call.callee) else {
            fatalError()
        }
        let arguments = call.arguments.map {
            visitExpression($0.value)!
        }
        let inst = builder.buildCall(callee: callee, arguments: arguments)
        return inst.result
    }

    @discardableResult
    private func newBlock(_ name: String? = nil) -> TIR.BasicBlock {
        guard let builder, let currentFunction else {
            fatalError("unreachable")
        }
        let blockName = name ?? "bb\(currentFunction.basicBlocks.count)"
        let block = currentFunction.addBasicBlock(name: blockName)
        builder.insertPoint = block
        return block
    }

    private func mangleVariable(_ name: String) -> String {
        guard let currentFunction else {
            fatalError("unreachable")
        }
        var varMap = variableMap[ObjectIdentifier(currentFunction), default: [:]]
        let map = varMap[name, default: []]
        let mangledName = "\(name)_\(map.count)"
        varMap[name] = map + [mangledName]
        variableMap[ObjectIdentifier(currentFunction)] = varMap
        return mangledName
    }

    private func emitReturn(_ value: TIR.Value? = nil) {
        guard let builder else {
            fatalError("unreachable")
        }
        builder.buildReturn(value)
    }

    private func functionRefValue(_ symbol: Symbol.FunctionSymbol, at range: SourceRange) -> TIR.Value? {
        guard let builder else { return nil }
        let function: TIR.Function
        if let existing = gen.functionsBySymbol[symbol.id] {
            function = existing
        } else {
            guard let module = gen.currentModule,
                  let functionType = symbol.functionType else { return nil }
            let parameters: [TIR.Parameter] = functionType.parameters.enumerated().map {
                index, parameter in
                TIR.Parameter(ty: gen.typeLower.lower(parameter.type).id, name: "arg\(index)")
            }
            let returnType = lowerType(functionType.returnType)
            function = module.addFunction(
                name: symbol.name,
                parameters: parameters,
                returnType: returnType.id,
                isVariadic: false,
                isExtern: true,
                callingConvention: nil
            )
            gen.functionsBySymbol[symbol.id] = function
        }
        return builder.buildFunctionRef(function: function)
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

    private func lowerType(_ type: TrussType.TrussType?) -> TIRType.TIRType {
        type.map { gen.typeLower.lower($0) } ?? gen.registry.voidType()
    }
}
