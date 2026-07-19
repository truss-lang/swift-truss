public struct SourceLocation: Equatable {
    public let buffer: SourceBuffer
    public let offset: Int
    public let line: Int
    public let column: Int

    public init(buffer: SourceBuffer, offset: Int, line: Int, column: Int) {
        self.buffer = buffer
        self.offset = offset
        self.line = line
        self.column = column
    }

    public static func == (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        return lhs.buffer.filePath == rhs.buffer.filePath && lhs.offset == rhs.offset
    }
}
