public protocol DiagnosticRenderer {
    func render(_ diagnostics: [Diagnostic]) -> String
    func renderSingle(_ diag: Diagnostic) -> String
    func renderSuggestion(_ suggestion: Suggestion) -> String
    func renderLabeledSpan(_ span: LabeledSpan) -> String
    func renderNote(_ note: Diagnostic) -> String
}
