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
        "a.truss", "struct Point {\n    var x: Int32\n    var y: Int32\n}\n"
    )
    let b = try writeTemp("b.truss", "extension Point {\n    func sum() -> Int32 {\n        self.x + self.y\n    }\n}\n")
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
