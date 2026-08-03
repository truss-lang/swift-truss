import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSyntax
import Foundation

func preprocessWithDiagnostics(
    _ source: String, flags: Set<String> = [], target: String = "x86_64-unknown-linux-gnu",
    workingDirectory: String = ""
) -> ([Token], [Diagnostic]) {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexer = Lexer(input: stream)
    let tokens = lexer.parse().tokens
    let result = Preprocessor(context: context).process(
        tokens,
        config: PreprocessorConfig(flags: flags, target: target, workingDirectory: workingDirectory))
    return (result, context.diagnositicEngine.diagnostics)
}

func preprocess(
    _ source: String, flags: Set<String> = [], target: String = "x86_64-unknown-linux-gnu",
    workingDirectory: String = ""
) -> [Token] {
    preprocessWithDiagnostics(source, flags: flags, target: target, workingDirectory: workingDirectory).0
}

func tokenValues(_ tokens: [Token]) -> [String] {
    tokens.map { $0.value }
}

@Test func ppPassthroughWithoutDirectives() {
    let tokens = preprocess("let x = 1\nfunc f() {}")
    #expect(tokenValues(tokens) == ["let", "x", "=", "1", "func", "f", "(", ")", "{", "}"])
}

@Test func ppKeepsActiveBranch() {
    let tokens = preprocess("#if A\n1\n#else\n2\n#endif", flags: ["A"])
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppTakesElseWhenFlagUnset() {
    let tokens = preprocess("#if A\n1\n#else\n2\n#endif")
    #expect(tokenValues(tokens) == ["2"])
}

@Test func ppIfZeroCommentOut() {
    let tokens = preprocess("#if 0\n1\n2\n#endif\n3")
    #expect(tokenValues(tokens) == ["3"])
}

@Test func ppNestedConditional() {
    let source = "#if A\n#if B\n1\n#else\n2\n#endif\n#else\n3\n#endif"
    #expect(tokenValues(preprocess(source, flags: ["A", "B"])) == ["1"])
    #expect(tokenValues(preprocess(source, flags: ["A"])) == ["2"])
    #expect(tokenValues(preprocess(source, flags: ["B"])) == ["3"])
    #expect(tokenValues(preprocess(source)) == ["3"])
}

@Test func ppElseIfChain() {
    let source = "#if A\n1\n#elseif B\n2\n#elseif C\n3\n#else\n4\n#endif"
    #expect(tokenValues(preprocess(source, flags: ["A"])) == ["1"])
    #expect(tokenValues(preprocess(source, flags: ["B"])) == ["2"])
    #expect(tokenValues(preprocess(source, flags: ["C"])) == ["3"])
    #expect(tokenValues(preprocess(source)) == ["4"])
    #expect(tokenValues(preprocess(source, flags: ["A", "C"])) == ["1"])
}

@Test func ppLogicalOperators() {
    let source = "#if A && B\n1\n#endif"
    #expect(tokenValues(preprocess(source, flags: ["A", "B"])) == ["1"])
    #expect(tokenValues(preprocess(source, flags: ["A"])) == [])
    #expect(tokenValues(preprocess("#if A || B\n1\n#endif", flags: ["B"])) == ["1"])
    #expect(tokenValues(preprocess("#if !A\n1\n#endif")) == ["1"])
    #expect(tokenValues(preprocess("#if (A || B) && C\n1\n#endif", flags: ["A", "C"])) == ["1"])
    #expect(tokenValues(preprocess("#if true\n1\n#endif")) == ["1"])
    #expect(tokenValues(preprocess("#if false\n1\n#endif")) == [])
}

@Test func ppDirectivesOnSameLine() {
    let tokens = preprocess("#if A #else 2 #endif")
    #expect(tokenValues(tokens) == ["2"])
    let tokens2 = preprocess("#if A #else 2 #endif", flags: ["A"])
    #expect(tokenValues(tokens2) == [])
}

@Test func ppConditionStopsAtLineEnd() {
    let tokens = preprocess("#if A\nx\n#endif", flags: ["A"])
    #expect(tokenValues(tokens) == ["x"])
}

@Test func ppNestedIfInsideInactiveBranch() {
    let tokens = preprocess("#if 0\n#if B\n1\n#endif\n#else\n2\n#endif")
    #expect(tokenValues(tokens) == ["2"])
}

@Test func ppUnterminatedIf() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#if A\n1", flags: ["A"])
    #expect(tokenValues(tokens) == ["1"])
    #expect(diagnostics.contains { $0.message.contains("unterminated #if") })
}

@Test func ppStrayEndif() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#endif")
    #expect(tokens.isEmpty)
    #expect(diagnostics.contains { $0.message.contains("unexpected #endif") })
}

