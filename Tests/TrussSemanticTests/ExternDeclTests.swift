import Testing
import TrussCore

private func externDiagnostics(_ source: String) -> [String] {
    let (context, _) = runEnter([source])
    return context.diagnositicEngine.diagnostics.map(\.message)
}

@Test func externAtTopLevelIsAllowed() {
    #expect(externDiagnostics(#"extern "C" { func foo() }"#).isEmpty)
}

@Test func externInModuleBlockIsAllowed() {
    #expect(externDiagnostics(#"module M { extern "C" { func foo() } }"#).isEmpty)
}

@Test func externInStructBodyIsError() {
    let messages = externDiagnostics(#"struct S { extern "C" { func foo() } }"#)
    #expect(messages.contains("extern declaration must be at top level"))
}

@Test func externInFunctionBodyIsError() {
    let messages = externDiagnostics(#"func f() { extern "C" { func foo() } }"#)
    #expect(messages.contains("extern declaration must be at top level"))
}

@Test func externInExtensionIsError() {
    let messages = externDiagnostics(#"struct S {} extension S { extern "C" { func foo() } }"#)
    #expect(messages.contains("extern declaration must be at top level"))
}
