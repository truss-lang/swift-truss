import Testing
import TrussCore
import TrussSyntax

func parse(_ source: String) -> AST.Program {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexer = Lexer(input: stream)
    let tokens = lexer.parse().tokens
    let result = LexerResult(id: Id.SourceId(id: 0), tokens: tokens)
    let parser = Parser(context: context, result, "main")
    return parser.parse()
}

func parseStatements(_ source: String) -> [AST.Statement] {
    parse(source).statements
}

func parseBlockStatements(_ source: String) -> [AST.Statement] {
    let program = parse(source)
    let funcDecl = program.statements[0] as! AST.FunctionDecl
    if case .Block(let stmts) = funcDecl.body {
        return stmts
    }
    return []
}

func firstExpression(_ source: String) -> AST.Expression {
    let body = parseBlockStatements("func main() { \(source) }")
    let exprStmt = body[0] as! AST.ExpressionStatement
    return exprStmt.expression
}

@Test func parseProgramIdPropagation() {
    let program = parse("let x")
    #expect(program.id.id == 0)
    #expect(program.statements.count == 1)
}

@Test func parseSingleEmptyStatement() {
    let statements = parseStatements(";")
    #expect(statements.count == 1)
    #expect(statements[0] is AST.EmptyStatement)
}

@Test func parseMultipleEmptyStatements() {
    let statements = parseStatements(";;;")
    #expect(statements.count == 3)
    #expect(statements[0] is AST.EmptyStatement)
    #expect(statements[1] is AST.EmptyStatement)
    #expect(statements[2] is AST.EmptyStatement)
}

@Test func parseEmptyStatementInBlock() {
    let body = parseBlockStatements("func main() { ; }")
    #expect(body.count == 1)
    #expect(body[0] is AST.EmptyStatement)
}

@Test func parseLetWithoutInitializer() {
    let statements = parseStatements("let x")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Let))
    #expect(decl!.name.kind == .Identifier)
    #expect(decl!.name.value == "x")
    #expect(decl!.typeExpression == nil)
    #expect(decl!.initializer == nil)
}

@Test func parseVarWithoutInitializer() {
    let statements = parseStatements("var y")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Var))
    #expect(decl!.name.value == "y")
    #expect(decl!.typeExpression == nil)
    #expect(decl!.initializer == nil)
}

@Test func parseLetWithInitializer() {
    let statements = parseStatements("let x = 42")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.name.value == "x")
    #expect(decl!.typeExpression == nil)
    #expect(decl!.initializer != nil)
    let infix = decl!.initializer as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops.isEmpty)
    #expect(infix!.operands.count == 1)
    let intLit = infix!.operands[0] as? AST.IntegerLiteral
    #expect(intLit != nil)
    #expect(intLit!.value == 42)
}

@Test func parseLetWithTypeAnnotation() {
    let statements = parseStatements("let x: Int")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.name.value == "x")
    #expect(decl!.typeExpression != nil)
    #expect(decl!.initializer == nil)
    let typeInfix = decl!.typeExpression as? AST.Infix
    #expect(typeInfix != nil)
    #expect(typeInfix!.operands.count == 1)
    let typeVar = typeInfix!.operands[0] as? AST.Variable
    #expect(typeVar != nil)
    #expect(typeVar!.name.value == "Int")
}

@Test func parseVarWithInitializer() {
    let statements = parseStatements("var flag = true")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.name.value == "flag")
    let initInfix = decl!.initializer as? AST.Infix
    #expect(initInfix != nil)
    let boolLit = initInfix!.operands[0] as? AST.BoolLiteral
    #expect(boolLit != nil)
    #expect(boolLit!.value == true)
}

