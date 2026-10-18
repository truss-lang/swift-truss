import ArgumentParser
import Foundation
import TrussCore
import TrussDriver
import TrussPackageManager

enum TrussStd {
    static let packageName = "Truss"
    static let source = """
    public enum Optional<T> {
        case None
        case Some(T)
    }
    """
}

@main
struct Trussc: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trussc",
        abstract: "Compile truss source files to diagnostics, dumps and native artifacts.",
        version: "0.1.0"
    )

    @Argument(help: "Input .truss source files.")
    var files: [String]

    @Option(
        name: .long,
        help: "The target triple."
    )
    var target: String = DriverConfig.hostTarget

    @Option(
        name: .customLong("module-name"),
        help: "The module name used by the parser, the name mangler and the default output name."
    )
    var moduleName: String?

    @Option(
        name: [.customShort("D"), .customLong("define")],
        help: "Define a preprocessor build flag, as NAME or NAME=value."
    )
    var defines: [String] = []

    @Flag(help: "Print the AST dump.")
    var dumpAST = false

    @Flag(help: "Print the symbol table dump.")
    var dumpSymbols = false

    @Flag(help: "Print the TIR dump.")
    var dumpTIR = false

    @Flag(help: "Print the LLVM IR dump.")
    var dumpLLVMIR = false

    @Flag(help: "Print the round-tripped source.")
    var dumpSource = false

    @Flag(
        name: .customLong("no-stdlib"),
        help: "Do not preload the Truss standard library."
    )
    var noStdlib = false

    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: "Write the emitted artifact to this path (default: derived from the first input file)."
    )
    var output: String?

    @Option(
        name: .long,
        help: "Artifact to emit: object, assembly, llvm-ir or executable (default: executable unless dumps are requested)."
    )
    var emit: String?

    func run() throws {
        if let moduleName, moduleName.isEmpty {
            throw ValidationError("--module-name must not be empty")
        }
        let defineMap = Dictionary(
            defines.map { raw -> (String, String) in
                if let eq = raw.firstIndex(of: "=") {
                    return (String(raw[..<eq]), String(raw[raw.index(after: eq)...]))
                }
                return (raw, "1")
            },
            uniquingKeysWith: { _, new in new }
        )
        var importedInterfaces: [ModuleInterface] = []
        if !noStdlib {
            let stdResult = Driver(config: DriverConfig(moduleName: TrussStd.packageName))
                .runString(TrussStd.source)
            if stdResult.hasErrors {
                throw ValidationError("standard library failed to compile:\n\(stdResult.stderr)")
            }
            if let interface = stdResult.packageInterface {
                importedInterfaces.append(interface)
            }
        }
        var emitKind = EmitKind.Executable
        if let emit {
            guard let parsed = EmitKind(rawValue: emit) else {
                throw ValidationError(
                    "unknown emit kind '\(emit)' (expected: \(EmitKind.allCases.map(\.rawValue).joined(separator: ", ")))"
                )
            }
            emitKind = parsed
        }
        let config = DriverConfig(
            target: target,
            defines: defineMap,
            dumpAST: dumpAST,
            dumpSymbols: dumpSymbols,
            dumpTIR: dumpTIR,
            dumpLLVMIR: dumpLLVMIR,
            dumpSource: dumpSource,
            moduleName: moduleName ?? "main",
            importedInterfaces: importedInterfaces,
            outputPath: resolvedOutputPath(emitKind: emitKind),
            emitKind: emitKind
        )
        let result = Driver(config: config).run(files: files)
        if !result.stdout.isEmpty {
            print(result.stdout, terminator: "")
        }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        if result.hasErrors {
            throw ExitCode.failure
        }
    }

    private func resolvedOutputPath(emitKind: EmitKind) -> String? {
        if let output {
            return output
        }
        guard emit != nil || !hasDumps else {
            return nil
        }
        guard let first = files.first else {
            return nil
        }
        let stem = moduleName ?? URL(fileURLWithPath: first).deletingPathExtension().lastPathComponent
        return switch emitKind {
        case .Executable: Self.executableName(stem)
        case .Object: "\(stem).o"
        case .Assembly: "\(stem).s"
        case .LLVMIR: "\(stem).ll"
        }
    }

    private var hasDumps: Bool {
        dumpAST || dumpSymbols || dumpTIR || dumpLLVMIR || dumpSource
    }

    private static func executableName(_ stem: String) -> String {
        #if os(Windows)
            "\(stem).exe"
        #else
            stem
        #endif
    }
}
