import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSemantics
import TrussSyntax

func runImports(
    _ source: String, interfaces: [ModuleInterface]
) -> (Context, AST.Program) {
    let context = Context()
    for interface in interfaces {
        InterfaceLoader(context: context).load(interface)
    }
    let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
    context.register(source: src)
    let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
    let preprocessed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig()
    )
    let program = Parser(context: context, packageName: "main", preprocessed).parse()
    DeclCollector(context: context).visitProgram(program)
    ImportProcessor(context: context).visitProgram(program)
    NameResolver(context: context).visitProgram(program)
    return (context, program)
}

private func trussInterface() -> ModuleInterface {
    ModuleInterface(
        name: "Truss",
        root: InterfaceScope(
            modules: [
                InterfaceModule(
                    name: "Core",
                    scope: InterfaceScope(
                        types: [.Nominal(InterfaceNominal(kind: .StructType, name: "Vector"))]
                    )
                ),
            ],
            types: [.Nominal(InterfaceNominal(kind: .StructType, name: "Int"))],
            values: [.Function(InterfaceFunction(
                name: "print", labels: [nil], hasDefaults: [false],
                isVararg: [false], isVariadic: false
            ))]
        )
    )
}

private func fooInterface() -> ModuleInterface {
    ModuleInterface(
        name: "Foo",
        root: InterfaceScope(
            modules: [
                InterfaceModule(
                    name: "Bar",
                    scope: InterfaceScope(
                        types: [.Nominal(InterfaceNominal(kind: .StructType, name: "Point"))],
                        values: [.Function(InterfaceFunction(
                            name: "makePoint", labels: [nil], hasDefaults: [false],
                            isVararg: [false], isVariadic: false
                        ))]
                    )
                ),
            ],
            types: [.Nominal(InterfaceNominal(kind: .StructType, name: "FooType"))]
        )
    )
}

@Test func importsSubmoduleAsNamespace() {
    let (context, program) = runImports("import Foo.Bar", interfaces: [fooInterface()])
    let scope = program.packageSymbol!.scope
    #expect(scope.modules["Bar"] != nil)
    #expect(scope.modules["Bar"]!.scope.types["Point"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func importsPackageTopLevelType() {
    let (context, program) = runImports("import Foo.FooType", interfaces: [fooInterface()])
    let scope = program.packageSymbol!.scope
    #expect(scope.types["FooType"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func importsSingleComponentPackage() {
    let (context, program) = runImports("import Foo", interfaces: [fooInterface()])
    #expect(context.name2Package["Foo"] != nil)
    #expect(program.packageSymbol!.scope.modules["Foo"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func wildcardImportExposesMembers() {
    let (context, program) = runImports("import Foo.Bar.*", interfaces: [fooInterface()])
    let scope = program.packageSymbol!.scope
    #expect(scope.types["Point"] != nil)
    #expect(scope.values["makePoint"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func explicitImportWithAlias() {
    let (context, program) = runImports("import Foo.Bar.Point as P", interfaces: [fooInterface()])
    let scope = program.packageSymbol!.scope
    #expect(scope.types["P"] != nil)
    #expect(scope.types["Point"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedExplicitImportResolvesSubmoduleMembers() {
    let (context, program) = runImports(
        "import Foo.{Bar.{Point, makePoint}}", interfaces: [fooInterface()]
    )
    let scope = program.packageSymbol!.scope
    #expect(scope.types["Point"] != nil)
    #expect(scope.values["makePoint"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedExplicitImportMixedWithFlatItems() {
    let (context, program) = runImports(
        "import Foo.{FooType, Bar.{Point}}", interfaces: [fooInterface()]
    )
    let scope = program.packageSymbol!.scope
    #expect(scope.types["FooType"] != nil)
    #expect(scope.types["Point"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedWildcardImport() {
    let (context, program) = runImports(
        "import Foo.{Bar.*}", interfaces: [fooInterface()]
    )
    let scope = program.packageSymbol!.scope
    #expect(scope.types["Point"] != nil)
    #expect(scope.values["makePoint"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedUnresolvedTerminalReportsError() {
    let (context, _) = runImports("import Foo.{Bar.{Missing}}", interfaces: [fooInterface()])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(context.diagnositicEngine.diagnostics.contains {
        $0.message.contains("unresolved import 'Foo.Bar.Missing'")
    })
}

@Test func nestedUnresolvedSubmoduleReportsError() {
    let (context, _) = runImports("import Foo.{Nope.{Point}}", interfaces: [fooInterface()])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(context.diagnositicEngine.diagnostics.contains {
        $0.message.contains("unresolved import 'Foo.Nope.Point'")
    })
}

@Test func unresolvedRootReportsError() {
    let (context, _) = runImports("import Baz.Quux", interfaces: [fooInterface()])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(context.diagnositicEngine.diagnostics.contains {
        $0.message.contains("unresolved import 'Baz.Quux'")
    })
}

@Test func unresolvedTerminalReportsError() {
    let (context, _) = runImports("import Foo.Missing", interfaces: [fooInterface()])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(context.diagnositicEngine.diagnostics.contains {
        $0.message.contains("unresolved import 'Foo.Missing'")
    })
}

