import Testing

@Suite struct MissingLoweringTests {
    @Test func ifLetBindingBindsVariable() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S?) {
                if let y = x {
                    let z = y
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Load "))
    }

    @Test func matchCaseBindingBindsVariable() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A(S)
            }
            struct S {
                init() {}
            }
            func f(e: E) {
                match e {
                .A(let x) => {
                    let z = x
                }
                }
            }
            """
        )
        try #require(tir.contains("UncheckedEnumData"))
        try #require(tir.contains("Load "))
    }

    @Test func guardLetBindingBindsVariable() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S?) {
                guard let y = x else { return }
                let z = y
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Load "))
        try #require(tir.contains("Return"))
    }

    @Test func addressOfLowersToAddressToPointer() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S) -> S {
                let p = &x
                return *p
            }
            """
        )
        try #require(tir.contains("AddressToPointer "))
        try #require(tir.contains("Load "))
    }

    @Test func nullPointerLiteralLowersToNullLiteral() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let p: S* = nullptr
            }
            """
        )
        try #require(tir.contains("NullLiteral"))
    }

    @Test func labeledBreakTargetsOuterLoop() throws {
        let plain = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                while true {
                    while true {
                        break
                    }
                }
            }
            """
        )
        let labeled = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                outer: while true {
                    while true {
                        break outer
                    }
                }
            }
            """
        )
        try #require(labeled != plain)
        try #require(labeled.contains("Branch "))
    }

    @Test func closureBindingUsesClosureScope() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S?) {
                let g = {
                    if let y = x {
                        let z = y
                    }
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Load "))
    }
}

@Test func caseMatchLowersToBoolPhi() throws {
    let tir = dumpTIR(
        """
        enum E {
            case C
        }
        func f(e: E) {
            let b = case .C = e
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("BoolLiteral true"))
    try #require(tir.contains("BoolLiteral false"))
    try #require(tir.contains("Phi"))
}

@Test func optionalBindingExpressionLowersToBoolPhi() throws {
    let tir = dumpTIR(
        """
        struct S {
            init() {}
        }
        func f(a: S?) {
            let b = (let x = a)
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("SwitchEnum"))
    try #require(tir.contains("BoolLiteral true"))
    try #require(tir.contains("BoolLiteral false"))
    try #require(tir.contains("Phi"))
}

@Test func logicalAndShortCircuits() throws {
    let tir = dumpTIR(
        """
        precedencegroup LogicalAnd { associativity: left }
        infix operator &&: LogicalAnd
        func &&(lhs: Builtin.Bool, rhs: Builtin.Bool) -> Builtin.Bool {
            lhs
        }
        func f(a: Builtin.Bool, b: Builtin.Bool) -> Builtin.Bool {
            return a && b
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("CondBranch"))
    try #require(tir.contains("BoolLiteral false"))
    try #require(tir.contains("Phi"))
    try #require(!tir.contains("Apply "))
}
