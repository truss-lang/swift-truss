import SwiftBetterDiagnostic

public final class Context {
    public let diagnositicEngine = DiagnosticEngine(deduplicateOnEmit: true)
    public private(set) var sourceTable: [Id.SourceId: Source] = [:]
    public private(set) var id2Symbol: [Id.SymbolId: Symbol.Symbol] = [:]
    public private(set) var name2Package: [String: Symbol.PackageSymbol] = [:]
    public private(set) var typeTable: [Id.TypeId: TrussType.TrussType] = [:]
    public private(set) var allowedWarningRanges: [SourceRange] = []
    public init() {}
    @discardableResult
    public func register(source: Source) -> Context {
        sourceTable[source.id] = source
        return self
    }

    @discardableResult
    public func register(symbol: Symbol.Symbol) -> Context {
        id2Symbol[symbol.id] = symbol
        return self
    }

    @discardableResult
    public func register(packageSymbol: Symbol.PackageSymbol) -> Context {
        name2Package[packageSymbol.name] = packageSymbol
        id2Symbol[packageSymbol.id] = packageSymbol
        return self
    }

    @discardableResult
    public func register(type: TrussType.NominalType) -> Context {
        typeTable[type.id] = type
        return self
    }

    public var nextSourceId: Id.SourceId {
        Id.SourceId(id: UInt64(sourceTable.count))
    }

    public var nextSymbolId: Id.SymbolId {
        Id.SymbolId(id: UInt64(id2Symbol.count))
    }

    public var nextTypeId: Id.TypeId {
        Id.TypeId(id: UInt64(typeTable.count))
    }
}

public extension Context {
    func emitError(_ message: String, at range: SourceRange) {
        diagnositicEngine.emit(Diagnostic(severity: .error, message: message, range: range))
    }

    func emitError(_ message: String, at token: Token) {
        emitError(message, at: token, notes: [])
    }

    func emitError(_ message: String, at token: Token, notes: [Diagnostic]) {
        guard let source = sourceTable[token.id] else { return }
        diagnositicEngine.emit(
            Diagnostic(
                severity: .error, message: message,
                range: token.sourceRange(in: source.stringSourceBuffer),
                notes: notes + token.expansionNotes(in: self)
            )
        )
    }

    func emitWarning(_ message: String, at range: SourceRange) {
        diagnositicEngine.emit(Diagnostic(severity: .warning, message: message, range: range))
    }

    func emitWarning(_ message: String, at token: Token) {
        emitWarning(message, at: token, notes: [])
    }

    func emitWarning(_ message: String, at token: Token, notes: [Diagnostic]) {
        guard let source = sourceTable[token.id] else { return }
        diagnositicEngine.emit(
            Diagnostic(
                severity: .warning, message: message,
                range: token.sourceRange(in: source.stringSourceBuffer),
                notes: notes + token.expansionNotes(in: self)
            )
        )
    }
}

public extension Context {
    func allowWarning(in range: SourceRange) {
        allowedWarningRanges.append(range)
    }

    func isWarningAllowed(at range: SourceRange) -> Bool {
        allowedWarningRanges.contains { $0.start.offset <= range.start.offset && range.start.offset <= $0.end.offset }
    }

    func isWarningAllowed(at token: Token) -> Bool {
        guard let source = sourceTable[token.id] else { return false }
        return isWarningAllowed(at: token.sourceRange(in: source.stringSourceBuffer))
    }
}

public final class Source {
    public let id: Id.SourceId
    public let filepath: String
    public let content: String
    public let charStream: CharStream
    public let stringSourceBuffer: StringSourceBuffer
    public init(id: Id.SourceId, filepath: String, content: String) {
        self.id = id
        self.filepath = filepath
        self.content = content
        charStream = CharStream(content: content, id: id)
        stringSourceBuffer = StringSourceBuffer(filePath: filepath, content: content)
    }
}
