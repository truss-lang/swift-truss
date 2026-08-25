import Foundation
import SwiftGraph
import TrussCore
import TrussDriver

public enum PackageBuildError: Error, CustomStringConvertible {
    case unknownTarget(String)
    case dependencyCycle([String])
    case sourceReadFailed(String)
    case compileFailed(String, String)
    case missingDependencyArtifact(String)

    public var description: String {
        switch self {
        case let .unknownTarget(n): "unknown target '\(n)'"
        case let .dependencyCycle(c): "dependency cycle detected: \(c.joined(separator: " -> "))"
        case let .sourceReadFailed(p): "could not read source at '\(p)'"
        case let .compileFailed(t, err): "failed to compile target '\(t)':\n\(err)"
        case let .missingDependencyArtifact(t): "missing dependency artifact for '\(t)'"
        }
    }
}

public struct PackageBuildResult {
    public let targetResults: [TargetBuildResult]
    public init(targetResults: [TargetBuildResult]) { self.targetResults = targetResults }
}

public struct TargetBuildResult {
    public let name: String
    public let artifactURL: URL?
    public let interface: ModuleInterface?
    public let rebuilt: Bool
    public init(name: String, artifactURL: URL?, interface: ModuleInterface?, rebuilt: Bool) {
        self.name = name
        self.artifactURL = artifactURL
        self.interface = interface
        self.rebuilt = rebuilt
    }
}

public final class TrussPackageManager {
    private let package: PackageDescription
    private let packageRoot: URL
    private let buildRoot: URL
    private let cas: ContentAddressableStore
    private let target: String

    public init(package: PackageDescription, packageRoot: URL, target: String = DriverConfig.hostTarget) {
        self.package = package
        self.packageRoot = packageRoot
        buildRoot = packageRoot.appendingPathComponent(package.buildDirectory, isDirectory: true)
        cas = ContentAddressableStore(root: buildRoot)
        self.target = target
    }

    public var buildDirectoryURL: URL { buildRoot }

    public func build() throws -> PackageBuildResult {
        let order = try topologicalOrder()
        var interfaces: [String: ModuleInterface] = [:]
        var results: [TargetBuildResult] = []
        for name in order {
            guard let targetDesc = package.targets.first(where: { $0.name == name }) else {
                throw PackageBuildError.unknownTarget(name)
            }
            let fingerprint = try computeFingerprint(for: targetDesc, dependencyInterfaces: interfaces)
            if cas.contains(hash: fingerprint, targetName: name) {
                let bytes = try cas.load(hash: fingerprint, targetName: name)
                let doc = try TrussPackageDecoder().decode(bytes)
                interfaces[name] = doc.interface
                try TargetPointer.write(root: buildRoot, targetName: name, hash: fingerprint)
                results.append(TargetBuildResult(
                    name: name, artifactURL: TargetPointer.artifactURL(root: buildRoot, targetName: name),
                    interface: doc.interface, rebuilt: false
                ))
                continue
            }
            let depInterfaces = try targetDesc.dependencies.map { depName -> ModuleInterface in
                guard let i = interfaces[depName] else { throw PackageBuildError.missingDependencyArtifact(depName) }
                return i
            }
            let config = DriverConfig(
                target: target,
                defines: [:],
                moduleName: name,
                importedInterfaces: depInterfaces
            )
            let sourceFiles = try sourceFiles(for: targetDesc)
            let result = Driver(config: config).run(files: sourceFiles)
            if result.hasErrors {
                throw PackageBuildError.compileFailed(name, result.stderr)
            }
            guard let interface = result.packageInterface else {
                throw PackageBuildError.compileFailed(name, "no module interface produced")
            }
            let bytes = TrussPackageEncoder(interface: interface).encode()
            try cas.store(hash: fingerprint, targetName: name, bytes: bytes)
            try TargetPointer.write(root: buildRoot, targetName: name, hash: fingerprint)
            interfaces[name] = interface
            results.append(TargetBuildResult(
                name: name, artifactURL: TargetPointer.artifactURL(root: buildRoot, targetName: name),
                interface: interface, rebuilt: true
            ))
        }
        return PackageBuildResult(targetResults: results)
    }

