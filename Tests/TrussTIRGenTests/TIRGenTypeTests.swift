import Testing

@Suite struct TypeLoweringTests {
    @Test func enumMatchWithPayload() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            enum E {
                case A
                case B(S)
            }
            func f(e: E) {
                match e {
                .B(let s) -> { let x = s }
                _ -> { return }
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("UncheckedEnumData"))
        try #require(tir.contains("TupleElementAddr"))
    }

    @Test func enumCaseValue() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            enum E {
                case A
            }
            func f() -> E {
                return E.A
            }
            """
        )
        try #require(tir.contains("EnumValue"))
        try #require(tir.contains("case A"))
    }

    @Test func forceUnwrapUncheckedEnumData() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(o: S?) -> S {
                return o!
            }
            """
        )
        try #require(tir.contains("UncheckedEnumData"))
        try #require(tir.contains("case some"))
    }

    @Test func ifLetSwitchOnOptional() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(o: S?) {
                if let x = o {
                    let y = x
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("case some"))
        try #require(tir.contains("case none"))
    }

    @Test func upcastToProtocol() throws {
        let tir = dumpTIR(
            """
            protocol P {}
            struct S: P {
                init() {}
            }
            func f(s: S) -> P {
                return s as P
            }
            """
        )
        try #require(tir.contains("Upcast"))
    }

    @Test func classStoredPropertyUsesRefElementAddr() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            class C {
                var x: S = S()
                init() {}
            }
            func f(c: C) -> S {
                return c.x
            }
            """
        )
        try #require(tir.contains("RefElementAddr"))
        try #require(tir.contains("#0 x"))
        try #require(tir.contains("Store "))
    }

    @Test func deinitFunctionLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            class C {
                var x: S = S()
                init() {}
                deinit {
                }
            }
            """
        )
        try #require(tir.contains("function deinit"))
    }

    @Test func subscriptDeclLoweredToFunction() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            struct T {
                init() {}
                subscript(i: S) -> S {
                    return i
                }
            }
            """
        )
        try #require(tir.contains("function $t4main1T9subscript1i1SF"))
    }

    @Test func initCallLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() -> S {
                return S()
            }
            """
        )
        try #require(tir.contains("function $t4main1S4initF"))
        try #require(tir.contains("FunctionRef $t4main1S4initF"))
        try #require(tir.contains("Apply "))
    }
}
