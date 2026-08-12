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

@Test func driverCompilesSingleFile() throws {
    let file = try writeTemp("main.truss", "func f() {}\n")
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stderr.isEmpty)
}

@Test func driverMultiFileMergesCrossFileExtension() throws {
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

@Test func driverDefineActivatesConditional() throws {
    let file = try writeTemp("cond.truss", "#if FLAG\nfunc f() {}\n#endif\n")
    let on = Driver(config: DriverConfig(defines: ["FLAG": "1"], dumpAST: true))
        .run(files: [file])
    #expect(!on.hasErrors)
    #expect(on.stdout.contains("FunctionDecl"))
    let off = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!off.hasErrors)
    #expect(!off.stdout.contains("FunctionDecl"))
}

@Test func driverDefineWithValue() throws {
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

@Test func driverDumpFlags() throws {
    let file = try writeTemp("dump.truss", "func f() {}\n")
    let result = Driver(
        config: DriverConfig(dumpAST: true, dumpSymbols: true, dumpSource: true)
    ).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("Program"))
    #expect(result.stdout.contains("package"))
    #expect(result.stdout.contains("func f()"))
}

@Test func driverTypeCheckerStructuralAnnotations() throws {
    let file = try writeTemp(
        "types.truss",
        """
        struct S {}
        struct Box<T> {}
        typealias A = S
        let b: S?
        let g: Box<S>
        let f: (S) -> S
        let p: P & Q
        protocol P {}
        protocol Q {}
        """
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("ty:Optional(StructType(S)#0)"))
    #expect(result.stdout.contains("ty:Generic(StructType(Box)#1<StructType(S)#0>)"))
    #expect(result.stdout.contains("ty:Function((StructType(S)#0) -> StructType(S)#0)"))
    #expect(result.stdout.contains("ty:Composition(ProtocolType(P)#2 & ProtocolType(Q)#3)"))
}

@Test func driverMissingFileReportsError() {
    let missing = "/nonexistent/truss-\(UUID().uuidString).truss"
    let result = Driver(config: DriverConfig()).run(files: [missing])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("could not read file"))
}

@Test func driverTargetTriple() throws {
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

@Test func driverIncludeResolvesRelativeToSourceFile() throws {
    let header = try writeTemp("defs.truss", "#define MAX 42\n")
    let dir = (header as NSString).deletingLastPathComponent
    let main = dir + "/main.truss"
    try "#include \"defs.truss\"\nfunc g() { MAX }\n".write(
        to: URL(fileURLWithPath: main), atomically: true, encoding: .utf8)
    let result = Driver(config: DriverConfig(dumpSource: true)).run(files: [main])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("42"))
}

@Test func driverStopsAfterFrontendError() throws {
    let a = try writeTemp("bad.truss", "struct S {\n")
    let b = try writeTemp("ext.truss", "extension Missing {}\n")
    let result = Driver(config: DriverConfig()).run(files: [a, b])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("expected '}' after struct body"))
    #expect(!result.stderr.contains("has no matching declaration"))
}

@Test func driverStopsAfterCollectorError() throws {
    let file = try writeTemp(
        "dup.truss", "struct S {}\nstruct S {}\nextension Missing {}\n"
    )
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("invalid redeclaration of type 'S'"))
    #expect(!result.stderr.contains("has no matching declaration"))
}

@Test func driverSkipsDumpOnError() throws {
    let file = try writeTemp("bad2.truss", "struct S {\n")
    let result = Driver(
        config: DriverConfig(dumpAST: true, dumpSymbols: true, dumpSource: true)
    ).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stdout.isEmpty)
}

@Test func driverDumpsOnErrorWhenEnabled() throws {
    let file = try writeTemp("bad3.truss", "struct S {\n")
    let on = Driver(config: DriverConfig(dumpAST: true, dumpOnError: true)).run(files: [file])
    #expect(on.hasErrors)
    #expect(on.stdout.contains("Program"))
    let off = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(off.hasErrors)
    #expect(off.stdout.isEmpty)
}

@Test func driverRunStringParsesInMemorySource() throws {
    let result = Driver(config: DriverConfig(dumpAST: true)).runString("func f() {}\n")
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("FunctionDecl"))
}

@Test func driverFoldsExpressionsByPrecedence() throws {
    let file = try writeTemp(
        "fold.truss",
        "precedencegroup Additive {} precedencegroup Multiplicative { higherThan: Additive }\n"
            + "infix operator +: Additive infix operator *: Multiplicative\n"
            + "struct S {}\n"
            + "func +(lhs: S, rhs: S) -> S { lhs }\n"
            + "func *(lhs: S, rhs: S) -> S { lhs }\n"
            + "func main() { 1 + 2 * 3 }\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("Binary"))
    #expect(!result.stdout.contains("SequentialExpression"))
}

@Test func driverFoldsUnaryOperators() throws {
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

@Test func driverFoldsGenericApplication() throws {
    let file = try writeTemp(
        "generic.truss",
        "struct Box {}\nstruct S {}\nfunc main() { Box<S> }\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("GenericApplication"))
    #expect(!result.stdout.contains("SequentialExpression"))
}

@Test func driverReportsUnknownOperator() throws {
    let file = try writeTemp("unknown-op.truss", "func main() { 1 + 2 }\n")
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("unknown operator '+'"))
}

@Test func driverOperatorFunctionResolution() throws {
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

@Test func driverOperatorWithoutFunctionReportsError() throws {
    let file = try writeTemp(
        "op-noimpl.truss",
        "precedencegroup Additive {}\ninfix operator +: Additive\n"
            + "func main() { 1 + 2 }\n"
    )
    let result = Driver(config: DriverConfig()).run(files: [file])
    #expect(result.hasErrors)
    #expect(result.stderr.contains("operator '+' has no function declaration"))
}

@Test func driverGenericFunctionEndToEnd() throws {
    let file = try writeTemp(
        "generic-fn.truss",
        "struct S {}\n"
            + "func id<T>(x: T) -> T { x }\n"
            + "func main() {\nvar s: S\nlet a = id(s)\n}\n"
    )
    let result = Driver(config: DriverConfig(dumpAST: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("ty:StructType(S)"))
}

@Test func driverMismatchedTypeReportsError() throws {
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

@Test func driverAssignmentToPropertyEndToEnd() throws {
    let file = try writeTemp(
        "assign.truss",
        """
        precedencegroup Assignment { assignment: true }
        infix operator =: Assignment
        struct TT {
            init() {}
        }
        struct TS {
            var x: TT = TT()
            var y: TT = TT()
            init() {}
        }
        func f(s: TS) -> TT {
            s.y = TT()
            return s.x
        }
        """
    )
    let result = Driver(config: DriverConfig(dumpTIR: true)).run(files: [file])
    #expect(!result.hasErrors)
    #expect(result.stdout.contains("StructElementAddr"))
    #expect(result.stdout.contains("Store "))
}
