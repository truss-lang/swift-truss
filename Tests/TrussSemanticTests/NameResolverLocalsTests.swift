import Testing
import TrussCore
import TrussSemantics

final class SymbolProbe: AST.Visitor {
    var variables: [AST.Variable] = []
    var selfExpressions: [AST.SelfExpression] = []
    var superExpressions: [AST.SuperExpression] = []
    var memberAccesses: [AST.MemberAccess] = []
    var implicitMembers: [AST.ImplicitMemberAccess] = []

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
}

func probe(_ source: String) -> (Context, SymbolProbe) {
    let (context, programs) = runEnter([source])
    NameResolver(context: context).visitProgram(programs[0])
    let probe = SymbolProbe()
    probe.visitProgram(programs[0])
    return (context, probe)
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

@Test func closureLocalsIsolated() {
    let (context, probe) = probe(
        "func makeClosures() { let c1 = { var x = 1 x } let c2 = { var x = 2 x } }")
    let xs = probe.variables.filter { $0.name.value == "x" }
    #expect(xs.count == 2)
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

@Test func typeMemberResolvedFromTypeBody() {
    let (context, probe) = probe("struct S { func f() {} func g() { f() } }")
    let variable = probe.variables.first { $0.name.value == "f" }
    #expect(variable?.overloads?.count == 1)
    #expect(variable?.symbol == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func selfResolvedToCurrentType() {
    let (context, probe) = probe("struct S { var x: Int func m() { self } }")
    #expect(probe.selfExpressions.count == 1)
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

@Test func superResolvedToSuperclass() {
    let (context, probe) = probe(
        "class A { func f() {} } class B: A { func g() { super } }")
    #expect(probe.superExpressions.count == 1)
    #expect(probe.superExpressions[0].symbol?.name == "A")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func superclassResolvedFromFirstInheritanceClause() {
    let (context, programs) = runEnter(["class A {} class B: A {} class C: A, B {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let packageScope = programs[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = packageScope.types["B"] as! Symbol.NominalTypeSymbol
    let c = packageScope.types["C"] as! Symbol.NominalTypeSymbol
    #expect(b.superclass === a)
    #expect(c.superclass === a)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func protocolConformanceIsNotSuperclass() {
    let (context, programs) = runEnter(["protocol P {} class D: P {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let packageScope = programs[0].packageSymbol!.scope
    let d = packageScope.types["D"] as! Symbol.NominalTypeSymbol
    #expect(d.superclass == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func implicitMemberAccessResolvedInTypeBody() {
    let (context, probe) = probe("struct S { var f: Int func m() { .f } }")
    #expect(probe.implicitMembers.count == 1)
    #expect(probe.implicitMembers[0].symbol is Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}
