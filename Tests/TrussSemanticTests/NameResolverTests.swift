import Testing
import TrussCore
import TrussSemantics

final class SymbolProbe: AST.Visitor {
    var variables: [AST.Variable] = []
    var selfExpressions: [AST.SelfExpression] = []
    var superExpressions: [AST.SuperExpression] = []
    var memberAccesses: [AST.MemberAccess] = []
    var implicitMembers: [AST.ImplicitMemberAccess] = []
    var keyPaths: [AST.KeyPathExpression] = []

    override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        variables.append(variable)
        return super.visitVariable(variable, additional: additional)
    }

    override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        selfExpressions.append(selfExpression)
        return super.visitSelfExpression(selfExpression, additional: additional)
    }

    override func visitSuperExpression(
        _ superExpression: AST.SuperExpression, additional: Any? = nil
    ) -> Any? {
        superExpressions.append(superExpression)
        return super.visitSuperExpression(superExpression, additional: additional)
    }

    override func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        memberAccesses.append(memberAccess)
        return super.visitMemberAccess(memberAccess, additional: additional)
    }

    override func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        implicitMembers.append(implicitMemberAccess)
        return super.visitImplicitMemberAccess(implicitMemberAccess, additional: additional)
    }

    override func visitKeyPathExpression(
        _ keyPathExpression: AST.KeyPathExpression, additional: Any? = nil
    ) -> Any? {
        keyPaths.append(keyPathExpression)
        return super.visitKeyPathExpression(keyPathExpression, additional: additional)
    }
}

func probe(_ source: String) -> (Context, SymbolProbe) {
    let (context, programs) = runEnter([source])
    NameResolver(context: context).visitProgram(programs[0])
    let probe = SymbolProbe()
    probe.visitProgram(programs[0])
    return (context, probe)
}

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
    guard case let .Block(statements) = caller.body else { return }
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
    guard case let .Block(statements) = caller.body else { return }
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

