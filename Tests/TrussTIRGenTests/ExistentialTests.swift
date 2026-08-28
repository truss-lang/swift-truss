import Testing
import TrussTIRGen

@Suite struct ExistentialTests {
    @Test func protocolTypeLowersToExistential() throws {
        let tir = dumpTIR(
            """
            protocol Shape {
                func describe()
            }
            struct Square: Shape {
                init() {}
                func describe() { return }
            }
            func main() {
                let s: any Shape = Square()
                s.describe()
            }
            """
        )
        try #require(tir.contains("%$tany"))
        try #require(tir.contains("buildexistential"))
        try #require(tir.contains("openexistential"))
        try #require(tir.contains("witnessmethod"))
    }

    @Test func existentialBoxesConcreteValue() throws {
        let tir = dumpTIR(
            """
            protocol Shape {
                func describe()
            }
            struct Square: Shape {
                init() {}
                func describe() { return }
            }
            func main() {
                let s: any Shape = Square()
            }
            """
        )
        try #require(tir.contains("buildexistential"))
        try #require(tir.contains("store %$tany"))
    }

    @Test func multiProtocolDispatch() throws {
        let tir = dumpTIR(
            """
            protocol Drawable {
                func draw()
            }
            protocol Shape {
                func describe()
            }
            struct Square: Shape, Drawable {
                init() {}
                func describe() { return }
                func draw() { return }
            }
            func main() {
                let s: any Shape & Drawable = Square()
                s.describe()
                s.draw()
            }
            """
        )
        try #require(tir.contains("witnessmethod"))
    }

    @Test func structInitConstruction() throws {
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
        try #require(tir.contains("@$t4main_1S_4init_1S"))
        try #require(tir.contains("call void @$t4main_1S_4init_1S"))
        try #require(tir.contains("load %$t4main_1S"))
    }

    @Test func classInitConstruction() throws {
        let tir = dumpTIR(
            """
            class C {
                init() {}
            }
            func f() -> C {
                return C()
            }
            """
        )
        try #require(tir.contains("allocheap %$t4main_1C"))
        try #require(tir.contains("call void @$t4main_1C_4init_1C"))
    }

    @Test func associatedTypeWitnessDispatch() throws {
        let tir = dumpTIR(
            """
            protocol Container {
                associatedtype Element
                func count()
            }
            struct Box: Container {
                init() {}
                func count() { return }
            }
            func main() {
                let c: any Container = Box()
                c.count()
            }
            """
        )
        try #require(tir.contains("buildexistential"))
        try #require(tir.contains("witnessmethod"))
    }

    @Test func existentialAssignmentCopies() throws {
        let tir = dumpTIR(
            """
            protocol Shape {
                func describe()
            }
            struct Square: Shape {
                init() {}
                func describe() { return }
            }
            func main() {
                var s: any Shape = Square()
                var t: any Shape = s
            }
            """
        )
        try #require(tir.contains("existentialcopy"))
    }

    @Test func structInitWritesFieldsThroughPointer() throws {
        let tir = dumpTIR(
            """
            struct S {
                var a: Builtin.Int32
                init() {
                    a = 5
                }
            }
            func f() -> S {
                return S()
            }
            """,
            installBuiltin: true
        )
        try #require(tir.contains("structelementaddr"))
        try #require(tir.contains("store i32 5"))
        try #require(tir.contains("call void @$t4main_1S_4init_1S"))
    }
}

@Test func nestedCompositionDispatch() throws {
    let tir = dumpTIR(
        """
        protocol A {
            func a()
        }
        protocol B {
            func b()
        }
        protocol C {
            func c()
        }
        struct S: A, B, C {
            init() {}
            func a() { return }
            func b() { return }
            func c() { return }
        }
        func main() {
            let s: any (A & B) & C = S()
            s.a()
            s.b()
            s.c()
        }
        """
    )
    try #require(tir.contains("buildexistential"))
    let witnessCount = tir.components(separatedBy: "witnessmethod").count - 1
    #expect(witnessCount == 3, "expected 3 witnessmethod calls, got \(witnessCount)")
}

@Test func duplicateProtocolInCompositionFlattened() throws {
    let tir = dumpTIR(
        """
        protocol P {
            func a()
        }
        struct S: P {
            init() {}
            func a() { return }
        }
        func main() {
            let s: any P & P = S()
            s.a()
        }
        """
    )
    try #require(tir.contains("buildexistential"))
    try #require(tir.contains("witnessmethod"))
    try #require(tir.contains("%$tany0"))
    try #require(!tir.contains("%$tany00"))
}

@Test func copyPreservesWitnessDispatch() throws {
    let tir = dumpTIR(
        """
        protocol P {
            func a()
        }
        struct S: P {
            init() {}
            func a() { return }
        }
        func main() {
            var s: any P = S()
            var t: any P = s
            t.a()
        }
        """
    )
    try #require(tir.contains("existentialcopy"))
    try #require(tir.contains("witnessmethod"))
}

@Test func opaqueParamDispatch() throws {
    let tir = dumpTIR(
        """
        protocol Shape {
            func describe()
        }
        struct Square: Shape {
            init() {}
            func describe() { return }
        }
        func f(_ s: any Shape) {
            s.describe()
        }
        func main() {
            let a: any Shape = Square()
            f(a)
        }
        """
    )
    try #require(tir.contains("opaquewitnessmethod"))
    try #require(tir.contains("%$tany0#0.0"))
}

@Test func opaqueCompositionParamDispatch() throws {
    let tir = dumpTIR(
        """
        protocol Drawable {
            func draw()
        }
        protocol Shape {
            func describe()
        }
        struct Square: Shape, Drawable {
            init() {}
            func describe() { return }
            func draw() { return }
        }
        func f(_ s: any Shape & Drawable) {
            s.describe()
            s.draw()
        }
        func main() {
            let a: any Shape & Drawable = Square()
            f(a)
        }
        """
    )
    let opaqueCount = tir.components(separatedBy: "opaquewitnessmethod").count - 1
    #expect(opaqueCount == 2, "expected 2 opaque dispatches, got \(opaqueCount)")
    try #require(tir.contains("%$tany01#0.0"))
    try #require(tir.contains("%$tany01#1.0"))
}

@Test func opaqueReturnedExistentialDispatch() throws {
    let tir = dumpTIR(
        """
        protocol Shape {
            func describe()
        }
        struct Square: Shape {
            init() {}
            func describe() { return }
        }
        func make() -> any Shape {
            return Square()
        }
        func f() {
            let s: any Shape = make()
            s.describe()
        }
        func main() {}
        """
    )
    try #require(tir.contains("opaquewitnessmethod"))
}

@Test func opaqueParamDispatchLandsReturnValueIntoTypedLet() throws {
    let tir = dumpTIR(
        """
        protocol Shape {
            func area() -> Builtin.Int32
        }
        struct Square: Shape {
            init() {}
            func area() -> Builtin.Int32 { return 4 }
        }
        func f(_ s: any Shape) {
            let n: Builtin.Int32 = s.area()
        }
        func main() {
            let a: any Shape = Square()
            f(a)
        }
        """,
        installBuiltin: true
    )
    let fBlock = tir.components(separatedBy: "$t4main_1f_")
        .last { $0.contains("opaquewitnessmethod") } ?? ""
    try #require(tir.contains("opaquewitnessmethod %$tany0#0.0"))
    try #require(fBlock.range(of: #"store i32 %\d+, ptr %n"#, options: .regularExpression) != nil)
}
