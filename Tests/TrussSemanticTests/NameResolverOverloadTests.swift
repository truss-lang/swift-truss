import Testing
import TrussCore
import TrussSemantics

func resolve(_ source: String) -> (Context, AST.Program) {
    let (context, programs) = runEnter([source])
    NameResolver(context: context).visitProgram(programs[0])
    return (context, programs[0])
}

@Test func valueReferenceOverloadsCollected() {
    let (context, program) = resolve("func f() {} func f(x: Int) {} let g = f")
    let decl = program.statements[2] as! AST.VariableDecl
    let initializer = decl.initializer as! AST.Variable
    #expect(initializer.overloads?.count == 2)
    #expect(initializer.overloads?.allSatisfy { $0.name == "f" } == true)
    #expect(initializer.symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func singleCandidateAlsoCollected() {
    let (context, program) = resolve("func g() {} let h = g")
    let decl = program.statements[1] as! AST.VariableDecl
    let initializer = decl.initializer as! AST.Variable
    #expect(initializer.overloads?.count == 1)
    #expect(initializer.symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nonFunctionBindingUntouched() {
    let (context, program) = resolve("var x: Int = 0 let y = x")
    let x = program.statements[0] as! AST.VariableDecl
    #expect(x.symbol != nil)
    let decl = program.statements[1] as! AST.VariableDecl
    let initializer = decl.initializer as! AST.Variable
    #expect(initializer.symbol is Symbol.VariableSymbol)
    #expect(initializer.overloads == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func localVariableShadowsOverloads() {
    let (context, program) = resolve(
        "func f() {} func f(x: Int) {} func caller() { var f: Int = 0 let x = f }")
    let caller = program.statements[2] as! AST.FunctionDecl
    guard case .Block(let statements) = caller.body else { return }
    let decl = statements[1] as! AST.VariableDecl
    let initializer = decl.initializer as! AST.Variable
    #expect(initializer.symbol is Symbol.VariableSymbol)
    #expect(initializer.overloads == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedTypeMemberResolved() {
    let (context, program) = resolve("struct A { struct B {} } let x = A.B")
    let decl = program.statements[1] as! AST.VariableDecl
    let member = decl.initializer as! AST.MemberAccess
    #expect(member.symbol?.name == "B")
    #expect(member.symbol is Symbol.NominalTypeSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func moduleMemberFunctionCollected() {
    let (context, program) = resolve("module M { func f() {} } let x = M.f")
    let decl = program.statements[1] as! AST.VariableDecl
    let member = decl.initializer as! AST.MemberAccess
    #expect(member.overloads?.count == 1)
    #expect(member.symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func moduleFunctionOverloadsCollected() {
    let (context, program) = resolve(
        "module M { func f() {} func f(x: Int) {} } let x = M.f")
    let decl = program.statements[1] as! AST.VariableDecl
    let member = decl.initializer as! AST.MemberAccess
    #expect(member.overloads?.count == 2)
    #expect(member.symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func enumCaseMemberResolved() {
    let (context, program) = resolve("enum E { case c } let x = E.c")
    let decl = program.statements[1] as! AST.VariableDecl
    let member = decl.initializer as! AST.MemberAccess
    #expect(member.symbol is Symbol.CaseSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func chainedTypeMemberResolved() {
    let (context, program) = resolve("module M { struct A { struct B {} } } let x = M.A.B")
    let decl = program.statements[1] as! AST.VariableDecl
    let outer = decl.initializer as! AST.MemberAccess
    let inner = outer.object as! AST.MemberAccess
    #expect(outer.symbol?.name == "B")
    #expect(outer.symbol is Symbol.NominalTypeSymbol)
    #expect(inner.symbol?.name == "A")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func instanceMemberSkipped() {
    let (context, program) = resolve(
        "struct S { var x: Int } func caller() { let s: S = S() s.x }")
    let caller = program.statements[1] as! AST.FunctionDecl
    guard case .Block(let statements) = caller.body else { return }
    let member = (statements[1] as! AST.ExpressionStatement).expression as! AST.MemberAccess
    #expect(member.symbol == nil)
    #expect(member.overloads == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func memberNotFoundLeavesNil() {
    let (context, program) = resolve("struct A {} let x = A.zzz")
    let decl = program.statements[1] as! AST.VariableDecl
    let member = decl.initializer as! AST.MemberAccess
    #expect(member.symbol == nil)
    #expect(member.overloads == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func functionSignatureCached() {
    let (context, programs) = runEnter([
        "func f(_ a: Int, b: Int = 0, xs: Int...) {} func g(i: Int32, ...) {} "
            + "struct S { init(x: Int) {} subscript(i: Int) -> Int { 0 } }",
    ])
    let packageScope = programs[0].packageSymbol!.scope
    let f = (packageScope.values["f"]![0] as! Symbol.FunctionSymbol).signature
    #expect(f.labels == [nil, "b", "xs"])
    #expect(f.hasDefaults == [false, true, false])
    #expect(f.isVararg == [false, false, true])
    let g = (packageScope.values["g"]![0] as! Symbol.FunctionSymbol).signature
    #expect(g.labels == ["i", nil])
    #expect(g.isVararg == [false, true])
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let initSig = (s.scope.values["init"]![0] as! Symbol.FunctionSymbol).signature
    #expect(initSig.labels == ["x"])
    let subSig = (s.scope.values["subscript"]![0] as! Symbol.FunctionSymbol).signature
    #expect(subSig.labels == ["i"])
    #expect(!context.diagnositicEngine.hasErrors)
}
