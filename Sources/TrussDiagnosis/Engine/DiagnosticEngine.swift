public final class DiagnosticEngine {
    public private(set) var diagnostics: [Diagnostic] = []
    public var errorLimit: Int?
    public var deduplicateOnEmit: Bool
    public private(set) var reachedErrorLimit: Bool = false

    public init(deduplicateOnEmit: Bool = false, errorLimit: Int? = nil) {
        self.deduplicateOnEmit = deduplicateOnEmit
        self.errorLimit = errorLimit
    }

    public func emit(_ diagnostic: Diagnostic) {
        if deduplicateOnEmit, isDuplicate(diagnostic) { return }
        diagnostics.append(diagnostic)
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity >= .error }
    }

    public func sortedDiagnostics() -> [Diagnostic] {
        diagnostics.sorted { lhs, rhs in
            let lfn = lhs.range.start.buffer.fileName
            let rfn = rhs.range.start.buffer.fileName
            if lfn != rfn { return lfn < rfn }
            return lhs.range.start.offset < rhs.range.start.offset
        }
    }

    public func deduplicated() -> [Diagnostic] {
        var seen: Set<String> = []
        var result: [Diagnostic] = []
        for d in diagnostics {
            if seen.insert(dedupKey(d)).inserted {
                result.append(d)
            }
        }
        return result
    }

    public func outputDiagnostics() -> [Diagnostic] {
        var diags = deduplicated()
        diags.sort { lhs, rhs in
            let lfn = lhs.range.start.buffer.fileName
            let rfn = rhs.range.start.buffer.fileName
            if lfn != rfn { return lfn < rfn }
            return lhs.range.start.offset < rhs.range.start.offset
        }

        guard let limit = errorLimit else { return diags }

        var kept: [Diagnostic] = []
        var errorCount = 0
        reachedErrorLimit = false
        for d in diags {
            if d.severity >= .error {
                if errorCount >= limit {
                    reachedErrorLimit = true
                    continue
                }
                errorCount += 1
            }
            kept.append(d)
        }
        return kept
    }

    public func reset() {
        diagnostics.removeAll()
        reachedErrorLimit = false
    }

    private func isDuplicate(_ d: Diagnostic) -> Bool {
        diagnostics.contains { existing in
            dedupKey(existing) == dedupKey(d)
        }
    }

    private func dedupKey(_ d: Diagnostic) -> String {
        "\(d.range.start.buffer.fileName)|\(d.range.start.offset)|\(d.severity.rawValue)|\(d.message)"
    }
}
