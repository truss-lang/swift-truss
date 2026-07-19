public enum DiagnosticSeverity: Int, Comparable {
    case note, remark, warning, error, fatal
    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Diagnostic {
    public let severity: DiagnosticSeverity
    public let message: String
    public let range: SourceRange
    public var notes: [Diagnostic]
    public var suggestions: [Suggestion]
    public var labeledSpans: [LabeledSpan]

    public init(
        severity: DiagnosticSeverity,
        message: String,
        range: SourceRange,
        notes: [Diagnostic] = [],
        suggestions: [Suggestion] = [],
        labeledSpans: [LabeledSpan] = []
    ) {
        self.severity = severity
        self.message = message
        self.range = range
        self.notes = notes
        self.suggestions = suggestions
        self.labeledSpans = labeledSpans
    }
}
