import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSyntax

func parseWithDiagnostics(_ source: String) -> (AST.Program, [Diagnostic]) {
    let context = Context()
    let src = Source(id: Id.SourceId(0), filepath: "<test>", content: source)
    context.register(source: src)
    let stream = CharStream(content: source, id: Id.SourceId(0))
    let lexer = Lexer(input: stream)
    let tokens = lexer.parse().tokens
    let result = LexerResult(id: Id.SourceId(0), tokens: tokens)
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
    if case let .Block(stmts) = funcDecl.body {
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
    case let (.Open(a), .Open(b)): a == b
    case let (.Public(a), .Public(b)): a == b
    case let (.Protected(a), .Protected(b)): a == b
    case let (.PackagePrivate(a), .PackagePrivate(b)): a == b
    case let (.Internal(a), .Internal(b)): a == b
    case let (.FilePrivate(a), .FilePrivate(b)): a == b
    case let (.Private(a), .Private(b)): a == b
    case (.Abstract, .Abstract), (.Final, .Final), (.Mutating, .Mutating),
         (.Nonmutating, .Nonmutating), (.Convenience, .Convenience),
         (.Override, .Override), (.Lazy, .Lazy), (.Weak, .Weak),
         (.Unowned, .Unowned), (.Indirect, .Indirect), (.Isolated, .Isolated):
        true
    default: false
    }
}

@Test func parseProgramIdPropagation() {
    let program = parse("let x")
    #expect(program.id.id == 0)
    #expect(program.statements.count == 1)
}

@Test func parseSingleEmptyStatement() throws {
    let statements = parseStatements(";")
    try #require(statements.count == 1)
    #expect(statements[0] is AST.EmptyStatement)
}

@Test func parseMultipleEmptyStatements() throws {
    let statements = parseStatements(";;;")
    try #require(statements.count == 3)
    #expect(statements[0] is AST.EmptyStatement)
    #expect(statements[1] is AST.EmptyStatement)
    #expect(statements[2] is AST.EmptyStatement)
}

@Test func parseEmptyStatementInBlock() throws {
    let body = parseBlockStatements("func main() { ; }")
    try #require(body.count == 1)
    #expect(body[0] is AST.EmptyStatement)
}

@Test func parseLetWithoutInitializer() throws {
    let statements = parseStatements("let x")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Let))
    #expect(decl!.name.kind == .Identifier)
    #expect(decl!.name.value == "x")
    #expect(decl!.typeExpression == nil)
    #expect(decl!.initializer == nil)
}

@Test func parseVarWithoutInitializer() throws {
    let statements = parseStatements("var y")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Var))
    #expect(decl!.name.value == "y")
    #expect(decl!.typeExpression == nil)
    #expect(decl!.initializer == nil)
}

@Test func parseLetWithInitializer() throws {
    let statements = parseStatements("let x = 42")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(decl!.name.value == "x")
    #expect(decl!.typeExpression == nil)
    #expect(decl!.initializer != nil)
    let intLit = decl!.initializer as? AST.IntegerLiteral
    try #require(intLit != nil)
    #expect(intLit!.value == 42)
}

@Test func parseLetWithTypeAnnotation() throws {
    let statements = parseStatements("let x: Int")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(decl!.name.value == "x")
    #expect(decl!.typeExpression != nil)
    #expect(decl!.initializer == nil)
    let typeVar = decl!.typeExpression as? AST.Variable
    try #require(typeVar != nil)
    #expect(typeVar!.name.value == "Int")
}

@Test func parseVarWithInitializer() throws {
    let statements = parseStatements("var flag = true")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(decl!.name.value == "flag")
    let boolLit = decl?.initializer as? AST.BoolLiteral
    try #require(boolLit != nil)
    #expect(boolLit!.value == true)
}

@Test func parseFunctionEmptyBlock() throws {
    let statements = parseStatements("func main() {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Func))
    #expect(decl!.name.kind == .Identifier)
    #expect(decl!.name.value == "main")
    #expect(decl!.returnTypeExpression == nil)
    if case let .Block(body) = decl!.body {
        #expect(body.isEmpty)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseFunctionExpressionBody() throws {
    let statements = parseStatements("func foo() = 42")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.returnTypeExpression == nil)
    if case let .Expression(expr) = decl!.body {
        let intLit = expr as? AST.IntegerLiteral
        try #require(intLit != nil)
        #expect(intLit!.value == 42)
    } else {
        Issue.record("expected expression body")
    }
}

@Test func parseFunctionWithBlockStatements() throws {
    let body = parseBlockStatements("func main() { let x }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseFunctionWithMultipleBlockStatements() throws {
    let body = parseBlockStatements("func main() { let x let y }")
    try #require(body.count == 2)
    let vd1 = body[0] as? AST.VariableDecl
    try #require(vd1 != nil)
    #expect(vd1!.name.value == "x")
    let vd2 = body[1] as? AST.VariableDecl
    try #require(vd2 != nil)
    #expect(vd2!.name.value == "y")
}

@Test func parseNestedFunctionDecl() throws {
    let body = parseBlockStatements("func main() { func inner() {} }")
    try #require(body.count == 1)
    let inner = body[0] as? AST.FunctionDecl
    try #require(inner != nil)
    #expect(inner!.name.value == "inner")
    if case let .Block(innerBody) = inner!.body {
        #expect(innerBody.isEmpty)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseExpressionStatementWithIdentifier() throws {
    let expr = firstExpression("x")
    let varExpr = expr as? AST.Variable
    try #require(varExpr != nil)
    #expect(varExpr!.name.value == "x")
}

@Test func parseIntegerLiteralExpression() throws {
    let expr = firstExpression("42")
    let lit = expr as? AST.IntegerLiteral
    try #require(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseFloatLiteralExpression() throws {
    let expr = firstExpression("3.14")
    let lit = expr as? AST.FloatLiteral
    try #require(lit != nil)
    #expect(lit!.value == 3.14)
}

@Test func parseStringLiteralExpression() throws {
    let expr = firstExpression("\"hello\"")
    let lit = expr as? AST.StringLiteral
    try #require(lit != nil)
    #expect(lit!.token.value == "hello")
}

@Test func parseCharLiteralExpression() throws {
    let expr = firstExpression("'a'")
    let lit = expr as? AST.CharLiteral
    try #require(lit != nil)
    #expect(lit!.value == "a")
}

@Test func parseBooleanTrueLiteralExpression() throws {
    let expr = firstExpression("true")
    let lit = expr as? AST.BoolLiteral
    try #require(lit != nil)
    #expect(lit!.value == true)
}

@Test func parseBooleanFalseLiteralExpression() throws {
    let expr = firstExpression("false")
    let lit = expr as? AST.BoolLiteral
    try #require(lit != nil)
    #expect(lit!.value == false)
}

@Test func parseNullLiteralExpression() {
    let expr = firstExpression("null")
    let lit = expr as? AST.NullLiteral
    #expect(lit != nil)
}

@Test func parseFunctionCallNoArgs() throws {
    let expr = firstExpression("foo()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.Variable
    try #require(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(call!.arguments.isEmpty)
}

@Test func parseMemberAccess() throws {
    let expr = firstExpression("a.b")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    let obj = member!.object as? AST.Variable
    try #require(obj != nil)
    #expect(obj!.name.value == "a")
    #expect(member!.member.value == "b")
    #expect(member!.token.kind == .Operator(.Dot))
}

@Test func parseChainedMemberAccess() throws {
    let expr = firstExpression("a.b.c")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "c")
    let innerMember = member!.object as? AST.MemberAccess
    try #require(innerMember != nil)
    #expect(innerMember!.member.value == "b")
    let obj = innerMember!.object as? AST.Variable
    try #require(obj != nil)
    #expect(obj!.name.value == "a")
    #expect(member!.isOptional == false)
}

@Test func parseOptionalChaining() throws {
    let expr = firstExpression("a?.b")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.isOptional == true)
    #expect(member!.token.kind == .Operator(.QuestionMarkDot))
    #expect(member!.member.value == "b")
}

@Test func parseChainedOptionalChaining() throws {
    let expr = firstExpression("a?.b?.c")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.isOptional == true)
    #expect(member!.member.value == "c")
    let inner = member!.object as? AST.MemberAccess
    try #require(inner != nil)
    #expect(inner!.isOptional == true)
    #expect(inner!.member.value == "b")
}

@Test func parseMixedOptionalAndRegular() throws {
    let expr = firstExpression("a.b?.c")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.isOptional == true)
    let inner = member!.object as? AST.MemberAccess
    try #require(inner != nil)
    #expect(inner!.isOptional == false)
}

@Test func parseCastAsExpression() {
    let expr = firstExpression("x as Int32")
    let cast = expr as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .As)
    #expect(cast!.token.kind == .Keyword(.As))
    let left = cast!.left as? AST.Variable
    #expect(left!.name.value == "x")
    let right = cast!.right as? AST.Variable
    #expect(right!.name.value == "Int32")
}

@Test func parseCastOptionalAsExpression() {
    let expr = firstExpression("x as? Int32")
    let cast = expr as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .OptionalAs)
}

@Test func parseCastAsExclamationExpression() {
    let expr = firstExpression("x as! Int32")
    let cast = expr as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .AsExclamation)
}

@Test func parseIsExpression() {
    let expr = firstExpression("x is Int32")
    let cast = expr as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .Is)
    #expect(cast!.token.kind == .Keyword(.Is))
}

@Test func parseCastChain() throws {
    let expr = firstExpression("a as B as? C")
    let cast = expr as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .OptionalAs)
    let inner = cast!.left as? AST.Cast
    try #require(inner != nil)
    #expect(inner!.kind == .As)
    #expect(cast!.right is AST.Variable)
}

@Test func parseCallOnMemberAccess() throws {
    let expr = firstExpression("a.b()")
    let call = expr as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.isEmpty)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.value == "b")
    let obj = callee!.object as? AST.Variable
    try #require(obj != nil)
    #expect(obj!.name.value == "a")
}

@Test func parseInitMemberCall() throws {
    let expr = firstExpression("Foo.init()")
    let call = expr as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.isEmpty)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.kind == .Keyword(.Init))
    #expect(callee!.member.value == "init")
    let obj = callee!.object as? AST.Variable
    try #require(obj != nil)
    #expect(obj!.name.value == "Foo")
}

@Test func parseInitMemberCallWithArguments() throws {
    let expr = firstExpression("Foo.init(x: 1, y: 2)")
    let call = expr as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.count == 2)
    #expect(call!.arguments[0].label?.value == "x")
    #expect(call!.arguments[1].label?.value == "y")
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.value == "init")
}

@Test func parseSelfInitDelegation() throws {
    let expr = firstExpression("self.init(capacity: count)")
    let call = expr as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.count == 1)
    #expect(call!.arguments[0].label?.value == "capacity")
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.kind == .Keyword(.Init))
    let obj = callee!.object as? AST.SelfExpression
    #expect(obj != nil)
}

@Test func parseSuperInitCall() throws {
    let expr = firstExpression("super.init()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.value == "init")
    let obj = callee!.object as? AST.SuperExpression
    #expect(obj != nil)
}

@Test func parseDeinitMemberCallOnSubscript() throws {
    let expr = firstExpression("data[i].deinit()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.kind == .Keyword(.Deinit))
    #expect(callee!.member.value == "deinit")
    let sub = callee!.object as? AST.Subscript
    try #require(sub != nil)
    #expect(sub!.arguments.count == 1)
}

@Test func parseDeinitMemberCallOnParens() throws {
    let expr = firstExpression("(*value).deinit()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.value == "deinit")
    let paren = callee!.object as? AST.Parenthetical
    try #require(paren != nil)
}

@Test func parseInitMemberCallAfterGeneric() throws {
    let expr = firstExpression("Foo<Int32>.init()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.kind == .Keyword(.Init))
    let seq = callee!.object as? AST.Sequential
    try #require(seq != nil)
    #expect(seq!.ops.count == 2)
}

@Test func parseBareInitMemberReference() throws {
    let expr = firstExpression("Foo.init")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.kind == .Keyword(.Init))
    #expect(member!.member.value == "init")
}

@Test func parseBareDeinitMemberReference() throws {
    let expr = firstExpression("foo.deinit")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.kind == .Keyword(.Deinit))
    #expect(member!.member.value == "deinit")
}

@Test func parseKeywordMemberName() throws {
    let expr = firstExpression("foo.return")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.kind == .Keyword(.Return))
    #expect(member!.member.value == "return")
}

@Test func parseKeywordMemberNameIf() throws {
    let expr = firstExpression("foo.if")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.kind == .Keyword(.If))
    #expect(member!.member.value == "if")
}

@Test func parseDeinitCallWithArgumentsAllowed() throws {
    let expr = firstExpression("foo.deinit(1)")
    let call = expr as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.count == 1)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.member.value == "deinit")
}

@Test func parseInitMemberOptionalChain() throws {
    let expr = firstExpression("foo?.init()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.MemberAccess
    try #require(callee != nil)
    #expect(callee!.isOptional == true)
    #expect(callee!.token.kind == .Operator(.QuestionMarkDot))
    #expect(callee!.member.value == "init")
}

@Test func parseStringLiteralMemberReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { foo.\"str\" }")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected identifier or keyword or integer literal after") })
}

@Test func parseMemberAtEofReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { foo.")
    try #require(errors.count >= 1)
    #expect(errors.contains { $0.message.contains("expected member name after '.'") })
}

@Test func parseCallOnCall() throws {
    let expr = firstExpression("foo()()")
    let outer = expr as? AST.Call
    try #require(outer != nil)
    let inner = outer!.callee as? AST.Call
    try #require(inner != nil)
    let base = inner!.callee as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "foo")
}

@Test func parseInfixExpression() throws {
    let expr = firstExpression("a + b")
    let sequentialExpression = expr as? AST.Sequential
    try #require(sequentialExpression != nil)
    try #require(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
    try #require(sequentialExpression!.operands.count == 2)
    let left = sequentialExpression!.operands[0] as? AST.Variable
    try #require(left != nil)
    #expect(left!.name.value == "a")
    let right = sequentialExpression!.operands[1] as? AST.Variable
    try #require(right != nil)
    #expect(right!.name.value == "b")
}

@Test func parseComplexInfixExpression() throws {
    let expr = firstExpression("a + b * c - d")
    let sequentialExpression = expr as? AST.Sequential
    try #require(sequentialExpression != nil)
    try #require(sequentialExpression!.ops.count == 3)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
    #expect(sequentialExpression!.ops[1].kind == .Operator(.Multiply))
    #expect(sequentialExpression!.ops[2].kind == .Operator(.Minus))
    try #require(sequentialExpression!.operands.count == 4)
    let names = ["a", "b", "c", "d"]
    for i in 0 ..< 4 {
        let v = sequentialExpression!.operands[i] as? AST.Variable
        try #require(v != nil)
        #expect(v!.name.value == names[i])
    }
}

@Test func parseAssignmentExpression() throws {
    let expr = firstExpression("x = 42")
    let sequentialExpression = expr as? AST.Sequential
    try #require(sequentialExpression != nil)
    try #require(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Assign))
    try #require(sequentialExpression!.operands.count == 2)
    let target = sequentialExpression!.operands[0] as? AST.Variable
    try #require(target != nil)
    #expect(target!.name.value == "x")
    let value = sequentialExpression!.operands[1] as? AST.IntegerLiteral
    try #require(value != nil)
    #expect(value!.value == 42)
}

@Test func parseComparisonExpression() throws {
    let expr = firstExpression("a == b")
    let sequentialExpression = expr as? AST.Sequential
    try #require(sequentialExpression != nil)
    try #require(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Equal))
    #expect(sequentialExpression!.operands.count == 2)
}

@Test func parseLogicalAndExpression() throws {
    let expr = firstExpression("a && b")
    let sequentialExpression = expr as? AST.Sequential
    try #require(sequentialExpression != nil)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.And))
}

@Test func parseLogicalOrExpression() throws {
    let expr = firstExpression("a || b")
    let sequentialExpression = expr as? AST.Sequential
    try #require(sequentialExpression != nil)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Or))
}

@Test func parseMixedDeclarations() throws {
    let statements = parseStatements("let x = 1 func foo() {}")
    try #require(statements.count == 2)
    let vd = statements[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
    let fd = statements[1] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "foo")
}

@Test func parseMultipleVariableDeclarations() throws {
    let statements = parseStatements("let a = 1 let b = 2 let c = 3")
    try #require(statements.count == 3)
    let names = ["a", "b", "c"]
    for i in 0 ..< 3 {
        let vd = statements[i] as? AST.VariableDecl
        try #require(vd != nil)
        #expect(vd!.name.value == names[i])
    }
}

@Test func parseFunctionWithEmptyStatementInBody() throws {
    let body = parseBlockStatements("func main() { ; let x }")
    try #require(body.count == 2)
    #expect(body[0] is AST.EmptyStatement)
    let vd = body[1] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseHexStringLiteral() throws {
    let expr = firstExpression("0xFF")
    let lit = expr as? AST.IntegerLiteral
    try #require(lit != nil)
    #expect(lit!.value == 255)
}

@Test func parseBinaryStringLiteral() throws {
    let expr = firstExpression("0b1010")
    let lit = expr as? AST.IntegerLiteral
    try #require(lit != nil)
    #expect(lit!.value == 10)
}

@Test func parseUnderscoredIntegerLiteral() throws {
    let expr = firstExpression("1_000_000")
    let lit = expr as? AST.IntegerLiteral
    try #require(lit != nil)
    #expect(lit!.value == 1_000_000)
}

@Test func parseScientificFloatLiteral() throws {
    let expr = firstExpression("1.5e-3")
    let lit = expr as? AST.FloatLiteral
    try #require(lit != nil)
    #expect(lit!.value == 0.0015)
}

@Test func parseReturnWithIntegerLiteral() throws {
    let body = parseBlockStatements("func main() { return 42 }")
    try #require(body.count == 1)
    let ret = body[0] as? AST.Return
    try #require(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    let lit = ret!.value as? AST.IntegerLiteral
    try #require(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseReturnWithComplexExpression() throws {
    let body = parseBlockStatements("func main() { return a + b }")
    try #require(body.count == 1)
    let ret = body[0] as? AST.Return
    try #require(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    let sequentialExpression = ret!.value as? AST.Sequential
    try #require(sequentialExpression != nil)
    try #require(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
    try #require(sequentialExpression!.operands.count == 2)
    let left = sequentialExpression!.operands[0] as? AST.Variable
    try #require(left != nil)
    #expect(left!.name.value == "a")
    let right = sequentialExpression!.operands[1] as? AST.Variable
    try #require(right != nil)
    #expect(right!.name.value == "b")
}

@Test func parseReturnWithoutValueFollowedBySemicolon() throws {
    let body = parseBlockStatements("func main() { return; }")
    try #require(body.count == 2)
    let ret = body[0] as? AST.Return
    try #require(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    #expect(ret!.value == nil)
    #expect(body[1] is AST.EmptyStatement)
}

@Test func parseReturnWithoutValueOnOwnLine() throws {
    let body = parseBlockStatements("func main() {\nreturn\n}")
    try #require(body.count == 1)
    let ret = body[0] as? AST.Return
    try #require(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    #expect(ret!.value == nil)
}

@Test func parseReturnFollowedByAnotherStatement() throws {
    let body = parseBlockStatements("func main() { return x; let y }")
    try #require(body.count == 3)
    let ret = body[0] as? AST.Return
    try #require(ret != nil)
    let varExpr = ret!.value as? AST.Variable
    try #require(varExpr != nil)
    #expect(varExpr!.name.value == "x")
    #expect(body[1] is AST.EmptyStatement)
    let vd = body[2] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "y")
}

@Test func parseThrowWithMemberAccess() throws {
    let body = parseBlockStatements("func main() { throw MyError.bad }")
    try #require(body.count == 1)
    let throwStmt = body[0] as? AST.Throw
    try #require(throwStmt != nil)
    #expect(throwStmt!.token.kind == .Keyword(.Throw))
    let memberAccess = throwStmt!.expression as? AST.MemberAccess
    try #require(memberAccess != nil)
    #expect(memberAccess!.member.value == "bad")
}

@Test func parseThrowWithVariable() throws {
    let body = parseBlockStatements("func main() { throw err }")
    try #require(body.count == 1)
    let throwStmt = body[0] as? AST.Throw
    try #require(throwStmt != nil)
    let varExpr = throwStmt!.expression as? AST.Variable
    try #require(varExpr != nil)
    #expect(varExpr!.name.value == "err")
}

@Test func parseThrowWithComplexExpression() throws {
    let body = parseBlockStatements("func main() { throw a + b }")
    try #require(body.count == 1)
    let throwStmt = body[0] as? AST.Throw
    try #require(throwStmt != nil)
    let sequentialExpression = throwStmt!.expression as? AST.Sequential
    try #require(sequentialExpression != nil)
    try #require(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
}

@Test func parseThrowInClosureBody() throws {
    let body = parseBlockStatements("func main() { let f = { throw E.x } }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closure = vd!.initializer as? AST.Closure
    try #require(closure != nil)
    let throwStmt = closure!.body[0] as? AST.Throw
    try #require(throwStmt != nil)
    #expect(throwStmt!.token.kind == .Keyword(.Throw))
}

@Test func parseThrowMissingExpressionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { throw }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected expression after 'throw'"))
}

@Test func parseTryExpression() throws {
    let expr = firstExpression("try foo()")
    let tryExpr = expr as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .Try)
    #expect(tryExpr!.token.kind == .Keyword(.Try))
    let call = tryExpr!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryQuestionExpression() throws {
    let expr = firstExpression("try? foo()")
    let tryExpr = expr as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .OptionalTry)
    let call = tryExpr!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryExclamationExpression() throws {
    let expr = firstExpression("try! foo()")
    let tryExpr = expr as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .TryExclamation)
    let call = tryExpr!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryWrapsWholeExpression() throws {
    let expr = firstExpression("try foo() + bar")
    let tryExpr = expr as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .Try)
    let sequentialExpression = tryExpr!.expression as? AST.Sequential
    try #require(sequentialExpression != nil)
    try #require(sequentialExpression!.ops.count == 1)
    #expect(sequentialExpression!.ops[0].kind == .Operator(.Plus))
}

@Test func parseTryInVariableInitializer() throws {
    let body = parseBlockStatements("func main() { let x = try? foo() }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let tryExpr = vd!.initializer as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .OptionalTry)
}

@Test func parseTryInExpressionStatementWithOperator() throws {
    let expr = firstExpression("a + try b")
    let sequentialExpression = expr as? AST.Sequential
    try #require(sequentialExpression != nil)
    let right = sequentialExpression!.operands[1] as? AST.Try
    try #require(right != nil)
    #expect(right!.kind == .Try)
    let variable = right!.expression as? AST.Variable
    try #require(variable != nil)
    #expect(variable!.name.value == "b")
}

@Test func parseTryGreedyExclamationAfterTry() throws {
    let expr = firstExpression("try !flag")
    let tryExpr = expr as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .TryExclamation)
    let variable = tryExpr!.expression as? AST.Variable
    try #require(variable != nil)
    #expect(variable!.name.value == "flag")
}

@Test func parseTryNested() throws {
    let expr = firstExpression("try try foo()")
    let outer = expr as? AST.Try
    try #require(outer != nil)
    #expect(outer!.kind == .Try)
    let inner = outer!.expression as? AST.Try
    try #require(inner != nil)
    let call = inner!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseTryMissingExpressionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { try }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected expression after 'try'"))
}

