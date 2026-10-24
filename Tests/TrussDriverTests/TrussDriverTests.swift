import Foundation
import Testing
import TrussDriver

private func writeTemp(_ name: String, _ content: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-driver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

@Test
func driverCompilesSingleFile() throws {
    let file = try writeTemp("main.truss", "func f() { 1 }\n")
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stderr.isEmpty)
}

@Test
func driverMultiFileMergesCrossFileExtension() throws {
    let a = try writeTemp(
        "a.truss",
        "struct Coord {}\nstruct Point {\n    var x: Coord\n    var y: Coord\n}\n"
    )
    let b = try writeTemp(
        "b.truss",
        "precedencegroup Additive {}\ninfix operator +: Additive\n"
            + "func +(lhs: Coord, rhs: Coord) -> Coord { lhs }\n"
            + "extension Point {\n    func sum() -> Coord {\n        self.x + self.y\n    }\n}\n"
    )
    let config = DriverConfig(dumpSymbols: true)
    let result = Driver(config: config).run(files: [a, b])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("sum"))
}

@Test
func driverResolvesCrossFileFunctionCall() throws {
    let a = try writeTemp(
        "a.truss",
        "func makeB() -> B {\n    b()\n}\n"
    )
    let b = try writeTemp(
        "b.truss",
        "struct B {}\nfunc b() -> B {\n    b()\n}\n"
    )
    let result = Driver(config: DriverConfig(dumpTIR: true)).run(files: [a, b])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("$t4main_1b_10$t4main_1B"))
}

@Test
func driverResolvesCircularTypeReferencesAcrossFiles() throws {
    let a = try writeTemp(
        "a.truss",
        "struct A {\n    var b: B\n}\n"
    )
    let b = try writeTemp(
        "b.truss",
        "struct B {\n    var a: A\n}\n"
    )
    let result = Driver(config: DriverConfig(dumpTIR: true)).run(files: [a, b])
    #expect(!result.hasErrors)
}

@Test
func driverReportsCrossFilePrivateAccess() throws {
    let a = try writeTemp(
        "a.truss",
        "func f() {\n    helper()\n}\n"
    )
    let b = try writeTemp(
        "b.truss",
        "private func helper() {\n}\n"
    )
    let result = Driver(config: DriverConfig()).run(files: [a, b])
    #expect(result.hasErrors)
}

@Test
func driverResolvesCrossFileGlobalVariable() throws {
    let a = try writeTemp(
        "a.truss",
        "func getG() -> S {\n    g\n}\n"
    )
    let b = try writeTemp(
        "b.truss",
        "struct S {}\nvar g: S\n"
    )
    let result = Driver(config: DriverConfig(dumpTIR: true)).run(files: [a, b])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("@$t4main_1g"))
}

@Test
func driverResolvesCrossFileGlobalInitializerDependency() throws {
    let a = try writeTemp(
        "a.truss",
        "var x: S = g\n"
    )
    let b = try writeTemp(
        "b.truss",
        "struct S {}\nvar g: S\n"
    )
    let result = Driver(config: DriverConfig(dumpTIR: true)).run(files: [a, b])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("@$t4main_1x"))
}

@Test
func driverDefineActivatesConditional() throws {
    let file = try writeTemp("cond.truss", "#if FLAG\nfunc f() {}\n#endif\n")
    let on = Driver(config: DriverConfig(defines: ["FLAG": "1"], dumpAST: true))
        .run(files: [file])
    #expect(!on.hasErrors)
    #expect(on.stdout.contains("FunctionDecl"))
    let off = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!off.hasErrors)
    #expect(!off.stdout.contains("FunctionDecl"))
}

@Test
func driverDefineWithValue() throws {
    let file = try writeTemp("cond2.truss", "#if MODE == 2\nfunc f() {}\n#endif\n")
    let on = Driver(config: DriverConfig(defines: ["MODE": "2"], dumpAST: true))
        .run(files: [file])
    #expect(!on.hasErrors)
    #expect(on.stdout.contains("FunctionDecl"))
    let off = Driver(config: DriverConfig(defines: ["MODE": "1"], dumpAST: true))
        .run(files: [file])
    #expect(!off.hasErrors)
    #expect(!off.stdout.contains("FunctionDecl"))
}

