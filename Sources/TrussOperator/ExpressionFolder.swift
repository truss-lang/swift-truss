import SwiftBetterDiagnostic
import SwiftGraph
import TrussCore

public final class ExpressionFolder: AST.Rewriter {
    private let context: Context
    private let table: OperatorTable
    private var modulePath: [String] = []

    private lazy var graph = PrecedenceGraphBuilder(table: table, context: context).build()
    private lazy var ranks: [ObjectIdentifier: Int]? = computeRanks()
    private lazy var reachability: [ObjectIdentifier: Set<ObjectIdentifier>] =
        computeReachability()

    public init(context: Context, table: OperatorTable) {
        self.context = context
        self.table = table
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        modulePath = []
        return super.visitProgram(program, additional: additional)
    }

    @discardableResult
    public override func visitModuleDecl(
        _ moduleDecl: AST.ModuleDecl, additional: Any? = nil
    ) -> Any? {
        modulePath.append(moduleDecl.name.value)
        let result = super.visitModuleDecl(moduleDecl, additional: additional)
        modulePath.removeLast()
        return result
    }

    @discardableResult
    public override func visitSequentialExpression(
        _ sequentialExpression: AST.SequentialExpression, additional: Any? = nil
    ) -> Any? {
        let rewritten =
            super.visitSequentialExpression(sequentialExpression, additional: additional)
                as? AST.SequentialExpression ?? sequentialExpression
        guard !rewritten.ops.isEmpty, ranks != nil else { return rewritten }
        guard let folded = fold(rewritten) else { return rewritten }
        copySemanticFields(from: rewritten, to: folded)
        return folded
    }

    private func fold(_ sequence: AST.SequentialExpression) -> AST.Expression? {
        let ops = sequence.ops
        let operands = sequence.operands
        var opIndex = 0
        var operandIndex = 0
        var pendingPrefix: [Token] = []
        var head: AST.Expression? = nil
        var chainOperands: [AST.Expression] = []
        var chainOps: [Token] = []
        var awaitingOperand = true
        while opIndex < ops.count || operandIndex < operands.count {
            let opPosition = opIndex < ops.count ? ops[opIndex].pos.pos : Int.max
            let operandPosition =
                operandIndex < operands.count
                    ? operands[operandIndex].sourceRange.start.offset : Int.max
            if opPosition < operandPosition {
                let op = ops[opIndex]
                opIndex += 1
                if awaitingOperand {
                    let info = findOperator(op.value)
                    if info == nil {
                        context.emitError("unknown operator '\(op.value)'", at: op)
                    } else if !info!.kinds.contains(where: {
                        if case .Prefix = $0 { true } else { false }
                    }) {
                        context.emitError("operator '\(op.value)' is not prefix", at: op)
                    }
                    pendingPrefix.append(op)
                } else {
                    let info = findOperator(op.value)
                    let isInfix = info?.kinds.contains(where: {
                        if case .Infix = $0 { true } else { false }
                    }) ?? false
                    let isPostfix = info?.kinds.contains(where: {
                        if case .Postfix = $0 { true } else { false }
                    }) ?? false
                    if info == nil {
                        context.emitError("unknown operator '\(op.value)'", at: op)
                        startInfix(op, head: &head, chainOperands: &chainOperands, chainOps: &chainOps)
                        awaitingOperand = true
                    } else if isInfix {
                        startInfix(op, head: &head, chainOperands: &chainOperands, chainOps: &chainOps)
                        awaitingOperand = true
                    } else if isPostfix {
                        let wrapped = makePostfix(chainOperands.last ?? head!, op, in: sequence)
                        if chainOps.isEmpty {
                            head = wrapped
                        } else {
                            chainOperands[chainOperands.count - 1] = wrapped
                        }
                    } else {
                        context.emitError("operator '\(op.value)' is not infix", at: op)
                        startInfix(op, head: &head, chainOperands: &chainOperands, chainOps: &chainOps)
                        awaitingOperand = true
                    }
                }
            } else {
                let operand = operands[operandIndex]
                operandIndex += 1
                var wrapped = operand
                for prefixToken in pendingPrefix.reversed() {
                    wrapped = makePrefix(prefixToken, wrapped, in: sequence)
                }
                pendingPrefix = []
                if awaitingOperand {
                    if chainOps.isEmpty {
                        head = wrapped
                    } else {
                        chainOperands.append(wrapped)
                    }
                } else {
                    chainOperands.append(wrapped)
                }
                awaitingOperand = false
            }
        }
        if chainOps.isEmpty {
            return head
        }
        guard chainOperands.count == chainOps.count + 1 else { return nil }
        return foldChain(chainOperands, chainOps, in: sequence)
    }

    private func startInfix(
        _ op: Token, head: inout AST.Expression?,
        chainOperands: inout [AST.Expression], chainOps: inout [Token]
    ) {
        if chainOps.isEmpty {
            chainOperands.append(head!)
            head = nil
        }
        chainOps.append(op)
    }

