import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSyntax

func parseWithDiagnostics(_ source: String) -> (AST.Program, [Diagnostic]) {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexer = Lexer(input: stream)
    let tokens = lexer.parse().tokens
    let result = LexerResult(id: Id.SourceId(id: 0), tokens: tokens)
    let parser = Parser(context: context, packageName: "main", result)
    return (parser.parse(), context.diagnositicEngine.diagnostics)
}

func parse(_ source: String) -> AST.Program {
    parseWithDiagnostics(source).0
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

func modifierKind(_ kind: AST.ModifierKind, equals expected: AST.ModifierKind) -> Bool {
    switch (kind, expected) {
    case (.Open(let a), .Open(let b)): return a == b
    case (.Public(let a), .Public(let b)): return a == b
    case (.Protected(let a), .Protected(let b)): return a == b
    case (.PackagePrivate(let a), .PackagePrivate(let b)): return a == b
    case (.Internal(let a), .Internal(let b)): return a == b
    case (.FilePrivate(let a), .FilePrivate(let b)): return a == b
    case (.Private(let a), .Private(let b)): return a == b
    case (.Abstract, .Abstract), (.Final, .Final), (.Mutating, .Mutating),
        (.Nonmutating, .Nonmutating), (.Convenience, .Convenience),
        (.Override, .Override), (.Lazy, .Lazy), (.Weak, .Weak),
        (.Unowned, .Unowned), (.Indirect, .Indirect), (.Isolated, .Isolated):
        return true
    default: return false
    }
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
    let intLit = decl!.initializer as? AST.IntegerLiteral
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
    let typeVar = decl!.typeExpression as? AST.Variable
    #expect(typeVar != nil)
    #expect(typeVar!.name.value == "Int")
}

@Test func parseVarWithInitializer() {
    let statements = parseStatements("var flag = true")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.name.value == "flag")
    let boolLit = decl?.initializer as? AST.BoolLiteral
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
        let intLit = expr as? AST.IntegerLiteral
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
    let varExpr = expr as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
}

@Test func parseIntegerLiteralExpression() {
    let expr = firstExpression("42")
    let lit = expr as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseFloatLiteralExpression() {
    let expr = firstExpression("3.14")
    let lit = expr as? AST.FloatLiteral
    #expect(lit != nil)
    #expect(lit!.value == 3.14)
}

@Test func parseStringLiteralExpression() {
    let expr = firstExpression("\"hello\"")
    let lit = expr as? AST.StringLiteral
    #expect(lit != nil)
    #expect(lit!.token.value == "hello")
}

@Test func parseCharLiteralExpression() {
    let expr = firstExpression("'a'")
    let lit = expr as? AST.CharLiteral
    #expect(lit != nil)
    #expect(lit!.value == "a")
}

@Test func parseBooleanTrueLiteralExpression() {
    let expr = firstExpression("true")
    let lit = expr as? AST.BoolLiteral
    #expect(lit != nil)
    #expect(lit!.value == true)
}

@Test func parseBooleanFalseLiteralExpression() {
    let expr = firstExpression("false")
    let lit = expr as? AST.BoolLiteral
    #expect(lit != nil)
    #expect(lit!.value == false)
}

@Test func parseNullLiteralExpression() {
    let expr = firstExpression("null")
    let lit = expr as? AST.NullLiteral
    #expect(lit != nil)
}

@Test func parseFunctionCallNoArgs() {
    let expr = firstExpression("foo()")
    let call = expr as? AST.Call
    #expect(call != nil)
    let callee = call!.callee as? AST.Variable
    #expect(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(call!.arguments.isEmpty)
}

@Test func parseMemberAccess() {
    let expr = firstExpression("a.b")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    let obj = member!.object as? AST.Variable
    #expect(obj != nil)
    #expect(obj!.name.value == "a")
    #expect(member!.member.value == "b")
    #expect(member!.token.kind == .Operator(.Dot))
}

@Test func parseChainedMemberAccess() {
    let expr = firstExpression("a.b.c")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "c")
    let innerMember = member!.object as? AST.MemberAccess
    #expect(innerMember != nil)
    #expect(innerMember!.member.value == "b")
    let obj = innerMember!.object as? AST.Variable
    #expect(obj != nil)
    #expect(obj!.name.value == "a")
    #expect(member!.isOptional == false)
}

@Test func parseOptionalChaining() {
    let expr = firstExpression("a?.b")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.isOptional == true)
    #expect(member!.token.kind == .Operator(.QuestionMarkDot))
    #expect(member!.member.value == "b")
}

@Test func parseChainedOptionalChaining() {
    let expr = firstExpression("a?.b?.c")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.isOptional == true)
    #expect(member!.member.value == "c")
    let inner = member!.object as? AST.MemberAccess
    #expect(inner != nil)
    #expect(inner!.isOptional == true)
    #expect(inner!.member.value == "b")
}

@Test func parseMixedOptionalAndRegular() {
    let expr = firstExpression("a.b?.c")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.isOptional == true)
    let inner = member!.object as? AST.MemberAccess
    #expect(inner != nil)
    #expect(inner!.isOptional == false)
}

@Test func parseCastAsExpression() {
    let expr = firstExpression("x as Int32")
    let cast = expr as? AST.CastExpression
    #expect(cast != nil)
    #expect(cast!.kind == .As)
    #expect(cast!.token.kind == .Keyword(.As))
    let left = cast!.left as? AST.Variable
    #expect(left!.name.value == "x")
    let right = cast!.right as? AST.Variable
    #expect(right!.name.value == "Int32")
}

@Test func parseCastAsQuestionExpression() {
    let expr = firstExpression("x as? Int32")
    let cast = expr as? AST.CastExpression
    #expect(cast != nil)
    #expect(cast!.kind == .AsQuestion)
}

@Test func parseCastAsExclamationExpression() {
    let expr = firstExpression("x as! Int32")
    let cast = expr as? AST.CastExpression
    #expect(cast != nil)
    #expect(cast!.kind == .AsExclamation)
}

@Test func parseIsExpression() {
    let expr = firstExpression("x is Int32")
    let cast = expr as? AST.CastExpression
    #expect(cast != nil)
    #expect(cast!.kind == .Is)
    #expect(cast!.token.kind == .Keyword(.Is))
}

@Test func parseCastChain() {
    let expr = firstExpression("a as B as? C")
    let cast = expr as? AST.CastExpression
    #expect(cast != nil)
    #expect(cast!.kind == .AsQuestion)
    let inner = cast!.left as? AST.CastExpression
    #expect(inner != nil)
    #expect(inner!.kind == .As)
    #expect(cast!.right is AST.Variable)
}

@Test func parseCallOnMemberAccess() {
    let expr = firstExpression("a.b()")
    let call = expr as? AST.Call
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
    let outer = expr as? AST.Call
    #expect(outer != nil)
    let inner = outer!.callee as? AST.Call
    #expect(inner != nil)
    let base = inner!.callee as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "foo")
}

@Test func parseInfixExpression() {
    let expr = firstExpression("a + b")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
    #expect(sequentialExpression!.operands.count == 2)
    let left = sequentialExpression!.operands[0] as? AST.Variable
    #expect(left != nil)
    #expect(left!.name.value == "a")
    let right = sequentialExpression!.operands[1] as? AST.Variable
    #expect(right != nil)
    #expect(right!.name.value == "b")
}

@Test func parseComplexInfixExpression() {
    let expr = firstExpression("a + b * c - d")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.count == 3)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
    #expect(sequentialExpression!.ops[1].kind == .Operator(.Multiply))
    #expect(sequentialExpression!.ops[2].kind == .Operator(.Minus))
    #expect(sequentialExpression!.operands.count == 4)
    let names = ["a", "b", "c", "d"]
    for i in 0..<4 {
        let v = sequentialExpression!.operands[i] as? AST.Variable
        #expect(v != nil)
        #expect(v!.name.value == names[i])
    }
}

@Test func parseAssignmentExpression() {
    let expr = firstExpression("x = 42")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Assign))
    #expect(sequentialExpression!.operands.count == 2)
    let target = sequentialExpression!.operands[0] as? AST.Variable
    #expect(target != nil)
    #expect(target!.name.value == "x")
    let value = sequentialExpression!.operands[1] as? AST.IntegerLiteral
    #expect(value != nil)
    #expect(value!.value == 42)
}

@Test func parseComparisonExpression() {
    let expr = firstExpression("a == b")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Equal))
    #expect(sequentialExpression!.operands.count == 2)
}

@Test func parseLogicalAndExpression() {
    let expr = firstExpression("a && b")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.And))
}

@Test func parseLogicalOrExpression() {
    let expr = firstExpression("a || b")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Or))
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
    let lit = expr as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 255)
}

@Test func parseBinaryStringLiteral() {
    let expr = firstExpression("0b1010")
    let lit = expr as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 10)
}

@Test func parseUnderscoredIntegerLiteral() {
    let expr = firstExpression("1_000_000")
    let lit = expr as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 1_000_000)
}

@Test func parseScientificFloatLiteral() {
    let expr = firstExpression("1.5e-3")
    let lit = expr as? AST.FloatLiteral
    #expect(lit != nil)
    #expect(lit!.value == 0.0015)
}

@Test func parseReturnWithIntegerLiteral() {
    let body = parseBlockStatements("func main() { return 42 }")
    #expect(body.count == 1)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    let lit = ret!.value as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseReturnWithComplexExpression() {
    let body = parseBlockStatements("func main() { return a + b }")
    #expect(body.count == 1)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    let sequentialExpression = ret!.value as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
    #expect(sequentialExpression!.operands.count == 2)
    let left = sequentialExpression!.operands[0] as? AST.Variable
    #expect(left != nil)
    #expect(left!.name.value == "a")
    let right = sequentialExpression!.operands[1] as? AST.Variable
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
    let varExpr = ret!.value as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
    #expect(body[1] is AST.EmptyStatement)
    let vd = body[2] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "y")
}

@Test func parseThrowWithMemberAccess() {
    let body = parseBlockStatements("func main() { throw MyError.bad }")
    #expect(body.count == 1)
    let throwStmt = body[0] as? AST.Throw
    #expect(throwStmt != nil)
    #expect(throwStmt!.token.kind == .Keyword(.Throw))
    let memberAccess = throwStmt!.expression as? AST.MemberAccess
    #expect(memberAccess != nil)
    #expect(memberAccess!.member.value == "bad")
}

@Test func parseThrowWithVariable() {
    let body = parseBlockStatements("func main() { throw err }")
    #expect(body.count == 1)
    let throwStmt = body[0] as? AST.Throw
    #expect(throwStmt != nil)
    let varExpr = throwStmt!.expression as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "err")
}

@Test func parseThrowWithComplexExpression() {
    let body = parseBlockStatements("func main() { throw a + b }")
    #expect(body.count == 1)
    let throwStmt = body[0] as? AST.Throw
    #expect(throwStmt != nil)
    let sequentialExpression = throwStmt!.expression as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
}

@Test func parseThrowInClosureBody() {
    let body = parseBlockStatements("func main() { let f = { throw E.x } }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    let closure = vd!.initializer as? AST.Closure
    #expect(closure != nil)
    let throwStmt = closure!.body[0] as? AST.Throw
    #expect(throwStmt != nil)
    #expect(throwStmt!.token.kind == .Keyword(.Throw))
}

@Test func parseThrowMissingExpressionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { throw }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected expression after 'throw'"))
}