@Test
func driverDumpFlags() throws {
    let file = try writeTemp("dump.truss", "func f() {}\n")
    let result = Driver(
        config: DriverConfig(dumpAST: true, dumpSymbols: true, dumpSource: true)
    ).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("Program"))
    #expect(result.stdout.contains("package"))
    #expect(result.stdout.contains("func f()"))
}

@Test
func driverTypeCheckerStructuralAnnotations() throws {
    let file = try writeTemp(
        "types.truss",
        """
        struct S {}
        typealias A = S
        let b: S?
        let f: (S) -> S
        let p: P & Q
        protocol P {}
        protocol Q {}
        """
    )
    let stdSource = "public enum Optional<T> { case None; case Some(T) }"
    let stdResult = Driver(config: DriverConfig(moduleName: "Truss")).runString(stdSource)
    #expect(!stdResult.hasErrors)
    let stdInterface = try #require(stdResult.packageInterface)
    let result = Driver(config: DriverConfig(dumpAST: true, importedInterfaces: [stdInterface]))
        .run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("ty:Optional(StructType(S)"))
    #expect(result.stdout.contains("ClosureType ty:(StructType(S)#1) -> StructType(S)#1"))
    #expect(result.stdout.contains("ty:Composition(ProtocolType(P)"))
}

@Test
func driverMissingFileReportsError() {
    let missing = "/nonexistent/truss-\(UUID().uuidString).truss"
    let result = Driver(config: DriverConfig()).run(files: [missing])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("could not read file"))
}

@Test
func driverTargetTriple() throws {
    let file = try writeTemp("os.truss", "#if os(Linux)\nfunc f() {}\n#endif\n")
    let linux = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!linux.hasErrors)
    #expect(linux.stdout.contains("FunctionDecl"))
    let macos = Driver(
        config: DriverConfig(target: "x86_64-apple-macosx", dumpAST: true)
    ).run(files: [file])
    #expect(!macos.hasErrors)
    #expect(!macos.stdout.contains("FunctionDecl"))
}

@Test
func driverIncludeResolvesRelativeToSourceFile() throws {
    let header = try writeTemp("defs.truss", "#define MAX 42\n")
    let dir = (header as NSString).deletingLastPathComponent
    let main = dir + "/main.truss"
    try "#include \"defs.truss\"\nfunc g() { MAX }\n".write(
        to: URL(fileURLWithPath: main), atomically: true, encoding: .utf8)
    let result = Driver(config: DriverConfig(dumpSource: true)).run(files: [main])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("42"))
}

@Test
func driverStopsAfterFrontendError() throws {
    let a = try writeTemp("bad.truss", "struct S {\n")
    let b = try writeTemp("ext.truss", "extension Missing {}\n")
    let result = Driver(config: DriverConfig()).run(files: [a, b])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("expected '}' after struct body"))
    #expect(!result.stderr.contains("has no matching declaration"))
}

@Test
func driverStopsAfterCollectorError() throws {
    let file = try writeTemp(
        "dup.truss", "struct S {}\nstruct S {}\nextension Missing {}\n"
    )
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("invalid redeclaration of type 'S'"))
    #expect(!result.stderr.contains("has no matching declaration"))
}

@Test
func driverSkipsDumpOnError() throws {
    let file = try writeTemp("bad2.truss", "struct S {\n")
    let result = Driver(
        config: DriverConfig(dumpAST: true, dumpSymbols: true, dumpSource: true)
    ).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stdout.isEmpty)
}

@Test
func driverDumpsOnErrorWhenEnabled() throws {
    let file = try writeTemp("bad3.truss", "struct S {\n")
    let on = Driver(config: DriverConfig(dumpAST: true, dumpOnError: true)).run(files: [file])
    #expect(on.hasErrors)
    #expect(on.stdout.contains("Program"))
    let off = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(off.hasErrors)
    #expect(off.stdout.isEmpty)
}

