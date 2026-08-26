import Testing
import TrussDriver

func codegenIR(_ source: String) -> String {
    let result = Driver(config: DriverConfig(dumpLLVMIR: true)).runString(source)
    return result.stdout
}

@Suite struct TrussCodeGenTests {
    @Test func structFunctionReturnsStruct() throws {
        let ir = codegenIR(
            """
            struct S {}
            func f(a: S) -> S {
                return a
            }
            """
        )
        try #require(ir.contains("%\"$t4main_1S\" = type {}"))
        try #require(ir.contains("define %\"$t4main_1S\""))
        try #require(ir.contains("ret %\"$t4main_1S\""))
        try #require(ir.contains("alloca %\"$t4main_1S\""))
    }

    @Test func enumMatchLowersToSwitch() throws {
        let ir = codegenIR(
            """
            enum E {
                case A
                case B
            }
            func f(e: E) -> E {
                match e {
                .A => { e }
                .B => { e }
                }
            }
            """
        )
        try #require(ir.contains("switch i8"))
        try #require(ir.contains("i8 0, label"))
        try #require(ir.contains("i8 1, label"))
        try #require(ir.contains("unreachable"))
    }

    @Test func enumMatchMergeLowersToPhi() throws {
        let ir = codegenIR(
            """
            enum E {
                case A
                case B
            }
            func f(e: E) -> E {
                match e {
                .A => { e }
                .B => { e }
                }
            }
            """
        )
        try #require(ir.contains("phi i8"))
    }

    @Test func functionCallLowersToCall() throws {
        let ir = codegenIR(
            """
            struct S {}
            func g(a: S) -> S {
                return a
            }
            func f(a: S) -> S {
                return g(a)
            }
            """
        )
        try #require(ir.contains("call %\"$t4main_1S\""))
        try #require(ir.contains("ret %\"$t4main_1S\" %2"))
    }

    @Test func voidFunctionReturnsVoid() throws {
        let ir = codegenIR(
            """
            func f() {
            }
            """
        )
        try #require(ir.contains("define void"))
        try #require(ir.contains("ret void"))
    }

    @Test func setsTargetTriple() throws {
        let ir = codegenIR(
            """
            struct S {}
            func f(a: S) -> S {
                return a
            }
            """
        )
        try #require(ir.contains("target triple ="))
        try #require(ir.contains("target datalayout ="))
    }
}
