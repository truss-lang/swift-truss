import Testing
import TrussCore

@Test func printSimpleFunction() {
    #expect(
        printProgram(
            """
            func f(x: Int) -> Int {
                return x + 1
            }
            """
        )
            == """
            func f(x: Int) -> Int {
                return x + 1
            }
            """
    )
}

@Test func printIfElse() {
    #expect(
        printProgram(
            """
            func f(c: Bool) {
                if c {
                    g()
                } else {
                    h()
                }
            }
            """
        )
            == """
            func f(c: Bool) {
                if c {
                    g()
                } else {
                    h()
                }
            }
            """
    )
}

@Test func printForWithWhereClause() {
    #expect(
        printProgram(
            """
            func f(xs: [Int]) {
                for i in xs where i > 0 {
                    g(i)
                }
            }
            """
        )
            == """
            func f(xs: [Int]) {
                for i in xs where i > 0 {
                    g(i)
                }
            }
            """
    )
}

@Test func printForCaseWithWhereClause() {
    #expect(
        printProgram(
            """
            enum E {
                case foo(Int)
            }

            func f(xs: [E]) {
                for case .foo(let x) in xs where x > 0 {
                    g(x)
                }
            }
            """
        )
            == """
            enum E {
                case foo(Int)
            }

            func f(xs: [E]) {
                for case .foo(let x) in xs where x > 0 {
                    g(x)
                }
            }
            """
    )
}

@Test func printNestedStruct() {
    #expect(
        printProgram(
            """
            struct S: P2 {
                public func m() {
                    if x {
                        g()
                    }
                }
            }
            """
        )
            == """
            struct S: P2 {
                public func m() {
                    if x {
                        g()
                    }
                }
            }
            """
    )
}

@Test func printAccessors() {
    #expect(
        printProgram(
            """
            var a = 1 {
                get {
                    1
                }
                set(v) {
                }
            }
            """
        )
            == """
            var a = 1 {
                get {
                    1
                }
                set(v) {}
            }
            """
    )
}

@Test func printExpressionBody() {
    #expect(printProgram("func f() = 1") == "func f() = 1")
}

@Test func printVarargParameter() {
    #expect(printProgram("func f(xs: Int...) {}") == "func f(xs: Int...) {}")
}

@Test func printUnderscoreParameter() {
    #expect(printProgram("func f(_ x: Int) {}") == "func f(_ x: Int) {}")
}

@Test func printLabeledParameter() {
    #expect(printProgram("func f(label x: Int) {}") == "func f(label x: Int) {}")
}

@Test func printEmptyDecls() {
    #expect(printProgram("func f() {}") == "func f() {}")
    #expect(printProgram("struct S {}") == "struct S {}")
    #expect(printProgram("protocol P {}") == "protocol P {}")
    #expect(printProgram("module M {}") == "module M {}")
}

@Test func printClosureExpression() {
    #expect(
        printProgram(
            """
            func f() {
                let fn = { [weak self] (x: Int) -> Int in x }
            }
            """
        )
            == """
            func f() {
                let fn = { [weak self] (x: Int) -> Int in x }
            }
            """
    )
}

@Test func roundTripExpressions() {
    for source in [
        "let x = a + b * c",
        "let x = a + -b",
        "let x = - -a",
        "let x = a!",
        "let x = a!!",
        "let x = (a + b) * c",
        "let x = a * (b + c)",
        "let x = ((a))",
        "let x = a < b > c",
        "let s = \"a\\(x + 1)b\"",
        "let x = [1, 2, 3]",
        "let x = [a: 1, b: 2]",
        "let x = (a, b: c)",
        "let x = a[i]",
        "let x = try? f()",
        "let x = try! f()",
        "let x = await f()",
        "let x = a as? T",
        "let x = a as! T",
        "let x = a is T",
        "let x = some P & Q",
        "let x = f(a, b: c)",
        "let x = foo() { (y: Int) in y }",
        "let x = $0 + 1",
        "let x = 1...5",
        "let x = \"a\\nb\"",
        "let x = M.f3()",
        "let x = .None",
        "let x = a?.b",
        "let x = Int(42)",
        "let x = #\"hello\"#",
        "let x = #\"a\\nb\"#",
        "let x = #\"a\\#(x)b\"#",
        "let x = #\"a\"b\"#",
        "let x = \\Person.name",
        "let x = \\.self",
        "let x = \\A.b!.c",
        "let x = \\Person.age?.city",
        "let x = \\A?.b",
    ] {
        assertRoundTrip(source)
    }
}

