public struct LabeledSpan {
    public let range: SourceRange
    public let label: String
    public let isPrimary: Bool

    public init(range: SourceRange, label: String, isPrimary: Bool = false) {
        self.range = range
        self.label = label
        self.isPrimary = isPrimary
    }
}
