import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSyntax

func preprocessWithDiagnostics(
    _ source: String, flags: Set<String> = []
) -> ([Token], [Diagnostic]) {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexer = Lexer(input: stream)
    let tokens = lexer.parse().tokens
    let result = Preprocessor(context: context).process(
        tokens, config: PreprocessorConfig(flags: flags))
    return (result, context.diagnositicEngine.diagnostics)
}

func preprocess(_ source: String, flags: Set<String> = []) -> [Token] {
    preprocessWithDiagnostics(source, flags: flags).0
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