@Test func autoImportsTrussPackageWhenPresent() {
    let (context, program) = runImports("", interfaces: [trussInterface()])
    let scope = program.packageSymbol!.scope
    #expect(scope.types["Int"] != nil)
    #expect(scope.modules["Core"] != nil)
    #expect(scope.values["print"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func autoImportSkipsWhenTrussPackageAbsent() {
    let (context, program) = runImports("", interfaces: [fooInterface()])
    let scope = program.packageSymbol!.scope
    #expect(scope.types["FooType"] == nil)
    #expect(scope.modules["Bar"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func autoImportDoesNotShadowExplicitNames() {
    let (context, program) = runImports("import Foo.FooType", interfaces: [fooInterface(), trussInterface()])
    let scope = program.packageSymbol!.scope
    #expect(scope.types["FooType"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

private func interfaceFunctionKinds(of scope: InterfaceScope) -> [String: InterfaceFunctionKind] {
    var result: [String: InterfaceFunctionKind] = [:]
    for value in scope.values {
        if case let .Function(f) = value { result[f.name] = f.kind }
    }
    return result
}

private func nominalScope(_ name: String, in interface: ModuleInterface) -> InterfaceScope? {
    for type in interface.root.types {
        if case let .Nominal(n) = type, n.name == name { return n.scope }
    }
    return nil
}

private func symbolFunctionKind(of scope: Scope, _ name: String) -> Symbol.FunctionSymbol.Kind? {
    (scope.values[name]?.first as? Symbol.FunctionSymbol)?.kind
}

private func symbolVariableKind(of scope: Scope, _ name: String) -> Symbol.VariableSymbol.Kind? {
    (scope.values[name]?.first as? Symbol.VariableSymbol)?.kind
}

private func interfaceVariableKinds(of scope: InterfaceScope) -> [String: InterfaceVariableKind] {
    var result: [String: InterfaceVariableKind] = [:]
    for value in scope.values {
        if case let .Variable(v) = value { result[v.name] = v.kind }
    }
    return result
}

@Test func interfaceExtractorPreservesVariableKind() throws {
    let (context, programs) = runEnter([
        """
        public struct S { public var p: Int; public static var sp: Int }
        public var g: Int
        """,
    ])
    let interface = InterfaceExtractor(context: context).extract(from: programs[0])
    #expect(interfaceVariableKinds(of: interface.root) == ["g": .Global])
    let scope = try #require(nominalScope("S", in: interface))
    #expect(interfaceVariableKinds(of: scope) == ["p": .Property, "sp": .StaticProperty])
}

@Test func variableKindSurvivesEncodingAndLoading() throws {
    let interface = ModuleInterface(
        name: "V",
        root: InterfaceScope(values: [
            .Variable(InterfaceVariable(name: "g", kind: .Global)),
            .Variable(InterfaceVariable(name: "p", kind: .Property)),
            .Variable(InterfaceVariable(name: "sp", kind: .StaticProperty)),
        ])
    )
    let decoded = try TrussPackageDecoder().decode(TrussPackageEncoder(interface: interface).encode())
    #expect(decoded.interface == interface)

    let context = Context()
    InterfaceLoader(context: context).load(decoded.interface)
    let package = try #require(context.name2Package["V"])
    #expect(symbolVariableKind(of: package.scope, "g") == .Global)
    #expect(symbolVariableKind(of: package.scope, "p") == .Property)
    #expect(symbolVariableKind(of: package.scope, "sp") == .StaticProperty)
}

@Test func interfaceExtractorPreservesFunctionKind() throws {
    let (context, programs) = runEnter([
        """
        public class C {
            public init() {}
            public func method() {}
            public static func staticMethod() {}
        }
        public func free() {}
        """,
    ])
    let interface = InterfaceExtractor(context: context).extract(from: programs[0])
    #expect(interfaceFunctionKinds(of: interface.root) == ["free": .Function])
    let scope = try #require(nominalScope("C", in: interface))
    #expect(interfaceFunctionKinds(of: scope) == [
        "init": .Initializer, "method": .Method, "staticMethod": .StaticMethod,
    ])
}

