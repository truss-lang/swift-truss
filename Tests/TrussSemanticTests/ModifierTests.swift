import Testing
import TrussCore
import TrussSemantics

func expectError(_ source: String, _ message: String) {
    let (context, _) = runChecks([source])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(message))
}

func expectNoError(_ source: String) {
    let (context, _) = runChecks([source])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func openOnStruct() {
    expectError("open struct S {}", "'open' modifier cannot be applied to 'struct'")
}

@Test func openOnTopLevelFunction() {
    expectError("open func f() {}", "'open' modifier can only be applied to a class or class member")
}

@Test func openOnStructMember() {
    expectError(
        "struct S {\n    open func f() {}\n}",
        "'open' modifier can only be applied to a class or class member"
    )
}

@Test func protectedOnTopLevel() {
    expectError("protected func f() {}", "'protected' modifier can only be applied to a class member")
}

@Test func abstractOnStruct() {
    expectError("abstract struct S {}", "'abstract' modifier cannot be applied to 'struct'")
}

@Test func abstractOnTopLevelFunction() {
    expectError(
        "abstract func f()", "'abstract' modifier can only be applied to a class or protocol member"
    )
}

@Test func abstractMethodWithBody() {
    expectError(
        "abstract class C {\n    abstract func f() {}\n}",
        "'abstract' method cannot have a body"
    )
}

@Test func abstractMemberInNonAbstractClass() {
    expectError(
        "class C {\n    abstract func f()\n}",
        "'abstract' member in non-abstract class"
    )
}

@Test func finalOnStruct() {
    expectError("final struct S {}", "'final' modifier cannot be applied to 'struct'")
}

@Test func finalCombinedWithOpen() {
    expectError(
        "open final class C {}", "'final' modifier cannot be combined with 'open'"
    )
}

@Test func finalCombinedWithAbstract() {
    expectError(
        "abstract final class C {}", "'final' modifier cannot be combined with 'abstract'"
    )
}

@Test func mutatingOnClassMethod() {
    expectError(
        "class C {\n    mutating func f() {}\n}",
        "'mutating' modifier can only be applied to a struct or enum method"
    )
}

@Test func mutatingCombinedWithStatic() {
    expectError(
        "struct S {\n    static mutating func f() {}\n}",
        "'mutating' modifier cannot be combined with 'static'"
    )
}

@Test func overrideOnTopLevel() {
    expectError("override func f() {}", "'override' modifier can only be applied to a class member")
}

@Test func staticOnTopLevel() {
    expectError("static func f() {}", "'static' modifier can only be applied to type members")
}

@Test func convenienceOnStructInit() {
    expectError(
        "struct S {\n    convenience init() {}\n}",
        "'convenience' initializer must be in a class"
    )
}

@Test func lazyOnLet() {
    expectError(
        "struct S {\n    lazy let x = 1\n}", "'lazy' property must be a var"
    )
}

@Test func lazyWithoutInitializer() {
    expectError(
        "struct S {\n    lazy var x\n}", "'lazy' property must have an initializer"
    )
}

@Test func weakOnLet() {
    expectError(
        "class C {}\nstruct S {\n    weak let c: C?\n}", "'weak' property must be a var"
    )
}

@Test func weakOnNonClassType() {
    expectError(
        "struct V {}\nstruct S {\n    weak var v: V\n}",
        "'weak' property must be of class type"
    )
}

@Test func isolatedOnNonActor() {
    expectError(
        "struct S {\n    isolated func f() {}\n}",
        "'isolated' modifier can only be applied to an actor member"
    )
}

@Test func indirectOnFunction() {
    expectError("indirect func f() {}", "'indirect' modifier cannot be applied to a function")
}

@Test func accessOnExtension() {
    expectError(
        "struct S {}\npublic extension S {}",
        "'public' modifier cannot be applied to an extension"
    )
}

@Test func modifierOnDeinit() {
    expectError(
        "class C {\n    public deinit {}\n}",
        "'public' modifier cannot be applied to a deinitializer"
    )
}

@Test func setterOnFunction() {
    expectError(
        "struct S {\n    private(set) func f() {}\n}",
        "'private(set)' modifier cannot be applied to a function"
    )
}

@Test func abstractClassValid() {
    expectNoError(
        "abstract class C {\n    abstract func f()\n}\nclass D: C {\n    override func f() {}\n}"
    )
}

@Test func abstractProtocolMemberValid() {
    expectNoError("protocol P {\n    abstract func f()\n}")
}

@Test func openClassValid() {
    expectNoError("open class C {\n    open func f() {}\n}")
}

@Test func mutatingStructMethodValid() {
    expectNoError("struct S {\n    mutating func f() {}\n}")
}

@Test func mutatingEnumMethodValid() {
    expectNoError("enum E {\n    case A\n    mutating func f() {}\n}")
}

@Test func finalClassValid() {
    expectNoError("final class C {}")
}

@Test func convenienceInitValid() {
    expectNoError("class C {\n    convenience init() {}\n}")
}

@Test func lazyVarValid() {
    expectNoError("struct S {\n    lazy var x = 1\n}")
}

@Test func weakClassVarValid() {
    expectNoError("class C {}\nstruct S {\n    weak var c: C?\n}")
}

@Test func isolatedActorMethodValid() {
    expectNoError("actor A {\n    isolated func f() {}\n}")
}

@Test func indirectEnumCaseValid() {
    expectNoError("enum E {\n    indirect case A\n}")
}

@Test func indirectEnumValid() {
    expectNoError("indirect enum E {\n    case A\n}")
}

@Test func staticTypeMemberValid() {
    expectNoError("struct S {\n    static func f() {}\n}")
}

@Test func finalExtensionValid() {
    expectNoError("struct S {}\nfinal extension S {}")
}

@Test func accessOnTypeAliasValid() {
    expectNoError("struct S {}\nprivate typealias T = S")
}

@Test func privateTopLevelValid() {
    expectNoError("private struct S {}")
}
