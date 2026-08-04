import ArgumentParser
import Foundation
import TrussDriver

@main
struct Trussc: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trussc",
        abstract: "Compile truss source files to semantic checks and dumps.",
        version: "0.1.0")

    @Argument(help: "Input .truss source files.")
    var files: [String]

    @Option(
        name: .long,
        help: "Target triple used by the preprocessor.")
    var target: String = "x86_64-unknown-linux-gnu"

    @Option(
        name: [.customShort("D"), .customLong("define")],
        help: "Define a preprocessor build flag, as NAME or NAME=value.")
    var defines: [String] = []

    @Flag(help: "Print the AST dump.")
    var dumpAST = false

    @Flag(help: "Print the symbol table dump.")
    var dumpSymbols = false

    @Flag(help: "Print the round-tripped source.")
    var dumpSource = false

    func run() throws {
        var defineMap: [String: String] = [:]
        for raw in self.defines {
            if let eq = raw.firstIndex(of: "=") {
                defineMap[String(raw[..<eq])] = String(raw[raw.index(after: eq)...])
            } else {
                defineMap[raw] = "1"
            }
        }
        let config = DriverConfig(
            target: self.target,
            defines: defineMap,
            dumpAST: self.dumpAST,
            dumpSymbols: self.dumpSymbols,
            dumpSource: self.dumpSource)
        let result = Driver(config: config).run(files: self.files)
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
