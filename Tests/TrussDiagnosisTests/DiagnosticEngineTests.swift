import Testing

@testable import TrussDiagnosis

private func makeDiagnostic(_ severity: DiagnosticSeverity) -> Diagnostic {
    let buffer = StringSourceBuffer(filePath: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    return Diagnostic(severity: severity, message: "msg", range: range)
}

@Test func engineStartsEmpty() {
    let engine = DiagnosticEngine()
    #expect(engine.diagnostics.isEmpty)
    #expect(engine.hasErrors == false)
}

@Test func engineEmitAppendsDiagnostic() {
    let engine = DiagnosticEngine()
    let diag = makeDiagnostic(.warning)
    engine.emit(diag)
    #expect(engine.diagnostics.count == 1)
    #expect(engine.diagnostics[0].message == "msg")
}

@Test func engineEmitPreservesOrder() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.note))
    engine.emit(makeDiagnostic(.warning))
    engine.emit(makeDiagnostic(.error))
    #expect(engine.diagnostics.count == 3)
    #expect(engine.diagnostics[0].severity == .note)
    #expect(engine.diagnostics[1].severity == .warning)
    #expect(engine.diagnostics[2].severity == .error)
}

@Test func engineHasErrorsFalseForNoteOnly() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.note))
    #expect(engine.hasErrors == false)
}

@Test func engineHasErrorsFalseForRemarkOnly() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.remark))
    #expect(engine.hasErrors == false)
}

@Test func engineHasErrorsFalseForWarningOnly() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.warning))
    #expect(engine.hasErrors == false)
}

@Test func engineHasErrorsTrueForError() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.error))
    #expect(engine.hasErrors == true)
}

@Test func engineHasErrorsTrueForFatal() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.fatal))
    #expect(engine.hasErrors == true)
}

@Test func engineHasErrorsTrueWhenErrorMixedWithOthers() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.note))
    engine.emit(makeDiagnostic(.warning))
    engine.emit(makeDiagnostic(.error))
    #expect(engine.hasErrors == true)
}

@Test func engineHasErrorsTrueWhenFatalMixedWithOthers() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.note))
    engine.emit(makeDiagnostic(.fatal))
    #expect(engine.hasErrors == true)
}

@Test func engineHasErrorsFalseWhenOnlyNotesAndWarnings() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnostic(.note))
    engine.emit(makeDiagnostic(.remark))
    engine.emit(makeDiagnostic(.warning))
    #expect(engine.hasErrors == false)
}

@Test func engineMultipleInstancesAreIndependent() {
    let engine1 = DiagnosticEngine()
    let engine2 = DiagnosticEngine()
    engine1.emit(makeDiagnostic(.error))
    #expect(engine1.diagnostics.count == 1)
    #expect(engine2.diagnostics.isEmpty)
    #expect(engine1.hasErrors == true)
    #expect(engine2.hasErrors == false)
}

private func makeDiagnosticAt(
    _ severity: DiagnosticSeverity,
    _ fileName: String,
    _ offset: Int,
    line: Int = 1,
    column: Int = 1,
    message: String = "msg"
) -> Diagnostic {
    let buffer = StringSourceBuffer(
        filePath: fileName, content: String(repeating: "x", count: max(offset + 1, 1)))
    let start = SourceLocation(buffer: buffer, offset: offset, line: line, column: column)
    let end = SourceLocation(buffer: buffer, offset: offset + 1, line: line, column: column + 1)
    let range = SourceRange(start: start, end: end)
    return Diagnostic(severity: severity, message: message, range: range)
}

@Test func engineSortedDiagnosticsByOffsetSameFile() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 10, message: "third"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2, message: "first"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 7, message: "second"))
    let sorted = engine.sortedDiagnostics()
    #expect(sorted[0].message == "first")
    #expect(sorted[1].message == "second")
    #expect(sorted[2].message == "third")
}

@Test func engineSortedDiagnosticsByFileNameFirst() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "z.truss", 0))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 99))
    engine.emit(makeDiagnosticAt(.error, "m.truss", 5))
    let sorted = engine.sortedDiagnostics()
    #expect(sorted[0].range.start.buffer.filePath == "a.truss")
    #expect(sorted[1].range.start.buffer.filePath == "m.truss")
    #expect(sorted[2].range.start.buffer.filePath == "z.truss")
}

@Test func engineSortedDoesNotMutateStoredOrder() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 10))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2))
    _ = engine.sortedDiagnostics()
    #expect(engine.diagnostics[0].range.start.offset == 10)
    #expect(engine.diagnostics[1].range.start.offset == 2)
}