@Test
func driverRunStringParsesInMemorySource() throws {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString("func f() {}\n")
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("FunctionDecl"))
}

@Test
func driverFoldsExpressionsByPrecedence() throws {
    let file = try writeTemp(
        "fold.truss",
        "precedencegroup Additive {} precedencegroup Multiplicative { higherThan: Additive }\n"
            + "infix operator +: Additive infix operator *: Multiplicative\n"
            +
            "func +(lhs: Builtin.Int32, rhs: Builtin.Int32) -> Builtin.Int32 { Builtin.builtin_add_int32(lhs, rhs) }\n"
            +
            "func *(lhs: Builtin.Int32, rhs: Builtin.Int32) -> Builtin.Int32 { Builtin.builtin_mul_int32(lhs, rhs) }\n"
            + "func main() { 1 + 2 * 3 }\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("Binary"))
    #expect(!result.stdout.contains("SequentialExpression"))
}

@Test
func driverFoldsUnaryOperators() throws {
    let file = try writeTemp(
        "unary.truss",
        "precedencegroup Multiplicative {}\nprefix operator - infix operator -: Multiplicative\n"
            + "infix operator *: Multiplicative\n"
            + "struct S {}\n"
            + "func -(prefixValue: S) -> S { prefixValue }\n"
            + "func *(lhs: S, rhs: S) -> S { lhs }\n"
            + "let a: S\n"
            + "let b: S\n"
            + "func main() { -a * b }\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("Prefix"))
    #expect(result.stdout.contains("Binary"))
}

@Test
func driverSupportsGenericApplication() throws {
    let file = try writeTemp(
        "generic.truss",
        "struct Box {}\nstruct S {}\nfunc main() { Box<S> }\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
}

@Test
func driverReportsUnknownOperator() throws {
    let file = try writeTemp("unknown-op.truss", "func main() { 1 + 2 }\n")
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("unknown operator '+'"))
}

@Test
func driverOperatorFunctionResolution() throws {
    let file = try writeTemp(
        "op-func.truss",
        "precedencegroup Additive {}\ninfix operator +: Additive\n"
            + "struct S {}\n"
            + "func +(lhs: S, rhs: S) -> S { lhs }\n"
            + "func main() {\nvar s: S\nlet a: S = s + s\n}\n"
    )
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(!result.hasErrors)
}

@Test
func driverSupportsMemberOperatorCall() throws {
    let file = try writeTemp(
        "member-op.truss",
        "struct S { func +(rhs: S) -> S { self } }\n"
            + "func main() {\nvar s: S\nlet a: S = s.+(s)\n}\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("MemberAccess"))
}

@Test
func driverOperatorWithoutFunctionReportsError() throws {
    let file = try writeTemp(
        "op-noimpl.truss",
        "precedencegroup Additive {}\ninfix operator +: Additive\n"
            + "func main() { 1 + 2 }\n"
    )
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("operator '+' has no function declaration"))
}

@Test
func driverFunctionCallEndToEnd() throws {
    let file = try writeTemp(
        "generic-fn.truss",
        "struct S {}\n"
            + "func id(x: S) -> S { x }\n"
            + "func main() {\nvar s: S\nlet a = id(x: s)\n}\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("ty:StructType(S)"))
}

@Test
func driverMismatchedTypeReportsError() throws {
    let file = try writeTemp(
        "mismatch.truss",
        "struct S {}\nstruct T {}\n"
            + "func makeT() -> T { }\n"
            + "func main() {\nlet x: S = makeT()\n}\n"
    )
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("expected 'S', found 'T'"))
}

@Test
func driverAssignmentToPropertyEndToEnd() throws {
    let file = try writeTemp(
        "assign.truss",
        """
        precedencegroup Assignment { assignment: true }
        infix operator =: Assignment
        struct TT {}
        struct TS {
            var x: TT
            var y: TT
        }
        var gs: TS
        func f(t: TT) -> TT {
            gs.y = t
            return gs.x
        }
        """
    )
    let result = Driver(config: DriverConfig(dumpTIR: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("structelementaddr"))
    #expect(result.stdout.contains("store"))
}

@Test
func driverDumpLLVMIRShowsArithInstructions() throws {
    let sources = [
        (
            "add.truss",
            """
            #[cname("truss_add_i32")]
            func addI32(a: Builtin.Int32, b: Builtin.Int32) -> Builtin.Int32 {
                return Builtin.builtin_add_int32(a, b)
            }
            """,
            "add i32"
        ),
        (
            "div.truss",
            """
            #[cname("truss_div_u64")]
            func divU64(a: Builtin.UInt64, b: Builtin.UInt64) -> Builtin.UInt64 {
                return Builtin.builtin_div_uint64(a, b)
            }
            """,
            "udiv i64"
        ),
        (
            "neg.truss",
            """
            #[cname("truss_neg_f64")]
            func negF64(a: Builtin.Float64) -> Builtin.Float64 {
                return Builtin.builtin_neg_float64(a)
            }
            """,
            "fneg double"
        ),
    ]
    for (name, source, expected) in sources {
        let file = try writeTemp(name, source)
        let result = Driver(config: DriverConfig(dumpLLVMIR: true)).run(files: [file])
        #expect(!result.hasErrors)
        #expect(result.stdout.contains(expected))
    }
}

@Test
func driverDumpLLVMIRShowsCompareAndBitwiseInstructions() throws {
    let file = try writeTemp(
        "cmp.truss",
        """
        #[cname("truss_eq_i32")]
        func eqI32(a: Builtin.Int32, b: Builtin.Int32) -> Builtin.Bool {
            return Builtin.builtin_eq_int32(a, b)
        }
        #[cname("truss_lt_u64")]
        func ltU64(a: Builtin.UInt64, b: Builtin.UInt64) -> Builtin.Bool {
            return Builtin.builtin_lt_uint64(a, b)
        }
        #[cname("truss_ge_f64")]
        func geF64(a: Builtin.Float64, b: Builtin.Float64) -> Builtin.Bool {
            return Builtin.builtin_ge_float64(a, b)
        }
        #[cname("truss_not_b")]
        func notB(a: Builtin.Bool) -> Builtin.Bool {
            return Builtin.builtin_not_bool(a)
        }
        #[cname("truss_bitnot_i32")]
        func bitnotI32(a: Builtin.Int32) -> Builtin.Int32 {
            return Builtin.builtin_bitnot_int32(a)
        }
        """
    )
    let result = Driver(config: DriverConfig(dumpLLVMIR: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("icmp eq i32"))
    #expect(result.stdout.contains("icmp ult i64"))
    #expect(result.stdout.contains("fcmp oge double"))
    #expect(result.stdout.contains("xor i1"))
    #expect(result.stdout.contains("xor i32"))
}

private func tempOutput(_ name: String) throws -> String {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-emit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(name).path
}

private func hasSystemCompiler() -> Bool {
    SystemLinker.findCompiler() != nil
}

private let emitSource = """
#[cname("main")]
func main() -> Builtin.Int32 {
    return Builtin.builtin_add_int32(1, 1)
}
"""

@Test
func driverEmitsObjectFile() throws {
    let output = try tempOutput("main.o")
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .Object)).runString(emitSource)
    #expect(!result.hasErrors)
    let bytes = try Data(contentsOf: URL(fileURLWithPath: output))
    #expect(!bytes.isEmpty)
}

@Test
func driverEmitsLLVMIRFile() throws {
    let output = try tempOutput("main.ll")
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .LLVMIR)).runString(emitSource)
    #expect(!result.hasErrors)
    let text = try String(contentsOfFile: output, encoding: .utf8)
    #expect(text.contains("define i32 @main"))
    #expect(text.contains("target triple"))
}