@Test func parseFunctionWithoutThrows() throws {
    let statements = parseStatements("func f() -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.throwsClause == nil)
}

@Test func parseFunctionThrowsClause() throws {
    let statements = parseStatements("func f() throws {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.throwsClause != nil)
    #expect(decl!.throwsClause!.token.kind == .Keyword(.Throws))
    #expect(decl!.throwsClause!.types == nil)
}

@Test func parseFunctionThrowsWithReturnType() throws {
    let statements = parseStatements("func f() throws -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.throwsClause != nil)
    #expect(decl!.throwsClause!.types == nil)
    let returnType = decl!.returnTypeExpression as? AST.Variable
    try #require(returnType != nil)
    #expect(returnType!.name.value == "Int")
}

@Test func parseFunctionTypedThrows() throws {
    let statements = parseStatements("func f() throws(E1) -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let throwsClause = decl!.throwsClause
    try #require(throwsClause != nil)
    try #require(throwsClause!.types?.count == 1)
    let type0 = throwsClause!.types![0] as? AST.Variable
    try #require(type0 != nil)
    #expect(type0!.name.value == "E1")
}

@Test func parseFunctionMultipleTypedThrows() throws {
    let statements = parseStatements("func f() throws(E1, E2) -> Int")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let throwsClause = decl!.throwsClause
    try #require(throwsClause != nil)
    try #require(throwsClause!.types?.count == 2)
    let type0 = throwsClause!.types![0] as? AST.Variable
    #expect(type0!.name.value == "E1")
    let type1 = throwsClause!.types![1] as? AST.Variable
    #expect(type1!.name.value == "E2")
}

@Test func parseInitThrowsClause() throws {
    let statements = parseStatements("struct S { init() throws {} }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.throwsClause != nil)
    #expect(initDecl!.throwsClause!.types == nil)
}

@Test func parseInitTypedThrows() throws {
    let statements = parseStatements("struct S { init() throws(E) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.throwsClause?.types?.count == 1)
}

@Test func parseInitWithParameters() throws {
    let statements = parseStatements("struct S { init(x: Int) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.parameters.count == 1)
    #expect(initDecl!.parameters[0].name.value == "x")
    #expect(initDecl!.parameters[0].type != nil)
}

@Test func parseInitWithLabelAndDefaultValue() throws {
    let statements = parseStatements("struct S { init(_ a: Int, b: Int = 42) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.parameters.count == 2)
    #expect(initDecl!.parameters[0].label == nil)
    #expect(initDecl!.parameters[0].name.value == "a")
    #expect(initDecl!.parameters[1].label?.value == "b")
    #expect(initDecl!.parameters[1].name.value == "b")
    #expect(initDecl!.parameters[1].defaultValue != nil)
}

@Test func parseInitWithParametersAndThrows() throws {
    let statements = parseStatements("struct S { init(x: Int) throws(E) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.parameters.count == 1)
    #expect(initDecl!.parameters[0].name.value == "x")
    try #require(initDecl!.throwsClause?.types?.count == 1)
}

@Test func parseInitWithTrailingComma() throws {
    let statements = parseStatements("struct S { init(x: Int,) {} }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    #expect(initDecl!.parameters.count == 1)
}

@Test func parseSubscriptThrowsClause() throws {
    let statements = parseStatements("struct S { subscript(i: Int) throws -> Int { i } }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    try #require(subDecl != nil)
    try #require(subDecl!.throwsClause != nil)
    #expect(subDecl!.throwsClause!.types == nil)
}

@Test func parseClosureTypeThrows() throws {
    let body = parseBlockStatements("func main() { let f: (Int) throws -> Int = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.throwsClause != nil)
    #expect(closureType!.throwsClause!.types == nil)
    #expect(closureType!.parameters.count == 1)
}

@Test func parseClosureTypeTypedThrows() throws {
    let body = parseBlockStatements("func main() { let f: (Int, String) throws(E1) -> Bool = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.throwsClause?.types?.count == 1)
    #expect(closureType!.parameters.count == 2)
}

@Test func parseClosureSignatureThrows() throws {
    let body = parseBlockStatements("func main() { { (x: Int) throws -> Int in x } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    #expect(closure!.signature?.throwsClause != nil)
    #expect(closure!.signature!.throwsClause!.types == nil)
}

@Test func parseClosureSignatureTypedThrows() throws {
    let body = parseBlockStatements("func main() { { (x: Int) throws(E1) -> Int in x } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    try #require(closure!.signature?.throwsClause?.types?.count == 1)
}

@Test func parseDoAlone() throws {
    let body = parseBlockStatements("func main() { do { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    #expect(doExpr!.token.kind == .Keyword(.Do))
    #expect(doExpr!.body.isEmpty)
    #expect(doExpr!.catches.isEmpty)
}

@Test func parseDoWithBody() throws {
    let body = parseBlockStatements("func main() { do { foo() } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    #expect(doExpr!.body.count == 1)
    #expect(doExpr!.catches.isEmpty)
}

@Test func parseDoCatchBare() throws {
    let body = parseBlockStatements("func main() { do { } catch { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    try #require(doExpr!.catches.count == 1)
    #expect(doExpr!.catches[0].pattern == nil)
    #expect(doExpr!.catches[0].whereCondition == nil)
}

@Test func parseDoCatchLetBinding() throws {
    let body = parseBlockStatements("func main() { do { } catch let e { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let binding = catchClause.pattern as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "e")
}

@Test func parseDoCatchQualifiedPattern() throws {
    let body = parseBlockStatements("func main() { do { } catch E.bad { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let memberAccess = catchClause.pattern as? AST.MemberAccess
    try #require(memberAccess != nil)
    #expect(memberAccess!.member.value == "bad")
}

@Test func parseDoCatchImplicitPattern() throws {
    let body = parseBlockStatements("func main() { do { } catch .bad { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let implicit = catchClause.pattern as? AST.ImplicitMemberAccess
    try #require(implicit != nil)
    #expect(implicit!.name.value == "bad")
}

@Test func parseDoCatchWildcard() throws {
    let body = parseBlockStatements("func main() { do { } catch _ { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    #expect(catchClause.pattern is AST.WildcardPattern)
}

@Test func parseDoCatchWhereOnly() throws {
    let body = parseBlockStatements("func main() { do { } catch where cond { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    #expect(catchClause.pattern == nil)
    #expect(catchClause.whereToken != nil)
    #expect(catchClause.whereCondition != nil)
}

@Test func parseDoCatchPatternWithWhere() throws {
    let body = parseBlockStatements("func main() { do { } catch let e where cond { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    let catchClause = doExpr!.catches[0]
    let binding = catchClause.pattern as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "e")
    #expect(catchClause.whereCondition != nil)
}

@Test func parseDoMultipleCatches() throws {
    let body = parseBlockStatements("func main() { do { } catch A { } catch B { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    #expect(doExpr!.catches.count == 2)
}

@Test func parseDoAsExpressionValue() throws {
    let body = parseBlockStatements("func main() { let x = do { 1 } }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let doExpr = vd!.initializer as? AST.Do
    try #require(doExpr != nil)
    #expect(doExpr!.body.count == 1)
}

@Test func parseDoMissingOpenBraceReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { do }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '{' after 'do'"))
}

@Test func parseDoFinallyAlone() throws {
    let body = parseBlockStatements("func main() { do { } finally { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    #expect(doExpr!.catches.isEmpty)
    try #require(doExpr!.finallyBody != nil)
    #expect(doExpr!.finallyBody!.isEmpty)
}

@Test func parseDoCatchFinally() throws {
    let body = parseBlockStatements("func main() { do { } catch { } finally { cleanup() } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    #expect(doExpr!.catches.count == 1)
    try #require(doExpr!.finallyBody?.count == 1)
}

@Test func parseDoCatchLetFinally() throws {
    let body = parseBlockStatements("func main() { do { } catch let e { } finally { log(e) } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    try #require(doExpr!.catches.count == 1)
    let binding = doExpr!.catches[0].pattern as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "e")
    #expect(doExpr!.finallyBody != nil)
}

@Test func parseDoWithoutFinally() throws {
    let body = parseBlockStatements("func main() { do { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    #expect(doExpr!.finallyBody == nil)
}

@Test func parseEmptyModule() throws {
    let statements = parseStatements("module Foo {}")
    try #require(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    try #require(module != nil)
    #expect(module!.token.kind == .Keyword(.Module))
    #expect(module!.name.kind == .Identifier)
    #expect(module!.name.value == "Foo")
    #expect(module!.body.isEmpty)
}

@Test func parseModuleWithVariableDecl() throws {
    let statements = parseStatements("module Foo { let x }")
    try #require(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    try #require(module != nil)
    #expect(module!.name.value == "Foo")
    try #require(module!.body.count == 1)
    let vd = module!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseModuleWithFunctionDecl() throws {
    let statements = parseStatements("module Foo { func bar() {} }")
    try #require(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    try #require(module != nil)
    #expect(module!.name.value == "Foo")
    try #require(module!.body.count == 1)
    let fd = module!.body[0] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "bar")
    if case let .Block(body) = fd!.body {
        #expect(body.isEmpty)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseModuleWithMultipleDeclarations() throws {
    let statements = parseStatements("module Foo { let x func bar() {} var y }")
    try #require(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    try #require(module != nil)
    try #require(module!.body.count == 3)
    let vd1 = module!.body[0] as? AST.VariableDecl
    try #require(vd1 != nil)
    #expect(vd1!.name.value == "x")
    let fd = module!.body[1] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "bar")
    let vd2 = module!.body[2] as? AST.VariableDecl
    try #require(vd2 != nil)
    #expect(vd2!.name.value == "y")
}

@Test func parseModuleWithEmptyStatement() throws {
    let statements = parseStatements("module Foo { ; }")
    try #require(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    try #require(module != nil)
    try #require(module!.body.count == 1)
    #expect(module!.body[0] is AST.EmptyStatement)
}

@Test func parseNestedModule() throws {
    let statements = parseStatements("module Outer { module Inner {} }")
    try #require(statements.count == 1)
    let outer = statements[0] as? AST.ModuleDecl
    try #require(outer != nil)
    #expect(outer!.name.value == "Outer")
    try #require(outer!.body.count == 1)
    let inner = outer!.body[0] as? AST.ModuleDecl
    try #require(inner != nil)
    #expect(inner!.name.value == "Inner")
    #expect(inner!.body.isEmpty)
}

@Test func parseModuleWithDottedPath() throws {
    let statements = parseStatements("module A.B {}")
    try #require(statements.count == 1)
    let outer = statements[0] as? AST.ModuleDecl
    try #require(outer != nil)
    #expect(outer!.name.value == "A")
    try #require(outer!.body.count == 1)
    let inner = outer!.body[0] as? AST.ModuleDecl
    try #require(inner != nil)
    #expect(inner!.token.kind == .Keyword(.Module))
    #expect(inner!.name.value == "B")
    #expect(inner!.body.isEmpty)
}

@Test func parseModuleWithThreeLevelPath() throws {
    let statements = parseStatements("module A.B.C { let x }")
    try #require(statements.count == 1)
    let outer = statements[0] as? AST.ModuleDecl
    try #require(outer != nil)
    #expect(outer!.name.value == "A")
    try #require(outer!.body.count == 1)
    let mid = outer!.body[0] as? AST.ModuleDecl
    try #require(mid != nil)
    #expect(mid!.name.value == "B")
    try #require(mid!.body.count == 1)
    let inner = mid!.body[0] as? AST.ModuleDecl
    try #require(inner != nil)
    #expect(inner!.name.value == "C")
    try #require(inner!.body.count == 1)
    let vd = inner!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseModuleDottedPathWithModifiers() throws {
    let statements = parseStatements("public module A.B {}")
    try #require(statements.count == 1)
    let outer = statements[0] as? AST.ModuleDecl
    try #require(outer != nil)
    try #require(outer!.modifiers.count == 1)
    #expect(modifierKind(outer!.modifiers[0].kind, equals: .Public(setter: false)))
    let inner = outer!.body[0] as? AST.ModuleDecl
    try #require(inner != nil)
    try #require(inner!.modifiers.count == 1)
    #expect(modifierKind(inner!.modifiers[0].kind, equals: .Public(setter: false)))
}

@Test func parseModuleDottedPathTrailingDotError() throws {
    let errors = parseWithDiagnostics("module A.").1
    try #require(errors.count == 2)
    #expect(errors[0].message.contains("expected module name after '.'"))
}

@Test func parseModuleDottedPathInvalidComponentError() throws {
    let errors = parseWithDiagnostics("module A.3 {}").1
    try #require(errors.count == 5)
    #expect(errors[0].message.contains("expected module name after '.', but got '3'"))
}

@Test func parseModuleWithVariableInitializer() throws {
    let statements = parseStatements("module Foo { let x = 42 }")
    try #require(statements.count == 1)
    let module = statements[0] as? AST.ModuleDecl
    try #require(module != nil)
    try #require(module!.body.count == 1)
    let vd = module!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
    let lit = vd!.initializer as? AST.IntegerLiteral
    try #require(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseModuleFollowedByDeclaration() throws {
    let statements = parseStatements("module Foo {} let x")
    try #require(statements.count == 2)
    let module = statements[0] as? AST.ModuleDecl
    try #require(module != nil)
    #expect(module!.name.value == "Foo")
    let vd = statements[1] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseOperatorInfix() throws {
    let statements = parseStatements("infix operator +")
    try #require(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    try #require(op != nil)
    #expect(op!.name.value == "+")
    if case let .Infix(t) = op!.kind {
        #expect(t.kind == .Keyword(.Infix))
    } else {
        #expect(Bool(false))
    }
}

@Test func parseOperatorPrefix() throws {
    let statements = parseStatements("prefix operator -")
    try #require(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    try #require(op != nil)
    #expect(op!.name.value == "-")
    if case let .Prefix(t) = op!.kind {
        #expect(t.kind == .Keyword(.Prefix))
    } else {
        #expect(Bool(false))
    }
}

@Test func parseOperatorPostfix() throws {
    let statements = parseStatements("postfix operator ++")
    try #require(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    try #require(op != nil)
    #expect(op!.name.value == "++")
    if case let .Postfix(t) = op!.kind {
        #expect(t.kind == .Keyword(.Postfix))
    } else {
        #expect(Bool(false))
    }
}

@Test func parseOperatorWithGroup() throws {
    let statements = parseStatements("infix operator +: P")
    try #require(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    try #require(op != nil)
    #expect((op!.group as? AST.Variable)?.name.value == "P")
}

@Test func parseOperatorWithQualifiedGroup() throws {
    let statements = parseStatements("infix operator +: M.P")
    try #require(statements.count == 1)
    let op = statements[0] as? AST.OperatorDecl
    let member = op!.group as? AST.MemberAccess
    #expect((member?.object as? AST.Variable)?.name.value == "M")
    #expect(member?.member.value == "P")
}

@Test func parseOperatorWithoutGroup() {
    let statements = parseStatements("infix operator +")
    let op = statements[0] as? AST.OperatorDecl
    #expect(op!.group == nil)
}

@Test func prefixOperatorWithGroupReportsError() throws {
    let statements = parseStatements("prefix operator -: P")
    let op = statements[0] as? AST.OperatorDecl
    try #require(op != nil)
    #expect(op!.group == nil)
    #expect(
        parseWithDiagnostics("prefix operator -: P").1.map(\.message)
            .contains("prefix operator '-' cannot have a precedence group")
    )
}

@Test func legacyOperatorKindSuffixReportsError() throws {
    let (program, diagnostics) = parseWithDiagnostics("operator + infix\nfunc f() {}")
    #expect(
        diagnostics.map(\.message)
            .contains("expected 'infix', 'prefix', or 'postfix', but got 'operator'")
    )
    try #require(program.statements.count == 2)
    #expect(program.statements[1] is AST.FunctionDecl)
}

@Test func parseUnknownTokenReportsErrorAndContinues() throws {
    let (program, diagnostics) = parseWithDiagnostics("foo\nfunc f() {}")
    try #require(diagnostics.count == 1)
    #expect(diagnostics[0].message == "expected statement, but got 'foo'")
    try #require(program.statements.count == 2)
    #expect(program.statements[1] is AST.FunctionDecl)
}

@Test func parseUnknownKeywordAndSeparatorReportErrors() throws {
    let (program, diagnostics) = parseWithDiagnostics("init\n}\nfunc f() {}")
    #expect(diagnostics.count == 2)
    #expect(diagnostics.map(\.message) == ["expected statement, but got 'init'", "expected statement, but got '}'"])
    try #require(program.statements.count == 3)
    #expect(program.statements[2] is AST.FunctionDecl)
}

@Test func parseEmptyPrecedenceGroup() throws {
    let statements = parseStatements("precedencegroup Foo {}")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.name.value == "Foo")
    #expect(pg!.associativity == .None)
    #expect(pg!.assignment == false)
    #expect(pg!.higherThan.isEmpty)
    #expect(pg!.lowerThan.isEmpty)
}

@Test func parsePrecedenceGroupAssociativityLeft() throws {
    let statements = parseStatements("precedencegroup Foo { associativity: left }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.associativity == .Left)
    #expect(pg!.associativityToken != nil)
}

@Test func parsePrecedenceGroupAssociativityRight() throws {
    let statements = parseStatements("precedencegroup Foo { associativity: right }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.associativity == .Right)
}

@Test func parsePrecedenceGroupAssociativityNone() throws {
    let statements = parseStatements("precedencegroup Foo { associativity: none }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.associativity == .None)
}

@Test func parsePrecedenceGroupAssignmentTrue() throws {
    let statements = parseStatements("precedencegroup Foo { assignment: true }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.assignment == true)
    #expect(pg!.assignmentToken != nil)
}

@Test func parsePrecedenceGroupAssignmentFalse() throws {
    let statements = parseStatements("precedencegroup Foo { assignment: false }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.assignment == false)
}

@Test func parsePrecedenceGroupHigherThanSingle() throws {
    let statements = parseStatements("precedencegroup Foo { higherThan: Bar }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    try #require(pg!.higherThan.count == 1)
    let bar = pg!.higherThan[0] as? AST.Variable
    try #require(bar != nil)
    #expect(bar!.name.value == "Bar")
    #expect(pg!.higherThanTokens.count == 1)
}

@Test func parsePrecedenceGroupHigherThanMultiple() throws {
    let statements = parseStatements("precedencegroup Foo { higherThan: Bar, Baz }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    try #require(pg!.higherThan.count == 2)
    let bar = pg!.higherThan[0] as? AST.Variable
    try #require(bar != nil)
    #expect(bar!.name.value == "Bar")
    let baz = pg!.higherThan[1] as? AST.Variable
    try #require(baz != nil)
    #expect(baz!.name.value == "Baz")
}

@Test func parsePrecedenceGroupLowerThanSingle() throws {
    let statements = parseStatements("precedencegroup Foo { lowerThan: Bar }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    try #require(pg!.lowerThan.count == 1)
    let bar = pg!.lowerThan[0] as? AST.Variable
    try #require(bar != nil)
    #expect(bar!.name.value == "Bar")
    #expect(pg!.lowerThanTokens.count == 1)
}

@Test func parsePrecedenceGroupLowerThanMultiple() throws {
    let statements = parseStatements("precedencegroup Foo { lowerThan: Bar, Baz }")
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    try #require(pg!.lowerThan.count == 2)
    #expect((pg!.lowerThan[0] as! AST.Variable).name.value == "Bar")
    #expect((pg!.lowerThan[1] as! AST.Variable).name.value == "Baz")
}

@Test func parsePrecedenceGroupAllProperties() throws {
    let statements = parseStatements(
        "precedencegroup Foo { associativity: left assignment: true higherThan: Bar lowerThan: Baz }"
    )
    try #require(statements.count == 1)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.name.value == "Foo")
    #expect(pg!.associativity == .Left)
    #expect(pg!.assignment == true)
    try #require(pg!.higherThan.count == 1)
    #expect((pg!.higherThan[0] as! AST.Variable).name.value == "Bar")
    try #require(pg!.lowerThan.count == 1)
    #expect((pg!.lowerThan[0] as! AST.Variable).name.value == "Baz")
}

@Test func parsePrecedenceGroupFollowedByDeclaration() throws {
    let statements = parseStatements("precedencegroup Foo {} let x")
    try #require(statements.count == 2)
    let pg = statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    #expect(pg!.name.value == "Foo")
    let vd = statements[1] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parsePrecedenceGroupMultipleHigherThanClauses() throws {
    let (program, diagnostics) = parseWithDiagnostics(
        "precedencegroup Foo { higherThan: Bar higherThan: Baz }"
    )
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.isEmpty)
    let pg = program.statements[0] as? AST.PrecedenceGroupDecl
    try #require(pg != nil)
    try #require(pg!.higherThan.count == 2)
    #expect(pg!.higherThanTokens.count == 2)
    let bar = pg!.higherThan[0] as? AST.Variable
    try #require(bar != nil)
    #expect(bar!.name.value == "Bar")
    let baz = pg!.higherThan[1] as? AST.Variable
    try #require(baz != nil)
    #expect(baz!.name.value == "Baz")
}

@Test func parsePrecedenceGroupDuplicateAssociativityReportsFirstDefinition() throws {
    let (_, diagnostics) = parseWithDiagnostics(
        "precedencegroup Foo { associativity: left associativity: right }"
    )
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "associativity can only be set once")
    try #require(errors[0].notes.count == 1)
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
    let sequentialExpression = expr as! AST.Sequential
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
    try #require(errors[0].notes.count == 1)
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
    try #require(errors[0].notes.count == 1)
    let note = errors[0].notes[0]
    #expect(note.severity == .note)
    #expect(note.message == "first declared here")
}

@Test func parseObserverInFunctionContextReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics(
        "func main() { var a: Int = 0 { willSet {} didSet {} } }"
    )
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "property observers are not allowed in function context")
}

// MARK: - Struct Declarations

@Test func parseEmptyStruct() throws {
    let statements = parseStatements("struct Foo {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Struct))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.genericDecl == nil)
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseStructWithMembers() throws {
    let statements = parseStatements("struct Foo { let x var y func bar() {} }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.body.count == 3)
    let vd1 = decl!.body[0] as? AST.VariableDecl
    try #require(vd1 != nil)
    #expect(vd1!.name.value == "x")
    let vd2 = decl!.body[1] as? AST.VariableDecl
    try #require(vd2 != nil)
    #expect(vd2!.name.value == "y")
    let fd = decl!.body[2] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "bar")
}

@Test func parseStructWithConformances() throws {
    let statements = parseStatements("struct Foo: P, Q {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.conformances.count == 2)
    let p = decl!.conformances[0] as? AST.Variable
    try #require(p != nil)
    #expect(p!.name.value == "P")
    let q = decl!.conformances[1] as? AST.Variable
    try #require(q != nil)
    #expect(q!.name.value == "Q")
}

@Test func parseStructWithEmptyStatementInBody() throws {
    let statements = parseStatements("struct Foo { ; }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.body.count == 1)
    #expect(decl!.body[0] is AST.EmptyStatement)
}

@Test func parseStructWithGenericPlainParameters() throws {
    let statements = parseStatements("struct Foo<T, U> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl != nil)
    try #require(decl!.genericDecl!.generics.count == 2)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
    #expect(decl!.genericDecl!.generics[1].name.value == "U")
}

@Test func parseStructWithGenericEachParameter() throws {
    let statements = parseStatements("struct Foo<each T> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl != nil)
    try #require(decl!.genericDecl!.generics.count == 1)
    let param = decl!.genericDecl!.generics[0]
    #expect(param.eachToken != nil)
    #expect(param.name.value == "T")
    #expect(param.constraint == nil)
}

@Test func parseStructWithGenericEachParameterWithConstraint() throws {
    let statements = parseStatements("struct Foo<each T: P> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl!.generics.count == 1)
    let param = decl!.genericDecl!.generics[0]
    #expect(param.eachToken != nil)
    #expect(param.name.value == "T")
    let constraint = param.constraint as? AST.Variable
    try #require(constraint != nil)
    #expect(constraint!.name.value == "P")
}

@Test func parseStructWithMixedGenericParameters() throws {
    let statements = parseStatements("struct Foo<T, each U: P> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl!.generics.count == 2)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
    #expect(decl!.genericDecl!.generics[1].name.value == "U")
}

// MARK: - Class Declarations

@Test func parseEmptyClass() throws {
    let statements = parseStatements("class Foo {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Class))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.genericDecl == nil)
    #expect(decl!.inheritanceClauses.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseClassWithInheritance() throws {
    let statements = parseStatements("class Foo: Base, P {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    try #require(decl!.inheritanceClauses.count == 2)
    let base = decl!.inheritanceClauses[0] as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Base")
    let p = decl!.inheritanceClauses[1] as? AST.Variable
    try #require(p != nil)
    #expect(p!.name.value == "P")
}

@Test func parseClassWithMembers() throws {
    let statements = parseStatements("class Foo { var x func bar() {} }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    try #require(decl!.body.count == 2)
    let vd = decl!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
    let fd = decl!.body[1] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "bar")
}

// MARK: - Protocol Declarations

@Test func parseEmptyProtocol() throws {
    let statements = parseStatements("protocol Foo {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.ProtocolKw))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseProtocolWithMembers() throws {
    let statements = parseStatements("protocol Foo { func bar() {} var x: Int }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    try #require(decl != nil)
    try #require(decl!.body.count == 2)
    let fd = decl!.body[0] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "bar")
    let vd = decl!.body[1] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

@Test func parseProtocolWithConformances() throws {
    let statements = parseStatements("protocol Foo: P {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    try #require(decl != nil)
    try #require(decl!.conformances.count == 1)
    let p = decl!.conformances[0] as? AST.Variable
    try #require(p != nil)
    #expect(p!.name.value == "P")
}

// MARK: - Extension Declarations

@Test func parseEmptyExtension() throws {
    let statements = parseStatements("extension Foo {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ExtensionDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Extension))
    let base = decl!.base as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Foo")
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseExtensionWithConformances() throws {
    let statements = parseStatements("extension Foo: P, Q {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ExtensionDecl
    try #require(decl != nil)
    try #require(decl!.conformances.count == 2)
    let p = decl!.conformances[0] as? AST.Variable
    try #require(p != nil)
    #expect(p!.name.value == "P")
    let q = decl!.conformances[1] as? AST.Variable
    try #require(q != nil)
    #expect(q!.name.value == "Q")
}

@Test func parseExtensionWithMembers() throws {
    let statements = parseStatements("extension Foo { func bar() {} }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ExtensionDecl
    try #require(decl != nil)
    try #require(decl!.body.count == 1)
    let fd = decl!.body[0] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "bar")
}

@Test func parseExtensionGenericReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("extension Foo<T> {}")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "declaring generic type in extension is not allowed")
}

// MARK: - While Statements

@Test func parseWhileWithEmptyBody() throws {
    let body = parseBlockStatements("func main() { while true {} }")
    try #require(body.count == 1)
    let whileStmt = body[0] as? AST.While
    try #require(whileStmt != nil)
    #expect(whileStmt!.token.kind == .Keyword(.While))
    let cond = whileStmt!.condition as? AST.BoolLiteral
    try #require(cond != nil)
    #expect(cond!.value == true)
    #expect(whileStmt!.body.isEmpty)
    #expect(whileStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(whileStmt!.endToken.kind == .Separator(.CloseBrace))
}

@Test func parseWhileWithBody() throws {
    let body = parseBlockStatements("func main() { while x { let y } }")
    try #require(body.count == 1)
    let whileStmt = body[0] as? AST.While
    try #require(whileStmt != nil)
    let cond = whileStmt!.condition as? AST.Variable
    try #require(cond != nil)
    #expect(cond!.name.value == "x")
    try #require(whileStmt!.body.count == 1)
    let vd = whileStmt!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "y")
}

// MARK: - Repeat-While Statements

@Test func parseRepeatWhileEmptyBody() throws {
    let body = parseBlockStatements("func main() { repeat {} while true }")
    try #require(body.count == 1)
    let repeatStmt = body[0] as? AST.RepeatWhile
    try #require(repeatStmt != nil)
    #expect(repeatStmt!.token.kind == .Keyword(.Repeat))
    #expect(repeatStmt!.body.isEmpty)
    #expect(repeatStmt!.whileToken.kind == .Keyword(.While))
    let cond = repeatStmt!.condition as? AST.BoolLiteral
    try #require(cond != nil)
    #expect(cond!.value == true)
}

@Test func parseRepeatWhileWithBody() throws {
    let body = parseBlockStatements("func main() { repeat { let y } while x }")
    try #require(body.count == 1)
    let repeatStmt = body[0] as? AST.RepeatWhile
    try #require(repeatStmt != nil)
    try #require(repeatStmt!.body.count == 1)
    let vd = repeatStmt!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "y")
    let cond = repeatStmt!.condition as? AST.Variable
    try #require(cond != nil)
    #expect(cond!.name.value == "x")
}

// MARK: - Guard Statements

@Test func parseGuardWithEmptyBody() throws {
    let body = parseBlockStatements("func main() { guard x else {} }")
    try #require(body.count == 1)
    let guardStmt = body[0] as? AST.Guard
    try #require(guardStmt != nil)
    #expect(guardStmt!.token.kind == .Keyword(.Guard))
    let cond = guardStmt!.condition as? AST.Variable
    try #require(cond != nil)
    #expect(cond!.name.value == "x")
    #expect(guardStmt!.body.isEmpty)
    #expect(guardStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(guardStmt!.endToken.kind == .Separator(.CloseBrace))
}

@Test func parseGuardWithBody() throws {
    let body = parseBlockStatements("func main() { guard x else { return } }")
    try #require(body.count == 1)
    let guardStmt = body[0] as? AST.Guard
    try #require(guardStmt != nil)
    try #require(guardStmt!.body.count == 1)
    #expect(guardStmt!.body[0] is AST.Return)
}

// MARK: - Defer Statements

@Test func parseDeferWithEmptyBody() throws {
    let body = parseBlockStatements("func main() { defer {} }")
    try #require(body.count == 1)
    let deferStmt = body[0] as? AST.Defer
    try #require(deferStmt != nil)
    #expect(deferStmt!.token.kind == .Keyword(.Defer))
    #expect(deferStmt!.body.isEmpty)
    #expect(deferStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(deferStmt!.endToken.kind == .Separator(.CloseBrace))
}

@Test func parseDeferWithBody() throws {
    let body = parseBlockStatements("func main() { defer { let x } }")
    try #require(body.count == 1)
    let deferStmt = body[0] as? AST.Defer
    try #require(deferStmt != nil)
    try #require(deferStmt!.body.count == 1)
    let vd = deferStmt!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
}

// MARK: - Asm Statements

@Test func parseAsmBasic() throws {
    let body = parseBlockStatements("func main() { asm { \"mov {dst}, 42\" : dst = out(reg) result } }")
    try #require(body.count == 1)
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    #expect(asm!.token.kind == .Keyword(.Asm))
    #expect(asm!.beginToken.kind == .Separator(.OpenBrace))
    #expect(asm!.endToken.kind == .Separator(.CloseBrace))
    try #require(asm!.templates.count == 1)
    #expect(asm!.templates[0].token.value == "mov {dst}, 42")
    try #require(asm!.bindings.count == 1)
    let binding = asm!.bindings[0]
    #expect(binding.name.value == "dst")
    #expect(binding.kind.value == "out")
    #expect(binding.constraint.value == "reg")
    #expect(binding.local?.value == "result")
    #expect(asm!.options.isEmpty)
}

@Test func parseAsmInKindWithoutLocal() throws {
    let body = parseBlockStatements("func main() { asm { \"mov {dst}, 42\" : dst = in(reg) } }")
    try #require(body.count == 1)
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    try #require(asm!.bindings.count == 1)
    #expect(asm!.bindings[0].kind.value == "in")
    #expect(asm!.bindings[0].local == nil)
}

@Test func parseAsmMultipleTemplates() throws {
    let body = parseBlockStatements(
        "func main() { asm { \"mov {dst}, 42\" \"add {dst}, 1\" : dst = out(reg) result } }"
    )
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    try #require(asm!.templates.count == 2)
    #expect(asm!.templates[0].token.value == "mov {dst}, 42")
    #expect(asm!.templates[1].token.value == "add {dst}, 1")
}

@Test func parseAsmMultipleBindings() throws {
    let body = parseBlockStatements(
        "func main() { asm { \"mov {dst}, {src}\" : dst = out(reg) result, src = in(reg) value } }"
    )
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    try #require(asm!.bindings.count == 2)
    #expect(asm!.bindings[0].name.value == "dst")
    #expect(asm!.bindings[0].local?.value == "result")
    #expect(asm!.bindings[1].name.value == "src")
    #expect(asm!.bindings[1].kind.value == "in")
    #expect(asm!.bindings[1].local?.value == "value")
}

@Test func parseAsmInoutKindWithLocal() throws {
    let body = parseBlockStatements(
        "func main() { asm { \"inc {x}\" : x = inout(reg) counter } }"
    )
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    try #require(asm!.bindings.count == 1)
    #expect(asm!.bindings[0].kind.value == "inout")
    #expect(asm!.bindings[0].local?.value == "counter")
}

@Test func parseAsmEmptyBindings() {
    let body = parseBlockStatements("func main() { asm { \"nop\" : } }")
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    #expect(asm!.templates.count == 1)
    #expect(asm!.bindings.isEmpty)
    #expect(asm!.options.isEmpty)
}

@Test func parseAsmOptions() throws {
    let body = parseBlockStatements(
        "func main() { asm { \"mov {dst}, 42\" : dst = out(reg) result : result preserves_flags } }"
    )
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    #expect(asm!.bindings.count == 1)
    try #require(asm!.options.count == 2)
    #expect(asm!.options[0].value == "result")
    #expect(asm!.options[1].value == "preserves_flags")
}

@Test func parseAsmMissingOpenBraceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { asm x }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected '{' after 'asm', but got 'x'")
}

@Test func parseAsmWithoutColon() throws {
    let body = parseBlockStatements("func main() { asm { \"mov {dst}, 42\" } }")
    try #require(body.count == 1)
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    try #require(asm!.templates.count == 1)
    #expect(asm!.templates[0].token.value == "mov {dst}, 42")
    #expect(asm!.bindings.isEmpty)
    #expect(asm!.options.isEmpty)
}

@Test func parseAsmEmptyBlock() throws {
    let body = parseBlockStatements("func main() { asm { } }")
    try #require(body.count == 1)
    let asm = body[0] as? AST.Asm
    #expect(asm != nil)
    #expect(asm!.templates.isEmpty)
    #expect(asm!.bindings.isEmpty)
    #expect(asm!.options.isEmpty)
}

@Test func parseAsmMissingEqualsReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { asm { \"mov\" : dst out(reg) result } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected '=' after asm operand name, but got 'out'")
}

@Test func parseAsmMissingKindReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { asm { \"mov\" : dst = (reg) result } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected operand kind after '=', but got '('")
}

@Test func parseAsmMissingConstraintReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { asm { \"mov\" : dst = out() result } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected constraint after '(', but got ')'")
}

@Test func parseAsmMissingCloseParenReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { asm { \"mov\" : dst = out(reg result } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected ')' after asm constraint, but got 'result'")
}

@Test func parseAsmMissingCloseBraceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { asm { \"mov\" : dst = out(reg) result")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.contains { $0.message.contains("expected '}' after asm body") })
}

@Test func parseAsmInvalidOptionReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { asm { \"nop\" : : 42 } }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected asm option, but got '42'")
}

// MARK: - Break / Continue / Goto

@Test func parseBreakWithoutLabel() throws {
    let body = parseBlockStatements("func main() { break }")
    try #require(body.count == 1)
    let breakStmt = body[0] as? AST.Break
    try #require(breakStmt != nil)
    #expect(breakStmt!.token.kind == .Keyword(.Break))
    #expect(breakStmt!.label == nil)
}

@Test func parseBreakWithLabel() throws {
    let body = parseBlockStatements("func main() { break label }")
    try #require(body.count == 1)
    let breakStmt = body[0] as? AST.Break
    try #require(breakStmt != nil)
    try #require(breakStmt!.label != nil)
    #expect(breakStmt!.label!.value == "label")
}

@Test func parseBreakLabelOnDifferentLineHasNoLabel() throws {
    let body = parseBlockStatements("func main() {\nbreak\nlabel\n}")
    let breakStmt = body[0] as? AST.Break
    try #require(breakStmt != nil)
    #expect(breakStmt!.label == nil)
}

@Test func parseContinueWithoutLabel() throws {
    let body = parseBlockStatements("func main() { continue }")
    try #require(body.count == 1)
    let continueStmt = body[0] as? AST.Continue
    try #require(continueStmt != nil)
    #expect(continueStmt!.token.kind == .Keyword(.Continue))
    #expect(continueStmt!.label == nil)
}

@Test func parseContinueWithLabel() throws {
    let body = parseBlockStatements("func main() { continue label }")
    try #require(body.count == 1)
    let continueStmt = body[0] as? AST.Continue
    try #require(continueStmt != nil)
    try #require(continueStmt!.label != nil)
    #expect(continueStmt!.label!.value == "label")
}

@Test func parseContinueLabelOnDifferentLineHasNoLabel() throws {
    let body = parseBlockStatements("func main() {\ncontinue\nlabel\n}")
    let continueStmt = body[0] as? AST.Continue
    try #require(continueStmt != nil)
    #expect(continueStmt!.label == nil)
}

@Test func parseGotoProducesGotoNode() throws {
    let body = parseBlockStatements("func main() { goto label }")
    try #require(body.count == 1)
    let gotoStmt = body[0] as? AST.Goto
    try #require(gotoStmt != nil)
    #expect(gotoStmt!.token.kind == .Keyword(.Goto))
    #expect(gotoStmt!.label.value == "label")
}

// MARK: - For-In Statements

@Test func parseForPlainIdentifier() throws {
    let body = parseBlockStatements("func main() { for i in items {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    #expect(forStmt!.token.kind == .Keyword(.For))
    #expect(forStmt!.inToken.kind == .Identifier)
    #expect(forStmt!.inToken.value == "in")
    let pattern = forStmt!.pattern as? AST.Variable
    try #require(pattern != nil)
    #expect(pattern!.name.value == "i")
    let seq = forStmt!.sequence as? AST.Variable
    try #require(seq != nil)
    #expect(seq!.name.value == "items")
    #expect(forStmt!.body.isEmpty)
    #expect(forStmt!.beginToken.kind == .Separator(.OpenBrace))
    #expect(forStmt!.endToken.kind == .Separator(.CloseBrace))
    #expect(forStmt!.whereClause == nil)
    #expect(forStmt!.caseToken == nil)
}

@Test func parseForLetBinding() throws {
    let body = parseBlockStatements("func main() { for let x in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let pattern = forStmt!.pattern as? AST.BindingPattern
    try #require(pattern != nil)
    #expect(pattern!.token.kind == .Keyword(.Let))
    #expect(pattern!.name.value == "x")
}

@Test func parseForVarBinding() throws {
    let body = parseBlockStatements("func main() { for var x in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let pattern = forStmt!.pattern as? AST.BindingPattern
    try #require(pattern != nil)
    #expect(pattern!.token.kind == .Keyword(.Var))
    #expect(pattern!.name.value == "x")
}

@Test func parseForWithBody() throws {
    let body = parseBlockStatements("func main() { for i in items { let y } }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    try #require(forStmt!.body.count == 1)
    let vd = forStmt!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "y")
}

@Test func parseForWithWhereClause() throws {
    let body = parseBlockStatements("func main() { for i in items where i > 0 {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let whereClause = forStmt!.whereClause as? AST.Sequential
    try #require(whereClause != nil)
    #expect(whereClause!.ops.count == 1)
    #expect(forStmt!.body.isEmpty)
}

@Test func parseForAwaitWithWhereClause() throws {
    let body = parseBlockStatements("func main() { for await x in items where x > 0 {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    #expect(forStmt!.asyncToken != nil)
    #expect(forStmt!.whereClause != nil)
}

@Test func parseForCaseWithWhereClause() throws {
    let body = parseBlockStatements("func main() { for case .foo(let x) in arr where x > 0 {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let call = forStmt!.pattern as? AST.Call
    try #require(call != nil)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    #expect(forStmt!.caseToken != nil)
    #expect(forStmt!.whereClause != nil)
}

@Test func parseForWhereClauseComplexCondition() throws {
    let body = parseBlockStatements("func main() { for i in items where i > 0 && i < 10 {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let whereClause = forStmt!.whereClause as? AST.Sequential
    try #require(whereClause != nil)
    #expect(whereClause!.ops.count == 3)
    #expect(whereClause!.operands.count == 4)
}

@Test func parseForWhereClauseMissingExpressionReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { for i in items where }")
    try #require(!errors.isEmpty)
    #expect(errors.contains { $0.message.contains("expected '{' after for-in sequence") })
}

// MARK: - Accessor Success Paths

@Test func parseGetterWithBlockBody() throws {
    let statements = parseStatements("var x: Int { get { 1 } }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    try #require(decl!.accessors.count == 1)
    let accessor = decl!.accessors[0]
    #expect(accessor.kind == .Get)
    #expect(accessor.token?.value == "get")
    #expect(accessor.parameterName == nil)
    if case let .Block(stmts) = accessor.body {
        #expect(stmts.count == 1)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseGetterWithExpressionBody() throws {
    let statements = parseStatements("var x: Int { get = 1 }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    try #require(decl!.accessors.count == 1)
    let accessor = decl!.accessors[0]
    #expect(accessor.kind == .Get)
    if case let .Expression(expr) = accessor.body {
        let lit = expr as? AST.IntegerLiteral
        try #require(lit != nil)
        #expect(lit!.value == 1)
    } else {
        Issue.record("expected expression body")
    }
}

@Test func parseSetterWithoutParameterName() throws {
    let statements = parseStatements("var x: Int { get { 1 } set {} }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    try #require(decl!.accessors.count == 2)
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

@Test func parseSetterWithParameterName() throws {
    let statements = parseStatements("var x: Int { get { 1 } set(newValue) {} }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    let setter = decl!.accessors[1]
    #expect(setter.kind == .Set)
    try #require(setter.parameterName != nil)
    #expect(setter.parameterName!.value == "newValue")
}

@Test func parseWillSetWithoutParameterName() throws {
    let statements = parseStatements("var x: Int = 0 { willSet {} }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    try #require(decl!.accessors.count == 1)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .WillSet)
    #expect(observer.token?.value == "willSet")
    #expect(observer.parameterName == nil)
}

@Test func parseWillSetWithParameterName() throws {
    let statements = parseStatements("var x: Int = 0 { willSet(new) {} }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .WillSet)
    try #require(observer.parameterName != nil)
    #expect(observer.parameterName!.value == "new")
}

@Test func parseDidSetWithoutParameterName() throws {
    let statements = parseStatements("var x: Int = 0 { didSet {} }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .DidSet)
    #expect(observer.token?.value == "didSet")
    #expect(observer.parameterName == nil)
}

@Test func parseDidSetWithParameterName() throws {
    let statements = parseStatements("var x: Int = 0 { didSet(old) {} }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    let observer = decl!.accessors[0]
    #expect(observer.kind == .DidSet)
    try #require(observer.parameterName != nil)
    #expect(observer.parameterName!.value == "old")
}

@Test func parseShorthandGetter() throws {
    let statements = parseStatements("var x: Int { 1 }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    try #require(decl!.accessors.count == 1)
    let accessor = decl!.accessors[0]
    #expect(accessor.kind == .Get)
    #expect(accessor.token == nil)
    if case let .Block(stmts) = accessor.body {
        #expect(stmts.count == 1)
    } else {
        Issue.record("expected block body")
    }
}

@Test func parseStoredPropertyWithWillSetAndDidSet() throws {
    let statements = parseStatements("var x: Int = 0 { willSet {} didSet {} }")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    try #require(decl!.accessors.count == 2)
    #expect(decl!.accessors[0].kind == .WillSet)
    #expect(decl!.accessors[1].kind == .DidSet)
}

// MARK: - Modifiers

@Test func parsePublicModifierOnStruct() throws {
    let statements = parseStatements("public struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: false)))
}

@Test func parsePublicSetModifierOnStruct() throws {
    let statements = parseStatements("public(set) struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: true)))
}

@Test func parsePrivateModifierOnVariable() throws {
    let statements = parseStatements("private var x")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    try #require(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Private(setter: false)))
}

@Test func parsePrivateSetModifierOnVariable() throws {
    let statements = parseStatements("private(set) var x")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Private(setter: true)))
}

@Test func parseInternalModifierOnFunction() throws {
    let statements = parseStatements("internal func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Internal(setter: false)))
}

@Test func parseFilePrivateModifierOnStruct() throws {
    let statements = parseStatements("fileprivate struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .FilePrivate(setter: false)))
}

@Test func parseProtectedSetModifierOnClass() throws {
    let statements = parseStatements("protected(set) class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Protected(setter: true)))
}

@Test func parsePackagePrivateModifierOnStruct() throws {
    let statements = parseStatements("packageprivate struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .PackagePrivate(setter: false)))
}

@Test func parseOpenModifierOnClass() throws {
    let statements = parseStatements("open class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Open(setter: false)))
}

@Test func parseFinalModifierOnClass() throws {
    let statements = parseStatements("final class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Final))
}

@Test func parseOverrideModifierOnFunction() throws {
    let statements = parseStatements("override func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Override))
}

@Test func parseMultipleModifiersOnStruct() throws {
    let statements = parseStatements("public final struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.modifiers.count == 2)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: false)))
    #expect(modifierKind(decl!.modifiers[1].kind, equals: .Final))
}

@Test func parseMutatingModifierOnFunction() throws {
    let statements = parseStatements("mutating func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Mutating))
}

@Test func parseLazyModifierOnVariable() throws {
    let statements = parseStatements("lazy var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Lazy))
}

// MARK: - Attributes

@Test func parseAttributeWithoutArguments() throws {
    let statements = parseStatements("#[attr] struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.attributes.count == 1)
    #expect(decl!.attributes[0].name.value == "attr")
    #expect(decl!.attributes[0].arguments.isEmpty)
}

@Test func parseAttributeWithModifiers() throws {
    let statements = parseStatements("#[attr] public struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    #expect(decl!.attributes.count == 1)
    try #require(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: false)))
}

@Test func parseAttributeWithArguments() throws {
    let statements = parseStatements("#[attr(a b)] struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.attributes.count == 1)
    try #require(decl!.attributes[0].arguments.count == 1)
    try #require(decl!.attributes[0].arguments[0].count == 2)
    #expect(decl!.attributes[0].arguments[0][0].value == "a")
    #expect(decl!.attributes[0].arguments[0][1].value == "b")
}

@Test func parseAttributeWithLabeledArguments() throws {
    let statements = parseStatements("#[attr(label: a b)] struct Foo {}")
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.attributes.count == 1)
    let attr = decl!.attributes[0]
    #expect(attr.labeledArguments.count == 1)
    let labelToken = attr.labeledArguments.first { $0.key.value == "label" }
    try #require(labelToken != nil)
    try #require(labelToken!.value.count == 2)
    #expect(labelToken!.value[0].value == "a")
    #expect(labelToken!.value[1].value == "b")
}

@Test func parseModifierOnReturnStatementReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func f() { public return }")
    #expect(
        diagnostics.map(\.message)
            .contains("modifiers are not allowed on 'return' statement")
    )
}

@Test func parseModifierOnWhileStatementReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func f() { public while true {} }")
    #expect(
        diagnostics.map(\.message)
            .contains("modifiers are not allowed on 'while' statement")
    )
}

@Test func parseModifierOnExpressionStatementReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func f() { public x = 1 }")
    #expect(
        diagnostics.map(\.message)
            .contains("modifiers are not allowed on expressions")
    )
}

@Test func parseAttributeOnExpressionStatementReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func f() { #[attr] x + 1 }")
    #expect(
        diagnostics.map(\.message)
            .contains("attributes are not allowed on expressions")
    )
}

@Test func parseModifiersAndAttributesOnStatementReportsCombinedError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func f() { public #[attr] return }")
    #expect(
        diagnostics.map(\.message)
            .contains("modifiers and attributes are not allowed on 'return' statement")
    )
}

@Test func parseModifierOnNonDeclarationInModuleBodyReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("module M { public foo }")
    #expect(
        diagnostics.map(\.message)
            .contains("modifiers are not allowed on declarations")
    )
}

@Test func parseModifierOnImportReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("public import Foo")
    #expect(
        diagnostics.map(\.message)
            .contains("modifiers are not allowed on 'import' declaration")
    )
}

@Test func parseModifierOnVariableStatementIsAllowed() throws {
    let (_, diagnostics) = parseWithDiagnostics("func f() { public static var x = 1 }")
    #expect(diagnostics.isEmpty)
}

// MARK: - Self / SelfType / Super Expressions

@Test func parseSelfExpression() {
    let expr = firstExpression("self")
    let selfExpr = expr as? AST.SelfExpression
    #expect(selfExpr != nil)
}

@Test func parseSelfTypeExpression() {
    let expr = firstExpression("Self")
    let selfExpr = expr as? AST.SelfType
    #expect(selfExpr != nil)
}

@Test func parseSuperExpression() {
    let expr = firstExpression("super")
    let superExpr = expr as? AST.SuperExpression
    #expect(superExpr != nil)
}

// MARK: - Implicit Member Access

@Test func parseImplicitMemberAccess() throws {
    let expr = firstExpression(".foo")
    let implicit = expr as? AST.ImplicitMemberAccess
    try #require(implicit != nil)
    #expect(implicit!.name.value == "foo")
}

// MARK: - Parenthesized Expression

@Test func parseParenthesizedVariable() throws {
    let expr = firstExpression("(x)")
    let paren = expr as? AST.Parenthetical
    try #require(paren != nil)
    let varExpr = paren!.inner as? AST.Variable
    try #require(varExpr != nil)
    #expect(varExpr!.name.value == "x")
}

@Test func parseParenthesizedSequentialExpression() throws {
    let expr = firstExpression("(a + b)")
    let paren = expr as? AST.Parenthetical
    try #require(paren != nil)
    let seq = paren!.inner as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
    #expect(seq!.operands.count == 2)
}

// MARK: - Compound Assignment Operators

@Test func parsePlusAssignExpression() throws {
    let expr = firstExpression("x += 1")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.PlusAssign))
    try #require(seq!.operands.count == 2)
    let target = seq!.operands[0] as? AST.Variable
    try #require(target != nil)
    #expect(target!.name.value == "x")
    let value = seq!.operands[1] as? AST.IntegerLiteral
    try #require(value != nil)
    #expect(value!.value == 1)
}

@Test func parseMultiplyAssignExpression() throws {
    let expr = firstExpression("x *= 2")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.MultiplyAssign))
}

@Test func parseMinusAssignExpression() throws {
    let expr = firstExpression("x -= 3")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.MinusAssign))
}

// MARK: - Function Return Type

@Test func parseFunctionWithReturnType() throws {
    let statements = parseStatements("func foo() -> Int {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.returnTypeExpression != nil)
    let returnType = decl!.returnTypeExpression as? AST.Variable
    try #require(returnType != nil)
    #expect(returnType!.name.value == "Int")
}

@Test func parseFunctionWithReturnTypeAndBlockBody() throws {
    let statements = parseStatements("func foo() -> Int { return 42 }")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.returnTypeExpression != nil)
    if case let .Block(body) = decl!.body {
        try #require(body.count == 1)
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
    try #require(errors.count == 3)
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

@Test func parseFunctionWithReturnTypeAndExpressionBody() throws {
    let statements = parseStatements("func foo() -> Int = 42")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.returnTypeExpression != nil)
    let returnType = decl!.returnTypeExpression as? AST.Variable
    try #require(returnType != nil)
    #expect(returnType!.name.value == "Int")
    if case let .Expression(expr) = decl!.body {
        let lit = expr as? AST.IntegerLiteral
        try #require(lit != nil)
        #expect(lit!.value == 42)
    } else {
        Issue.record("expected expression body")
    }
}

// MARK: - Actor Declarations (previously dead code)

@Test func parseEmptyActor() throws {
    let statements = parseStatements("actor Foo {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Actor))
    #expect(decl!.name.value == "Foo")
    #expect(decl!.genericDecl == nil)
    #expect(decl!.conformances.isEmpty)
    #expect(decl!.body.isEmpty)
}

@Test func parseActorWithMembers() throws {
    let statements = parseStatements("actor Foo { let x func bar() {} }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    try #require(decl != nil)
    try #require(decl!.body.count == 2)
    let vd = decl!.body[0] as? AST.VariableDecl
    try #require(vd != nil)
    #expect(vd!.name.value == "x")
    let fd = decl!.body[1] as? AST.FunctionDecl
    try #require(fd != nil)
    #expect(fd!.name.value == "bar")
}

// MARK: - If Statements (previously dead code)

@Test func parseIfStatementWithEmptyThen() throws {
    let body = parseBlockStatements("func main() { if true {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    try #require(ifExpr != nil)
    let cond = ifExpr!.condition as? AST.BoolLiteral
    try #require(cond != nil)
    #expect(cond!.value == true)
    #expect(ifExpr!.then.isEmpty)
    #expect(ifExpr!.elseKind == nil)
}

@Test func parseIfStatementWithThenBody() throws {
    let body = parseBlockStatements("func main() { if x { return } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    try #require(ifExpr != nil)
    try #require(ifExpr!.then.count == 1)
    #expect(ifExpr!.then[0] is AST.Return)
}

@Test func parseIfElseStatement() throws {
    let body = parseBlockStatements("func main() { if x { return 1 } else { return 2 } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    try #require(ifExpr != nil)
    #expect(ifExpr!.then.count == 1)
    if case let .Block(elseBody) = ifExpr!.elseKind {
        #expect(elseBody.count == 1)
    } else {
        Issue.record("expected block else")
    }
}

@Test func parseIfElseIfChain() throws {
    let body = parseBlockStatements("func main() { if x {} else if y {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    try #require(ifExpr != nil)
    if case let .If(innerIf) = ifExpr!.elseKind {
        let cond = innerIf.condition as? AST.Variable
        try #require(cond != nil)
        #expect(cond!.name.value == "y")
    } else {
        Issue.record("expected else if")
    }
}

// MARK: - If as Expression (parsePrimary)

@Test func parseIfExpressionWithoutElse() throws {
    let expr = firstExpression("if true {}")
    let ifExpr = expr as? AST.If
    try #require(ifExpr != nil)
    let cond = ifExpr!.condition as? AST.BoolLiteral
    try #require(cond != nil)
    #expect(cond!.value == true)
    #expect(ifExpr!.then.isEmpty)
    #expect(ifExpr!.elseKind == nil)
}

@Test func parseIfExpressionAsAssignmentValue() throws {
    let expr = firstExpression("x = if true {} else {}")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Assign))
    try #require(seq!.operands.count == 2)
    let target = seq!.operands[0] as? AST.Variable
    try #require(target != nil)
    #expect(target!.name.value == "x")
    let ifExpr = seq!.operands[1] as? AST.If
    try #require(ifExpr != nil)
    if case let .Block(elseBody) = ifExpr!.elseKind {
        #expect(elseBody.isEmpty)
    } else {
        Issue.record("expected block else")
    }
}

@Test func parseIfExpressionAsReturnValue() throws {
    let body = parseBlockStatements("func main() { return if true { 1 } else { 2 } }")
    try #require(body.count == 1)
    let ret = body[0] as? AST.Return
    try #require(ret != nil)
    let ifExpr = ret!.value as? AST.If
    try #require(ifExpr != nil)
    #expect(ifExpr!.then.count == 1)
    if case let .Block(elseBody) = ifExpr!.elseKind {
        #expect(elseBody.count == 1)
    } else {
        Issue.record("expected block else")
    }
}

@Test func parseIfExpressionWithMemberAccess() throws {
    let expr = firstExpression("(if true { 1 } else { 2 }).foo")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "foo")
    let paren = member!.object as? AST.Parenthetical
    try #require(paren != nil)
    let ifExpr = paren!.inner as? AST.If
    #expect(ifExpr != nil)
}

@Test func parseIfExpressionElseIfChainAsValue() throws {
    let expr = firstExpression("x = if a {} else if b {} else {}")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    let ifExpr = seq!.operands[1] as? AST.If
    try #require(ifExpr != nil)
    if case let .If(innerIf) = ifExpr!.elseKind {
        if case .Block = innerIf.elseKind {
        } else {
            Issue.record("expected block else in inner if")
        }
    } else {
        Issue.record("expected else if")
    }
}

@Test func parseNestedIfExpressionInThenBody() throws {
    let body = parseBlockStatements("func main() { if x { if y {} } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let outerIf = exprStmt!.expression as? AST.If
    try #require(outerIf != nil)
    try #require(outerIf!.then.count == 1)
    let innerStmt = outerIf!.then[0] as? AST.ExpressionStatement
    try #require(innerStmt != nil)
    let innerIf = innerStmt!.expression as? AST.If
    try #require(innerIf != nil)
    let cond = innerIf!.condition as? AST.Variable
    try #require(cond != nil)
    #expect(cond!.name.value == "y")
}

@Test func parseIfExpressionWithComplexCondition() throws {
    let expr = firstExpression("if a + b == c {}")
    let ifExpr = expr as? AST.If
    try #require(ifExpr != nil)
    let seq = ifExpr!.condition as? AST.Sequential
    try #require(seq != nil)
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
        from: source.startIndex, to: source.index(after: plusIndex)
    )
    #expect(op.start.offset == afterPlusOffset)
}

@Test func parseOperatorOnlyReturnsErrorExpression() throws {
    let body = parseBlockStatements("func main() { + }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
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

@Test func parseOperatorOnlyInReturnTypeParsedAsSequential() throws {
    let statements = parseStatements("func foo() -> + {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let returnType = decl!.returnTypeExpression as? AST.Sequential
    try #require(returnType != nil)
    try #require(returnType!.ops.count == 1)
    #expect(returnType!.ops[0].kind == .Operator(.Plus))
    try #require(returnType!.operands.count == 1)
    #expect(returnType!.operands[0] is AST.Closure)
}

// MARK: - Import

@Test func parseImportSimple() throws {
    let statements = parseStatements("import A")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    try #require(decl.path.components.count == 1)
    if case let .Identifier(t) = decl.path.components[0] {
        #expect(t.value == "A")
    } else {
        Issue.record("expected identifier component")
    }
    if case let .WholeModule(alias) = decl.selector {
        #expect(alias == nil)
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportWildcard() throws {
    let statements = parseStatements("import A.*")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 1)
    if case .Wildcard = decl.selector {
    } else {
        Issue.record("expected wildcard selector")
    }
}

@Test func parseImportNestedPath() throws {
    let statements = parseStatements("import A.B")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    try #require(decl.path.components.count == 2)
    if case let .Identifier(t) = decl.path.components[1] {
        #expect(t.value == "B")
    } else {
        Issue.record("expected identifier component")
    }
    if case let .WholeModule(alias) = decl.selector {
        #expect(alias == nil)
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportNestedWildcard() throws {
    let statements = parseStatements("import A.B.*")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case .Wildcard = decl.selector {
    } else {
        Issue.record("expected wildcard selector")
    }
}

@Test func parseImportExplicitSelector() throws {
    let statements = parseStatements("import A.{self, B, C}")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 1)
    if case let .Explicit(items) = decl.selector {
        try #require(items.count == 3)
        if case .Self_ = items[0].kind {
        } else {
            Issue.record("expected self_ item")
        }
        #expect(items[0].alias == nil)
        if case let .Name(t) = items[1].kind {
            #expect(t.value == "B")
        } else {
            Issue.record("expected name item")
        }
        if case let .Name(t) = items[2].kind {
            #expect(t.value == "C")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportSelfPrefix() throws {
    let statements = parseStatements("import Self.A")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    try #require(decl.path.components.count == 2)
    if case .Self_ = decl.path.components[0] {
    } else {
        Issue.record("expected self_ path component")
    }
    if case let .Identifier(t) = decl.path.components[1] {
        #expect(t.value == "A")
    } else {
        Issue.record("expected identifier component")
    }
    if case let .WholeModule(alias) = decl.selector {
        #expect(alias == nil)
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportSelfPrefixExplicit() throws {
    let statements = parseStatements("import Self.{A, B}")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    try #require(decl.path.components.count == 1)
    if case .Self_ = decl.path.components[0] {
    } else {
        Issue.record("expected self_ path component")
    }
    if case let .Explicit(items) = decl.selector {
        try #require(items.count == 2)
        if case let .Name(t) = items[0].kind {
            #expect(t.value == "A")
        } else {
            Issue.record("expected name item")
        }
        if case let .Name(t) = items[1].kind {
            #expect(t.value == "B")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportAliasModule() throws {
    let statements = parseStatements("import A as B")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case let .WholeModule(alias) = decl.selector {
        #expect(alias?.value == "B")
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportAliasNestedModule() throws {
    let statements = parseStatements("import A.B as C")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case let .WholeModule(alias) = decl.selector {
        #expect(alias?.value == "C")
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportAliasExplicitItems() throws {
    let statements = parseStatements("import A.{B as b, C as c}")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case let .Explicit(items) = decl.selector {
        try #require(items.count == 2)
        if case let .Name(t) = items[0].kind {
            #expect(t.value == "B")
            #expect(items[0].alias?.value == "b")
        } else {
            Issue.record("expected name item")
        }
        if case let .Name(t) = items[1].kind {
            #expect(t.value == "C")
            #expect(items[1].alias?.value == "c")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportAliasSelfItem() throws {
    let statements = parseStatements("import A.{self as a, B as b}")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case let .Explicit(items) = decl.selector {
        try #require(items.count == 2)
        if case .Self_ = items[0].kind {
            #expect(items[0].alias?.value == "a")
        } else {
            Issue.record("expected self_ item")
        }
        if case let .Name(t) = items[1].kind {
            #expect(t.value == "B")
            #expect(items[1].alias?.value == "b")
        } else {
            Issue.record("expected name item")
        }
    } else {
        Issue.record("expected explicit selector")
    }
}

@Test func parseImportAliasUnderscore() throws {
    let statements = parseStatements("import A as _")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    if case let .WholeModule(alias) = decl.selector {
        #expect(alias?.value == "_")
    } else {
        Issue.record("expected wholeModule selector")
    }
}

@Test func parseImportNestedPathExplicitSelector() throws {
    let statements = parseStatements("import A.B.{self, C}")
    try #require(statements.count == 1)
    let decl = statements[0] as! AST.Import
    #expect(decl.path.components.count == 2)
    if case let .Explicit(items) = decl.selector {
        try #require(items.count == 2)
        if case .Self_ = items[0].kind {
        } else {
            Issue.record("expected self_ item")
        }
        if case let .Name(t) = items[1].kind {
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

@Test func parseImportNoPathError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    #expect(errors[0].message == "expected module path after 'import'")
}

@Test func parseImportEmptySelectorError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import A.{}")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    #expect(errors[0].message == "expected import item after '{'")
}

@Test func parseImportWildcardAliasError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import A.* as B")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    #expect(errors[0].message == "cannot alias a wildcard import")
}

@Test func parseImportSelfInMiddleError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import A.Self.B")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    #expect(errors[0].message == "'Self' can only appear at the beginning of an import path")
}

@Test func parseImportLowercaseSelfInPathError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import self.A")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    #expect(errors[0].message == "'self' is not allowed in import path, use 'Self' instead")
}

@Test func parseImportDoubleAliasError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import A as B as C")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    #expect(errors[0].message == "unexpected 'as'")
}

// MARK: - Labeled Statements

@Test func parseLabeledWhile() throws {
    let body = parseBlockStatements("func main() { outer: while true { break outer } }")
    try #require(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    try #require(labeled != nil)
    #expect(labeled!.label.value == "outer")
    let whileStmt = labeled!.body as? AST.While
    try #require(whileStmt != nil)
    try #require(whileStmt!.body.count == 1)
    let breakStmt = whileStmt!.body[0] as? AST.Break
    try #require(breakStmt != nil)
    #expect(breakStmt!.label?.value == "outer")
}

@Test func parseLabeledRepeatWhile() throws {
    let body = parseBlockStatements("func main() { end: repeat { } while false }")
    try #require(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    try #require(labeled != nil)
    #expect(labeled!.label.value == "end")
    let repeatStmt = labeled!.body as? AST.RepeatWhile
    #expect(repeatStmt != nil)
}

@Test func parseNestedLabels() throws {
    let body = parseBlockStatements("func main() { outer: inner: while true { } }")
    try #require(body.count == 1)
    let outer = body[0] as? AST.LabeledStatement
    try #require(outer != nil)
    #expect(outer!.label.value == "outer")
    let inner = outer!.body as? AST.LabeledStatement
    try #require(inner != nil)
    #expect(inner!.label.value == "inner")
    let whileStmt = inner!.body as? AST.While
    #expect(whileStmt != nil)
}

@Test func parseLabeledReturn() throws {
    let body = parseBlockStatements("func main() { end: return 0 }")
    try #require(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    try #require(labeled != nil)
    #expect(labeled!.label.value == "end")
    let returnStmt = labeled!.body as? AST.Return
    #expect(returnStmt != nil)
}

@Test func parseLabeledEmptyStatement() throws {
    let body = parseBlockStatements("func main() { foo: ; }")
    try #require(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    try #require(labeled != nil)
    #expect(labeled!.label.value == "foo")
    let empty = labeled!.body as? AST.EmptyStatement
    #expect(empty != nil)
}

@Test func parseLabeledExpressionStatement() throws {
    let body = parseBlockStatements("func main() { start: x }")
    try #require(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    try #require(labeled != nil)
    #expect(labeled!.label.value == "start")
    let exprStmt = labeled!.body as? AST.ExpressionStatement
    #expect(exprStmt != nil)
}

@Test func parseLabelWithNewline() throws {
    let body = parseBlockStatements("func main() {\nouter:\n while true {}\n}")
    try #require(body.count == 1)
    let labeled = body[0] as? AST.LabeledStatement
    try #require(labeled != nil)
    #expect(labeled!.label.value == "outer")
    let whileStmt = labeled!.body as? AST.While
    #expect(whileStmt != nil)
}

@Test func parseGotoWithLabeledStatement() throws {
    let body = parseBlockStatements("func main() { goto end\n end: return 0 }")
    try #require(body.count == 2)
    let gotoStmt = body[0] as? AST.Goto
    try #require(gotoStmt != nil)
    #expect(gotoStmt!.label.value == "end")
    let labeled = body[1] as? AST.LabeledStatement
    try #require(labeled != nil)
    #expect(labeled!.label.value == "end")
    let returnStmt = labeled!.body as? AST.Return
    #expect(returnStmt != nil)
}

@Test func parseLabeledStatementSourceRangeCoversInnerOnly() throws {
    let body = parseBlockStatements("func main() { outer: while true {} }")
    let labeled = body[0] as? AST.LabeledStatement
    try #require(labeled != nil)
    let whileStmt = labeled!.body as? AST.While
    try #require(whileStmt != nil)
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
    try #require(errors.count >= 1)
    #expect(errors[0].message == "expected statement after label 'foo:'")
}

// MARK: - Angle Bracket Generics vs Comparison

@Test func parseBareGenericSingleArg() throws {
    let expr = firstExpression("Array<Int32>")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 2)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Operator(.Greater))
    try #require(seq!.operands.count == 2)
    let base = seq!.operands[0] as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Array")
    let arg = seq!.operands[1] as? AST.Variable
    try #require(arg != nil)
    #expect(arg!.name.value == "Int32")
}

@Test func parseBareGenericMultipleArgs() throws {
    let expr = firstExpression("Array<Int32, String>")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 3)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Separator(.Comma))
    #expect(seq!.ops[2].kind == .Operator(.Greater))
    try #require(seq!.operands.count == 3)
    let arg0 = seq!.operands[0] as? AST.Variable
    try #require(arg0 != nil)
    #expect(arg0!.name.value == "Array")
    let arg1 = seq!.operands[1] as? AST.Variable
    try #require(arg1 != nil)
    #expect(arg1!.name.value == "Int32")
    let arg2 = seq!.operands[2] as? AST.Variable
    try #require(arg2 != nil)
    #expect(arg2!.name.value == "String")
}

@Test func parseComparisonWithAngleBrackets() throws {
    let expr = firstExpression("1<2>3")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 2)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Operator(.Greater))
    try #require(seq!.operands.count == 3)
    let first = seq!.operands[0] as? AST.IntegerLiteral
    try #require(first != nil)
    #expect(first!.value == 1)
    let second = seq!.operands[1] as? AST.IntegerLiteral
    try #require(second != nil)
    #expect(second!.value == 2)
    let third = seq!.operands[2] as? AST.IntegerLiteral
    try #require(third != nil)
    #expect(third!.value == 3)
}

@Test func parseGenericApplicationWithCall() throws {
    let expr = firstExpression("Array<Int32>()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.Sequential
    try #require(callee != nil)
    #expect(callee!.ops.count == 2)
    let base = callee!.operands[0] as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Array")
    let arg = callee!.operands[1] as? AST.Variable
    try #require(arg != nil)
    #expect(arg!.name.value == "Int32")
    #expect(call!.arguments.isEmpty)
}

@Test func parseSimpleCall() throws {
    let expr = firstExpression("foo()")
    let call = expr as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.Variable
    try #require(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(call!.arguments.isEmpty)
}

@Test func parseParenthesizedAfterOperator() throws {
    let expr = firstExpression("a + (b)")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
    try #require(seq!.operands.count == 2)
    let first = seq!.operands[0] as? AST.Variable
    try #require(first != nil)
    #expect(first!.name.value == "a")
    let second = seq!.operands[1] as? AST.Parenthetical
    try #require(second != nil)
    let inner = second!.inner as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "b")
}

@Test func parseCallThenMemberAccess() throws {
    let expr = firstExpression("foo().bar")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    let call = member!.object as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.Variable
    try #require(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(member!.member.value == "bar")
}

@Test func parseGenericWithMemberAccess() throws {
    let expr = firstExpression("Array<Int32>.f")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "f")
    let base = member!.object as? AST.Sequential
    #expect(base != nil)
    try #require(base!.ops.count == 2)
    #expect(base!.ops[0].kind == .Operator(.Less))
    #expect(base!.ops[1].kind == .Operator(.Greater))
    try #require(base!.operands.count == 2)
    let array = base!.operands[0] as? AST.Variable
    try #require(array != nil)
    #expect(array!.name.value == "Array")
    let arg = base!.operands[1] as? AST.Variable
    try #require(arg != nil)
    #expect(arg!.name.value == "Int32")
}

@Test func parseGenericWithMemberAccessAndCall() throws {
    let expr = firstExpression("Array<Int32>.f()")
    let call = expr as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.isEmpty)
    let member = call!.callee as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "f")
    let baseSeq = member!.object as? AST.Sequential
    #expect(baseSeq != nil)
    #expect(baseSeq!.ops.count == 2)
    #expect(baseSeq!.operands[0] is AST.Variable)
    #expect((baseSeq!.operands[0] as! AST.Variable).name.value == "Array")
    #expect(baseSeq!.operands[1] is AST.Variable)
    #expect((baseSeq!.operands[1] as! AST.Variable).name.value == "Int32")
}

@Test func parseGenericWithMemberAccessAndCallArg() throws {
    let expr = firstExpression("Array<Int32>.f(1)")
    let call = expr as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 1)
    let argVal = call!.arguments[0].value as? AST.IntegerLiteral
    try #require(argVal != nil)
    #expect(argVal!.value == 1)
    let member = call!.callee as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "f")
}

@Test func parseGenericMultiArgWithMemberAccess() throws {
    let expr = firstExpression("Array<Int32, String>.foo")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "foo")
    let baseSeq = member!.object as? AST.Sequential
    #expect(baseSeq != nil)
    try #require(baseSeq!.operands.count == 3)
    #expect((baseSeq!.operands[0] as? AST.Variable)?.name.value == "Array")
    #expect((baseSeq!.operands[1] as? AST.Variable)?.name.value == "Int32")
    #expect((baseSeq!.operands[2] as? AST.Variable)?.name.value == "String")
}

@Test func parseCallOnGenericThenMemberAccess() throws {
    let expr = firstExpression("Producer<Item>().result")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "result")
    let call = member!.object as? AST.Call
    try #require(call != nil)
    let calleeSeq = call!.callee as? AST.Sequential
    try #require(calleeSeq != nil)
    try #require(calleeSeq!.operands.count == 2)
    #expect((calleeSeq!.operands[0] as? AST.Variable)?.name.value == "Producer")
    #expect((calleeSeq!.operands[1] as? AST.Variable)?.name.value == "Item")
    #expect(call!.arguments.isEmpty)
}

@Test func parseComparisonThenMemberAccess() throws {
    let expr = firstExpression("1 < 2 && 3 > x.foo")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    let lastOperand = seq!.operands.last
    let member = lastOperand as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "foo")
    let obj = member!.object as? AST.Variable
    try #require(obj != nil)
    #expect(obj!.name.value == "x")
}

@Test func parseNestedGenericRightShift() throws {
    let expr = firstExpression("Array<Array<Int32>>")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 3)
    #expect(seq!.ops[0].kind == .Operator(.Less))
    #expect(seq!.ops[1].kind == .Operator(.Less))
    #expect(seq!.ops[2].kind == .Operator(.RightShift))
    try #require(seq!.operands.count == 3)
    let arg0 = seq!.operands[0] as? AST.Variable
    try #require(arg0 != nil)
    #expect(arg0!.name.value == "Array")
    let arg1 = seq!.operands[1] as? AST.Variable
    try #require(arg1 != nil)
    #expect(arg1!.name.value == "Array")
    let arg2 = seq!.operands[2] as? AST.Variable
    try #require(arg2 != nil)
    #expect(arg2!.name.value == "Int32")
}

@Test func parseEmptyArrayLiteral() throws {
    let expr = firstExpression("[]")
    let arr = expr as? AST.ArrayLiteral
    try #require(arr != nil)
    #expect(arr!.elements.isEmpty)
}

@Test func parseSingleElementArrayLiteral() throws {
    let expr = firstExpression("[1]")
    let arr = expr as? AST.ArrayLiteral
    try #require(arr != nil)
    try #require(arr!.elements.count == 1)
    let lit = arr!.elements[0] as? AST.IntegerLiteral
    try #require(lit != nil)
    #expect(lit!.value == 1)
}

@Test func parseMultiElementArrayLiteral() throws {
    let expr = firstExpression("[1, 2, 3]")
    let arr = expr as? AST.ArrayLiteral
    try #require(arr != nil)
    try #require(arr!.elements.count == 3)
    for i in 0 ..< 3 {
        let lit = arr!.elements[i] as? AST.IntegerLiteral
        try #require(lit != nil)
        #expect(lit!.value == Int128(i + 1))
    }
}

@Test func parseArrayLiteralWithTrailingComma() throws {
    let expr = firstExpression("[1, 2,]")
    let arr = expr as? AST.ArrayLiteral
    try #require(arr != nil)
    #expect(arr!.elements.count == 2)
}

@Test func parseArrayLiteralWithExpressions() throws {
    let expr = firstExpression("[a + b, c]")
    let arr = expr as? AST.ArrayLiteral
    try #require(arr != nil)
    try #require(arr!.elements.count == 2)
    let seq = arr!.elements[0] as? AST.Sequential
    #expect(seq != nil)
    let v = arr!.elements[1] as? AST.Variable
    try #require(v != nil)
    #expect(v!.name.value == "c")
}

@Test func parseEmptyDictionaryLiteral() throws {
    let expr = firstExpression("[:]")
    let dict = expr as? AST.DictionaryLiteral
    try #require(dict != nil)
    #expect(dict!.entries.isEmpty)
}

@Test func parseSingleEntryDictionaryLiteral() throws {
    let expr = firstExpression("[1: 2]")
    let dict = expr as? AST.DictionaryLiteral
    try #require(dict != nil)
    try #require(dict!.entries.count == 1)
    let key = dict!.entries[0].key as? AST.IntegerLiteral
    try #require(key != nil)
    #expect(key!.value == 1)
    let val = dict!.entries[0].value as? AST.IntegerLiteral
    try #require(val != nil)
    #expect(val!.value == 2)
}

@Test func parseMultiEntryDictionaryLiteral() throws {
    let expr = firstExpression("[1: 2, 3: 4]")
    let dict = expr as? AST.DictionaryLiteral
    try #require(dict != nil)
    try #require(dict!.entries.count == 2)
    let key0 = dict!.entries[0].key as? AST.IntegerLiteral
    #expect(key0!.value == 1)
    let val0 = dict!.entries[0].value as? AST.IntegerLiteral
    #expect(val0!.value == 2)
    let key1 = dict!.entries[1].key as? AST.IntegerLiteral
    #expect(key1!.value == 3)
    let val1 = dict!.entries[1].value as? AST.IntegerLiteral
    #expect(val1!.value == 4)
}

@Test func parseDictionaryLiteralWithTrailingComma() throws {
    let expr = firstExpression("[1: 2,]")
    let dict = expr as? AST.DictionaryLiteral
    try #require(dict != nil)
    #expect(dict!.entries.count == 1)
}

@Test func parseSubscriptSingleIndex() throws {
    let expr = firstExpression("arr[1]")
    let sub = expr as? AST.Subscript
    try #require(sub != nil)
    let base = sub!.base as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "arr")
    try #require(sub!.arguments.count == 1)
    #expect(sub!.arguments[0].label == nil)
    let idx = sub!.arguments[0].value as? AST.IntegerLiteral
    try #require(idx != nil)
    #expect(idx!.value == 1)
}

@Test func parseSubscriptMultiIndex() throws {
    let expr = firstExpression("arr[1, 2]")
    let sub = expr as? AST.Subscript
    try #require(sub != nil)
    try #require(sub!.arguments.count == 2)
    #expect(sub!.arguments[0].label == nil)
    #expect(sub!.arguments[1].label == nil)
    let idx0 = sub!.arguments[0].value as? AST.IntegerLiteral
    #expect(idx0!.value == 1)
    let idx1 = sub!.arguments[1].value as? AST.IntegerLiteral
    #expect(idx1!.value == 2)
}

@Test func parseSubscriptWithLabel() throws {
    let expr = firstExpression("arr[row: 1, col: 2]")
    let sub = expr as? AST.Subscript
    try #require(sub != nil)
    try #require(sub!.arguments.count == 2)
    #expect(sub!.arguments[0].label?.value == "row")
    #expect(sub!.arguments[1].label?.value == "col")
    let val0 = sub!.arguments[0].value as? AST.IntegerLiteral
    #expect(val0!.value == 1)
    let val1 = sub!.arguments[1].value as? AST.IntegerLiteral
    #expect(val1!.value == 2)
}

@Test func parseSubscriptWithTrailingComma() throws {
    let expr = firstExpression("arr[1, 2,]")
    let sub = expr as? AST.Subscript
    try #require(sub != nil)
    #expect(sub!.arguments.count == 2)
}

@Test func parseChainedSubscript() throws {
    let expr = firstExpression("arr[0][1]")
    let outer = expr as? AST.Subscript
    try #require(outer != nil)
    let inner = outer!.base as? AST.Subscript
    try #require(inner != nil)
    let base = inner!.base as? AST.Variable
    #expect(base!.name.value == "arr")
    #expect(outer!.arguments.count == 1)
    #expect(inner!.arguments.count == 1)
}

@Test func parseSubscriptThenMemberAccess() throws {
    let expr = firstExpression("arr[0].field")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "field")
    let sub = member!.object as? AST.Subscript
    try #require(sub != nil)
    let base = sub!.base as? AST.Variable
    #expect(base!.name.value == "arr")
}

@Test func parseMemberAccessThenSubscript() throws {
    let expr = firstExpression("obj.field[0]")
    let sub = expr as? AST.Subscript
    try #require(sub != nil)
    let member = sub!.base as? AST.MemberAccess
    try #require(member != nil)
    #expect(member!.member.value == "field")
    let obj = member!.object as? AST.Variable
    #expect(obj!.name.value == "obj")
}

@Test func parseCallWithSingleArgument() throws {
    let expr = firstExpression("foo(1)")
    let call = expr as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 1)
    #expect(call!.arguments[0].label == nil)
    let arg = call!.arguments[0].value as? AST.IntegerLiteral
    try #require(arg != nil)
    #expect(arg!.value == 1)
}

@Test func parseCallWithMultipleArguments() throws {
    let expr = firstExpression("foo(1, 2, 3)")
    let call = expr as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 3)
    for i in 0 ..< 3 {
        let arg = call!.arguments[i].value as? AST.IntegerLiteral
        try #require(arg != nil)
        #expect(arg!.value == Int128(i + 1))
    }
}

@Test func parseCallWithLabeledArguments() throws {
    let expr = firstExpression("foo(a: 1, b: 2)")
    let call = expr as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 2)
    #expect(call!.arguments[0].label?.value == "a")
    #expect(call!.arguments[1].label?.value == "b")
    let val0 = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(val0!.value == 1)
    let val1 = call!.arguments[1].value as? AST.IntegerLiteral
    #expect(val1!.value == 2)
}

@Test func parseCallWithMixedArguments() throws {
    let expr = firstExpression("foo(1, b: 2)")
    let call = expr as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 2)
    #expect(call!.arguments[0].label == nil)
    #expect(call!.arguments[1].label?.value == "b")
}

@Test func parseCallWithTrailingComma() throws {
    let expr = firstExpression("foo(1, 2,)")
    let call = expr as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.count == 2)
}

@Test func parseCallWithExpressionArgument() throws {
    let expr = firstExpression("foo(a + b)")
    let call = expr as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 1)
    let seq = call!.arguments[0].value as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
}

@Test func parseFunctionDeclWithSingleParameter() throws {
    let statements = parseStatements("func foo(a: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].label?.value == "a")
    #expect(decl!.parameters[0].name.value == "a")
    let type = decl!.parameters[0].type as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int")
    #expect(decl!.parameters[0].defaultValue == nil)
}

@Test func parseFunctionDeclWithMultipleParameters() throws {
    let statements = parseStatements("func foo(a: Int, b: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 2)
    #expect(decl!.parameters[0].name.value == "a")
    #expect(decl!.parameters[1].name.value == "b")
}

@Test func parseFunctionDeclWithWildcardLabel() throws {
    let statements = parseStatements("func foo(_ a: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].label == nil)
    #expect(decl!.parameters[0].name.value == "a")
}

@Test func parseFunctionDeclWithExplicitLabel() throws {
    let statements = parseStatements("func foo(by a: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].label?.value == "by")
    #expect(decl!.parameters[0].name.value == "a")
}

@Test func parseFunctionDeclWithDefaultValue() throws {
    let statements = parseStatements("func foo(a: Int = 42) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    let defVal = decl!.parameters[0].defaultValue as? AST.IntegerLiteral
    try #require(defVal != nil)
    #expect(defVal!.value == 42)
}

@Test func parseFunctionDeclWithMixedParameters() throws {
    let statements = parseStatements("func foo(_ a: Int, b: Int = 0, by c: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 3)
    #expect(decl!.parameters[0].label == nil)
    #expect(decl!.parameters[0].name.value == "a")
    #expect(decl!.parameters[1].label?.value == "b")
    #expect(decl!.parameters[1].name.value == "b")
    let defVal = decl!.parameters[1].defaultValue as? AST.IntegerLiteral
    try #require(defVal != nil)
    #expect(defVal!.value == 0)
    #expect(decl!.parameters[2].label?.value == "by")
    #expect(decl!.parameters[2].name.value == "c")
}

@Test func parseFunctionDeclWithTrailingComma() throws {
    let statements = parseStatements("func foo(a: Int,) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.parameters.count == 1)
}

// MARK: - Variadic Type

@Test func parseFunctionDeclWithVariadicType() throws {
    let statements = parseStatements("func foo(_ xs: Int...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    try #require(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Int")
    #expect(variadic!.token.kind == .Operator(.DotDotDot))
}

@Test func parseFunctionDeclWithLabeledVariadicType() throws {
    let statements = parseStatements("func foo(items: Int32...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    try #require(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base!.name.value == "Int32")
}

@Test func parseFunctionDeclWithTupleVariadicType() throws {
    let statements = parseStatements("func foo(_ xs: (Int, String)...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    try #require(variadic != nil)
    let tuple = variadic!.base as? AST.Tuple
    try #require(tuple != nil)
    #expect(tuple!.elements.count == 2)
}

@Test func parseVariableDeclWithVariadicType() throws {
    let statements = parseStatements("let x: Int...")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    let variadic = decl!.typeExpression as? AST.VariadicType
    try #require(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base!.name.value == "Int")
}

@Test func parseEnumCaseWithVariadicType() throws {
    let statements = parseStatements("enum E { case a(Int...) }")
    let enumDecl = statements[0] as? AST.EnumDecl
    try #require(enumDecl != nil)
    let caseDecl = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(caseDecl != nil)
    let variadic = caseDecl!.elements[0].associatedValues[0].typeExpression as? AST.VariadicType
    try #require(variadic != nil)
    let base = variadic!.base as? AST.Variable
    #expect(base!.name.value == "Int")
}

@Test func parseRangeExpressionStillSequential() throws {
    let statements = parseStatements("let r = 1...5")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    let seq = decl!.initializer as? AST.Sequential
    try #require(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    #expect(seq!.operands.count == 2)
}

@Test func parseFunctionDeclNonVariadicTypeUnaffected() throws {
    let statements = parseStatements("func foo(_ xs: Int) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let type = decl!.parameters[0].type as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int")
}

// MARK: - C-Style Vararg

@Test func parseFunctionDeclWithCStyleVararg() throws {
    let statements = parseStatements("func f(i: Int32, ...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    #expect(decl!.parameters[0].name.value == "i")
    try #require(decl!.varargToken != nil)
    #expect(decl!.varargToken!.kind == .Operator(.DotDotDot))
}

@Test func parseFunctionDeclBareVararg() throws {
    let statements = parseStatements("func f(...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.parameters.count == 0)
    #expect(decl!.varargToken != nil)
}

@Test func parseFunctionDeclWithoutVararg() throws {
    let statements = parseStatements("func f(i: Int32) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.varargToken == nil)
}

@Test func parseFunctionDeclCStyleVarargAfterSwiftVariadic() throws {
    let statements = parseStatements("func f(_ xs: Int..., ...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    let variadic = decl!.parameters[0].type as? AST.VariadicType
    #expect(variadic != nil)
    #expect(decl!.varargToken != nil)
}

@Test func parseSwiftVariadicDoesNotSetVarargToken() throws {
    let statements = parseStatements("func f(_ xs: Int...) {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.varargToken == nil)
}

@Test func parseMemberAccessInteger() throws {
    let expr = firstExpression("tuple.0")
    let member = expr as? AST.MemberAccess
    try #require(member != nil)
    let obj = member!.object as? AST.Variable
    #expect(obj!.name.value == "tuple")
    #expect(member!.member.kind == .IntegerLiteral(0))
}

@Test func parseArrayLiteralInExpression() throws {
    let expr = firstExpression("a + [1, 2]")
    let seq = expr as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
    try #require(seq!.operands.count == 2)
    let left = seq!.operands[0] as? AST.Variable
    #expect(left!.name.value == "a")
    let right = seq!.operands[1] as? AST.ArrayLiteral
    try #require(right != nil)
    #expect(right!.elements.count == 2)
}

// MARK: - Optional Binding (if let / guard let / while let)

@Test func parseIfLetBasic() throws {
    let body = parseBlockStatements("func main() { if let x = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    try #require(ifExpr != nil)
    let binding = ifExpr!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Let))
    #expect(binding!.name.value == "x")
    #expect(binding!.typeExpression == nil)
    let value = binding!.value as? AST.Variable
    #expect(value!.name.value == "a")
}

@Test func parseIfLetWithTypeAnnotation() throws {
    let body = parseBlockStatements("func main() { if let x: Int32 = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let binding = ifExpr!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    #expect(binding!.typeExpression != nil)
}

@Test func parseIfVar() throws {
    let body = parseBlockStatements("func main() { if var x = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let binding = ifExpr!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Var))
}

@Test func parseIfLetWithAndCombination() throws {
    let body = parseBlockStatements("func main() { if (let x = a) && (let y = b) {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let seq = ifExpr!.condition as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.And))
    let lhs = seq!.operands[0] as? AST.Parenthetical
    try #require(lhs != nil)
    let lhsBinding = lhs!.inner as? AST.OptionalBinding
    try #require(lhsBinding != nil)
    #expect(lhsBinding!.name.value == "x")
    let rhs = seq!.operands[1] as? AST.Parenthetical
    try #require(rhs != nil)
    let rhsBinding = rhs!.inner as? AST.OptionalBinding
    try #require(rhsBinding != nil)
    #expect(rhsBinding!.name.value == "y")
}

@Test func parseGuardLet() throws {
    let body = parseBlockStatements("func main() { guard let x = a else {} }")
    try #require(body.count == 1)
    let guardStmt = body[0] as? AST.Guard
    try #require(guardStmt != nil)
    let binding = guardStmt!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseWhileLet() throws {
    let body = parseBlockStatements("func main() { while let x = a {} }")
    try #require(body.count == 1)
    let whileStmt = body[0] as? AST.While
    try #require(whileStmt != nil)
    let binding = whileStmt!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseIfLetShorthand() throws {
    let body = parseBlockStatements("func main() { if let x {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    try #require(exprStmt != nil)
    let ifExpr = exprStmt!.expression as? AST.If
    try #require(ifExpr != nil)
    let binding = ifExpr!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Let))
    #expect(binding!.name.value == "x")
    #expect(binding!.typeExpression == nil)
    let value = binding!.value as? AST.Variable
    try #require(value != nil)
    #expect(value!.name.value == "x")
}

@Test func parseIfVarShorthand() throws {
    let body = parseBlockStatements("func main() { if var x {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let binding = ifExpr!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Var))
    #expect(binding!.name.value == "x")
}

@Test func parseIfLetShorthandWithTypeAnnotation() throws {
    let body = parseBlockStatements("func main() { if let x: Int32 {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let binding = ifExpr!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    #expect(binding!.typeExpression != nil)
    let value = binding!.value as? AST.Variable
    try #require(value != nil)
    #expect(value!.name.value == "x")
}

@Test func parseGuardLetShorthand() throws {
    let body = parseBlockStatements("func main() { guard let x else {} }")
    try #require(body.count == 1)
    let guardStmt = body[0] as? AST.Guard
    try #require(guardStmt != nil)
    let binding = guardStmt!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    let value = binding!.value as? AST.Variable
    try #require(value != nil)
    #expect(value!.name.value == "x")
}

@Test func parseWhileLetShorthand() throws {
    let body = parseBlockStatements("func main() { while let x {} }")
    try #require(body.count == 1)
    let whileStmt = body[0] as? AST.While
    try #require(whileStmt != nil)
    let binding = whileStmt!.condition as? AST.OptionalBinding
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    let value = binding!.value as? AST.Variable
    try #require(value != nil)
    #expect(value!.name.value == "x")
}

// MARK: - Case Match (if case)

@Test func parseIfCaseDotName() throws {
    let body = parseBlockStatements("func main() { if case .foo = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let pattern = caseMatch!.pattern as? AST.ImplicitMemberAccess
    try #require(pattern != nil)
    #expect(pattern!.name.value == "foo")
    let subject = caseMatch!.subject as? AST.Variable
    #expect(subject!.name.value == "a")
}

@Test func parseIfCaseWithBinding() throws {
    let body = parseBlockStatements("func main() { if case .foo(let x) = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let call = caseMatch!.pattern as? AST.Call
    try #require(call != nil)
    let member = call!.callee as? AST.ImplicitMemberAccess
    #expect(member!.name.value == "foo")
    try #require(call!.arguments.count == 1)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Let))
    #expect(binding!.name.value == "x")
}

@Test func parseIfCaseNestedPattern() throws {
    let body = parseBlockStatements("func main() { if case .some(.some(let x)) = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let outerCall = caseMatch!.pattern as? AST.Call
    try #require(outerCall != nil)
    let outerMember = outerCall!.callee as? AST.ImplicitMemberAccess
    #expect(outerMember!.name.value == "some")
    let innerCall = outerCall!.arguments[0].value as? AST.Call
    try #require(innerCall != nil)
    let innerMember = innerCall!.callee as? AST.ImplicitMemberAccess
    #expect(innerMember!.name.value == "some")
    let binding = innerCall!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseIfCaseQualified() throws {
    let body = parseBlockStatements("func main() { if case Color.red = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let memberAccess = caseMatch!.pattern as? AST.MemberAccess
    try #require(memberAccess != nil)
    let base = memberAccess!.object as? AST.Variable
    #expect(base!.name.value == "Color")
    #expect(memberAccess!.member.value == "red")
}

@Test func parseIfCaseWildcard() throws {
    let body = parseBlockStatements("func main() { if case _ = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let wildcard = caseMatch!.pattern as? AST.WildcardPattern
    #expect(wildcard != nil)
}

// MARK: - Enum Declarations

@Test func parseBasicEnum() throws {
    let stmts = parseStatements("enum Color { case red\ncase green\ncase blue }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    try #require(enumDecl != nil)
    #expect(enumDecl!.name.value == "Color")
    #expect(enumDecl!.genericDecl == nil)
    #expect(enumDecl!.conformances.isEmpty)
    try #require(enumDecl!.body.count == 3)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0 != nil)
    try #require(case0!.elements.count == 1)
    #expect(case0!.elements[0].name.value == "red")
    #expect(case0!.elements[0].associatedValues.isEmpty)
    #expect(case0!.elements[0].rawValue == nil)
}

@Test func parseEnumWithAssociatedValues() throws {
    let stmts = parseStatements("enum Result { case ok(Int32)\ncase err(String) }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    try #require(enumDecl!.body.count == 2)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].name.value == "ok")
    try #require(case0!.elements[0].associatedValues.count == 1)
    #expect(case0!.elements[0].associatedValues[0].label == nil)
    let case1 = enumDecl!.body[1] as? AST.EnumCaseDecl
    #expect(case1!.elements[0].name.value == "err")
    #expect(case1!.elements[0].associatedValues.count == 1)
}

@Test func parseEnumWithNamedAssociatedValues() throws {
    let stmts = parseStatements("enum Point { case coord(x: Int32, y: Int32) }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    try #require(case0!.elements[0].associatedValues.count == 2)
    #expect(case0!.elements[0].associatedValues[0].label?.value == "x")
    #expect(case0!.elements[0].associatedValues[1].label?.value == "y")
}

@Test func parseEnumGeneric() throws {
    let stmts = parseStatements("enum Result<T> { case ok(T)\ncase err(String) }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    try #require(enumDecl != nil)
    #expect(enumDecl!.genericDecl != nil)
    try #require(enumDecl!.body.count == 2)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].name.value == "ok")
    let case1 = enumDecl!.body[1] as? AST.EnumCaseDecl
    #expect(case1!.elements[0].name.value == "err")
}

@Test func parseEnumWithRawValue() throws {
    let stmts = parseStatements("enum Color: Int32 { case red = 1\ncase green = 2 }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    #expect(enumDecl!.conformances.count == 1)
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].rawValue != nil)
    let rawVal = case0!.elements[0].rawValue as? AST.IntegerLiteral
    #expect(rawVal != nil)
}

@Test func parseIndirectEnum() throws {
    let stmts = parseStatements("indirect enum Tree { case node(Int32, Tree, Tree)\ncase leaf }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    try #require(enumDecl != nil)
    try #require(enumDecl!.modifiers.count == 1)
    #expect(modifierKind(enumDecl!.modifiers[0].kind, equals: .Indirect))
    let case0 = enumDecl!.body[0] as? AST.EnumCaseDecl
    #expect(case0!.elements[0].associatedValues.count == 3)
}

@Test func parseEnumWithConformance() throws {
    let stmts = parseStatements("enum Foo: Equatable { case a\ncase b }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    try #require(enumDecl!.conformances.count == 1)
    let conf = enumDecl!.conformances[0] as? AST.Variable
    #expect(conf!.name.value == "Equatable")
}

@Test func parseEnumMultipleCasesOnOneLine() throws {
    let stmts = parseStatements("enum Color { case red, green, blue }")
    try #require(stmts.count == 1)
    let enumDecl = stmts[0] as? AST.EnumDecl
    try #require(enumDecl!.body.count == 1)
    let caseDecl = enumDecl!.body[0] as? AST.EnumCaseDecl
    try #require(caseDecl!.elements.count == 3)
    #expect(caseDecl!.elements[0].name.value == "red")
    #expect(caseDecl!.elements[1].name.value == "green")
    #expect(caseDecl!.elements[2].name.value == "blue")
}

// MARK: - Match with Bindings

@Test func parseMatchAtBindingPattern() throws {
    let expr = firstExpression("match a { let x @ .some => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    try #require(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseMatchAtBindingWithArguments() throws {
    let expr = firstExpression("match a { let x @ .some(let y) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    try #require(binding != nil)
    let call = binding!.subpattern as? AST.Call
    try #require(call != nil)
    let inner = call!.arguments[0].value as? AST.BindingPattern
    try #require(inner != nil)
    #expect(inner!.name.value == "y")
}

@Test func parseIfCaseAtBindingPattern() throws {
    let body = parseBlockStatements("func main() { if case let x @ .some = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let binding = caseMatch!.pattern as? AST.BindingPattern
    try #require(binding != nil)
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    try #require(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseNestedAtBindingPattern() throws {
    let expr = firstExpression("match a { .foo(let x @ .some) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    try #require(call != nil)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    try #require(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseWildcardAtBindingPattern() throws {
    let expr = firstExpression("match a { _ @ .some => 1 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let subpattern = matchExpr!.cases[0].patterns[0] as? AST.ImplicitMemberAccess
    try #require(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseBindingPatternWithoutSubpattern() throws {
    let expr = firstExpression("match a { .some(let x) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.subpattern == nil)
}

// MARK: - Typed Binding in Patterns

@Test func parseNestedTypedBindingPattern() throws {
    let expr = firstExpression("match a { .foo(let x: Int) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    try #require(call != nil)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    let type = binding!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int")
}

@Test func parseMatchTypedBindingPattern() throws {
    let expr = firstExpression("match a { let x: Int => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    try #require(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int")
    #expect(binding!.subpattern == nil)
}

@Test func parseIfCaseTypedBindingPattern() throws {
    let body = parseBlockStatements("func main() { if case let x: Int = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let binding = caseMatch!.pattern as? AST.BindingPattern
    try #require(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int")
}

@Test func parseForTypedBindingPattern() throws {
    let body = parseBlockStatements("func main() { for let x: Int in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let binding = forStmt!.pattern as? AST.BindingPattern
    try #require(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int")
}

@Test func parseCatchTypedBindingPattern() throws {
    let body = parseBlockStatements("func main() { do { } catch let e: Int32 { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let doExpr = exprStmt!.expression as? AST.Do
    try #require(doExpr != nil)
    let binding = doExpr!.catches[0].pattern as? AST.BindingPattern
    try #require(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int32")
}

@Test func parseTypedBindingWithAtSubpattern() throws {
    let expr = firstExpression("match a { let x: Int @ .some => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let binding = matchExpr!.cases[0].patterns[0] as? AST.BindingPattern
    try #require(binding != nil)
    let type = binding!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int")
    let subpattern = binding!.subpattern as? AST.ImplicitMemberAccess
    try #require(subpattern != nil)
    #expect(subpattern!.name.value == "some")
}

@Test func parseBindingPatternWithoutType() throws {
    let expr = firstExpression("match a { .some(let x) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let call = matchExpr!.cases[0].patterns[0] as? AST.Call
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.typeExpression == nil)
}

// MARK: - As Binding in Patterns

@Test func parseMatchAsBindingPattern() throws {
    let expr = firstExpression("match a { let x as Int32 => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let asPattern = matchExpr!.cases[0].patterns[0] as? AST.AsPattern
    #expect(asPattern != nil)
    let binding = asPattern!.pattern as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    let type = asPattern!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "Int32")
}

@Test func parseIfCaseAsBindingPattern() throws {
    let body = parseBlockStatements("func main() { if case let x as String = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let asPattern = caseMatch!.pattern as? AST.AsPattern
    #expect(asPattern != nil)
    let type = asPattern!.typeExpression as? AST.Variable
    try #require(type != nil)
    #expect(type!.name.value == "String")
}

@Test func parseWildcardAsBindingPattern() throws {
    let expr = firstExpression("match a { _ as Int32 => 1 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let asPattern = matchExpr!.cases[0].patterns[0] as? AST.AsPattern
    #expect(asPattern != nil)
    #expect(asPattern!.pattern is AST.WildcardPattern)
}

@Test func parseAsExpressionStillCastExpression() {
    let expr = firstExpression("x as Int32")
    let cast = expr as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .As)
    #expect(!(expr is AST.AsPattern))
}

@Test func parseAsQuestionInPatternStaysCast() throws {
    let expr = firstExpression("match a { let x as? Int32 => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let cast = matchExpr!.cases[0].patterns[0] as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .OptionalAs)
}

@Test func parseMatchWithBinding() throws {
    let expr = firstExpression("match a { .some(let x) => x, .none => 0 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    try #require(matchExpr!.cases.count == 2)
    let case0 = matchExpr!.cases[0]
    try #require(case0.patterns.count == 1)
    let call = case0.patterns[0] as? AST.Call
    try #require(call != nil)
    let member = call!.callee as? AST.ImplicitMemberAccess
    #expect(member!.name.value == "some")
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseMatchWithPartialBinding() throws {
    let expr = firstExpression("match a { .foo(let x, _) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let case0 = matchExpr!.cases[0]
    let call = case0.patterns[0] as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 2)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
    let wildcard = call!.arguments[1].value as? AST.WildcardPattern
    #expect(wildcard != nil)
}

@Test func parseMatchWithNestedBinding() throws {
    let expr = firstExpression("match a { .some(.some(let x)) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let case0 = matchExpr!.cases[0]
    let outerCall = case0.patterns[0] as? AST.Call
    try #require(outerCall != nil)
    let innerCall = outerCall!.arguments[0].value as? AST.Call
    try #require(innerCall != nil)
    let binding = innerCall!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseMatchWithMultiplePatterns() throws {
    let expr = firstExpression("match a { .a, .b => 1, .c => 2 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    try #require(matchExpr!.cases.count == 2)
    #expect(matchExpr!.cases[0].patterns.count == 2)
    #expect(matchExpr!.cases[1].patterns.count == 1)
}

@Test func parseMatchExpressionCaseRequiresComma() throws {
    let (_, diagnostics) = parseWithDiagnostics(
        "func f() { match a { .a => 1 .b => 2 } }"
    )
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    #expect(errors[0].message == "expected ',' after match case expression")
}

@Test func parseMatchMixedLiteralAndBinding() throws {
    let expr = firstExpression("match a { .foo(1, let x) => x }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let case0 = matchExpr!.cases[0]
    let call = case0.patterns[0] as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 2)
    let lit = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(lit != nil)
    let binding = call!.arguments[1].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
}

@Test func parseMatchWithWildcardCatchAll() throws {
    let expr = firstExpression("match a { _ => 42 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    try #require(matchExpr!.cases.count == 1)
    let case0 = matchExpr!.cases[0]
    try #require(case0.patterns.count == 1)
    #expect(case0.patterns[0] is AST.WildcardPattern)
}

@Test func parseIfCaseMixedLiteralAndBinding() throws {
    let body = parseBlockStatements("func main() { if case .foo(1, let x) = a {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let call = caseMatch!.pattern as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 2)
    let lit = call!.arguments[0].value as? AST.IntegerLiteral
    #expect(lit != nil)
    let binding = call!.arguments[1].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "x")
}

// MARK: - Range Operators in Patterns

@Test func parseMatchRangePatternClosed() throws {
    let expr = firstExpression("match x { 1...5 => 1 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    try #require(matchExpr!.cases.count == 1)
    let seq = matchExpr!.cases[0].patterns[0] as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    try #require(seq!.operands.count == 2)
    let lower = seq!.operands[0] as? AST.IntegerLiteral
    try #require(lower != nil)
    #expect(lower!.value == 1)
    let upper = seq!.operands[1] as? AST.IntegerLiteral
    try #require(upper != nil)
    #expect(upper!.value == 5)
}

@Test func parseMatchRangePatternHalfOpen() throws {
    let expr = firstExpression("match x { 1..<5 => 1 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let seq = matchExpr!.cases[0].patterns[0] as? AST.Sequential
    try #require(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDotLess))
}

@Test func parseMatchRangePatternDotDot() throws {
    let expr = firstExpression("match x { 1..5 => 1 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    let seq = matchExpr!.cases[0].patterns[0] as? AST.Sequential
    try #require(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDot))
}

@Test func parseMatchMultipleRangePatterns() throws {
    let expr = firstExpression("match x { 1...5, 10...20 => 1, 30...40 => 2 }")
    let matchExpr = expr as? AST.Match
    try #require(matchExpr != nil)
    try #require(matchExpr!.cases.count == 2)
    #expect(matchExpr!.cases[0].patterns.count == 2)
    #expect(matchExpr!.cases[1].patterns.count == 1)
    for pattern in matchExpr!.cases[0].patterns {
        let seq = pattern as? AST.Sequential
        try #require(seq != nil)
        #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    }
}

@Test func parseIfCaseRangePattern() throws {
    let body = parseBlockStatements("func main() { if case 1...5 = x {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let seq = caseMatch!.pattern as? AST.Sequential
    try #require(seq != nil)
    #expect(seq!.ops[0].kind == .Operator(.DotDotDot))
    #expect(seq!.operands.count == 2)
}

// MARK: - ShorthandArgument

@Test func parseShorthandArgumentDollar0() throws {
    let body = parseBlockStatements("func main() { $0 }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let arg = exprStmt!.expression as? AST.ShorthandArgument
    try #require(arg != nil)
    #expect(arg!.index == 0)
}

@Test func parseShorthandArgumentDollar42() throws {
    let body = parseBlockStatements("func main() { $42 }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let arg = exprStmt!.expression as? AST.ShorthandArgument
    try #require(arg != nil)
    #expect(arg!.index == 42)
}

@Test func parseShorthandArgumentInClosure() throws {
    let body = parseBlockStatements("func main() { { $0 } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    try #require(closure!.body.count == 1)
    let innerExpr = closure!.body[0] as? AST.ExpressionStatement
    try #require(innerExpr != nil)
    let arg = innerExpr!.expression as? AST.ShorthandArgument
    try #require(arg != nil)
    #expect(arg!.index == 0)
}

// MARK: - Trailing Closure

@Test func parseTrailingClosureWithoutParens() throws {
    let body = parseBlockStatements("func main() { arr.filter { $0 } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.isEmpty)
    try #require(call!.trailingClosures.count == 1)
    #expect(call!.trailingClosures[0].0 == nil)
    let memberAccess = call!.callee as? AST.MemberAccess
    #expect(memberAccess != nil)
}

@Test func parseTrailingClosureWithParens() throws {
    let body = parseBlockStatements("func main() { foo() { $0 } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.isEmpty)
    try #require(call!.trailingClosures.count == 1)
    #expect(call!.trailingClosures[0].0 == nil)
}

@Test func parseMultipleTrailingClosures() throws {
    let body = parseBlockStatements("func main() { foo { } bar: { } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.isEmpty)
    try #require(call!.trailingClosures.count == 2)
    #expect(call!.trailingClosures[0].0 == nil)
    #expect(call!.trailingClosures[1].0?.value == "bar")
}

@Test func parseTrailingClosureWithArgs() throws {
    let body = parseBlockStatements("func main() { foo(1) { $0 } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    try #require(call != nil)
    #expect(call!.arguments.count == 1)
    try #require(call!.trailingClosures.count == 1)
    #expect(call!.trailingClosures[0].0 == nil)
}

@Test func parseMultipleTrailingClosuresWithUnlabeledFirstIsValid() {
    let (_, errors) = parseWithDiagnostics("func main() { foo { } bar: { } }")
    #expect(errors.isEmpty)
}

@Test func parseUnlabeledTrailingClosureStopsAttachment() throws {
    let body = parseBlockStatements("func main() { foo { } { } }")
    try #require(body.count == 2)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    try #require(call != nil)
    try #require(call!.trailingClosures.count == 1)
    #expect(call!.trailingClosures[0].0 == nil)
    #expect(body[1] is AST.ExpressionStatement)
}

@Test func parseLabeledTrailingClosureThenUnlabeledStopsAttachment() throws {
    let body = parseBlockStatements("func main() { foo { } bar: { } { } }")
    try #require(body.count == 2)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let call = exprStmt!.expression as? AST.Call
    try #require(call != nil)
    try #require(call!.trailingClosures.count == 2)
    #expect(call!.trailingClosures[0].0 == nil)
    #expect(call!.trailingClosures[1].0?.value == "bar")
    #expect(body[1] is AST.ExpressionStatement)
}

// MARK: - String Interpolation

@Test func parseStringInterpolationSimple() throws {
    let expr = firstExpression("\"hello \\(name)\"")
    let interp = expr as? AST.StringInterpolation
    try #require(interp != nil)
    try #require(interp!.segments.count == 3)
    guard case let .Literal(first) = interp!.segments[0] else {
        #expect(Bool(false))
        return
    }
    #expect(first.value == "hello ")
    guard case let .Expression(e) = interp!.segments[1] else {
        #expect(Bool(false))
        return
    }
    #expect(e is AST.Variable)
    guard case let .Literal(last) = interp!.segments[2] else {
        #expect(Bool(false))
        return
    }
    #expect(last.value == "")
    #expect(!last.isUnterminated)
}

@Test func parseStringInterpolationMultiSegment() throws {
    let expr = firstExpression("\"\\(v1) \\(v2)\"")
    let interp = expr as? AST.StringInterpolation
    try #require(interp != nil)
    try #require(interp!.segments.count == 5)
    guard case let .Literal(first) = interp!.segments[0] else {
        #expect(Bool(false))
        return
    }
    #expect(first.value == "")
    #expect(first.isUnterminated)
    guard case .Expression = interp!.segments[1] else {
        #expect(Bool(false))
        return
    }
    guard case let .Literal(mid) = interp!.segments[2] else {
        #expect(Bool(false))
        return
    }
    #expect(mid.value == " ")
    #expect(mid.isUnterminated)
}

@Test func parseRawStringLiteral() throws {
    let expr = firstExpression("#\"hello\\nworld\"#")
    let literal = expr as? AST.StringLiteral
    try #require(literal != nil)
    #expect(literal!.token.isRaw)
    #expect(literal!.token.value == "hello\\nworld")
}

@Test func parseRawStringInterpolation() throws {
    let expr = firstExpression("#\"a\\#(name)b\"#")
    let interp = expr as? AST.StringInterpolation
    try #require(interp != nil)
    try #require(interp!.segments.count == 3)
    guard case let .Literal(first) = interp!.segments[0] else {
        #expect(Bool(false))
        return
    }
    #expect(first.value == "a")
    #expect(first.isRaw)
    guard case let .Expression(e) = interp!.segments[1] else {
        #expect(Bool(false))
        return
    }
    #expect(e is AST.Variable)
    guard case let .Literal(last) = interp!.segments[2] else {
        #expect(Bool(false))
        return
    }
    #expect(last.value == "b")
    #expect(last.isRaw)
}

@Test func parseRawMultilineStringLiteral() throws {
    let expr = firstExpression("#\"\"\"\nhello\nworld\n\"\"\"#")
    let literal = expr as? AST.StringLiteral
    try #require(literal != nil)
    #expect(literal!.token.isRaw)
    #expect(literal!.token.value == "hello\nworld\n")
}

@Test func parseMultilineStringInterpolation() throws {
    let expr = firstExpression("\"\"\"\nhello \\(name) world\n\"\"\"")
    let interp = expr as? AST.StringInterpolation
    try #require(interp != nil)
    try #require(interp!.segments.count == 3)
    guard case let .Literal(first) = interp!.segments[0] else {
        #expect(Bool(false))
        return
    }
    #expect(first.value == "hello ")
    guard case let .Literal(last) = interp!.segments[2] else {
        #expect(Bool(false))
        return
    }
    #expect(last.value == " world\n")
}

// MARK: - KeyPath

@Test func parseKeyPathSimple() throws {
    let expr = firstExpression("\\Person.name")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    #expect(keyPath!.root != nil)
    #expect(keyPath!.root is AST.Variable)
    #expect((keyPath!.root as? AST.Variable)?.name.value == "Person")
    try #require(keyPath!.components.count == 1)
    #expect(keyPath!.components[0].dotToken.kind == .Operator(.Dot))
    #expect(keyPath!.components[0].name!.value == "name")
    #expect(keyPath!.components[0].postfix == nil)
}

@Test func parseKeyPathNoRoot() throws {
    let expr = firstExpression("\\.name")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    #expect(keyPath!.root == nil)
    try #require(keyPath!.components.count == 1)
    #expect(keyPath!.components[0].name!.value == "name")
}

@Test func parseKeyPathSelfComponent() throws {
    let expr = firstExpression("\\.self")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    #expect(keyPath!.root == nil)
    try #require(keyPath!.components.count == 1)
    #expect(keyPath!.components[0].name!.kind == .Keyword(.SelfKw))
}

@Test func parseKeyPathIntegerComponent() throws {
    let expr = firstExpression("\\Person.0")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    try #require(keyPath!.components.count == 1)
    #expect(keyPath!.components[0].name!.kind == .IntegerLiteral(0))
}

@Test func parseKeyPathPostfixComponents() throws {
    let expr = firstExpression("\\Person.name!.age")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    try #require(keyPath!.components.count == 2)
    #expect(keyPath!.components[0].name!.value == "name")
    #expect(keyPath!.components[0].postfix?.kind == .Operator(.Not))
    #expect(keyPath!.components[1].name!.value == "age")
    #expect(keyPath!.components[1].postfix == nil)
}

@Test func parseKeyPathOptionalComponent() throws {
    let expr = firstExpression("\\Person.age?.city")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    try #require(keyPath!.components.count == 2)
    #expect(keyPath!.components[0].name!.value == "age")
    #expect(keyPath!.components[0].postfix == nil)
    #expect(keyPath!.components[1].dotToken.kind == .Operator(.QuestionMarkDot))
    #expect(keyPath!.components[1].name!.value == "city")
}

@Test func parseKeyPathRootPostfix() throws {
    let expr = firstExpression("\\A!.b")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    #expect((keyPath!.root as? AST.Variable)?.name.value == "A")
    #expect(keyPath!.rootPostfix?.kind == .Operator(.Not))
    try #require(keyPath!.components.count == 1)
    #expect(keyPath!.components[0].name!.value == "b")
}

@Test func parseKeyPathDottedRoot() throws {
    let expr = firstExpression("\\A.b.c")
    let keyPath = expr as? AST.KeyPathExpression
    try #require(keyPath != nil)
    #expect((keyPath!.root as? AST.Variable)?.name.value == "A")
    try #require(keyPath!.components.count == 2)
    #expect(keyPath!.components[0].name!.value == "b")
    #expect(keyPath!.components[1].name!.value == "c")
}

@Test func parseKeyPathMissingComponentReportsError() {
    let (_, errors) = parseWithDiagnostics("func main() { let x = \\ }")
    #expect(!errors.isEmpty)
}

// MARK: - Closure Signature

@Test func parseClosureWithParameters() throws {
    let body = parseBlockStatements("func main() { { (x: Int) in x } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    try #require(closure!.signature != nil)
    try #require(closure!.signature!.parameters.count == 1)
    #expect(closure!.signature!.parameters[0].name.value == "x")
    #expect(closure!.body.count == 1)
}

@Test func parseClosureWithReturnType() throws {
    let body = parseBlockStatements("func main() { { () -> Int in 42 } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    #expect(closure!.signature?.returnType != nil)
}

@Test func parseClosureWithCaptureList() throws {
    let body = parseBlockStatements("func main() { { [weak self] in self.foo() } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    let sig = closure!.signature
    try #require(sig != nil)
    try #require(sig!.captureList.count == 1)
    #expect(sig!.captureList[0].specifier?.value == "weak")
    #expect(sig!.captureList[0].name.value == "self")
}

// MARK: - OptionalType

@Test func parseOptionalTypeSimple() throws {
    let expr = firstExpression("Int?")
    let optional = expr as? AST.OptionalType
    try #require(optional != nil)
    let inner = optional!.wrappedType as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "Int")
}

@Test func parseOptionalTypeNested() throws {
    let expr = firstExpression("Int??")
    let outer = expr as? AST.OptionalType
    try #require(outer != nil)
    let inner = outer!.wrappedType as? AST.OptionalType
    try #require(inner != nil)
    let innermost = inner!.wrappedType as? AST.Variable
    try #require(innermost != nil)
    #expect(innermost!.name.value == "Int")
}

@Test func parseOptionalTypeInReturnType() throws {
    let stmts = parseStatements("func f() -> Int? {}")
    try #require(stmts.count == 1)
    let funcDecl = stmts[0] as? AST.FunctionDecl
    try #require(funcDecl != nil)
    let retType = funcDecl!.returnTypeExpression as? AST.OptionalType
    try #require(retType != nil)
    let inner = retType!.wrappedType as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "Int")
}

@Test func parseOptionalTypeInVariableDeclaration() throws {
    let stmts = parseStatements("let x: Int?")
    try #require(stmts.count == 1)
    let varDecl = stmts[0] as? AST.VariableDecl
    try #require(varDecl != nil)
    let type = varDecl!.typeExpression as? AST.OptionalType
    try #require(type != nil)
    let inner = type!.wrappedType as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "Int")
}

// MARK: - SomeType / AnyType

@Test func parseSomeTypeSimple() throws {
    let expr = firstExpression("some Collection")
    let some = expr as? AST.SomeType
    try #require(some != nil)
    let inner = some!.wrappedType as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "Collection")
}

@Test func parseAnyTypeSimple() throws {
    let expr = firstExpression("any Collection")
    let anyType = expr as? AST.AnyType
    try #require(anyType != nil)
    let inner = anyType!.wrappedType as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "Collection")
}

@Test func parseSomeTypeWithComposition() throws {
    let expr = firstExpression("some A & B")
    let some = expr as? AST.SomeType
    try #require(some != nil)
    let comp = some!.wrappedType as? AST.ProtocolCompositionType
    try #require(comp != nil)
    try #require(comp!.types.count == 2)
    let t0 = comp!.types[0] as? AST.Variable
    try #require(t0 != nil)
    #expect(t0!.name.value == "A")
    let t1 = comp!.types[1] as? AST.Variable
    try #require(t1 != nil)
    #expect(t1!.name.value == "B")
}

@Test func parseSomeTypeWithMultipleComposition() throws {
    let expr = firstExpression("some A & B & C")
    let some = expr as? AST.SomeType
    try #require(some != nil)
    let comp = some!.wrappedType as? AST.ProtocolCompositionType
    try #require(comp != nil)
    #expect(comp!.types.count == 3)
}

@Test func parseAnyTypeWithComposition() throws {
    let expr = firstExpression("any A & B")
    let anyType = expr as? AST.AnyType
    try #require(anyType != nil)
    let comp = anyType!.wrappedType as? AST.ProtocolCompositionType
    try #require(comp != nil)
    #expect(comp!.types.count == 2)
}

@Test func parseSomeTypeWithOptionalInner() throws {
    let expr = firstExpression("some Int?")
    let some = expr as? AST.SomeType
    try #require(some != nil)
    let optional = some!.wrappedType as? AST.OptionalType
    try #require(optional != nil)
    let inner = optional!.wrappedType as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "Int")
}

@Test func parseSomeTypeInGenericConstraint() throws {
    let stmts = parseStatements("struct Foo<each T: some P> {}")
    try #require(stmts.count == 1)
    let structDecl = stmts[0] as? AST.StructDecl
    try #require(structDecl != nil)
    try #require(structDecl!.genericDecl != nil)
    let generics = structDecl!.genericDecl!.generics
    try #require(generics.count == 1)
    let some = generics[0].constraint as? AST.SomeType
    try #require(some != nil)
    let inner = some!.wrappedType as? AST.Variable
    try #require(inner != nil)
    #expect(inner!.name.value == "P")
}

// MARK: - Self type constraint

@Test func parseSelfInGenericConstraint() throws {
    let stmts = parseStatements("struct Foo<each T: Self> {}")
    try #require(stmts.count == 1)
    let structDecl = stmts[0] as? AST.StructDecl
    try #require(structDecl != nil)
    try #require(structDecl!.genericDecl != nil)
    try #require(structDecl!.genericDecl!.generics.count == 1)
    let constraint = structDecl!.genericDecl!.generics[0].constraint as? AST.SelfType
    #expect(constraint != nil)
}

// MARK: - TupleExpression

@Test func parseTupleExpression() throws {
    let expr = firstExpression("(1, 2)")
    let tuple = expr as? AST.Tuple
    try #require(tuple != nil)
    try #require(tuple!.elements.count == 2)
    let e0 = tuple!.elements[0].value as? AST.IntegerLiteral
    #expect(e0 != nil)
    let e1 = tuple!.elements[1].value as? AST.IntegerLiteral
    #expect(e1 != nil)
}

@Test func parseLabeledTupleExpression() throws {
    let expr = firstExpression("(name: String, age: Int)")
    let tuple = expr as? AST.Tuple
    try #require(tuple != nil)
    try #require(tuple!.elements.count == 2)
    #expect(tuple!.elements[0].label?.value == "name")
    #expect(tuple!.elements[1].label?.value == "age")
}

@Test func parseTupleWithTrailingComma() throws {
    let expr = firstExpression("(1, 2,)")
    let tuple = expr as? AST.Tuple
    try #require(tuple != nil)
    #expect(tuple!.elements.count == 2)
}

@Test func parseTuplePattern() throws {
    let body = parseBlockStatements("func main() { match x { (a, b) => a } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let match = exprStmt!.expression as? AST.Match
    try #require(match != nil)
    try #require(match!.cases.count == 1)
    let patterns = match!.cases[0].patterns
    try #require(patterns.count == 1)
    let tuple = patterns[0] as? AST.Tuple
    try #require(tuple != nil)
    try #require(tuple!.elements.count == 2)
    let e0 = tuple!.elements[0].value as? AST.Variable
    try #require(e0 != nil)
    #expect(e0!.name.value == "a")
    let e1 = tuple!.elements[1].value as? AST.Variable
    try #require(e1 != nil)
    #expect(e1!.name.value == "b")
}

@Test func parseTuplePatternWithBinding() throws {
    let body = parseBlockStatements("func main() { match x { (a, let b) => b } }")
    let exprStmt = body[0] as? AST.ExpressionStatement
    let match = exprStmt!.expression as? AST.Match
    let tuple = match!.cases[0].patterns[0] as? AST.Tuple
    try #require(tuple != nil)
    try #require(tuple!.elements.count == 2)
    let binding = tuple!.elements[1].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "b")
}

// MARK: - IsPattern

@Test func parseIsPatternInMatch() throws {
    let body = parseBlockStatements("func main() { match x { is Int => \"int\" } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let match = exprStmt!.expression as? AST.Match
    try #require(match != nil)
    try #require(match!.cases.count == 1)
    try #require(match!.cases[0].patterns.count == 1)
    let isPattern = match!.cases[0].patterns[0] as? AST.IsPattern
    try #require(isPattern != nil)
    let typeExpr = isPattern!.typeExpression as? AST.Variable
    try #require(typeExpr != nil)
    #expect(typeExpr!.name.value == "Int")
}

@Test func parseIsPatternInIfCase() throws {
    let body = parseBlockStatements("func main() { if case is Int = x {} }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let ifExpr = exprStmt!.expression as? AST.If
    let caseMatch = ifExpr!.condition as? AST.CaseMatch
    #expect(caseMatch != nil)
    let isPattern = caseMatch!.pattern as? AST.IsPattern
    try #require(isPattern != nil)
    let typeExpr = isPattern!.typeExpression as? AST.Variable
    try #require(typeExpr != nil)
    #expect(typeExpr!.name.value == "Int")
}

// MARK: - TypeAlias Declarations

@Test func parseTypeAliasSimple() throws {
    let statements = parseStatements("typealias Foo = Int32")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.TypeAliasDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.TypeAlias))
    #expect(decl!.name.kind == .Identifier)
    #expect(decl!.name.value == "Foo")
    let typeVar = decl!.typeExpression as? AST.Variable
    try #require(typeVar != nil)
    #expect(typeVar!.name.value == "Int32")
}

@Test func parseTypeAliasWithGenericType() throws {
    let statements = parseStatements("typealias Pair = (Int32, Int32)")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.TypeAliasDecl
    try #require(decl != nil)
    let tuple = decl!.typeExpression as? AST.Tuple
    try #require(tuple != nil)
    #expect(tuple!.elements.count == 2)
}

@Test func parseTypeAliasInStructBody() throws {
    let statements = parseStatements("struct Foo { typealias Inner = Int32 }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    try #require(structDecl!.body.count == 1)
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

@Test func parseExternDeclarationForm() throws {
    let statements = parseStatements("extern \"C\" func foo() -> Int32")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    try #require(decl != nil)
    #expect(decl!.token.kind == .Keyword(.Extern))
    #expect(decl!.convention.value == "C")
    if case let .Declaration(inner) = decl!.body {
        let fd = inner as? AST.FunctionDecl
        try #require(fd != nil)
        #expect(fd!.name.value == "foo")
    } else {
        Issue.record("expected .Declaration body")
    }
}

@Test func parseExternVariableDeclaration() throws {
    let statements = parseStatements("extern \"C\" var errno: Int32")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    try #require(decl != nil)
    if case let .Declaration(inner) = decl!.body {
        let vd = inner as? AST.VariableDecl
        try #require(vd != nil)
        #expect(vd!.name.value == "errno")
    } else {
        Issue.record("expected .Declaration body")
    }
}

@Test func parseExternBlockForm() throws {
    let statements = parseStatements("extern \"C\" { func foo() func bar() }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    try #require(decl != nil)
    if case let .Block(body) = decl!.body {
        try #require(body.count == 2)
        let fd0 = body[0] as? AST.FunctionDecl
        try #require(fd0 != nil)
        #expect(fd0!.name.value == "foo")
        let fd1 = body[1] as? AST.FunctionDecl
        try #require(fd1 != nil)
        #expect(fd1!.name.value == "bar")
    } else {
        Issue.record("expected .Block body")
    }
}

@Test func parseExternBlockWithMixedDeclarations() throws {
    let statements = parseStatements("extern \"C\" { let x = 1 var y: Int32 func foo() }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ExternDecl
    try #require(decl != nil)
    if case let .Block(body) = decl!.body {
        try #require(body.count == 3)
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

@Test func parseDeinitEmptyBody() throws {
    let statements = parseStatements("class Foo { deinit {} }")
    try #require(statements.count == 1)
    let classDecl = statements[0] as? AST.ClassDecl
    #expect(classDecl != nil)
    try #require(classDecl!.body.count == 1)
    let deinitDecl = classDecl!.body[0] as? AST.DeinitDecl
    try #require(deinitDecl != nil)
    #expect(deinitDecl!.token.kind == .Keyword(.Deinit))
    #expect(deinitDecl!.body.isEmpty)
}

@Test func parseDeinitWithBody() throws {
    let statements = parseStatements("class Foo { deinit { cleanup() } }")
    try #require(statements.count == 1)
    let classDecl = statements[0] as? AST.ClassDecl
    #expect(classDecl != nil)
    let deinitDecl = classDecl!.body[0] as? AST.DeinitDecl
    try #require(deinitDecl != nil)
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

@Test func parseAssociatedTypeBare() throws {
    let statements = parseStatements("protocol P { associatedtype T }")
    try #require(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    try #require(protocolDecl != nil)
    try #require(protocolDecl!.body.count == 1)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    #expect(assoc!.token.kind == .Keyword(.AssociatedType))
    #expect(assoc!.name.value == "T")
    #expect(assoc!.constraint == nil)
    #expect(assoc!.whereClause == nil)
}

@Test func parseAssociatedTypeWithConstraint() throws {
    let statements = parseStatements("protocol P { associatedtype T: Equatable }")
    try #require(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    try #require(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let constraint = assoc!.constraint as? AST.Variable
    try #require(constraint != nil)
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

@Test func parseWhereClauseConformance() throws {
    let statements = parseStatements("protocol P { associatedtype T where T: Equatable }")
    try #require(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    try #require(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let whereClause = assoc!.whereClause
    try #require(whereClause != nil)
    try #require(whereClause!.count == 1)
    let left = whereClause![0].left as? AST.Variable
    try #require(left != nil)
    #expect(left!.name.value == "T")
    if case let .Conformance(right) = whereClause![0].constraint {
        let rightVar = right as? AST.Variable
        try #require(rightVar != nil)
        #expect(rightVar!.name.value == "Equatable")
    } else {
        Issue.record("expected conformance constraint")
    }
}

@Test func parseWhereClauseEquality() throws {
    let statements = parseStatements("protocol P { associatedtype T where T == Int32 }")
    try #require(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    try #require(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let whereClause = assoc!.whereClause
    try #require(whereClause != nil)
    try #require(whereClause!.count == 1)
    let left = whereClause![0].left as? AST.Variable
    try #require(left != nil)
    #expect(left!.name.value == "T")
    if case let .Equality(right) = whereClause![0].constraint {
        let rightVar = right as? AST.Variable
        try #require(rightVar != nil)
        #expect(rightVar!.name.value == "Int32")
    } else {
        Issue.record("expected equality constraint")
    }
}

@Test func parseWhereClauseEqualityWithGenericType() throws {
    let statements = parseStatements("protocol P { associatedtype T where T == Array<U> }")
    try #require(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    try #require(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    if case let .Equality(right) = assoc!.whereClause![0].constraint {
        let seq = right as? AST.Sequential
        try #require(seq != nil)
        #expect(seq!.ops.count == 2)
        let base = seq!.operands[0] as? AST.Variable
        #expect(base != nil)
        #expect(base!.name.value == "Array")
        let arg = seq!.operands[1] as? AST.Variable
        try #require(arg != nil)
        #expect(arg!.name.value == "U")
    } else {
        Issue.record("expected equality constraint")
    }
}

@Test func parseStructWhereClauseEquality() throws {
    let statements = parseStatements("struct S<T> where T == Int32 {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    let whereClause = decl!.whereClause
    try #require(whereClause != nil)
    try #require(whereClause!.count == 1)
    if case .Equality = whereClause![0].constraint {
    } else {
        Issue.record("expected equality constraint")
    }
}

@Test func parseWhereClauseMultipleRequirements() throws {
    let statements = parseStatements(
        "protocol P { associatedtype T where T: Equatable, T.Element: Hashable }"
    )
    try #require(statements.count == 1)
    let protocolDecl = statements[0] as? AST.ProtocolDecl
    try #require(protocolDecl != nil)
    let assoc = protocolDecl!.body[0] as? AST.AssociatedTypeDecl
    #expect(assoc != nil)
    let whereClause = assoc!.whereClause
    try #require(whereClause != nil)
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

@Test func parseStructWhereClauseConformance() throws {
    let statements = parseStatements("struct S<T> where T: Equatable {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    #expect(decl!.genericDecl != nil)
    let whereClause = decl!.whereClause
    try #require(whereClause != nil)
    try #require(whereClause!.count == 1)
    let left = whereClause![0].left as? AST.Variable
    try #require(left != nil)
    #expect(left!.name.value == "T")
    if case let .Conformance(right) = whereClause![0].constraint {
        let rightVar = right as? AST.Variable
        try #require(rightVar != nil)
        #expect(rightVar!.name.value == "Equatable")
    } else {
        Issue.record("expected conformance constraint")
    }
    #expect(decl!.body.isEmpty)
}

@Test func parseClassWhereClauseConformance() throws {
    let statements = parseStatements("class C<T> where T: Equatable {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    try #require(decl!.whereClause?.count == 1)
}

@Test func parseEnumWhereClauseConformance() throws {
    let statements = parseStatements("enum E<T> where T: Equatable {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.EnumDecl
    try #require(decl != nil)
    try #require(decl!.whereClause?.count == 1)
}

@Test func parseActorWhereClauseConformance() throws {
    let statements = parseStatements("actor A<T> where T: Equatable {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    try #require(decl != nil)
    try #require(decl!.whereClause?.count == 1)
}

@Test func parseProtocolWhereClauseConformance() throws {
    let statements = parseStatements("protocol P where T: Equatable {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    try #require(decl != nil)
    try #require(decl!.whereClause?.count == 1)
}

@Test func parseStructWhereClauseMultipleRequirements() throws {
    let statements = parseStatements("struct S<T, U> where T: Equatable, U: Hashable {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    try #require(decl!.whereClause?.count == 2)
}

@Test func parseStructWithoutWhereClause() throws {
    let statements = parseStatements("struct S<T> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    try #require(decl != nil)
    #expect(decl!.whereClause == nil)
}

// MARK: - Actor Declarations (extended)

@Test func parseActorWithConformances() throws {
    let statements = parseStatements("actor Foo: P, Q {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    try #require(decl != nil)
    try #require(decl!.conformances.count == 2)
    let p = decl!.conformances[0] as? AST.Variable
    try #require(p != nil)
    #expect(p!.name.value == "P")
    let q = decl!.conformances[1] as? AST.Variable
    try #require(q != nil)
    #expect(q!.name.value == "Q")
}

@Test func parseActorWithGenericParameters() throws {
    let statements = parseStatements("actor Foo<T> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl != nil)
    try #require(decl!.genericDecl!.generics.count == 1)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
}

@Test func parseActorWithInitAndPropertyMembers() throws {
    let statements = parseStatements("actor Foo { var x: Int init() {} func bar() {} }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ActorDecl
    try #require(decl != nil)
    try #require(decl!.body.count == 3)
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
    try #require(errors.count == 3)
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

@Test func parseGenericFunctionDecl() throws {
    let statements = parseStatements("func foo<T>(x: T) -> T { x }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let genericDecl = decl!.genericDecl
    try #require(genericDecl != nil)
    try #require(genericDecl!.generics.count == 1)
    #expect(genericDecl!.generics[0].name.value == "T")
    #expect(genericDecl!.generics[0].eachToken == nil)
    #expect(decl!.parameters.count == 1)
    #expect(decl!.returnTypeExpression != nil)
}

@Test func parseGenericFunctionDeclWithConstraint() throws {
    let statements = parseStatements("func foo<T: Equatable>(x: T) -> T { x }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let genericDecl = decl!.genericDecl
    try #require(genericDecl != nil)
    try #require(genericDecl!.generics.count == 1)
    let constraint = genericDecl!.generics[0].constraint
    #expect(constraint != nil)
}

@Test func parseGenericFunctionDeclMultipleParams() throws {
    let statements = parseStatements("func swap<T, U>(_ a: T, _ b: U) {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl?.generics.count == 2)
    #expect(decl!.genericDecl!.generics[1].name.value == "U")
}

@Test func parseNonGenericFunctionHasNoGenericDecl() throws {
    let statements = parseStatements("func foo() {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.genericDecl == nil)
}

@Test func parseGenericInitDecl() throws {
    let statements = parseStatements("struct S { init<T>(x: T) {} }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.genericDecl != nil)
    try #require(initDecl!.genericDecl!.generics.count == 1)
    #expect(initDecl!.genericDecl!.generics[0].name.value == "T")
}

@Test func parseGenericSubscriptDecl() throws {
    let statements = parseStatements("struct S { subscript<T>(i: T) -> T { i } }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    try #require(subDecl != nil)
    try #require(subDecl!.genericDecl != nil)
    try #require(subDecl!.genericDecl!.generics.count == 1)
    #expect(subDecl!.genericDecl!.generics[0].name.value == "T")
    #expect(subDecl!.parameters.count == 1)
}

// MARK: - Subscript Declarations (extended)

@Test func parseSubscriptDeclBasic() throws {
    let statements = parseStatements("struct S { subscript(i: Int) -> Int { i } }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    try #require(subDecl != nil)
    #expect(subDecl!.token.kind == .Keyword(.Subscript))
    #expect(subDecl!.parameters.count == 1)
    #expect(subDecl!.throwsClause == nil)
    let returnType = subDecl!.returnType as? AST.Variable
    try #require(returnType != nil)
    #expect(returnType!.name.value == "Int")
    #expect(subDecl!.accessors.count == 1)
    #expect(subDecl!.accessors[0].kind == .Get)
    if case let .Block(statements) = subDecl!.accessors[0].body {
        #expect(statements.count == 1)
    } else {
        Issue.record("expected block getter body")
    }
}

@Test func parseSubscriptDeclNoParameters() throws {
    let statements = parseStatements("struct S { subscript -> Int { 0 } }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    try #require(subDecl != nil)
    #expect(subDecl!.parameters.isEmpty)
}

@Test func parseSubscriptDeclWithGetSetBody() throws {
    let statements = parseStatements(
        "struct S { subscript(i: Int) -> Int { get { i } set { _ = newValue } } }"
    )
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    try #require(subDecl != nil)
    #expect(subDecl!.accessors.count == 2)
    #expect(subDecl!.accessors[0].kind == .Get)
    #expect(subDecl!.accessors[1].kind == .Set)
}

@Test func parseSubscriptDeclMultipleParameters() throws {
    let statements = parseStatements("struct S { subscript(row: Int, col: Int) -> Int { 0 } }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let subDecl = structDecl!.body[0] as? AST.SubscriptDecl
    try #require(subDecl != nil)
    try #require(subDecl!.parameters.count == 2)
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

@Test func parseForCasePattern() throws {
    let body = parseBlockStatements("func main() { for case .foo(x) in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let call = forStmt!.pattern as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.ImplicitMemberAccess
    try #require(callee != nil)
    #expect(callee!.name.value == "foo")
    try #require(call!.arguments.count == 1)
    let arg = call!.arguments[0].value as? AST.Variable
    try #require(arg != nil)
    #expect(arg!.name.value == "x")
    let sequence = forStmt!.sequence as? AST.Variable
    try #require(sequence != nil)
    #expect(sequence!.name.value == "arr")
}

@Test func parseForCasePatternWithLetBinding() throws {
    let body = parseBlockStatements("func main() { for case .foo(let x) in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let call = forStmt!.pattern as? AST.Call
    try #require(call != nil)
    let binding = call!.arguments[0].value as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.token.kind == .Keyword(.Let))
    #expect(binding!.name.value == "x")
}

@Test func parseForCaseWithLetBinding() throws {
    let body = parseBlockStatements("func main() { for case let y in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let binding = forStmt!.pattern as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "y")
}

@Test func parseForCaseWildcard() throws {
    let body = parseBlockStatements("func main() { for case _ in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let wildcard = forStmt!.pattern as? AST.WildcardPattern
    #expect(wildcard != nil)
}

@Test func parseForCaseWithInitializer() throws {
    let body = parseBlockStatements("func main() { for case let y = a in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let caseMatch = forStmt!.pattern as? AST.CaseMatch
    #expect(caseMatch != nil)
    let binding = caseMatch!.pattern as? AST.BindingPattern
    try #require(binding != nil)
    #expect(binding!.name.value == "y")
    let subject = caseMatch!.subject as? AST.Variable
    try #require(subject != nil)
    #expect(subject!.name.value == "a")
    let sequence = forStmt!.sequence as? AST.Variable
    try #require(sequence != nil)
    #expect(sequence!.name.value == "arr")
}

@Test func parseForCaseWithInitializerExpression() throws {
    let body = parseBlockStatements("func main() { for case let y = a + 1 in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    let caseMatch = forStmt!.pattern as? AST.CaseMatch
    #expect(caseMatch != nil)
    let subject = caseMatch!.subject as? AST.Sequential
    try #require(subject != nil)
    #expect(subject!.ops.count == 1)
}

@Test func parseForPatternWithoutInitializer() throws {
    let body = parseBlockStatements("func main() { for x in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    #expect(forStmt!.pattern as? AST.Variable != nil)
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

@Test func parseFailableInit() throws {
    let statements = parseStatements("struct S { init?() {} }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.optionalToken != nil)
    #expect(initDecl!.optionalToken!.kind == .Operator(.QuestionMark))
}

@Test func parseFailableInitWithParameters() throws {
    let statements = parseStatements("struct S { init?(x: Int) {} }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    #expect(initDecl!.optionalToken != nil)
    #expect(initDecl!.parameters.count == 1)
}

@Test func parseIUOInit() throws {
    let statements = parseStatements("struct S { init!() {} }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.optionalToken != nil)
    #expect(initDecl!.optionalToken!.kind == .Operator(.Not))
    #expect(initDecl!.parameters.isEmpty)
}

@Test func parseIUOInitWithParameters() throws {
    let statements = parseStatements("struct S { init!(x: Int) {} }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    try #require(initDecl!.optionalToken != nil)
    #expect(initDecl!.optionalToken!.kind == .Operator(.Not))
    #expect(initDecl!.parameters.count == 1)
}

// MARK: - Operator Function Declarations

@Test func parseOperatorFunctionDeclaration() throws {
    let statements = parseStatements("func +(lhs: Int32, rhs: Int32) -> Int32 { lhs }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    if case .Operator = decl!.name.kind {
    } else {
        Issue.record("expected operator name")
    }
    #expect(decl!.name.value == "+")
    #expect(decl!.parameters.count == 2)
}

@Test func parsePrefixOperatorFunctionDeclaration() throws {
    let statements = parseStatements("func -(prefixValue: Int32) -> Int32 { prefixValue }")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    if case .Operator = decl!.name.kind {
    } else {
        Issue.record("expected operator name")
    }
    #expect(decl!.name.value == "-")
    #expect(decl!.parameters.count == 1)
}

// MARK: - Generic Declarations (extended)

@Test func parseClassWithGenericParameters() throws {
    let statements = parseStatements("class Foo<T> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl != nil)
    try #require(decl!.genericDecl!.generics.count == 1)
    #expect(decl!.genericDecl!.generics[0].name.value == "T")
}

@Test func parseProtocolWithGenericParameters() throws {
    let statements = parseStatements("protocol Foo<T> {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.ProtocolDecl
    try #require(decl != nil)
    try #require(decl!.genericDecl != nil)
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

@Test func parseEmptyClosure() throws {
    let body = parseBlockStatements("func main() { let f = {} }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closure = vd!.initializer as? AST.Closure
    try #require(closure != nil)
    #expect(closure!.signature == nil)
    #expect(closure!.body.isEmpty)
}

@Test func parseClosureSingleUnannotatedParameter() throws {
    let body = parseBlockStatements("func main() { { x in x } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    let signature = closure!.signature
    try #require(signature != nil)
    try #require(signature!.parameters.count == 1)
    #expect(signature!.parameters[0].name.value == "x")
    #expect(signature!.parameters[0].label == nil)
    #expect(signature!.parameters[0].type == nil)
    #expect(signature!.inToken.value == "in")
    #expect(closure!.body.count == 1)
}

@Test func parseClosureSingleUnannotatedParameterWildcard() throws {
    let body = parseBlockStatements("func main() { { _ in 42 } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    try #require(closure!.signature?.parameters.count == 1)
    #expect(closure!.signature!.parameters[0].name.value == "_")
    #expect(closure!.body.count == 1)
}

@Test func parseClosureSingleUnannotatedParameterEmptyBody() throws {
    let body = parseBlockStatements("func main() { { x in } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    try #require(closure!.signature?.parameters.count == 1)
    #expect(closure!.body.isEmpty)
}

@Test func parseClosureWithCaptureListCombined() throws {
    let body = parseBlockStatements("func main() { { [weak a, unowned b] in a } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    let captureList = closure!.signature!.captureList
    try #require(captureList.count == 2)
    #expect(captureList[0].specifier?.value == "weak")
    #expect(captureList[0].name.value == "a")
    #expect(captureList[1].specifier?.value == "unowned")
    #expect(captureList[1].name.value == "b")
}

@Test func parseClosureCaptureUnownedSelf() throws {
    let body = parseBlockStatements("func main() { { [unowned self] in self } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    let captureList = closure!.signature!.captureList
    try #require(captureList.count == 1)
    #expect(captureList[0].specifier?.value == "unowned")
    #expect(captureList[0].name.value == "self")
}

@Test func parseClosureFullSignature() throws {
    let body = parseBlockStatements(
        "func main() { { [weak self] (x: Int32) throws -> Int32 in x } }"
    )
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let closure = exprStmt!.expression as? AST.Closure
    try #require(closure != nil)
    let signature = closure!.signature
    try #require(signature != nil)
    #expect(signature!.captureList.count == 1)
    #expect(signature!.parameters.count == 1)
    #expect(signature!.throwsClause != nil)
    #expect(signature!.returnType != nil)
}

@Test func parseClosureAsRegularArgument() throws {
    let expr = firstExpression("foo({ 42 })")
    let call = expr as? AST.Call
    try #require(call != nil)
    try #require(call!.arguments.count == 1)
    let closure = call!.arguments[0].value as? AST.Closure
    #expect(closure != nil)
}

@Test func parseNestedClosure() throws {
    let body = parseBlockStatements("func main() { { { 1 } } }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let outer = exprStmt!.expression as? AST.Closure
    try #require(outer != nil)
    try #require(outer!.body.count == 1)
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

@Test func parseClosureTypeInVariableAnnotation() throws {
    let body = parseBlockStatements("func main() { let f: (Int32) -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.parameters.count == 1)
    #expect(closureType!.parameters[0].label == nil)
    let parameterType = closureType!.parameters[0].type as? AST.Variable
    try #require(parameterType != nil)
    #expect(parameterType!.name.value == "Int32")
    let returnType = closureType!.returnType as? AST.Variable
    try #require(returnType != nil)
    #expect(returnType!.name.value == "Int32")
}

@Test func parseClosureTypeInFunctionReturnType() throws {
    let statements = parseStatements("func make() -> (Int32) -> Int32")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    let closureType = decl!.returnTypeExpression as? AST.ClosureType
    #expect(closureType != nil)
    #expect(closureType!.parameters.count == 1)
}

@Test func parseClosureTypeInParameter() throws {
    let statements = parseStatements("func apply(f: (Int32) -> Int32) {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    let closureType = decl!.parameters[0].type as? AST.ClosureType
    #expect(closureType != nil)
    #expect(closureType!.parameters.count == 1)
}

@Test func parseClosureTypeEmptyParameters() throws {
    let body = parseBlockStatements("func main() { let f: () -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    #expect(closureType!.parameters.isEmpty)
}

@Test func parseClosureTypeSingleVoidParameter() throws {
    let body = parseBlockStatements("func main() { let f: (Void) -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.parameters.count == 1)
    let parameterType = closureType!.parameters[0].type as? AST.Variable
    try #require(parameterType != nil)
    #expect(parameterType!.name.value == "Void")
}

@Test func parseClosureTypeParameterLabels() throws {
    let body = parseBlockStatements("func main() { let f: (a: Int32, b: String) -> Bool = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.parameters.count == 2)
    #expect(closureType!.parameters[0].label?.value == "a")
    #expect(closureType!.parameters[1].label?.value == "b")
}

@Test func parseClosureTypeOptionalParameter() throws {
    let body = parseBlockStatements("func main() { let f: (Int32?) -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.parameters.count == 1)
    #expect(closureType!.parameters[0].type is AST.OptionalType)
}

@Test func parseClosureTypeVariadicParameter() throws {
    let body = parseBlockStatements("func main() { let f: (Int32...) -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.parameters.count == 1)
    #expect(closureType!.parameters[0].type is AST.VariadicType)
}

@Test func parseClosureTypeNestedReturn() throws {
    let body = parseBlockStatements("func main() { let f: (Int32) -> (String) -> Bool = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    let nested = closureType!.returnType as? AST.ClosureType
    try #require(nested != nil)
    #expect(nested!.parameters.count == 1)
}

@Test func parseClosureTypeAsync() throws {
    let body = parseBlockStatements("func main() { let f: (Int32) async -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    #expect(closureType!.asyncToken != nil)
    try #require(closureType!.parameters.count == 1)
}

@Test func parseClosureTypeAsyncThrows() throws {
    let body = parseBlockStatements("func main() { let f: (Int32) async throws -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    #expect(closureType!.asyncToken != nil)
    #expect(closureType!.throwsClause != nil)
}

@Test func parseClosureTypeThrowsAsyncOrder() throws {
    let body = parseBlockStatements("func main() { let f: (Int32) throws async -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    #expect(closureType!.asyncToken != nil)
    #expect(closureType!.throwsClause != nil)
}

@Test func parseClosureTypeAsyncAsParameter() throws {
    let statements = parseStatements("func apply(f: ((Int32) async -> Int32) -> Int32) {}")
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.parameters.count == 1)
    let closureType = decl!.parameters[0].type as? AST.ClosureType
    try #require(closureType != nil)
    try #require(closureType!.parameters.count == 1)
    let parameterClosure = closureType!.parameters[0].type as? AST.ClosureType
    try #require(parameterClosure != nil)
    #expect(parameterClosure!.asyncToken != nil)
}

@Test func parseClosureTypeEmptyParensThrows() throws {
    let body = parseBlockStatements("func main() { let f: () throws -> Int32 = g }")
    try #require(body.count == 1)
    let vd = body[0] as? AST.VariableDecl
    try #require(vd != nil)
    let closureType = vd!.typeExpression as? AST.ClosureType
    try #require(closureType != nil)
    #expect(closureType!.parameters.isEmpty)
    #expect(closureType!.throwsClause != nil)
}

@Test func parseClosureTypeBareParameterReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { let f: Int32 -> Int32 = g }")
    try #require(!errors.isEmpty)
}

@Test func parseClosureTypeAsyncWithoutArrowReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { let f: (Int32) async = g }")
    try #require(errors.contains { $0.message.contains("expected '->' after 'async'") })
}

@Test func parseAsyncPrefixBeforeFuncReportsError() throws {
    let (_, errors) = parseWithDiagnostics("async func foo() {}")
    try #require(errors.contains { $0.message.contains("expected 'let' or 'var' after 'async'") })
}

@Test func parseAsyncPrefixWithoutBindingReportsError() throws {
    let (_, errors) = parseWithDiagnostics("func main() { async Int32 }")
    try #require(errors.contains { $0.message.contains("expected 'let' or 'var' after 'async'") })
}

// MARK: - String Interpolation (error paths)

@Test func parseStringInterpolationComplexExpression() throws {
    let expr = firstExpression("\"result: \\(1 + 2)\"")
    let interp = expr as? AST.StringInterpolation
    try #require(interp != nil)
    try #require(interp!.segments.count == 3)
    guard case let .Expression(e) = interp!.segments[1] else {
        Issue.record("expected expression segment")
        return
    }
    let seq = e as? AST.Sequential
    try #require(seq != nil)
    try #require(seq!.ops.count == 1)
    #expect(seq!.ops[0].kind == .Operator(.Plus))
}

@Test func parseStringInterpolationNested() throws {
    let expr = firstExpression("\"\\(foo(\\(bar)))\"")
    let interp = expr as? AST.StringInterpolation
    try #require(interp != nil)
    try #require(interp!.segments.count == 3)
    guard case let .Expression(e) = interp!.segments[1] else {
        Issue.record("expected expression segment")
        return
    }
    let call = e as? AST.Call
    try #require(call != nil)
    let callee = call!.callee as? AST.Variable
    try #require(callee != nil)
    #expect(callee!.name.value == "foo")
    try #require(call!.arguments.count == 1)
    let inner = call!.arguments[0].value as? AST.StringInterpolation
    try #require(inner != nil)
    guard case let .Expression(innerExpr) = inner!.segments[1] else {
        Issue.record("expected inner expression segment")
        return
    }
    let innerVar = innerExpr as? AST.Variable
    try #require(innerVar != nil)
    #expect(innerVar!.name.value == "bar")
}

@Test func parseStringInterpolationNestedAsCallArgument() throws {
    let expr = firstExpression("\"\\(f(g(\\(x))))\"")
    let interp = expr as? AST.StringInterpolation
    try #require(interp != nil)
    try #require(interp!.segments.count == 3)
    guard case let .Expression(e) = interp!.segments[1] else {
        Issue.record("expected expression segment")
        return
    }
    let outerCall = e as? AST.Call
    try #require(outerCall != nil)
    let innerCall = outerCall!.arguments[0].value as? AST.Call
    try #require(innerCall != nil)
    let nested = innerCall!.arguments[0].value as? AST.StringInterpolation
    try #require(nested != nil)
    guard case let .Expression(nestedExpr) = nested!.segments[1] else {
        Issue.record("expected nested expression segment")
        return
    }
    let varExpr = nestedExpr as? AST.Variable
    try #require(varExpr != nil)
    #expect(varExpr!.name.value == "x")
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

@Test func parseIsolatedModifierOnFunction() throws {
    let statements = parseStatements("isolated func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Isolated))
}

@Test func parseIsolatedModifierCombined() throws {
    let statements = parseStatements("isolated public func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.modifiers.count == 2)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Isolated))
    #expect(modifierKind(decl!.modifiers[1].kind, equals: .Public(setter: false)))
}

@Test func parseIsolatedModifierOnVar() throws {
    let statements = parseStatements("isolated var x: Int32")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Isolated))
}

@Test func parseNonmutatingModifierOnFunction() throws {
    let statements = parseStatements("nonmutating func foo() {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Nonmutating))
}

@Test func parseConvenienceModifierOnInit() throws {
    let statements = parseStatements("struct S { convenience init() {} }")
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    #expect(modifierKind(initDecl!.modifiers[0].kind, equals: .Convenience))
}

@Test func parseWeakModifierOnVariable() throws {
    let statements = parseStatements("weak var ref: AnyObject")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Weak))
}

@Test func parseUnownedModifierOnVariable() throws {
    let statements = parseStatements("unowned var ref: AnyObject")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Unowned))
}

@Test func parseAbstractModifierOnClass() throws {
    let statements = parseStatements("abstract class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Abstract))
}

@Test func parseOpenSetModifierOnVariable() throws {
    let statements = parseStatements("open(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Open(setter: true)))
}

@Test func parseInternalSetModifierOnVariable() throws {
    let statements = parseStatements("internal(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Internal(setter: true)))
}

@Test func parseFilePrivateSetModifierOnVariable() throws {
    let statements = parseStatements("fileprivate(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .FilePrivate(setter: true)))
}

@Test func parsePackagePrivateSetModifierOnVariable() throws {
    let statements = parseStatements("packageprivate(set) var x: Int")
    let decl = statements[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .PackagePrivate(setter: true)))
}

@Test func parseProtectedModifierOnClass() throws {
    let statements = parseStatements("protected class Foo {}")
    let decl = statements[0] as? AST.ClassDecl
    try #require(decl != nil)
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
    let (_, errors) = parseWithDiagnostics("func main() { if let x + 1 {} }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected '=' or '{' after variable name in optional binding"))
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
    let expr = firstExpression("match x { 1 => 2 }")
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

// MARK: - Async / Await

@Test func parseAwaitExpression() throws {
    let expr = firstExpression("await foo()")
    let awaitExpr = expr as? AST.Await
    try #require(awaitExpr != nil)
    #expect(awaitExpr!.token.kind == .Keyword(.Await))
    let call = awaitExpr!.expression as? AST.Call
    #expect(call != nil)
}

@Test func parseAwaitVariable() throws {
    let expr = firstExpression("await x")
    let awaitExpr = expr as? AST.Await
    try #require(awaitExpr != nil)
    let variable = awaitExpr!.expression as? AST.Variable
    try #require(variable != nil)
    #expect(variable!.name.value == "x")
}

@Test func parseTryAwait() throws {
    let expr = firstExpression("try await foo()")
    let tryExpr = expr as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .Try)
    let awaitExpr = tryExpr!.expression as? AST.Await
    #expect(awaitExpr != nil)
}

@Test func parseAwaitTry() throws {
    let expr = firstExpression("await try foo()")
    let awaitExpr = expr as? AST.Await
    try #require(awaitExpr != nil)
    let tryExpr = awaitExpr!.expression as? AST.Try
    try #require(tryExpr != nil)
    #expect(tryExpr!.kind == .Try)
}

@Test func parseAwaitInStatementPosition() throws {
    let body = parseBlockStatements("func main() { await foo() }")
    try #require(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    let awaitExpr = exprStmt!.expression as? AST.Await
    #expect(awaitExpr != nil)
}

@Test func parseAwaitMissingExpressionReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { await }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected expression after 'await'")
}

@Test func parseAsyncFunction() throws {
    let statements = parseStatements("func foo() async {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    #expect(decl!.asyncToken != nil)
}

@Test func parseAsyncFunctionWithModifiers() throws {
    let statements = parseStatements("public func foo() async {}")
    let decl = statements[0] as? AST.FunctionDecl
    try #require(decl != nil)
    try #require(decl!.modifiers.count == 1)
    #expect(modifierKind(decl!.modifiers[0].kind, equals: .Public(setter: false)))
    #expect(decl!.asyncToken != nil)
}

@Test func parseAsyncInit() throws {
    let statements = parseStatements("struct S { init() async {} }")
    let structDecl = statements[0] as? AST.StructDecl
    let initDecl = structDecl!.body[0] as? AST.InitDecl
    try #require(initDecl != nil)
    #expect(initDecl!.asyncToken != nil)
}

@Test func parseAsyncLetBinding() throws {
    let body = parseBlockStatements("func main() { async let x = foo() }")
    try #require(body.count == 1)
    let decl = body[0] as? AST.VariableDecl
    try #require(decl != nil)
    #expect(decl!.name.value == "x")
    #expect(decl!.asyncToken != nil)
}

@Test func parseAsyncClosure() throws {
    let expr = firstExpression("{ () async in 1 }")
    let closure = expr as? AST.Closure
    try #require(closure != nil)
    try #require(closure!.signature != nil)
    #expect(closure!.signature!.asyncToken != nil)
    #expect(closure!.signature!.asyncToken!.kind == .Keyword(.Async))
    #expect(closure!.signature!.parameters.isEmpty)
}

@Test func parseAsyncClosureWithParams() throws {
    let expr = firstExpression("{ (x: Int) async in x }")
    let closure = expr as? AST.Closure
    try #require(closure != nil)
    let signature = closure!.signature
    try #require(signature != nil)
    #expect(signature!.asyncToken != nil)
    try #require(signature!.parameters.count == 1)
    #expect(signature!.parameters[0].name.value == "x")
}

@Test func parseAsyncClosureThrowsReturnType() throws {
    let expr = firstExpression("{ () async throws -> Int in 1 }")
    let closure = expr as? AST.Closure
    try #require(closure != nil)
    let signature = closure!.signature
    try #require(signature != nil)
    #expect(signature!.asyncToken != nil)
    #expect(signature!.throwsClause != nil)
    #expect(signature!.returnType != nil)
}

@Test func parseAsyncClosureCaptureList() throws {
    let expr = firstExpression("{ [weak self] () async in 1 }")
    let closure = expr as? AST.Closure
    try #require(closure != nil)
    let signature = closure!.signature
    try #require(signature != nil)
    #expect(signature!.captureList.count == 1)
    #expect(signature!.asyncToken != nil)
}

@Test func parseForAwait() throws {
    let body = parseBlockStatements("func main() { for await x in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    #expect(forStmt!.asyncToken != nil)
    #expect(forStmt!.asyncToken!.kind == .Keyword(.Await))
}

@Test func parseForAwaitCase() throws {
    let body = parseBlockStatements("func main() { for await case .foo(x) in arr {} }")
    try #require(body.count == 1)
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    #expect(forStmt!.asyncToken != nil)
}

@Test func parseForWithoutAwaitHasNilAsyncToken() throws {
    let body = parseBlockStatements("func main() { for x in arr {} }")
    let forStmt = body[0] as? AST.For
    try #require(forStmt != nil)
    #expect(forStmt!.asyncToken == nil)
}

@Test func parseRejectsLocalEnumInFunctionBody() throws {
    let (_, errors) = parseWithDiagnostics("func f() { enum E {} }")
    try #require(errors.count == 1)
    #expect(errors[0].message.contains("expected a statement"))
}

@Test func parseAllowsEnumInTypeBody() throws {
    let statements = parseStatements("struct S { enum E { case a } }")
    try #require(statements.count == 1)
    let structDecl = statements[0] as? AST.StructDecl
    try #require(structDecl != nil)
    try #require(structDecl!.body.count == 1)
    #expect(structDecl!.body[0] is AST.EnumDecl)
}

@Test func parseAllowsExtensionInModuleBody() throws {
    let statements = parseStatements("module M { struct T {} extension T { func f() {} } }")
    try #require(statements.count == 1)
    let moduleDecl = statements[0] as? AST.ModuleDecl
    try #require(moduleDecl != nil)
    try #require(moduleDecl!.body.count == 2)
    #expect(moduleDecl!.body[0] is AST.StructDecl)
    #expect(moduleDecl!.body[1] is AST.ExtensionDecl)
}

@Test func parseOperatorImportWildcard() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.*")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    try #require(decl!.path.components.count == 1)
    if case let .Identifier(t) = decl!.path.components[0] {
        #expect(t.value == "Pkg")
    } else {
        Issue.record("expected identifier component")
    }
    if case .Wildcard = decl!.selector {
    } else {
        Issue.record("expected wildcard selector")
    }
}

@Test func parseOperatorImportSingleOperator() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.+")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    try #require(decl!.path.components.count == 1)
    if case let .Identifier(t) = decl!.path.components[0] {
        #expect(t.value == "Pkg")
    } else {
        Issue.record("expected identifier component")
    }
    if case let .Operator(token) = decl!.selector {
        #expect(token.value == "+")
    } else {
        Issue.record("expected operator selector")
    }
}

@Test func parseOperatorImportList() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.{+, -}")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    if case let .List(items) = decl!.selector {
        try #require(items.count == 2)
        if case let .Operator(token) = items[0] {
            #expect(token.value == "+")
        } else {
            Issue.record("expected operator item")
        }
        if case let .Operator(token) = items[1] {
            #expect(token.value == "-")
        } else {
            Issue.record("expected operator item")
        }
    } else {
        Issue.record("expected list selector")
    }
}

@Test func parseOperatorImportSubmodule() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.{+, module.-}")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    if case let .List(items) = decl!.selector {
        try #require(items.count == 2)
        if case let .Operator(token) = items[0] {
            #expect(token.value == "+")
        } else {
            Issue.record("expected operator item")
        }
        if case let .Submodule(name, selector) = items[1] {
            #expect(name.value == "module")
            if case let .Operator(token) = selector {
                #expect(token.value == "-")
            } else {
                Issue.record("expected operator selector")
            }
        } else {
            Issue.record("expected submodule item")
        }
    } else {
        Issue.record("expected list selector")
    }
}

@Test func parseOperatorImportNestedList() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.{+, module.{-,*}}")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    if case let .List(items) = decl!.selector {
        try #require(items.count == 2)
        if case let .Submodule(name, selector) = items[1] {
            #expect(name.value == "module")
            if case let .List(nested) = selector {
                try #require(nested.count == 2)
                if case let .Operator(token) = nested[0] {
                    #expect(token.value == "-")
                } else {
                    Issue.record("expected operator item")
                }
                if case let .Operator(token) = nested[1] {
                    #expect(token.value == "*")
                } else {
                    Issue.record("expected operator item for '*'")
                }
            } else {
                Issue.record("expected nested list selector")
            }
        } else {
            Issue.record("expected submodule item")
        }
    } else {
        Issue.record("expected list selector")
    }
}

@Test func parseOperatorImportMultilevelPath() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.sub.+")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    try #require(decl!.path.components.count == 2)
    if case let .Identifier(t0) = decl!.path.components[0] {
        #expect(t0.value == "Pkg")
    } else {
        Issue.record("expected identifier component")
    }
    if case let .Identifier(t1) = decl!.path.components[1] {
        #expect(t1.value == "sub")
    } else {
        Issue.record("expected identifier component")
    }
    if case .Operator = decl!.selector {
    } else {
        Issue.record("expected operator selector")
    }
}

@Test func parseOperatorImportStarInListIsOperator() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.{*, +}")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    if case let .List(items) = decl!.selector {
        try #require(items.count == 2)
        if case let .Operator(token) = items[0] {
            #expect(token.value == "*")
        } else {
            Issue.record("expected operator item for '*'")
        }
    } else {
        Issue.record("expected list selector")
    }
}

@Test func parseOperatorImportNestedWildcard() throws {
    let (program, diagnostics) = parseWithDiagnostics("import operator Pkg.{+, module.*}")
    #expect(diagnostics.isEmpty)
    let statements = program.statements
    try #require(statements.count == 1)
    let decl = statements[0] as? AST.OperatorImport
    try #require(decl != nil)
    if case let .List(items) = decl!.selector {
        try #require(items.count == 2)
        if case let .Submodule(name, selector) = items[1] {
            #expect(name.value == "module")
            if case .Wildcard = selector {
            } else {
                Issue.record("expected wildcard selector")
            }
        } else {
            Issue.record("expected submodule item")
        }
    } else {
        Issue.record("expected list selector")
    }
}

@Test func parseOperatorImportBarePathReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator Pkg")
    #expect(
        diagnostics.contains {
            $0.message.contains("expected '.', '*', or '{' after module path in operator import")
        }
    )
}

@Test func parseOperatorImportMissingPathReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator")
    #expect(
        diagnostics.contains {
            $0.message.contains("expected module name after 'import operator'")
        }
    )
}

@Test func parseOperatorImportMissingSelectorReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator Pkg.")
    #expect(
        diagnostics.contains {
            $0.message.contains("expected operator name, '*', or '{' after '.'")
        }
    )
}

@Test func parseOperatorImportBareSubmoduleReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator Pkg.{module}")
    #expect(
        diagnostics.contains {
            $0.message.contains("expected '.', '*', or '{' after submodule name 'module'")
        }
    )
}

@Test func parseOperatorImportEmptyListReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator Pkg.{}")
    #expect(
        diagnostics.contains {
            $0.message.contains("expected operator name or submodule after '{'")
        }
    )
}

@Test func parseOperatorImportMissingBraceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator Pkg.{+")
    #expect(
        diagnostics.contains {
            $0.message.contains("expected '}' after operator import items")
        }
    )
}

@Test func parseOperatorImportAliasReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator Pkg.+ as x")
    #expect(
        diagnostics.contains {
            $0.message.contains("operator imports cannot have an alias")
        }
    )
}

@Test func parseOperatorImportInvalidPathReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("import operator 123")
    #expect(
        diagnostics.contains {
            $0.message.contains("expected module name after 'import operator'")
        }
    )
}

@Test func parseOperatorImportOnlyAtTopLevel() throws {
    let (_, diagnostics) = parseWithDiagnostics("module M { import operator Pkg.+ }")
    #expect(
        diagnostics.contains {
            $0.message.contains("import is only allowed at top level")
        }
    )
}

@Test func parseCastAsBitCastExpression() {
    let expr = firstExpression("x as!! Int32")
    let cast = expr as? AST.Cast
    #expect(cast != nil)
    #expect(cast!.kind == .AsBitCast)
    let right = cast!.right as? AST.Variable
    #expect(right!.name.value == "Int32")
}
