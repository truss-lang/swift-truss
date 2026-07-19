import Testing
@testable import TrussDiagnosis

@Test func severityOrderingNoteLeastSevere() {
    #expect(DiagnosticSeverity.note < .remark)
    #expect(DiagnosticSeverity.remark < .warning)
    #expect(DiagnosticSeverity.warning < .error)
    #expect(DiagnosticSeverity.error < .fatal)
}

@Test func severityOrderingNoteIsLeast() {
    #expect(DiagnosticSeverity.note <= .note)
    #expect(DiagnosticSeverity.note < .fatal)
}

@Test func severityOrderingFatalIsGreatest() {
    #expect(DiagnosticSeverity.fatal > .error)
    #expect(DiagnosticSeverity.fatal > .note)
    #expect(DiagnosticSeverity.fatal >= .fatal)
}

@Test func severityEquality() {
    #expect(DiagnosticSeverity.error == .error)
    #expect(DiagnosticSeverity.error != .warning)
}

@Test func severityRawValues() {
    #expect(DiagnosticSeverity.note.rawValue == 0)
    #expect(DiagnosticSeverity.remark.rawValue == 1)
    #expect(DiagnosticSeverity.warning.rawValue == 2)
    #expect(DiagnosticSeverity.error.rawValue == 3)
    #expect(DiagnosticSeverity.fatal.rawValue == 4)
}

@Test func suggestionStoresRangeAndNewText() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let suggestion = Suggestion(range: range, newText: "var")
    #expect(suggestion.range == range)
    #expect(suggestion.newText == "var")
}

@Test func suggestionWithEmptyReplacement() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let end = SourceLocation(buffer: buffer, offset: 4, line: 1, column: 5)
    let range = SourceRange(start: start, end: end)
    let suggestion = Suggestion(range: range, newText: "")
    #expect(suggestion.newText == "")
    #expect(suggestion.range.length == 1)
}

@Test func diagnosticStoresAllFields() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let diag = Diagnostic(severity: .error, message: "oops", range: range)
    #expect(diag.severity == .error)
    #expect(diag.message == "oops")
    #expect(diag.range == range)
    #expect(diag.notes.isEmpty)
    #expect(diag.suggestions.isEmpty)
}

@Test func diagnosticWithNotesAndSuggestions() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let note = Diagnostic(severity: .note, message: "see also", range: range)
    let suggestion = Suggestion(range: range, newText: "var")
    let diag = Diagnostic(
        severity: .warning, message: "suspicious", range: range,
        notes: [note], suggestions: [suggestion]
    )
    #expect(diag.notes.count == 1)
    #expect(diag.notes[0].message == "see also")
    #expect(diag.suggestions.count == 1)
    #expect(diag.suggestions[0].newText == "var")
}

@Test func diagnosticSeverityVariants() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 1, line: 1, column: 2)
    let range = SourceRange(start: start, end: end)
    #expect(Diagnostic(severity: .note, message: "", range: range).severity == .note)
    #expect(Diagnostic(severity: .remark, message: "", range: range).severity == .remark)
    #expect(Diagnostic(severity: .warning, message: "", range: range).severity == .warning)
    #expect(Diagnostic(severity: .error, message: "", range: range).severity == .error)
    #expect(Diagnostic(severity: .fatal, message: "", range: range).severity == .fatal)
}

@Test func labeledSpanStoresAllFields() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let span = LabeledSpan(range: range, label: "defined here", isPrimary: true)
    #expect(span.range == range)
    #expect(span.label == "defined here")
    #expect(span.isPrimary == true)
}

@Test func labeledSpanDefaultsToNonPrimary() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let span = LabeledSpan(range: range, label: "related")
    #expect(span.isPrimary == false)
}

@Test func diagnosticLabeledSpansDefaultsEmpty() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let diag = Diagnostic(severity: .error, message: "m", range: range)
    #expect(diag.labeledSpans.isEmpty)
}

@Test func diagnosticStoresLabeledSpans() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x\nlet y\n")
    let s1 = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let e1 = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let r1 = SourceRange(start: s1, end: e1)
    let s2 = SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1)
    let e2 = SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    let r2 = SourceRange(start: s2, end: e2)
    let span1 = LabeledSpan(range: r1, label: "first use")
    let span2 = LabeledSpan(range: r2, label: "defined here", isPrimary: true)
    let diag = Diagnostic(
        severity: .error, message: "conflict", range: r1,
        labeledSpans: [span1, span2]
    )
    #expect(diag.labeledSpans.count == 2)
    #expect(diag.labeledSpans[0].label == "first use")
    #expect(diag.labeledSpans[1].isPrimary == true)
}

@Test func diagnosticInitBackwardCompatible() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let note = Diagnostic(severity: .note, message: "n", range: range)
    let suggestion = Suggestion(range: range, newText: "var")
    let diag = Diagnostic(
        severity: .warning, message: "m", range: range,
        notes: [note], suggestions: [suggestion]
    )
    #expect(diag.notes.count == 1)
    #expect(diag.suggestions.count == 1)
    #expect(diag.labeledSpans.isEmpty)
}

@Test func suggestionDefaultsMessageToEmpty() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let suggestion = Suggestion(range: range, newText: "var")
    #expect(suggestion.message == "")
}

@Test func suggestionStoresMessage() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    let suggestion = Suggestion(range: range, newText: "var", message: "use var instead")
    #expect(suggestion.message == "use var instead")
    #expect(suggestion.newText == "var")
    #expect(suggestion.range == range)
}

@Test func diagnosticStoresMultipleSuggestions() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x\nlet y\n")
    let r1 = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1),
        end: SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    )
    let r2 = SourceRange(
        start: SourceLocation(buffer: buffer, offset: 6, line: 2, column: 1),
        end: SourceLocation(buffer: buffer, offset: 9, line: 2, column: 4)
    )
    let suggestion1 = Suggestion(range: r1, newText: "var", message: "first")
    let suggestion2 = Suggestion(range: r2, newText: "const", message: "second")
    let diag = Diagnostic(
        severity: .error, message: "m", range: r1, suggestions: [suggestion1, suggestion2]
    )
    #expect(diag.suggestions.count == 2)
    #expect(diag.suggestions[0].message == "first")
    #expect(diag.suggestions[1].message == "second")
    #expect(diag.suggestions[1].newText == "const")
}
