public struct TerminalRenderer: DiagnosticRenderer {
    public init() {}

    public func render(_ diagnostics: [Diagnostic]) -> String {
        diagnostics.map { renderSingle($0) }.joined(separator: "\n")
    }

    public func renderSingle(_ diag: Diagnostic) -> String {
        var output = ""
        let loc = diag.range.start
        let color = severityColor(diag.severity)

        output += colorize("\(loc.buffer.filePath):\(loc.line):\(loc.column): ", color: .cyan)
        output += colorize("\(diag.severity): ", color: color, bold: true)
        output += "\(diag.message)\n"

        output += renderSnippet(at: loc, range: diag.range, color: color)

        for span in diag.labeledSpans where !span.isPrimary {
            output += renderLabeledSpan(span)
        }

        for note in diag.notes {
            output += renderNote(note)
        }

        for suggestion in diag.suggestions {
            output += renderSuggestion(suggestion)
        }

        return output
    }

    public func renderSuggestion(_ suggestion: Suggestion) -> String {
        var output = ""
        let floc = suggestion.range.start
        output += colorize("\(floc.buffer.filePath):\(floc.line):\(floc.column): ", color: .cyan)
        output += colorize("help: ", color: .green, bold: true)
        if !suggestion.message.isEmpty {
            output += "\(suggestion.message)"
        } else {
            output += defaultSuggestionDescription(suggestion)
        }
        output += "\n"
        output += renderSnippet(at: floc, range: suggestion.range, color: .green)
        return output
    }

    private func defaultSuggestionDescription(_ suggestion: Suggestion) -> String {
        if suggestion.range.length == 0 {
            return "insert '\(suggestion.newText)'"
        }
        if suggestion.newText.isEmpty {
            return "delete \(suggestion.range.length) char(s)"
        }
        return "replace '\(suggestion.range.length)' chars with '\(suggestion.newText)'"
    }

    public func renderLabeledSpan(_ span: LabeledSpan) -> String {
        var output = ""
        output += colorize("  = ", color: .cyan)
        output += colorize("note: ", color: .cyan, bold: true)
        output += "\(span.label)\n"
        output += renderSnippet(at: span.range.start, range: span.range, color: .cyan)
        return output
    }

    public func renderNote(_ note: Diagnostic) -> String {
        var output = ""
        let color = severityColor(note.severity)
        output += colorize("  = ", color: .cyan)
        output += colorize("note: ", color: color, bold: true)
        output += "\(note.message)\n"
        output += renderSnippet(at: note.range.start, range: note.range, color: color)
        return output
    }

    private func renderSnippet(
        at loc: SourceLocation, range: SourceRange, color: ANSIColor
    ) -> String {
        var output = ""
        let lines = loc.buffer.content.split(separator: "\n", omittingEmptySubsequences: false)
        guard loc.line > 0 && loc.line <= lines.count else { return output }
        let lineContent = String(lines[loc.line - 1])
        let lineNumStr = "\(loc.line)"

        output += colorize(
            "\(String(repeating: " ", count: lineNumStr.count)) --> ", color: .cyan)
        output += "\(loc.buffer.filePath):\(loc.line):\(loc.column)\n"

        output += colorize("\(lineNumStr) | ", color: .cyan)
        output += "\(lineContent)\n"

        let indent = String(repeating: " ", count: lineNumStr.count + 1)
        output += colorize("\(indent)| ", color: .cyan)

        let prefixSpaces = String(repeating: " ", count: max(0, loc.column - 1))
        let squiggles = String(repeating: "~", count: max(1, range.length))
        output += colorize("\(prefixSpaces)\(squiggles)", color: color, bold: true)
        output += "\n"
        return output
    }

    private enum ANSIColor: String {
        case red = "\u{001B}[31m"
        case yellow = "\u{001B}[33m"
        case cyan = "\u{001B}[36m"
        case green = "\u{001B}[32m"
        case reset = "\u{001B}[0m"
        case bold = "\u{001B}[1m"
    }

    private func colorize(_ text: String, color: ANSIColor, bold: Bool = false) -> String {
        var result = color.rawValue
        if bold { result += ANSIColor.bold.rawValue }
        result += text + ANSIColor.reset.rawValue
        return result
    }

    private func severityColor(_ severity: DiagnosticSeverity) -> ANSIColor {
        switch severity {
        case .error, .fatal: return .red
        case .warning: return .yellow
        default: return .cyan
        }
    }
}