@Test func parseTryExpression() {
    let expr = firstExpression("try foo()")
    let tryExpr = expr as? AST.TryExpression
    #expect(tryExpr != nil)
    #expect(tryExpr!.kind == .Try)
    #expect(tryExpr!.token.kind == .Keyword(.Try))
    let call = tryExpr!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryQuestionExpression() {
    let expr = firstExpression("try? foo()")
    let tryExpr = expr as? AST.TryExpression
    #expect(tryExpr != nil)
    #expect(tryExpr!.kind == .TryQuestion)
    let call = tryExpr!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryExclamationExpression() {
    let expr = firstExpression("try! foo()")
    let tryExpr = expr as? AST.TryExpression
    #expect(tryExpr != nil)
    #expect(tryExpr!.kind == .TryExclamation)
    let call = tryExpr!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryWrapsWholeExpression() {
    let expr = firstExpression("try foo() + bar")
    let tryExpr = expr as? AST.TryExpression
    #expect(tryExpr != nil)
    #expect(tryExpr!.kind == .Try)
    let sequentialExpression = tryExpr!.expression as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
}

@Test func parseTryInVariableInitializer() {
    let body = parseBlockStatements("func main() { let x = try? foo() }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    let tryExpr = vd!.initializer as? AST.TryExpression
    #expect(tryExpr != nil)
    #expect(tryExpr!.kind == .TryQuestion)
}

@Test func parseTryInExpressionStatementWithOperator() {
    let expr = firstExpression("a + try b")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let right = sequentialExpression!.operands[1] as? AST.TryExpression
    #expect(right != nil)
    #expect(right!.kind == .Try)
    let variable = right!.expression as? AST.Variable
    #expect(variable != nil)
    #expect(variable!.name.value == "b")
}

@Test func parseTryGreedyExclamationAfterTry() {
    let expr = firstExpression("try !flag")
    let tryExpr = expr as? AST.TryExpression
    #expect(tryExpr != nil)
    #expect(tryExpr!.kind == .TryExclamation)
    let variable = tryExpr!.expression as? AST.Variable
    #expect(variable != nil)
    #expect(variable!.name.value == "flag")
}

@Test func parseTryNested() {
    let expr = firstExpression("try try foo()")
    let outer = expr as? AST.TryExpression
    #expect(outer != nil)
    #expect(outer!.kind == .Try)
    let inner = outer!.expression as? AST.TryExpression
    #expect(inner != nil)
    let call = inner!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryMissingExpressionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { try }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected expression after 'try'"))
}

@Test func parseFunctionWithoutThrows() {
    let statements = parseStatements("func f() -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.throwsClause == nil)
}

@Test func parseFunctionThrowsClause() {
    let statements = parseStatements("func f() throws {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.throwsClause != nil)
    #expect(decl!.throwsClause!.token.kind == .Keyword(.Throws))
    #expect(decl!.throwsClause!.types == nil)
}

@Test func parseFunctionThrowsWithReturnType() {
    let statements = parseStatements("func f() throws -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.throwsClause != nil)
    #expect(decl!.throwsClause!.types == nil)
    let returnType = decl!.returnTypeExpression as? AST.Variable
    #expect(returnType != nil)
    #expect(returnType!.name.value == "Int")
}

@Test func parseFunctionTypedThrows() {
    let statements = parseStatements("func f() throws(E1) -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let throwsClause = decl!.throwsClause
    #expect(throwsClause != nil)
    #expect(throwsClause!.types?.count == 1)
    let type0 = throwsClause!.types![0] as? AST.Variable
    #expect(type0 != nil)
    #expect(type0!.name.value == "E1")
}

@Test func parseFunctionMultipleTypedThrows() {
    let statements = parseStatements("func f() throws(E1, E2) -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let throwsClause = decl!.throwsClause
    #expect(throwsClause != nil)
    #expect(throwsClause!.types?.count == 2)
    let type0 = throwsClause!.types![0] as? AST.Variable
    #expect(type0!.name.value == "E1")
    let type1 = throwsClause!.types![1] as? AST.Variable
    #expect(type1!.name.value == "E2")
}

@Test func parseInitThrowsClause() {
    let statements = parseStatements("struct S { init() throws {} }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.throwsClause != nil)
    #expect(initDecl!.throwsClause!.types == nil)
}

@Test func parseInitTypedThrows() {
    let statements = parseStatements("struct S { init() throws(E) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.throwsClause?.types?.count == 1)
}

@Test func parseInitWithParameters() {
    let statements = parseStatements("struct S { init(x: Int) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.parameters.count == 1)
    #expect(initDecl!.parameters[0].name.value == "x")
    #expect(initDecl!.parameters[0].type != nil)
}

@Test func parseInitWithLabelAndDefaultValue() {
    let statements = parseStatements("struct S { init(_ a: Int, b: Int = 42) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.parameters.count == 2)
    #expect(initDecl!.parameters[0].label == nil)
    #expect(initDecl!.parameters[0].name.value == "a")
    #expect(initDecl!.parameters[1].label?.value == "b")
    #expect(initDecl!.parameters[1].name.value == "b")
    #expect(initDecl!.parameters[1].defaultValue != nil)
}

@Test func parseInitWithParametersAndThrows() {
    let statements = parseStatements("struct S { init(x: Int) throws(E) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.parameters.count == 1)
    #expect(initDecl!.parameters[0].name.value == "x")
    #expect(initDecl!.throwsClause?.types?.count == 1)
}

@Test func parseInitWithTrailingComma() {
    let statements = parseStatements("struct S { init(x: Int,) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.parameters.count == 1)
}

@Test func parseSubscriptThrowsClause() {
    let statements = parseStatements("struct S { subscript(i: Int) throws -> Int { i } }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    #expect(subDecl != nil)
    #expect(subDecl!.throwsClause != nil)
    #expect(subDecl!.throwsClause!.types == nil)
}

@Test func parseClosureTypeThrows() {
    let body = parseBlockStatements("func main() { let f: (Int) throws -> Int = g }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    #expect(closureType != nil)
    #expect(closureType!.throwsClause != nil)
    #expect(closureType!.throwsClause!.types == nil)
}

@Test func parseClosureTypeTypedThrows() {
    let body = parseBlockStatements("func main() { let f: (Int, String) throws(E1) -> Bool = g }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    #expect(closureType != nil)
    #expect(closureType!.throwsClause?.types?.count == 1)
}

@Test func parseClosureSignatureThrows() {
    let body = parseBlockStatements("func main() { { (x: Int) throws -> Int in x } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    #expect(closure!.signature?.throwsClause != nil)
    #expect(closure!.signature!.throwsClause!.types == nil)
}

@Test func parseClosureSignatureTypedThrows() {
    let body = parseBlockStatements("func main() { { (x: Int) throws(E1) -> Int in x } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    #expect(closure!.signature?.throwsClause?.types?.count == 1)
}

@Test func parseDoAlone() {
    let body = parseBlockStatements("func main() { do { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.token.kind == .Keyword(.Do))
    #expect(doExpr!.body.isEmpty)
    #expect(doExpr!.catches.isEmpty)
}

@Test func parseDoWithBody() {
    let body = parseBlockStatements("func main() { do { foo() } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.body.count == 1)
    #expect(doExpr!.catches.isEmpty)
}

@Test func parseDoCatchBare() {
    let body = parseBlockStatements("func main() { do { } catch { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.catches.count == 1)
    #expect(doExpr!.catches[0].pattern == nil)
    #expect(doExpr!.catches[0].whereCondition == nil)
}

@Test func parseDoCatchLetBinding() {
    let body = parseBlockStatements("func main() { do { } catch let e { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let binding = catchClause.pattern as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "e")
}

@Test func parseDoCatchQualifiedPattern() {
    let body = parseBlockStatements("func main() { do { } catch E.bad { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let memberAccess = catchClause.pattern as? AST.MemberAccess
    #expect(memberAccess != nil)
    #expect(memberAccess!.member.value == "bad")
}

@Test func parseDoCatchImplicitPattern() {
    let body = parseBlockStatements("func main() { do { } catch .bad { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let implicit = catchClause.pattern as? AST.ImplicitMemberAccess
    #expect(implicit != nil)
    #expect(implicit!.name.value == "bad")
}

@Test func parseDoCatchWildcard() {
    let body = parseBlockStatements("func main() { do { } catch _ { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    #expect(catchClause.pattern is AST.WildcardPattern)
}

@Test func parseDoCatchWhereOnly() {
    let body = parseBlockStatements("func main() { do { } catch where cond { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    #expect(catchClause.pattern == nil)
    #expect(catchClause.whereToken != nil)
    #expect(catchClause.whereCondition != nil)
}

@Test func parseDoCatchPatternWithWhere() {
    let body = parseBlockStatements("func main() { do { } catch let e where cond { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let binding = catchClause.pattern as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "e")
    #expect(catchClause.whereCondition != nil)
}

@Test func parseDoMultipleCatches() {
    let body = parseBlockStatements("func main() { do { } catch A { } catch B { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.catches.count == 2)
}

@Test func parseDoAsExpressionValue() {
    let body = parseBlockStatements("func main() { let x = do { 1 } }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    let doExpr = vd!.initializer as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.body.count == 1)
}

@Test func parseDoMissingOpenBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { do }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '{' after 'do'"))
}

@Test func parseDoFinallyAlone() {
    let body = parseBlockStatements("func main() { do { } finally { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.catches.isEmpty)
    #expect(doExpr!.finallyBody != nil)
    #expect(doExpr!.finallyBody!.isEmpty)
}

@Test func parseDoCatchFinally() {
    let body = parseBlockStatements("func main() { do { } catch { } finally { cleanup() } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.catches.count == 1)
    #expect(doExpr!.finallyBody?.count == 1)
}

@Test func parseDoCatchLetFinally() {
    let body = parseBlockStatements("func main() { do { } catch let e { } finally { log(e) } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.catches.count == 1)
    let binding = doExpr!.catches[0].pattern as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "e")
    #expect(doExpr!.finallyBody != nil)
}

@Test func parseDoWithoutFinally() {
    let body = parseBlockStatements("func main() { do { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    #expect(doExpr!.finallyBody == nil)
}

@Test func parseEmptyModule() {
    let statements = parseStatements("module Foo {}")
    #expect(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    #expect(module != nil)
    #expect(module!.token.kind == .Keyword(.Module))
    #expect(module!.name.kind == .Identifier)
    #expect(module!.name.value == "Foo")
    #expect(module!.body.isEmpty)
}

@Test func parseModuleWithVariableDecl() {
    let statements = parseStatements("module Foo { let x }")
    #expect(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    #expect(module != nil)
    #expect(module!.name.value == "Foo")
    #expect(module!.body.count == 1)
    let vd = module!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseModuleWithFunctionDecl() {
    let statements = parseStatements("module Foo { func bar() {} }")
    #expect(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    #expect(module != nil)
    #expect(module!.name.value == "Foo")
    #expect(module!.body.count == 1)
    let fd = module!.body[0] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "bar")
    if case .Block(let body) = fd!.body {
        #expect(body.isEmpty)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseModuleWithMultipleDeclarations() {
    let statements = parseStatements("module Foo { let x func bar() {} var y }")
    #expect(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    #expect(module != nil)
    #expect(module!.body.count == 3)
    let vd1 = module!.body[0] as? AST.VariableDecl
    #expect(vd1 != nil)
    #expect(vd1!.name.value == "x")
    let fd = module!.body[1] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "bar")
    let vd2 = module!.body[2] as? AST.VariableDecl
    #expect(vd2 != nil)
    #expect(vd2!.name.value == "y")
}

@Test func parseModuleWithEmptyStatement() {
    let statements = parseStatements("module Foo { ; }")
    #expect(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    #expect(module != nil)
    #expect(module!.body.count == 1)
    #expect(module!.body[0] is AST.EmptyStatement)
}

@Test func parseNestedModule() {
    let statements = parseStatements("module Outer { module Inner {} }")
    #expect(statements.count == 1)
    let outer = statements[0] as? AST.ModuleDecl
    #expect(outer != nil)
    #expect(outer!.name.value == "Outer")
    #expect(outer!.body.count == 1)
    let inner = outer!.body[0] as? AST.ModuleDecl
    #expect(inner != nil)
    #expect(inner!.name.value == "Inner")
    #expect(inner!.body.isEmpty)
}

@Test func parseModuleWithVariableInitializer() {
    let statements = parseStatements("module Foo { let x = 42 }")
    #expect(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    #expect(module != nil)
    #expect(module!.body.count == 1)
    let vd = module!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
    let lit = vd!.initializer as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseModuleFollowedByDeclaration() {
    let statements = parseStatements("module Foo {} let x")
    #expect(statements.count == 2)
    let module = statements[0] as? AST.ModuleDecl
    #expect(module != nil)
    #expect(module!.name.value == "Foo")
    let vd = statements[1] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseOperatorInfix() {
    let statements = parseStatements("operator + infix")
    #expect(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    #expect(op != nil)
    #expect(op!.name.value == "+")
    if case .Infix(let t) = op!.kind {
        #expect(t.kind == .Keyword(.Infix))
    } else {
        #expect(Bool(false))
    }

}

@Test func parseOperatorPrefix() {
    let statements = parseStatements("operator - prefix")
    #expect(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    #expect(op != nil)
    #expect(op!.name.value == "-")
    if case .Prefix(let t) = op!.kind {
        #expect(t.kind == .Keyword(.Prefix))
    } else {
        #expect(Bool(false))
    }

}

@Test func parseOperatorPostfix() {
    let statements = parseStatements("operator ++ postfix")
    #expect(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    #expect(op != nil)
    #expect(op!.name.value == "++")
    if case .Postfix(let t) = op!.kind {
        #expect(t.kind == .Keyword(.Postfix))
    } else {
        #expect(Bool(false))
    }

}

@Test func parseEmptyPrecedenceGroup() {
    let statements = parseStatements("precedencegroup Foo {}")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.name.value == "Foo")
    #expect(pg!.associativity == .None)
    #expect(pg!.assignment == false)
    #expect(pg!.higherThan.isEmpty)
    #expect(pg!.lowerThan.isEmpty)
}

@Test func parsePrecedenceGroupAssociativityLeft() {
    let statements = parseStatements("precedencegroup Foo { associativity: left }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.associativity == .Left)
    #expect(pg!.associativityToken != nil)
}

@Test func parsePrecedenceGroupAssociativityRight() {
    let statements = parseStatements("precedencegroup Foo { associativity: right }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.associativity == .Right)
}

@Test func parsePrecedenceGroupAssociativityNone() {
    let statements = parseStatements("precedencegroup Foo { associativity: none }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.associativity == .None)
}

@Test func parsePrecedenceGroupAssignmentTrue() {
    let statements = parseStatements("precedencegroup Foo { assignment: true }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.assignment == true)
    #expect(pg!.assignmentToken != nil)
}

@Test func parsePrecedenceGroupAssignmentFalse() {
    let statements = parseStatements("precedencegroup Foo { assignment: false }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.assignment == false)
}

@Test func parsePrecedenceGroupHigherThanSingle() {
    let statements = parseStatements("precedencegroup Foo { higherThan: Bar }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.higherThan.count == 1)
    let bar = pg!.higherThan[0] as? AST.Variable
    #expect(bar != nil)
    #expect(bar!.name.value == "Bar")
    #expect(pg!.higherThanTokens.count == 1)
}

@Test func parsePrecedenceGroupHigherThanMultiple() {
    let statements = parseStatements("precedencegroup Foo { higherThan: Bar, Baz }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.higherThan.count == 2)
    let bar = pg!.higherThan[0] as? AST.Variable
    #expect(bar != nil)
    #expect(bar!.name.value == "Bar")
    let baz = pg!.higherThan[1] as? AST.Variable
    #expect(baz != nil)
    #expect(baz!.name.value == "Baz")
}

@Test func parsePrecedenceGroupLowerThanSingle() {
    let statements = parseStatements("precedencegroup Foo { lowerThan: Bar }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.lowerThan.count == 1)
    let bar = pg!.lowerThan[0] as? AST.Variable
    #expect(bar != nil)
    #expect(bar!.name.value == "Bar")
    #expect(pg!.lowerThanTokens.count == 1)
}

@Test func parsePrecedenceGroupLowerThanMultiple() {
    let statements = parseStatements("precedencegroup Foo { lowerThan: Bar, Baz }")
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.lowerThan.count == 2)
    #expect((pg!.lowerThan[0] as! AST.Variable).name.value == "Bar")
    #expect((pg!.lowerThan[1] as! AST.Variable).name.value == "Baz")
}

@Test func parsePrecedenceGroupAllProperties() {
    let statements = parseStatements(
        "precedencegroup Foo { associativity: left assignment: true higherThan: Bar lowerThan: Baz }"
    )
    #expect(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.name.value == "Foo")
    #expect(pg!.associativity == .Left)
    #expect(pg!.assignment == true)
    #expect(pg!.higherThan.count == 1)
    #expect((pg!.higherThan[0] as! AST.Variable).name.value == "Bar")
    #expect(pg!.lowerThan.count == 1)
    #expect((pg!.lowerThan[0] as! AST.Variable).name.value == "Baz")
}

@Test func parsePrecedenceGroupFollowedByDeclaration() {
    let statements = parseStatements("precedencegroup Foo {} let x")
    #expect(statements.count == 2)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.name.value == "Foo")
    let vd = statements[1] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parsePrecedenceGroupMultipleHigherThanClauses() {
    let (program, diagnostics) = parseWithDiagnostics(
        "precedencegroup Foo { higherThan: Bar higherThan: Baz }")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.isEmpty)
    let pg = program.statements[0] as? AST.PrecedenceGroupDecl
    #expect(pg != nil)
    #expect(pg!.higherThan.count == 2)
    #expect(pg!.higherThanTokens.count == 2)
    let bar = pg!.higherThan[0] as? AST.Variable
    #expect(bar != nil)
    #expect(bar!.name.value == "Bar")
    let baz = pg!.higherThan[1] as? AST.Variable
    #expect(baz != nil)
    #expect(baz!.name.value == "Baz")
}

@Test func parsePrecedenceGroupDuplicateAssociativityReportsFirstDefinition() throws {
    let (_, diagnostics) = parseWithDiagnostics(
        "precedencegroup Foo { associativity: left associativity: right }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "associativity can only be set once")
    #expect(errors[0].notes.count == 1)
    let note = errors[0].notes[0]
    #expect(note.severity == .note)
    #expect(note.message == "previous definition here")
    #expect(note.range.start.offset < errors[0].range.start.offset)
}

@Test func sourceRangeVariableDeclWithoutInitializer() {
    let statements = parseStatements("let x")
    let decl = statements[0] as! AST.VariableDecl
    let range = decl.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 5)
}

@Test func sourceRangeVariableDeclWithInitializer() {
    let statements = parseStatements("let x = 42")
    let decl = statements[0] as! AST.VariableDecl
    let range = decl.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 10)
}

@Test func sourceRangeIntegerLiteral() {
    let expr = firstExpression("42")
    let lit = expr as? AST.IntegerLiteral
    #expect(lit != nil)
    let range = lit?.sourceRange
    #expect(range != nil)
    #expect(range?.start.offset == 14)
    #expect(range?.end.offset == 16)
    #expect(range?.start.line == 1)
    #expect(range?.start.column == 15)
}

@Test func sourceRangeVariable() {
    let expr = firstExpression("x")
    let varExpr = expr as! AST.Variable
    let range = varExpr.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 15)
}

@Test func sourceRangeFunctionDeclBlockBody() {
    let statements = parseStatements("func main() {}")
    let decl = statements[0] as! AST.FunctionDecl
    let range = decl.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 14)
}

@Test func sourceRangeFunctionDeclExpressionBody() {
    let statements = parseStatements("func foo() = 42")
    let decl = statements[0] as! AST.FunctionDecl
    let range = decl.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 15)
}

@Test func sourceRangeModuleDecl() {
    let statements = parseStatements("module Foo {}")
    let module = statements[0] as! AST.ModuleDecl
    let range = module.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 13)
}

@Test func sourceRangeCall() {
    let expr = firstExpression("foo()")
    let call = expr as! AST.Call
    let range = call.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 19)
}

@Test func sourceRangeMemberAccess() {
    let expr = firstExpression("a.b")
    let member = expr as! AST.MemberAccess
    let range = member.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 17)
}

@Test func sourceRangeChainedMemberAccess() {
    let expr = firstExpression("a.b.c")
    let member = expr as! AST.MemberAccess
    let range = member.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 19)
}

@Test func sourceRangeInfixExpression() {
    let expr = firstExpression("a + b")
    let sequentialExpression = expr as! AST.SequentialExpression
    let range = sequentialExpression.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 19)
}

@Test func sourceRangeReturnWithValue() {
    let body = parseBlockStatements("func main() { return 42 }")
    let ret = body[0] as! AST.Return
    let range = ret.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 23)
}

@Test func sourceRangeReturnWithoutValue() {
    let body = parseBlockStatements("func main() {\nreturn\n}")
    let ret = body[0] as! AST.Return
    let range = ret.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 20)
}

@Test func sourceRangeProgram() {
    let program = parse("let x let y")
    let range = program.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 11)
}

@Test func sourceRangeEmptyProgram() {
    let program = parse("")
    #expect(program.sourceRange.start.offset == 0)
    #expect(program.sourceRange.end.offset == 0)
}

@Test func sourceRangeEmptyStatement() {
    let statements = parseStatements(";")
    let empty = statements[0] as! AST.EmptyStatement
    let range = empty.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 1)
}

@Test func sourceRangeExpressionStatement() {
    let body = parseBlockStatements("func main() { 42 }")
    let exprStmt = body[0] as! AST.ExpressionStatement
    let range = exprStmt.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 16)
}

@Test func sourceRangeMultiLineStringLiteral() {
    let expr = firstExpression("\"hello\nworld\"")
    let lit = expr as? AST.StringLiteral
    #expect(lit != nil)
    let range = lit?.sourceRange
    #expect(range?.start.offset == 14)
    #expect(range?.start.line == 1)
    #expect(range?.start.column == 15)
    #expect(range?.end.offset == 27)
    #expect(range?.end.line == 2)
    #expect(range?.end.column == 6)
}

@Test func sourceRangeFromToWithMultiLineEndToken() {
    let body = parseBlockStatements("func main() {\nreturn \"a\nb\"\n}")
    let ret = body[0] as! AST.Return
    let range = ret.sourceRange
    #expect(range.start.line == 2)
    #expect(range.end.line == 3)
    #expect(range.end.column == 2)
}

@Test func parseStoredPropertyWithAccessorReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("var a = 1 { get { 1 } set(v) {} }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "stored property cannot have a getter or setter")
    #expect(errors[0].notes.count == 1)
    let note = errors[0].notes[0]
    #expect(note.severity == .note)
    #expect(note.message == "initializer makes this a stored property")
}

@Test func parseComputedPropertyWithObserverReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("var a: Int { get { 1 } willSet {} }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "computed property cannot have 'willSet' or 'didSet' observers")
}

@Test func parseSetterWithoutGetterReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("var a: Int { set(v) {} }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "setter requires a getter")
}

@Test func parseComputedPropertyWithoutTypeAnnotationReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("var a { get { 1 } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "computed property must have a type annotation")
}

@Test func parseStoredPropertyWithObserversIsValid() {
    let (_, diagnostics) = parseWithDiagnostics("var a: Int = 0 { willSet {} didSet {} }")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.isEmpty)
}

@Test func parseComputedPropertyWithGetAndSetIsValid() {
    let (_, diagnostics) = parseWithDiagnostics("var a: Int { get { 1 } set(v) {} }")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.isEmpty)
}

@Test func parseDuplicateAccessorReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("var a: Int { get { 1 } get { 2 } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "duplicate 'get' accessor")
    #expect(errors[0].notes.count == 1)
    let note = errors[0].notes[0]
    #expect(note.severity == .note)
    #expect(note.message == "first declared here")
}

@Test func parseObserverInFunctionContextReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics(
        "func main() { var a: Int = 0 { willSet {} didSet {} } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "property observers are not allowed in function context")
}

// MARK: - Struct Declarations

@Test func parseEmptyStruct() {
    let statements = parseStatements("struct Foo {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Struct))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.genericDecl == nil)
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseStructWithMembers() {
    let statements = parseStatements("struct Foo { let x var y func bar() {} }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.body.count == 3)
    let vd1 = decl!.body[0] as? AST.VariableDecl
    #expect(vd1 != nil)
    #expect(vd1!.name.value == "x")
    let vd2 = decl!.body[1] as? AST.VariableDecl
    #expect(vd2 != nil)
    #expect(vd2!.name.value == "y")
    let fd = decl!.body[2] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "bar")
}

@Test func parseStructWithConformances() {
    let statements = parseStatements("struct Foo: P, Q {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.conformances.count == 2)
    let p = decl!.conformances[0] as? AST.Variable
    #expect(p != nil)
    #expect(p!.name.value == "P")
    let q = decl!.conformances[1] as? AST.Variable
    #expect(q != nil)
    #expect(q!.name.value == "Q")
}

@Test func parseStructWithEmptyStatementInBody() {
    let statements = parseStatements("struct Foo { ; }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.body.count == 1)
    #expect(decl!.body[0] is AST.EmptyStatement)
}

@Test func parseStructWithGenericPlainParameters() {
    let statements = parseStatements("struct Foo<T, U> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl != nil)
    #expect(decl!.genericDecl!.generics.count == 2)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
    #expect(decl!.genericDecl!.generics[1].name.value == "U")
}

@Test func parseStructWithGenericEachParameter() {
    let statements = parseStatements("struct Foo<each T> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl != nil)
    #expect(decl!.genericDecl!.generics.count == 1)
    let param = decl!.genericDecl!.generics[0]
    #expect(param.eachToken != nil)
    #expect(param.name.value == "T")
    #expect(param.constraint == nil)
}

@Test func parseStructWithGenericEachParameterWithConstraint() {
    let statements = parseStatements("struct Foo<each T: P> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl!.generics.count == 1)
    let param = decl!.genericDecl!.generics[0]
    #expect(param.eachToken != nil)
    #expect(param.name.value == "T")
    let constraint = param.constraint as? AST.Variable
    #expect(constraint != nil)
    #expect(constraint!.name.value == "P")
}

@Test func parseStructWithMixedGenericParameters() {
    let statements = parseStatements("struct Foo<T, each U: P> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl!.generics.count == 2)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
    #expect(decl!.genericDecl!.generics[1].name.value == "U")
}

// MARK: - Class Declarations

@Test func parseEmptyClass() {
    let statements = parseStatements("class Foo {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Class))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.genericDecl == nil)
    #expect(decl!.inheritanceClauses.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseClassWithInheritance() {
    let statements = parseStatements("class Foo: Base, P {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(decl!.inheritanceClauses.count == 2)
    let base = decl!.inheritanceClauses[0] as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Base")
    let p = decl!.inheritanceClauses[1] as? AST.Variable
    #expect(p != nil)
    #expect(p!.name.value == "P")
}

@Test func parseClassWithMembers() {
    let statements = parseStatements("class Foo { var x func bar() {} }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(decl!.body.count == 2)
    let vd = decl!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
    let fd = decl!.body[1] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "bar")
}

// MARK: - Protocol Declarations

@Test func parseEmptyProtocol() {
    let statements = parseStatements("protocol Foo {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.ProtocolKw))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseProtocolWithMembers() {
    let statements = parseStatements("protocol Foo { func bar() {} var x: Int }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    #expect(decl != nil)
    #expect(decl!.body.count == 2)
    let fd = decl!.body[0] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "bar")
    let vd = decl!.body[1] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseProtocolWithConformances() {
    let statements = parseStatements("protocol Foo: P {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    #expect(decl != nil)
    #expect(decl!.conformances.count == 1)
    let p = decl!.conformances[0] as? AST.Variable
    #expect(p != nil)
    #expect(p!.name.value == "P")
}

// MARK: - Extension Declarations

@Test func parseEmptyExtension() {
    let statements = parseStatements("extension Foo {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ExtensionDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Extension))
    let base = decl!.base as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Foo")
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseExtensionWithConformances() {
    let statements = parseStatements("extension Foo: P, Q {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ExtensionDecl
    #expect(decl != nil)
    #expect(decl!.conformances.count == 2)
    let p = decl!.conformances[0] as? AST.Variable
    #expect(p != nil)
    #expect(p!.name.value == "P")
    let q = decl!.conformances[1] as? AST.Variable
    #expect(q != nil)
    #expect(q!.name.value == "Q")
}

@Test func parseExtensionWithMembers() {
    let statements = parseStatements("extension Foo { func bar() {} }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ExtensionDecl
    #expect(decl != nil)
    #expect(decl!.body.count == 1)
    let fd = decl!.body[0] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "bar")
}

@Test func parseExtensionGenericReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("extension Foo<T> {}")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "declaring generic type in extension is not allowed")
}

// MARK: - While Statements

@Test func parseWhileWithEmptyBody() {
    let body = parseBlockStatements("func main() { while true {} }")
    #expect(body.count == 1)
    let whileStmt = body[0] as? AST.While
    #expect(whileStmt != nil)
    #expect(whileStmt!.token.kind == .Keyword(.While))
    let cond = whileStmt!.condition as? AST.BoolLiteral
    #expect(cond != nil)
    #expect(cond!.value == true)
    #expect(whileStmt!.body.isEmpty)
    #expect(whileStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(whileStmt!.endToken.kind == .Separator(.CloseBrace))
}

@Test func parseWhileWithBody() {
    let body = parseBlockStatements("func main() { while x { let y } }")
    #expect(body.count == 1)
    let whileStmt = body[0] as? AST.While
    #expect(whileStmt != nil)
    let cond = whileStmt!.condition as? AST.Variable
    #expect(cond != nil)
    #expect(cond!.name.value == "x")
    #expect(whileStmt!.body.count == 1)
    let vd = whileStmt!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "y")
}

// MARK: - Repeat-While Statements

@Test func parseRepeatWhileEmptyBody() {
    let body = parseBlockStatements("func main() { repeat {} while true }")
    #expect(body.count == 1)
    let repeatStmt = body[0] as? AST.RepeatWhile
    #expect(repeatStmt != nil)
    #expect(repeatStmt!.token.kind == .Keyword(.Repeat))
    #expect(repeatStmt!.body.isEmpty)
    #expect(repeatStmt!.whileToken.kind == .Keyword(.While))
    let cond = repeatStmt!.condition as? AST.BoolLiteral
    #expect(cond != nil)
    #expect(cond!.value == true)
}

@Test func parseRepeatWhileWithBody() {
    let body = parseBlockStatements("func main() { repeat { let y } while x }")
    #expect(body.count == 1)
    let repeatStmt = body[0] as? AST.RepeatWhile
    #expect(repeatStmt != nil)
    #expect(repeatStmt!.body.count == 1)
    let vd = repeatStmt!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "y")
    let cond = repeatStmt!.condition as? AST.Variable
    #expect(cond != nil)
    #expect(cond!.name.value == "x")
}

// MARK: - Guard Statements

@Test func parseGuardWithEmptyBody() {
    let body = parseBlockStatements("func main() { guard x else {} }")
    #expect(body.count == 1)
    let guardStmt = body[0] as? AST.Guard
    #expect(guardStmt != nil)
    #expect(guardStmt!.token.kind == .Keyword(.Guard))
    let cond = guardStmt!.condition as? AST.Variable
    #expect(cond != nil)
    #expect(cond!.name.value == "x")
    #expect(guardStmt!.body.isEmpty)
    #expect(guardStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(guardStmt!.endToken.kind == .Separator(.CloseBrace))
}

@Test func parseGuardWithBody() {
    let body = parseBlockStatements("func main() { guard x else { return } }")
    #expect(body.count == 1)
    let guardStmt = body[0] as? AST.Guard
    #expect(guardStmt != nil)
    #expect(guardStmt!.body.count == 1)
    #expect(guardStmt!.body[0] is AST.Return)
}

// MARK: - Defer Statements

@Test func parseDeferWithEmptyBody() {
    let body = parseBlockStatements("func main() { defer {} }")
    #expect(body.count == 1)
    let deferStmt = body[0] as? AST.Defer
    #expect(deferStmt != nil)
    #expect(deferStmt!.token.kind == .Keyword(.Defer))
    #expect(deferStmt!.body.isEmpty)
    #expect(deferStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(deferStmt!.endToken.kind == .Separator(.CloseBrace))
}

@Test func parseDeferWithBody() {
    let body = parseBlockStatements("func main() { defer { let x } }")
    #expect(body.count == 1)
    let deferStmt = body[0] as? AST.Defer
    #expect(deferStmt != nil)
    #expect(deferStmt!.body.count == 1)
    let vd = deferStmt!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
}

// MARK: - Break / Continue / Goto

@Test func parseBreakWithoutLabel() {
    let body = parseBlockStatements("func main() { break }")
    #expect(body.count == 1)
    let breakStmt = body[0] as? AST.Break
    #expect(breakStmt != nil)
    #expect(breakStmt!.token.kind == .Keyword(.Break))
    #expect(breakStmt!.label == nil)
}

@Test func parseBreakWithLabel() {
    let body = parseBlockStatements("func main() { break label }")
    #expect(body.count == 1)
    let breakStmt = body[0] as? AST.Break
    #expect(breakStmt != nil)
    #expect(breakStmt!.label != nil)
    #expect(breakStmt!.label!.value == "label")
}

@Test func parseBreakLabelOnDifferentLineHasNoLabel() {
    let body = parseBlockStatements("func main() {\nbreak\nlabel\n}")
    let breakStmt = body[0] as? AST.Break
    #expect(breakStmt != nil)
    #expect(breakStmt!.label == nil)
}

@Test func parseContinueWithoutLabel() {
    let body = parseBlockStatements("func main() { continue }")
    #expect(body.count == 1)
    let continueStmt = body[0] as? AST.Continue
    #expect(continueStmt != nil)
    #expect(continueStmt!.token.kind == .Keyword(.Continue))
    #expect(continueStmt!.label == nil)
}

@Test func parseContinueWithLabel() {
    let body = parseBlockStatements("func main() { continue label }")
    #expect(body.count == 1)
    let continueStmt = body[0] as? AST.Continue
    #expect(continueStmt != nil)
    #expect(continueStmt!.label != nil)
    #expect(continueStmt!.label!.value == "label")
}

@Test func parseContinueLabelOnDifferentLineHasNoLabel() {
    let body = parseBlockStatements("func main() {\ncontinue\nlabel\n}")
    let continueStmt = body[0] as? AST.Continue
    #expect(continueStmt != nil)
    #expect(continueStmt!.label == nil)
}

@Test func parseGotoProducesGotoNode() {
    let body = parseBlockStatements("func main() { goto label }")
    #expect(body.count == 1)
    let gotoStmt = body[0] as? AST.Goto
    #expect(gotoStmt != nil)
    #expect(gotoStmt!.token.kind == .Keyword(.Goto))
    #expect(gotoStmt!.label.value == "label")
}

// MARK: - For-In Statements

@Test func parseForPlainIdentifier() {
    let body = parseBlockStatements("func main() { for i in items {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    #expect(forStmt!.token.kind == .Keyword(.For))
    #expect(forStmt!.inToken.kind == .Identifier)
    #expect(forStmt!.inToken.value == "in")
    let pattern = forStmt!.pattern as? AST.Variable
    #expect(pattern != nil)
    #expect(pattern!.name.value == "i")
    let seq = forStmt!.sequence as? AST.Variable
    #expect(seq != nil)
    #expect(seq!.name.value == "items")
    #expect(forStmt!.body.isEmpty)
    #expect(forStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(forStmt!.endToken.kind == .Separator(.CloseBrace))
}

@Test func parseForLetBinding() {
    let body = parseBlockStatements("func main() { for let x in arr {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    let pattern = forStmt!.pattern as? AST.BindingPattern
    #expect(pattern != nil)
    #expect(pattern!.token.kind == .Keyword(.Let))
    #expect(pattern!.name.value == "x")
}

@Test func parseForVarBinding() {
    let body = parseBlockStatements("func main() { for var x in arr {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    let pattern = forStmt!.pattern as? AST.BindingPattern
    #expect(pattern != nil)
    #expect(pattern!.token.kind == .Keyword(.Var))
    #expect(pattern!.name.value == "x")
}

@Test func parseForWithBody() {
    let body = parseBlockStatements("func main() { for i in items { let y } }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    #expect(forStmt!.body.count == 1)
    let vd = forStmt!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "y")
}

// MARK: - Accessor Success Paths

@Test func parseGetterWithBlockBody() {
    let statements = parseStatements("var x: Int { get { 1 } }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.accessors.count == 1)
    let accessor = decl!.accessors[0]
    #expect(accessor.kind == .Get)
    #expect(accessor.token?.value == "get")
    #expect(accessor.parameterName == nil)
    if case .Block(let stmts) = accessor.body {
        #expect(stmts.count == 1)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseGetterWithExpressionBody() {
    let statements = parseStatements("var x: Int { get = 1 }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.accessors.count == 1)
    let accessor = decl!.accessors[0]
    #expect(accessor.kind == .Get)
    if case .Expression(let expr) = accessor.body {
        let lit = expr as? AST.IntegerLiteral
        #expect(lit != nil)
        #expect(lit!.value == 1)
    } else {
        Issue.record("expected expression body")
    }
}

@Test func parseSetterWithoutParameterName() {
    let statements = parseStatements("var x: Int { get { 1 } set {} }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.accessors.count == 2)
    #expect(decl!.accessors[0].kind == .Get)
    let setter = decl!.accessors[1]
    #expect(setter.kind == .Set)
    #expect(setter.token?.value == "set")
    #expect(setter.parameterName == nil)
    if case .Block = setter.body {
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseSetterWithParameterName() {
    let statements = parseStatements("var x: Int { get { 1 } set(newValue) {} }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    let setter = decl!.accessors[1]
    #expect(setter.kind == .Set)
    #expect(setter.parameterName != nil)
    #expect(setter.parameterName!.value == "newValue")
}

@Test func parseWillSetWithoutParameterName() {
    let statements = parseStatements("var x: Int = 0 { willSet {} }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.accessors.count == 1)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .WillSet)
    #expect(observer.token?.value == "willSet")
    #expect(observer.parameterName == nil)
}

@Test func parseWillSetWithParameterName() {
    let statements = parseStatements("var x: Int = 0 { willSet(new) {} }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .WillSet)
    #expect(observer.parameterName != nil)
    #expect(observer.parameterName!.value == "new")
}

@Test func parseDidSetWithoutParameterName() {
    let statements = parseStatements("var x: Int = 0 { didSet {} }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .DidSet)
    #expect(observer.token?.value == "didSet")
    #expect(observer.parameterName == nil)
}

@Test func parseDidSetWithParameterName() {
    let statements = parseStatements("var x: Int = 0 { didSet(old) {} }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .DidSet)
    #expect(observer.parameterName != nil)
    #expect(observer.parameterName!.value == "old")
}

@Test func parseShorthandGetter() {
    let statements = parseStatements("var x: Int { 1 }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.accessors.count == 1)
    let accessor = decl!.accessors[0]
    #expect(accessor.kind == .Get)
    #expect(accessor.token == nil)
    if case .Block(let stmts) = accessor.body {
        #expect(stmts.count == 1)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseStoredPropertyWithWillSetAndDidSet() {
    let statements = parseStatements("var x: Int = 0 { willSet {} didSet {} }")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.accessors.count == 2)
    #expect(decl!.accessors[0].kind == .WillSet)
    #expect(decl!.accessors[1].kind == .DidSet)
}

// MARK: - Modifiers

@Test func parsePublicModifierOnStruct() {
    let statements = parseStatements("public struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: false)))
}

@Test func parsePublicSetModifierOnStruct() {
    let statements = parseStatements("public(set) struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: true)))
}

@Test func parsePrivateModifierOnVariable() {
    let statements = parseStatements("private var x")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Private(setter: false)))
}

@Test func parsePrivateSetModifierOnVariable() {
    let statements = parseStatements("private(set) var x")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Private(setter: true)))
}

@Test func parseInternalModifierOnFunction() {
    let statements = parseStatements("internal func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Internal(setter: false)))
}

@Test func parseFilePrivateModifierOnStruct() {
    let statements = parseStatements("fileprivate struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .FilePrivate(setter: false)))
}

@Test func parseProtectedSetModifierOnClass() {
    let statements = parseStatements("protected(set) class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Protected(setter: true)))
}

@Test func parsePackagePrivateModifierOnStruct() {
    let statements = parseStatements("packageprivate struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .PackagePrivate(setter: false)))
}

@Test func parseOpenModifierOnClass() {
    let statements = parseStatements("open class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Open(setter: false)))
}

@Test func parseFinalModifierOnClass() {
    let statements = parseStatements("final class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Final))
}

@Test func parseOverrideModifierOnFunction() {
    let statements = parseStatements("override func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Override))
}

@Test func parseMultipleModifiersOnStruct() {
    let statements = parseStatements("public final struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.modifiers.count == 2)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: false)))
    #expect(modifierKind(decl!.modifiers[1].kind, equals: .Final))
}

@Test func parseMutatingModifierOnFunction() {
    let statements = parseStatements("mutating func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Mutating))
}

@Test func parseLazyModifierOnVariable() {
    let statements = parseStatements("lazy var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Lazy))
}

// MARK: - Attributes

@Test func parseAttributeWithoutArguments() {
    let statements = parseStatements("#[attr] struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.attributes.count == 1)
    #expect(decl!.attributes[0].name.value == "attr")
    #expect(decl!.attributes[0].arguments.isEmpty)
}

@Test func parseAttributeWithModifiers() {
    let statements = parseStatements("#[attr] public struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.attributes.count == 1)
    #expect(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: false)))
}

@Test func parseAttributeWithArguments() {
    let statements = parseStatements("#[attr(a b)] struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.attributes.count == 1)
    #expect(decl!.attributes[0].arguments.count == 1)
    #expect(decl!.attributes[0].arguments[0].count == 2)
    #expect(decl!.attributes[0].arguments[0][0].value == "a")
    #expect(decl!.attributes[0].arguments[0][1].value == "b")
}

@Test func parseAttributeWithLabeledArguments() {
    let statements = parseStatements("#[attr(label: a b)] struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.attributes.count == 1)
    let attr = decl!.attributes[0]
    #expect(attr.labeledArguments.count == 1)
    let labelToken = attr.labeledArguments.first { $0.key.value == "label" }
    #expect(labelToken != nil)
    #expect(labelToken!.value.count == 2)
    #expect(labelToken!.value[0].value == "a")
    #expect(labelToken!.value[1].value == "b")
}

// MARK: - Self / SelfType / Super Expressions

@Test func parseSelfExpression() {
    let expr = firstExpression("self")
    let selfExpr = expr as? AST.SelfExpression
    #expect(selfExpr != nil)
}

@Test func parseSelfTypeExpression() {
    let expr = firstExpression("Self")
    let selfExpr = expr as? AST.SelfTypeExpression
    #expect(selfExpr != nil)
}

@Test func parseSuperExpression() {
    let expr = firstExpression("super")
    let superExpr = expr as? AST.SuperExpression
    #expect(superExpr != nil)
}

// MARK: - Implicit Member Access

@Test func parseImplicitMemberAccess() {
    let expr = firstExpression(".foo")
    let implicit = expr as? AST.ImplicitMemberAccess
    #expect(implicit != nil)
    #expect(implicit!.name.value == "foo")
}

// MARK: - Parenthesized Expression

@Test func parseParenthesizedVariable() {
    let expr = firstExpression("(x)")
    let paren = expr as? AST.ParentheticalExpression
    #expect(paren != nil)
    let varExpr = paren!.inner as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
}

@Test func parseParenthesizedSequentialExpression() {
    let expr = firstExpression("(a + b)")
    let paren = expr as? AST.ParentheticalExpression
    #expect(paren != nil)
    let seq = paren!.inner as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
    #expect(seq!.operands.count == 2)
}

// MARK: - Compound Assignment Operators

@Test func parsePlusAssignExpression() {
    let expr = firstExpression("x += 1")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.PlusAssign))
    #expect(seq!.operands.count == 2)
    let target = seq!.operands[0] as? AST.Variable
    #expect(target != nil)
    #expect(target!.name.value == "x")
    let value = seq!.operands[1] as? AST.IntegerLiteral
    #expect(value != nil)
    #expect(value!.value == 1)
}

@Test func parseMultiplyAssignExpression() {
    let expr = firstExpression("x *= 2")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.MultiplyAssign))
}

@Test func parseMinusAssignExpression() {
    let expr = firstExpression("x -= 3")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.MinusAssign))
}

// MARK: - Function Return Type

@Test func parseFunctionWithReturnType() {
    let statements = parseStatements("func foo() -> Int {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.returnTypeExpression != nil)
    let returnType = decl!.returnTypeExpression as? AST.Variable
    #expect(returnType != nil)
    #expect(returnType!.name.value == "Int")
}

@Test func parseFunctionWithReturnTypeAndBlockBody() {
    let statements = parseStatements("func foo() -> Int { return 42 }")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.returnTypeExpression != nil)
    if case .Block(let body) = decl!.body {
        #expect(body.count == 1)
        #expect(body[0] is AST.Return)
    } else {
        Issue.record("expected block body")
    }
}

// MARK: - Error Recovery

@Test func parseStructMissingNameReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("struct")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected struct name after 'struct'")
}

@Test func parseStructNonIdentifierNameReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("struct 42 {}")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected identifier after 'struct', but got '42'")
}

@Test func parseClassMissingNameReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("class")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected class name after 'class'")
}

@Test func parseWhileMissingOpenBraceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { while x let }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected '{' after while condition, but got 'let'")
}

@Test func parseGuardMissingOpenBraceAfterElseReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { guard x else let }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected '{' after 'else', but got 'let'")
}

@Test func parseDeferMissingOpenBraceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { defer x }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected '{' after 'defer', but got 'x'")
}

@Test func parseBreakWithNonIdentifierLabelReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { break 42 }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected identifier after 'break', but got '42'")
}

@Test func parseContinueWithNonIdentifierLabelReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { continue 42 }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected identifier after 'continue', but got '42'")
}

// MARK: - Fixed Bug Regressions

@Test func parseGotoWithIdentifierLabelDoesNotReportError() {
    let (_, diagnostics) = parseWithDiagnostics("func main() { goto label }")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.isEmpty)
}

@Test func parseFunctionWithReturnTypeAndExpressionBody() {
    let statements = parseStatements("func foo() -> Int = 42")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.returnTypeExpression != nil)
    let returnType = decl!.returnTypeExpression as? AST.Variable
    #expect(returnType != nil)
    #expect(returnType!.name.value == "Int")
    if case .Expression(let expr) = decl!.body {
        let lit = expr as? AST.IntegerLiteral
        #expect(lit != nil)
        #expect(lit!.value == 42)
    } else {
        Issue.record("expected expression body")
    }
}

// MARK: - Actor Declarations (previously dead code)

@Test func parseEmptyActor() {
    let statements = parseStatements("actor Foo {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Actor))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.genericDecl == nil)
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseActorWithMembers() {
    let statements = parseStatements("actor Foo { let x func bar() {} }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    #expect(decl != nil)
    #expect(decl!.body.count == 2)
    let vd = decl!.body[0] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "x")
    let fd = decl!.body[1] as? AST.FunctionDecl
    #expect(fd != nil)
    #expect(fd!.name.value == "bar")
}

// MARK: - If Statements (previously dead code)

@Test func parseIfStatementWithEmptyThen() {
    let body = parseBlockStatements("func main() { if true {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    #expect(ifExpr != nil)
    let cond = ifExpr!.condition as? AST.BoolLiteral
    #expect(cond != nil)
    #expect(cond!.value == true)
    #expect(ifExpr!.then.isEmpty)
    #expect(ifExpr!.elseKind == nil)
}

@Test func parseIfStatementWithThenBody() {
    let body = parseBlockStatements("func main() { if x { return } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    #expect(ifExpr != nil)
    #expect(ifExpr!.then.count == 1)
    #expect(ifExpr!.then[0] is AST.Return)
}

@Test func parseIfElseStatement() {
    let body = parseBlockStatements("func main() { if x { return 1 } else { return 2 } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    #expect(ifExpr != nil)
    #expect(ifExpr!.then.count == 1)
    if case .Block(let elseBody) = ifExpr!.elseKind {
        #expect(elseBody.count == 1)
    } else {
        Issue.record("expected block else")
    }
}

@Test func parseIfElseIfChain() {
    let body = parseBlockStatements("func main() { if x {} else if y {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    #expect(ifExpr != nil)
    if case .If(let innerIf) = ifExpr!.elseKind {
        let cond = innerIf.condition as? AST.Variable
        #expect(cond != nil)
        #expect(cond!.name.value == "y")
    } else {
        Issue.record("expected else if")
    }
}

// MARK: - If as Expression (parsePrimary)

@Test func parseIfExpressionWithoutElse() {
    let expr = firstExpression("if true {}")
    let ifExpr = expr as? AST.If
    #expect(ifExpr != nil)
    let cond = ifExpr!.condition as? AST.BoolLiteral
    #expect(cond != nil)
    #expect(cond!.value == true)
    #expect(ifExpr!.then.isEmpty)
    #expect(ifExpr!.elseKind == nil)
}

@Test func parseIfExpressionAsAssignmentValue() {
    let expr = firstExpression("x = if true {} else {}")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Assign))
    #expect(seq!.operands.count == 2)
    let target = seq!.operands[0] as? AST.Variable
    #expect(target != nil)
    #expect(target!.name.value == "x")
    let ifExpr = seq!.operands[1] as? AST.If
    #expect(ifExpr != nil)
    if case .Block(let elseBody) = ifExpr!.elseKind {
        #expect(elseBody.isEmpty)
    } else {
        Issue.record("expected block else")
    }
}

@Test func parseIfExpressionAsReturnValue() {
    let body = parseBlockStatements("func main() { return if true { 1 } else { 2 } }")
    #expect(body.count == 1)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    let ifExpr = ret!.value as? AST.If
    #expect(ifExpr != nil)
    #expect(ifExpr!.then.count == 1)
    if case .Block(let elseBody) = ifExpr!.elseKind {
        #expect(elseBody.count == 1)
    } else {
        Issue.record("expected block else")
    }
}

@Test func parseIfExpressionWithMemberAccess() {
    let expr = firstExpression("(if true { 1 } else { 2 }).foo")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "foo")
    let paren = member!.object as? AST.ParentheticalExpression
    #expect(paren != nil)
    let ifExpr = paren!.inner as? AST.If
    #expect(ifExpr != nil)
}

@Test func parseIfExpressionElseIfChainAsValue() {
    let expr = firstExpression("x = if a {} else if b {} else {}")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    let ifExpr = seq!.operands[1] as? AST.If
    #expect(ifExpr != nil)
    if case .If(let innerIf) = ifExpr!.elseKind {
        if case .Block = innerIf.elseKind {
        } else {
            Issue.record("expected block else in inner if")
        }
    } else {
        Issue.record("expected else if")
    }
}

@Test func parseNestedIfExpressionInThenBody() {
    let body = parseBlockStatements("func main() { if x { if y {} } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let outerIf = exprStmt!.expression as? AST.If
    #expect(outerIf != nil)
    #expect(outerIf!.then.count == 1)
    let innerStmt = outerIf!.then[0] as? AST.ExpressionStatement
    #expect(innerStmt != nil)
    let innerIf = innerStmt!.expression as? AST.If
    #expect(innerIf != nil)
    let cond = innerIf!.condition as? AST.Variable
    #expect(cond != nil)
    #expect(cond!.name.value == "y")
}

@Test func parseIfExpressionWithComplexCondition() {
    let expr = firstExpression("if a + b == c {}")
    let ifExpr = expr as? AST.If
    #expect(ifExpr != nil)
    let seq = ifExpr!.condition as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 2)
}

// MARK: - parseExpression: ops-only and nil return

@Test func parseOperatorOnlyReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { + }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected expression after operator '+'")
}

@Test func parseOperatorOnlyPointsAfterOperator() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { + }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    let op = errors[0].range
    let source = "func main() { + }"
    let plusIndex = source.firstIndex(of: "+")!
    let afterPlusOffset = source.distance(
        from: source.startIndex, to: source.index(after: plusIndex))
    #expect(op.start.offset == afterPlusOffset)
}

@Test func parseOperatorOnlyReturnsErrorExpression() {
    let body = parseBlockStatements("func main() { + }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    #expect(exprStmt!.expression is AST.ErrorExpression)
}

@Test func parseEmptyParenthesesIsVoidLiteral() {
    let expr = firstExpression("()")
    let void = expr as? AST.VoidLiteral
    #expect(void != nil)
}

@Test func parseOperatorOnlyInConformanceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("struct Foo: + {}")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    let expr = errors.first { $0.message == "expected '{' in struct type" }
    #expect(expr != nil)
}

@Test func parseOperatorOnlyInReturnTypeParsedAsSequential() {
    let statements = parseStatements("func foo() -> + {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let returnType = decl!.returnTypeExpression as? AST.SequentialExpression
    #expect(returnType != nil)
    #expect(returnType!.ops.count == 1)
    #expect(returnType!.ops[0].kind == .Operator(.Plus))
    #expect(returnType!.operands.count == 1)
    #expect(returnType!.operands[0] is AST.Closure)
}

// MARK: - Import

@Test func parseImportSimple() {
    let statements = parseStatements("import A")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 1)
    if case .identifier(let t) = decl.path.components[0] {
        #expect(t.value == "A")
    } else {
        Issue.record("expected identifier component")
    }
    if case .wholeModule(let alias) = decl.selector {
        #expect(alias == nil)
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportWildcard() {
    let statements = parseStatements("import A.*")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 1)
    if case .wildcard = decl.selector {
    } else {
        Issue.record("expected wildcard selector")
    }
}

@Test func parseImportNestedPath() {
    let statements = parseStatements("import A.B")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case .identifier(let t) = decl.path.components[1] {
        #expect(t.value == "B")
    } else {
        Issue.record("expected identifier component")
    }
    if case .wholeModule(let alias) = decl.selector {
        #expect(alias == nil)
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportNestedWildcard() {
    let statements = parseStatements("import A.B.*")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case .wildcard = decl.selector {
    } else {
        Issue.record("expected wildcard selector")
    }
}

@Test func parseImportExplicitSelector() {
    let statements = parseStatements("import A.{self, B, C}")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 1)
    if case .explicit(let items) = decl.selector {
        #expect(items.count == 3)
        if case .self_ = items[0].kind {
        } else {
            Issue.record("expected self_ item")
        }
        #expect(items[0].alias == nil)
        if case .name(let t) = items[1].kind {
            #expect(t.value == "B")
        } else {
            Issue.record("expected name item")
        }
        if case .name(let t) = items[2].kind {
            #expect(t.value == "C")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportSelfPrefix() {
    let statements = parseStatements("import Self.A")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case .self_ = decl.path.components[0] {
    } else {
        Issue.record("expected self_ path component")
    }
    if case .identifier(let t) = decl.path.components[1] {
        #expect(t.value == "A")
    } else {
        Issue.record("expected identifier component")
    }
    if case .wholeModule(let alias) = decl.selector {
        #expect(alias == nil)
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportSelfPrefixExplicit() {
    let statements = parseStatements("import Self.{A, B}")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 1)
    if case .self_ = decl.path.components[0] {
    } else {
        Issue.record("expected self_ path component")
    }
    if case .explicit(let items) = decl.selector {
        #expect(items.count == 2)
        if case .name(let t) = items[0].kind {
            #expect(t.value == "A")
        } else {
            Issue.record("expected name item")
        }
        if case .name(let t) = items[1].kind {
            #expect(t.value == "B")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportAliasModule() {
    let statements = parseStatements("import A as B")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case .wholeModule(let alias) = decl.selector {
        #expect(alias?.value == "B")
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportAliasNestedModule() {
    let statements = parseStatements("import A.B as C")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case .wholeModule(let alias) = decl.selector {
        #expect(alias?.value == "C")
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportAliasExplicitItems() {
    let statements = parseStatements("import A.{B as b, C as c}")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case .explicit(let items) = decl.selector {
        #expect(items.count == 2)
        if case .name(let t) = items[0].kind {
            #expect(t.value == "B")
            #expect(items[0].alias?.value == "b")
        } else {
            Issue.record("expected name item")
        }
        if case .name(let t) = items[1].kind {
            #expect(t.value == "C")
            #expect(items[1].alias?.value == "c")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportAliasSelfItem() {
    let statements = parseStatements("import A.{self as a, B as b}")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case .explicit(let items) = decl.selector {
        #expect(items.count == 2)
        if case .self_ = items[0].kind {
            #expect(items[0].alias?.value == "a")
        } else {
            Issue.record("expected self_ item")
        }
        if case .name(let t) = items[1].kind {
            #expect(t.value == "B")
            #expect(items[1].alias?.value == "b")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportAliasUnderscore() {
    let statements = parseStatements("import A as _")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case .wholeModule(let alias) = decl.selector {
        #expect(alias?.value == "_")
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportNestedPathExplicitSelector() {
    let statements = parseStatements("import A.B.{self, C}")
    #expect(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case .explicit(let items) = decl.selector {
        #expect(items.count == 2)
        if case .self_ = items[0].kind {
        } else {
            Issue.record("expected self_ item")
        }
        if case .name(let t) = items[1].kind {
            #expect(t.value == "C")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportSourceRange() {
    let statements = parseStatements("import A.B")
    let decl = statements[0] as! AST.Import
    let range = decl.sourceRange
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 10)
}

@Test func parseImportNoPathError() {
    let (_, diagnostics) = parseWithDiagnostics("import")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
    #expect(errors[0].message == "expected module path after 'import'")
}

@Test func parseImportEmptySelectorError() {
    let (_, diagnostics) = parseWithDiagnostics("import A.{}")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
    #expect(errors[0].message == "expected import item after '{'")
}

@Test func parseImportWildcardAliasError() {
    let (_, diagnostics) = parseWithDiagnostics("import A.* as B")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
    #expect(errors[0].message == "cannot alias a wildcard import")
}

@Test func parseImportSelfInMiddleError() {
    let (_, diagnostics) = parseWithDiagnostics("import A.Self.B")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
    #expect(errors[0].message == "'Self' can only appear at the beginning of an import path")
}

@Test func parseImportLowercaseSelfInPathError() {
    let (_, diagnostics) = parseWithDiagnostics("import self.A")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
    #expect(errors[0].message == "'self' is not allowed in import path, use 'Self' instead")
}

@Test func parseImportDoubleAliasError() {
    let (_, diagnostics) = parseWithDiagnostics("import A as B as C")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
    #expect(errors[0].message == "unexpected 'as'")
}

// MARK: - Labeled Statements

@Test func parseLabeledWhile() {
    let body = parseBlockStatements("func main() { outer: while true { break outer } }")
    #expect(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    #expect(labeled != nil)
    #expect(labeled!.label.value == "outer")
    let whileStmt = labeled!.body as? AST.While
    #expect(whileStmt != nil)
    #expect(whileStmt!.body.count == 1)
    let breakStmt = whileStmt!.body[0] as? AST.Break
    #expect(breakStmt != nil)
    #expect(breakStmt!.label?.value == "outer")
}

@Test func parseLabeledRepeatWhile() {
    let body = parseBlockStatements("func main() { end: repeat { } while false }")
    #expect(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    #expect(labeled != nil)
    #expect(labeled!.label.value == "end")
    let repeatStmt = labeled!.body as? AST.RepeatWhile
    #expect(repeatStmt != nil)
}

@Test func parseNestedLabels() {
    let body = parseBlockStatements("func main() { outer: inner: while true { } }")
    #expect(body.count == 1)
    let outer = body[0] as? AST.LabeledStatement
    #expect(outer != nil)
    #expect(outer!.label.value == "outer")
    let inner = outer!.body as? AST.LabeledStatement
    #expect(inner != nil)
    #expect(inner!.label.value == "inner")
    let whileStmt = inner!.body as? AST.While
    #expect(whileStmt != nil)
}

@Test func parseLabeledReturn() {
    let body = parseBlockStatements("func main() { end: return 0 }")
    #expect(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    #expect(labeled != nil)
    #expect(labeled!.label.value == "end")
    let returnStmt = labeled!.body as? AST.Return
    #expect(returnStmt != nil)
}

@Test func parseLabeledEmptyStatement() {
    let body = parseBlockStatements("func main() { foo: ; }")
    #expect(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    #expect(labeled != nil)
    #expect(labeled!.label.value == "foo")
    let empty = labeled!.body as? AST.EmptyStatement
    #expect(empty != nil)
}

@Test func parseLabeledExpressionStatement() {
    let body = parseBlockStatements("func main() { start: x }")
    #expect(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    #expect(labeled != nil)
    #expect(labeled!.label.value == "start")
    let exprStmt = labeled!.body as? AST.ExpressionStatement
    #expect(exprStmt != nil)
}

@Test func parseLabelWithNewline() {
    let body = parseBlockStatements("func main() {\nouter:\n while true {}\n}")
    #expect(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    #expect(labeled != nil)
    #expect(labeled!.label.value == "outer")
    let whileStmt = labeled!.body as? AST.While
    #expect(whileStmt != nil)
}

@Test func parseGotoWithLabeledStatement() {
    let body = parseBlockStatements("func main() { goto end\n end: return 0 }")
    #expect(body.count == 2)
    let gotoStmt = body[0] as? AST.Goto
    #expect(gotoStmt != nil)
    #expect(gotoStmt!.label.value == "end")
    let labeled = body[1] as? AST.LabeledStatement
    #expect(labeled != nil)
    #expect(labeled!.label.value == "end")
    let returnStmt = labeled!.body as? AST.Return
    #expect(returnStmt != nil)
}

@Test func parseLabeledStatementSourceRangeCoversInnerOnly() {
    let body = parseBlockStatements("func main() { outer: while true {} }")
    let labeled = body[0] as? AST.LabeledStatement
    #expect(labeled != nil)
    let whileStmt = labeled!.body as? AST.While
    #expect(whileStmt != nil)
    #expect(labeled!.sourceRange == whileStmt!.sourceRange)
}

@Test func parseLabelFollowedByCloseBraceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { foo: }")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
}

@Test func parseLabelAtEOFReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { foo:")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count >= 1)
    #expect(errors[0].message == "expected statement after label 'foo:'")
}

// MARK: - Angle Bracket Generics vs Comparison

@Test func parseBareGenericSingleArg() {
    let expr = firstExpression("Array<Int32>")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 2)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Operator(.Greater))
    #expect(seq!.operands.count == 2)
    let base = seq!.operands[0] as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Array")
    let arg = seq!.operands[1] as? AST.Variable
    #expect(arg != nil)
    #expect(arg!.name.value == "Int32")
}

@Test func parseBareGenericMultipleArgs() {
    let expr = firstExpression("Array<Int32, String>")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 3)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Separator(.Comma))
    #expect(seq!.ops[2].kind == .Operator(.Greater))
    #expect(seq!.operands.count == 3)
    let arg0 = seq!.operands[0] as? AST.Variable
    #expect(arg0 != nil)
    #expect(arg0!.name.value == "Array")
    let arg1 = seq!.operands[1] as? AST.Variable
    #expect(arg1 != nil)
    #expect(arg1!.name.value == "Int32")
    let arg2 = seq!.operands[2] as? AST.Variable
    #expect(arg2 != nil)
    #expect(arg2!.name.value == "String")
}

@Test func parseComparisonWithAngleBrackets() {
    let expr = firstExpression("1<2>3")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 2)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Operator(.Greater))
    #expect(seq!.operands.count == 3)
    let first = seq!.operands[0] as? AST.IntegerLiteral
    #expect(first != nil)
    #expect(first!.value == 1)
    let second = seq!.operands[1] as? AST.IntegerLiteral
    #expect(second != nil)
    #expect(second!.value == 2)
    let third = seq!.operands[2] as? AST.IntegerLiteral
    #expect(third != nil)
    #expect(third!.value == 3)
}

@Test func parseGenericApplicationWithCall() {
    let expr = firstExpression("Array<Int32>()")
    let call = expr as? AST.Call
    #expect(call != nil)
    let callee = call!.callee as? AST.SequentialExpression
    #expect(callee != nil)
    #expect(callee!.ops.count == 2)
    let base = callee!.operands[0] as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Array")
    let arg = callee!.operands[1] as? AST.Variable
    #expect(arg != nil)
    #expect(arg!.name.value == "Int32")
    #expect(call!.arguments.isEmpty)
}

@Test func parseSimpleCall() {
    let expr = firstExpression("foo()")
    let call = expr as? AST.Call
    #expect(call != nil)
    let callee = call!.callee as? AST.Variable
    #expect(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(call!.arguments.isEmpty)
}

@Test func parseParenthesizedAfterOperator() {
    let expr = firstExpression("a + (b)")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
    #expect(seq!.operands.count == 2)
    let first = seq!.operands[0] as? AST.Variable
    #expect(first != nil)
    #expect(first!.name.value == "a")
    let second = seq!.operands[1] as? AST.ParentheticalExpression
    #expect(second != nil)
    let inner = second!.inner as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "b")
}

@Test func parseCallThenMemberAccess() {
    let expr = firstExpression("foo().bar")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    let call = member!.object as? AST.Call
    #expect(call != nil)
    let callee = call!.callee as? AST.Variable
    #expect(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(member!.member.value == "bar")
}

@Test func parseGenericWithMemberAccess() {
    let expr = firstExpression("Array<Int32>.f")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "f")
    let base = member!.object as? AST.SequentialExpression
    #expect(base != nil)
    #expect(base!.ops.count == 2)
    #expect(base!.ops[0].kind == .Operator(.Less))
    #expect(base!.ops[1].kind == .Operator(.Greater))
    #expect(base!.operands.count == 2)
    let array = base!.operands[0] as? AST.Variable
    #expect(array != nil)
    #expect(array!.name.value == "Array")
    let arg = base!.operands[1] as? AST.Variable
    #expect(arg != nil)
    #expect(arg!.name.value == "Int32")
}

@Test func parseGenericWithMemberAccessAndCall() {
    let expr = firstExpression("Array<Int32>.f()")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.isEmpty)
    let member = call!.callee as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "f")
    let baseSeq = member!.object as? AST.SequentialExpression
    #expect(baseSeq != nil)
    #expect(baseSeq!.ops.count == 2)
    #expect(baseSeq!.operands[0] is AST.Variable)
    #expect((baseSeq!.operands[0] as! AST.Variable).name.value == "Array")
    #expect(baseSeq!.operands[1] is AST.Variable)
    #expect((baseSeq!.operands[1] as! AST.Variable).name.value == "Int32")
}

@Test func parseGenericWithMemberAccessAndCallArg() {
    let expr = firstExpression("Array<Int32>.f(1)")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 1)
    let argVal = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(argVal != nil)
    #expect(argVal!.value == 1)
    let member = call!.callee as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "f")
}

@Test func parseGenericMultiArgWithMemberAccess() {
    let expr = firstExpression("Array<Int32, String>.foo")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "foo")
    let baseSeq = member!.object as? AST.SequentialExpression
    #expect(baseSeq != nil)
    #expect(baseSeq!.operands.count == 3)
    #expect((baseSeq!.operands[0] as? AST.Variable)?.name.value == "Array")
    #expect((baseSeq!.operands[1] as? AST.Variable)?.name.value == "Int32")
    #expect((baseSeq!.operands[2] as? AST.Variable)?.name.value == "String")
}

@Test func parseCallOnGenericThenMemberAccess() {
    let expr = firstExpression("Producer<Item>().result")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "result")
    let call = member!.object as? AST.Call
    #expect(call != nil)
    let calleeSeq = call!.callee as? AST.SequentialExpression
    #expect(calleeSeq != nil)
    #expect(calleeSeq!.operands.count == 2)
    #expect((calleeSeq!.operands[0] as? AST.Variable)?.name.value == "Producer")
    #expect((calleeSeq!.operands[1] as? AST.Variable)?.name.value == "Item")
    #expect(call!.arguments.isEmpty)
}

@Test func parseComparisonThenMemberAccess() {
    let expr = firstExpression("1 < 2 && 3 > x.foo")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    let lastOperand = seq!.operands.last
    let member = lastOperand as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "foo")
    let obj = member!.object as? AST.Variable
    #expect(obj != nil)
    #expect(obj!.name.value == "x")
}

@Test func parseNestedGenericRightShift() {
    let expr = firstExpression("Array<Array<Int32>>")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 3)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Operator(.Less))
    #expect(seq!.ops[2].kind == .Operator(.RightShift))
    #expect(seq!.operands.count == 3)
    let arg0 = seq!.operands[0] as? AST.Variable
    #expect(arg0 != nil)
    #expect(arg0!.name.value == "Array")
    let arg1 = seq!.operands[1] as? AST.Variable
    #expect(arg1 != nil)
    #expect(arg1!.name.value == "Array")
    let arg2 = seq!.operands[2] as? AST.Variable
    #expect(arg2 != nil)
    #expect(arg2!.name.value == "Int32")
}

@Test func parseEmptyArrayLiteral() {
    let expr = firstExpression("[]")
    let arr = expr as? AST.ArrayLiteral
    #expect(arr != nil)
    #expect(arr!.elements.isEmpty)
}

@Test func parseSingleElementArrayLiteral() {
    let expr = firstExpression("[1]")
    let arr = expr as? AST.ArrayLiteral
    #expect(arr != nil)
    #expect(arr!.elements.count == 1)
    let lit = arr!.elements[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 1)
}

@Test func parseMultiElementArrayLiteral() {
    let expr = firstExpression("[1, 2, 3]")
    let arr = expr as? AST.ArrayLiteral
    #expect(arr != nil)
    #expect(arr!.elements.count == 3)
    for i in 0..<3 {
        let lit = arr!.elements[i] as? AST.IntegerLiteral
        #expect(lit != nil)
        #expect(lit!.value == Int128(i + 1))
    }
}

@Test func parseArrayLiteralWithTrailingComma() {
    let expr = firstExpression("[1, 2,]")
    let arr = expr as? AST.ArrayLiteral
    #expect(arr != nil)
    #expect(arr!.elements.count == 2)
}

@Test func parseArrayLiteralWithExpressions() {
    let expr = firstExpression("[a + b, c]")
    let arr = expr as? AST.ArrayLiteral
    #expect(arr != nil)
    #expect(arr!.elements.count == 2)
    let seq = arr!.elements[0] as? AST.SequentialExpression
    #expect(seq != nil)
    let v = arr!.elements[1] as? AST.Variable
    #expect(v != nil)
    #expect(v!.name.value == "c")
}

@Test func parseEmptyDictionaryLiteral() {
    let expr = firstExpression("[:]")
    let dict = expr as? AST.DictionaryLiteral
    #expect(dict != nil)
    #expect(dict!.entries.isEmpty)
}

@Test func parseSingleEntryDictionaryLiteral() {
    let expr = firstExpression("[1: 2]")
    let dict = expr as? AST.DictionaryLiteral
    #expect(dict != nil)
    #expect(dict!.entries.count == 1)
    let key = dict!.entries[0].key as? AST.IntegerLiteral
    #expect(key != nil)
    #expect(key!.value == 1)
    let val = dict!.entries[0].value as? AST.IntegerLiteral
    #expect(val != nil)
    #expect(val!.value == 2)
}

@Test func parseMultiEntryDictionaryLiteral() {
    let expr = firstExpression("[1: 2, 3: 4]")
    let dict = expr as? AST.DictionaryLiteral
    #expect(dict != nil)
    #expect(dict!.entries.count == 2)
    let key0 = dict!.entries[0].key as? AST.IntegerLiteral
    #expect(key0!.value == 1)
    let val0 = dict!.entries[0].value as? AST.IntegerLiteral
    #expect(val0!.value == 2)
    let key1 = dict!.entries[1].key as? AST.IntegerLiteral
    #expect(key1!.value == 3)
    let val1 = dict!.entries[1].value as? AST.IntegerLiteral
    #expect(val1!.value == 4)
}

@Test func parseDictionaryLiteralWithTrailingComma() {
    let expr = firstExpression("[1: 2,]")
    let dict = expr as? AST.DictionaryLiteral
    #expect(dict != nil)
    #expect(dict!.entries.count == 1)
}

@Test func parseSubscriptSingleIndex() {
    let expr = firstExpression("arr[1]")
    let sub = expr as? AST.Subscript
    #expect(sub != nil)
    let base = sub!.base as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "arr")
    #expect(sub!.arguments.count == 1)
    #expect(sub!.arguments[0].label == nil)
    let idx = sub!.arguments[0].value as? AST.IntegerLiteral
    #expect(idx != nil)
    #expect(idx!.value == 1)
}

@Test func parseSubscriptMultiIndex() {
    let expr = firstExpression("arr[1, 2]")
    let sub = expr as? AST.Subscript
    #expect(sub != nil)
    #expect(sub!.arguments.count == 2)
    #expect(sub!.arguments[0].label == nil)
    #expect(sub!.arguments[1].label == nil)
    let idx0 = sub!.arguments[0].value as? AST.IntegerLiteral
    #expect(idx0!.value == 1)
    let idx1 = sub!.arguments[1].value as? AST.IntegerLiteral
    #expect(idx1!.value == 2)
}

@Test func parseSubscriptWithLabel() {
    let expr = firstExpression("arr[row: 1, col: 2]")
    let sub = expr as? AST.Subscript
    #expect(sub != nil)
    #expect(sub!.arguments.count == 2)
    #expect(sub!.arguments[0].label?.value == "row")
    #expect(sub!.arguments[1].label?.value == "col")
    let val0 = sub!.arguments[0].value as? AST.IntegerLiteral
    #expect(val0!.value == 1)
    let val1 = sub!.arguments[1].value as? AST.IntegerLiteral
    #expect(val1!.value == 2)
}

@Test func parseSubscriptWithTrailingComma() {
    let expr = firstExpression("arr[1, 2,]")
    let sub = expr as? AST.Subscript
    #expect(sub != nil)
    #expect(sub!.arguments.count == 2)
}

@Test func parseChainedSubscript() {
    let expr = firstExpression("arr[0][1]")
    let outer = expr as? AST.Subscript
    #expect(outer != nil)
    let inner = outer!.base as? AST.Subscript
    #expect(inner != nil)
    let base = inner!.base as? AST.Variable
    #expect(base!.name.value == "arr")
    #expect(outer!.arguments.count == 1)
    #expect(inner!.arguments.count == 1)
}

@Test func parseSubscriptThenMemberAccess() {
    let expr = firstExpression("arr[0].field")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "field")
    let sub = member!.object as? AST.Subscript
    #expect(sub != nil)
    let base = sub!.base as? AST.Variable
    #expect(base!.name.value == "arr")
}

@Test func parseMemberAccessThenSubscript() {
    let expr = firstExpression("obj.field[0]")
    let sub = expr as? AST.Subscript
    #expect(sub != nil)
    let member = sub!.base as? AST.MemberAccess
    #expect(member != nil)
    #expect(member!.member.value == "field")
    let obj = member!.object as? AST.Variable
    #expect(obj!.name.value == "obj")
}

@Test func parseCallWithSingleArgument() {
    let expr = firstExpression("foo(1)")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 1)
    #expect(call!.arguments[0].label == nil)
    let arg = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(arg != nil)
    #expect(arg!.value == 1)
}

@Test func parseCallWithMultipleArguments() {
    let expr = firstExpression("foo(1, 2, 3)")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 3)
    for i in 0..<3 {
        let arg = call!.arguments[i].value as? AST.IntegerLiteral
        #expect(arg != nil)
        #expect(arg!.value == Int128(i + 1))
    }
}

@Test func parseCallWithLabeledArguments() {
    let expr = firstExpression("foo(a: 1, b: 2)")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 2)
    #expect(call!.arguments[0].label?.value == "a")
    #expect(call!.arguments[1].label?.value == "b")
    let val0 = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(val0!.value == 1)
    let val1 = call!.arguments[1].value as? AST.IntegerLiteral
    #expect(val1!.value == 2)
}

@Test func parseCallWithMixedArguments() {
    let expr = firstExpression("foo(1, b: 2)")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 2)
    #expect(call!.arguments[0].label == nil)
    #expect(call!.arguments[1].label?.value == "b")
}

@Test func parseCallWithTrailingComma() {
    let expr = firstExpression("foo(1, 2,)")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 2)
}

@Test func parseCallWithExpressionArgument() {
    let expr = firstExpression("foo(a + b)")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 1)
    let seq = call!.arguments[0].value as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
}

@Test func parseFunctionDeclWithSingleParameter() {
    let statements = parseStatements("func foo(a: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].label?.value == "a")
    #expect(decl!.parameters[0].name.value == "a")
    let type = decl!.parameters[0].type as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int")
    #expect(decl!.parameters[0].defaultValue == nil)
}

@Test func parseFunctionDeclWithMultipleParameters() {
    let statements = parseStatements("func foo(a: Int, b: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 2)
    #expect(decl!.parameters[0].name.value == "a")
    #expect(decl!.parameters[1].name.value == "b")
}

@Test func parseFunctionDeclWithWildcardLabel() {
    let statements = parseStatements("func foo(_ a: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].label == nil)
    #expect(decl!.parameters[0].name.value == "a")
}

@Test func parseFunctionDeclWithExplicitLabel() {
    let statements = parseStatements("func foo(by a: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].label?.value == "by")
    #expect(decl!.parameters[0].name.value == "a")
}

@Test func parseFunctionDeclWithDefaultValue() {
    let statements = parseStatements("func foo(a: Int = 42) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    let defVal = decl!.parameters[0].defaultValue as? AST.IntegerLiteral
    #expect(defVal != nil)
    #expect(defVal!.value == 42)
}

@Test func parseFunctionDeclWithMixedParameters() {
    let statements = parseStatements("func foo(_ a: Int, b: Int = 0, by c: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 3)
    #expect(decl!.parameters[0].label == nil)
    #expect(decl!.parameters[0].name.value == "a")
    #expect(decl!.parameters[1].label?.value == "b")
    #expect(decl!.parameters[1].name.value == "b")
    let defVal = decl!.parameters[1].defaultValue as? AST.IntegerLiteral
    #expect(defVal != nil)
    #expect(defVal!.value == 0)
    #expect(decl!.parameters[2].label?.value == "by")
    #expect(decl!.parameters[2].name.value == "c")
}

@Test func parseFunctionDeclWithTrailingComma() {
    let statements = parseStatements("func foo(a: Int,) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
}

// MARK: - Variadic Type

@Test func parseFunctionDeclWithVariadicType() {
    let statements = parseStatements("func foo(_ xs: Int...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    #expect(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Int")
    #expect(variadic!.token.kind == .Operator(.DotDotDot))
}

@Test func parseFunctionDeclWithLabeledVariadicType() {
    let statements = parseStatements("func foo(items: Int32...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    #expect(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base!.name.value == "Int32")
}

@Test func parseFunctionDeclWithTupleVariadicType() {
    let statements = parseStatements("func foo(_ xs: (Int, String)...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    #expect(variadic != nil)
    let tuple = variadic!.base as? AST.TupleExpression
    #expect(tuple != nil)
    #expect(tuple!.elements.count == 2)
}

@Test func parseVariableDeclWithVariadicType() {
    let statements = parseStatements("let x: Int...")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    let variadic = decl!.typeExpression as? AST.VariadicType
    #expect(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base!.name.value == "Int")
}

@Test func parseEnumCaseWithVariadicType() {
    let statements = parseStatements("enum E { case a(Int...) }")
    let enumDecl = statements[0] as? AST.EnumDecl
    #expect(enumDecl != nil)
    let caseDecl = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(caseDecl != nil)
    let variadic = caseDecl!.elements[0].associatedValues[0].typeExpression as? AST.VariadicType
    #expect(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base!.name.value == "Int")
}

@Test func parseRangeExpressionStillSequential() {
    let statements = parseStatements("let r = 1...5")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    let seq = decl!.initializer as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    #expect(seq!.operands.count == 2)
}

@Test func parseFunctionDeclNonVariadicTypeUnaffected() {
    let statements = parseStatements("func foo(_ xs: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let type = decl!.parameters[0].type as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int")
}

// MARK: - C-Style Vararg

@Test func parseFunctionDeclWithCStyleVararg() {
    let statements = parseStatements("func f(i: Int32, ...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].name.value == "i")
    #expect(decl!.varargToken != nil)
    #expect(decl!.varargToken!.kind == .Operator(.DotDotDot))
}

@Test func parseFunctionDeclBareVararg() {
    let statements = parseStatements("func f(...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 0)
    #expect(decl!.varargToken != nil)
}

@Test func parseFunctionDeclWithoutVararg() {
    let statements = parseStatements("func f(i: Int32) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.varargToken == nil)
}

@Test func parseFunctionDeclCStyleVarargAfterSwiftVariadic() {
    let statements = parseStatements("func f(_ xs: Int..., ...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    #expect(variadic != nil)
    #expect(decl!.varargToken != nil)
}

@Test func parseSwiftVariadicDoesNotSetVarargToken() {
    let statements = parseStatements("func f(_ xs: Int...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.varargToken == nil)
}

@Test func parseMemberAccessInteger() {
    let expr = firstExpression("tuple.0")
    let member = expr as? AST.MemberAccess
    #expect(member != nil)
    let obj = member!.object as? AST.Variable
    #expect(obj!.name.value == "tuple")
    #expect(member!.member.kind == .IntegerLiteral(0))
}

@Test func parseArrayLiteralInExpression() {
    let expr = firstExpression("a + [1, 2]")
    let seq = expr as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
    #expect(seq!.operands.count == 2)
    let left = seq!.operands[0] as? AST.Variable
    #expect(left!.name.value == "a")
    let right = seq!.operands[1] as? AST.ArrayLiteral
    #expect(right != nil)
    #expect(right!.elements.count == 2)
}

// MARK: - Optional Binding (if let / guard let / while let)

@Test func parseIfLetBasic() {
    let body = parseBlockStatements("func main() { if let x = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    #expect(ifExpr != nil)
    let binding = ifExpr!.condition as? AST.OptionalBinding
    #expect(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Let))
    #expect(binding!.name.value == "x")
    #expect(binding!.typeExpression == nil)
    let value = binding!.value as? AST.Variable
    #expect(value!.name.value == "a")
}

@Test func parseIfLetWithTypeAnnotation() {
    let body = parseBlockStatements("func main() { if let x: Int32 = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let binding = ifExpr!.condition as? AST.OptionalBinding
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
    #expect(binding!.typeExpression != nil)
}

@Test func parseIfVar() {
    let body = parseBlockStatements("func main() { if var x = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let binding = ifExpr!.condition as? AST.OptionalBinding
    #expect(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Var))
}

@Test func parseIfLetWithAndCombination() {
    let body = parseBlockStatements("func main() { if (let x = a) && (let y = b) {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let seq = ifExpr!.condition as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.And))
    let lhs = seq!.operands[0] as? AST.ParentheticalExpression
    #expect(lhs != nil)
    let lhsBinding = lhs!.inner as? AST.OptionalBinding
    #expect(lhsBinding != nil)
    #expect(lhsBinding!.name.value == "x")
    let rhs = seq!.operands[1] as? AST.ParentheticalExpression
    #expect(rhs != nil)
    let rhsBinding = rhs!.inner as? AST.OptionalBinding
    #expect(rhsBinding != nil)
    #expect(rhsBinding!.name.value == "y")
}

@Test func parseGuardLet() {
    let body = parseBlockStatements("func main() { guard let x = a else {} }")
    #expect(body.count == 1)
    let guardStmt = body[0] as? AST.Guard
    #expect(guardStmt != nil)
    let binding = guardStmt!.condition as? AST.OptionalBinding
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseWhileLet() {
    let body = parseBlockStatements("func main() { while let x = a {} }")
    #expect(body.count == 1)
    let whileStmt = body[0] as? AST.While
    #expect(whileStmt != nil)
    let binding = whileStmt!.condition as? AST.OptionalBinding
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
}

// MARK: - Case Match (if case)

@Test func parseIfCaseDotName() {
    let body = parseBlockStatements("func main() { if case .foo = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let pattern = caseMatch!.pattern as? AST.ImplicitMemberAccess
    #expect(pattern != nil)
    #expect(pattern!.name.value == "foo")
    let subject = caseMatch!.subject as? AST.Variable
    #expect(subject!.name.value == "a")
}

@Test func parseIfCaseWithBinding() {
    let body = parseBlockStatements("func main() { if case .foo(let x) = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let call = caseMatch!.pattern as? AST.Call
    #expect(call != nil)
    let member = call!.callee as? AST.ImplicitMemberAccess
    #expect(member!.name.value == "foo")
    #expect(call!.arguments.count == 1)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Let))
    #expect(binding!.name.value == "x")
}

@Test func parseIfCaseNestedPattern() {
    let body = parseBlockStatements("func main() { if case .some(.some(let x)) = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let outerCall = caseMatch!.pattern as? AST.Call
    #expect(outerCall != nil)
    let outerMember = outerCall!.callee as? AST.ImplicitMemberAccess
    #expect(outerMember!.name.value == "some")
    let innerCall = outerCall!.arguments[0].value as? AST.Call
    #expect(innerCall != nil)
    let innerMember = innerCall!.callee as? AST.ImplicitMemberAccess
    #expect(innerMember!.name.value == "some")
    let binding = innerCall!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseIfCaseQualified() {
    let body = parseBlockStatements("func main() { if case Color.red = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let memberAccess = caseMatch!.pattern as? AST.MemberAccess
    #expect(memberAccess != nil)
    let base = memberAccess!.object as? AST.Variable
    #expect(base!.name.value == "Color")
    #expect(memberAccess!.member.value == "red")
}

@Test func parseIfCaseWildcard() {
    let body = parseBlockStatements("func main() { if case _ = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let wildcard = caseMatch!.pattern as? AST.WildcardPattern
    #expect(wildcard != nil)
}

// MARK: - Enum Declarations

@Test func parseBasicEnum() {
    let stmts = parseStatements("enum Color { case red\ncase green\ncase blue }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl != nil)
    #expect(enumDecl!.name.value == "Color")
    #expect(enumDecl!.genericDecl == nil)
    #expect(enumDecl!.conformances.isEmpty)
    #expect(enumDecl!.body.count == 3)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0 != nil)
    #expect(case0!.elements.count == 1)
    #expect(case0!.elements[0].name.value == "red")
    #expect(case0!.elements[0].associatedValues.isEmpty)
    #expect(case0!.elements[0].rawValue == nil)
}

@Test func parseEnumWithAssociatedValues() {
    let stmts = parseStatements("enum Result { case ok(Int32)\ncase err(String) }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl!.body.count == 2)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].name.value == "ok")
    #expect(case0!.elements[0].associatedValues.count == 1)
    #expect(case0!.elements[0].associatedValues[0].label == nil)
    let case1 = enumDecl!.body[1] as? AST.EnumCaseDecl
    #expect(case1!.elements[0].name.value == "err")
    #expect(case1!.elements[0].associatedValues.count == 1)
}

@Test func parseEnumWithNamedAssociatedValues() {
    let stmts = parseStatements("enum Point { case coord(x: Int32, y: Int32) }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].associatedValues.count == 2)
    #expect(case0!.elements[0].associatedValues[0].label?.value == "x")
    #expect(case0!.elements[0].associatedValues[1].label?.value == "y")
}

@Test func parseEnumGeneric() {
    let stmts = parseStatements("enum Result<T> { case ok(T)\ncase err(String) }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl != nil)
    #expect(enumDecl!.genericDecl != nil)
    #expect(enumDecl!.body.count == 2)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].name.value == "ok")
    let case1 = enumDecl!.body[1] as? AST.EnumCaseDecl
    #expect(case1!.elements[0].name.value == "err")
}

@Test func parseEnumWithRawValue() {
    let stmts = parseStatements("enum Color: Int32 { case red = 1\ncase green = 2 }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl!.conformances.count == 1)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].rawValue != nil)
    let rawVal = case0!.elements[0].rawValue as? AST.IntegerLiteral
    #expect(rawVal != nil)
}

@Test func parseIndirectEnum() {
    let stmts = parseStatements("indirect enum Tree { case node(Int32, Tree, Tree)\ncase leaf }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl != nil)
    #expect(enumDecl!.modifiers.count == 1)
    #expect(modifierKind(enumDecl!.modifiers[0].kind, equals: .Indirect))
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].associatedValues.count == 3)
}

@Test func parseEnumWithConformance() {
    let stmts = parseStatements("enum Foo: Equatable { case a\ncase b }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl!.conformances.count == 1)
    let conf = enumDecl!.conformances[0] as? AST.Variable
    #expect(conf!.name.value == "Equatable")
}

@Test func parseEnumMultipleCasesOnOneLine() {
    let stmts = parseStatements("enum Color { case red, green, blue }")
    #expect(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl!.body.count == 1)
    let caseDecl = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(caseDecl!.elements.count == 3)
    #expect(caseDecl!.elements[0].name.value == "red")
    #expect(caseDecl!.elements[1].name.value == "green")
    #expect(caseDecl!.elements[2].name.value == "blue")
}

// MARK: - Match with Bindings

@Test func parseMatchAtBindingPattern() {
    let expr = firstExpression("match a { let x @ .some -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    #expect(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseMatchAtBindingWithArguments() {
    let expr = firstExpression("match a { let x @ .some(let y) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    #expect(binding != nil)
    let call = binding!.subpattern as? AST.Call
    #expect(call != nil)
    let inner = call!.arguments[0].value as? AST.BindingPattern
    #expect(inner != nil)
    #expect(inner!.name.value == "y")
}

@Test func parseIfCaseAtBindingPattern() {
    let body = parseBlockStatements("func main() { if case let x @ .some = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let binding = caseMatch!.pattern as? AST.BindingPattern
    #expect(binding != nil)
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    #expect(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseNestedAtBindingPattern() {
    let expr = firstExpression("match a { .foo(let x @ .some) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    #expect(call != nil)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    #expect(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseWildcardAtBindingPattern() {
    let expr = firstExpression("match a { _ @ .some -> 1 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let subpattern = matchExpr!.cases[0].patterns[0] as? AST.ImplicitMemberAccess
    #expect(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseBindingPatternWithoutSubpattern() {
    let expr = firstExpression("match a { .some(let x) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.subpattern == nil)
}

// MARK: - Typed Binding in Patterns

@Test func parseNestedTypedBindingPattern() {
    let expr = firstExpression("match a { .foo(let x: Int) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    #expect(call != nil)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
    let type = binding!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int")
}

@Test func parseMatchTypedBindingPattern() {
    let expr = firstExpression("match a { let x: Int -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    #expect(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int")
    #expect(binding!.subpattern == nil)
}

@Test func parseIfCaseTypedBindingPattern() {
    let body = parseBlockStatements("func main() { if case let x: Int = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let binding = caseMatch!.pattern as? AST.BindingPattern
    #expect(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int")
}

@Test func parseForTypedBindingPattern() {
    let body = parseBlockStatements("func main() { for let x: Int in arr {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    let binding = forStmt!.pattern as? AST.BindingPattern
    #expect(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int")
}

@Test func parseCatchTypedBindingPattern() {
    let body = parseBlockStatements("func main() { do { } catch let e: Int32 { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let doExpr = exprStmt!.expression as? AST.Do
    #expect(doExpr != nil)
    let binding = doExpr!.catches[0].pattern as? AST.BindingPattern
    #expect(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int32")
}

@Test func parseTypedBindingWithAtSubpattern() {
    let expr = firstExpression("match a { let x: Int @ .some -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    #expect(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int")
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    #expect(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseBindingPatternWithoutType() {
    let expr = firstExpression("match a { .some(let x) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.typeExpression == nil)
}

// MARK: - As Binding in Patterns

@Test func parseMatchAsBindingPattern() {
    let expr = firstExpression("match a { let x as Int32 -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let asPattern = matchExpr!.cases[0].patterns[0] as? AST.AsPattern
    #expect(asPattern != nil)
    let binding = asPattern!.pattern as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
    let type = asPattern!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "Int32")
}

@Test func parseIfCaseAsBindingPattern() {
    let body = parseBlockStatements("func main() { if case let x as String = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let asPattern = caseMatch!.pattern as? AST.AsPattern
    #expect(asPattern != nil)
    let type = asPattern!.typeExpression as? AST.Variable
    #expect(type != nil)
    #expect(type!.name.value == "String")
}

@Test func parseWildcardAsBindingPattern() {
    let expr = firstExpression("match a { _ as Int32 -> 1 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let asPattern = matchExpr!.cases[0].patterns[0] as? AST.AsPattern
    #expect(asPattern != nil)
    #expect(asPattern!.pattern is AST.WildcardPattern)
}

@Test func parseAsExpressionStillCastExpression() {
    let expr = firstExpression("x as Int32")
    let cast = expr as? AST.CastExpression
    #expect(cast != nil)
    #expect(cast!.kind == .As)
    #expect(!(expr is AST.AsPattern))
}

@Test func parseAsQuestionInPatternStaysCast() {
    let expr = firstExpression("match a { let x as? Int32 -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let cast = matchExpr!.cases[0].patterns[0] as? AST.CastExpression
    #expect(cast != nil)
    #expect(cast!.kind == .AsQuestion)
}

@Test func parseMatchWithBinding() {
    let expr = firstExpression("match a { .some(let x) -> x, .none -> 0 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    #expect(matchExpr!.cases.count == 2)
    let case0 = matchExpr!.cases[0]
    #expect(case0.patterns.count == 1)
    let call = case0.patterns[0] as? AST.Call
    #expect(call != nil)
    let member = call!.callee as? AST.ImplicitMemberAccess
    #expect(member!.name.value == "some")
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseMatchWithPartialBinding() {
    let expr = firstExpression("match a { .foo(let x, _) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let case0 = matchExpr!.cases[0]
    let call = case0.patterns[0] as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 2)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
    let wildcard = call!.arguments[1].value as? AST.WildcardPattern
    #expect(wildcard != nil)
}

@Test func parseMatchWithNestedBinding() {
    let expr = firstExpression("match a { .some(.some(let x)) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let case0 = matchExpr!.cases[0]
    let outerCall = case0.patterns[0] as? AST.Call
    #expect(outerCall != nil)
    let innerCall = outerCall!.arguments[0].value as? AST.Call
    #expect(innerCall != nil)
    let binding = innerCall!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseMatchWithMultiplePatterns() {
    let expr = firstExpression("match a { .a, .b -> 1, .c -> 2 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    #expect(matchExpr!.cases.count == 2)
    #expect(matchExpr!.cases[0].patterns.count == 2)
    #expect(matchExpr!.cases[1].patterns.count == 1)
}

@Test func parseMatchMixedLiteralAndBinding() {
    let expr = firstExpression("match a { .foo(1, let x) -> x }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let case0 = matchExpr!.cases[0]
    let call = case0.patterns[0] as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 2)
    let lit = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(lit != nil)
    let binding = call!.arguments[1].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseMatchWithWildcardCatchAll() {
    let expr = firstExpression("match a { _ -> 42 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    #expect(matchExpr!.cases.count == 1)
    let case0 = matchExpr!.cases[0]
    #expect(case0.patterns.count == 1)
    #expect(case0.patterns[0] is AST.WildcardPattern)
}

@Test func parseIfCaseMixedLiteralAndBinding() {
    let body = parseBlockStatements("func main() { if case .foo(1, let x) = a {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let call = caseMatch!.pattern as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 2)
    let lit = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(lit != nil)
    let binding = call!.arguments[1].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "x")
}

// MARK: - Range Operators in Patterns

@Test func parseMatchRangePatternClosed() {
    let expr = firstExpression("match x { 1...5 -> 1 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    #expect(matchExpr!.cases.count == 1)
    let seq = matchExpr!.cases[0].patterns[0] as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    #expect(seq!.operands.count == 2)
    let lower = seq!.operands[0] as? AST.IntegerLiteral
    #expect(lower != nil)
    #expect(lower!.value == 1)
    let upper = seq!.operands[1] as? AST.IntegerLiteral
    #expect(upper != nil)
    #expect(upper!.value == 5)
}

@Test func parseMatchRangePatternHalfOpen() {
    let expr = firstExpression("match x { 1..<5 -> 1 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let seq = matchExpr!.cases[0].patterns[0] as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDotLess))
}

@Test func parseMatchRangePatternDotDot() {
    let expr = firstExpression("match x { 1..5 -> 1 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    let seq = matchExpr!.cases[0].patterns[0] as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDot))
}

@Test func parseMatchMultipleRangePatterns() {
    let expr = firstExpression("match x { 1...5, 10...20 -> 1, 30...40 -> 2 }")
    let matchExpr = expr as? AST.Match
    #expect(matchExpr != nil)
    #expect(matchExpr!.cases.count == 2)
    #expect(matchExpr!.cases[0].patterns.count == 2)
    #expect(matchExpr!.cases[1].patterns.count == 1)
    for pattern in matchExpr!.cases[0].patterns {
        let seq = pattern as? AST.SequentialExpression
        #expect(seq != nil)
        #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    }
}

@Test func parseIfCaseRangePattern() {
    let body = parseBlockStatements("func main() { if case 1...5 = x {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let seq = caseMatch!.pattern as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    #expect(seq!.operands.count == 2)
}

// MARK: - ShorthandArgument

@Test func parseShorthandArgumentDollar0() {
    let body = parseBlockStatements("func main() { $0 }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let arg = exprStmt!.expression as? AST.ShorthandArgument
    #expect(arg != nil)
    #expect(arg!.index == 0)
}

@Test func parseShorthandArgumentDollar42() {
    let body = parseBlockStatements("func main() { $42 }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let arg = exprStmt!.expression as? AST.ShorthandArgument
    #expect(arg != nil)
    #expect(arg!.index == 42)
}

@Test func parseShorthandArgumentInClosure() {
    let body = parseBlockStatements("func main() { { $0 } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    #expect(closure!.body.count == 1)
    let innerExpr = closure!.body[0] as? AST.ExpressionStatement
    #expect(innerExpr != nil)
    let arg = innerExpr!.expression as? AST.ShorthandArgument
    #expect(arg != nil)
    #expect(arg!.index == 0)
}

// MARK: - Trailing Closure

@Test func parseTrailingClosureWithoutParens() {
    let body = parseBlockStatements("func main() { arr.filter { $0 } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.isEmpty)
    #expect(call!.trailingClosures.count == 1)
    #expect(call!.trailingClosures[0].0 == nil)
    let memberAccess = call!.callee as? AST.MemberAccess
    #expect(memberAccess != nil)
}

@Test func parseTrailingClosureWithParens() {
    let body = parseBlockStatements("func main() { foo() { $0 } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.isEmpty)
    #expect(call!.trailingClosures.count == 1)
    #expect(call!.trailingClosures[0].0 == nil)
}

@Test func parseMultipleTrailingClosures() {
    let body = parseBlockStatements("func main() { foo { } bar: { } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.isEmpty)
    #expect(call!.trailingClosures.count == 2)
    #expect(call!.trailingClosures[0].0 == nil)
    #expect(call!.trailingClosures[1].0?.value == "bar")
}

@Test func parseTrailingClosureWithArgs() {
    let body = parseBlockStatements("func main() { foo(1) { $0 } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 1)
    #expect(call!.trailingClosures.count == 1)
    #expect(call!.trailingClosures[0].0 == nil)
}

// MARK: - String Interpolation

@Test func parseStringInterpolationSimple() {
    let expr = firstExpression("\"hello \\(name)\"")
    let interp = expr as? AST.StringInterpolation
    #expect(interp != nil)
    #expect(interp!.segments.count == 3)
    guard case .literal(let first) = interp!.segments[0] else {
        #expect(Bool(false))
        return
    }
    #expect(first.value == "hello ")
    guard case .expression(let e) = interp!.segments[1] else {
        #expect(Bool(false))
        return
    }
    #expect(e is AST.Variable)
    guard case .literal(let last) = interp!.segments[2] else {
        #expect(Bool(false))
        return
    }
    #expect(last.value == "")
    #expect(!last.isUnterminated)
}

@Test func parseStringInterpolationMultiSegment() {
    let expr = firstExpression("\"\\(v1) \\(v2)\"")
    let interp = expr as? AST.StringInterpolation
    #expect(interp != nil)
    #expect(interp!.segments.count == 5)
    guard case .literal(let first) = interp!.segments[0] else {
        #expect(Bool(false))
        return
    }
    #expect(first.value == "")
    #expect(first.isUnterminated)
    guard case .expression = interp!.segments[1] else {
        #expect(Bool(false))
        return
    }
    guard case .literal(let mid) = interp!.segments[2] else {
        #expect(Bool(false))
        return
    }
    #expect(mid.value == " ")
    #expect(mid.isUnterminated)
}

// MARK: - Closure Signature

@Test func parseClosureWithParameters() {
    let body = parseBlockStatements("func main() { { (x: Int) in x } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    #expect(closure!.signature != nil)
    #expect(closure!.signature!.parameters.count == 1)
    #expect(closure!.signature!.parameters[0].name.value == "x")
    #expect(closure!.body.count == 1)
}

@Test func parseClosureWithReturnType() {
    let body = parseBlockStatements("func main() { { () -> Int in 42 } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    #expect(closure!.signature?.returnType != nil)
}

@Test func parseClosureWithCaptureList() {
    let body = parseBlockStatements("func main() { { [weak self] in self.foo() } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    let sig = closure!.signature
    #expect(sig != nil)
    #expect(sig!.captureList.count == 1)
    #expect(sig!.captureList[0].specifier?.value == "weak")
    #expect(sig!.captureList[0].name.value == "self")
}

// MARK: - OptionalType

@Test func parseOptionalTypeSimple() {
    let expr = firstExpression("Int?")
    let optional = expr as? AST.OptionalType
    #expect(optional != nil)
    let inner = optional!.wrappedType as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "Int")
}

@Test func parseOptionalTypeNested() {
    let expr = firstExpression("Int??")
    let outer = expr as? AST.OptionalType
    #expect(outer != nil)
    let inner = outer!.wrappedType as? AST.OptionalType
    #expect(inner != nil)
    let innermost = inner!.wrappedType as? AST.Variable
    #expect(innermost != nil)
    #expect(innermost!.name.value == "Int")
}

@Test func parseOptionalTypeInReturnType() {
    let stmts = parseStatements("func f() -> Int? {}")
    #expect(stmts.count == 1)
    let funcDecl = stmts[0] as? AST.FunctionDecl
    #expect(funcDecl != nil)
    let retType = funcDecl!.returnTypeExpression as? AST.OptionalType
    #expect(retType != nil)
    let inner = retType!.wrappedType as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "Int")
}

@Test func parseOptionalTypeInVariableDeclaration() {
    let stmts = parseStatements("let x: Int?")
    #expect(stmts.count == 1)
    let varDecl = stmts[0] as? AST.VariableDecl
    #expect(varDecl != nil)
    let type = varDecl!.typeExpression as? AST.OptionalType
    #expect(type != nil)
    let inner = type!.wrappedType as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "Int")
}

// MARK: - SomeType / AnyType

@Test func parseSomeTypeSimple() {
    let expr = firstExpression("some Collection")
    let some = expr as? AST.SomeType
    #expect(some != nil)
    let inner = some!.wrappedType as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "Collection")
}

@Test func parseAnyTypeSimple() {
    let expr = firstExpression("any Collection")
    let anyType = expr as? AST.AnyType
    #expect(anyType != nil)
    let inner = anyType!.wrappedType as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "Collection")
}

@Test func parseSomeTypeWithComposition() {
    let expr = firstExpression("some A & B")
    let some = expr as? AST.SomeType
    #expect(some != nil)
    let comp = some!.wrappedType as? AST.ProtocolCompositionType
    #expect(comp != nil)
    #expect(comp!.types.count == 2)
    let t0 = comp!.types[0] as? AST.Variable
    #expect(t0 != nil)
    #expect(t0!.name.value == "A")
    let t1 = comp!.types[1] as? AST.Variable
    #expect(t1 != nil)
    #expect(t1!.name.value == "B")
}

@Test func parseSomeTypeWithMultipleComposition() {
    let expr = firstExpression("some A & B & C")
    let some = expr as? AST.SomeType
    #expect(some != nil)
    let comp = some!.wrappedType as? AST.ProtocolCompositionType
    #expect(comp != nil)
    #expect(comp!.types.count == 3)
}

@Test func parseAnyTypeWithComposition() {
    let expr = firstExpression("any A & B")
    let anyType = expr as? AST.AnyType
    #expect(anyType != nil)
    let comp = anyType!.wrappedType as? AST.ProtocolCompositionType
    #expect(comp != nil)
    #expect(comp!.types.count == 2)
}

@Test func parseSomeTypeWithOptionalInner() {
    let expr = firstExpression("some Int?")
    let some = expr as? AST.SomeType
    #expect(some != nil)
    let optional = some!.wrappedType as? AST.OptionalType
    #expect(optional != nil)
    let inner = optional!.wrappedType as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "Int")
}

@Test func parseSomeTypeInGenericConstraint() {
    let stmts = parseStatements("struct Foo<each T: some P> {}")
    #expect(stmts.count == 1)
    let structDecl = stmts[0] as? AST.StructDecl
    #expect(structDecl != nil)
    #expect(structDecl!.genericDecl != nil)
    let generics = structDecl!.genericDecl!.generics
    #expect(generics.count == 1)
    let some = generics[0].constraint as? AST.SomeType
    #expect(some != nil)
    let inner = some!.wrappedType as? AST.Variable
    #expect(inner != nil)
    #expect(inner!.name.value == "P")
}

// MARK: - Self type constraint

@Test func parseSelfInGenericConstraint() {
    let stmts = parseStatements("struct Foo<each T: Self> {}")
    #expect(stmts.count == 1)
    let structDecl = stmts[0] as? AST.StructDecl
    #expect(structDecl != nil)
    #expect(structDecl!.genericDecl != nil)
    #expect(structDecl!.genericDecl!.generics.count == 1)
    let constraint = structDecl!.genericDecl!.generics[0].constraint as? AST.SelfTypeExpression
    #expect(constraint != nil)
}

// MARK: - TupleExpression

@Test func parseTupleExpression() {
    let expr = firstExpression("(1, 2)")
    let tuple = expr as? AST.TupleExpression
    #expect(tuple != nil)
    #expect(tuple!.elements.count == 2)
    let e0 = tuple!.elements[0].value as? AST.IntegerLiteral
    #expect(e0 != nil)
    let e1 = tuple!.elements[1].value as? AST.IntegerLiteral
    #expect(e1 != nil)
}

@Test func parseLabeledTupleExpression() {
    let expr = firstExpression("(name: String, age: Int)")
    let tuple = expr as? AST.TupleExpression
    #expect(tuple != nil)
    #expect(tuple!.elements.count == 2)
    #expect(tuple!.elements[0].label?.value == "name")
    #expect(tuple!.elements[1].label?.value == "age")
}

@Test func parseTupleWithTrailingComma() {
    let expr = firstExpression("(1, 2,)")
    let tuple = expr as? AST.TupleExpression
    #expect(tuple != nil)
    #expect(tuple!.elements.count == 2)
}

@Test func parseTuplePattern() {
    let body = parseBlockStatements("func main() { match x { (a, b) -> a } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let match = exprStmt!.expression as? AST.Match
    #expect(match != nil)
    #expect(match!.cases.count == 1)
    let patterns = match!.cases[0].patterns
    #expect(patterns.count == 1)
    let tuple = patterns[0] as? AST.TupleExpression
    #expect(tuple != nil)
    #expect(tuple!.elements.count == 2)
    let e0 = tuple!.elements[0].value as? AST.Variable
    #expect(e0 != nil)
    #expect(e0!.name.value == "a")
    let e1 = tuple!.elements[1].value as? AST.Variable
    #expect(e1 != nil)
    #expect(e1!.name.value == "b")
}

@Test func parseTuplePatternWithBinding() {
    let body = parseBlockStatements("func main() { match x { (a, let b) -> b } }")
    let exprStmt = body[0] as? AST.ExpressionStatement
    let match = exprStmt!.expression as? AST.Match
    let tuple = match!.cases[0].patterns[0] as? AST.TupleExpression
    #expect(tuple != nil)
    #expect(tuple!.elements.count == 2)
    let binding = tuple!.elements[1].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "b")
}

// MARK: - IsPattern

@Test func parseIsPatternInMatch() {
    let body = parseBlockStatements("func main() { match x { is Int -> \"int\" } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let match = exprStmt!.expression as? AST.Match
    #expect(match != nil)
    #expect(match!.cases.count == 1)
    #expect(match!.cases[0].patterns.count == 1)
    let isPattern = match!.cases[0].patterns[0] as? AST.IsPattern
    #expect(isPattern != nil)
    let typeExpr = isPattern!.typeExpression as? AST.Variable
    #expect(typeExpr != nil)
    #expect(typeExpr!.name.value == "Int")
}

@Test func parseIsPatternInIfCase() {
    let body = parseBlockStatements("func main() { if case is Int = x {} }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let isPattern = caseMatch!.pattern as? AST.IsPattern
    #expect(isPattern != nil)
    let typeExpr = isPattern!.typeExpression as? AST.Variable
    #expect(typeExpr != nil)
    #expect(typeExpr!.name.value == "Int")
}

// MARK: - TypeAlias Declarations

@Test func parseTypeAliasSimple() {
    let statements = parseStatements("typealias Foo = Int32")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.TypeAliasDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.TypeAlias))
    #expect(decl!.name.kind == .Identifier)
    #expect(decl!.name.value == "Foo")
    let typeVar = decl!.typeExpression as? AST.Variable
    #expect(typeVar != nil)
    #expect(typeVar!.name.value == "Int32")
}

@Test func parseTypeAliasWithGenericType() {
    let statements = parseStatements("typealias Pair = (Int32, Int32)")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.TypeAliasDecl
    #expect(decl != nil)
    let tuple = decl!.typeExpression as? AST.TupleExpression
    #expect(tuple != nil)
    #expect(tuple!.elements.count == 2)
}

@Test func parseTypeAliasInStructBody() {
    let statements = parseStatements("struct Foo { typealias Inner = Int32 }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    #expect(structDecl!.body.count == 1)
    let alias = structDecl!.body[0] as? AST.TypeAliasDecl
    #expect(alias != nil)
    #expect(alias!.name.value == "Inner")
}

@Test func parseTypeAliasMissingNameReportsError() throws {
    let (_, errors) = parseWithDiagnostics("typealias")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected type name after 'typealias'"))
}

@Test func parseTypeAliasNonIdentifierNameReportsError() throws {
    let (_, errors) = parseWithDiagnostics("typealias 123 = Int32")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected identifier after 'typealias'"))
}

@Test func parseTypeAliasMissingEqualReportsError() throws {
    let (_, errors) = parseWithDiagnostics("typealias Foo")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '=' after type alias name"))
}

@Test func parseTypeAliasMissingTypeExpressionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("typealias Foo =")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected type expression after '='"))
}

// MARK: - Extern Declarations

@Test func parseExternDeclarationForm() {
    let statements = parseStatements("extern \"C\" func foo() -> Int32")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    #expect(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Extern))
    #expect(decl!.convention.value == "C")
    if case .Declaration(let inner) = decl!.body {
        let fd = inner as? AST.FunctionDecl
        #expect(fd != nil)
        #expect(fd!.name.value == "foo")
    } else {
        Issue.record("expected .Declaration body")
    }
}

@Test func parseExternVariableDeclaration() {
    let statements = parseStatements("extern \"C\" var errno: Int32")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    #expect(decl != nil)
    if case .Declaration(let inner) = decl!.body {
        let vd = inner as? AST.VariableDecl
        #expect(vd != nil)
        #expect(vd!.name.value == "errno")
    } else {
        Issue.record("expected .Declaration body")
    }
}

@Test func parseExternBlockForm() {
    let statements = parseStatements("extern \"C\" { func foo() func bar() }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    #expect(decl != nil)
    if case .Block(let body) = decl!.body {
        #expect(body.count == 2)
        let fd0 = body[0] as? AST.FunctionDecl
        #expect(fd0 != nil)
        #expect(fd0!.name.value == "foo")
        let fd1 = body[1] as? AST.FunctionDecl
        #expect(fd1 != nil)
        #expect(fd1!.name.value == "bar")
    } else {
        Issue.record("expected .Block body")
    }
}

@Test func parseExternBlockWithMixedDeclarations() {
    let statements = parseStatements("extern \"C\" { let x = 1 var y: Int32 func foo() }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    #expect(decl != nil)
    if case .Block(let body) = decl!.body {
        #expect(body.count == 3)
        #expect(body[0] is AST.VariableDecl)
        #expect(body[1] is AST.VariableDecl)
        #expect(body[2] is AST.FunctionDecl)
    } else {
        Issue.record("expected .Block body")
    }
}

@Test func parseExternMissingConventionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("extern")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected calling convention after 'extern'"))
}

@Test func parseExternNonStringConventionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("extern 123 func foo()")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected calling convention (string literal) after 'extern'"))
}

@Test func parseExternMissingBodyReportsError() throws {
    let (_, errors) = parseWithDiagnostics("extern \"C\"")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '{' or declaration after extern calling convention"))
}

@Test func parseExternBlockUnterminatedReportsError() throws {
    let (_, errors) = parseWithDiagnostics("extern \"C\" { func foo()")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '}' after extern body"))
}

// MARK: - Deinit Declarations

@Test func parseDeinitEmptyBody() {
    let statements = parseStatements("class Foo { deinit {} }")
    #expect(statements.count == 1)
    let classDecl = statements[0] as? AST.ClassDecl
    #expect(classDecl != nil)
    #expect(classDecl!.body.count == 1)
    let deinitDecl = classDecl!.body[0] as? AST.DeinitDecl
    #expect(deinitDecl != nil)
    #expect(deinitDecl!.token.kind == .Keyword(.Deinit))
    #expect(deinitDecl!.body.isEmpty)
}

@Test func parseDeinitWithBody() {
    let statements = parseStatements("class Foo { deinit { cleanup() } }")
    #expect(statements.count == 1)
    let classDecl = statements[0] as? AST.ClassDecl
    #expect(classDecl != nil)
    let deinitDecl = classDecl!.body[0] as? AST.DeinitDecl
    #expect(deinitDecl != nil)
    #expect(deinitDecl!.body.count == 1)
}

@Test func parseDeinitMissingOpenBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("class Foo { deinit }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '{' after 'deinit'"))
}

@Test func parseDeinitNonBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("class Foo { deinit 123 }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected '{' after 'deinit'") })
}

// MARK: - AssociatedType Declarations

@Test func parseAssociatedTypeBare() {
    let statements = parseStatements("protocol P { associatedtype T }")
    #expect(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    #expect(protocolDecl != nil)
    #expect(protocolDecl!.body.count == 1)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    #expect(assoc!.token.kind == .Keyword(.AssociatedType))
    #expect(assoc!.name.value == "T")
    #expect(assoc!.constraint == nil)
    #expect(assoc!.whereClause == nil)
}

@Test func parseAssociatedTypeWithConstraint() {
    let statements = parseStatements("protocol P { associatedtype T: Equatable }")
    #expect(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    #expect(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let constraint = assoc!.constraint as? AST.Variable
    #expect(constraint != nil)
    #expect(constraint!.name.value == "Equatable")
    #expect(assoc!.whereClause == nil)
}

@Test func parseAssociatedTypeMissingNameReportsError() throws {
    let (_, errors) = parseWithDiagnostics("protocol P { associatedtype }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected identifier after 'associatedtype'"))
}

@Test func parseAssociatedTypeNonIdentifierReportsError() throws {
    let (_, errors) = parseWithDiagnostics("protocol P { associatedtype 123 }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected identifier after 'associatedtype'") })
}

// MARK: - Where Clause

@Test func parseWhereClauseConformance() {
    let statements = parseStatements("protocol P { associatedtype T where T: Equatable }")
    #expect(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    #expect(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let whereClause = assoc!.whereClause
    #expect(whereClause != nil)
    #expect(whereClause!.count == 1)
    let left = whereClause![0].left as? AST.Variable
    #expect(left != nil)
    #expect(left!.name.value == "T")
    if case .conformance(let right) = whereClause![0].constraint {
        let rightVar = right as? AST.Variable
        #expect(rightVar != nil)
        #expect(rightVar!.name.value == "Equatable")
    } else {
        Issue.record("expected conformance constraint")
    }
}

@Test func parseWhereClauseEquality() {
    let statements = parseStatements("protocol P { associatedtype T where T == Int32 }")
    #expect(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    #expect(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let whereClause = assoc!.whereClause
    #expect(whereClause != nil)
    #expect(whereClause!.count == 1)
    let left = whereClause![0].left as? AST.Variable
    #expect(left != nil)
    #expect(left!.name.value == "T")
    if case .equality(let right) = whereClause![0].constraint {
        let rightVar = right as? AST.Variable
        #expect(rightVar != nil)
        #expect(rightVar!.name.value == "Int32")
    } else {
        Issue.record("expected equality constraint")
    }
}

@Test func parseWhereClauseEqualityWithGenericType() {
    let statements = parseStatements("protocol P { associatedtype T where T == Array<U> }")
    #expect(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    #expect(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    if case .equality(let right) = assoc!.whereClause![0].constraint {
        let seq = right as? AST.SequentialExpression
        #expect(seq != nil)
        #expect(seq!.ops.count == 2)
        let base = seq!.operands[0] as? AST.Variable
        #expect(base != nil)
        #expect(base!.name.value == "Array")
        let arg = seq!.operands[1] as? AST.Variable
        #expect(arg != nil)
        #expect(arg!.name.value == "U")
    } else {
        Issue.record("expected equality constraint")
    }
}

@Test func parseStructWhereClauseEquality() {
    let statements = parseStatements("struct S<T> where T == Int32 {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    let whereClause = decl!.whereClause
    #expect(whereClause != nil)
    #expect(whereClause!.count == 1)
    if case .equality = whereClause![0].constraint {
    } else {
        Issue.record("expected equality constraint")
    }
}

@Test func parseWhereClauseMultipleRequirements() {
    let statements = parseStatements(
        "protocol P { associatedtype T where T: Equatable, T.Element: Hashable }")
    #expect(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    #expect(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let whereClause = assoc!.whereClause
    #expect(whereClause != nil)
    #expect(whereClause!.count == 2)
}

@Test func parseWhereClauseMissingOperatorReportsError() throws {
    let (_, errors) = parseWithDiagnostics("protocol P { associatedtype T where T }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected ':' or '==' in where clause"))
}

@Test func parseWhereClauseSingleEqualReportsError() throws {
    let (_, errors) = parseWithDiagnostics("protocol P { associatedtype T where T = Int32 }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected ':' or '==' in where clause"))
}

// MARK: - Where Clause on Type Declarations

@Test func parseStructWhereClauseConformance() {
    let statements = parseStatements("struct S<T> where T: Equatable {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl != nil)
    let whereClause = decl!.whereClause
    #expect(whereClause != nil)
    #expect(whereClause!.count == 1)
    let left = whereClause![0].left as? AST.Variable
    #expect(left != nil)
    #expect(left!.name.value == "T")
    if case .conformance(let right) = whereClause![0].constraint {
        let rightVar = right as? AST.Variable
        #expect(rightVar != nil)
        #expect(rightVar!.name.value == "Equatable")
    } else {
        Issue.record("expected conformance constraint")
    }
    #expect(decl!.body.isEmpty)
}

@Test func parseClassWhereClauseConformance() {
    let statements = parseStatements("class C<T> where T: Equatable {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(decl!.whereClause?.count == 1)
}

@Test func parseEnumWhereClauseConformance() {
    let statements = parseStatements("enum E<T> where T: Equatable {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.EnumDecl
    #expect(decl != nil)
    #expect(decl!.whereClause?.count == 1)
}

@Test func parseActorWhereClauseConformance() {
    let statements = parseStatements("actor A<T> where T: Equatable {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    #expect(decl != nil)
    #expect(decl!.whereClause?.count == 1)
}

@Test func parseProtocolWhereClauseConformance() {
    let statements = parseStatements("protocol P where T: Equatable {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    #expect(decl != nil)
    #expect(decl!.whereClause?.count == 1)
}

@Test func parseStructWhereClauseMultipleRequirements() {
    let statements = parseStatements("struct S<T, U> where T: Equatable, U: Hashable {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.whereClause?.count == 2)
}

@Test func parseStructWithoutWhereClause() {
    let statements = parseStatements("struct S<T> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.whereClause == nil)
}

// MARK: - Actor Declarations (extended)

@Test func parseActorWithConformances() {
    let statements = parseStatements("actor Foo: P, Q {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    #expect(decl != nil)
    #expect(decl!.conformances.count == 2)
    let p = decl!.conformances[0] as? AST.Variable
    #expect(p != nil)
    #expect(p!.name.value == "P")
    let q = decl!.conformances[1] as? AST.Variable
    #expect(q != nil)
    #expect(q!.name.value == "Q")
}

@Test func parseActorWithGenericParameters() {
    let statements = parseStatements("actor Foo<T> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl != nil)
    #expect(decl!.genericDecl!.generics.count == 1)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
}

@Test func parseActorWithInitAndPropertyMembers() {
    let statements = parseStatements("actor Foo { var x: Int init() {} func bar() {} }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    #expect(decl != nil)
    #expect(decl!.body.count == 3)
    #expect(decl!.body[0] is AST.VariableDecl)
    #expect(decl!.body[1] is AST.InitDecl)
    #expect(decl!.body[2] is AST.FunctionDecl)
}

@Test func parseActorMissingNameReportsError() throws {
    let (_, errors) = parseWithDiagnostics("actor")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected actor name after 'actor'"))
}

@Test func parseActorNonIdentifierNameReportsError() throws {
    let (_, errors) = parseWithDiagnostics("actor 123 {}")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected identifier after 'actor', but got '123'"))
}

@Test func parseActorMissingOpenBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("actor Foo")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '{' in actor type"))
}

@Test func parseActorNonBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("actor Foo 123")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '{' in actor type, but got '123'"))
}

// MARK: - Generic Function / Init / Subscript Declarations

@Test func parseGenericFunctionDecl() {
    let statements = parseStatements("func foo<T>(x: T) -> T { x }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let genericDecl = decl!.genericDecl
    #expect(genericDecl != nil)
    #expect(genericDecl!.generics.count == 1)
    #expect(genericDecl!.generics[0].name.value == "T")
    #expect(genericDecl!.generics[0].eachToken == nil)
    #expect(decl!.parameters.count == 1)
    #expect(decl!.returnTypeExpression != nil)
}

@Test func parseGenericFunctionDeclWithConstraint() {
    let statements = parseStatements("func foo<T: Equatable>(x: T) -> T { x }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let genericDecl = decl!.genericDecl
    #expect(genericDecl != nil)
    #expect(genericDecl!.generics.count == 1)
    let constraint = genericDecl!.generics[0].constraint
    #expect(constraint != nil)
}

@Test func parseGenericFunctionDeclMultipleParams() {
    let statements = parseStatements("func swap<T, U>(_ a: T, _ b: U) {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl?.generics.count == 2)
    #expect(decl!.genericDecl!.generics[1].name.value == "U")
}

@Test func parseNonGenericFunctionHasNoGenericDecl() {
    let statements = parseStatements("func foo() {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl == nil)
}

@Test func parseGenericInitDecl() {
    let statements = parseStatements("struct S { init<T>(x: T) {} }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.genericDecl != nil)
    #expect(initDecl!.genericDecl!.generics.count == 1)
    #expect(initDecl!.genericDecl!.generics[0].name.value == "T")
}

@Test func parseGenericSubscriptDecl() {
    let statements = parseStatements("struct S { subscript<T>(i: T) -> T { i } }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    #expect(subDecl != nil)
    #expect(subDecl!.genericDecl != nil)
    #expect(subDecl!.genericDecl!.generics.count == 1)
    #expect(subDecl!.genericDecl!.generics[0].name.value == "T")
    #expect(subDecl!.parameters.count == 1)
}

// MARK: - Subscript Declarations (extended)

@Test func parseSubscriptDeclBasic() {
    let statements = parseStatements("struct S { subscript(i: Int) -> Int { i } }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    #expect(subDecl != nil)
    #expect(subDecl!.token.kind == .Keyword(.Subscript))
    #expect(subDecl!.parameters.count == 1)
    #expect(subDecl!.throwsClause == nil)
    let returnType = subDecl!.returnType as? AST.Variable
    #expect(returnType != nil)
    #expect(returnType!.name.value == "Int")
    #expect(subDecl!.body.count == 1)
}

@Test func parseSubscriptDeclNoParameters() {
    let statements = parseStatements("struct S { subscript -> Int { 0 } }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    #expect(subDecl != nil)
    #expect(subDecl!.parameters.isEmpty)
}

@Test func parseSubscriptDeclWithGetSetBody() {
    let statements = parseStatements(
        "struct S { subscript(i: Int) -> Int { get { i } set { _ = newValue } } }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    #expect(subDecl != nil)
    #expect(subDecl!.body.count == 2)
}

@Test func parseSubscriptDeclMultipleParameters() {
    let statements = parseStatements("struct S { subscript(row: Int, col: Int) -> Int { 0 } }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    #expect(subDecl != nil)
    #expect(subDecl!.parameters.count == 2)
    #expect(subDecl!.parameters[0].label?.value == "row")
    #expect(subDecl!.parameters[1].label?.value == "col")
}

@Test func parseSubscriptDeclMissingArrowReportsError() throws {
    let (_, errors) = parseWithDiagnostics("struct S { subscript(i: Int) Int { 0 } }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected '->' after subscript parameters") })
}

@Test func parseSubscriptDeclMissingCloseParenReportsError() throws {
    let (_, errors) = parseWithDiagnostics("struct S { subscript(i: Int -> Int { 0 } }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected ')' after subscript parameters") })
}

// MARK: - Goto (extended)

@Test func parseGotoNonIdentifierReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { goto 123 }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected identifier after 'goto', but got '123'"))
}

@Test func parseGotoMissingLabelReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { goto }")
    try #require(errors.count >= 1)
    #expect(errors[0].message.contains("expected identifier after 'goto'"))
}

// MARK: - For Case

@Test func parseForCasePattern() {
    let body = parseBlockStatements("func main() { for case .foo(x) in arr {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    let call = forStmt!.pattern as? AST.Call
    #expect(call != nil)
    let callee = call!.callee as? AST.ImplicitMemberAccess
    #expect(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(call!.arguments.count == 1)
    let arg = call!.arguments[0].value as? AST.Variable
    #expect(arg != nil)
    #expect(arg!.name.value == "x")
    let sequence = forStmt!.sequence as? AST.Variable
    #expect(sequence != nil)
    #expect(sequence!.name.value == "arr")
}

@Test func parseForCasePatternWithLetBinding() {
    let body = parseBlockStatements("func main() { for case .foo(let x) in arr {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    let call = forStmt!.pattern as? AST.Call
    #expect(call != nil)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Let))
    #expect(binding!.name.value == "x")
}

@Test func parseForCaseWithLetBinding() {
    let body = parseBlockStatements("func main() { for case let y in arr {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    let binding = forStmt!.pattern as? AST.BindingPattern
    #expect(binding != nil)
    #expect(binding!.name.value == "y")
}

@Test func parseForCaseWildcard() {
    let body = parseBlockStatements("func main() { for case _ in arr {} }")
    #expect(body.count == 1)
    let forStmt = body[0] as? AST.For
    #expect(forStmt != nil)
    let wildcard = forStmt!.pattern as? AST.WildcardPattern
    #expect(wildcard != nil)
}

@Test func parseForMissingInReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { for x {} }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected 'in' after for pattern"))
}

@Test func parseForMissingSequenceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { for x in }")
    try #require(errors.count >= 1)
    #expect(errors[0].message.contains("expected '{' after for-in sequence"))
}

@Test func parseForMissingOpenBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { for x in arr }")
    try #require(errors.count >= 1)
    #expect(errors[0].message.contains("expected '{' after for-in sequence"))
}

// MARK: - Failable Init

@Test func parseFailableInit() {
    let statements = parseStatements("struct S { init?() {} }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.optionalToken != nil)
    #expect(initDecl!.optionalToken!.kind == .Operator(.QuestionMark))
}

@Test func parseFailableInitWithParameters() {
    let statements = parseStatements("struct S { init?(x: Int) {} }")
    #expect(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(initDecl!.optionalToken != nil)
    #expect(initDecl!.parameters.count == 1)
}

// MARK: - Operator Function Declarations

@Test func parseOperatorFunctionDeclaration() {
    let statements = parseStatements("func +(a: Int32, b: Int32) -> Int32 { a }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    if case .Operator = decl!.name.kind {
    } else {
        Issue.record("expected operator name")
    }
    #expect(decl!.name.value == "+")
    #expect(decl!.parameters.count == 2)
}

@Test func parsePrefixOperatorFunctionDeclaration() {
    let statements = parseStatements("func -(_ a: Int32) -> Int32 { a }")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    if case .Operator = decl!.name.kind {
    } else {
        Issue.record("expected operator name")
    }
    #expect(decl!.name.value == "-")
    #expect(decl!.parameters.count == 1)
}

// MARK: - Generic Declarations (extended)

@Test func parseClassWithGenericParameters() {
    let statements = parseStatements("class Foo<T> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl != nil)
    #expect(decl!.genericDecl!.generics.count == 1)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
}

@Test func parseProtocolWithGenericParameters() {
    let statements = parseStatements("protocol Foo<T> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl != nil)
    #expect(decl!.genericDecl!.generics.count == 1)
}

@Test func parseGenericEachMissingNameReportsError() throws {
    let (_, errors) = parseWithDiagnostics("struct S<each> {}")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected identifier after 'each'") })
}

@Test func parseGenericMissingCloseAngleReportsError() throws {
    let (_, errors) = parseWithDiagnostics("struct S<T")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected '>' after generic parameters") })
}

@Test func parseGenericInvalidParameterReportsError() throws {
    let (_, errors) = parseWithDiagnostics("struct S<123> {}")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected generic parameter name"))
}

// MARK: - Closure Expressions (extended)

@Test func parseEmptyClosure() {
    let body = parseBlockStatements("func main() { let f = {} }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    let closure = vd!.initializer as? AST.Closure
    #expect(closure != nil)
    #expect(closure!.signature == nil)
    #expect(closure!.body.isEmpty)
}

@Test func parseClosureSingleUnannotatedParameterHasNoSignature() {
    let body = parseBlockStatements("func main() { { x in x } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    #expect(closure!.signature == nil)
    #expect(closure!.body.count == 3)
}

@Test func parseClosureWithCaptureListCombined() {
    let body = parseBlockStatements("func main() { { [weak a, unowned b] in a } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    let captureList = closure!.signature!.captureList
    #expect(captureList.count == 2)
    #expect(captureList[0].specifier?.value == "weak")
    #expect(captureList[0].name.value == "a")
    #expect(captureList[1].specifier?.value == "unowned")
    #expect(captureList[1].name.value == "b")
}

@Test func parseClosureCaptureUnownedSelf() {
    let body = parseBlockStatements("func main() { { [unowned self] in self } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    let captureList = closure!.signature!.captureList
    #expect(captureList.count == 1)
    #expect(captureList[0].specifier?.value == "unowned")
    #expect(captureList[0].name.value == "self")
}

@Test func parseClosureFullSignature() {
    let body = parseBlockStatements(
        "func main() { { [weak self] (x: Int32) throws -> Int32 in x } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    #expect(closure != nil)
    let signature = closure!.signature
    #expect(signature != nil)
    #expect(signature!.captureList.count == 1)
    #expect(signature!.parameters.count == 1)
    #expect(signature!.throwsClause != nil)
    #expect(signature!.returnType != nil)
}

@Test func parseClosureAsRegularArgument() {
    let expr = firstExpression("foo({ 42 })")
    let call = expr as? AST.Call
    #expect(call != nil)
    #expect(call!.arguments.count == 1)
    let closure = call!.arguments[0].value as? AST.Closure
    #expect(closure != nil)
}

@Test func parseNestedClosure() {
    let body = parseBlockStatements("func main() { { { 1 } } }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let outer = exprStmt!.expression as? AST.Closure
    #expect(outer != nil)
    #expect(outer!.body.count == 1)
    let innerStmt = outer!.body[0] as? AST.ExpressionStatement
    let inner = innerStmt!.expression as? AST.Closure
    #expect(inner != nil)
}

@Test func parseClosureMissingInReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { { (x: Int32) 42 } }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected 'in' after closure signature"))
}

@Test func parseCaptureListMissingIdentifierReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { { [weak] in 1 } }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected identifier in capture list"))
}

@Test func parseCaptureListMissingCloseBracketReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { { [weak a in 1 } }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected ']' after capture list"))
}

// MARK: - Closure Types (extended)

@Test func parseClosureTypeInVariableAnnotation() {
    let body = parseBlockStatements("func main() { let f: (Int32) -> Int32 = g }")
    #expect(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    #expect(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    #expect(closureType != nil)
    let returnType = closureType!.returnType as? AST.Variable
    #expect(returnType != nil)
    #expect(returnType!.name.value == "Int32")
}

@Test func parseClosureTypeInFunctionReturnType() {
    let statements = parseStatements("func make() -> (Int32) -> Int32")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    let closureType = decl!.returnTypeExpression as? AST.ClosureType
    #expect(closureType != nil)
}

@Test func parseClosureTypeInParameter() {
    let statements = parseStatements("func apply(f: (Int32) -> Int32) {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.parameters.count == 1)
    let closureType = decl!.parameters[0].type as? AST.ClosureType
    #expect(closureType != nil)
}

// MARK: - String Interpolation (error paths)

@Test func parseStringInterpolationComplexExpression() {
    let expr = firstExpression("\"result: \\(1 + 2)\"")
    let interp = expr as? AST.StringInterpolation
    #expect(interp != nil)
    #expect(interp!.segments.count == 3)
    guard case .expression(let e) = interp!.segments[1] else {
        Issue.record("expected expression segment")
        return
    }
    let seq = e as? AST.SequentialExpression
    #expect(seq != nil)
    #expect(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
}

@Test func parseStringInterpolationNestedCurrentlyUnsupported() throws {
    let (_, errors) = parseWithDiagnostics("func main() { let s = \"\\(foo(\\(bar)))\" }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected ')' after interpolation expression") })
}

@Test func parseStringInterpolationMissingCloseParenReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { let s = \"\\(x\" }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected ')' after interpolation expression") })
}

@Test func parseStringEscapeWithoutInterpolationIsPlainLiteral() {
    let (_, errors) = parseWithDiagnostics("func main() { let s = \"\\x\" }")
    #expect(errors.isEmpty)
    let expr = firstExpression("\"\\x\"")
    let lit = expr as? AST.StringLiteral
    #expect(lit != nil)
}

// MARK: - Modifiers (extended)

@Test func parseIsolatedModifierOnFunction() {
    let statements = parseStatements("isolated func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Isolated))
}

@Test func parseIsolatedModifierCombined() {
    let statements = parseStatements("isolated public func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(decl!.modifiers.count == 2)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Isolated))
    #expect(modifierKind(decl!.modifiers[1].kind, equals: .Public(setter: false)))
}

@Test func parseIsolatedModifierOnVar() {
    let statements = parseStatements("isolated var x: Int32")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Isolated))
}

@Test func parseNonmutatingModifierOnFunction() {
    let statements = parseStatements("nonmutating func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Nonmutating))
}

@Test func parseConvenienceModifierOnInit() {
    let statements = parseStatements("struct S { convenience init() {} }")
    let structDecl = statements[0] as? AST.StructDecl
    #expect(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    #expect(initDecl != nil)
    #expect(modifierKind(initDecl!.modifiers[0].kind, equals: .Convenience))
}

@Test func parseWeakModifierOnVariable() {
    let statements = parseStatements("weak var ref: AnyObject")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Weak))
}

@Test func parseUnownedModifierOnVariable() {
    let statements = parseStatements("unowned var ref: AnyObject")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Unowned))
}

@Test func parseAbstractModifierOnClass() {
    let statements = parseStatements("abstract class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Abstract))
}

@Test func parseOpenSetModifierOnVariable() {
    let statements = parseStatements("open(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Open(setter: true)))
}

@Test func parseInternalSetModifierOnVariable() {
    let statements = parseStatements("internal(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Internal(setter: true)))
}

@Test func parseFilePrivateSetModifierOnVariable() {
    let statements = parseStatements("fileprivate(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .FilePrivate(setter: true)))
}

@Test func parsePackagePrivateSetModifierOnVariable() {
    let statements = parseStatements("packageprivate(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .PackagePrivate(setter: true)))
}

@Test func parseProtectedModifierOnClass() {
    let statements = parseStatements("protected class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    #expect(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Protected(setter: false)))
}

// MARK: - Attributes (error paths)

@Test func parseAttributeMissingCloseBracketReportsError() throws {
    let (_, errors) = parseWithDiagnostics("#[foo struct Foo {}")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '(' or ']' after attribute name"))
}

// MARK: - Function Parameter (error paths)

@Test func parseParameterMissingColonReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func foo(a Int) {}")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected ':' after parameter name"))
}

@Test func parseParameterNonIdentifierReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func foo(123: Int) {}")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected identifier in parameter") })
}

// MARK: - Repeat-While (error paths)

@Test func parseRepeatWhileMissingWhileReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { repeat {} 123 }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected 'while' after '}'"))
}

@Test func parseRepeatWhileMissingOpenBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { repeat 123 }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '{' after 'repeat'"))
}

@Test func parseRepeatWhileMissingCloseBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { repeat { while true }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected '}' after repeat body") })
}

// MARK: - Optional Binding (error paths)

@Test func parseOptionalBindingMissingEqualReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { if let x {} }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '=' in optional binding"))
}

@Test func parseOptionalBindingMissingNameReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { if let {} }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected identifier after 'let'") })
}

// MARK: - Case Match (error paths)

@Test func parseCaseMatchMissingEqualReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { if case .foo {} }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected '=' after case pattern") })
}

// MARK: - Match Case (error paths)

@Test func parseMatchMissingOpenBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { match x }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected '{' after match subject") })
}

@Test func parseMatchCaseMissingArrowReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { match x { 1 } }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected '=>' after match case pattern") })
}

// MARK: - Call / Subscript (error paths)

@Test func parseCallMissingCloseParenReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { foo(1 }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected ')' after call arguments") })
}

@Test func parseSubscriptMissingCloseBracketReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { arr[1 }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected ']' after subscript arguments") })
}

// MARK: - Collection Literal (error paths)

@Test func parseArrayLiteralMissingCloseBracketReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { [1, 2 }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected ']' after array literal") })
}

@Test func parseDictionaryLiteralMissingColonReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { [1: 2, 3 4] }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected ':' in dictionary entry") })
}

// MARK: - SourceRange (extended)

@Test func sourceRangeIfExpression() {
    let expr = firstExpression("if x { y }")
    let range = expr.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 24)
}

@Test func sourceRangeDoCatchExpression() {
    let expr = firstExpression("do { x } catch { y }")
    let range = expr.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 34)
}

@Test func sourceRangeMatchExpression() {
    let expr = firstExpression("match x { 1 -> 2 }")
    let range = expr.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 32)
}

@Test func sourceRangeClosure() {
    let body = parseBlockStatements("func main() { let f = { 42 } }")
    let vd = body[0] as! AST.VariableDecl
    let range = vd.initializer!.sourceRange
    #expect(range.start.offset == 22)
    #expect(range.end.offset == 28)
}

@Test func sourceRangeStringInterpolation() {
    let body = parseBlockStatements("func main() { let s = \"hi \\(x)\" }")
    let vd = body[0] as! AST.VariableDecl
    let range = vd.initializer!.sourceRange
    #expect(range.start.offset == 22)
    #expect(range.end.offset == 31)
}

@Test func sourceRangeSubscriptExpression() {
    let expr = firstExpression("arr[0]")
    let range = expr.sourceRange
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 20)
}

@Test func sourceRangeGenericDecl() {
    let statements = parseStatements("struct S<T> {}")
    let structDecl = statements[0] as! AST.StructDecl
    let range = structDecl.genericDecl!.sourceRange
    #expect(range.start.offset == 8)
    #expect(range.end.offset == 11)
}

@Test func sourceRangeThrowsClause() {
    let statements = parseStatements("func f() throws -> Int32")
    let decl = statements[0] as! AST.FunctionDecl
    let range = decl.throwsClause!.sourceRange
    #expect(range.start.offset == 9)
    #expect(range.end.offset == 15)
}

@Test func sourceRangeEnumCaseDecl() {
    let statements = parseStatements("enum E { case a, b(Int32) }")
    let enumDecl = statements[0] as! AST.EnumDecl
    let caseDecl = enumDecl.body[0] as! AST.EnumCaseDecl
    let range = caseDecl.sourceRange
    #expect(range.start.offset == 9)
    #expect(range.end.offset == 25)
}

@Test func sourceRangeAccessor() {
    let statements = parseStatements("struct S { var x: Int { get { x } set { _ = newValue } } }")
    let structDecl = statements[0] as! AST.StructDecl
    let vd = structDecl.body[0] as! AST.VariableDecl
    let range = vd.accessors[0].sourceRange
    #expect(range.start.offset == 24)
    #expect(range.end.offset == 33)
}

@Test func sourceRangeSubscriptDecl() {
    let statements = parseStatements("struct S { subscript(i: Int) -> Int { 0 } }")
    let structDecl = statements[0] as! AST.StructDecl
    let subDecl = structDecl.body[0] as! AST.SubscriptDecl
    let range = subDecl.sourceRange
    #expect(range.start.offset == 11)
    #expect(range.end.offset == 41)
}
