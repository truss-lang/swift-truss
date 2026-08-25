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

private func fooInterface() -> ModuleInterface {
    ModuleInterface(
        name: "Foo",
        root: InterfaceScope(
            modules: [
                InterfaceModule(
                    name: "Bar",
                    scope: InterfaceScope(
                        types: [.nominal(InterfaceNominal(kind: .structType, name: "Point"))],
                        values: [.function(InterfaceFunction(
                            name: "makePoint", labels: [nil], hasDefaults: [false],
                            isVararg: [false], isVariadic: false, isStatic: true
                        ))]
                    )
                ),
            ],
            types: [.nominal(InterfaceNominal(kind: .structType, name: "FooType"))]
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
