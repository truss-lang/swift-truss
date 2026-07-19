import Testing
@testable import TrussDiagnosis

@Test func sourceRangeLengthZeroWidth() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 2, line: 1, column: 3)
    let end = SourceLocation(buffer: buffer, offset: 2, line: 1, column: 3)
    let range = SourceRange(start: start, end: end)
    #expect(range.length == 0)
}

@Test func sourceRangeLengthSingleChar() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 1, line: 1, column: 2)
    let range = SourceRange(start: start, end: end)
    #expect(range.length == 1)
}

@Test func sourceRangeLengthMultiChar() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range = SourceRange(start: start, end: end)
    #expect(range.length == 3)
}

@Test func sourceRangeEqualitySameOffsets() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start1 = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end1 = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let start2 = SourceLocation(buffer: buffer, offset: 0, line: 9, column: 9)
    let end2 = SourceLocation(buffer: buffer, offset: 3, line: 9, column: 9)
    let range1 = SourceRange(start: start1, end: end1)
    let range2 = SourceRange(start: start2, end: end2)
    #expect(range1 == range2)
}

@Test func sourceRangeInequalityDifferentStart() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start1 = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let start2 = SourceLocation(buffer: buffer, offset: 1, line: 1, column: 2)
    let end = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range1 = SourceRange(start: start1, end: end)
    let range2 = SourceRange(start: start2, end: end)
    #expect(range1 != range2)
}

@Test func sourceRangeInequalityDifferentEnd() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let end1 = SourceLocation(buffer: buffer, offset: 2, line: 1, column: 3)
    let end2 = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    let range1 = SourceRange(start: start, end: end1)
    let range2 = SourceRange(start: start, end: end2)
    #expect(range1 != range2)
}

@Test func sourceRangeExposesStartAndEnd() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let start = SourceLocation(buffer: buffer, offset: 1, line: 1, column: 2)
    let end = SourceLocation(buffer: buffer, offset: 4, line: 1, column: 5)
    let range = SourceRange(start: start, end: end)
    #expect(range.start.offset == 1)
    #expect(range.end.offset == 4)
}
