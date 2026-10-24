import Testing
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax

func firstBodyExpression(_ program: AST.Program) -> AST.Expression {
    var statements = program.statements
    if let moduleDecl = statements[0] as? AST.ModuleDecl {
        statements = moduleDecl.body
    }
    let funcDecl = statements.first(where: { $0 is AST.FunctionDecl }) as! AST.FunctionDecl
    let body = if case let .Block(stmts) = funcDecl.body {
        stmts
    } else {
        []
    }
    let exprStmt = body[0] as! AST.ExpressionStatement
    return exprStmt.expression
}

func bodyExpression(
    _ program: AST.Program, at index: Int
) -> AST.Expression {
    let funcDecl = program.statements.first(where: { $0 is AST.FunctionDecl }) as! AST.FunctionDecl
    let body = if case let .Block(stmts) = funcDecl.body {
        stmts
    } else {
        []
    }
    let exprStmt = body[index] as! AST.ExpressionStatement
    return exprStmt.expression
}

func binary(_ expr: AST.Expression?, op: String) -> AST.Binary? {
    guard let expr, let binary = expr as? AST.Binary, binary.operatorToken.value == op else {
        return nil
    }
    return binary
}

func integer(_ expr: AST.Expression?, _ value: String) -> Bool {
    (expr as? AST.IntegerLiteral)?.token.value == value
}

func variable(_ expr: AST.Expression?, _ name: String) -> Bool {
    (expr as? AST.Variable)?.name.value == name
}