@Test func ppStrayElse() {
    let (_, diagnostics) = preprocessWithDiagnostics("#else")
    #expect(diagnostics.contains { $0.message.contains("unexpected #else") })
}

@Test func ppStrayElseIf() {
    let (_, diagnostics) = preprocessWithDiagnostics("#elseif A")
    #expect(diagnostics.contains { $0.message.contains("unexpected #elseif") })
}

@Test func ppUnknownDirective() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#foo bar")
    #expect(diagnostics.contains { $0.message.contains("unknown preprocessing directive") })
    #expect(tokenValues(tokens) == ["foo", "bar"])
}

@Test func ppBadConditionToken() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#if \"str\"\n1\n#else\n2\n#endif")
    #expect(diagnostics.contains { $0.message.contains("unexpected token") })
    #expect(tokens.isEmpty)
}

@Test func ppEmptyCondition() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#if\n1\n#else\n2\n#endif")
    #expect(diagnostics.contains { $0.message.contains("expected expression") })
    #expect(tokens.isEmpty)
}

@Test func ppErrorDirective() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#error(\"boom\")\n1")
    #expect(diagnostics.contains { $0.severity == .error && $0.message == "boom" })
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppWarningDirective() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#warning(\"careful\")\n1")
    #expect(diagnostics.contains { $0.severity == .warning && $0.message == "careful" })
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppErrorSkippedWhenInactive() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#if 0\n#error(\"boom\")\n#endif\n1")
    #expect(diagnostics.isEmpty)
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppErrorMissingMessage() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#error\n1")
    #expect(diagnostics.contains { $0.message.contains("expected string literal") })
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppObjectMacro() {
    let tokens = preprocess("#define MAX 100\nMAX")
    #expect(tokenValues(tokens) == ["100"])
}

@Test func ppObjectMacroMultiToken() {
    let tokens = preprocess("#define PAIR (1, 2)\nPAIR")
    #expect(tokenValues(tokens) == ["(", "1", ",", "2", ")"])
}

@Test func ppObjectMacroWithString() {
    let tokens = preprocess("#define GREETING \"hi\"\nGREETING")
    #expect(tokenValues(tokens) == ["hi"])
}

