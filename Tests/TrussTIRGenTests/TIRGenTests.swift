import Testing

@Suite struct TIRGenTests {
    @Test func basicFunction() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(a: S) -> S {
                return a
            }
            """
        )
        try #require(tir.contains("function $t4main1f1a1SF"))
        try #require(tir.contains("entry:"))
        try #require(tir.contains("AllocStack"))
        try #require(tir.contains("Load"))
        try #require(tir.contains("Return"))
    }

    @Test func matchStatement() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A
                case B
            }
            func f(e: E) {
                match e {
                .A -> { return }
                .B -> { return }
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Unreachable"))
    }

    @Test func closureCapture() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f() {
                var x: S = S()
                let c = { () -> Void in
                    let y = x
                    return
                }
                c()
            }
            """
        )
        try #require(tir.contains("closure-0"))
        try #require(tir.contains("AllocCell"))
        try #require(tir.contains("Closure"))
    }

    @Test func errorHandling() throws {
        let tir = dumpTIR(
            """
            struct E {}
            func g() throws(E) {}
            func f() {
                do {
                    try g()
                } catch {
                    return
                }
            }
            """
        )
        try #require(tir.contains("TryApply"))
        try #require(tir.contains("error:"))
    }
}

@Suite struct GlobalVarTests {
    @Test func globalVariableLowered() throws {
        let tir = dumpTIR(
            """
            struct S {}
            var g: S
            func f() -> S {
                return g
            }
            """
        )
        try #require(tir.contains("global "))
        try #require(tir.contains("GlobalAddr"))
        try #require(tir.contains("Load"))
    }

    @Test func propertyInitializerInInit() throws {
        let tir = dumpTIR(
            """
            struct T {}
            struct S {
                var x: T = T()
                init() {}
            }
            """
        )
        try #require(tir.contains("StructElementAddr"))
        try #require(tir.contains("Store"))
    }

    @Test func accessorGetterCalled() throws {
        let tir = dumpTIR(
            """
            struct T {}
            struct S {
                var x: T {
                    get { return y }
                }
                var y: T = T()
            }
            func f(s: S) -> T {
                return s.x
            }
            """
        )
        try #require(tir.contains("xGetter"))
        try #require(tir.contains("Apply"))
    }
}