@Test
func driverEmitsAssemblyFile() throws {
    let output = try tempOutput("main.s")
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .Assembly)).runString(emitSource)
    #expect(!result.hasErrors)
    let text = try String(contentsOfFile: output, encoding: .utf8)
    #expect(text.contains(".text"))
    #expect(text.contains("main"))
}

@Test
func driverEmitsExternDeclaration() throws {
    let output = try tempOutput("extern.ll")
    let source = """
    extern "C" {
        func truss_helper(x: Builtin.Int32) -> Builtin.Int32
    }
    #[cname("main")]
    func main() -> Builtin.Int32 {
        return truss_helper(x: 1)
    }
    """
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .LLVMIR)).runString(source)
    #expect(!result.hasErrors)
    let text = try String(contentsOfFile: output, encoding: .utf8)
    #expect(text.contains("declare i32 @truss_helper"))
    #expect(text.contains("define i32 @main"))
}

@Test
func driverReportsEmitFailure() throws {
    let output = try tempOutput("missing/main.o")
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .Object))
        .runString(emitSource)
    #expect(result.hasErrors)
    #expect(result.stderr.contains("could not emit '\(output)'"))
}

@Test(.enabled(if: hasSystemCompiler()))
func driverEmitsRunnableExecutable() throws {
    let output = try tempOutput("main")
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .Executable)).runString(emitSource)
    #expect(!result.hasErrors)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: output)
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 2)
}

