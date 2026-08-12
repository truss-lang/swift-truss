import Testing

@Suite struct ValueLoweringTests {
    @Test func binaryOperatorAppliesFunction() throws {
        let tir = dumpTIR(
            """
            precedencegroup P {}
            infix operator +: P
            struct S {
                init() {}
            }
            func +(lhs: S, rhs: S) -> S { lhs }
            func f(a: S, b: S) -> S {
                return a + b
            }
            """
        )
        try #require(tir.contains("function $t4main1+3lhs1S3rhs1SF"))
        try #require(tir.contains("FunctionRef $t4main1+3lhs1S3rhs1SF"))
        try #require(tir.contains("Apply "))
    }

    @Test func prefixOperatorAppliesFunction() throws {
        let tir = dumpTIR(
            """
            precedencegroup P {}
            prefix operator -
            struct S {
                init() {}
            }
            func -(prefixValue: S) -> S { prefixValue }
            func f(s: S) -> S {
                return -s
            }
            """
        )
        try #require(tir.contains("function $t4main1-11prefixValue1SF"))
        try #require(tir.contains("Apply "))
    }

    @Test func tupleValueLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() -> S {
                let t = (S(), S())
                return S()
            }
            """
        )
        try #require(tir.contains("TupleValue"))
    }

    @Test func arrayAndDictionaryLiterals() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let a = [S(), S()]
                let d = ["k": S()]
            }
            """
        )
        try #require(tir.contains("ArrayValue"))
        try #require(tir.contains("DictionaryValue"))
        try #require(tir.contains("StringLiteral \"k\""))
    }

    @Test func stringInterpolationLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(s: S) {
                let t = "value \\(s) tail"
            }
            """
        )
        try #require(tir.contains("StringLiteral \"value  tail\""))
        try #require(tir.contains("Load "))
    }

    @Test func closureShorthandArgument() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let c = { (a: S, b: S) -> S in
                    return $0
                }
            }
            """
        )
        try #require(tir.contains("function closure-0"))
        try #require(tir.contains("Closure closure-0"))
        try #require(tir.contains("Return "))
    }

    @Test func globalInitializerLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            var g: S = S()
            func f() -> S {
                return g
            }
            """
        )
        try #require(tir.contains("global $t4main1g"))
        try #require(tir.contains("GlobalAddr $t4main1g"))
        try #require(tir.contains("FunctionRef $t4main1S4initF"))
        try #require(tir.contains("Store "))
    }

    @Test func staticMethodCallLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
                static func make() -> S {
                    return S()
                }
            }
            func f() -> S {
                return S.make()
            }
            """
        )
        try #require(tir.contains("function $t4main1S4makeF"))
        try #require(tir.contains("FunctionRef $t4main1S4makeF"))
        try #require(tir.contains("Apply "))
    }
}
