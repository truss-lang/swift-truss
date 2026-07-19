public struct SourceRange: Equatable {
    public let start: SourceLocation
    public let end: SourceLocation
    public var length: Int {
        end.offset - start.offset
    }
    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }
}
