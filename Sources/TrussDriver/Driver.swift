import Foundation
import LLVMSwiftBinding
import SwiftBetterDiagnostic
import TrussCodeGen
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax
import TrussTIRGen
import TrussTIRPass

public enum EmitKind: String, CaseIterable {
    case Object = "object"
    case Assembly = "assembly"
    case LLVMIR = "llvm-ir"
    case Executable = "executable"
}

public enum SystemLinker {
    public static let compilerNames = ["cc", "clang", "gcc"]

    public static func findCompiler() -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: pathSeparator) {
            for name in compilerNames {
                let candidate = "\(directory)/\(name)"
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
                      !isDirectory.boolValue,
                      FileManager.default.isExecutableFile(atPath: candidate)
                else {
                    continue
                }
                return candidate
            }
        }
        return nil
    }

    private static var pathSeparator: Character {
        #if os(Windows)
            ";"
        #else
            ":"
        #endif
    }
}

public struct DriverConfig {
    public static let hostTarget: String = TargetTriple.host

    public var target: String
    public var defines: [String: String]
    public var dumpAST: Bool
    public var dumpSymbols: Bool
    public var dumpTIR: Bool
    public var dumpLLVMIR: Bool
    public var dumpSource: Bool
    public var dumpOnError: Bool
    public var moduleName: String
    public var importedInterfaces: [ModuleInterface]
    public var outputPath: String?
    public var emitKind: EmitKind

    public init(
        target: String = DriverConfig.hostTarget,
        defines: [String: String] = [:],
        dumpAST: Bool = false,
        dumpSymbols: Bool = false,
        dumpTIR: Bool = false,
        dumpLLVMIR: Bool = false,
        dumpSource: Bool = false,
        dumpOnError: Bool = false,
        moduleName: String = "main",
        importedInterfaces: [ModuleInterface] = [],
        outputPath: String? = nil,
        emitKind: EmitKind = .Executable
    ) {
        self.target = target
        self.defines = defines
        self.dumpAST = dumpAST
        self.dumpSymbols = dumpSymbols
        self.dumpTIR = dumpTIR
        self.dumpLLVMIR = dumpLLVMIR
        self.dumpSource = dumpSource
        self.dumpOnError = dumpOnError
        self.moduleName = moduleName
        self.importedInterfaces = importedInterfaces
        self.outputPath = outputPath
        self.emitKind = emitKind
    }
}

public struct DriverResult {
    public let stdout: String
    public let stderr: String
    public let hasErrors: Bool
    public let packageInterface: ModuleInterface?
    public init(stdout: String, stderr: String, hasErrors: Bool, packageInterface: ModuleInterface? = nil) {
        self.stdout = stdout
        self.stderr = stderr
        self.hasErrors = hasErrors
        self.packageInterface = packageInterface
    }
}

public final class Driver {
    private let config: DriverConfig

    public init(config: DriverConfig) {
        self.config = config
    }

    public func run(files: [String]) -> DriverResult {
        let context = TrussCore.Context()
        Builtin.install(context: context)
        for interface in config.importedInterfaces {
            InterfaceLoader(context: context).load(interface)
        }
        let programs: [AST.Program] = files.compactMap {
            guard !context.diagnosticEngine.hasErrors else {
                return nil
            }
            guard let content = try? String(contentsOfFile: $0, encoding: .utf8) else {
                Self.emitReadError($0, context: context)
                return nil
            }
            return parseSource(
                content, filepath: $0,
                workingDirectory: ($0 as NSString).deletingLastPathComponent,
                context: context
            )
        }
        return runPasses(programs: programs, context: context)
    }

    public func runString(_ source: String, filename: String = "<main>") -> DriverResult {
        let context = TrussCore.Context()
        Builtin.install(context: context)
        for interface in config.importedInterfaces {
            InterfaceLoader(context: context).load(interface)
        }
        let program = parseSource(
            source, filepath: filename, workingDirectory: "",
            context: context
        )
        return runPasses(programs: [program], context: context)
    }

    private func parseSource(
        _ content: String, filepath: String, workingDirectory: String,
        context: TrussCore.Context
    ) -> AST.Program {
        let src = Source(id: context.nextSourceId, filepath: filepath, content: content)
        context.register(source: src)
        let lexerResult = Lexer(input: CharStream(content: content, id: src.id)).parse()
        let preprocessed = Preprocessor(context: context).process(
            lexerResult,
            config: .init(
                defines: config.defines,
                target: config.target,
                workingDirectory: workingDirectory
            )
        )
        return Parser(context: context, packageName: config.moduleName, preprocessed).parse()
    }

