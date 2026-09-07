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
        guard let builder, let symbol = variableDecl.symbol else {
            fatalError("unreachable")
        }
        if let global = gen.globalsBySymbol[symbol.id] {
            if let initializer = variableDecl.initializer {
                guard let initializerFunction = global.initializer else {
                    fatalError("unreachable")
                }
                let lastInsertPoint = builder.insertPoint
                let lastFunction = currentFunction

                currentFunction = initializerFunction

                newBlock("entry")
                guard let v = visitExpression(initializer) else {
                    fatalError()
                }
                let addr = builder.buildGlobalAddr(global: global)
                builder.buildStore(value: v, to: addr)
                builder.buildReturn()

                builder.insertPoint = lastInsertPoint
                currentFunction = lastFunction
            }
        } else {
            let alloc = builder.buildAllocStack(
                allocatedType: lowerType(symbol.type).id,
                name: mangleVariable(variableDecl.name.value)
            )
            if let initializer = variableDecl.initializer {
                builder.buildStore(value: visitExpression(initializer)!, to: alloc.result)
            }
        }
        return nil
    }

    public override func visitLoop(_ loopStatement: AST.Loop, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let block = buildBlock()
        let nextBlock = buildBlock()

        builder.buildBranch(to: block)

        builder.insertPoint = block
        for statement in loopStatement.body {
            visit(statement)
        }
        builder.buildBranch(to: block)

        builder.insertPoint = nextBlock
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let condBlock = buildBlock()
        let thenBlock = buildBlock()
        let nextBlock = buildBlock()

        builder.buildBranch(to: condBlock)

        builder.insertPoint = condBlock
        guard let cond = visitExpression(whileStatement.condition) else {
            fatalError()
        }
        builder.buildConditionalBranch(condition: cond, trueBranch: thenBlock, falseBranch: nextBlock)

        builder.insertPoint = thenBlock
        for statement in whileStatement.body {
            visit(statement)
        }
        builder.buildBranch(to: condBlock)

        builder.insertPoint = nextBlock
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(_ repeatWhile: AST.RepeatWhile, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let bodyBlock = buildBlock()
        let nextBlock = buildBlock()

        builder.buildBranch(to: bodyBlock)

        builder.insertPoint = bodyBlock
        for statement in repeatWhile.body {
            visit(statement)
        }
        guard let cond = visitExpression(repeatWhile.condition) else {
            fatalError()
        }
        builder.buildConditionalBranch(condition: cond, trueBranch: bodyBlock, falseBranch: nextBlock)

        builder.insertPoint = nextBlock
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
        if let global = gen.globalsBySymbol[symbol.id] {
            let addr = builder.buildGlobalAddr(global: global)
            if variable.isLeftValue {
                return addr
            }
            let load = builder.buildLoad(ptr: addr)
            return load.result
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
    public override func visitBinary(_ binary: AST.Binary, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let left = visitExpression(binary.left) else {
            fatalError()
        }
        guard let right = visitExpression(binary.right) else {
            fatalError()
        }
        if binary.operatorToken.kind == .Operator(.Assign) {
            builder.buildStore(value: right, to: left)
            return right
        } else {
            guard let symbol = binary.symbol else {
                fatalError("unreachable")
            }
            guard let f = functionRefValue(symbol, at: binary.sourceRange) else {
                fatalError()
            }
            let inst = builder.buildCall(callee: f, arguments: [left, right])
            return inst.result
        }
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
    public override func visitDereference(_ dereference: AST.Dereference, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let v = visitExpression(dereference.expression) else {
            fatalError()
        }
        if dereference.isLeftValue {
            return v
        } else {
            let load = builder.buildLoad(ptr: v)
            return load.result
        }
    }

    @discardableResult
    private func newBlock(_ name: String? = nil) -> TIR.BasicBlock {
        guard let builder else {
            fatalError("unreachable")
        }
        let block = buildBlock(name)
        builder.insertPoint = block
        return block
    }

    @discardableResult
    private func buildBlock(_ name: String? = nil) -> TIR.BasicBlock {
        guard let currentFunction else {
            fatalError("unreachable")
        }
        let blockName = name ?? "bb\(currentFunction.basicBlocks.count)"
        return currentFunction.addBasicBlock(name: blockName)
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
            guard let module = gen.currentModule, let functionType = symbol.functionType else {
                fatalError("unreachable")
            }
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

    private func builtinOpName(of symbol: Symbol.FunctionSymbol) -> String {
        if symbol.name.hasPrefix("builtin_") {
            String(symbol.name.dropFirst("builtin_".count).prefix { $0 != "_" })
        } else {
            ""
        }
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