@Test(.enabled(if: hasSystemCompiler()))
func driverRunsPointerDereference() throws {
    let output = try tempOutput("ptr")
    let source = """
    precedencegroup Assign {
        assignment: true
    }
    infix operator = : Assign
    typealias Int32 = Builtin.Int32
    #[cname("main")]
    func main() -> Int32 {
        var x: Int32 = 1
        let p: Int32* = &x
        *p = 7
        return x
    }
    """
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .Executable)).runString(source)
    #expect(!result.hasErrors)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: output)
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 7)
}

@Test(.enabled(if: hasSystemCompiler()))
func driverEmitsMergedMultiFileExecutable() throws {
    let helper = try writeTemp(
        "helper.truss",
        """
        func helper(x: Builtin.Int32) -> Builtin.Int32 {
            return Builtin.builtin_add_int32(x, 2)
        }
        """
    )
    let main = try writeTemp(
        "main.truss",
        """
        #[cname("main")]
        func main() -> Builtin.Int32 {
            return helper(x: 40)
        }
        """
    )
    let output = try tempOutput("main")
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .Executable))
        .run(files: [helper, main])
    #expect(!result.hasErrors)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: output)
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 42)
}

@Test
func driverParenthesizedFunctionReferenceInLet() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        func id(_ x: Builtin.Int32) -> Builtin.Int32 {
            return x
        }

        func main() -> Builtin.Int32 {
            let f: (Builtin.Int32) -> Builtin.Int32 = (id)
            return f(1)
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("closure(i32)->i32"))
}

@Test
func driverParenthesizedOperatorReference() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        precedencegroup AdditionPrecedence {
            associativity: left
            higherThan: AssignmentPrecedence
        }
        precedencegroup AssignmentPrecedence {
            associativity: right
            assignment: true
        }
        infix operator + : AdditionPrecedence

        func +(lhs: Builtin.Int32, rhs: Builtin.Int32) -> Builtin.Int32 {
            return Builtin.builtin_add_int32(lhs, rhs)
        }

        func main() -> Builtin.Int32 {
            let g: (Builtin.Int32, Builtin.Int32) -> Builtin.Int32 = (+)
            return g(1, 2)
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("closure(i32,i32)->i32"))
}

