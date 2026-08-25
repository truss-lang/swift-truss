import Foundation

public struct ContentAddressableStore {
    public let root: URL
    public init(root: URL) { self.root = root }

    public var casDirectory: URL { root.appendingPathComponent("cas", isDirectory: true) }

    public func store(hash: String, targetName: String, bytes: [UInt8]) throws {
        let dir = casDirectory.appendingPathComponent(hash, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(targetName + ".trusspackage")
        try Data(bytes).write(to: file)
    }

    public func contains(hash: String, targetName: String) -> Bool {
        let file = casDirectory.appendingPathComponent(hash)
            .appendingPathComponent(targetName + ".trusspackage")
        return FileManager.default.fileExists(atPath: file.path)
    }

    public func load(hash: String, targetName: String) throws -> [UInt8] {
        let file = casDirectory.appendingPathComponent(hash)
            .appendingPathComponent(targetName + ".trusspackage")
        return try Array(Data(contentsOf: file))
    }
}

public enum TargetPointer {
    public static func write(root: URL, targetName: String, hash: String) throws {
        let dir = root.appendingPathComponent(targetName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pointer = dir.appendingPathComponent("current")
        try hash.data(using: .utf8)!.write(to: pointer)
    }

    public static func read(root: URL, targetName: String) -> String? {
        let pointer = root.appendingPathComponent(targetName).appendingPathComponent("current")
        guard let data = try? Data(contentsOf: pointer) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func artifactURL(root: URL, targetName: String) -> URL? {
        guard let hash = read(root: root, targetName: targetName) else { return nil }
        return root.appendingPathComponent("cas")
            .appendingPathComponent(hash)
            .appendingPathComponent(targetName + ".trusspackage")
    }
}
