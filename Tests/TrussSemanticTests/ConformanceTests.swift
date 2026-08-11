import Testing
import TrussCore
import TrussSemantics

private func packageScope(_ programs: [AST.Program]) -> Scope {
    programs[0].packageSymbol!.scope
}

@Test func structConformsProtocol() throws {
    let (context, programs) = runEnter(["protocol P {} struct S: P {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    try #require(s.conformances.count == 1)
    #expect(s.conformances[0].name == "P")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func enumAndActorAndProtocolConform() {
    let (context, programs) = runEnter(
        ["protocol P {} enum E: P {} actor A: P {} protocol R: P {}"]
    )
    NameResolver(context: context).visitProgram(programs[0])
    let scope = packageScope(programs)
    let e = scope.types["E"] as! Symbol.EnumSymbol
    let a = scope.types["A"] as! Symbol.ActorSymbol
    let r = scope.types["R"] as! Symbol.ProtocolSymbol
    #expect(e.conformances.map(\.name) == ["P"])
    #expect(a.conformances.map(\.name) == ["P"])
    #expect(r.conformances.map(\.name) == ["P"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func classInheritsAndConforms() {
    let (context, programs) = runEnter(["protocol P {} class B {} class C: B, P {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let c = packageScope(programs).types["C"] as! Symbol.ClassSymbol
    #expect(c.superclass?.name == "B")
    #expect(c.conformances.map(\.name) == ["P"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func classConformsWithoutSuperclass() {
    let (context, programs) = runEnter(["protocol P {} class C: P {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let c = packageScope(programs).types["C"] as! Symbol.ClassSymbol
    #expect(c.superclass == nil)
    #expect(c.conformances.map(\.name) == ["P"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func protocolCompositionFlattens() {
    let (context, programs) = runEnter(["protocol P {} protocol Q {} struct S: P & Q {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    #expect(s.conformances.map(\.name) == ["P", "Q"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericProtocolConformanceResolved() {
    let (context, programs) = runEnter(["protocol P {} struct S: P<Int32> {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    #expect(s.conformances.map(\.name) == ["P"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericProtocolCompositionResolved() {
    let (context, programs) = runEnter(
        ["protocol P {} protocol Q {} struct S: P<Int32> & Q {}"]
    )
    NameResolver(context: context).visitProgram(programs[0])
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    #expect(s.conformances.map(\.name) == ["P", "Q"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func unknownConformanceSilentlyIgnored() {
    let (context, programs) = runEnter(["struct S: Unknown {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    #expect(s.conformances.isEmpty)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func structConformingClassSilentlyIgnored() {
    let (context, programs) = runEnter(["class C {} struct S: C {}"])
    NameResolver(context: context).visitProgram(programs[0])
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    #expect(s.conformances.isEmpty)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionConformanceMergedIntoBase() {
    let (context, programs) = runEnter(["protocol P {} struct S {} extension S: P {}"])
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    #expect(s.conformances.map(\.name) == ["P"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionCompositionAndUnknownConformance() {
    let (context, programs) = runEnter(
        ["protocol P {} protocol Q {} struct S {} extension S: P & Q, Unknown {}"]
    )
    let s = packageScope(programs).types["S"] as! Symbol.StructSymbol
    #expect(s.conformances.map(\.name) == ["P", "Q"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionConformanceInPendingBase() {
    let (context, programs) = runEnter(
        ["extension A.B { func f() {} }", "struct A {} extension A { class B {} }"]
    )
    let scope = packageScope(programs)
    let a = scope.types["A"] as! Symbol.StructSymbol
    let b = a.scope.types["B"] as! Symbol.ClassSymbol
    #expect(b.scope.values["f"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func associatedTypeGetsOwnSymbol() {
    let (context, programs) = runEnter(["protocol P { associatedtype T }"])
    let p = packageScope(programs).types["P"] as! Symbol.ProtocolSymbol
    #expect(p.scope.types["T"] is Symbol.AssociatedTypeSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nominalKindsDistinct() {
    let (context, programs) = runEnter(
        ["struct S {} class C {} enum E {} protocol P {} actor A {}"]
    )
    let scope = packageScope(programs)
    #expect(scope.types["S"] is Symbol.StructSymbol)
    #expect(scope.types["C"] is Symbol.ClassSymbol)
    #expect(scope.types["E"] is Symbol.EnumSymbol)
    #expect(scope.types["P"] is Symbol.ProtocolSymbol)
    #expect(scope.types["A"] is Symbol.ActorSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionWithModulePrefixConformanceMerged() {
    let (context, programs) = runEnter([
        "protocol P {} module M { struct T {} } extension M.T: P {}",
    ])
    let t = packageScope(programs).modules["M"]!.scope.types["T"] as! Symbol.StructSymbol
    #expect(t.conformances.map(\.name) == ["P"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionWithModulePrefixProtocolResolved() {
    let (context, programs) = runEnter([
        "module X { protocol Q {} } module M { struct T {} } extension M.T: X.Q {}",
    ])
    let t = packageScope(programs).modules["M"]!.scope.types["T"] as! Symbol.StructSymbol
    #expect(t.conformances.map(\.name) == ["Q"])
    #expect(!context.diagnositicEngine.hasErrors)
}
