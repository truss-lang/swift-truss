import Testing
import TrussCore

@Test func patternBindingUnusedIsWarned() {
    let (context, _) = runFullChecks(
        ["enum E {\n    case A(Builtin.Int32)\n}\nfunc f(e: E) {\n    match e {\n    .A(let x) => { }\n    }\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("unused variable 'x'"))
}

@Test func patternBindingUsedIsNotWarned() {
    let (context, _) = runFullChecks(
        ["enum E {\n    case A(Builtin.Int32)\n}\nfunc f(e: E) {\n    match e {\n    .A(let x) => { x }\n    }\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("unused variable 'x'") }))
}

@Test func wildcardPatternBindingIsNotWarned() {
    let (context, _) = runFullChecks(
        ["enum E {\n    case A\n}\nfunc f(e: E) {\n    match e {\n    _ => { }\n    }\n}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("unused variable") }))
}
