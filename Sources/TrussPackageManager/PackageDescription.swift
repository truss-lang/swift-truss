import Foundation

public enum TargetKind: Equatable, Sendable {
    case Executable
    case StaticLibrary
    case DynamicLibrary
}

public enum ProductKind: Equatable, Sendable {
    case Executable
    case StaticLibrary
    case DynamicLibrary
}

public struct PackageTarget: Equatable, Sendable {
    public var name: String
    public var kind: TargetKind
    public var sourcesDirectory: String
    public var dependencies: [String]
    public var resources: [String]
    public var compileFlags: [String]
    public init(
        name: String, kind: TargetKind, sourcesDirectory: String,
        dependencies: [String] = [], resources: [String] = [], compileFlags: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.sourcesDirectory = sourcesDirectory
        self.dependencies = dependencies
        self.resources = resources
        self.compileFlags = compileFlags
    }
}

public struct PackageProduct: Equatable, Sendable {
    public var name: String
    public var kind: ProductKind
    public var targets: [String]
    public init(name: String, kind: ProductKind, targets: [String]) {
        self.name = name
        self.kind = kind
        self.targets = targets
    }
}

public struct PackageDescription: Equatable, Sendable {
    public var name: String
    public var targets: [PackageTarget]
    public var products: [PackageProduct]
    public var buildDirectory: String
    public init(
        name: String,
        targets: [PackageTarget],
        products: [PackageProduct] = [],
        buildDirectory: String = "Build"
    ) {
        self.name = name
        self.targets = targets
        self.products = products
        self.buildDirectory = buildDirectory
    }
}
