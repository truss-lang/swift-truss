import Foundation
import SwiftBetterDiagnostic
import TrussCore
import TrussSemantics
import TrussSyntax

public struct DriverConfig {
    public var target: String
    public var defines: [String: String]
    public var dumpAST: Bool
    public var dumpSymbols: Bool
    public var dumpSource: Bool

    public init(
        target: String = "x86_64-unknown-linux-gnu",
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
        var programs: [AST.Program] = []
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                Self.emitReadError(file, context: context)
                continue
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
            let program = Parser(context: context, packageName: "main", preprocessed).parse()
            programs.append(program)
        }
        for program in programs {
            DeclCollector(context: context).visitProgram(program)
        }
        for program in programs {
            Enter(context: context).visitProgram(program)
        }
        let merger = MergePass(context: context)
        for program in programs {
            merger.visitProgram(program)
        }
        merger.resolvePending()
        for program in programs {
            NameResolver(context: context).visitProgram(program)
        }
        var stdout = ""
        if self.config.dumpAST {
            for program in programs {
                stdout += ASTDumper().dump(program) + "\n"
            }
        }
        if self.config.dumpSymbols, let first = programs.first {
            stdout += SymbolDumper().dump(first) + "\n"
        }
        if self.config.dumpSource {
            for program in programs {
                stdout += SourcePrinter().print(program) + "\n"
            }
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
