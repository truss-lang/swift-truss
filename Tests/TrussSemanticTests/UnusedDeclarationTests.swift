import Testing
import TrussCore

@Test func unusedLocalVariableIsWarned() {
    let (context, _) = runFullChecks(["func f() {\n    let x = 1\n}"], installBuiltin: true)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("unused variable 'x'"))
}

@Test func unusedParameterIsWarned() {
    let (context, _) = runFullChecks(
        ["func f(a: Builtin.Int32) {}"], installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("unused variable 'a'"))
}

@Test func underscoreParameterIsExempt() {
    let (context, _) = runFullChecks(
        ["func f(_a: Builtin.Int32) {}"], installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("unused variable '_a'") }))
}

@Test func usedLocalVariableIsNotWarned() {
    let (context, _) = runFullChecks(
        ["func f() -> Builtin.Int32 {\n    let x = 1\n    return x\n}"],
        installBuiltin: true
    )
    #expect(context.diagnositicEngine.diagnostics.isEmpty)
}

@Test func unusedPrivateFunctionIsWarned() {
    let (context, _) = runFullChecks(["private func g() {}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("function 'g' is never used"))
}

@Test func usedPrivateFunctionIsNotWarned() {
    let (context, _) = runFullChecks(
        ["private func g() { 1 }\nfunc f() {\n    g()\n}"]
    )
    #expect(context.diagnositicEngine.diagnostics.isEmpty)
}

@Test func unusedPrivateTypeIsWarned() {
    let (context, _) = runFullChecks(["private struct S {\n    let x: Builtin.Int32\n}"], installBuiltin: true)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("type 'S' is never used"))
}

@Test func unusedPrivateMemberIsWarned() {
    let (context, _) = runFullChecks(
        ["struct S {\n    private var m: Builtin.Int32\n}"], installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("member 'm' is never used"))
}

@Test func internalFunctionIsNotWarned() {
    let (context, _) = runFullChecks(["func f() { 1 }"])
    #expect(context.diagnositicEngine.diagnostics.isEmpty)
}

@Test func allowAttributeSuppressesWarnings() {
    let (context, _) = runFullChecks(
        ["#[allow(warning)]\nprivate func g() {\n    let x = 1\n}"]
    )
    #expect(context.diagnositicEngine.diagnostics.isEmpty)
}

@Test func emptyFunctionBodyIsWarned() {
    let (context, _) = runFullChecks(["func f() {}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("function has an empty body"))
}

@Test func allowAttributeSuppressesEmptyBodyWarning() {
    let (context, _) = runFullChecks(["#[allow(warning)]\nfunc f() {}"])
    #expect(context.diagnositicEngine.diagnostics.isEmpty)
}

@Test func duplicateConformanceIsError() {
    let (context, _) = runFullChecks(
        ["protocol P {}\nstruct S: P, P {}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("duplicate conformance to protocol 'P'"))
}

@Test func uniqueConformanceIsNotError() {
    let (context, _) = runFullChecks(
        ["protocol P {}\nprotocol Q {}\nstruct S: P, Q {}"]
    )
    #expect(context.diagnositicEngine.diagnostics.isEmpty)
}

@Test func unknownAttributeIsError() {
    let (context, _) = runFullChecks(["#[foo]\nfunc f() {}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("unknown attribute 'foo'"))
}

@Test func cnameAttributeIsAccepted() {
    let (context, _) = runFullChecks(
        ["#[cname(\"truss_f\")]\nfunc f() { 1 }"]
    )
    #expect(context.diagnositicEngine.diagnostics.isEmpty)
}
