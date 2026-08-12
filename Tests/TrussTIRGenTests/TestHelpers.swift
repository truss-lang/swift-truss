import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax
import TrussTIRGen

func parseProgram(_ source: String) -> AST.Program {
    let context = Context()
    let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
    context.register(source: src)
    let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
    let preprocessed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig()
    )
    return Parser(context: context, packageName: "main", preprocessed).parse()
}

func runPipeline(_ source: String, installBuiltin: Bool = false) -> (Context, AST.Program) {
    let context = Context()
    if installBuiltin {
        Builtin.install(context: context)
    }
    let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
    context.register(source: src)
    let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
    let preprocessed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig()
    )
    var program = Parser(context: context, packageName: "main", preprocessed).parse()
    DeclCollector(context: context).visitProgram(program)
    Enter(context: context).visitProgram(program)
    let merger = MergePass(context: context)
    merger.visitProgram(program)
    merger.resolvePending()
    NameResolver(context: context).visitProgram(program)
    let table = OperatorTable()
    TrussOperator.DeclCollector(table: table, context: context).visitProgram(program)
    PrecedenceResolver(table: table, context: context).resolve()
    let folder = ExpressionFolder(context: context, table: table)
    program = folder.rewrite(program)
    TypeBuilder(context: context).visitProgram(program)
    TypeChecker(context: context).visitProgram(program)
    return (context, program)
}

func dumpTIR(_ source: String, installBuiltin: Bool = false) -> String {
    let (context, program) = runPipeline(source, installBuiltin: installBuiltin)
    let module = TIRGen(context: context).generate(program)
    return TIR.Dumper().dump(module)
}
