import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax

func runEnter(_ sources: [String], installBuiltin: Bool = false) -> (Context, [AST.Program]) {
    let context = Context()
    if installBuiltin {
        Builtin.install(context: context)
    }
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

func runTypeBuilder(_ sources: [String], installBuiltin: Bool = false)
    -> (Context, [AST.Program])
{
    let (context, programs) = runEnter(sources, installBuiltin: installBuiltin)
    for program in programs {
        NameResolver(context: context).visitProgram(program)
    }
    for program in programs {
        TypeBuilder(context: context).visitProgram(program)
    }
    return (context, programs)
}

func runTypeChecker(_ sources: [String], installBuiltin: Bool = false)
    -> (Context, [AST.Program])
{
    let (context, initialPrograms) = runEnter(sources, installBuiltin: installBuiltin)
    var programs = initialPrograms
    for program in programs {
        NameResolver(context: context).visitProgram(program)
    }
    let table = OperatorTable()
    for program in programs {
        TrussOperator.DeclCollector(table: table, context: context).visitProgram(program)
    }
    PrecedenceResolver(table: table, context: context).resolve()
    let folder = ExpressionFolder(context: context, table: table)
    programs = programs.map { folder.rewrite($0) }
    for program in programs {
        TypeBuilder(context: context).visitProgram(program)
    }
    for program in programs {
        TypeChecker(context: context).visitProgram(program)
    }
    return (context, programs)
}

func runChecks(_ sources: [String]) -> (Context, [AST.Program]) {
    let (context, programs) = runTypeChecker(sources)
    for program in programs {
        ModifierChecker(context: context).visitProgram(program)
    }
    for program in programs {
        AccessChecker(context: context).visitProgram(program)
    }
    return (context, programs)
}