@Test func engineDeduplicatedRemovesExactDuplicates() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "dup"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "dup"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "dup"))
    #expect(engine.deduplicated().count == 1)
}

@Test func engineDeduplicatedKeepsDistinctMessages() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "one"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "two"))
    #expect(engine.deduplicated().count == 2)
}

@Test func engineDeduplicatedKeepsDistinctOffsets() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 6))
    #expect(engine.deduplicated().count == 2)
}

@Test func engineDeduplicatedKeepsDistinctSeverities() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "m"))
    engine.emit(makeDiagnosticAt(.warning, "a.truss", 5, message: "m"))
    #expect(engine.deduplicated().count == 2)
}

@Test func engineDeduplicatedKeepsDistinctFiles() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "m"))
    engine.emit(makeDiagnosticAt(.error, "b.truss", 5, message: "m"))
    #expect(engine.deduplicated().count == 2)
}

@Test func engineDeduplicateOnEmitSuppressesAtEmitTime() {
    let engine = DiagnosticEngine(deduplicateOnEmit: true)
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "dup"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "dup"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 6, message: "other"))
    #expect(engine.diagnostics.count == 2)
}

@Test func engineDeduplicateOnEmitOffByDefault() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "dup"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 5, message: "dup"))
    #expect(engine.diagnostics.count == 2)
}

@Test func engineOutputDiagnosticsSortsAndDeduplicates() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 10, message: "third"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2, message: "first"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 10, message: "third"))
    let output = engine.outputDiagnostics()
    #expect(output.count == 2)
    #expect(output[0].message == "first")
    #expect(output[1].message == "third")
}

@Test func engineErrorLimitTruncatesErrorsOnly() {
    let engine = DiagnosticEngine(errorLimit: 2)
    engine.emit(makeDiagnosticAt(.error, "a.truss", 1, message: "e1"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2, message: "e2"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 3, message: "e3"))
    let output = engine.outputDiagnostics()
    #expect(output.count == 2)
    #expect(output[0].message == "e1")
    #expect(output[1].message == "e2")
    #expect(engine.reachedErrorLimit == true)
}

@Test func engineErrorLimitKeepsNonErrorsBeyondLimit() {
    let engine = DiagnosticEngine(errorLimit: 1)
    engine.emit(makeDiagnosticAt(.error, "a.truss", 1, message: "e1"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2, message: "e2"))
    engine.emit(makeDiagnosticAt(.warning, "a.truss", 3, message: "w1"))
    engine.emit(makeDiagnosticAt(.note, "a.truss", 4, message: "n1"))
    let output = engine.outputDiagnostics()
    let messages = output.map(\.message)
    #expect(messages.contains("e1"))
    #expect(!messages.contains("e2"))
    #expect(messages.contains("w1"))
    #expect(messages.contains("n1"))
    #expect(engine.reachedErrorLimit == true)
}

@Test func engineErrorLimitNotReachedStaysFalse() {
    let engine = DiagnosticEngine(errorLimit: 5)
    engine.emit(makeDiagnosticAt(.error, "a.truss", 1, message: "e1"))
    _ = engine.outputDiagnostics()
    #expect(engine.reachedErrorLimit == false)
}

@Test func engineNoErrorLimitReturnsAll() {
    let engine = DiagnosticEngine(errorLimit: nil)
    engine.emit(makeDiagnosticAt(.error, "a.truss", 1, message: "e1"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2, message: "e2"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 3, message: "e3"))
    let output = engine.outputDiagnostics()
    #expect(output.count == 3)
    #expect(engine.reachedErrorLimit == false)
}

@Test func engineResetClearsDiagnostics() {
    let engine = DiagnosticEngine()
    engine.emit(makeDiagnosticAt(.error, "a.truss", 1))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2))
    #expect(engine.diagnostics.count == 2)
    engine.reset()
    #expect(engine.diagnostics.isEmpty)
    #expect(engine.hasErrors == false)
}

@Test func engineResetClearsReachedErrorLimit() {
    let engine = DiagnosticEngine(errorLimit: 1)
    engine.emit(makeDiagnosticAt(.error, "a.truss", 1))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2))
    _ = engine.outputDiagnostics()
    #expect(engine.reachedErrorLimit == true)
    engine.reset()
    #expect(engine.reachedErrorLimit == false)
}

@Test func engineFatalCountsAsErrorForLimit() {
    let engine = DiagnosticEngine(errorLimit: 1)
    engine.emit(makeDiagnosticAt(.fatal, "a.truss", 1, message: "f"))
    engine.emit(makeDiagnosticAt(.error, "a.truss", 2, message: "e"))
    let output = engine.outputDiagnostics()
    #expect(output.count == 1)
    #expect(engine.reachedErrorLimit == true)
}
