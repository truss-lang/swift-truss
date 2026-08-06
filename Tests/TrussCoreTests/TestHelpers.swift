import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSemantics
import TrussSyntax

func parseProgram(_ source: String, semantic: Bool = false) -> AST.Program {
    let context = Context()
    let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
    context.register(source: src)
    let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
    let preprocessed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig()
    )
    let program = Parser(context: context, packageName: "main", preprocessed).parse()
    if semantic {
        DeclCollector(context: context).visitProgram(program)
        Enter(context: context).visitProgram(program)
        let merger = MergePass(context: context)
        merger.visitProgram(program)
        merger.resolvePending()
        NameResolver(context: context).visitProgram(program)
        TypeBuilder(context: context).visitProgram(program)
    }
    return program
}

func dumpProgram(_ source: String, semantic: Bool = false) -> String {
    AST.Dumper().dump(parseProgram(source, semantic: semantic))
}

func printProgram(_ source: String) -> String {
    SourcePrinter().print(parseProgram(source))
}

func assertRoundTrip(_ source: String) {
    let original = dumpProgram(source)
    let printed = printProgram(source)
    let reparsed = dumpProgram(printed)
    #expect(
        reparsed == original,
        "round-trip failed for: \(source)\nprinted:\n\(printed)\nexpected dump:\n\(original)\nactual dump:\n\(reparsed)"
    )
}
