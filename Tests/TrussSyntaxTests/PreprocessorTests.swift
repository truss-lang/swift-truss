import Foundation
import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSyntax

func preprocessWithDiagnostics(
    _ source: String, flags: Set<String> = [], target: String = "x86_64-unknown-linux-gnu",
    workingDirectory: String = ""
) -> ([Token], [Diagnostic]) {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexerResult = Lexer(input: stream).parse()
    let result = Preprocessor(context: context).process(
        lexerResult,
        config: PreprocessorConfig(flags: flags, target: target, workingDirectory: workingDirectory)
    )
    return (result.tokens, context.diagnositicEngine.diagnostics)
}

func preprocess(
    _ source: String, flags: Set<String> = [], target: String = "x86_64-unknown-linux-gnu",
    workingDirectory: String = ""
) -> [Token] {
    preprocessWithDiagnostics(source, flags: flags, target: target, workingDirectory: workingDirectory).0
}

func tokenValues(_ tokens: [Token]) -> [String] {
    tokens.map(\.value)
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

@Test func ppZeroParameterMacro() {
    let tokens = preprocess("#define funclike() add\n#define add(x, y) x + y\nfunclike()(1, 2)")
    #expect(tokenValues(tokens) == ["1", "+", "2"])
}

@Test func ppZeroParameterMacroSimpleCall() {
    let tokens = preprocess("#define VERSION() 42\nVERSION()")
    #expect(tokenValues(tokens) == ["42"])
}

@Test func ppZeroParameterMacroExtraArg() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#define F() 1\nF(2)")
    #expect(diagnostics.contains { $0.message.contains("expects 0 arguments, but got 1") })
    #expect(tokenValues(tokens) == ["F", "(", "2", ")"])
}

@Test func ppVariadicMacroEmptyCall() {
    let tokens = preprocess("#define LOG(...) print(__VA_ARGS__)\nLOG()")
    #expect(tokenValues(tokens) == ["print", "(", ")"])
}

@Test func ppEmptyMacroExpansion() {
    let tokens = preprocess("#define EMPTY\nEMPTY")
    #expect(tokens.isEmpty)
}

@Test func ppEmptyMacroWithCode() {
    let tokens = preprocess("#define EMPTY\n1 EMPTY 2")
    #expect(tokenValues(tokens) == ["1", "2"])
}

@Test func ppFunctionMacroEmptyExpansion() {
    let tokens = preprocess("#define F(x)\nF(1)")
    #expect(tokens.isEmpty)
}

@Test func ppEmptyMacroExpansionChain() {
    let tokens = preprocess("#define A EMPTY\n#define EMPTY\nA")
    #expect(tokens.isEmpty)
}

@Test func ppEmptyMacroInCondition() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#define EMPTY\n#if EMPTY\n1\n#endif")
    #expect(diagnostics.contains { $0.message.contains("expected expression") })
    #expect(tokens.isEmpty)
}

@Test func ppDeferExpansion() {
    let source =
        "#define EMPTY()\n#define DEFER2(A) A EMPTY()\n#define A() 123\n#define EXPAND(...) __VA_ARGS__\nEXPAND(DEFER2(A)())"
    let tokens = preprocess(source)
    #expect(tokenValues(tokens) == ["123"])
}

@Test func ppDeferDirectStillDefers() {
    let source = "#define EMPTY()\n#define DEFER2(A) A EMPTY()\n#define A() 123\nDEFER2(A)()"
    let tokens = preprocess(source)
    #expect(tokenValues(tokens) == ["A", "(", ")"])
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
        "#include \"a.truss\"", workingDirectory: dir.path
    )
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

@Test func ppExpandedTokenUsesUseSitePosition() {
    let (tokens, _) = preprocessWithDiagnostics("#define MAX 100\nMAX")
    #expect(tokens[0].kind == .IntegerLiteral(100))
    #expect(tokens[0].pos.line == 2)
    #expect(tokens[0].pos.pos == 16)
}

@Test func ppExpandedFunctionTokenUsesUseSitePosition() {
    let (tokens, _) = preprocessWithDiagnostics("#define F(x) x + 1\nF(2)")
    #expect(tokens[0].pos.line == 2)
    #expect(tokens[1].pos.line == 2)
    #expect(tokens[2].pos.line == 2)
}

@Test func ppExpandedNestedTokenUsesUseSitePosition() {
    let (tokens, _) = preprocessWithDiagnostics("#define A B\n#define B 1\nA")
    #expect(tokens[0].pos.line == 3)
}

@Test func ppTokenPasteOperator() {
    let tokens = preprocess("#define ARROW(a, b) a ## b\nARROW(-, >)")
    #expect(tokenValues(tokens) == ["->"])
    #expect(tokens[0].kind == .Separator(.Arrow))
}

@Test func ppTokenPasteKeyword() {
    let tokens = preprocess("#define KW(a, b) a ## b\nKW(i, f)")
    #expect(tokenValues(tokens) == ["if"])
    #expect(tokens[0].kind == .Keyword(.If))
}

