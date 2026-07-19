public protocol SourceBuffer {
    var fileName: String { get }
    var content: String { get }
}

public struct StringSourceBuffer: SourceBuffer {
    public let fileName: String
    public let content: String

    public init(fileName: String, content: String) {
        self.fileName = fileName
        self.content = content
    }
}