@Test
func driverParenthesizedFunctionReferenceAsCallArgument() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        func id(_ x: Builtin.Int32) -> Builtin.Int32 {
            return x
        }

        func apply(_ f: (Builtin.Int32) -> Builtin.Int32, _ v: Builtin.Int32) -> Builtin.Int32 {
            return f(v)
        }

        func main() -> Builtin.Int32 {
            return apply((id), 1)
        }
        """
    )
    #expect(!result.hasErrors)
}

@Test
func driverParenthesizedFunctionReferenceInReturn() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        func id(_ x: Builtin.Int32) -> Builtin.Int32 {
            return x
        }

        func makeF() -> (Builtin.Int32) -> Builtin.Int32 {
            return (id)
        }

        func main() -> Builtin.Int32 {
            let f = makeF()
            return f(1)
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("closure(i32)->i32"))
}

@Test
func driverParenthesizedFunctionReferenceGlobalInit() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        func id(_ x: Builtin.Int32) -> Builtin.Int32 {
            return x
        }

        let f: (Builtin.Int32) -> Builtin.Int32 = (id)

        func main() -> Builtin.Int32 {
            return f(1)
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("global @$t4main_1f : closure(i32)->i32"))
}

@Test
func driverParenthesizedFunctionReferenceCallee() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        func id(_ x: Builtin.Int32) -> Builtin.Int32 {
            return x
        }

        func main() -> Builtin.Int32 {
            return (id)(1)
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("closure @$t4main_2id"))
}

@Test
func driverNestedParenthesizedFunctionReference() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        func id(_ x: Builtin.Int32) -> Builtin.Int32 {
            return x
        }

        func main() -> Builtin.Int32 {
            let f: (Builtin.Int32) -> Builtin.Int32 = ((id))
            let g: (Builtin.Int32) -> Builtin.Int32 = (((id)))
            return g(f(((id))(1)))
        }
        """
    )
    #expect(!result.hasErrors)
}

@Test
func driverParenthesizedMethodCalleeStillErrors() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        struct S {
            init() {}
            func add(_ a: Builtin.Int32) -> Builtin.Int32 {
                return a
            }
        }

        func main() -> Builtin.Int32 {
            let s = S()
            return (s.add)(1)
        }
        """
    )
    #expect(result.hasErrors)
    #expect(result.stderr.contains("passes 1 arguments but the callee declares 2 parameters"))
}

@Test(.enabled(if: hasSystemCompiler()))
func driverRunsOutOfOrderLabelledArgumentsInParameterOrder() throws {
    let output = try tempOutput("labelled-order")
    let source = """
    typealias Int32 = Builtin.Int32
    func pick(a: Int32, b: Int32) -> Int32 {
        return b
    }
    #[cname("main")]
    func main() -> Int32 {
        return pick(b: 2, a: 10)
    }
    """
    let result = Driver(config: DriverConfig(outputPath: output, emitKind: .Executable)).runString(source)
    #expect(!result.hasErrors)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: output)
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 2)
}

@Test
func driverRejectsMissingArgumentLabel() throws {
    let file = try writeTemp(
        "missing-label.truss",
        "typealias Int32 = Builtin.Int32\n"
            + "func pick(a: Int32, b: Int32) -> Int32 { a }\n"
            + "func main() -> Int32 { return pick(1, 2) }\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("no exact matches in call to 'pick'"))
}

@Test
func driverRejectsMissingArgumentLabelOnFunctionValueCall() throws {
    let file = try writeTemp(
        "missing-label-value.truss",
        "typealias Int32 = Builtin.Int32\n"
            + "func pick(a: Int32, b: Int32) -> Int32 { a }\n"
            + "func main() -> Int32 {\n    let h = pick\n    return h(1, 2)\n}\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("missing argument label 'a' in call to 'h'"))
}

@Test
func driverParenthesizedDefaultParameterValue() {
    let result = Driver(config: DriverConfig(dumpTIR: true)).runString(
        """
        func id(_ x: Builtin.Int32) -> Builtin.Int32 {
            return x
        }

        func apply(_ f: (Builtin.Int32) -> Builtin.Int32 = (id)) -> Builtin.Int32 {
            return f(1)
        }

        func main() -> Builtin.Int32 {
            return apply(id)
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("closure(i32)->i32"))
}