@Test func functionParameterResolved() {
    let (context, probe) = probe("func f(x: Int) -> Int { return x }")
    let variable = probe.variables.first { $0.name.value == "x" }
    #expect(variable?.symbol?.name == "x")
    #expect(variable?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func closureParameterResolved() {
    let (context, probe) = probe("func g() { let c = { (y: Int) in y } }")
    let variable = probe.variables.first { $0.name.value == "y" }
    #expect(variable?.symbol?.name == "y")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func closureLocalsIsolated() throws {
    let (context, probe) = probe(
        "func makeClosures() { let c1 = { var x = 1 x } let c2 = { var x = 2 x } }")
    let xs = probe.variables.filter { $0.name.value == "x" }
    try #require(xs.count == 2)
    #expect(xs.allSatisfy { $0.symbol is Symbol.VariableSymbol })
    #expect(xs[0].symbol !== xs[1].symbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func forInVariableResolved() {
    let (context, probe) = probe("func h(xs: [Int]) { for i in xs { i } }")
    let variable = probe.variables.first { $0.name.value == "i" }
    #expect(variable?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func optionalBindingResolved() {
    let (context, probe) = probe("func h(a: Int?) { if let x = a { x } }")
    let variable = probe.variables.first { $0.name.value == "x" }
    #expect(variable?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func casePatternBindingResolved() {
    let (context, probe) = probe(
        "enum E { case foo(Int) } func h(e: E) { if case .foo(let y) = e { y } }")
    let variable = probe.variables.first { $0.name.value == "y" }
    #expect(variable?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func forInVariableResolvedWithWhereClause() {
    let (context, probe) = probe("func h(xs: [Int]) { for i in xs where i > 0 { i } }")
    let iVariables = probe.variables.filter { $0.name.value == "i" }
    #expect(iVariables.count == 3)
    #expect(iVariables.allSatisfy { $0.symbol is Symbol.VariableSymbol })
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func forCasePatternBindingResolvedWithWhereClause() {
    let (context, probe) = probe(
        "enum E { case foo(Int) } func h(xs: [E]) { for case .foo(let x) in xs where x > 0 { x } }")
    let xs = probe.variables.filter { $0.name.value == "x" }
    #expect(xs.count == 2)
    #expect(xs.allSatisfy { $0.symbol is Symbol.VariableSymbol })
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func typeMemberResolvedFromTypeBody() {
    let (context, probe) = probe("struct S { func f() {} func g() { f() } }")
    let variable = probe.variables.first { $0.name.value == "f" }
    #expect(variable?.overloads?.count == 1)
    #expect(variable?.symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func selfResolvedToCurrentType() throws {
    let (context, probe) = probe("struct S { var x: Int func m() { self } }")
    try #require(probe.selfExpressions.count == 1)
    #expect(probe.selfExpressions[0].symbol?.name == "S")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func selfMemberAccessResolved() {
    let (context, probe) = probe("struct S { var x: Int func m() { self.x } }")
    let member = probe.memberAccesses.first { $0.member.value == "x" }
    #expect(member?.symbol is Symbol.VariableSymbol)
    #expect(member?.symbol?.name == "x")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func superResolvedToSuperclass() throws {
    let (context, probe) = probe(
        "class A { func f() {} } class B: A { func g() { super } }")
    try #require(probe.superExpressions.count == 1)
    #expect(probe.superExpressions[0].symbol?.name == "A")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func superclassResolvedFromFirstInheritanceClause() {
    let (context, programs) = runEnter(["class A {} class B: A {} class C: A, B {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let packageScope = programs[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = packageScope.types["B"] as! Symbol.ClassSymbol
    let c = packageScope.types["C"] as! Symbol.ClassSymbol
    #expect(b.superclass === a)
    #expect(c.superclass === a)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericSuperclassResolved() {
    let (context, programs) = runEnter(["class A {} class B: A<Int32> {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let packageScope = programs[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = packageScope.types["B"] as! Symbol.ClassSymbol
    #expect(b.superclass === a)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func protocolConformanceIsNotSuperclass() {
    let (context, programs) = runEnter(["protocol P {} class D: P {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let packageScope = programs[0].packageSymbol!.scope
    let d = packageScope.types["D"] as! Symbol.ClassSymbol
    #expect(d.superclass == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func implicitMemberAccessResolvedInTypeBody() throws {
    let (context, probe) = probe("struct S { var f: Int func m() { .f } }")
    try #require(probe.implicitMembers.count == 1)
    #expect(probe.implicitMembers[0].symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func staticModifierParsedInTypeBody() throws {
    let (context, probe) = probe("struct S { static func f() {} func m() { .f } }")
    try #require(probe.implicitMembers.count == 1)
    #expect(probe.implicitMembers[0].overloads?.count == 1)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func inheritedMemberResolvedThroughSelf() {
    let (context, probe) = probe(
        "class A { func base() {} } class B: A { func m() { self.base() } }")
    let member = probe.memberAccesses.first { $0.member.value == "base" }
    #expect(member?.overloads?.count == 1)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func inheritedMemberResolvedThroughMultiLevelChain() {
    let (context, probe) = probe(
        "class A { func x() {} } class B: A {} class C: B { func m() { self.x() } }")
    let member = probe.memberAccesses.first { $0.member.value == "x" }
    #expect(member?.overloads?.count == 1)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func inheritedMemberResolvedThroughImplicitMember() throws {
    let (context, probe) = probe(
        "class A { func base() {} } class B: A { func m() { .base } }")
    try #require(probe.implicitMembers.count == 1)
    #expect(probe.implicitMembers[0].overloads?.count == 1)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathRootResolvedToType() throws {
    let (context, probe) = probe("struct Person { var name: Int } func f() { let k = \\Person.name }")
    let keyPath = probe.keyPaths[0]
    let root = keyPath.root as? AST.Variable
    #expect(root?.symbol is Symbol.NominalTypeSymbol)
    #expect((root?.symbol as? Symbol.NominalTypeSymbol)?.name == "Person")
    try #require(keyPath.components.count == 1)
    #expect(keyPath.components[0].symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathFunctionMemberOverloadsCollected() {
    let (context, probe) = probe(
        "struct S { func g() {} func g(x: Int) {} } func f() { let k = \\S.g }")
    let keyPath = probe.keyPaths[0]
    #expect(keyPath.components[0].symbol == nil)
    #expect(keyPath.components[0].overloads?.count == 2)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathNestedTypePrefixContinued() {
    let (context, probe) = probe(
        "struct A { struct B { var c: Int } } func f() { let k = \\A.B.c }")
    let keyPath = probe.keyPaths[0]
    #expect((keyPath.root as? AST.Variable)?.symbol is Symbol.NominalTypeSymbol)
    #expect(keyPath.components[0].symbol is Symbol.NominalTypeSymbol)
    #expect((keyPath.components[0].symbol as? Symbol.NominalTypeSymbol)?.name == "B")
    #expect(keyPath.components[1].symbol is Symbol.VariableSymbol)
    #expect((keyPath.components[1].symbol as? Symbol.VariableSymbol)?.name == "c")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathModulePrefixContinued() {
    let (context, probe) = probe(
        "module M { struct T { var v: Int } } func f() { let k = \\M.T.v }")
    let keyPath = probe.keyPaths[0]
    #expect((keyPath.root as? AST.Variable)?.symbol is Symbol.ModuleSymbol)
    #expect(keyPath.components[0].symbol is Symbol.NominalTypeSymbol)
    #expect((keyPath.components[0].symbol as? Symbol.NominalTypeSymbol)?.name == "T")
    #expect(keyPath.components[1].symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathNoRootComponentsUnresolved() {
    let (context, probe) = probe("func f() { let k = \\.name }")
    let keyPath = probe.keyPaths[0]
    #expect(keyPath.root == nil)
    #expect(keyPath.components[0].symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathInstanceMemberStopsResolution() {
    let (context, probe) = probe("struct P { var a: Int } func f() { let k = \\P.a.b }")
    let keyPath = probe.keyPaths[0]
    #expect(keyPath.components[0].symbol is Symbol.VariableSymbol)
    #expect(keyPath.components[1].symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathSelfComponentResolvedToBase() {
    let (context, probe) = probe("struct P {} func f() { let k = \\P.self }")
    let keyPath = probe.keyPaths[0]
    #expect(keyPath.components[0].symbol is Symbol.NominalTypeSymbol)
    #expect((keyPath.components[0].symbol as? Symbol.NominalTypeSymbol)?.name == "P")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathValueRootStopsResolution() {
    let (context, probe) = probe("var p = 1 func f() { let k = \\p.name }")
    let keyPath = probe.keyPaths[0]
    #expect((keyPath.root as? AST.Variable)?.symbol is Symbol.VariableSymbol)
    #expect(keyPath.components[0].symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathUnknownMemberStaysNil() {
    let (context, probe) = probe("struct P { var a: Int } func f() { let k = \\P.missing }")
    let keyPath = probe.keyPaths[0]
    #expect(keyPath.components[0].symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionSelfResolved() throws {
    let (context, probe) = probe("struct S { var x: Int } extension S { func m() { self } }")
    try #require(probe.selfExpressions.count == 1)
    #expect(probe.selfExpressions[0].symbol?.name == "S")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionSelfMemberAccessResolved() {
    let (context, probe) = probe("struct S { var x: Int } extension S { func m() { self.x } }")
    let member = probe.memberAccesses.first { $0.member.value == "x" }
    #expect(member?.symbol is Symbol.VariableSymbol)
    #expect(member?.symbol?.name == "x")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionImplicitMemberResolved() throws {
    let (context, probe) = probe("struct S { var f: Int } extension S { func m() { .f } }")
    try #require(probe.implicitMembers.count == 1)
    #expect(probe.implicitMembers[0].symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionMemberFunctionReferenceResolved() {
    let (context, probe) = probe(
        "struct S {} extension S { func a() {} func b() { a() } }")
    let variable = probe.variables.first { $0.name.value == "a" }
    #expect(variable?.overloads?.count == 1)
    #expect(variable?.symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionSuperResolved() throws {
    let (context, probe) = probe(
        "class A {} class B: A {} extension B { func m() { super } }")
    try #require(probe.superExpressions.count == 1)
    #expect(probe.superExpressions[0].symbol?.name == "A")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionOfModuleTypeSelfResolved() {
    let (context, probe) = probe(
        "module M { struct T { var v: Int } } extension M.T { func m() { self.v } }")
    let member = probe.memberAccesses.first { $0.member.value == "v" }
    #expect(member?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionUnresolvedBaseFallsBackSilently() {
    let (context, probe) = probe("extension NotFound { func m() { self } }")
    #expect(probe.selfExpressions[0].symbol == nil)
}

@Test func initParameterResolvedInBody() {
    let (context, probe) = probe(
        "struct S { var x: Int init(x: Int) { self.x = x } }")
    let variable = probe.variables.first {
        $0.name.value == "x" && $0.symbol is Symbol.VariableSymbol
    }
    #expect(variable != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func subscriptParameterResolvedInBody() {
    let (context, probe) = probe("struct S { subscript(i: Int) -> Int { i } }")
    let variable = probe.variables.first { $0.name.value == "i" }
    #expect(variable?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func setterImplicitParameterResolved() {
    let (context, probe) = probe(
        "struct S { var x: Int { get { return 0 } set { x = newValue } } }")
    let variable = probe.variables.first { $0.name.value == "newValue" }
    #expect(variable?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func setterNamedParameterResolved() {
    let (context, probe) = probe(
        "struct S { var x: Int { get { return 0 } set(value) { x = value } } }")
    let variable = probe.variables.first { $0.name.value == "value" }
    #expect(variable?.symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func modulePrefixSuperclassResolved() {
    let (context, programs) = runEnter(["module M { class C {} } class D: M.C {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let packageScope = programs[0].packageSymbol!.scope
    let d = packageScope.types["D"] as! Symbol.ClassSymbol
    let c = packageScope.modules["M"]!.scope.types["C"] as! Symbol.ClassSymbol
    #expect(d.superclass === c)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func ifLetShorthandShadowResolved() {
    let (context, program) = resolve("func f(x: Int?) { if let x { g(x) } }")
    let functionDecl = program.statements[0] as! AST.FunctionDecl
    guard case let .Block(statements) = functionDecl.body else { return }
    let ifExpr = (statements[0] as! AST.ExpressionStatement).expression as! AST.If
    let binding = ifExpr.condition as! AST.OptionalBinding
    let value = binding.value as! AST.Variable
    let paramSymbol = functionDecl.symbol!.scope.values["x"]![0]
    #expect(value.symbol === paramSymbol)
    let call = (ifExpr.then[0] as! AST.ExpressionStatement).expression as! AST.Call
    let arg = call.arguments[0].value as! AST.Variable
    #expect(arg.symbol is Symbol.VariableSymbol)
    #expect(arg.symbol !== paramSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func ifLetExplicitShadowResolved() {
    let (context, program) = resolve("func f(x: Int?) { if let x = x { g(x) } }")
    let functionDecl = program.statements[0] as! AST.FunctionDecl
    guard case let .Block(statements) = functionDecl.body else { return }
    let ifExpr = (statements[0] as! AST.ExpressionStatement).expression as! AST.If
    let binding = ifExpr.condition as! AST.OptionalBinding
    let value = binding.value as! AST.Variable
    let paramSymbol = functionDecl.symbol!.scope.values["x"]![0]
    #expect(value.symbol === paramSymbol)
    let call = (ifExpr.then[0] as! AST.ExpressionStatement).expression as! AST.Call
    let arg = call.arguments[0].value as! AST.Variable
    #expect(arg.symbol is Symbol.VariableSymbol)
    #expect(arg.symbol !== paramSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func ifBodyLocalsIsolatedFromOuterScope() {
    let (context, program) = resolve("func f(c: Bool) { if c { let x = 1 } }")
    let functionDecl = program.statements[0] as! AST.FunctionDecl
    let functionScope = functionDecl.symbol!.scope
    #expect(functionScope.values["x"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}
