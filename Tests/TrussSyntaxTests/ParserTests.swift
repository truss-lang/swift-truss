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
    let sequentialExpression = decl!.initializer as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.ops.isEmpty)
    #expect(sequentialExpression!.operands.count == 1)
    let intLit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
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
    let typesequentialExpression = decl!.typeExpression as? AST.SequentialExpression
    #expect(typesequentialExpression != nil)
    #expect(typesequentialExpression!.operands.count == 1)
    let typeVar = typesequentialExpression!.operands[0] as? AST.Variable
    #expect(typeVar != nil)
    #expect(typeVar!.name.value == "Int")
}

@Test func parseVarWithInitializer() {
    let statements = parseStatements("var flag = true")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.VariableDecl
    #expect(decl != nil)
    #expect(decl!.name.value == "flag")
    let initsequentialExpression = decl!.initializer as? AST.SequentialExpression
    #expect(initsequentialExpression != nil)
    let boolLit = initsequentialExpression!.operands[0] as? AST.BoolLiteral
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
        let sequentialExpression = expr as? AST.SequentialExpression
        #expect(sequentialExpression != nil)
        #expect(sequentialExpression!.operands.count == 1)
        let intLit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
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
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.operands.count == 1)
    let varExpr = sequentialExpression!.operands[0] as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
}

@Test func parseIntegerLiteralExpression() {
    let expr = firstExpression("42")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.operands.count == 1)
    let lit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 42)
}

@Test func parseFloatLiteralExpression() {
    let expr = firstExpression("3.14")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.FloatLiteral
    #expect(lit != nil)
    #expect(lit!.value == 3.14)
}

@Test func parseStringLiteralExpression() {
    let expr = firstExpression("\"hello\"")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.StringLiteral
    #expect(lit != nil)
    #expect(lit!.token.value == "\"hello\"")
}

@Test func parseCharLiteralExpression() {
    let expr = firstExpression("'a'")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.CharLiteral
    #expect(lit != nil)
    #expect(lit!.value == "a")
}

@Test func parseBooleanTrueLiteralExpression() {
    let expr = firstExpression("true")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.BoolLiteral
    #expect(lit != nil)
    #expect(lit!.value == true)
}

@Test func parseBooleanFalseLiteralExpression() {
    let expr = firstExpression("false")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.BoolLiteral
    #expect(lit != nil)
    #expect(lit!.value == false)
}

@Test func parseNullLiteralExpression() {
    let expr = firstExpression("null")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.NullLiteral
    #expect(lit != nil)
}

@Test func parseFunctionCallNoArgs() {
    let expr = firstExpression("foo()")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.operands.count == 1)
    let call = sequentialExpression!.operands[0] as? AST.Call
    #expect(call != nil)
    let callee = call!.callee as? AST.Variable
    #expect(callee != nil)
    #expect(callee!.name.value == "foo")
    #expect(call!.arguments.isEmpty)
}

@Test func parseMemberAccess() {
    let expr = firstExpression("a.b")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let member = sequentialExpression!.operands[0] as? AST.MemberAccess
    #expect(member != nil)
    let obj = member!.object as? AST.Variable
    #expect(obj != nil)
    #expect(obj!.name.value == "a")
    #expect(member!.member.value == "b")
    #expect(member!.token.kind == .Operator(.Dot))
}

@Test func parseChainedMemberAccess() {
    let expr = firstExpression("a.b.c")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let member = sequentialExpression!.operands[0] as? AST.MemberAccess
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
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let call = sequentialExpression!.operands[0] as? AST.Call
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
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let outer = sequentialExpression!.operands[0] as? AST.Call
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
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 255)
}

@Test func parseBinaryStringLiteral() {
    let expr = firstExpression("0b1010")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 10)
}

@Test func parseUnderscoredIntegerLiteral() {
    let expr = firstExpression("1_000_000")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
    #expect(lit != nil)
    #expect(lit!.value == 1_000_000)
}

@Test func parseScientificFloatLiteral() {
    let expr = firstExpression("1.5e-3")
    let sequentialExpression = expr as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.FloatLiteral
    #expect(lit != nil)
    #expect(lit!.value == 0.0015)
}