@Test
func foldByPrecedenceRank() {
    let (context, _, programs) = runFolded([
        "precedencegroup A {} precedencegroup B { higherThan: A } "
            + "precedencegroup C { higherThan: B } infix operator +: B infix operator *: C "
            + "func main() { 1 + 2 * 3 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "+")
    #expect(integer(root?.left, "1"))
    let right = binary(root?.right, op: "*")
    #expect(integer(right?.left, "2"))
    #expect(integer(right?.right, "3"))
}

@Test
func foldThreeLevelChain() {
    let (context, _, programs) = runFolded([
        "precedencegroup A {} precedencegroup B { higherThan: A associativity: left } "
            + "precedencegroup C { higherThan: B } infix operator +: B infix operator -: B "
            + "infix operator *: C func main() { 1 + 2 * 3 - 4 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "-")
    let left = binary(root?.left, op: "+")
    #expect(integer(left?.left, "1"))
    let middle = binary(left?.right, op: "*")
    #expect(integer(middle?.left, "2"))
    #expect(integer(middle?.right, "3"))
    #expect(integer(root?.right, "4"))
}

@Test
func foldLeftAssociative() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { associativity: left } infix operator -: P "
            + "func main() { 1 - 2 - 3 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "-")
    let left = binary(root?.left, op: "-")
    #expect(integer(left?.left, "1"))
    #expect(integer(left?.right, "2"))
    #expect(integer(root?.right, "3"))
}

@Test
func mixedChainKeepsHigherPrecedencePairs() {
    let (context, _, programs) = runFolded([
        "precedencegroup Assignment { assignment: true } "
            + "precedencegroup LogicalAnd { higherThan: Assignment } "
            + "precedencegroup Comparison { higherThan: LogicalAnd } "
            + "precedencegroup Addition { higherThan: Comparison associativity: left } "
            + "precedencegroup Multiplication { higherThan: Addition associativity: left } "
            + "infix operator &&: LogicalAnd infix operator >=: Comparison "
            + "infix operator +: Addition infix operator -: Addition "
            + "infix operator *: Multiplication infix operator /: Multiplication "
            + "func main() { 1 + 2 && 3 * 4 - 5 / 6 >= 7 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "&&")
    let lhs = binary(root?.left, op: "+")
    #expect(integer(lhs?.left, "1"))
    #expect(integer(lhs?.right, "2"))
    let cmp = binary(root?.right, op: ">=")
    #expect(integer(cmp?.right, "7"))
    let sub = binary(cmp?.left, op: "-")
    let mul = binary(sub?.left, op: "*")
    #expect(integer(mul?.left, "3"))
    #expect(integer(mul?.right, "4"))
    let div = binary(sub?.right, op: "/")
    #expect(integer(div?.left, "5"))
    #expect(integer(div?.right, "6"))
}

@Test
func foldRightAssociative() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { associativity: right } infix operator >>: P "
            + "func main() { 1 >> 2 >> 3 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: ">>")
    let right = binary(root?.right, op: ">>")
    #expect(integer(root?.left, "1"))
    #expect(integer(right?.left, "2"))
    #expect(integer(right?.right, "3"))
}

@Test
func assignmentGroupForcesRightFold() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { assignment: true } infix operator =: P "
            + "func main() { a = b = c }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "=")
    let right = binary(root?.right, op: "=")
    #expect(variable(root?.left, "a"))
    #expect(variable(right?.left, "b"))
    #expect(variable(right?.right, "c"))
}

@Test
func nonAssociativeChainReportsError() {
    let (context, _, programs) = runFolded([
        "precedencegroup P {} infix operator <: P func main() { 1 < 2 < 3 }",
    ])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(messages(context).contains("operator '<' is non-associative"))
    let root = binary(firstBodyExpression(programs[0]), op: "<")
    #expect(binary(root?.left, op: "<") != nil)
}

@Test
func unrelatedGroupsReportError() {
    let (context, _, programs) = runFolded([
        "precedencegroup A {} precedencegroup B {} infix operator &&: A infix operator *: B "
            + "func main() { 1 && 2 * 3 }",
    ])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(
        messages(context).contains(
            "adjacent operators are in unrelated precedence groups 'A' and 'B'"
        )
    )
    #expect(binary(firstBodyExpression(programs[0]), op: "*") != nil)
    let root = binary(firstBodyExpression(programs[0]), op: "*")
    #expect(binary(root?.left, op: "&&") != nil)
}

@Test
func unknownOperatorReportsError() {
    let (context, _, programs) = runFolded(["func main() { 1 + 2 }"])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(messages(context).contains("unknown operator '+'"))
    #expect(binary(firstBodyExpression(programs[0]), op: "+") != nil)
}

@Test
func ungroupedOperatorReportsError() {
    let (context, _, programs) = runFolded([
        "infix operator + func main() { 1 + 2 }",
    ])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(messages(context).contains("infix operator '+' has no precedence group"))
    #expect(binary(firstBodyExpression(programs[0]), op: "+") != nil)
}

@Test
func notInfixOperatorReportsError() {
    let (context, _, _) = runFolded([
        "prefix operator - func main() { 1 - 2 }",
    ])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(messages(context).contains("operator '-' is not infix"))
}

@Test
func notPrefixOperatorReportsError() {
    let (context, _, programs) = runFolded([
        "infix operator % func main() { %1 }",
    ])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(messages(context).contains("operator '%' is not prefix"))
    let expr = firstBodyExpression(programs[0]) as? AST.Prefix
    #expect(expr?.operatorToken.value == "%")
    #expect(integer(expr?.expression, "1"))
}

@Test
func prefixInfixMixFolds() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { associativity: left } prefix operator - infix operator -: P "
            + "infix operator *: P func main() { -a * b }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "*")
    let left = root?.left as? AST.Prefix
    #expect(left?.operatorToken.value == "-")
    #expect(variable(left?.expression, "a"))
    #expect(variable(root?.right, "b"))
}

@Test
func postfixInfixMixFolds() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { associativity: left } postfix operator ! infix operator *: P "
            + "func main() { a! * b }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "*")
    let left = root?.left as? AST.ForceUnwrap
    #expect(variable(left?.expression, "a"))
    #expect(variable(root?.right, "b"))
}

@Test
func prefixRunWrapsRightToLeft() {
    let (context, _, programs) = runFolded([
        "prefix operator - func main() { - -a }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let outer = firstBodyExpression(programs[0]) as? AST.Prefix
    let inner = outer?.expression as? AST.Prefix
    #expect(outer?.operatorToken.value == "-")
    #expect(inner?.operatorToken.value == "-")
    #expect(variable(inner?.expression, "a"))
}

@Test
func postfixWrapsOperand() {
    let (context, _, programs) = runFolded([
        "postfix operator ! func main() { a! }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let outer = firstBodyExpression(programs[0]) as? AST.ForceUnwrap
    #expect(variable(outer?.expression, "a"))
}

@Test
func infixWithPrefixOnRight() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { associativity: left } prefix operator - infix operator -: P "
            + "func main() { a - -b }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "-")
    #expect(variable(root?.left, "a"))
    let right = root?.right as? AST.Prefix
    #expect(right?.operatorToken.value == "-")
    #expect(variable(right?.expression, "b"))
}

@Test
func parentheticalInnerFolds() {
    let (context, _, programs) = runFolded([
        "precedencegroup A {} precedencegroup B { higherThan: A } infix operator +: A "
            + "infix operator *: B func main() { (1 + 2) * 3 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "*")
    let paren = root?.left as? AST.Parenthetical
    let inner = binary(paren?.inner, op: "+")
    #expect(integer(inner?.left, "1"))
    #expect(integer(inner?.right, "2"))
    #expect(integer(root?.right, "3"))
}

@Test
func parentheticalSurvivesFolding() {
    let (context, _, programs) = runFolded([
        "struct S {}\nfunc id(_ x: S) -> S { x }\nfunc main() {\n"
            + "    let f: (S) -> S = ((id))\n    (f)\n}",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    #expect(AST.Dumper().dump(programs[0]).contains("ParentheticalExpression"))
}

@Test
func parentheticalFunctionReferenceKeepsOverloads() throws {
    let (context, _, programs) = runFolded([
        "struct S {}\nfunc id(_ x: S) -> S { x }\nfunc main() {\n    let f = (id)\n}",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let funcDecl = programs[0].statements.first {
        ($0 as? AST.FunctionDecl)?.name.value == "main"
    } as! AST.FunctionDecl
    guard case let .Block(statements) = funcDecl.body else {
        Issue.record("main has no block body")
        return
    }
    let variableDecl = statements[0] as! AST.VariableDecl
    let parenthetical = try #require(variableDecl.initializer as? AST.Parenthetical)
    let initializer = try #require(parenthetical.inner as? AST.Variable)
    #expect(initializer.name.value == "id")
    #expect(initializer.overloads?.count == 1)
}

@Test
func ifConditionFolds() {
    let (context, _, programs) = runFolded([
        "precedencegroup A {} precedencegroup B { higherThan: A } infix operator +: A "
            + "infix operator *: B func main() { if 1 + 2 * 3 { 4 + 5 } }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let funcDecl = programs[0].statements.first(where: { $0 is AST.FunctionDecl }) as! AST.FunctionDecl
    let body = if case let .Block(stmts) = funcDecl.body {
        stmts
    } else {
        []
    }
    let ifStmt = (body[0] as! AST.ExpressionStatement).expression as! AST.If
    let condition = binary(ifStmt.condition, op: "+")
    #expect(integer(condition?.left, "1"))
    #expect(binary(condition?.right, op: "*") != nil)
    let thenExpr = (ifStmt.then[0] as! AST.ExpressionStatement).expression
    #expect(binary(thenExpr, op: "+") != nil)
}

@Test
func callArgumentsFold() {
    let (context, _, programs) = runFolded([
        "precedencegroup A {} precedencegroup B { higherThan: A } infix operator +: A "
            + "infix operator *: B func main() { f(1 + 2 * 3) }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let call = firstBodyExpression(programs[0]) as? AST.Call
    let arg = binary(call?.arguments[0].value, op: "+")
    #expect(integer(arg?.left, "1"))
    #expect(binary(arg?.right, op: "*") != nil)
}

@Test
func moduleScopedOperatorFolds() {
    let (context, _, programs) = runFolded([
        "module M { infix operator +: P precedencegroup P { associativity: left } "
            + "func f() { 1 + 2 } }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    #expect(binary(firstBodyExpression(programs[0]), op: "+") != nil)
}

@Test
func moduleIsolationReportsUnknownOperator() {
    let (context, _, _) = runFolded([
        "module M { infix operator +: P precedencegroup P {} } func main() { 1 + 2 }",
    ])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(messages(context).contains("unknown operator '+'"))
}

@Test
func cycleSkipsFolding() {
    let (context, _, programs) = runFolded([
        "precedencegroup A { higherThan: B } precedencegroup B { higherThan: A } "
            + "infix operator +: A func main() { 1 + 2 }",
    ])
    #expect(context.diagnosticEngine.hasErrors)
    #expect(firstBodyExpression(programs[0]) is AST.Sequential)
}

@Test
func genericApplicationSequenceLeftUnfolded() {
    let (context, _, programs) = runFolded([
        "infix operator <: P infix operator >: P precedencegroup P {} "
            + "func main() { Array<Int32> }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    #expect(firstBodyExpression(programs[0]) is AST.Sequential)
}

@Test
func genericApplicationFoldsSingleArg() {
    let (context, _, programs) = runFolded([
        "struct Array {} func main() { Array<Int32> }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let app = firstBodyExpression(programs[0]) as? AST.GenericApplication
    #expect(variable(app?.base, "Array"))
    #expect(app?.genericArguments.count == 1)
    #expect(variable(app?.genericArguments.first, "Int32"))
}

@Test
func genericApplicationFoldsMultipleArgs() {
    let (context, _, programs) = runFolded([
        "struct Array {} func main() { Array<Int32, String> }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let app = firstBodyExpression(programs[0]) as? AST.GenericApplication
    #expect(variable(app?.base, "Array"))
    #expect(app?.genericArguments.count == 2)
    #expect(variable(app?.genericArguments[0], "Int32"))
    #expect(variable(app?.genericArguments[1], "String"))
}

@Test
func genericApplicationFoldsNested() {
    let (context, _, programs) = runFolded([
        "struct Array {} func main() { Array<Array<Int32>> }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let app = firstBodyExpression(programs[0]) as? AST.GenericApplication
    #expect(variable(app?.base, "Array"))
    #expect(app?.genericArguments.count == 1)
    let inner = app?.genericArguments[0] as? AST.GenericApplication
    #expect(variable(inner?.base, "Array"))
    #expect(variable(inner?.genericArguments.first, "Int32"))
}

@Test
func genericApplicationThenInfixFolds() {
    let (context, _, programs) = runFolded([
        "struct Array {} precedencegroup P { associativity: left } infix operator +: P "
            + "func main() { Array<Int32> + 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "+")
    let left = root?.left as? AST.GenericApplication
    #expect(variable(left?.base, "Array"))
    #expect(variable(left?.genericArguments.first, "Int32"))
    #expect(integer(root?.right, "1"))
}

@Test
func genericApplicationCallAndMemberAccess() {
    let (context, _, programs) = runFolded([
        "struct Array {} func main() { Array<Int32>()\nArray<Int32>.f }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let call = bodyExpression(programs[0], at: 0) as? AST.Call
    #expect((call?.callee as? AST.GenericApplication) != nil)
    #expect(call?.arguments.isEmpty == true)
    let member = bodyExpression(programs[0], at: 1) as? AST.MemberAccess
    #expect((member?.object as? AST.GenericApplication) != nil)
    #expect(member?.member.value == "f")
}

@Test
func genericApplicationAssignRemainder() {
    let (context, _, programs) = runFolded([
        "struct X<T> {} precedencegroup P {} infix operator =: P func main() { X<Int32>=5 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "=")
    let left = root?.left as? AST.GenericApplication
    #expect(variable(left?.base, "X"))
    #expect(variable(left?.genericArguments.first, "Int32"))
    #expect(integer(root?.right, "5"))
}

@Test
func genericApplicationMemberBase() {
    let (context, _, programs) = runFolded([
        "struct Outer { struct Inner {} } func main() { Outer.Inner<Int32> }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let app = firstBodyExpression(programs[0]) as? AST.GenericApplication
    let base = app?.base as? AST.MemberAccess
    #expect(base?.member.value == "Inner")
    #expect(variable(app?.genericArguments.first, "Int32"))
}

@Test
func genericApplicationGenericParamBase() {
    let (context, _, programs) = runFolded([
        "struct S<T> {} func main() { S<T> }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let app = firstBodyExpression(programs[0]) as? AST.GenericApplication
    #expect(variable(app?.base, "S"))
    #expect(variable(app?.genericArguments.first, "T"))
}

@Test
func comparisonChainNotMisFolded() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { associativity: left } infix operator <: P infix operator >: P "
            + "func main() { 1 < 2 > 3 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: ">")
    #expect(binary(root?.left, op: "<") != nil)
    #expect(integer(root?.right, "3"))
}

@Test
func singleComparisonNotMisFolded() {
    let (context, _, programs) = runFolded([
        "precedencegroup P { associativity: left } infix operator <: P func main() { a < b }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "<")
    #expect(variable(root?.left, "a"))
    #expect(variable(root?.right, "b"))
}

func parameterType(_ program: AST.Program, function: String) -> AST.Expression? {
    let funcDecl = program.statements.first {
        ($0 as? AST.FunctionDecl)?.name.value == function
    } as? AST.FunctionDecl
    return funcDecl?.parameters.first?.type
}

func runFoldedTyped(_ sources: [String]) -> (Context, [AST.Program]) {
    let context = Context()
    Builtin.install(context: context)
    var programs: [AST.Program] = []
    for source in sources {
        let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
        context.register(source: src)
        let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
        let preprocessed = Preprocessor(context: context).process(
            lexerResult, config: PreprocessorConfig()
        )
        programs.append(Parser(context: context, packageName: "main", preprocessed).parse())
    }
    for program in programs {
        TrussSemantics.DeclCollector(context: context).visitProgram(program)
        Enter(context: context).visitProgram(program)
    }
    let merger = MergePass(context: context)
    for program in programs {
        merger.visitProgram(program)
    }
    merger.resolvePending()
    for program in programs {
        NameResolver(context: context).visitProgram(program)
    }
    let table = OperatorTable()
    for program in programs {
        TrussOperator.DeclCollector(table: table, context: context).visitProgram(program)
    }
    PrecedenceResolver(table: table, context: context).resolve()
    let folder = ExpressionFolder(context: context, table: table)
    let folded: [AST.Program] = programs.map { folder.rewrite($0) }
    for program in folded {
        TypeBuilder(context: context).visitProgram(program)
    }
    TypeChecker(context: context).checkAll(folded)
    return (context, folded)
}

@Test
func genericApplicationWithClosureTypeArgument() {
    let (context, _, programs) = runFolded([
        "struct Box<T> { let v: T } "
            + "func take(_ c: Box<(Int32) -> Int32>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let application = parameterType(programs[0], function: "take") as? AST.GenericApplication
    #expect(variable(application?.base, "Box"))
    #expect(application?.genericArguments.count == 1)
    let closure = application?.genericArguments.first as? AST.ClosureType
    #expect(closure?.parameters.count == 1)
    #expect(variable(closure?.parameters.first?.type, "Int32"))
    #expect(variable(closure?.returnType, "Int32"))
}

@Test
func genericApplicationWithFunctionTypeArgument() {
    let (context, _, programs) = runFolded([
        "struct Box<T> { let v: T } "
            + "func take(_ c: Box<func() -> Void>) -> Void { }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let application = parameterType(programs[0], function: "take") as? AST.GenericApplication
    #expect(variable(application?.base, "Box"))
    #expect(application?.genericArguments.count == 1)
    let functionType = application?.genericArguments.first as? AST.FunctionType
    #expect(functionType?.parameters.count == 0)
    #expect(variable(functionType?.returnType, "Void"))
}

@Test
func genericApplicationWithClosureTypeAsLastArgument() {
    let (context, _, programs) = runFolded([
        "struct Pair<A, B> { let a: A let b: B } "
            + "func take(_ p: Pair<Int32, (Int32) -> Int32>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let application = parameterType(programs[0], function: "take") as? AST.GenericApplication
    #expect(variable(application?.base, "Pair"))
    #expect(application?.genericArguments.count == 2)
    #expect(variable(application?.genericArguments[0], "Int32"))
    let closure = application?.genericArguments[1] as? AST.ClosureType
    #expect(variable(closure?.returnType, "Int32"))
}

@Test
func genericApplicationWithNestedClosureTypeArgument() {
    let (context, _, programs) = runFolded([
        "struct Box<T> { let v: T } "
            + "func take(_ c: Box<Box<(Int32) -> Int32>>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let outer = parameterType(programs[0], function: "take") as? AST.GenericApplication
    #expect(variable(outer?.base, "Box"))
    let inner = outer?.genericArguments.first as? AST.GenericApplication
    #expect(variable(inner?.base, "Box"))
    let closure = inner?.genericArguments.first as? AST.ClosureType
    #expect(variable(closure?.returnType, "Int32"))
}

@Test
func genericApplicationWithClosureTypeEffects() {
    let (context, _, programs) = runFolded([
        "struct Box<T> { let v: T } "
            + "func takeAsync(_ c: Box<(Int32) async -> Int32>) -> Int32 { return 1 } "
            + "func takeThrows(_ c: Box<(Int32) throws -> Int32>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let asyncApplication = parameterType(programs[0], function: "takeAsync") as? AST.GenericApplication
    let asyncClosure = asyncApplication?.genericArguments.first as? AST.ClosureType
    #expect(asyncClosure?.asyncToken != nil)
    #expect(asyncClosure?.throwsClause == nil)
    let throwsApplication = parameterType(programs[0], function: "takeThrows") as? AST.GenericApplication
    let throwsClosure = throwsApplication?.genericArguments.first as? AST.ClosureType
    #expect(throwsClosure?.asyncToken == nil)
    #expect(throwsClosure?.throwsClause != nil)
}

@Test
func genericApplicationWithCurriedClosureTypeArgument() {
    let (context, _, programs) = runFolded([
        "struct Box<T> { let v: T } "
            + "func take(_ c: Box<(Int32) -> (Int32) -> Int32>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let application = parameterType(programs[0], function: "take") as? AST.GenericApplication
    let outerClosure = application?.genericArguments.first as? AST.ClosureType
    let innerClosure = outerClosure?.returnType as? AST.ClosureType
    #expect(innerClosure?.parameters.count == 1)
    #expect(variable(innerClosure?.returnType, "Int32"))
}

@Test
func genericApplicationWithClosureTypeArgumentInstantiatesClosureType() {
    let (context, programs) = runFoldedTyped([
        "typealias Int32 = Builtin.Int32 struct Box<T> { let v: T } "
            + "func take(_ c: Box<(Int32) -> Int32>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let parameter = parameterType(programs[0], function: "take")
    let instantiation = parameter?.ty as? TrussType.GenericInstantiation
    #expect(instantiation?.base.name == "Box")
    #expect(instantiation?.arguments.count == 1)
    let closure = instantiation?.arguments.first as? TrussType.ClosureType
    #expect(closure?.parameters.count == 1)
    #expect((closure?.parameters.first?.type as? TrussType.BuiltinType)?.name == "Int32")
    #expect((closure?.returnType as? TrussType.BuiltinType)?.name == "Int32")
    let dump = AST.Dumper().dump(programs[0])
    #expect(dump.contains("ty:Generic(StructType(Box)"))
    #expect(dump.contains("(Builtin.Int32) -> Builtin.Int32"))
    #expect(!dump.contains("SequentialExpression"))
}

@Test
func genericApplicationWithFunctionTypeArgumentInstantiatesFunctionType() {
    let (context, programs) = runFoldedTyped([
        "struct Box<T> { let v: T } "
            + "func take(_ c: Box<func() -> Void>) -> Void { }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let parameter = parameterType(programs[0], function: "take")
    let instantiation = parameter?.ty as? TrussType.GenericInstantiation
    #expect(instantiation?.base.name == "Box")
    let functionType = instantiation?.arguments.first as? TrussType.FunctionType
    #expect(functionType?.parameters.count == 0)
}

@Test
func existingGenericApplicationsKeepTheirShape() {
    let (context, _, programs) = runFolded([
        "struct Box<T> { let v: T }\nstruct Pair<A, B> { let a: A let b: B }\n"
            + "func single(_ c: Box<Int32>) -> Int32 { return 1 }\n"
            + "func tuple(_ c: Box<(Int32, Int32)>) -> Int32 { return 1 }\n"
            + "func nested(_ c: Box<Box<Int32>>) -> Int32 { return 1 }\n"
            + "func closureFirst(_ p: Pair<(Int32) -> Int32, Int32>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let single = parameterType(programs[0], function: "single") as? AST.GenericApplication
    #expect(variable(single?.base, "Box"))
    #expect(variable(single?.genericArguments.first, "Int32"))
    let tuple = parameterType(programs[0], function: "tuple") as? AST.GenericApplication
    #expect((tuple?.genericArguments.first as? AST.Tuple) != nil)
    let nested = parameterType(programs[0], function: "nested") as? AST.GenericApplication
    #expect((nested?.genericArguments.first as? AST.GenericApplication) != nil)
    let closureFirst = parameterType(programs[0], function: "closureFirst") as? AST.GenericApplication
    #expect((closureFirst?.genericArguments[0] as? AST.ClosureType) != nil)
    #expect(variable(closureFirst?.genericArguments[1], "Int32"))
}

@Test
func typeSymbolComparisonWithoutCloserStillFoldsAsBinary() {
    let (context, _, programs) = runFolded([
        "struct A {} struct B {} precedencegroup P { associativity: left } "
            + "infix operator <: P func main() { A < B }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let root = binary(firstBodyExpression(programs[0]), op: "<")
    #expect(variable(root?.left, "A"))
    #expect(variable(root?.right, "B"))
}

@Test
func genericApplicationWithNestedGenericClosureReturnTypeFolds() {
    let (context, _, programs) = runFolded([
        "struct Box<T> { let v: T }\n"
            + "func take(_ c: Box<(Int32) -> Box<Int32>>) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let outer = parameterType(programs[0], function: "take") as? AST.GenericApplication
    #expect(variable(outer?.base, "Box"))
    let closure = outer?.genericArguments.first as? AST.ClosureType
    let inner = closure?.returnType as? AST.GenericApplication
    #expect(variable(inner?.base, "Box"))
    #expect(variable(inner?.genericArguments.first, "Int32"))
}

@Test
func shiftOperatorsStayBinary() {
    let (context, _, programs) = runFolded([
        "precedencegroup S { associativity: none } infix operator <<: S infix operator >>: S\n"
            + "func main() {\n    a << b\n    a >> c\n}",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let leftShift = binary(bodyExpression(programs[0], at: 0), op: "<<")
    #expect(variable(leftShift?.left, "a"))
    #expect(variable(leftShift?.right, "b"))
    let rightShift = binary(bodyExpression(programs[0], at: 1), op: ">>")
    #expect(variable(rightShift?.left, "a"))
    #expect(variable(rightShift?.right, "c"))
}

@Test
func protocolCompositionStaysComposition() {
    let (context, _, programs) = runFolded([
        "protocol P {}\nprotocol Q {}\n"
            + "func take(_ c: some P & Q) -> Int32 { return 1 }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let someType = parameterType(programs[0], function: "take") as? AST.SomeType
    let composition = someType?.wrappedType as? AST.ProtocolCompositionType
    #expect(composition?.types.count == 2)
}

@Test
func explicitGenericCallStaysGenericApplication() {
    let (context, _, programs) = runFolded([
        "func main() { id<Int32>(1) }\nfunc id<T>(_ x: T) -> T { return x }",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let call = firstBodyExpression(programs[0]) as? AST.Call
    #expect((call?.callee as? AST.GenericApplication) != nil)
}
