import Testing
import TrussCore

@Test func downcastWithAsIsAllowed() {
    let (context, _) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func f(a: Animal) -> Dog {
            let d: Dog = a as Dog
            return d
        }
        """],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("expected 'Dog'") }))
}

@Test func isTestAllowsDowncast() {
    let (context, _) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func f(a: Animal) -> Builtin.Bool {
            return a is Dog
        }
        """],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("expected 'Dog'") }))
}

@Test func asPatternBindsVariable() {
    let (context, _) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func f(a: Animal) -> Builtin.Int32 {
            let result = match a {
            d as Dog => { let r: Dog = d; 1 }
            _ => { 0 }
            }
            return result
        }
        """],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("cannot find 'd'") }))
    #expect(!messages.contains(where: { $0.contains("expected 'Dog'") }))
}