    public func dump(_ targetName: String) throws -> String {
        if let artifact = TargetPointer.artifactURL(root: buildRoot, targetName: targetName) {
            let bytes = try Array(Data(contentsOf: artifact))
            let doc = try TrussPackageDecoder().decode(bytes)
            return ModuleInterfaceDumper().dump(doc.interface)
        }
        let order = try topologicalOrder()
        guard order.contains(targetName) else { throw PackageBuildError.unknownTarget(targetName) }
        _ = try build()
        guard let artifact = TargetPointer.artifactURL(root: buildRoot, targetName: targetName) else {
            throw PackageBuildError.missingDependencyArtifact(targetName)
        }
        let bytes = try Array(Data(contentsOf: artifact))
        let doc = try TrussPackageDecoder().decode(bytes)
        return ModuleInterfaceDumper().dump(doc.interface)
    }

    public func clean() throws {
        try? FileManager.default.removeItem(at: buildRoot)
    }

    public func graph() -> String {
        var out = ""
        for targetDesc in package.targets {
            out += "\(targetDesc.name): \(targetDesc.dependencies.joined(separator: ", "))\n"
        }
        return out
    }

    public func topologicalOrder() throws -> [String] {
        let names = package.targets.map(\.name)
        let graph = UnweightedGraph<String>(vertices: names)
        for targetDesc in package.targets {
            for dep in targetDesc.dependencies {
                guard names.contains(dep) else {
                    throw PackageBuildError.unknownTarget(dep)
                }
                graph.addEdge(from: dep, to: targetDesc.name, directed: true)
            }
        }
        if let sorted = graph.topologicalSort() {
            return sorted
        }
        let cycles = graph.detectCycles()
        let cycle = cycles.min { $0.count < $1.count } ?? []
        throw PackageBuildError.dependencyCycle(cycle)
    }

    private func sourceFiles(for targetDesc: PackageTarget) throws -> [String] {
        let dir = packageRoot.appendingPathComponent(targetDesc.sourcesDirectory, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            throw PackageBuildError.sourceReadFailed(dir.path)
        }
        return entries.filter { $0.pathExtension == "truss" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(\.path)
    }

    private func computeFingerprint(
        for targetDesc: PackageTarget, dependencyInterfaces: [String: ModuleInterface]
    ) throws -> String {
        var hasher = FingerprintHasher()
        hasher.add("target")
        hasher.add(targetDesc.name)
        hasher.add(targetDesc.kindName)
        for flag in targetDesc.compileFlags {
            hasher.add(flag)
        }
        for res in targetDesc.resources {
            hasher.add(res)
        }
        hasher.add(target)
        for depName in targetDesc.dependencies {
            hasher.add("dep")
            hasher.add(depName)
            if let i = dependencyInterfaces[depName] {
                hasher.add(ContentHash.sha256(TrussPackageEncoder(interface: i).encode()))
            }
        }
        let files = try sourceFiles(for: targetDesc)
        for path in files {
            hasher.add(path)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                throw PackageBuildError.sourceReadFailed(path)
            }
            hasher.add(ContentHash.sha256(Array(data)))
        }
        return hasher.finish()
    }
}

private extension PackageTarget {
    var kindName: String {
        switch kind {
        case .executable: "executable"
        case .staticLibrary: "staticLibrary"
        case .dynamicLibrary: "dynamicLibrary"
        }
    }
}

private struct FingerprintHasher {
    private var parts: [[UInt8]] = []
    mutating func add(_ s: String) { parts.append(Array(s.utf8)) }
    func finish() -> String {
        var buf: [UInt8] = []
        for p in parts {
            buf.append(contentsOf: p)
            buf.append(0)
        }
        return ContentHash.sha256(buf)
    }
}
