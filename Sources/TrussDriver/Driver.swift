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
        var programs: [AST.Program] = []
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                Self.emitReadError(file, context: context)
                break
            }
            let src = Source(id: context.nextSourceId, filepath: file, content: content)
            context.register(source: src)
            let lexerResult = Lexer(input: CharStream(content: content, id: src.id)).parse()
            let preprocessed = Preprocessor(context: context).process(
                lexerResult,
                config: PreprocessorConfig(
                    defines: config.defines,
                    target: config.target,
                    workingDirectory: (file as NSString).deletingLastPathComponent
                )
            )
            programs.append(Parser(context: context, packageName: "main", preprocessed).parse())
            if context.diagnositicEngine.hasErrors {
                break
            }
        }
        if !context.diagnositicEngine.hasErrors {
            runPass(DeclCollector(context: context), context: context, programs: programs)
        }
        if !context.diagnositicEngine.hasErrors {
            runPass(Enter(context: context), context: context, programs: programs)
        }
        if !context.diagnositicEngine.hasErrors {
            let merger = MergePass(context: context)
            runPass(merger, context: context, programs: programs)
            if !context.diagnositicEngine.hasErrors {
                merger.resolvePending()
            }
        }
        if !context.diagnositicEngine.hasErrors {
            runPass(NameResolver(context: context), context: context, programs: programs)
        }
        var stdout = ""
        if !context.diagnositicEngine.hasErrors {
            if config.dumpAST, !programs.isEmpty {
                let dumper = AST.Dumper()
                stdout += programs.map { dumper.dump($0) }.joined(separator: "\n") + "\n"
            }
            if config.dumpSymbols, let first = programs.first {
                stdout += Symbol.Dumper().dump(first) + "\n"
            }
            if config.dumpSource, !programs.isEmpty {
                let printer = SourcePrinter()
                stdout += programs.map { printer.print($0) }.joined(separator: "\n") + "\n"
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

    private func runPass(
        _ visitor: AST.Visitor,
        context: Context,
        programs: [AST.Program]
    ) {
        for program in programs {
            visitor.visitProgram(program)
            if context.diagnositicEngine.hasErrors {
                return
            }
        }
    }

    private static func emitReadError(_ file: String, context: Context) {
        let src = Source(id: context.nextSourceId, filepath: file, content: "")
        context.register(source: src)
        let buffer = src.stringSourceBuffer
        let location = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: .error, message: "could not read file '\(file)'",
                range: SourceRange(start: location, end: location)
            ))
    }
}
