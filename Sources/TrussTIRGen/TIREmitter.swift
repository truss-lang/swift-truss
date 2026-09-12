import SwiftBetterDiagnostic
import TrussCore

public final class TIREmitter: AST.Visitor {
    private struct BuiltinArith {
        let op: TIR.ArithOp
        let arity: Int
    }

    private class LabelTarget {
        let block: TIR.BasicBlock
        public init(block: TIR.BasicBlock) {
            self.block = block
        }
    }

    private let context: Context
    private let gen: GenerationContext
    private var currentFunction: TIR.Function?
    private var variableMap: [ObjectIdentifier: [String: Int]] = [:]
    private var localVariableMap: [[String: TIR.Value]] = []
    private var labelMap: [String: LabelTarget] = [:]

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

    private func visitExpression(_ expression: AST.Expression) -> TIR.Value {
        visit(expression) as! TIR.Value
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
        guard let symbol = functionDecl.symbol,
              let fn = gen.functionsBySymbol[symbol.id]
        else {
            fatalError("unreachable")
        }
        guard let body = functionDecl.body else {
            return nil
        }
        emitFunctionBody(
            fn: fn,
            parameters: functionDecl.parameters,
            parameterStartIndex: 0
        ) {
            switch body {
            case let .Block(statements):
                for statement in statements {
                    visit(statement)
                }
            case let .Expression(expression):
                emitReturn(visitExpression(expression))
            }
        } prologue: { [self] in
            if symbol.kind != .Function, symbol.kind != .StaticMethod {
                bindLocal("<self>", fn.parameters[0])
            }
        }
        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        guard let symbol = initDecl.symbol,
              let fn = gen.functionsBySymbol[symbol.id],
              let builder
        else {
            fatalError("unreachable")
        }
        emitFunctionBody(
            fn: fn,
            parameters: initDecl.parameters,
            parameterStartIndex: 1,
        ) {
            for statement in initDecl.body {
                visit(statement)
            }
        } prologue: { [self] in
            bindLocal("<self>", fn.parameters[0])
        }
        return nil
    }

