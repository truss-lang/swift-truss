import Testing
import TrussCore

@Test func missingReturnIsError() {
    let (context, _) = runFullChecks(
        ["func f() -> Builtin.Int32 {\n    let x = 1\n}"], installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("missing return in a function") }))
}

@Test func explicitReturnIsNotMissing() {
    let (context, _) = runFullChecks(
        ["func f() -> Builtin.Int32 {\n    return 1\n}"], installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("missing return") }))
}

@Test func implicitExpressionReturnIsNotMissing() {
    let (context, _) = runFullChecks(
        ["func f() -> Builtin.Int32 {\n    1\n}"], installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("missing return") }))
}

@Test func ifWithoutElseHasMissingReturn() {
    let (context, _) = runFullChecks(
        ["func f(c: Builtin.Bool) -> Builtin.Int32 {\n    if c { return 1 }\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("missing return in a function") }))
}

@Test func ifElseBothReturnIsNotMissing() {
    let (context, _) = runFullChecks(
        ["func f(c: Builtin.Bool) -> Builtin.Int32 {\n    if c { return 1 } else { return 2 }\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("missing return") }))
}

@Test func voidFunctionWithoutReturnIsNotMissing() {
    let (context, _) = runFullChecks(["func f() {\n    let x = 1\n}"], installBuiltin: true)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("missing return") }))
}

@Test func breakOutsideLoopIsError() {
    let (context, _) = runFullChecks(["func f() {\n    break\n}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("'break' outside of a loop"))
}

@Test func continueOutsideLoopIsError() {
    let (context, _) = runFullChecks(["func f() {\n    continue\n}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("'continue' outside of a loop"))
}

@Test func breakInsideLoopIsNotError() {
    let (context, _) = runFullChecks(["func f(c: Builtin.Bool) {\n    while c { break }\n}"], installBuiltin: true)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("outside of a loop") }))
}

@Test func gotoUnknownLabelIsError() {
    let (context, _) = runFullChecks(["func f() {\n    goto nowhere\n}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find label 'nowhere' for 'goto'"))
}

@Test func gotoKnownLabelIsNotError() {
    let (context, _) = runFullChecks(["func f() {\n    goto done\n    done: return\n}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("cannot find label") }))
}

@Test func unreachableCodeIsWarned() {
    let (context, _) = runFullChecks(["func f() {\n    return\n    let x = 1\n}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("unreachable code"))
}

@Test func redundantReturnIsUnreachable() {
    let (context, _) = runFullChecks(["func f() {\n    return\n    return\n}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("unreachable code"))
}

@Test func constantConditionIsWarned() {
    let (context, _) = runFullChecks(["func f() {\n    while true {}\n}"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("condition is always true"))
}

@Test func emptyCatchIsWarned() {
    let (context, _) = runFullChecks(["func f() {\n    do { 1 } catch { }\n}"], installBuiltin: true)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("empty catch block"))
}
