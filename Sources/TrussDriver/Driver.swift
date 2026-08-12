import Foundation
import SwiftBetterDiagnostic
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax
import TrussTIRGen

public struct DriverConfig {
    public static let hostTarget: String = TargetTriple.host

    public var target: String
    public var defines: [String: String]
    public var dumpAST: Bool
    public var dumpSymbols: Bool
    public var dumpTIR: Bool
    public var dumpSource: Bool
    public var dumpOnError: Bool

    public init(
        target: String = DriverConfig.hostTarget,
        defines: [String: String] = [:],
        dumpAST: Bool = false,
        dumpSymbols: Bool = false,
        dumpTIR: Bool = false,
        dumpSource: Bool = false,
        dumpOnError: Bool = false
    ) {
        self.target = target
        self.defines = defines
        self.dumpAST = dumpAST
        self.dumpSymbols = dumpSymbols
        self.dumpTIR = dumpTIR
        self.dumpSource = dumpSource
        self.dumpOnError = dumpOnError
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
        Builtin.install(context: context)
        var programs: [AST.Program] = []
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                Self.emitReadError(file, context: context)
                break
            }
            parseSource(
                content, filepath: file,
                workingDirectory: (file as NSString).deletingLastPathComponent,
                context: context, programs: &programs
            )
            if context.diagnositicEngine.hasErrors {
                break
            }
        }
        return runPasses(programs: programs, context: context)
    }

    public func runString(_ source: String, filename: String = "<main>") -> DriverResult {
        let context = Context()
        Builtin.install(context: context)
        var programs: [AST.Program] = []
        parseSource(
            source, filepath: filename, workingDirectory: "",
            context: context, programs: &programs
        )
        return runPasses(programs: programs, context: context)
    }

    private func parseSource(
        _ content: String, filepath: String, workingDirectory: String,
        context: Context, programs: inout [AST.Program]
    ) {
        let src = Source(id: context.nextSourceId, filepath: filepath, content: content)
        context.register(source: src)
        let lexerResult = Lexer(input: CharStream(content: content, id: src.id)).parse()
        let preprocessed = Preprocessor(context: context).process(
            lexerResult,
            config: PreprocessorConfig(
                defines: config.defines,
                target: config.target,
                workingDirectory: workingDirectory
            )
        )
        programs.append(Parser(context: context, packageName: "main", preprocessed).parse())
    }

    private func runPasses(programs: [AST.Program], context: Context) -> DriverResult {
        var programs = programs
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
        if !context.diagnositicEngine.hasErrors {
            runOperatorPasses(&programs, context: context)
        }
        if !context.diagnositicEngine.hasErrors {
            runPass(TypeBuilder(context: context), context: context, programs: programs)
        }
        if !context.diagnositicEngine.hasErrors {
            let checker = TypeChecker(context: context)
            checker.checkAll(programs)
        }
        if !context.diagnositicEngine.hasErrors {
            runPass(ModifierChecker(context: context), context: context, programs: programs)
        }
        if !context.diagnositicEngine.hasErrors {
            runPass(AccessChecker(context: context), context: context, programs: programs)
        }
        var tirModules: [TIR.Module] = []
        if !context.diagnositicEngine.hasErrors {
            let tirGen = TIRGen(context: context)
            tirModules = tirGen.generateAll(programs)
        }
        var stdout = ""
        if !context.diagnositicEngine.hasErrors || config.dumpOnError {
            if config.dumpAST, !programs.isEmpty {
                let dumper = AST.Dumper()
                stdout += programs.map { dumper.dump($0) }.joined(separator: "\n") + "\n"
            }
            if config.dumpSymbols, let first = programs.first {
                stdout += Symbol.Dumper(context: context).dump(first)
            }
            if config.dumpTIR, !tirModules.isEmpty {
                let dumper = TIR.Dumper()
                stdout += tirModules.map { dumper.dump($0) }.joined(separator: "\n") + "\n"
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

    private func runOperatorPasses(_ programs: inout [AST.Program], context: Context) {
        let table = OperatorTable()
        runPass(
            TrussOperator.DeclCollector(table: table, context: context),
            context: context, programs: programs
        )
        if context.diagnositicEngine.hasErrors { return }
        PrecedenceResolver(table: table, context: context).resolve()
        if context.diagnositicEngine.hasErrors { return }
        let folder = ExpressionFolder(context: context, table: table)
        programs = programs.map { folder.rewrite($0) }
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
            )
        )
    }
}