@Test func functionKindSurvivesEncodingAndLoading() throws {
    let interface = ModuleInterface(
        name: "K",
        root: InterfaceScope(
            types: [
                .Nominal(InterfaceNominal(
                    kind: .ClassType,
                    name: "C",
                    scope: InterfaceScope(values: [
                        .Function(InterfaceFunction(
                            name: "deinit", labels: [], hasDefaults: [], isVararg: [], isVariadic: false,
                            kind: .Deinitializer
                        )),
                        .Function(InterfaceFunction(
                            name: "init", labels: [], hasDefaults: [], isVararg: [], isVariadic: false,
                            kind: .Initializer
                        )),
                        .Function(InterfaceFunction(
                            name: "method", labels: [], hasDefaults: [], isVararg: [], isVariadic: false,
                            kind: .Method
                        )),
                        .Function(InterfaceFunction(
                            name: "staticMethod", labels: [], hasDefaults: [], isVararg: [], isVariadic: false,
                            kind: .StaticMethod
                        )),
                    ])
                )),
            ],
            values: [.Function(InterfaceFunction(
                name: "free", labels: [], hasDefaults: [], isVararg: [], isVariadic: false
            ))]
        )
    )
    let decoded = try TrussPackageDecoder().decode(TrussPackageEncoder(interface: interface).encode())
    #expect(decoded.interface == interface)

    let context = Context()
    InterfaceLoader(context: context).load(decoded.interface)
    let package = try #require(context.name2Package["K"])
    let cls = try #require(package.scope.types["C"] as? Symbol.ClassSymbol)
    #expect(symbolFunctionKind(of: cls.scope, "init") == .Initializer)
    #expect(symbolFunctionKind(of: cls.scope, "deinit") == .Deinitializer)
    #expect(symbolFunctionKind(of: cls.scope, "method") == .Method)
    #expect(symbolFunctionKind(of: cls.scope, "staticMethod") == .StaticMethod)
    #expect(symbolFunctionKind(of: package.scope, "free") == .Function)
}

@Test func interfaceExtractorPreservesAccessors() throws {
    let (context, programs) = runEnter([
        """
        public struct S {
            public var p: Int { get { 0 } set { } }
            public var o: Int = 0 { willSet { } didSet { } }
            public static var sp: Int { get { 0 } }
        }
        """,
    ])
    let interface = InterfaceExtractor(context: context).extract(from: programs[0])
    let scope = try #require(nominalScope("S", in: interface))
    var accessors: [String: [InterfaceAccessorKind]] = [:]
    for value in scope.values {
        if case let .Variable(v) = value { accessors[v.name] = v.accessors }
    }
    #expect(accessors["p"] == [.Get, .Set])
    #expect(accessors["o"] == [.WillSet, .DidSet])
    #expect(accessors["sp"] == [.Get])
}

@Test func interfaceDumperPrintsAccessors() throws {
    let interface = ModuleInterface(
        name: "D",
        root: InterfaceScope(
            types: [
                .Nominal(InterfaceNominal(
                    kind: .StructType,
                    name: "S",
                    scope: InterfaceScope(values: [
                        .Variable(InterfaceVariable(
                            name: "p", kind: .Property, type: .Builtin("Int"),
                            accessors: [.Get, .Set]
                        )),
                        .Variable(InterfaceVariable(name: "g", kind: .Global, type: .Builtin("Int"))),
                    ])
                )),
            ]
        )
    )
    let text = ModuleInterfaceDumper().dump(interface)
    #expect(text.contains("var p: Int { get set }"))
    #expect(text.contains("var g: Int"))
}

@Test func accessorsSurviveEncodingAndLoading() throws {
    let interface = ModuleInterface(
        name: "A",
        root: InterfaceScope(
            types: [
                .Nominal(InterfaceNominal(
                    kind: .StructType,
                    name: "S",
                    scope: InterfaceScope(values: [
                        .Variable(InterfaceVariable(
                            name: "p", kind: .Property, type: .Builtin("Int"),
                            accessors: [.Get, .Set]
                        )),
                        .Variable(InterfaceVariable(
                            name: "sp", kind: .StaticProperty, type: .Builtin("Int"),
                            accessors: [.Get]
                        )),
                    ])
                )),
            ]
        )
    )
    let decoded = try TrussPackageDecoder().decode(TrussPackageEncoder(interface: interface).encode())
    #expect(decoded.interface == interface)

    let context = Context()
    InterfaceLoader(context: context).load(decoded.interface)
    let package = try #require(context.name2Package["A"])
    let type = try #require(package.scope.types["S"] as? Symbol.StructSymbol)
    let property = try #require(type.scope.values["p"]?.first as? Symbol.VariableSymbol)
    let getter = try #require(property.accessors[.Get])
    let setter = try #require(property.accessors[.Set])
    #expect(property.memberOf == type.id)
    #expect(getter.memberOf == type.id)
    #expect(setter.memberOf == type.id)
    #expect(getter.kind == .Method)
    let getterType = try #require(getter.functionType)
    let typeId = try #require(type.typeId)
    #expect(getterType.selfType === context.typeTable[typeId])
    #expect(getterType.parameters.isEmpty)
    #expect(getterType.returnType is TrussType.BuiltinType)
    let setterType = try #require(setter.functionType)
    #expect(setterType.selfType === getterType.selfType)
    #expect(setterType.parameters.count == 1)
    #expect(setterType.parameters[0].type is TrussType.BuiltinType)
    #expect(setterType.returnType is TrussType.VoidType)

    let staticProperty = try #require(type.scope.values["sp"]?.first as? Symbol.VariableSymbol)
    let staticGetter = try #require(staticProperty.accessors[.Get])
    #expect(staticGetter.kind == .StaticMethod)
    let staticGetterType = try #require(staticGetter.functionType)
    #expect(staticGetterType.selfType == nil)
    #expect(staticGetterType.returnType is TrussType.BuiltinType)
}