@Test func ppTokenPasteInvalid() {
    let (tokens, diagnostics) = preprocessWithDiagnostics("#define CAT(a, b) a ## b\nCAT(1, x)")
    #expect(diagnostics.contains { $0.message.contains("invalid token formed") })
    #expect(tokenValues(tokens) == ["1", "x"])
}

@Test func ppExpansionChainSingle() throws {
    let (tokens, _) = preprocessWithDiagnostics("#define MAX 100\nMAX")
    let chain = tokens[0].expansion
    try #require(chain?.count == 1)
    #expect(chain?[0].name == "MAX")
    #expect(chain?[0].definitionPosition.line == 1)
    #expect(chain?[0].definitionPosition.pos == 8)
}

@Test func ppExpansionChainNested() throws {
    let (tokens, _) = preprocessWithDiagnostics("#define A B\n#define B 1\nA")
    let chain = tokens[0].expansion
    try #require(chain?.count == 2)
    #expect(chain?[0].name == "B")
    #expect(chain?[0].definitionPosition.line == 2)
    #expect(chain?[1].name == "A")
    #expect(chain?[1].definitionPosition.line == 1)
}

@Test func ppExpansionChainFunctionMacro() throws {
    let (tokens, _) = preprocessWithDiagnostics("#define F(x) x + 1\nF(2)")
    let chain = tokens[0].expansion
    try #require(chain?.count == 1)
    #expect(chain?[0].name == "F")
    #expect(tokens[0].pos.line == 2)
}

@Test func ppUnexpandedTokenHasNoChain() {
    let (tokens, _) = preprocessWithDiagnostics("let x = 1")
    #expect(tokens[0].expansion == nil)
}

@Test func ppExpansionNotesHelper() throws {
    let context = Context()
    let src = Source(
        id: Id.SourceId(id: 0), filepath: "<test>",
        content: "#define MAX 100\nMAX"
    )
    context.register(source: src)
    let site = MacroExpansionSite(
        name: "MAX",
        definitionPosition: Position(pos: 8, line: 1, col: 9, len: 3),
        definitionSourceId: Id.SourceId(id: 0)
    )
    let token = Token(
        value: "100", kind: .IntegerLiteral(100),
        pos: Position(pos: 16, line: 2, col: 1, len: 3),
        id: Id.SourceId(id: 0), expansion: [site]
    )
    let notes = token.expansionNotes(in: context)
    try #require(notes.count == 1)
    #expect(notes[0].message == "in expansion of macro 'MAX'")
    #expect(notes[0].range.start.offset == 8)
    #expect(notes[0].range.start.line == 1)
}

func parseWithPreprocessor(_ source: String) -> [Diagnostic] {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexerResult = Lexer(input: stream).parse()
    let processed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig()
    )
    let parser = Parser(context: context, packageName: "main", processed)
    _ = parser.parse()
    return context.diagnositicEngine.diagnostics
}

@Test func ppParserErrorShowsExpansionNote() {
    let diagnostics = parseWithPreprocessor("#define BAD :\nlet x = [BAD 1]")
    #expect(
        diagnostics.contains {
            $0.notes.contains { $0.message == "in expansion of macro 'BAD'" }
        }
    )
}

@Test func ppPreprocessorErrorShowsExpansionNote() {
    let (_, diagnostics) = preprocessWithDiagnostics("#define DIV / 0\n#if 1 DIV")
    #expect(
        diagnostics.contains {
            $0.message.contains("division by zero")
                && $0.notes.contains { $0.message == "in expansion of macro 'DIV'" }
        }
    )
}

@Test func ppNestedExpansionNotes() {
    let (_, diagnostics) = preprocessWithDiagnostics("#define A B\n#define B / 0\n#if 1 A")
    let divError = diagnostics.first { $0.message.contains("division by zero") }
    #expect(divError?.notes.map(\.message) == [
        "in expansion of macro 'B'", "in expansion of macro 'A'",
    ])
}

@Test func ppMacroChainExpansionInFunction() {
    let source = """
    #define A B + 2
    #define B C * 3
    #define C D - 4
    #define D E / 5
    #define E A | 1
    func f() {
        A
    }
    """
    let tokens = preprocess(source)
    #expect(tokenValues(tokens) == [
        "func", "f", "(", ")", "{",
        "A", "|", "1", "/", "5", "-", "4", "*", "3", "+", "2",
        "}",
    ])
}

@Test func ppFunclikeChainInFunction() {
    let source = """
    #define funclike() add
    #define add(x, y) x + y
    func f() {
        funclike()(1, 2)
    }
    """
    let tokens = preprocess(source)
    #expect(tokenValues(tokens) == [
        "func", "f", "(", ")", "{",
        "1", "+", "2",
        "}",
    ])
}

@Test func ppDeferFamilyInFunction() {
    let source = """
    #define EMPTY()
    #define DEFER1(A) A
    #define DEFER2(A) AA EMPTY()
    #define AA() 123
    #define EXPAND(x) x
    func f() {
        DEFER1(AA)()
        DEFER2(AA)()
        EXPAND(DEFER2(AA)())
    }
    """
    let tokens = preprocess(source)
    #expect(tokenValues(tokens) == [
        "func", "f", "(", ")", "{",
        "123",
        "AA", "(", ")",
        "123",
        "}",
    ])
}
