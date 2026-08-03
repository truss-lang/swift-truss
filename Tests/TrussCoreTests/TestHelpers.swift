import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSemantics
import TrussSyntax

func parseProgram(_ source: String, semantic: Bool = false) -> AST.Program {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let lexerResult = Lexer(input: CharStream(content: source, id: Id.SourceId(id: 0))).parse()
    let preprocessed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig())
    let program = Parser(context: context, packageName: "main", preprocessed).parse()
    if semantic {
        Enter(context: context).visitProgram(program)
        NameResolver(context: context).visitProgram(program)
    }
    return program
}

func dumpProgram(_ source: String, semantic: Bool = false) -> String {
    ASTDumper().dump(parseProgram(source, semantic: semantic))
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