@Test
func driverFoldsFunctionTypeGenericApplicationInReturnType() {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString(
        """
        typealias Int32 = Builtin.Int32

        struct Box<T> {
            let v: T
        }

        func make() -> Box<(Int32) -> Int32> {
            return make()
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(!result.stderr.contains("error:"))
    #expect(result.stdout.contains("FunctionDecl make"))
    #expect(result.stdout.contains("GenericApplication ty:Generic(StructType(Box)"))
    #expect(result.stdout.contains("-Return"))
}

@Test
func driverFoldsFunctionTypeGenericApplicationInCallPosition() {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString(
        """
        typealias Int32 = Builtin.Int32

        struct Box<T> {
            let v: T
        }

        func id(_ x: Int32) -> Int32 {
            return x
        }

        func main() -> Int32 {
            let c = Box<(Int32) -> Int32>(v: id)
            return 1
        }
        """
    )
    #expect(!result.hasErrors)
    #expect(!result.stderr.contains("error:"))
    #expect(result.stdout.contains("GenericApplication ty:Generic(StructType(Box)"))
    #expect(result.stdout.contains("willBeCalled"))
    #expect(result.stdout.contains("Argument label:v"))
}

private let explicitClosureGenericSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

struct Box<T> {
    let v: T
    init(v: T) {
        self.v = v
    }
}

func id(_ x: Int32) -> Int32 {
    return x
}

func main() -> Int32 {
    let c: Box<(Int32) -> Int32> = Box<(Int32) -> Int32>(v: id)
    return 1
}
"""

@Test
func driverTypeChecksExplicitClosureGenericArgument() throws {
    let file = try writeTemp("explicit-closure-generic.truss", explicitClosureGenericSource)
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("(Builtin.Int32) -> Builtin.Int32"))
    #expect(result.stdout.contains("Generic(StructType(Box)"))
}

@Test
func driverRejectsWrongTypeForExplicitClosureGenericArgument() throws {
    let source = explicitClosureGenericSource.replacingOccurrences(
        of: "Box<(Int32) -> Int32>(v: id)", with: "Box<(Int32) -> Int32>(v: 1)"
    )
    let file = try writeTemp("explicit-closure-generic-wrong.truss", source)
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("no exact matches in call to 'init'"))
}

private let boxDeclarationSource = """
typealias Int32 = Builtin.Int32

struct Box<T> {
    let v: T
}

"""

@Test
func driverFoldsSharedGenericCloserInParameter() {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString(
        boxDeclarationSource
            + "func f(c: Box<(Int32) -> Box<Int32>>) -> Int32 {\n    return 0\n}"
    )
    #expect(!result.hasErrors)
    #expect(!result.stderr.contains("error:"))
    #expect(result.stdout.contains("GenericApplication ty:Generic(StructType(Box)"))
    #expect(result.stdout.contains("(Builtin.Int32) -> Generic(StructType(Box)"))
}

@Test
func driverFoldsSharedTripleGenericCloserInParameter() {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString(
        boxDeclarationSource
            + "func f(c: Box<(Int32) -> Box<Box<Int32>>>) -> Int32 {\n    return 0\n}"
    )
    #expect(!result.hasErrors)
    #expect(!result.stderr.contains("error:"))
    #expect(result.stdout.contains("(Builtin.Int32) -> Generic(StructType(Box)"))
    #expect(result.stdout.contains("<Generic(StructType(Box)"))
}

@Test
func driverFoldsSharedGenericCloserInCallPosition() {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString(
        boxDeclarationSource
            + """
            func f(c: (Int32) -> Box<Int32>) -> Int32 {
                let b: Box<(Int32) -> Box<Int32>> = Box<(Int32) -> Box<Int32>>(v: c)
                return 0
            }
            """
    )
    #expect(!result.hasErrors)
    #expect(!result.stderr.contains("error:"))
    #expect(result.stdout.contains("(Builtin.Int32) -> Generic(StructType(Box)"))
    #expect(result.stdout.contains("willBeCalled"))
    #expect(result.stdout.contains("Argument label:v"))
}

@Test
func driverFoldsSharedGenericCloserInReturnType() {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString(
        boxDeclarationSource
            + "func make() -> Box<(Int32) -> Box<Int32>> {\n    return make()\n}"
    )
    #expect(!result.hasErrors)
    #expect(!result.stderr.contains("error:"))
    #expect(result.stdout.contains("FunctionDecl make"))
    #expect(result.stdout.contains("(Builtin.Int32) -> Generic(StructType(Box)"))
    #expect(result.stdout.contains("-Return"))
}
