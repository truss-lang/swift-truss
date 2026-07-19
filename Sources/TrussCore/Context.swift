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
    public private(set) var sourceTable: [Id.SourceId: Source] = [:]
    public let diagnositicEngine = DiagnosticEngine()

    public init() {}

    public func register(_ source: Source) {
        sourceTable[source.id] = source
    }
}
