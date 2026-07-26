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
         (.Unowned, .Unowned), (.Indirect, .Indirect):
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
    #expect(lit!.token.value == "\"hello\"")
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
    let (_, diagnostics) = parseWithDiagnostics("func main() { var a: Int = 0 { willSet {} didSet {} } }")
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

@Test func parseStructWithGenericPlainParametersDropped() {
    let statements = parseStatements("struct Foo<T, U> {}")
    #expect(statements.count == 1)
    let decl = statements[0] as? AST.StructDecl
    #expect(decl != nil)
    #expect(decl!.genericDecl != nil)
    #expect(decl!.genericDecl!.generics.isEmpty)
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
    #expect(decl!.genericDecl!.generics.count == 1)
    #expect(decl!.genericDecl!.generics[0].name.value == "U")
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

// MARK: - Generic Application

@Test func parseGenericApplicationSingleArg() {
    let expr = firstExpression("Foo::<Int>")
    let generic = expr as? AST.GenericApplication
    #expect(generic != nil)
    let base = generic!.base as? AST.Variable
    #expect(base != nil)
    #expect(base!.name.value == "Foo")
    #expect(generic!.genericArguments.count == 1)
    let arg = generic!.genericArguments[0] as? AST.Variable
    #expect(arg != nil)
    #expect(arg!.name.value == "Int")
}

@Test func parseGenericApplicationMultipleArgs() {
    let expr = firstExpression("Foo::<Int, String>")
    let generic = expr as? AST.GenericApplication
    #expect(generic != nil)
    #expect(generic!.genericArguments.count == 2)
    let arg0 = generic!.genericArguments[0] as? AST.Variable
    #expect(arg0 != nil)
    #expect(arg0!.name.value == "Int")
    let arg1 = generic!.genericArguments[1] as? AST.Variable
    #expect(arg1 != nil)
    #expect(arg1!.name.value == "String")
}

// MARK: - Parenthesized Expression

@Test func parseParenthesizedVariable() {
    let expr = firstExpression("(x)")
    let varExpr = expr as? AST.Variable
    #expect(varExpr != nil)
    #expect(varExpr!.name.value == "x")
}

@Test func parseParenthesizedSequentialExpression() {
    let expr = firstExpression("(a + b)")
    let seq = expr as? AST.SequentialExpression
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
    let ifExpr = member!.object as? AST.If
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
    let afterPlusOffset = source.distance(from: source.startIndex, to: source.index(after: plusIndex))
    #expect(op.start.offset == afterPlusOffset)
}

@Test func parseOperatorOnlyReturnsErrorExpression() {
    let body = parseBlockStatements("func main() { + }")
    #expect(body.count == 1)
    let exprStmt = body[0] as? AST.ExpressionStatement
    #expect(exprStmt != nil)
    #expect(exprStmt!.expression is AST.ErrorExpression)
}

@Test func parseEmptyParenthesesReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func main() { () }")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count == 1)
    #expect(errors[0].message == "expected expression after '('")
}

@Test func parseOperatorOnlyInConformanceReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("struct Foo: + {}")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    let expr = errors.first { $0.message == "expected expression after operator '+'" }
    #expect(expr != nil)
}

@Test func parseOperatorOnlyInReturnTypeReportsError() throws {
    let (_, diagnostics) = parseWithDiagnostics("func foo() -> + {}")
    let errors = diagnostics.filter { $0.severity == .error }
    try #require(errors.count >= 1)
    let expr = errors.first { $0.message == "expected expression after operator '+'" }
    #expect(expr != nil)
}