@Test func parseFunctionEmptyBlock() {
    let statements = parseStatements("func main() {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Func))
    #expect(decl!.name.kind == .Identifier)
    #expect(decl!.name.value == "main")
    #expect(decl!.returnTypeExpression == nil)
    if case .Block(let body) = decl!.body {
        #expect(body.isEmpty)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseFunctionExpressionBody() {
    let statements = parseStatements("func foo() = 42")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.returnTypeExpression == nil)
    if case .Expression(let expr) = decl!.body {
        let infix = expr as? AST.Infix
        #expect(infix != nil)
        #expect(infix!.operands.count == 1)
        let intLit = infix!.operands[0] as? AST.IntegerLiteral
        #expect(intLit != nil)
        #expect(intLit!.value == 42)
    } else {
        Issue.record("expected expression body")
    }
}

@Test func parseFunctionWithBlockStatements() {
    let body = parseBlockStatements("func main() { let x }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseFunctionWithMultipleBlockStatements() {
    let body = parseBlockStatements("func main() { let x let y }")
    #expect(body.count == 2)
    let vd1 = body[0] as? AST.VariableDecl
    #expect(vd1 != nil)
    #expect(vd1!.name.value == "x")
    let vd2 = body[1] as? AST.VariableDecl
    #expect(vd2 != nil)
    #expect(vd2!.name.value == "y")
}

@Test func parseNestedFunctionDecl() {
    let body = parseBlockStatements("func main() { func inner() {} }")
    #expect(body.count == 1)
    let inner = body[0] as? AST.FunctionDecl
    #expect(inner != nil)
    #expect(inner!.name.value == "inner")
    if case .Block(let innerBody) = inner!.body {
        #expect(innerBody.isEmpty)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseExpressionStatementWithIdentifier() {
    let expr = firstExpression("x")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.operands.count == 1)
    let varExpr = infix!.operands[0] as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
}

@Test func parseIntegerLiteralExpression() {
    let expr = firstExpression("42")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.operands.count == 1)
    let lit = infix!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseFloatLiteralExpression() {
    let expr = firstExpression("3.14")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.FloatLiteral
    #expect(lit != nil)
    #expect(lit!.value == 3.14)
}

@Test func parseStringLiteralExpression() {
    let expr = firstExpression("\"hello\"")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.StringLiteral
    #expect(lit != nil)
    #expect(lit!.token.value == "\"hello\"")
}

@Test func parseCharLiteralExpression() {
    let expr = firstExpression("'a'")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.CharLiteral
    #expect(lit != nil)
    #expect(lit!.value == "a")
}

@Test func parseBooleanTrueLiteralExpression() {
    let expr = firstExpression("true")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.BoolLiteral
    #expect(lit != nil)
    #expect(lit!.value == true)
}

@Test func parseBooleanFalseLiteralExpression() {
    let expr = firstExpression("false")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.BoolLiteral
    #expect(lit != nil)
    #expect(lit!.value == false)
}

@Test func parseNullLiteralExpression() {
    let expr = firstExpression("null")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.NullLiteral
    #expect(lit != nil)
}

@Test func parseFunctionCallNoArgs() {
    let expr = firstExpression("foo()")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.operands.count == 1)
    let call = infix!.operands[0] as? AST.Call
    #expect(call != nil)
    let callee = call!.callee as? AST.Variable
    #expect(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(call!.arguments.isEmpty)
}

@Test func parseMemberAccess() {
    let expr = firstExpression("a.b")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let member = infix!.operands[0] as? AST.MemberAccess
    #expect(member != nil)
    let obj = member!.object as? AST.Variable
    #expect(obj != nil)
    #expect(obj!.name.value == "a")
    #expect(member!.member.value == "b")
    #expect(member!.token.kind == .Operator(.Dot))
}

@Test func parseChainedMemberAccess() {
    let expr = firstExpression("a.b.c")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let member = infix!.operands[0] as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "c")
    let innerMember = member!.object as? AST.MemberAccess
    #expect(innerMember != nil)
    #expect(innerMember!.member.value == "b")
    let obj = innerMember!.object as? AST.Variable
    #expect(obj != nil)
    #expect(obj!.name.value == "a")
}

@Test func parseCallOnMemberAccess() {
    let expr = firstExpression("a.b()")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let call = infix!.operands[0] as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.isEmpty)
    let callee = call!.callee as? AST.MemberAccess
    #expect(callee != nil)
    #expect(callee!.member.value == "b")
    let obj = callee!.object as? AST.Variable
    #expect(obj != nil)
    #expect(obj!.name.value == "a")
}

@Test func parseCallOnCall() {
    let expr = firstExpression("foo()()")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let outer = infix!.operands[0] as? AST.Call
    #expect(outer != nil)
    let inner = outer!.callee as? AST.Call
    #expect(inner != nil)
    let base = inner!.callee as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "foo")
}

@Test func parseInfixExpression() {
    let expr = firstExpression("a + b")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops.count == 1)
    #expect(infix!.ops[0].kind == .Operator(.Plus))
    #expect(infix!.operands.count == 2)
    let left = infix!.operands[0] as? AST.Variable
    #expect(left != nil)
    #expect(left!.name.value == "a")
    let right = infix!.operands[1] as? AST.Variable
    #expect(right != nil)
    #expect(right!.name.value == "b")
}

