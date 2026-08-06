import SwiftGraph
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax

func runDeclCollector(_ sources: [String]) -> (Context, OperatorTable, [AST.Program]) {
    let context = Context()
    let table = OperatorTable()
    var programs: [AST.Program] = []
    for source in sources {
        let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
        context.register(source: src)
        let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
        let preprocessed = Preprocessor(context: context).process(
            lexerResult, config: PreprocessorConfig()
        )
        let program = Parser(context: context, packageName: "main", preprocessed).parse()
        programs.append(program)
    }
    for program in programs {
        TrussOperator.DeclCollector(table: table, context: context).visitProgram(program)
    }
    return (context, table, programs)
}

func runResolved(_ sources: [String]) -> (Context, OperatorTable, [AST.Program]) {
    let (context, table, programs) = runDeclCollector(sources)
    PrecedenceResolver(table: table, context: context).resolve()
    return (context, table, programs)
}

func runBuilt(_ sources: [String]) -> (Context, UnweightedGraph<PrecedenceGroupInfo>) {
    let (context, table, _) = runDeclCollector(sources)
    PrecedenceResolver(table: table, context: context).resolve()
    let graph = PrecedenceGraphBuilder(table: table, context: context).build()
    return (context, graph)
}

func runFolded(_ sources: [String]) -> (Context, OperatorTable, [AST.Program]) {
    let (context, table, programs) = runDeclCollector(sources)
    for program in programs {
        TrussSemantics.DeclCollector(context: context).visitProgram(program)
    }
    for program in programs {
        Enter(context: context).visitProgram(program)
    }
    let merger = MergePass(context: context)
    for program in programs {
        merger.visitProgram(program)
    }
    merger.resolvePending()
    for program in programs {
        NameResolver(context: context).visitProgram(program)
    }
    PrecedenceResolver(table: table, context: context).resolve()
    let folder = ExpressionFolder(context: context, table: table)
    let folded = programs.map { folder.rewrite($0) }
    return (context, table, folded)
}