@Test func roundTripStatements() {
    for source in [
        "func f() {}",
        "func f(x: Int) -> Int { return x + 1 }",
        "func f() = 1",
        "func f(xs: Int...) {}",
        "func f(_ x: Int) {}",
        "func f(label x: Int) {}",
        "func f() throws -> Int { 1 }",
        "func f() throws(E, F) -> Int { 1 }",
        "func f() {\n    if c {\n        g()\n    } else if d {\n        h()\n    } else {\n        i()\n    }\n}",
        "func f() {\n    while c {\n        break\n    }\n}",
        "func f() {\n    repeat {\n        continue\n    } while c\n}",
        "func f() {\n    guard let x = y else {\n        return\n    }\n}",
        "func f() {\n    for x in xs {\n        g(x)\n    }\n}",
        "func f() {\n    for await x in xs {\n        g(x)\n    }\n}",
        "func f() {\n    defer {\n        g()\n    }\n}",
        "func f() {\n    throw e\n}",
        "func f() {\n    var a = 1 {\n        get {\n            1\n        }\n        set(v) {\n        }\n    }\n}",
        "func f() {\n    asm { \"nop\" }\n}",
        "func f() {\n    asm { \"x\" : dst = out(reg) result : result preserves_flags }\n}",
        "func f() {\n    goto l\n}",
        "func f() {\n    let x = match v {\n        a => {\n            g()\n        }\n        b, c => {\n            h()\n        }\n    }\n}",
        "func f() {\n    let x = do {\n        g()\n    } catch E {\n        h()\n    } catch {\n        i()\n    } finally {\n        j()\n    }\n}",
        "func f() {\n    let x: Int = 1\n    let y = x\n    z = y\n}",
    ] {
        assertRoundTrip(source)
    }
}

@Test func roundTripDecls() {
    for source in [
        "module M {\n    func f() {\n    }\n}",
        "struct S: P2 {\n    public func m() {\n    }\n}",
        "enum E {\n    case a(x: Int) = 1\n}",
        "protocol P: P2 {\n    associatedtype T: C\n}",
        "extension Array<T> {\n    func f() {\n    }\n}",
        "typealias SS = (S) -> S",
        "import Foo.Bar as B",
        "import Foo.*",
        "import Foo.{a, b}",
        "infix operator +",
        "infix operator +: P",
        "infix operator +: M.P",
        "precedencegroup P {\n    associativity: left\n}",
        "precedencegroup P {\n    higherThan: A\n    lowerThan: B\n    assignment: true\n}",
        "class C<T> where T: P {\n}",
        "actor A {\n}",
        "public func f() {\n}",
        "final class C {\n}",
    ] {
        assertRoundTrip(source)
    }
}

@Test func roundTripMacroExpansion() {
    assertRoundTrip(
        """
        #define A B + 2
        #define B C * 3
        #define C D - 4
        #define D E / 5
        #define E A | 1
        func tf() {
            A
        }
        """
    )
}

@Test func roundTripTypes() {
    for source in [
        "let x: Int? = 1",
        "let x: Int... = 1",
        "func f(x: some P) {}",
        "func f(x: any P) {}",
        "let f: (Int) -> Int = g",
        "let f: (Int) throws -> Int = g",
        "let f: (Int) async throws -> Int = g",
        "func f() async -> Int { 1 }",
        "func f() async throws -> Int { 1 }",
        "let f: (a: Int, b: String) -> Int = g",
        "let f: () -> Int = g",
        "let f: (Int, String) -> Void = g",
        "let x: [Int] = []",
        "let x: [String: Int] = [:]",
        "let x = [Int]()",
    ] {
        assertRoundTrip(source)
    }
}
