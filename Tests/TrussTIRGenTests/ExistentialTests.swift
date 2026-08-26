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
        try #require(tir.contains("@$t4main_1S_4init_4Void"))
        try #require(tir.contains("call void @$t4main_1S_4init_4Void"))
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
        try #require(tir.contains("call void @$t4main_1C_4init_4Void"))
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
        try #require(tir.contains("call void @$t4main_1S_4init_4Void"))
    }
}
