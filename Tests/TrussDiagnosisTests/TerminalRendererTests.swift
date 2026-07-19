import Foundation
import Testing

@testable import TrussDiagnosis

private func makeDiagnostic(
    severity: DiagnosticSeverity = .error,
    message: String = "missing semicolon",
    content: String = "let x\n",
    fileName: String = "test.truss",
    startOffset: Int = 5,
    endOffset: Int = 6,
    line: Int = 1,
    column: Int = 5,
    suggestions: [Suggestion] = []
) -> Diagnostic {
    let buffer = StringSourceBuffer(filePath: fileName, content: content)
    let start = SourceLocation(buffer: buffer, offset: startOffset, line: line, column: column)
    let end = SourceLocation(buffer: buffer, offset: endOffset, line: line, column: column + 1)
    let range = SourceRange(start: start, end: end)
    return Diagnostic(severity: severity, message: message, range: range, suggestions: suggestions)
}

@Test func rendererEmptyDiagnosticsReturnsEmptyString() {
    let renderer = TerminalRenderer()
    #expect(renderer.render([]) == "")
}

@Test func rendererIncludesFileName() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(fileName: "myfile.truss")])
    #expect(output.contains("myfile.truss"))
}

@Test func rendererIncludesLineAndColumn() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(line: 1, column: 5)])
    #expect(output.contains("1:5"))
}

@Test func rendererIncludesSeverity() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(severity: .error)])
    #expect(output.contains("error"))
}

@Test func rendererIncludesMessage() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(message: "unexpected token")])
    #expect(output.contains("unexpected token"))
}

@Test func rendererIncludesSourceLineContent() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(content: "let x = 1\n")])
    #expect(output.contains("let x = 1"))
}

@Test func rendererIncludesSquiggles() {
    let renderer = TerminalRenderer()
    let diag = makeDiagnostic(startOffset: 0, endOffset: 3, column: 1)
    let output = renderer.render([diag])
    #expect(output.contains("~~~"))
}

@Test func rendererSingleCharRangeProducesSingleSquiggle() {
    let renderer = TerminalRenderer()
    let diag = makeDiagnostic(startOffset: 0, endOffset: 1, column: 1)
    let output = renderer.render([diag])
    #expect(output.contains("~"))
}

@Test func rendererZeroLengthRangeProducesAtLeastOneSquiggle() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let range = SourceRange(start: start, end: end)
    let diag = Diagnostic(severity: .error, message: "m", range: range)
    let output = TerminalRenderer().render([diag])
    #expect(output.contains("~"))
}

@Test func rendererJoinsMultipleDiagnosticsWithNewline() {
    let renderer = TerminalRenderer()
    let output = renderer.render([
        makeDiagnostic(message: "first error"),
        makeDiagnostic(message: "second error"),
    ])
    #expect(output.contains("first error"))
    #expect(output.contains("second error"))
}

@Test func rendererIncludesSuggestionInformation() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let suggestion = Suggestion(range: range, newText: "var")
    let diag = makeDiagnostic(suggestions: [suggestion])
    let output = renderer.render([diag])
    #expect(output.contains("help:"))
    #expect(output.contains("var"))
}

@Test func rendererSuggestionShowsLength() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let suggestion = Suggestion(range: range, newText: "var")
    let diag = makeDiagnostic(suggestions: [suggestion])
    let output = renderer.render([diag])
    #expect(output.contains("3"))
}

@Test func rendererWarningSeverityUsesWarningLabel() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(severity: .warning)])
    #expect(output.contains("warning"))
}

@Test func rendererNoteSeverityUsesNoteLabel() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(severity: .note)])
    #expect(output.contains("note"))
}

@Test func rendererLineOutOfRangeSkipsSourceSnippet() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 99, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 1, line: 99, column: 2)
    let range = SourceRange(start: start, end: end)
    let diag = Diagnostic(severity: .error, message: "out of range", range: range)
    let output = renderer.render([diag])
    #expect(output.contains("out of range"))
    #expect(!output.contains(" | "))
}

@Test func rendererMultipleSuggestionsAllRendered() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let suggestion1 = Suggestion(range: range, newText: "var")
    let suggestion2 = Suggestion(range: range, newText: "const")
    let diag = makeDiagnostic(suggestions: [suggestion1, suggestion2])
    let output = renderer.render([diag])
    #expect(output.contains("var"))
    #expect(output.contains("const"))
}

@Test func rendererContainsANSIColorCodes() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic()])
    #expect(output.contains("\u{001B}[36m"))
    #expect(output.contains("\u{001B}[0m"))
}

@Test func rendererErrorUsesRedColor() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(severity: .error)])
    #expect(output.contains("\u{001B}[31m"))
}

@Test func rendererWarningUsesYellowColor() {
    let renderer = TerminalRenderer()
    let output = renderer.render([makeDiagnostic(severity: .warning)])
    #expect(output.contains("\u{001B}[33m"))
}

