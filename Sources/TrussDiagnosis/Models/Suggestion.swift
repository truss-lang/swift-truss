public struct Suggestion {
    public let range: SourceRange
    public let newText: String
    public let message: String

    public init(range: SourceRange, newText: String, message: String = "") {
        self.range = range
        self.newText = newText
        self.message = message
    }
}
