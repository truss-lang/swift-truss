import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussSemantics
import TrussSyntax

func runEnter(_ sources: [String]) -> (Context, [AST.Program]) {
    let context = Context()
    var programs: [AST.Program] = []
    for source in sources {
        let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
        context.register(source: src)
        let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
        let preprocessed = Preprocessor(context: context).process(
            lexerResult, config: PreprocessorConfig())
        let program = Parser(context: context, packageName: "main", preprocessed).parse()
        programs.append(program)
    }
    for program in programs {
        DeclCollector(context: context).visitProgram(program)
    }
    for program in programs {
        Enter(context: context).visitProgram(program)
    }
    let merger = MergePass(context: context)
    for program in programs {
        merger.visitProgram(program)
    }
    merger.resolvePending()
    return (context, programs)
}

func parseProgram(_ source: String) -> AST.Program {
    let (context, programs) = runEnter([source])
    NameResolver(context: context).visitProgram(programs[0])
    return programs[0]
}
