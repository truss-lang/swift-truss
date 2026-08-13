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
                .B(let s) => { let x = s }
                _ => { return }
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
        try #require(tir.contains("function $t4main_1C_6deinit_4Void"))
    }

    @Test func deinitBindsSelfAndAccessesMembers() throws {
        let tir = dumpTIR(
            """
            precedencegroup Assignment { assignment: true }
            infix operator =: Assignment
            struct S {
                init() {}
            }
            class C {
                var x: S = S()
                init() {}
                deinit {
                    x = S()
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1C_6deinit_4Void"))
        try #require(tir.contains("RefElementAddr"))
        try #require(tir.contains("Store "))
    }

    @Test func deinitPerClassMangledSeparately() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            class C {
                init() {}
                deinit {
                }
            }
            class D {
                init() {}
                deinit {
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1C_6deinit_4Void"))
        try #require(tir.contains("function $t4main_1D_6deinit_4Void"))
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
        try #require(tir.contains("function $t4main_1T_9subscript_1i9$t4main1S_9$t4main1S"))
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
        try #require(tir.contains("function $t4main_1S_4init_4Void"))
        try #require(tir.contains("FunctionRef $t4main_1S_4init_4Void"))
        try #require(tir.contains("Apply "))
    }
}

@Test func initCallPassesSelfArgument() throws {
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
    try #require(tir.contains("4init_4Void : $("))
    let fBlock = tir.components(separatedBy: "function ").last
        ?? ""
    try #require(fBlock.range(of: #"Apply %\d+\(%\d+\)"#, options: .regularExpression) != nil)
}

@Test func implicitReturnInFunctionBody() throws {
    let tir = dumpTIR(
        """
        struct S {
            init() {}
        }
        func f() -> S {
            S()
        }
        """
    )
    let fBlock = tir.components(separatedBy: "function ").last
        ?? ""
    try #require(fBlock.range(of: #"Return %\d+"#, options: .regularExpression) != nil)
}

@Test func implicitReturnInGetter() throws {
    let tir = dumpTIR(
        """
        struct S {
            init() {}
        }
        struct T {
            var x: S {
                get { S() }
            }
            init() {}
        }
        """
    )
    let getterBlock = tir.components(separatedBy: "function ")
        .first(where: { $0.contains("1xGetter_") }) ?? ""
    try #require(getterBlock.range(of: #"Return %\d+"#, options: .regularExpression) != nil)
}

@Test func implicitReturnInClosure() throws {
    let tir = dumpTIR(
        """
        struct S {}
        func f() {
            let g = { (s: S) -> S in
                s
            }
        }
        """
    )
    let closureBlock = tir.components(separatedBy: "function ")
        .first(where: { $0.hasPrefix("$t4main_1f_4Void_closure_0") }) ?? ""
    try #require(closureBlock.range(of: #"Return %\d+"#, options: .regularExpression) != nil)
}

@Test func builtinTypeLowersToPrimitive() throws {
    let tir = dumpTIR(
        """
        func f() {
            var v: Builtin.Int64 = 1
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("i64"))
}

@Test func builtinBoolLowersToPrimitive() throws {
    let tir = dumpTIR(
        """
        func f() {
            var b: Builtin.Bool = true
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("b1"))
}