@Test func ppObjectMacroEmptyBody() {
    let tokens = preprocess("#define X\nX\n1")
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppMacroCascade() {
    let tokens = preprocess("#define A B\n#define B 42\nA")
    #expect(tokenValues(tokens) == ["42"])
}

@Test func ppMacroSelfReference() {
    let tokens = preprocess("#define A B\n#define B A\nA")
    #expect(tokenValues(tokens) == ["A"])
}

@Test func ppMacroUndef() {
    let tokens = preprocess("#define X 1\nX\n#undef X\nX")
    #expect(tokenValues(tokens) == ["1", "X"])
}

@Test func ppMacroInactiveDefine() {
    let tokens = preprocess("#if 0\n#define X 1\n#endif\nX")
    #expect(tokenValues(tokens) == ["X"])
}

@Test func ppIfDef() {
    let source = "#ifdef X\n1\n#else\n2\n#endif"
    #expect(tokenValues(preprocess(source, flags: ["X"])) == ["1"])
    #expect(tokenValues(preprocess("#define X 1\n#ifdef X\n1\n#else\n2\n#endif")) == ["1"])
    #expect(tokenValues(preprocess(source)) == ["2"])
}

@Test func ppIfNDef() {
    let source = "#ifndef X\n1\n#else\n2\n#endif"
    #expect(tokenValues(preprocess(source)) == ["1"])
    #expect(tokenValues(preprocess(source, flags: ["X"])) == ["2"])
}

@Test func ppDefinedInCondition() {
    let source = "#if defined(X) && A\n1\n#endif"
    #expect(tokenValues(preprocess(source, flags: ["X", "A"])) == ["1"])
    #expect(tokenValues(preprocess(source, flags: ["A"])) == [])
    #expect(tokenValues(preprocess("#define X 1\n#if defined(X)\n1\n#endif")) == ["1"])
}

@Test func ppDefinedBareForm() {
    let tokens = preprocess("#if defined X\n1\n#endif", flags: ["X"])
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppDefinedNegated() {
    let tokens = preprocess("#if !defined(X)\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppFunctionMacro() {
    let tokens = preprocess("#define F(x) x + 1\nF(2)")
    #expect(tokenValues(tokens) == ["2", "+", "1"])
}

@Test func ppFunctionMacroMultiParam() {
    let tokens = preprocess("#define ADD(a, b) a + b\nADD(1, 2)")
    #expect(tokenValues(tokens) == ["1", "+", "2"])
}

@Test func ppFunctionMacroArgPreExpansion() {
    let tokens = preprocess("#define DOUBLE(x) x + x\n#define N 5\nDOUBLE(N)")
    #expect(tokenValues(tokens) == ["5", "+", "5"])
}

@Test func ppFunctionMacroNestedCall() {
    let tokens = preprocess("#define DOUBLE(x) x + x\nDOUBLE(DOUBLE(2))")
    #expect(tokenValues(tokens) == ["2", "+", "2", "+", "2", "+", "2"])
}

@Test func ppVariadicMacro() {
    let tokens = preprocess("#define LOG(...) print(__VA_ARGS__)\nLOG(1, 2, 3)")
    #expect(tokenValues(tokens) == ["print", "(", "1", ",", "2", ",", "3", ")"])
}

@Test func ppVariadicMacroNamedParams() {
    let tokens = preprocess("#define LOG(fmt, ...) log(fmt, __VA_ARGS__)\nLOG(\"x\", 1, 2)")
    #expect(tokenValues(tokens) == ["log", "(", "x", ",", "1", ",", "2", ")"])
}

@Test func ppFunctionMacroArgCountMismatch() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#define F(x) x\nF(1, 2)")
    #expect(diagnostics.contains { $0.message.contains("expects 1 arguments, but got 2") })
    #expect(diagnostics.contains { $0.severity == .note })
    #expect(tokenValues(tokens) == ["F", "(", "1", ",", "2", ")"])
}

@Test func ppFunctionMacroWithoutCall() {
    let tokens = preprocess("#define F(x) x\nF")
    #expect(tokenValues(tokens) == ["F"])
}

@Test func ppFunctionMacroEmptyArgument() {
    let tokens = preprocess("#define F(x) (x)\nF()")
    #expect(tokenValues(tokens) == ["(", ")"])
}

@Test func ppStringify() {
    let tokens = preprocess("#define STR(x) #x\nSTR(hello)")
    #expect(tokenValues(tokens) == ["hello"])
    #expect(tokens[0].kind == .StringLiteral)
}

@Test func ppStringifyNoArgExpansion() {
    let tokens = preprocess("#define N 5\n#define STR(x) #x\nSTR(N)")
    #expect(tokenValues(tokens) == ["N"])
}

@Test func ppStringifyMultiToken() {
    let tokens = preprocess("#define STR(x) #x\nSTR(a b)")
    #expect(tokenValues(tokens) == ["a b"])
}

@Test func ppTokenPaste() {
    let tokens = preprocess("#define CAT(a, b) a ## b\nCAT(foo, bar)")
    #expect(tokenValues(tokens) == ["foobar"])
}

@Test func ppTokenPasteNumber() {
    let tokens = preprocess("#define CAT(a, b) a ## b\nCAT(1, 2)")
    #expect(tokenValues(tokens) == ["12"])
}

@Test func ppTokenPasteUnexpandedOperand() {
    let tokens = preprocess("#define CAT(a, b) a ## b\n#define FOO bar\nCAT(FOO, 1)")
    #expect(tokenValues(tokens) == ["FOO1"])
}

@Test func ppOSCondition() {
    let source = "#if os(Linux)\n1\n#else\n2\n#endif"
    #expect(tokenValues(preprocess(source)) == ["1"])
    #expect(tokenValues(preprocess(source, target: "x86_64-apple-macosx")) == ["2"])
}

@Test func ppArchCondition() {
    let source = "#if arch(x86_64)\n1\n#endif"
    #expect(tokenValues(preprocess(source)) == ["1"])
    #expect(tokenValues(preprocess(source, target: "arm64-unknown-linux-gnu")) == [])
}

@Test func ppTargetEnvironmentCondition() {
    let source = "#if targetEnvironment(simulator)\n1\n#endif"
    #expect(tokenValues(preprocess(source, target: "x86_64-apple-ios-simulator")) == ["1"])
    #expect(tokenValues(preprocess(source)) == [])
}

@Test func ppUnknownConditionFunction() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#if canImport(X)\n1\n#endif")
    #expect(diagnostics.contains { $0.message.contains("unknown function") })
    #expect(tokens.isEmpty)
}

@Test func ppConstExprArithmetic() {
    let tokens = preprocess("#if 2 + 3 * 4 == 14\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
    #expect(tokenValues(preprocess("#if 2 + 3 * 4 == 15\n1\n#endif")) == [])
}

@Test func ppConstExprMacroExpansion() {
    let tokens = preprocess("#define MAX 10\n#if MAX > 3\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
    #expect(tokenValues(preprocess("#define MAX 2\n#if MAX > 3\n1\n#endif")) == [])
}

@Test func ppConstExprComparison() {
    let tokens = preprocess("#if 1 < 2 && 3 >= 3 && 4 != 5\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppConstExprBitwise() {
    let tokens = preprocess("#if (1 << 4) == 16 && (7 & 3) == 3 && (5 | 2) == 7 && (5 ^ 1) == 4\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppConstExprCharLiteral() {
    let tokens = preprocess("#if 'a' == 97\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppConstExprBooleanLiteral() {
    let tokens = preprocess("#if true == 1 && false == 0\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppConstExprUndefinedIdentifierIsZero() {
    let tokens = preprocess("#if UNDEFINED\n1\n#else\n2\n#endif")
    #expect(tokenValues(tokens) == ["2"])
}

@Test func ppConstExprDivisionByZero() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#if 1 / 0\n1\n#else\n2\n#endif")
    #expect(diagnostics.contains { $0.message.contains("division by zero") })
    #expect(tokens.isEmpty)
}

@Test func ppConstExprShortCircuit() {
    let tokens = preprocess("#if 0 && (1 / 0)\n1\n#else\n2\n#endif")
    #expect(tokenValues(tokens) == ["2"])
    #expect(tokenValues(preprocess("#if 1 || (1 / 0)\n1\n#endif")) == ["1"])
}

@Test func ppBuiltinFileAndLine() {
    let (tokens, _) = preprocessWithDiagnostics("__FILE__\n__LINE__")
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "<test>")
    #expect(tokens[1].kind == .IntegerLiteral(2))
}

@Test func ppBuiltinDateAndTime() {
    let (tokens, _) = preprocessWithDiagnostics("__DATE__\n__TIME__")
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value.count == 11)
    #expect(tokens[1].kind == .StringLiteral)
    #expect(tokens[1].value.count == 8)
}

@Test func ppBuiltinInCondition() {
    let tokens = preprocess("#if __LINE__ == 1\n1\n#endif")
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppInclude() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-pp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let header = dir.appendingPathComponent("defs.truss")
    try "#define MAX 42".write(to: header, atomically: true, encoding: .utf8)
    let tokens = preprocess("#include \"defs.truss\"\nMAX", workingDirectory: dir.path)
    #expect(tokenValues(tokens) == ["42"])
}

@Test func ppIncludeAngleBrackets() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-pp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let header = dir.appendingPathComponent("defs.truss")
    try "#define MAX 7".write(to: header, atomically: true, encoding: .utf8)
    let tokens = preprocess("#include <defs.truss>\nMAX", workingDirectory: dir.path)
    #expect(tokenValues(tokens) == ["7"])
}

@Test func ppIncludeGuardMacro() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-pp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let header = dir.appendingPathComponent("defs.truss")
    try "#ifndef DEFS\n#define DEFS\n#define MAX 42\n#endif".write(
        to: header, atomically: true, encoding: .utf8)
    let source = "#include \"defs.truss\"\n#include \"defs.truss\"\nMAX"
    let tokens = preprocess(source, workingDirectory: dir.path)
    #expect(tokenValues(tokens) == ["42"])
}

@Test func ppIncludeNested() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-pp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let inner = dir.appendingPathComponent("inner.truss")
    try "#define X 9".write(to: inner, atomically: true, encoding: .utf8)
    let outer = dir.appendingPathComponent("outer.truss")
    try "#include \"inner.truss\"".write(to: outer, atomically: true, encoding: .utf8)
    let tokens = preprocess("#include \"outer.truss\"\nX", workingDirectory: dir.path)
    #expect(tokenValues(tokens) == ["9"])
}

@Test func ppIncludeCircular() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-pp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.truss")
    let b = dir.appendingPathComponent("b.truss")
    try "#include \"b.truss\"".write(to: a, atomically: true, encoding: .utf8)
    try "#include \"a.truss\"".write(to: b, atomically: true, encoding: .utf8)
    let (tokens, diagnostics) = preprocessWithDiagnostics(
        "#include \"a.truss\"", workingDirectory: dir.path)
    #expect(diagnostics.contains { $0.message.contains("circular #include") })
    #expect(tokens.isEmpty)
}

@Test func ppIncludeMissingFile() {
    let (_, diagnostics) = preprocessWithDiagnostics("#include \"nope.truss\"")
    #expect(diagnostics.contains { $0.message.contains("file not found") })
}

@Test func ppIncludeSkippedWhenInactive() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truss-pp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let tokens = preprocess("#if 0\n#include \"nope.truss\"\n#endif\n1", workingDirectory: dir.path)
    #expect(tokenValues(tokens) == ["1"])
}

@Test func ppPragmaIgnored() {
    let tokens = preprocess("#pragma once\n1")
    #expect(tokenValues(tokens) == ["1"])
}