    private func runPasses(programs: [AST.Program], context: TrussCore.Context) -> DriverResult {
        var programs = programs
        if !context.diagnosticEngine.hasErrors {
            runPass(DeclCollector(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(ImportProcessor(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runRewriter(OptionalDesugarPass(), context: context, programs: &programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(Enter(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            let merger = MergePass(context: context)
            runPass(merger, context: context, programs: programs)
            if !context.diagnosticEngine.hasErrors {
                merger.resolvePending()
            }
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(NameResolver(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runOperatorPasses(&programs, context: context)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(TypeBuilder(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(TypeChecker(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(AttributeChecker(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(ModifierChecker(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(AccessChecker(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            runPass(ControlFlowChecker(context: context), context: context, programs: programs)
        }
        if !context.diagnosticEngine.hasErrors {
            let unusedChecker = UnusedDeclarationChecker(context: context)
            unusedChecker.checkAll(programs)
        }
        let needsTIR = config.dumpTIR || config.dumpLLVMIR || config.outputPath != nil
        let needsCodeGen = config.dumpLLVMIR || config.outputPath != nil
        let tirModules: [TIR.Module]
        if needsTIR, !context.diagnosticEngine.hasErrors {
            let tirGen = TIRGen(context: context)
            tirModules = tirGen.generateAll(programs)
        } else {
            tirModules = []
        }
        let lifetimePass = TIRPass()
        var loweredModules: [TIR.Module] = []
        for module in tirModules {
            let result = lifetimePass.run(on: module)
            TIRPass.emitFailures(result.failures, in: context)
            loweredModules.append(result.module)
        }
        let verifier = TIR.Verifier(context: context, ownershipMode: .Strict)
        for module in loweredModules {
            verifier.verify(module)
        }
        let llvmContext: LLVMSwiftBinding.Context?
        let llvmModules: [LLVMSwiftBinding.Module]
        if needsCodeGen, !context.diagnosticEngine.hasErrors {
            llvmContext = .init()
            let codeGen = CodeGen(
                context: context, llvmContext: llvmContext!, target: config.target
            )
            llvmModules = loweredModules.map {
                codeGen.generate($0)
            }
        } else {
            llvmContext = nil
            llvmModules = []
        }
        var stdout = ""
        if !context.diagnosticEngine.hasErrors, let outputPath = config.outputPath {
            emitArtifact(to: outputPath, modules: llvmModules, context: context)
        }
        if !context.diagnosticEngine.hasErrors || config.dumpOnError {
            if config.dumpAST, !programs.isEmpty {
                let dumper = AST.Dumper()
                stdout += programs.map { dumper.dump($0) }.joined(separator: "\n") + "\n"
            }
            if config.dumpSymbols, let first = programs.first {
                stdout += Symbol.Dumper(context: context).dump(first)
            }
            if config.dumpTIR, !loweredModules.isEmpty {
                let dumper = TIR.Dumper()
                stdout += loweredModules.map { dumper.dump($0) }.joined(separator: "\n") + "\n"
            }
            if config.dumpLLVMIR, !llvmModules.isEmpty {
                stdout += llvmModules.map(\.irString).joined(separator: "\n") + "\n"
            }
            if config.dumpSource, !programs.isEmpty {
                let printer = SourcePrinter()
                stdout += programs.map { printer.print($0) }.joined(separator: "\n") + "\n"
            }
        }
        let hasErrors = context.diagnosticEngine.hasErrors
        var stderr = ""
        if !context.diagnosticEngine.diagnostics.isEmpty {
            stderr = TerminalRenderer(beforeLines: 1, afterLines: 1)
                .render(context.diagnosticEngine.sortedDiagnostics())
        }
        let packageInterface: ModuleInterface? = if !hasErrors, let first = programs.first {
            InterfaceExtractor(context: context).extract(from: first)
        } else {
            nil
        }
        return DriverResult(stdout: stdout, stderr: stderr, hasErrors: hasErrors, packageInterface: packageInterface)
    }

    private func runPass(
        _ visitor: AST.Visitor,
        context: TrussCore.Context,
        programs: [AST.Program]
    ) {
        for program in programs {
            visitor.visitProgram(program)
            if context.diagnosticEngine.hasErrors {
                return
            }
        }
    }

    private func runRewriter(
        _ rewriter: AST.Rewriter,
        context: TrussCore.Context,
        programs: inout [AST.Program]
    ) {
        programs = programs.map { rewriter.rewrite($0) }
    }

    private func runOperatorPasses(_ programs: inout [AST.Program], context: TrussCore.Context) {
        let table = OperatorTable()
        runPass(
            TrussOperator.DeclCollector(table: table, context: context),
            context: context, programs: programs
        )
        if context.diagnosticEngine.hasErrors {
            return
        }
        runPass(
            TrussOperator.OperatorImportProcessor(table: table, context: context),
            context: context, programs: programs
        )
        if context.diagnosticEngine.hasErrors {
            return
        }
        PrecedenceResolver(table: table, context: context).resolve()
        if context.diagnosticEngine.hasErrors {
            return
        }
        let folder = ExpressionFolder(context: context, table: table)
        programs = programs.map { folder.rewrite($0) }
    }

    private func emitArtifact(
        to path: String, modules: [LLVMSwiftBinding.Module], context: TrussCore.Context
    ) {
        guard let module = mergedModule(modules, context: context) else {
            return
        }
        switch config.emitKind {
        case .LLVMIR:
            write(module.irString, to: path, context: context)
        case .Object:
            emitCode(module, to: path, fileType: LLVMObjectFile, context: context)
        case .Assembly:
            emitCode(module, to: path, fileType: LLVMAssemblyFile, context: context)
        case .Executable:
            emitExecutable(module, to: path, context: context)
        }
    }

    private func mergedModule(
        _ modules: [LLVMSwiftBinding.Module], context: TrussCore.Context
    ) -> LLVMSwiftBinding.Module? {
        guard let first = modules.first else {
            return nil
        }
        let merged = first.clone()
        for module in modules.dropFirst() {
            do {
                try merged.link(module.clone())
            } catch {
                context.emitError("could not link modules: \(error)", at: TIR.unknownSourceRange)
                return nil
            }
        }
        return merged
    }

    private func emitCode(
        _ module: LLVMSwiftBinding.Module, to path: String, fileType: LLVMCodeGenFileType,
        context: TrussCore.Context
    ) {
        guard let targetMachine = makeTargetMachine(context: context) else {
            context.emitError("could not get target machine", at: TIR.unknownSourceRange)
            return
        }
        do {
            try targetMachine.emitToFile(module: module, path, fileType: fileType)
        } catch {
            context.emitError("could not emit '\(path)': \(error)", at: TIR.unknownSourceRange)
        }
    }

    private func emitExecutable(
        _ module: LLVMSwiftBinding.Module, to path: String, context: TrussCore.Context
    ) {
        let objectPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("truss-\(UUID().uuidString).o")
            .path
        emitCode(module, to: objectPath, fileType: LLVMObjectFile, context: context)
        guard !context.diagnosticEngine.hasErrors else {
            return
        }
        defer {
            try? FileManager.default.removeItem(atPath: objectPath)
        }
        link(objectPath, to: path, context: context)
    }

    private func link(_ objectPath: String, to path: String, context: TrussCore.Context) {
        guard let compiler = SystemLinker.findCompiler() else {
            context.emitError(
                "no C compiler found in PATH (tried \(SystemLinker.compilerNames.joined(separator: ", ")))",
                at: TIR.unknownSourceRange
            )
            return
        }
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("truss-\(UUID().uuidString).log").path
        _ = FileManager.default.createFile(atPath: logPath, contents: nil)
        guard let log = FileHandle(forWritingAtPath: logPath) else {
            context.emitError("could not write linker log '\(logPath)'", at: TIR.unknownSourceRange)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: compiler)
        process.arguments = [objectPath, "-o", path]
        process.standardOutput = log
        process.standardError = log
        do {
            try process.run()
        } catch {
            log.closeFile()
            try? FileManager.default.removeItem(atPath: logPath)
            context.emitError("could not run the system linker: \(error)", at: TIR.unknownSourceRange)
            return
        }
        process.waitUntilExit()
        log.closeFile()
        let output = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(atPath: logPath)
        guard process.terminationStatus != 0 else {
            return
        }
        context.emitError(
            "system linker failed with exit code \(process.terminationStatus)\n\(output)",
            at: TIR.unknownSourceRange
        )
    }

    private func makeTargetMachine(context: TrussCore.Context) -> LLVMSwiftBinding.TargetMachine? {
        let triple = config.target.isEmpty
            ? LLVMSwiftBinding.TargetMachine.defaultTriple
            : LLVMSwiftBinding.TargetMachine.normalizedTriple(config.target)
        LLVMSwiftBinding.TargetMachine.initializeAllTargets()
        guard let target = try? LLVMSwiftBinding.Target.fromTriple(triple) else {
            context.emitError("target '\(config.target)' is not supported", at: TIR.unknownSourceRange)
            return nil
        }
        return LLVMSwiftBinding.TargetMachine(target: target, triple: triple)
    }

    private func write(_ contents: String, to path: String, context: TrussCore.Context) {
        do {
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            context.emitError("could not write '\(path)': \(error)", at: TIR.unknownSourceRange)
        }
    }

    private static func emitReadError(_ file: String, context: TrussCore.Context) {
        let src = Source(id: context.nextSourceId, filepath: file, content: "")
        context.register(source: src)
        let buffer = src.stringSourceBuffer
        let location = SourceLocation(buffer: buffer, offset: 0, line: 1, column: 1)
        context.diagnosticEngine.emit(
            Diagnostic(
                severity: .error, message: "could not read file '\(file)'",
                range: SourceRange(start: location, end: location)
            )
        )
    }
}
