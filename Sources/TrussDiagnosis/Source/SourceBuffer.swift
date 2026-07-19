public protocol SourceBuffer {
    var filePath: String { get }
    var content: String { get }
}

public struct StringSourceBuffer: SourceBuffer {
    public let filePath: String
    public let content: String

    public init(filePath: String, content: String) {
        self.filePath = filePath
        self.content = content
    }
}