@Test func rendererRendersNoteMessage() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\n")
    let mainStart = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let mainEnd = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let mainRange = SourceRange(start: mainStart, end: mainEnd)
    let noteStart = SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1)
    let noteEnd = SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    let noteRange = SourceRange(start: noteStart, end: noteEnd)
    let note = Diagnostic(severity: .note, message: "previously defined here", range: noteRange)
    let diag = Diagnostic(
        severity: .error, message: "redefinition", range: mainRange, notes: [note]
    )
    let output = renderer.render([diag])
    #expect(output.contains("redefinition"))
    #expect(output.contains("previously defined here"))
    #expect(output.contains("note:"))
}

@Test func rendererNoteHasItsOwnArrowPointingToNoteLocation() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\n")
    let mainStart = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let mainEnd = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let mainRange = SourceRange(start: mainStart, end: mainEnd)
    let noteStart = SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1)
    let noteEnd = SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    let noteRange = SourceRange(start: noteStart, end: noteEnd)
    let note = Diagnostic(severity: .note, message: "see here", range: noteRange)
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, notes: [note]
    )
    let output = renderer.render([diag])
    #expect(output.contains("t.truss:2:1"))
    #expect(output.contains("let y"))
}

@Test func rendererNoteRendersSquigglesAtNotePosition() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\n")
    let mainStart = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let mainEnd = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let mainRange = SourceRange(start: mainStart, end: mainEnd)
    let noteStart = SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1)
    let noteEnd = SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    let noteRange = SourceRange(start: noteStart, end: noteEnd)
    let note = Diagnostic(severity: .note, message: "here", range: noteRange)
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, notes: [note]
    )
    let output = renderer.render([diag])
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 2)
}

@Test func rendererMultipleNotesEachGetArrow() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "a\nb\nc\nd\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 1, line: 1, column: 2)
    )
    let note1 = Diagnostic(
        severity: .note, message: "first",
        range: SourceRange(
            start: SourceLocation(buffer: buffer, offset: 2, line: 2, column: 1),
            end: SourceLocation(buffer: buffer, offset: 3, line: 2, column: 2)
        )
    )
    let note2 = Diagnostic(
        severity: .note, message: "second",
        range: SourceRange(
            start: SourceLocation(buffer: buffer, offset: 4, line: 3, column: 1),
            end: SourceLocation(buffer: buffer, offset: 5, line: 3, column: 2)
        )
    )
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, notes: [note1, note2]
    )
    let output = renderer.render([diag])
    #expect(output.contains("first"))
    #expect(output.contains("second"))
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 3)
}

@Test func rendererRendersLabeledSpanLabel() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let relatedRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1),
        end: SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    )
    let span = LabeledSpan(range: relatedRange, label: "defined here")
    let diag = Diagnostic(
        severity: .error, message: "conflict", range: mainRange, labeledSpans: [span]
    )
    let output = renderer.render([diag])
    #expect(output.contains("defined here"))
}

@Test func rendererLabeledSpanHasItsOwnArrow() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let relatedRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1),
        end: SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    )
    let span = LabeledSpan(range: relatedRange, label: "related point")
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, labeledSpans: [span]
    )
    let output = renderer.render([diag])
    #expect(output.contains("t.truss:2:1"))
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 2)
}

@Test func rendererLabeledSpanRendersSourceLine() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let relatedRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1),
        end: SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    )
    let span = LabeledSpan(range: relatedRange, label: "here")
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, labeledSpans: [span]
    )
    let output = renderer.render([diag])
    #expect(output.contains("let y"))
}

@Test func rendererPrimaryLabeledSpanNotDuplicatedAsRelated() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let span = LabeledSpan(range: mainRange, label: "primary", isPrimary: true)
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, labeledSpans: [span]
    )
    let output = renderer.render([diag])
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 1)
}

@Test func rendererCombinesNotesLabeledSpansAndSuggestions() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\nlet z\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let noteRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1),
        end: SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    )
    let spanRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 12, line: 3, column: 1),
        end: SourceLocation(buffer: buffer, offset: 15, line: 3, column: 4)
    )
    let note = Diagnostic(severity: .note, message: "see also", range: noteRange)
    let span = LabeledSpan(range: spanRange, label: "anchor")
    let suggestion = Suggestion(range: mainRange, newText: "var")
    let diag = Diagnostic(
        severity: .error, message: "complex", range: mainRange,
        notes: [note], suggestions: [suggestion], labeledSpans: [span]
    )
    let output = renderer.render([diag])
    #expect(output.contains("complex"))
    #expect(output.contains("see also"))
    #expect(output.contains("anchor"))
    #expect(output.contains("help:"))
    #expect(output.contains("var"))
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 4)
}

@Test func rendererNoteOutOfLineRangeSkipsSnippetOnly() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let noteRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 99, column: 1),
        end: SourceLocation(buffer: buffer, offset: 1, line: 99, column: 2)
    )
    let note = Diagnostic(severity: .note, message: "far", range: noteRange)
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, notes: [note]
    )
    let output = renderer.render([diag])
    #expect(output.contains("main"))
    #expect(output.contains("far"))
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 1)
}

