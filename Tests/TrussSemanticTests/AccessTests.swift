import Testing
import TrussCore
import TrussSemantics

func expectAccessError(_ sources: [String], _ message: String) {
    let (context, _) = runChecks(sources)
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(message), "missing: \(message) in \(messages)")
}

func expectAccessNoError(_ sources: [String]) {
    let (context, _) = runChecks(sources)
    #expect(
        !context.diagnositicEngine.hasErrors,
        "unexpected errors: \(context.diagnositicEngine.diagnostics.map(\.message))"
    )
}

@Test func privateMemberCrossType() {
    expectAccessError(
        [
            "struct S {\n    init() {}\n    private func f() {}\n}\nstruct T {\n    func g() {\n        let s = S()\n        s.f()\n    }\n}",
        ],
        "'f' is private"
    )
}

@Test func privateMemberSameType() {
    expectAccessNoError(
        ["struct S {\n    private func f() {}\n    func g() {\n        f()\n    }\n}"]
    )
}

@Test func privateMemberSameFileExtension() {
    expectAccessNoError(
        ["struct S {\n    private func f() {}\n}\nextension S {\n    func g() {\n        f()\n    }\n}"]
    )
}

@Test func privateTopLevelSameFile() {
    expectAccessNoError(["private struct S {\n    init() {}\n}\nfunc use() {\n    let s = S()\n}"])
}

@Test func filePrivateCrossFile() {
    expectAccessError(
        [
            "struct S {\n    init() {}\n    fileprivate func f() {}\n}",
            "func use(s: S) {\n    s.f()\n}",
        ],
        "'f' is fileprivate"
    )
}

@Test func internalCrossModule() {
    expectAccessError(
        [
            "module A {\n    struct S {\n        init() {}\n        func f() {}\n    }\n}",
            "module B {\n    func use(s: A.S) {\n        s.f()\n    }\n}",
        ],
        "'f' is internal"
    )
}

@Test func internalSameModule() {
    expectAccessNoError(
        [
            "module A {\n    struct S {\n        init() {}\n        func f() {}\n    }\n    func use() {\n        let s = S()\n        s.f()\n    }\n}",
        ]
    )
}

@Test func protectedSubclassAccess() {
    expectAccessNoError(
        ["class A {\n    protected func f() {}\n}\nclass B: A {\n    func g() {\n        self.f()\n    }\n}"]
    )
}

@Test func protectedUnrelatedType() {
    expectAccessError(
        ["class A {\n    protected func f() {}\n}\nclass C {\n    func h(a: A) {\n        a.f()\n    }\n}"],
        "'f' is protected"
    )
}

@Test func protectedCrossModuleSubclass() {
    expectAccessNoError(
        [
            "module M1 {\n    open class A {\n        protected func f() {}\n    }\n}",
            "module M2 {\n    class B: M1.A {\n        func g() {\n            self.f()\n        }\n    }\n}",
        ]
    )
}

@Test func publicAccessibleEverywhere() {
    expectAccessNoError(
        ["module A {\n    public struct S {\n        public func f() {}\n    }\n}"]
    )
}

@Test func typeLeakInParameter() {
    expectAccessError(
        ["private struct T {}\npublic struct S {\n    public func f(p: T) {}\n}"],
        "method 'f' must be declared private because its parameter uses a private type 'T'"
    )
}

@Test func typeLeakInReturn() {
    expectAccessError(
        [
            "private struct T {\n    init() {}\n}\npublic struct S {\n    public func f() -> T {\n        return T()\n    }\n}",
        ],
        "method 'f' must be declared private because its return type uses a private type 'T'"
    )
}

@Test func privateTypeCrossScope() {
    expectAccessError(
        ["struct S {\n    private struct T {}\n}\nstruct U {\n    var t: S.T\n}"],
        "'T' is private"
    )
}

@Test func superclassLeak() {
    expectAccessError(
        ["private class A {}\npublic class B: A {}"],
        "'B' must be declared private because its superclass 'A' is private"
    )
}

@Test func finalClassInheritance() {
    expectAccessError(
        ["final class A {}\nclass B: A {}"],
        "cannot inherit from final class 'A'"
    )
}

@Test func overrideWithoutTarget() {
    expectAccessError(
        ["class A {}\nclass B: A {\n    override func f() {}\n}"],
        "method 'f' does not override any method from its superclass"
    )
}

@Test func overrideMissingKeyword() {
    expectAccessError(
        ["open class A {\n    open func f() {}\n}\nclass B: A {\n    func f() {}\n}"],
        "overriding declaration requires an 'override' keyword"
    )
}

@Test func overrideNonOpenMember() {
    expectAccessError(
        ["class A {\n    func f() {}\n}\nclass B: A {\n    override func f() {}\n}"],
        "cannot override non-open member 'f'"
    )
}

@Test func overrideFinalMember() {
    expectAccessError(
        ["open class A {\n    protected final func f() {}\n}\nclass B: A {\n    override func f() {}\n}"],
        "cannot override final member 'f'"
    )
}

@Test func overrideValid() {
    expectAccessNoError(
        ["open class A {\n    open func f() {}\n}\nclass B: A {\n    override func f() {}\n}"]
    )
}

@Test func abstractClassInstantiation() {
    expectAccessError(
        ["abstract class A {\n    abstract func f()\n}\nfunc use() {\n    let a = A()\n}"],
        "cannot instantiate abstract class 'A'"
    )
}

@Test func abstractMemberMissingImplementation() {
    expectAccessError(
        ["abstract class A {\n    abstract func f()\n}\nclass B: A {}"],
        "missing implementation of abstract member 'f'"
    )
}

@Test func abstractImplementedByIntermediateClass() {
    expectAccessNoError(
        [
            "abstract class A {\n    abstract func f()\n}\nclass B: A {\n    override func f() {}\n}\nclass C: B {}",
        ]
    )
}

@Test func abstractValidChain() {
    expectAccessNoError(
        ["abstract class A {\n    abstract func f()\n}\nclass B: A {\n    override func f() {}\n}"]
    )
}

@Test func privateVarReadCrossType() {
    expectAccessError(
        ["struct S {\n    private var x\n}\nstruct T {\n    func g(s: S) {\n        let y = s.x\n    }\n}"],
        "'x' is private"
    )
}
