import Testing
@testable import TrussDiagnosis

@Test func sourceLocationEqualitySameOffsetSameFile() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let loc1 = SourceLocation(buffer: buffer, offset: 2, line: 1, column: 3)
    let loc2 = SourceLocation(buffer: buffer, offset: 2, line: 1, column: 3)
    #expect(loc1 == loc2)
}

@Test func sourceLocationEqualityIgnoresLineAndColumn() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let loc1 = SourceLocation(buffer: buffer, offset: 2, line: 1, column: 3)
    let loc2 = SourceLocation(buffer: buffer, offset: 2, line: 99, column: 99)
    #expect(loc1 == loc2)
}

@Test func sourceLocationInequalityDifferentOffset() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let loc1 = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    let loc2 = SourceLocation(buffer: buffer, offset: 1, line: 1, column: 2)
    #expect(loc1 != loc2)
}

@Test func sourceLocationInequalityDifferentFile() {
    let buffer1 = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let buffer2 = StringSourceBuffer(fileName: "b.truss", content: "let x")
    let loc1 = SourceLocation(buffer: buffer1, offset: 0, line: 1, column: 1)
    let loc2 = SourceLocation(buffer: buffer2, offset: 0, line: 1, column: 1)
    #expect(loc1 != loc2)
}

@Test func sourceLocationEqualitySameFileNameDifferentBufferInstance() {
    let buffer1 = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let buffer2 = StringSourceBuffer(fileName: "a.truss", content: "different")
    let loc1 = SourceLocation(buffer: buffer1, offset: 1, line: 1, column: 2)
    let loc2 = SourceLocation(buffer: buffer2, offset: 1, line: 1, column: 2)
    #expect(loc1 == loc2)
}

@Test func sourceLocationStoresAllFields() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let loc = SourceLocation(buffer: buffer, offset: 3, line: 1, column: 4)
    #expect(loc.buffer.fileName == "a.truss")
    #expect(loc.offset == 3)
    #expect(loc.line == 1)
    #expect(loc.column == 4)
}

@Test func sourceLocationZeroOffset() {
    let buffer = StringSourceBuffer(fileName: "a.truss", content: "let x")
    let loc = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
    #expect(loc.offset == 0)
    #expect(loc.line == 1)
    #expect(loc.column == 1)
}