@Test func rendererOutputDiagnosticsSortsBeforeRender() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "abcdefghij")
    let d1 = Diagnostic(
        severity: .error, message: "late",
        range: SourceRange(
            start: SourceLocation(buffer: buffer, offset: 8, line: 1, column: 9),
            end: SourceLocation(buffer: buffer, offset: 9, line: 1, column: 10)
        )
    )
    let d2 = Diagnostic(
        severity: .error, message: "early",
        range: SourceRange(
            start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
            end: SourceLocation(buffer: buffer, offset: 1, line: 1, column: 2)
        )
    )
    let engine = DiagnosticEngine()
    engine.emit(d1)
    engine.emit(d2)
    let output = renderer.render(engine.outputDiagnostics())
    let earlyRange = output.range(of: "early")
    let lateRange = output.range(of: "late")
    #expect(earlyRange != nil)
    #expect(lateRange != nil)
    #expect(earlyRange!.lowerBound < lateRange!.lowerBound)
}

@Test func rendererHelpUsesItsOwnRangeNotMainLocation() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let helpRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1),
        end: SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    )
    let suggestion = Suggestion(range: helpRange, newText: "var", message: "fix here")
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, suggestions: [suggestion]
    )
    let output = renderer.render([diag])
    #expect(output.contains("t.truss:2:1"))
    #expect(output.contains("let y"))
}

@Test func rendererHelpMessageShownWhenProvided() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let range = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let suggestion = Suggestion(range: range, newText: "var", message: "consider using var")
    let diag = Diagnostic(
        severity: .error, message: "main", range: range, suggestions: [suggestion]
    )
    let output = renderer.render([diag])
    #expect(output.contains("help:"))
    #expect(output.contains("consider using var"))
}

@Test func rendererHelpDefaultDescriptionForReplace() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let range = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let suggestion = Suggestion(range: range, newText: "var")
    let diag = Diagnostic(
        severity: .error, message: "main", range: range, suggestions: [suggestion]
    )
    let output = renderer.render([diag])
    #expect(output.contains("replace"))
    #expect(output.contains("3"))
    #expect(output.contains("var"))
}

@Test func rendererHelpDefaultDescriptionForInsert() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let range = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 5, line: 1, column: 6),
        end: SourceLocation(buffer: buffer, offset: 5, line: 1, column: 6)
    )
    let suggestion = Suggestion(range: range, newText: ";")
    let diag = Diagnostic(
        severity: .error, message: "main", range: range, suggestions: [suggestion]
    )
    let output = renderer.render([diag])
    #expect(output.contains("insert"))
    #expect(output.contains(";"))
    #expect(!output.contains("replace"))
}

@Test func rendererHelpDefaultDescriptionForDelete() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x;\n")
    let range = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 5, line: 1, column: 6),
        end: SourceLocation(buffer: buffer, offset: 6, line: 1, column: 7)
    )
    let suggestion = Suggestion(range: range, newText: "")
    let diag = Diagnostic(
        severity: .error, message: "main", range: range, suggestions: [suggestion]
    )
    let output = renderer.render([diag])
    #expect(output.contains("delete"))
    #expect(!output.contains("replace"))
}

@Test func rendererMultipleHelpsAtDifferentPositionsEachGetArrow() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\nlet y\nlet z\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let help1Range = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1),
        end: SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    )
    let help2Range = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 12, line: 3, column: 1),
        end: SourceLocation(buffer: buffer, offset: 15, line: 3, column: 4)
    )
    let suggestion1 = Suggestion(range: help1Range, newText: "var", message: "option A")
    let suggestion2 = Suggestion(range: help2Range, newText: "const", message: "option B")
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange,
        suggestions: [suggestion1, suggestion2]
    )
    let output = renderer.render([diag])
    #expect(output.contains("option A"))
    #expect(output.contains("option B"))
    #expect(output.contains("t.truss:2:1"))
    #expect(output.contains("t.truss:3:1"))
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 3)
}

@Test func rendererHelpRendersGreenSnippet() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let range = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let suggestion = Suggestion(range: range, newText: "var")
    let diag = Diagnostic(
        severity: .error, message: "main", range: range, suggestions: [suggestion]
    )
    let output = renderer.render([diag])
    #expect(output.contains("\u{001B}[32m"))
    #expect(output.contains("~~~"))
}

@Test func rendererHelpOutOfLineRangeSkipsSnippetOnly() {
    let renderer = TerminalRenderer()
    let buffer = StringSourceBuffer(filePath: "t.truss", content: "let x\n")
    let mainRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let helpRange = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 99, column: 1),
        end: SourceLocation(buffer: buffer, offset: 1, line: 99, column: 2)
    )
    let suggestion = Suggestion(range: helpRange, newText: "var", message: "far help")
    let diag = Diagnostic(
        severity: .error, message: "main", range: mainRange, suggestions: [suggestion]
    )
    let output = renderer.render([diag])
    #expect(output.contains("main"))
    #expect(output.contains("far help"))
    let arrowOccurrences = output.components(separatedBy: " --> ").count - 1
    #expect(arrowOccurrences == 1)
}
