public enum Id {
    public struct SourceId: Hashable, Sendable, Equatable {
        public let id: UInt64
        public init(id: UInt64) {
            self.id = id
        }
    }
}
