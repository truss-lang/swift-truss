import TrussDiagnosis

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
        self.charStream = CharStream(content: content, id: id)
        self.stringSourceBuffer = StringSourceBuffer(filePath: filepath, content: content)
    }
}

public final class Context {
    public let diagnositicEngine = DiagnosticEngine()
    public private(set) var sourceTable: [Id.SourceId: Source] = [:]
    public private(set) var id2Symbol: [Id.SymbolId: Symbol.Symbol] = [:]
    public private(set) var name2Package: [String: Symbol.PackageSymbol] = [:]
    public init() {}
    @discardableResult
    public func register(source: Source) -> Context {
        sourceTable[source.id] = source
        return self
    }
    @discardableResult
    public func register(symbol: Symbol.Symbol) -> Context {
        self.id2Symbol[symbol.id] = symbol
        return self
    }
    @discardableResult
    public func register(packageSymbol: Symbol.PackageSymbol) -> Context {
        self.name2Package[packageSymbol.name] = packageSymbol
        self.id2Symbol[packageSymbol.id] = packageSymbol
        return self
    }
    public var nextSymbolId: Id.SymbolId {
        Id.SymbolId(id: UInt64(self.id2Symbol.count))
    }
}