    private func emitFunctionBody(
        fn: TIR.Function,
        parameters: [AST.FunctionDecl.Parameter],
        parameterStartIndex: Int,
        body: () -> Void,
        prologue: (() -> Void)? = nil
    ) {
        let lastFunction = currentFunction
        let lastLabelMap = labelMap
        labelMap = [:]

        currentFunction = fn
        variableMap[ObjectIdentifier(fn)] = [:]
        pushScope()

        newBlock("entry")

        if let prologue {
            prologue()
        }

        for (index, parameter) in parameters.enumerated() {
            let name = mangleVariable(parameter.name.value)
            let alloc = builder!.buildAllocStack(
                allocatedType: lowerType(parameter.symbol!.type).id,
                name: name
            )
            builder!.buildStore(value: fn.parameters[parameterStartIndex + index], to: alloc.result)
            bindLocal(parameter.name.value, alloc.result)
        }

        body()

        currentFunction = lastFunction
        labelMap = lastLabelMap
        variableMap.removeValue(forKey: ObjectIdentifier(fn))
        popScope()
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
                guard let initializerId = global.initializer,
                      let initializerFunction = gen.registry.functions[initializerId]
                else {
                    fatalError("unreachable")
                }
                let lastInsertPoint = builder.insertPoint
                let lastFunction = currentFunction

                currentFunction = initializerFunction

                newBlock("entry")
                let v = visitExpression(initializer)
                let addr = builder.buildGlobalAddr(global: global)
                builder.buildStore(value: v, to: addr)
                builder.buildReturn()

                builder.insertPoint = lastInsertPoint
                currentFunction = lastFunction
            }
        } else {
            let name = mangleVariable(variableDecl.name.value)
            let alloc = builder.buildAllocStack(
                allocatedType: lowerType(symbol.type).id,
                name: name
            )
            bindLocal(variableDecl.name.value, alloc.result)
            if let initializer = variableDecl.initializer {
                builder.buildStore(value: visitExpression(initializer), to: alloc.result)
            }
        }
        return nil
    }

    public override func visitLoop(_ loopStatement: AST.Loop, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        pushScope()
        let block = buildBlock()
        let nextBlock = buildBlock()

        builder.buildBranch(to: block)

        builder.insertPoint = block
        for statement in loopStatement.body {
            visit(statement)
        }
        builder.buildBranch(to: block)

        builder.insertPoint = nextBlock
        popScope()
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        pushScope()
        let condBlock = buildBlock()
        let thenBlock = buildBlock()
        let nextBlock = buildBlock()

        builder.buildBranch(to: condBlock)

        builder.insertPoint = condBlock
        let cond = visitExpression(whileStatement.condition)
        builder.buildConditionalBranch(condition: cond, trueBranch: thenBlock, falseBranch: nextBlock)

        builder.insertPoint = thenBlock
        for statement in whileStatement.body {
            visit(statement)
        }
        builder.buildBranch(to: condBlock)

        builder.insertPoint = nextBlock
        popScope()
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(_ repeatWhile: AST.RepeatWhile, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        pushScope()
        let bodyBlock = buildBlock()
        let nextBlock = buildBlock()

        builder.buildBranch(to: bodyBlock)

        builder.insertPoint = bodyBlock
        for statement in repeatWhile.body {
            visit(statement)
        }
        let cond = visitExpression(repeatWhile.condition)
        builder.buildConditionalBranch(condition: cond, trueBranch: bodyBlock, falseBranch: nextBlock)

        builder.insertPoint = nextBlock
        popScope()
        return nil
    }

    @discardableResult
    public override func visitGoto(_ gotoStatement: AST.Goto, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let target = getLabelTarget(gotoStatement.label.value)
        builder.buildBranch(to: target.block)
        return nil
    }

    @discardableResult
    public override func visitLabeledStatement(
        _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let target = getLabelTarget(labeledStatement.label.value)
        builder.insertPoint = target.block
        return visit(labeledStatement.body, additional: additional)
    }

    @discardableResult
    public override func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
    ) -> Any? {
        visit(expressionStatement.expression, additional: additional)
    }

    @discardableResult
    public override func visitEmptyStatement(_ emptyStatement: AST.EmptyStatement, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitErrorExpressionStatement(
        _ errorStatement: AST.ErrorExpressionStatement, additional: Any? = nil
    ) -> Any? {
        nil
    }

    @discardableResult
    public override func visitErrorExpression(_ errorExpression: AST.ErrorExpression, additional: Any? = nil) -> Any? {
        nil
    }

    @discardableResult
    public override func visitParenthetical(
        _ parentheticalExpression: AST.Parenthetical, additional: Any? = nil
    ) -> Any? {
        visit(parentheticalExpression.inner)
    }

    @discardableResult
    public override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let type = lowerType(integerLiteral.ty)
        return builder.buildIntegerLiteral(
            value: UInt64(integerLiteral.value),
            ty: type.id
        )
    }

    @discardableResult
    public override func visitFloatLiteral(
        _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let type = lowerType(floatLiteral.ty)
        return builder.buildFloatLiteral(value: floatLiteral.value, ty: type.id)
    }

    @discardableResult
    public override func visitBoolLiteral(
        _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let type = lowerType(boolLiteral.ty)
        return builder.buildBoolLiteral(value: boolLiteral.value, ty: type.id)
    }

    @discardableResult
    public override func visitCharLiteral(
        _ charLiteral: AST.CharLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let type = lowerType(charLiteral.ty)
        return builder.buildCharLiteral(value: charLiteral.value, ty: type.id)
    }

    @discardableResult
    public override func visitStringLiteral(
        _ stringLiteral: AST.StringLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let type = lowerType(stringLiteral.ty)
        return builder.buildStringLiteral(value: stringLiteral.token.value, ty: type.id)
    }

    @discardableResult
    public override func visitNullptrLiteral(
        _ nullPointerLiteral: AST.NullptrLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let type = lowerType(nullPointerLiteral.ty)
        return builder.buildNullptrLiteral(ty: type.id)
    }

    @discardableResult
    public override func visitNullLiteral(
        _ nullLiteral: AST.NullLiteral, additional: Any? = nil
    ) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
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
    public override func visitTuple(_ tuple: AST.Tuple, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let elements = tuple.elements.map {
            visitExpression($0.value)
        }
        return builder.buildTupleValue(elements: elements, ty: lowerType(tuple.ty).id)
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        guard let builder, let symbol = variable.symbol else {
            fatalError("unreachable")
        }
        if let functionSymbol = symbol as? Symbol.FunctionSymbol {
            if variable.willBeCalled {
                switch functionSymbol.kind {
                case .Initializer:
                    guard let memberOf = functionSymbol.memberOf,
                          let nominalTypeSymbol = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol,
                          let typeId = nominalTypeSymbol.typeId,
                          let type = context.typeTable[typeId]
                    else {
                        fatalError()
                    }
                    let ref = functionRefValue(functionSymbol, at: variable.sourceRange)
                    return builder.buildObjectConstruction(
                        initializer: ref,
                        objectTy: lowerType(type).id,
                        functionTy: lowerType(functionSymbol.functionType).id
                    )

                case .Method:
                    let obj = getSelf()
                    return objectBinding(obj: obj, of: functionSymbol, sourceRange: variable.sourceRange)

                default:
                    let ref = functionRefValue(functionSymbol, at: variable.sourceRange)
                    return ref
                }
            } else {
                let ref = functionRefValue(functionSymbol, at: variable.sourceRange)
                return builder.buildClosure(function: ref, captures: []).result
            }
        }
        if let nominal = symbol as? Symbol.NominalTypeSymbol {
            // TODO: return reflection of the nominal type
        }
        let addr: TIR.Value
        if let global = gen.globalsBySymbol[symbol.id] {
            addr = builder.buildGlobalAddr(global: global)
        } else if let value = lookupLocal(variable.name.value) {
            addr = value
        } else {
            return nil
        }
        if variable.isLeftValue {
            return addr
        }
        let load = builder.buildLoad(ptr: addr)
        return load.result
    }

    @discardableResult
    public override func visitMemberAccess(_ memberAccess: AST.MemberAccess, additional: Any? = nil) -> Any? {
        guard let builder, let symbol = memberAccess.symbol else {
            fatalError("unreachable")
        }
        if let functionSymbol = symbol as? Symbol.FunctionSymbol {
            if memberAccess.willBeCalled {
                switch functionSymbol.kind {
                case .Initializer:
                    guard let memberOf = functionSymbol.memberOf,
                          let nominalTypeSymbol = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol,
                          let typeId = nominalTypeSymbol.typeId,
                          let type = context.typeTable[typeId]
                    else {
                        fatalError()
                    }
                    let ref = functionRefValue(functionSymbol, at: memberAccess.sourceRange)
                    return builder.buildObjectConstruction(
                        initializer: ref,
                        objectTy: lowerType(type).id,
                        functionTy: lowerType(functionSymbol.functionType).id
                    )

                case .Method:
                    guard let memberOf = functionSymbol.memberOf,
                          let nominalTypeSymbol = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol
                    else {
                        fatalError()
                    }
                    memberAccess.object.isLeftValue = true
                    let obj = visitExpression(memberAccess.object)
                    memberAccess.object.isLeftValue = false
                    return objectBinding(obj: obj, of: functionSymbol, sourceRange: memberAccess.sourceRange)

                default:
                    let ref = functionRefValue(functionSymbol, at: memberAccess.sourceRange)
                    return ref
                }
            } else {
                let ref = functionRefValue(functionSymbol, at: memberAccess.sourceRange)
                return builder.buildClosure(function: ref, captures: []).result
            }
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
        let calleeValue = visitExpression(call.callee)
        let callee: TIR.Value
        let selfParameter: TIR.Value?
        var needLoad = false
        if let construction = calleeValue as? TIR.ObjectConstruction {
            callee = construction.initializer
            guard let ty = gen.registry.type(construction.objectTy) else {
                fatalError()
            }
            if ty is TIRType.ClassType {
                let alloc = builder.buildAllocHeap(allocatedType: construction.objectTy)
                selfParameter = alloc.result
            } else {
                let alloc = builder.buildAllocStack(allocatedType: construction.objectTy)
                selfParameter = alloc.result
                needLoad = true
            }
        } else if let binding = calleeValue as? TIR.ObjectBinding {
            callee = binding.method
            selfParameter = binding.object
        } else {
            callee = calleeValue
            selfParameter = nil
        }
        let arguments = [selfParameter].compactMap { $0 } + call.arguments.map {
            visitExpression($0.value)
        }
        let inst = builder.buildCall(callee: callee, arguments: arguments)
        if needLoad {
            return builder.buildLoad(ptr: inst.result!).result
        } else {
            return inst.result
        }
    }

    @discardableResult
    public override func visitBinary(_ binary: AST.Binary, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let left = visitExpression(binary.left)
        let right = visitExpression(binary.right)
        if binary.operatorToken.kind == .Operator(.Assign) {
            builder.buildStore(value: right, to: left)
            return right
        } else {
            guard let symbol = binary.symbol else {
                fatalError("unreachable")
            }
            let f = functionRefValue(symbol, at: binary.sourceRange)
            let inst = builder.buildCall(callee: f, arguments: [left, right])
            return inst.result
        }
    }

    @discardableResult
    public override func visitPrefix(_ prefix: AST.Prefix, additional: Any? = nil) -> Any? {
        guard let builder, let symbol = prefix.symbol else { return nil }
        if symbol.isBuiltin {
            if let arith = arithOp(named: builtinOpName(of: symbol)) {
                let operand = visitExpression(prefix.expression)
                return builder.buildUnaryArith(op: arith, operand: operand).result
            }
        }
        let callee = functionRefValue(symbol, at: prefix.sourceRange)
        let operand = visitExpression(prefix.expression)
        return builder.buildCall(callee: callee, arguments: [operand]).result
    }

    @discardableResult
    public override func visitPostfix(_ postfix: AST.Postfix, additional: Any? = nil) -> Any? {
        guard let builder, let symbol = postfix.symbol else { return nil }
        let callee = functionRefValue(symbol, at: postfix.sourceRange)
        let operand = visitExpression(postfix.expression)
        return builder.buildCall(callee: callee, arguments: [operand]).result
    }

    @discardableResult
    public override func visitDereference(_ dereference: AST.Dereference, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let v = visitExpression(dereference.expression)
        if dereference.isLeftValue {
            return v
        } else {
            let load = builder.buildLoad(ptr: v)
            return load.result
        }
    }

    @discardableResult
    public override func visitAddressOf(_ addressOf: AST.AddressOf, additional: Any? = nil) -> Any? {
        visit(addressOf.expression, additional: additional)
    }

    @discardableResult
    public override func visitSelfExpression(_ selfExpression: AST.SelfExpression, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let v = getSelf()
        if selfExpression.isLeftValue {
            return v
        } else {
            let inst = builder.buildLoad(ptr: v)
            return inst.result
        }
    }

    @discardableResult
    public override func visitSuperExpression(_ superExpression: AST.SuperExpression, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let v = getSelf()
        if superExpression.isLeftValue {
            return v
        } else {
            let inst = builder.buildLoad(ptr: v)
            return inst.result
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
        let count = varMap[name, default: 0]
        let mangledName = "\(name)_\(count)"
        varMap[name] = count + 1
        variableMap[ObjectIdentifier(currentFunction)] = varMap
        return mangledName
    }

    private func emitReturn(_ value: TIR.Value? = nil) {
        guard let builder else {
            fatalError("unreachable")
        }
        builder.buildReturn(value)
    }

    private func functionRefValue(_ symbol: Symbol.FunctionSymbol, at range: SourceRange) -> TIR.FunctionRef {
        guard let builder else { fatalError() }
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

    private func getSelf() -> TIR.Value {
        lookupLocal("<self>")!
    }

    private func objectBinding(
        obj: TIR.Value, of symbol: Symbol.FunctionSymbol, sourceRange: SourceRange
    ) -> TIR.ObjectBinding {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let memberOf = symbol.memberOf,
              let nominalTypeSymbol = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol
        else {
            fatalError()
        }
        switch nominalTypeSymbol {
        case is Symbol.StructSymbol, is Symbol.EnumSymbol:
            let ref = functionRefValue(symbol, at: sourceRange)
            return builder.buildObjectBinding(
                object: obj,
                method: ref,
                ty: lowerType(symbol.functionType).id
            )
        case is Symbol.ClassSymbol, is Symbol.ActorSymbol:
            let loweredType = lowerType(symbol.functionType).id
            let metadataId = metadata(of: nominalTypeSymbol)
            let metadata = gen.registry.metadata(metadataId)!
            let index = metadata.vtable.enumerated().filter { _, entry in
                entry.name == symbol.name && entry.signature == loweredType
            }.first!.offset
            let callee = builder.buildVirtualMethod(
                metadata: metadataId,
                index: index,
                selfValue: obj,
                ty: loweredType
            )
            return builder.buildObjectBinding(
                object: obj,
                method: callee.result,
                ty: loweredType
            )
        default:
            fatalError()
        }
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

    private func metadata(of symbol: Symbol.NominalTypeSymbol) -> Id.TIRMetadataId {
        gen.typeLower.metadataId(for: gen.context.typeTable[symbol.typeId!]! as! TrussType.NominalType)!
    }

    private func getLabelTarget(_ name: String) -> LabelTarget {
        if let existing = labelMap[name] {
            return existing
        }

        let block = buildBlock("label_\(name)")
        let target = LabelTarget(block: block)
        labelMap[name] = target
        return target
    }

    private func pushScope() {
        localVariableMap.append([:])
    }

    private func popScope() {
        localVariableMap.removeLast()
    }

    private func bindLocal(_ name: String, _ value: TIR.Value) {
        localVariableMap[localVariableMap.count - 1][name] = value
    }

    private func lookupLocal(_ name: String) -> TIR.Value? {
        for layer in localVariableMap.reversed() {
            if let value = layer[name] {
                return value
            }
        }
        return nil
    }

    private func lowerType(_ type: TrussType.TrussType?) -> TIRType.TIRType {
        type.map { gen.typeLower.lower($0) } ?? gen.registry.voidType()
    }
}
