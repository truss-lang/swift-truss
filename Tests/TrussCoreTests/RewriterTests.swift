import Testing
import TrussCore

private func blockBody(_ decl: AST.FunctionDecl) -> [AST.Statement] {
    if case let .Block(statements) = decl.body {
        return statements
    }
    return []
}

final class IdentityRewriter: AST.Rewriter {}

final class IncrementLiteralRewriter: AST.Rewriter {
    override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        AST.IntegerLiteral(
            integerLiteral.token, integerLiteral.value + 1,
            sourceRange: integerLiteral.sourceRange
        )
    }
}

final class LiteralToVariableRewriter: AST.Rewriter {
    override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        AST.Variable(
            name: integerLiteral.token, sourceRange: integerLiteral.sourceRange
        )
    }
}

final class DropExpressionStatementsRewriter: AST.Rewriter {
    override func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
    ) -> Any? {
        AST.Deleted()
    }
}

final class NilReturningRewriter: AST.Rewriter {
    override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        nil
    }
}

final class FoldAndIncrementRewriter: AST.Rewriter {
    override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        AST.IntegerLiteral(
            integerLiteral.token, integerLiteral.value + 10,
            sourceRange: integerLiteral.sourceRange
        )
    }

    override func visitSequentialExpression(
        _ sequentialExpression: AST.SequentialExpression, additional: Any? = nil
    ) -> Any? {
        guard
            let rewritten = super.visitSequentialExpression(
                sequentialExpression, additional: additional
            ) as? AST.SequentialExpression
        else { return nil }
        let ops = rewritten.ops
        let operands = rewritten.operands
        guard operands.count == ops.count + 1, operands.count >= 2 else { return rewritten }
        var tree = operands[0]
        for index in 0 ..< ops.count {
            tree = AST.Binary(
                tree, operands[index + 1], ops[index], sourceRange: rewritten.sourceRange
            )
        }
        return tree
    }
}

@Test func identityPreservesEveryNode() {
    let source = """
    struct S<T> where T: P {
        func f(x: Int) -> Int {
            let arr = [1, 2, 3]
            let dict = ["a": 1]
            let tup = (1, 2)
            let s = "\\(x)!"
            let kp = \\S.x
            let closure = { (y: Int) in y + 1 }
            if x > 0 {
                return x
            } else {
                return 0
            }
            while x > 0 {
                x = x - 1
            }
            for i in arr {
                print(i)
            }
            do {
                try g()
            } catch {
                h()
            }
            return 0
        }
    }
    """
    let program = parseProgram(source)
    let rewritten = IdentityRewriter().rewrite(program)
    #expect(rewritten === program)
    let structDecl = program.statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    #expect(rewritten.statements[0] === structDecl)
}

@Test func unchangedNodesKeepIdentity() {
    let program = parseProgram("func f() { g(x) }")
    let rewritten = IncrementLiteralRewriter().rewrite(program)
    #expect(rewritten === program)
}

@Test func forWithWhereClauseKeepsIdentity() {
    let program = parseProgram("func f(xs: [Int]) { for i in xs where i > 0 { g(i) } }")
    let rewritten = IdentityRewriter().rewrite(program)
    #expect(rewritten === program)
}

@Test func replaceWhereClauseRebuildsFor() {
    let program = parseProgram("func f(xs: [Int]) { for i in xs where i > 0 { g(i) } }")
    let functionDecl = program.statements[0] as! AST.FunctionDecl
    let originalFor = blockBody(functionDecl)[0] as! AST.For
    let rewritten = IncrementLiteralRewriter().rewrite(program)
    let newFunctionDecl = rewritten.statements[0] as! AST.FunctionDecl
    let forStmt = blockBody(newFunctionDecl)[0] as! AST.For
    #expect(forStmt !== originalFor)
    let whereClause = forStmt.whereClause as! AST.SequentialExpression
    let literal = whereClause.operands[1] as! AST.IntegerLiteral
    #expect(literal.value == 1)
}

@Test func replaceLiteralRebuildsCallArguments() {
    let program = parseProgram("func g() { f(1, 2) }")
    let functionDecl = program.statements[0] as! AST.FunctionDecl
    let originalCall = (blockBody(functionDecl)[0] as! AST.ExpressionStatement).expression
        as! AST.Call
    let originalCallee = originalCall.callee
    let rewritten = IncrementLiteralRewriter().rewrite(program)
    let newFunctionDecl = rewritten.statements[0] as! AST.FunctionDecl
    let call = (blockBody(newFunctionDecl)[0] as! AST.ExpressionStatement).expression as! AST.Call
    #expect(call !== originalCall)
    #expect(call.callee === originalCallee)
    #expect((call.arguments[0].value as! AST.IntegerLiteral).value == 2)
    #expect((call.arguments[1].value as! AST.IntegerLiteral).value == 3)
}

@Test func replaceLiteralWithDifferentType() {
    let program = parseProgram("func g() { f(1) }")
    let rewritten = LiteralToVariableRewriter().rewrite(program)
    let functionDecl = rewritten.statements[0] as! AST.FunctionDecl
    let call = (blockBody(functionDecl)[0] as! AST.ExpressionStatement).expression as! AST.Call
    let value = call.arguments[0].value
    #expect(value is AST.Variable)
    #expect((value as! AST.Variable).name.value == "1")
}

