import Testing
@testable import TrussDiagnosis

@Test func converterSingleLineOffsetZero() {
    let converter = LocationConverter(source: "hello")
    let (line, column) = converter.lineAndColumn(for: 0)
    #expect(line == 1)
    #expect(column == 1)
}

@Test func converterSingleLineLastOffset() {
    let converter = LocationConverter(source: "hello")
    let (line, column) = converter.lineAndColumn(for: 5)
    #expect(line == 1)
    #expect(column == 6)
}

@Test func converterSingleLineMiddleOffset() {
    let converter = LocationConverter(source: "hello")
    let (line, column) = converter.lineAndColumn(for: 2)
    #expect(line == 1)
    #expect(column == 3)
}

@Test func converterEmptySourceOffsetZero() {
    let converter = LocationConverter(source: "")
    let (line, column) = converter.lineAndColumn(for: 0)
    #expect(line == 1)
    #expect(column == 1)
}

@Test func converterTwoLinesStartOfSecondLine() {
    let converter = LocationConverter(source: "ab\ncd")
    let (line, column) = converter.lineAndColumn(for: 3)
    #expect(line == 2)
    #expect(column == 1)
}

@Test func converterTwoLinesEndOfFirstLine() {
    let converter = LocationConverter(source: "ab\ncd")
    let (line, column) = converter.lineAndColumn(for: 2)
    #expect(line == 1)
    #expect(column == 3)
}

@Test func converterTwoLinesAtNewline() {
    let converter = LocationConverter(source: "ab\ncd")
    let (line, column) = converter.lineAndColumn(for: 1)
    #expect(line == 1)
    #expect(column == 2)
}

@Test func converterMultipleLines() {
    let converter = LocationConverter(source: "a\nb\nc\nd")
    let (line1, col1) = converter.lineAndColumn(for: 0)
    #expect(line1 == 1)
    #expect(col1 == 1)

    let (line2, col2) = converter.lineAndColumn(for: 2)
    #expect(line2 == 2)
    #expect(col2 == 1)

    let (line3, col3) = converter.lineAndColumn(for: 4)
    #expect(line3 == 3)
    #expect(col3 == 1)

    let (line4, col4) = converter.lineAndColumn(for: 6)
    #expect(line4 == 4)
    #expect(col4 == 1)
}

@Test func converterSourceEndingWithNewline() {
    let converter = LocationConverter(source: "ab\n")
    let (line, column) = converter.lineAndColumn(for: 3)
    #expect(line == 2)
    #expect(column == 1)
}

@Test func converterConsecutiveNewlines() {
    let converter = LocationConverter(source: "a\n\nb")
    let (line2, col2) = converter.lineAndColumn(for: 2)
    #expect(line2 == 2)
    #expect(col2 == 1)

    let (line3, col3) = converter.lineAndColumn(for: 3)
    #expect(line3 == 3)
    #expect(col3 == 1)
}

@Test func converterOnlyNewlines() {
    let converter = LocationConverter(source: "\n\n\n")
    let (line1, col1) = converter.lineAndColumn(for: 0)
    #expect(line1 == 1)
    #expect(col1 == 1)

    let (line2, col2) = converter.lineAndColumn(for: 1)
    #expect(line2 == 2)
    #expect(col2 == 1)

    let (line4, col4) = converter.lineAndColumn(for: 3)
    #expect(line4 == 4)
    #expect(col4 == 1)
}

@Test func converterUtf8OffsetWithMultibyteChar() {
    let converter = LocationConverter(source: "你好")
    let (line, column) = converter.lineAndColumn(for: 3)
    #expect(line == 1)
    #expect(column == 4)
}
