import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSemantics
import TrussSyntax

func parseProgram(_ source: String) -> AST.Program {
    let context = Context()
    let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
    context.register(source: src)
    let lexerResult = Lexer(input: CharStream(content: source, id: Id.SourceId(id: 0))).parse()
    let preprocessed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig())
    let program = Parser(context: context, packageName: "main", preprocessed).parse()
    Enter(context: context).visitProgram(program)
    NameResolver(context: context).visitProgram(program)
    return program
}
