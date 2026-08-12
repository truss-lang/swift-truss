import ArgumentParser
import Foundation
import TrussDriver

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

    @Flag(help: "Print the round-tripped source.")
    var dumpSource = false

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
        let config = DriverConfig(
            target: target,
            defines: defineMap,
            dumpAST: dumpAST,
            dumpSymbols: dumpSymbols,
            dumpTIR: dumpTIR,
            dumpSource: dumpSource
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
