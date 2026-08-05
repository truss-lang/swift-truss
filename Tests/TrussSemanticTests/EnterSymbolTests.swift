import Testing
import TrussCore

@Test func crossFileExtensionCycle() {
    let (context, programs) = runEnter([
        "struct A {} extension B { func useA() {} }",
        "struct B {} extension A { func useB() {} }",
    ])
    let packageScope = programs[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = packageScope.types["B"] as! Symbol.NominalTypeSymbol
    #expect(a.scope.values["useB"] != nil)
    #expect(b.scope.values["useA"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func pendingNestedExtensionConvergence() {
    let (context, program) = runEnter([
        "struct A {} extension A.B { class C {} } extension A { class B {} }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = a.scope.types["B"] as? Symbol.NominalTypeSymbol
    #expect(b != nil)
    let c = b!.scope.types["C"] as? Symbol.NominalTypeSymbol
    #expect(c != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func deepNestingAcrossFiles() {
    let (context, programs) = runEnter([
        "class A {}",
        "extension A { class B { let c: C } }",
        "extension A.B { class C {} }",
    ])
    let packageScope = programs[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = a.scope.types["B"] as? Symbol.NominalTypeSymbol
    #expect(b != nil)
    #expect(b!.scope.values["c"] != nil)
    let c = b!.scope.types["C"] as? Symbol.NominalTypeSymbol
    #expect(c != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionMemberLandsInBaseScope() {
    let (context, program) = runEnter(["struct S {} extension S { func f() {} }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    #expect(s.scope.values["f"] != nil)
    #expect(packageScope.values["f"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func memberFunctionAndLocals() {
    let (context, program) = runEnter(["struct S { func m() { var x = 1 } }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let m = s.scope.values["m"]?.first as? Symbol.FunctionSymbol
    #expect(m != nil)
    #expect(m!.scope.values["x"] != nil)
    #expect(packageScope.values["m"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func typeRedeclarationConflict() {
    let (context, _) = runEnter(["struct A {} struct A {}"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of type 'A'"))
}

@Test func typeRedeclarationAcrossFiles() {
    let (context, _) = runEnter(["struct A {}", "class A {}"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of type 'A'"))
}

@Test func extensionMemberKindConflictAtMerge() {
    let (context, _) = runEnter([
        "struct A {} extension A { var v: Int } extension A { var v: Int }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of 'v'"))
}

@Test func functionVariableKindConflict() {
    let (context, _) = runEnter(["func f() {} var f: Int"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of 'f'"))
}

@Test func overloadedFunctionsAllowed() {
    let (context, program) = runEnter(["func f() {} func f(x: Int) {}"])
    let packageScope = program[0].packageSymbol!.scope
    let symbols = packageScope.values["f"]
    #expect(symbols?.count == 2)
    #expect(symbols?.allSatisfy { $0 is Symbol.FunctionSymbol } == true)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionBaseNotFound() {
    let (context, _) = runEnter(["extension NotFound { func f() {} }"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("extension of type 'NotFound' has no matching declaration"))
}

@Test func caseSymbols() {
    let (context, program) = runEnter(["enum E { case a, b(Int32) }"])
    let packageScope = program[0].packageSymbol!.scope
    let e = packageScope.types["E"] as! Symbol.NominalTypeSymbol
    #expect(e.scope.values["a"]?.first is Symbol.CaseSymbol)
    #expect(e.scope.values["b"]?.first is Symbol.CaseSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericParamsOnTypeAndFunction() {
    let (context, program) = runEnter([
        "struct S3<E, each T> {} func f<G>() {}",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s3 = packageScope.types["S3"] as! Symbol.NominalTypeSymbol
    #expect(s3.scope.types["E"] is Symbol.GenericParamSymbol)
    #expect(s3.scope.types["T"] is Symbol.GenericParamSymbol)
    let f = packageScope.values["f"]?.first as? Symbol.FunctionSymbol
    #expect(f?.scope.types["G"] is Symbol.GenericParamSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func initAndSubscriptSymbols() {
    let (context, program) = runEnter([
        "struct S { init() {} subscript(i: Int) -> Int { 0 } }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    #expect(s.scope.values["init"]?.first is Symbol.FunctionSymbol)
    #expect(s.scope.values["subscript"]?.first is Symbol.FunctionSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func associatedTypeSymbol() {
    let (context, program) = runEnter(["protocol P { associatedtype T }"])
    let packageScope = program[0].packageSymbol!.scope
    let p = packageScope.types["P"] as! Symbol.NominalTypeSymbol
    #expect(p.scope.types["T"] is Symbol.NominalTypeSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func typealiasSymbol() {
    let (context, program) = runEnter(["typealias SS = (S) -> S struct S {}"])
    let packageScope = program[0].packageSymbol!.scope
    #expect(packageScope.types["SS"] is Symbol.TypeAliasSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedTypeInExtension() {
    let (context, program) = runEnter([
        "struct A {} extension A { class B { class D {} } }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = a.scope.types["B"] as? Symbol.NominalTypeSymbol
    #expect(b != nil)
    #expect(b!.scope.types["D"] is Symbol.NominalTypeSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionInsideModuleResolvesInModuleScope() {
    let (context, program) = runEnter([
        "module M { struct T {} extension T { func f() {} } }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let m = packageScope.modules["M"]
    let t = m?.scope.types["T"] as? Symbol.NominalTypeSymbol
    #expect(t != nil)
    #expect(t!.scope.values["f"] != nil)
    #expect(packageScope.values["f"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func overloadedFunctionsAcrossExtensions() {
    let (context, program) = runEnter([
        "struct A {} extension A { func f() {} } extension A { func f(x: Int) {} }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let symbols = a.scope.values["f"]
    #expect(symbols?.count == 2)
    #expect(symbols?.allSatisfy { $0 is Symbol.FunctionSymbol } == true)
    #expect(!context.diagnositicEngine.hasErrors)
}
