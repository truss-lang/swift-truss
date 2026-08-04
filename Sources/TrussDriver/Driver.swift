import Foundation
import SwiftBetterDiagnostic
import TrussCore
import TrussSemantics
import TrussSyntax

public struct DriverConfig {
    public static let hostTarget: String = TargetTriple.host

    public var target: String
    public var defines: [String: String]
    public var dumpAST: Bool
    public var dumpSymbols: Bool
    public var dumpSource: Bool

    public init(
        target: String = DriverConfig.hostTarget,
        defines: [String: String] = [:],
        dumpAST: Bool = false,
        dumpSymbols: Bool = false,
        dumpSource: Bool = false
    ) {
        self.target = target
        self.defines = defines
        self.dumpAST = dumpAST
        self.dumpSymbols = dumpSymbols
        self.dumpSource = dumpSource
    }
}

public struct DriverResult {
    public let stdout: String
    public let stderr: String
    public let hasErrors: Bool
}

public final class Driver {
    private let config: DriverConfig

    public init(config: DriverConfig) {
        self.config = config
    }

    public func run(files: [String]) -> DriverResult {
        let context = Context()
        let programs = files.compactMap { file -> AST.Program? in
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                Self.emitReadError(file, context: context)
                return nil
            }
            let src = Source(id: context.nextSourceId, filepath: file, content: content)
            context.register(source: src)
            let lexerResult = Lexer(input: CharStream(content: content, id: src.id)).parse()
            let preprocessed = Preprocessor(context: context).process(
                lexerResult,
                config: PreprocessorConfig(
                    defines: self.config.defines,
                    target: self.config.target,
                    workingDirectory: (file as NSString).deletingLastPathComponent))
            return Parser(context: context, packageName: "main", preprocessed).parse()
        }
        programs.forEach { DeclCollector(context: context).visitProgram($0) }
        programs.forEach { Enter(context: context).visitProgram($0) }
        let merger = MergePass(context: context)
        programs.forEach { merger.visitProgram($0) }
        merger.resolvePending()
        programs.forEach { NameResolver(context: context).visitProgram($0) }
        var stdout = ""
        if self.config.dumpAST, !programs.isEmpty {
            stdout += programs.map { ASTDumper().dump($0) }.joined(separator: "\n") + "\n"
        }
        if self.config.dumpSymbols, let first = programs.first {
            stdout += SymbolDumper().dump(first) + "\n"
        }
        if self.config.dumpSource, !programs.isEmpty {
            stdout += programs.map { SourcePrinter().print($0) }.joined(separator: "\n") + "\n"
        }
        let hasErrors = context.diagnositicEngine.hasErrors
        var stderr = ""
        if hasErrors {
            stderr = TerminalRenderer(beforeLines: 1, afterLines: 1)
                .render(context.diagnositicEngine.diagnostics)
        }
        return DriverResult(stdout: stdout, stderr: stderr, hasErrors: hasErrors)
    }

    private static func emitReadError(_ file: String, context: Context) {
        let src = Source(id: context.nextSourceId, filepath: file, content: "")
        context.register(source: src)
        let buffer = src.stringSourceBuffer
        let location = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: .error, message: "could not read file '\(file)'",
                range: SourceRange(start: location, end: location)))
    }
}
