import ArgumentParser
import Foundation
import TrussPackageManager

@main
struct Truss: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "truss",
        abstract: "Build and manage truss packages.",
        version: "0.1.0",
        subcommands: [Build.self, Run.self, Clean.self, Graph.self]
    )

    static func examplePackage() -> PackageDescription {
        PackageDescription(
            name: "Example",
            targets: [
                PackageTarget(
                    name: "Library",
                    kind: .StaticLibrary,
                    sourcesDirectory: "Sources/Library"
                ),
                PackageTarget(
                    name: "App",
                    kind: .Executable,
                    sourcesDirectory: "Sources/App",
                    dependencies: ["Library"]
                ),
            ],
            products: [
                PackageProduct(name: "Library", kind: .StaticLibrary, targets: ["Library"]),
                PackageProduct(name: "App", kind: .Executable, targets: ["App"]),
            ]
        )
    }
}

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build all targets and emit .trusspackage interfaces.")

    @Flag(help: "Print the emitted module interface after building.")
    var dump = false

    func run() throws {
        let manager = TrussPackageManager(
            package: Truss.examplePackage(),
            packageRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        let result = try manager.build()
        for target in result.targetResults {
            print("\(target.name): \(target.rebuilt ? "rebuilt" : "up to date")")
        }
        if dump {
            for target in result.targetResults {
                print("===== \(target.name) =====")
                if let interface = target.interface {
                    print(TrussPackageDumper.dump(interface))
                }
            }
        }
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build a target and print its module interface dump.")

    @Argument(help: "Target name to run.")
    var target: String

    func run() throws {
        let manager = TrussPackageManager(
            package: Truss.examplePackage(),
            packageRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        guard Truss.examplePackage().targets.contains(where: { $0.name == target }) else {
            throw ValidationError("unknown target '\(target)'")
        }
        guard Truss.examplePackage().targets.first(where: { $0.name == target })?.kind == .Executable else {
            throw ValidationError("only executable targets can be run")
        }
        _ = try manager.build()
        try print(manager.dump(target))
    }
}

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove all build artifacts.")

    func run() throws {
        let manager = TrussPackageManager(
            package: Truss.examplePackage(),
            packageRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        try manager.clean()
        print("cleaned")
    }
}

struct Graph: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the target dependency graph.")

    func run() throws {
        let manager = TrussPackageManager(
            package: Truss.examplePackage(),
            packageRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        print(manager.graph(), terminator: "")
    }
}