@Test func bottomUpFoldRewritesChildrenFirst() {
    let program = parseProgram("func g() { 1 + 2 + 3 }")
    let rewritten = FoldAndIncrementRewriter().rewrite(program)
    let functionDecl = rewritten.statements[0] as! AST.FunctionDecl
    let expression = (blockBody(functionDecl)[0] as! AST.ExpressionStatement).expression
        as! AST.Binary
    let inner = expression.left as! AST.Binary
    #expect((inner.left as! AST.IntegerLiteral).value == 11)
    #expect((inner.right as! AST.IntegerLiteral).value == 12)
    #expect((expression.right as! AST.IntegerLiteral).value == 13)
}

@Test func deleteExpressionStatementsFromFunctionBody() {
    let program = parseProgram("func f() { g()\nh() }")
    let rewritten = DropExpressionStatementsRewriter().rewrite(program)
    let functionDecl = rewritten.statements[0] as! AST.FunctionDecl
    #expect(blockBody(functionDecl).isEmpty)
}

@Test func deleteFromFunctionBodyKeepsSymbols() {
    let program = parseProgram("struct S { func f() { g() } }", semantic: true)
    let structDecl = program.statements[0] as! AST.StructDecl
    let structSymbol = structDecl.symbol
    let functionDecl = structDecl.body[0] as! AST.FunctionDecl
    let functionSymbol = functionDecl.symbol
    #expect(structSymbol != nil)
    #expect(functionSymbol != nil)
    let rewritten = DropExpressionStatementsRewriter().rewrite(program)
    let newStructDecl = rewritten.statements[0] as! AST.StructDecl
    #expect(newStructDecl.symbol === structSymbol)
    let newFunctionDecl = newStructDecl.body[0] as! AST.FunctionDecl
    #expect(newFunctionDecl.symbol === functionSymbol)
    #expect(blockBody(newFunctionDecl).isEmpty)
}

@Test func copyTyOnRebuild() {
    let program = parseProgram("func g() { f(1) }")
    let functionDecl = program.statements[0] as! AST.FunctionDecl
    let originalCall = (blockBody(functionDecl)[0] as! AST.ExpressionStatement).expression
        as! AST.Call
    let originalLiteral = originalCall.arguments[0].value as! AST.IntegerLiteral
    originalLiteral.ty = TrussType.StructType(id: Id.TypeId(id: 0), name: "Int")
    let rewritten = IncrementLiteralRewriter().rewrite(program)
    let newFunctionDecl = rewritten.statements[0] as! AST.FunctionDecl
    let call = (blockBody(newFunctionDecl)[0] as! AST.ExpressionStatement).expression as! AST.Call
    let newLiteral = call.arguments[0].value as! AST.IntegerLiteral
    let ty = newLiteral.ty
    #expect(ty is TrussType.StructType)
    #expect((ty as! TrussType.StructType).name == "Int")
}

@Test func rebuildNestedStructs() {
    let program = parseProgram("func f() { g(1, 2) }\nlet t = (3, 4)\nlet d = [5: 6]")
    let rewritten = IncrementLiteralRewriter().rewrite(program)
    let functionDecl = rewritten.statements[0] as! AST.FunctionDecl
    let call = (blockBody(functionDecl)[0] as! AST.ExpressionStatement).expression as! AST.Call
    #expect((call.arguments[0].value as! AST.IntegerLiteral).value == 2)
    #expect((call.arguments[1].value as! AST.IntegerLiteral).value == 3)
    let tuple = (rewritten.statements[1] as! AST.VariableDecl).initializer as! AST.TupleExpression
    #expect((tuple.elements[0].value as! AST.IntegerLiteral).value == 4)
    #expect((tuple.elements[1].value as! AST.IntegerLiteral).value == 5)
    let dictionary = (rewritten.statements[2] as! AST.VariableDecl).initializer
        as! AST.DictionaryLiteral
    #expect((dictionary.entries[0].key as! AST.IntegerLiteral).value == 6)
    #expect((dictionary.entries[0].value as! AST.IntegerLiteral).value == 7)
}

@Test func nilReturnKeepsNode() {
    let program = parseProgram("func f() { g(1) }")
    let rewritten = NilReturningRewriter().rewrite(program)
    #expect(rewritten === program)
}

@Test func deinitAndAccessorScopesSurviveRewrite() throws {
    let program = parseProgram(
        """
        class C {
            deinit { let x = 1 }
            var p: Int {
                get { 1 }
                set { let y = 2 }
            }
        }
        """,
        semantic: true
    )
    let classDecl = program.statements[0] as! AST.ClassDecl
    let deinitDecl = classDecl.body[0] as! AST.DeinitDecl
    let deinitScope = try #require(deinitDecl.scope)
    let variableDecl = classDecl.body[1] as! AST.VariableDecl
    let getterScope = try #require(variableDecl.accessors[0].scope)
    let setterScope = try #require(variableDecl.accessors[1].scope)
    let rewritten = IncrementLiteralRewriter().rewrite(program)
    let newClassDecl = rewritten.statements[0] as! AST.ClassDecl
    let newDeinitDecl = newClassDecl.body[0] as! AST.DeinitDecl
    #expect(newDeinitDecl !== deinitDecl)
    #expect(newDeinitDecl.scope === deinitScope)
    let newVariableDecl = newClassDecl.body[1] as! AST.VariableDecl
    #expect(newVariableDecl.accessors[0] !== variableDecl.accessors[0])
    #expect(newVariableDecl.accessors[0].scope === getterScope)
    #expect(newVariableDecl.accessors[1].scope === setterScope)
}
