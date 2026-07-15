public final class LexerResult {
    public let id: Id.SourceId
    public let tokens: [Token]
    public init(id: Id.SourceId, tokens: [Token]) {
        self.id = id
        self.tokens = tokens
    }
}