@Test func parseComplexInfixExpression() {
    let expr = firstExpression("a + b * c - d")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops.count == 3)
    #expect(infix!.ops[0].kind == .Operator(.Plus))
    #expect(infix!.ops[1].kind == .Operator(.Multiply))
    #expect(infix!.ops[2].kind == .Operator(.Minus))
    #expect(infix!.operands.count == 4)
    let names = ["a", "b", "c", "d"]
    for i in 0..<4 {
        let v = infix!.operands[i] as? AST.Variable
        #expect(v != nil)
        #expect(v!.name.value == names[i])
    }
}

@Test func parseAssignmentExpression() {
    let expr = firstExpression("x = 42")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops.count == 1)
    #expect(infix!.ops[0].kind == .Operator(.Assign))
    #expect(infix!.operands.count == 2)
    let target = infix!.operands[0] as? AST.Variable
    #expect(target != nil)
    #expect(target!.name.value == "x")
    let value = infix!.operands[1] as? AST.IntegerLiteral
    #expect(value != nil)
    #expect(value!.value == 42)
}

@Test func parseComparisonExpression() {
    let expr = firstExpression("a == b")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops.count == 1)
    #expect(infix!.ops[0].kind == .Operator(.Equal))
    #expect(infix!.operands.count == 2)
}

@Test func parseLogicalAndExpression() {
    let expr = firstExpression("a && b")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops[0].kind == .Operator(.And))
}

@Test func parseLogicalOrExpression() {
    let expr = firstExpression("a || b")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops[0].kind == .Operator(.Or))
}

@Test func parseMixedDeclarations() {
    let statements = parseStatements("let x = 1 func foo() {}")
    #expect(statements.count == 2)
    let vd = statements[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
    let fd = statements[1] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "foo")
}

@Test func parseMultipleVariableDeclarations() {
    let statements = parseStatements("let a = 1 let b = 2 let c = 3")
    #expect(statements.count == 3)
    let names = ["a", "b", "c"]
    for i in 0..<3 {
        let vd = statements[i] as? AST.VariableDecl
        #expect(vd != nil)
        #expect(vd!.name.value == names[i])
    }
}

@Test func parseFunctionWithEmptyStatementInBody() {
    let body = parseBlockStatements("func main() { ; let x }")
    #expect(body.count == 2)
    #expect(body[0] is AST.EmptyStatement)
    let vd = body[1] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseHexStringLiteral() {
    let expr = firstExpression("0xFF")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 255)
}

@Test func parseBinaryStringLiteral() {
    let expr = firstExpression("0b1010")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 10)
}

@Test func parseUnderscoredIntegerLiteral() {
    let expr = firstExpression("1_000_000")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 1_000_000)
}

@Test func parseScientificFloatLiteral() {
    let expr = firstExpression("1.5e-3")
    let infix = expr as? AST.Infix
    #expect(infix != nil)
    let lit = infix!.operands[0] as? AST.FloatLiteral
    #expect(lit != nil)
    #expect(lit!.value == 0.0015)
}

@Test func parseReturnWithIntegerLiteral() {
    let body = parseBlockStatements("func main() { return 42 }")
    #expect(body.count == 1)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    let infix = ret!.value as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.operands.count == 1)
    let lit = infix!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseReturnWithComplexExpression() {
    let body = parseBlockStatements("func main() { return a + b }")
    #expect(body.count == 1)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    let infix = ret!.value as? AST.Infix
    #expect(infix != nil)
    #expect(infix!.ops.count == 1)
    #expect(infix!.ops[0].kind == .Operator(.Plus))
    #expect(infix!.operands.count == 2)
    let left = infix!.operands[0] as? AST.Variable
    #expect(left != nil)
    #expect(left!.name.value == "a")
    let right = infix!.operands[1] as? AST.Variable
    #expect(right != nil)
    #expect(right!.name.value == "b")
}

@Test func parseReturnWithoutValueFollowedBySemicolon() {
    let body = parseBlockStatements("func main() { return; }")
    #expect(body.count == 2)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    #expect(ret!.value == nil)
    #expect(body[1] is AST.EmptyStatement)
}

@Test func parseReturnWithoutValueOnOwnLine() {
    let body = parseBlockStatements("func main() {\nreturn\n}")
    #expect(body.count == 1)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    #expect(ret!.value == nil)
}

@Test func parseReturnFollowedByAnotherStatement() {
    let body = parseBlockStatements("func main() { return x; let y }")
    #expect(body.count == 3)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    let infix = ret!.value as? AST.Infix
    #expect(infix != nil)
    let varExpr = infix!.operands[0] as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
    #expect(body[1] is AST.EmptyStatement)
    let vd = body[2] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "y")
}
