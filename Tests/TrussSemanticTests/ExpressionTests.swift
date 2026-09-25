import Testing
import TrussCore

private let assignmentPrelude = """
precedencegroup Assignment { assignment: true }
infix operator =: Assignment

"""

private let compoundAssignmentPrelude = """
precedencegroup Assignment { assignment: true }
infix operator =: Assignment
infix operator >>>=: Assignment
func >>>=(lhs: Builtin.Int32, rhs: Builtin.Int32) -> Builtin.Int32 {
    return Builtin.builtin_add_int32(lhs, rhs)
}

"""

private let nonAssignmentCompoundPrelude = """
precedencegroup NotAssignment { assignment: false }
infix operator >>>=: NotAssignment
func >>>=(lhs: Builtin.Int32, rhs: Builtin.Int32) -> Builtin.Int32 {
    return Builtin.builtin_add_int32(lhs, rhs)
}

"""

@Test func assignToLetMemberInInitIsAllowed() {
    let (context, _) = runFullChecks(
        [assignmentPrelude + "struct S {\n    let x: Builtin.Int32\n    init(x: Builtin.Int32) { self.x = x }\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("cannot assign to immutable") }))
}

@Test func assignToLetMemberOutsideInitIsError() {
    let (context, _) = runFullChecks(
        [assignmentPrelude +
            "struct S {\n    let x: Builtin.Int32\n    init(x: Builtin.Int32) { self.x = x }\n    func set() { self.x = 1 }\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot assign to immutable variable 'x'"))
}

@Test func assignToVarIsAllowed() {
    let (context, _) = runFullChecks(
        [assignmentPrelude + "func f() {\n    var x = 1\n    x = 2\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("cannot assign to immutable") }))
}

@Test func assignToLetIsError() {
    let (context, _) = runFullChecks(
        [assignmentPrelude + "func f() {\n    let y = 1\n    y = 2\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot assign to immutable variable 'y'"))
}

@Test func compoundAssignmentOperatorOnLetIsError() {
    let (context, _) = runFullChecks(
        [compoundAssignmentPrelude + "func f() {\n    let a = 1\n    a >>>= 2\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.filter { $0 == "cannot assign to immutable variable 'a'" }.count == 1)
}

@Test func compoundLookingOperatorWithoutAssignmentGroupOnLetIsAllowed() {
    let (context, _) = runFullChecks(
        [nonAssignmentCompoundPrelude + "func f() {\n    let a = 1\n    a >>>= 2\n}"],
        installBuiltin: true
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("cannot assign to immutable") }))
}

@Test func matchNotExhaustiveIsError() {
    let (context, _) = runFullChecks(
        ["enum E {\n    case A\n    case B\n}\nfunc f(e: E) {\n    match e {\n    .A => { }\n    }\n}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("match is not exhaustive") }))
}

@Test func matchExhaustiveIsNotError() {
    let (context, _) = runFullChecks(
        ["enum E {\n    case A\n    case B\n}\nfunc f(e: E) {\n    match e {\n    .A => { }\n    .B => { }\n    }\n}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("match is not exhaustive") }))
}

@Test func matchWildcardIsExhaustive() {
    let (context, _) = runFullChecks(
        ["enum E {\n    case A\n    case B\n}\nfunc f(e: E) {\n    match e {\n    .A => { }\n    _ => { }\n    }\n}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("match is not exhaustive") }))
}

@Test func doCatchMatchingIsExhaustive() {
    let (context, _) = runFullChecks(
        ["struct E {\n    init() {}\n}\nfunc f() {\n    do {\n        throw E()\n    } catch E {\n    }\n}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("catch is not exhaustive") }))
}

@Test func doCatchWildcardIsExhaustive() {
    let (context, _) = runFullChecks(
        ["struct E {}\nfunc f() {\n    do {\n        throw E()\n    } catch {\n    }\n}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("catch is not exhaustive") }))
}

@Test func callToThrowingFunctionMustBeTried() {
    let (context, _) = runFullChecks(
        ["struct E {}\nfunc g() throws(E) { E() }\nfunc f() {\n    g()\n}"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("call to throwing function must be tried"))
}