@Test func parseReturnWithIntegerLiteral() {
    let body = parseBlockStatements("func main() { return 42 }")
    #expect(body.count == 1)
    let ret = body[0] as? AST.Return
    #expect(ret != nil)
    #expect(ret!.token.kind == .Keyword(.Return))
    let sequentialExpression = ret!.value as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    #expect(sequentialExpression!.operands.count == 1)
    let lit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
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
    let sequentialExpression = ret!.value as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let varExpr = sequentialExpression!.operands[0] as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
    #expect(body[1] is AST.EmptyStatement)
    let vd = body[2] as? AST.VariableDecl
    #expect(vd != nil)
    #expect(vd!.name.value == "y")
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
    let sequentialExpression = vd!.initializer as? AST.SequentialExpression
    #expect(sequentialExpression != nil)
    let lit = sequentialExpression!.operands[0] as? AST.IntegerLiteral
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
    #expect(pg!.higherThanToken != nil)
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
    #expect(pg!.lowerThanToken != nil)
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

@Test func parsePrecedenceGroupDuplicateHigherThanReportsFirstDefinition() {
    let (_, diagnostics) = parseWithDiagnostics(
        "precedencegroup Foo { higherThan: Bar higherThan: Baz }")
    let errors = diagnostics.filter { $0.severity == .error }
    #expect(errors.count == 1)
    #expect(errors[0].message == "higherThan can only be set once")
    #expect(errors[0].notes.count == 1)
    let note = errors[0].notes[0]
    #expect(note.severity == .note)
    #expect(note.message == "previous definition here")
    #expect(note.range.start.offset < errors[0].range.start.offset)
}

@Test func sourceRangeVariableDeclWithoutInitializer() {
    let statements = parseStatements("let x")
    let decl = statements[0] as! AST.VariableDecl
    let range = decl.sourceRange!
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 5)
}

@Test func sourceRangeVariableDeclWithInitializer() {
    let statements = parseStatements("let x = 42")
    let decl = statements[0] as! AST.VariableDecl
    let range = decl.sourceRange!
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 10)
}

@Test func sourceRangeIntegerLiteral() {
    let expr = firstExpression("42")
    let sequentialExpression = expr as! AST.SequentialExpression
    let lit = sequentialExpression.operands[0] as! AST.IntegerLiteral
    let range = lit.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 16)
    #expect(range.start.line == 1)
    #expect(range.start.column == 15)
}

@Test func sourceRangeVariable() {
    let expr = firstExpression("x")
    let sequentialExpression = expr as! AST.SequentialExpression
    let varExpr = sequentialExpression.operands[0] as! AST.Variable
    let range = varExpr.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 15)
}

@Test func sourceRangeFunctionDeclBlockBody() {
    let statements = parseStatements("func main() {}")
    let decl = statements[0] as! AST.FunctionDecl
    let range = decl.sourceRange!
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 14)
}

@Test func sourceRangeFunctionDeclExpressionBody() {
    let statements = parseStatements("func foo() = 42")
    let decl = statements[0] as! AST.FunctionDecl
    let range = decl.sourceRange!
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 15)
}

@Test func sourceRangeModuleDecl() {
    let statements = parseStatements("module Foo {}")
    let module = statements[0] as! AST.ModuleDecl
    let range = module.sourceRange!
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 13)
}

@Test func sourceRangeCall() {
    let expr = firstExpression("foo()")
    let sequentialExpression = expr as! AST.SequentialExpression
    let call = sequentialExpression.operands[0] as! AST.Call
    let range = call.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 19)
}

@Test func sourceRangeMemberAccess() {
    let expr = firstExpression("a.b")
    let sequentialExpression = expr as! AST.SequentialExpression
    let member = sequentialExpression.operands[0] as! AST.MemberAccess
    let range = member.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 17)
}

@Test func sourceRangeChainedMemberAccess() {
    let expr = firstExpression("a.b.c")
    let sequentialExpression = expr as! AST.SequentialExpression
    let member = sequentialExpression.operands[0] as! AST.MemberAccess
    let range = member.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 19)
}

@Test func sourceRangeInfixExpression() {
    let expr = firstExpression("a + b")
    let sequentialExpression = expr as! AST.SequentialExpression
    let range = sequentialExpression.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 19)
}

@Test func sourceRangeReturnWithValue() {
    let body = parseBlockStatements("func main() { return 42 }")
    let ret = body[0] as! AST.Return
    let range = ret.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 23)
}

@Test func sourceRangeReturnWithoutValue() {
    let body = parseBlockStatements("func main() {\nreturn\n}")
    let ret = body[0] as! AST.Return
    let range = ret.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 20)
}

@Test func sourceRangeProgram() {
    let program = parse("let x let y")
    let range = program.sourceRange!
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 11)
}

@Test func sourceRangeErrorStatementIsNil() {
    let program = parse("")
    #expect(program.sourceRange == nil)
}

@Test func sourceRangeEmptyStatement() {
    let statements = parseStatements(";")
    let empty = statements[0] as! AST.EmptyStatement
    let range = empty.sourceRange!
    #expect(range.start.offset == 0)
    #expect(range.end.offset == 1)
}

@Test func sourceRangeExpressionStatement() {
    let body = parseBlockStatements("func main() { 42 }")
    let exprStmt = body[0] as! AST.ExpressionStatement
    let range = exprStmt.sourceRange!
    #expect(range.start.offset == 14)
    #expect(range.end.offset == 16)
}
