import Foundation
import Testing
import TrussCore
import TrussDriver
import TrussPackageManager

private func makeTempDir(_ label: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("truspkg-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func write(_ file: URL, _ content: String) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: file, atomically: true, encoding: .utf8)
}

@Suite struct DriverImportTests {
    @Test func driverLoadsImportedInterfaceIntoContext() throws {
        // Build Library first, capture its interface.
        let libSource = """
        public func libValue() -> Builtin.Int64 { 42 }
        """
        let libResult = Driver(config: DriverConfig(moduleName: "Library")).runString(libSource)
        #expect(!libResult.hasErrors)
        guard let libInterface = libResult.packageInterface else {
            Issue.record("no library interface")
            return
        }
        let bytes = TrussPackageEncoder(interface: libInterface).encode()
        let decoded = try TrussPackageDecoder().decode(bytes)
        // Compile a dependent target with the interface imported.
        let appSource = """
        public func appEntry() -> Builtin.Int64 { 1 }
        """
        let appResult = Driver(config: DriverConfig(
            moduleName: "App",
            importedInterfaces: [decoded.interface]
        )).runString(appSource)
        #expect(!appResult.hasErrors, "diagnostics: \(appResult.stderr)")
    }

    @Test func importedInterfaceDecodesToUsableSymbols() throws {
        let source = """
        public struct Dep {
            public var value: Builtin.Int64
        }
        public func depFn(_ a: Builtin.Int64) -> Builtin.Int64 { a }
        """
        let result = Driver(config: DriverConfig(moduleName: "Dep")).runString(source)
        #expect(!result.hasErrors)
        guard let interface = result.packageInterface else {
            Issue.record("no interface")
            return
        }
        let bytes = TrussPackageEncoder(interface: interface).encode()
        let decoded = try TrussPackageDecoder().decode(bytes)
        #expect(decoded.interface.name == "Dep")
        let typeNames = decoded.interface.root.types.compactMap { t -> String? in
            switch t {
            case let .nominal(n): n.name
            default: nil
            }
        }
        #expect(typeNames.contains("Dep"))
    }
}

private func canonicalize(_ i: ModuleInterface) -> ModuleInterface {
    ModuleInterface(name: i.name, root: canonScope(i.root))
}

private func canonScope(_ s: InterfaceScope) -> InterfaceScope {
    InterfaceScope(
        modules: s.modules.map { InterfaceModule(name: $0.name, scope: canonScope($0.scope)) },
        types: s.types.sorted { nameOf($0) < nameOf($1) },
        values: s.values.sorted { nameOfValue($0) < nameOfValue($1) }
    )
}

private func nameOf(_ t: InterfaceType) -> String {
    switch t {
    case let .nominal(n): n.name
    case let .typeAlias(a): a.name
    case let .associatedType(s): s.name
    case let .builtin(s): s.name
    case let .genericParam(s): s.name
    }
}

private func nameOfValue(_ v: InterfaceValue) -> String {
    switch v {
    case let .function(f): f.name
    case let .variable(x): x.name
    }
}

@Suite struct ModuleInterfaceCodecTests {
    @Test func roundTripComplexInterface() throws {
        let interface = ModuleInterface(
            name: "M",
            root: InterfaceScope(
                types: [
                    .nominal(InterfaceNominal(
                        kind: .structType, name: "S",
                        conformances: ["P"], superclass: nil,
                        scope: InterfaceScope(
                            values: [
                                .function(InterfaceFunction(
                                    name: "f", labels: ["a", nil], hasDefaults: [false, true],
                                    isVararg: [false, false], isVariadic: false,
                                    functionType: .function(InterfaceFunctionType(
                                        parameters: [
                                            InterfaceTupleElement(label: "a", type: .builtin("Int64")),
                                            InterfaceTupleElement(label: nil, type: .builtin("Int64")),
                                        ],
                                        returnType: .builtin("Int64")
                                    ))
                                )),
                                .variable(InterfaceVariable(name: "x", isMutable: true, type: .builtin("Int64"))),
                            ]
                        )
                    )),
                    .typeAlias(InterfaceTypealias(name: "Alias", target: .optional(.builtin("Int64")))),
                ],
                values: [
                    .function(InterfaceFunction(
                        name: "top", labels: [], hasDefaults: [], isVararg: [], isVariadic: false,
                        functionType: .function(InterfaceFunctionType(parameters: [], returnType: .void))
                    )),
                ]
            )
        )
        let bytes = TrussPackageEncoder(interface: interface).encode()
        #expect(bytes.count > 0)
        let decoded = try TrussPackageDecoder().decode(bytes)
        #expect(canonicalize(decoded.interface) == canonicalize(interface))
    }

    @Test func roundTripEmpty() throws {
        let interface = ModuleInterface(name: "Empty", root: InterfaceScope())
        let bytes = TrussPackageEncoder(interface: interface).encode()
        let decoded = try TrussPackageDecoder().decode(bytes)
        #expect(decoded.interface == interface)
    }

    @Test func rejectsBadMagic() throws {
        var bytes: [UInt8] = [1, 2, 3, 4]
        bytes.append(contentsOf: [0, 0, 0, 0])
        do {
            _ = try TrussPackageDecoder().decode(bytes)
            Issue.record("expected badMagic")
        } catch TrussPackageCodecError.badMagic {
            // expected
        }
    }
}

@Suite struct InterfaceExtractionTests {
    @Test func extractsOnlyPublicAndOpen() throws {
        let source = """
        public struct S {
            public func f() -> Builtin.Int64 { 1 }
            internal func hidden() -> Builtin.Int64 { 2 }
        }
        internal struct Hidden {}
        open class C {
            open func m() {}
            public func n() {}
        }
        public func top() -> Builtin.Int64 { 3 }
        """
        let result = Driver(config: DriverConfig(moduleName: "Test")).runString(source)
        #expect(!result.hasErrors, "diagnostics: \(result.stderr)")
        guard let interface = result.packageInterface else {
            Issue.record("no interface")
            return
        }
        let names = interface.root.types.compactMap { t -> String? in
            switch t {
            case let .nominal(n): n.name
            case let .typeAlias(a): a.name
            default: nil
            }
        }
        #expect(names.contains("S"))
        #expect(names.contains("C"))
        #expect(!names.contains("Hidden"))
    }
}

@Suite struct PackageManagerTests {
    private func makeSamplePackage() throws -> (URL, PackageDescription) {
        let root = try makeTempDir("pkg")
        try write(
            root.appendingPathComponent("Sources/Library/lib.truss"),
            """
            precedencegroup Assignment { assignment: true }
            precedencegroup Addition { higherThan: Assignment associativity: left }
            infix operator =: Assignment
            infix operator +: Addition
            func +(lhs: Builtin.Int64, rhs: Builtin.Int64) -> Builtin.Int64 { Builtin.builtin_add_int64(lhs, rhs) }
            public struct Point {
                public var x: Builtin.Int64
                public var y: Builtin.Int64
                public init(x: Builtin.Int64, y: Builtin.Int64) {
                    self.x = x
                    self.y = y
                }
                public func distance() -> Builtin.Int64 {
                    Builtin.builtin_add_int64(self.x, self.y)
                }
            }
            public func add(_ a: Builtin.Int64, _ b: Builtin.Int64) -> Builtin.Int64 {
                a + b
            }
            """
        )
        try write(
            root.appendingPathComponent("Sources/App/main.truss"),
            """
            public func entry() -> Builtin.Int64 { 1 }
            """
        )
        let package = PackageDescription(
            name: "Sample",
            targets: [
                PackageTarget(name: "Library", kind: .staticLibrary, sourcesDirectory: "Sources/Library"),
                PackageTarget(
                    name: "App",
                    kind: .executable,
                    sourcesDirectory: "Sources/App",
                    dependencies: ["Library"]
                ),
            ]
        )
        return (root, package)
    }

    @Test func topologicalOrderDependenciesFirst() throws {
        let (_, package) = try makeSamplePackage()
        let manager = TrussPackageManager(package: package, packageRoot: URL(fileURLWithPath: "/tmp"))
        let order = try manager.topologicalOrder()
        #expect(order == ["Library", "App"])
    }

    @Test func buildProducesCasArtifacts() throws {
        let (root, package) = try makeSamplePackage()
        let manager = TrussPackageManager(package: package, packageRoot: root)
        let result = try manager.build()
        let library = result.targetResults.first { $0.name == "Library" }
        #expect(library?.rebuilt == true)
        #expect(library?.artifactURL != nil)
        #expect(FileManager.default.fileExists(atPath: library!.artifactURL!.path))
        let pointer = TargetPointer.read(root: root.appendingPathComponent("Build"), targetName: "Library")
        #expect(pointer != nil)
        // second build should be up-to-date (CAS hit)
        let second = try manager.build()
        let library2 = second.targetResults.first { $0.name == "Library" }
        #expect(library2?.rebuilt == false)
    }

    @Test func cleanRemovesBuildDir() throws {
        let (root, package) = try makeSamplePackage()
        let manager = TrussPackageManager(package: package, packageRoot: root)
        _ = try manager.build()
        let buildDir = root.appendingPathComponent("Build")
        #expect(FileManager.default.fileExists(atPath: buildDir.path))
        try manager.clean()
        #expect(!FileManager.default.fileExists(atPath: buildDir.path))
    }

    @Test func graphRendersEdges() throws {
        let (_, package) = try makeSamplePackage()
        let manager = TrussPackageManager(package: package, packageRoot: URL(fileURLWithPath: "/tmp"))
        let text = manager.graph()
        #expect(text.contains("App: Library"))
        #expect(text.contains("Library: "))
    }

    @Test func dependencyCycleThrows() throws {
        let package = PackageDescription(
            name: "Cyc",
            targets: [
                PackageTarget(name: "A", kind: .staticLibrary, sourcesDirectory: "Sources/A", dependencies: ["B"]),
                PackageTarget(name: "B", kind: .staticLibrary, sourcesDirectory: "Sources/B", dependencies: ["A"]),
            ]
        )
        let manager = TrussPackageManager(package: package, packageRoot: URL(fileURLWithPath: "/tmp"))
        do {
            _ = try manager.topologicalOrder()
            Issue.record("expected cycle error")
        } catch PackageBuildError.dependencyCycle {
            // expected
        }
    }
}