    private func foldChain(
        _ operands: [AST.Expression], _ ops: [Token], in sequence: AST.SequentialExpression
    ) -> AST.Expression {
        var operandStack: [AST.Expression] = [operands[0]]
        var opStack: [Token] = []
        var groupStack: [PrecedenceGroupInfo?] = []
        var operandIndex = 1
        for op in ops {
            let opGroup = group(of: op)
            while !opStack.isEmpty {
                let top = opStack.last!
                let topGroup = groupStack.last!
                if let topGroup, let opGroup,
                   !shouldReduce(top, topGroup, against: op, opGroup)
                {
                    break
                }
                let rhs = operandStack.removeLast()
                let lhs = operandStack.removeLast()
                opStack.removeLast()
                groupStack.removeLast()
                operandStack.append(makeBinary(lhs, top, rhs, in: sequence))
            }
            opStack.append(op)
            groupStack.append(opGroup)
            if operandIndex < operands.count {
                operandStack.append(operands[operandIndex])
                operandIndex += 1
            }
        }
        while !opStack.isEmpty {
            let rhs = operandStack.removeLast()
            let lhs = operandStack.removeLast()
            let top = opStack.removeLast()
            groupStack.removeLast()
            operandStack.append(makeBinary(lhs, top, rhs, in: sequence))
        }
        return operandStack[0]
    }

    private func shouldReduce(
        _ top: Token, _ topGroup: PrecedenceGroupInfo,
        against op: Token, _ opGroup: PrecedenceGroupInfo
    ) -> Bool {
        if topGroup === opGroup {
            if topGroup.assignment {
                return false
            }
            switch topGroup.associativity {
            case .Left:
                return true
            case .Right:
                return false
            case .None:
                context.emitError("operator '\(top.value)' is non-associative", at: top)
                return true
            }
        }
        if reachable(topGroup, opGroup) {
            return true
        }
        if reachable(opGroup, topGroup) {
            return false
        }
        context.emitError(
            "adjacent operators are in unrelated precedence groups "
                + "'\(topGroup.name.value)' and '\(opGroup.name.value)'",
            at: top
        )
        return true
    }

    private func group(of op: Token) -> PrecedenceGroupInfo? {
        guard let info = findOperator(op.value) else { return nil }
        if let resolved = info.resolvedGroup {
            return resolved
        }
        if info.group != nil { return nil }
        guard info.kinds.contains(where: { if case .Infix = $0 { true } else { false } }) else {
            return nil
        }
        context.emitError("infix operator '\(op.value)' has no precedence group", at: op)
        return nil
    }

    private func findOperator(_ name: String) -> OperatorInfo? {
        var chain = modulePath
        while !chain.isEmpty {
            if let op = table.modules[chain.joined(separator: ".")]?.operators[name] {
                return op
            }
            chain.removeLast()
        }
        return table.root.operators[name]
    }

    private func makeBinary(
        _ left: AST.Expression, _ op: Token, _ right: AST.Expression,
        in sequence: AST.SequentialExpression
    ) -> AST.Binary {
        AST.Binary(
            left, right, op,
            sourceRange: SourceRange(start: left.sourceRange.start, end: right.sourceRange.end)
        )
    }

    private func makePrefix(
        _ op: Token, _ expr: AST.Expression, in sequence: AST.SequentialExpression
    ) -> AST.Prefix {
        AST.Prefix(
            op, expr,
            sourceRange: SourceRange(
                start: location(of: op, in: sequence), end: expr.sourceRange.end
            )
        )
    }

    private func makePostfix(
        _ expr: AST.Expression, _ op: Token, in sequence: AST.SequentialExpression
    ) -> AST.Postfix {
        AST.Postfix(
            expr, op,
            sourceRange: SourceRange(
                start: expr.sourceRange.start, end: location(of: op, in: sequence)
            )
        )
    }

    private func location(of token: Token, in sequence: AST.SequentialExpression) -> SourceLocation {
        SourceLocation(
            buffer: sequence.sourceRange.start.buffer, offset: token.pos.pos,
            line: token.pos.line, column: token.pos.col
        )
    }

    private func computeRanks() -> [ObjectIdentifier: Int]? {
        var inDegree: [ObjectIdentifier: Int] = [:]
        for vertex in graph.vertices {
            inDegree[ObjectIdentifier(vertex)] = 0
        }
        for vertex in graph.vertices {
            for edge in graph.edgesForVertex(vertex) ?? [] {
                let target = ObjectIdentifier(graph.vertices[edge.v])
                inDegree[target] = inDegree[target]! + 1
            }
        }
        var queue = graph.vertices.filter { inDegree[ObjectIdentifier($0)] == 0 }
        var ranks: [ObjectIdentifier: Int] = [:]
        var next = 0
        while !queue.isEmpty {
            let vertex = queue.removeFirst()
            ranks[ObjectIdentifier(vertex)] = next
            next += 1
            for edge in graph.edgesForVertex(vertex) ?? [] {
                let target = ObjectIdentifier(graph.vertices[edge.v])
                inDegree[target] = inDegree[target]! - 1
                if inDegree[target]! == 0 {
                    queue.append(graph.vertices[edge.v])
                }
            }
        }
        if ranks.count != graph.vertexCount { return nil }
        return ranks
    }

    private func computeReachability() -> [ObjectIdentifier: Set<ObjectIdentifier>] {
        var result: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        for vertex in graph.vertices {
            var reachable: Set<ObjectIdentifier> = []
            var stack = [vertex]
            while let current = stack.popLast() {
                for edge in graph.edgesForVertex(current) ?? [] {
                    let target = graph.vertices[edge.v]
                    if reachable.insert(ObjectIdentifier(target)).inserted {
                        stack.append(target)
                    }
                }
            }
            result[ObjectIdentifier(vertex)] = reachable
        }
        return result
    }

    private func reachable(_ from: PrecedenceGroupInfo, _ to: PrecedenceGroupInfo) -> Bool {
        reachability[ObjectIdentifier(from)]?.contains(ObjectIdentifier(to)) ?? false
    }
}
