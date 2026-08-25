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
        abstract: "Compile truss source files to semantic checks and dumps.",
        version: "0.1.0"
    )

    @Argument(help: "Input .truss source files.")
    var files: [String]

    @Option(
        name: .long,
        help: "Target triple used by the preprocessor."
    )
    var target: String = DriverConfig.hostTarget

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

    func run() throws {
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
        let config = DriverConfig(
            target: target,
            defines: defineMap,
            dumpAST: dumpAST,
            dumpSymbols: dumpSymbols,
            dumpTIR: dumpTIR,
            dumpLLVMIR: dumpLLVMIR,
            dumpSource: dumpSource,
            moduleName: "main",
            importedInterfaces: importedInterfaces
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
}
