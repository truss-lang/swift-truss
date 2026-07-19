import Testing
@testable import TrussDiagnosis

@Test func stringSourceBufferStoresFileNameAndContent() {
    let buffer = StringSourceBuffer(fileName: "test.truss", content: "let x = 1")
    #expect(buffer.fileName == "test.truss")
    #expect(buffer.content == "let x = 1")
}

@Test func stringSourceBufferEmptyContent() {
    let buffer = StringSourceBuffer(fileName: "empty.truss", content: "")
    #expect(buffer.fileName == "empty.truss")
    #expect(buffer.content == "")
}

@Test func stringSourceBufferMultilineContent() {
    let content = "line1\nline2\nline3\n"
    let buffer = StringSourceBuffer(fileName: "multi.truss", content: content)
    #expect(buffer.content == content)
    #expect(buffer.fileName == "multi.truss")
}

@Test func stringSourceBufferConformsToProtocol() {
    let buffer: SourceBuffer = StringSourceBuffer(fileName: "p.truss", content: "x")
    #expect(buffer.fileName == "p.truss")
    #expect(buffer.content == "x")
}

@Test func stringSourceBufferWithUnicodeContent() {
    let buffer = StringSourceBuffer(fileName: "u.truss", content: "let x = \"你好\"")
    #expect(buffer.content == "let x = \"你好\"")
}
