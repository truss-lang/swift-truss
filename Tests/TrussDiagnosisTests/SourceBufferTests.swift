import Testing

@testable import TrussDiagnosis

@Test func stringSourceBufferStoresFileNameAndContent() {
    let buffer = StringSourceBuffer(filePath: "test.truss", content: "let x = 1")
    #expect(buffer.filePath == "test.truss")
    #expect(buffer.content == "let x = 1")
}

@Test func stringSourceBufferEmptyContent() {
    let buffer = StringSourceBuffer(filePath: "empty.truss", content: "")
    #expect(buffer.filePath == "empty.truss")
    #expect(buffer.content == "")
}

@Test func stringSourceBufferMultilineContent() {
    let content = "line1\nline2\nline3\n"
    let buffer = StringSourceBuffer(filePath: "multi.truss", content: content)
    #expect(buffer.content == content)
    #expect(buffer.filePath == "multi.truss")
}

@Test func stringSourceBufferConformsToProtocol() {
    let buffer: SourceBuffer = StringSourceBuffer(filePath: "p.truss", content: "x")
    #expect(buffer.filePath == "p.truss")
    #expect(buffer.content == "x")
}

@Test func stringSourceBufferWithUnicodeContent() {
    let buffer = StringSourceBuffer(filePath: "u.truss", content: "let x = \"你好\"")
    #expect(buffer.content == "let x = \"你好\"")
}
