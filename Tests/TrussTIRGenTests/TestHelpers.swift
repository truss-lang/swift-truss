import SwiftBetterDiagnostic
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax
import TrussTIRGen

func runTIRGen(_ source: String, filepath: String = "test.truss") -> (Context, TIR.Module) {
    let context = Context()
    Builtin.install(context: context)
    let src = Source(id: context.nextSourceId, filepath: filepath, content: source)
    context.register(source: src)
    let lexerResult = Lexer(input: CharStream(content: source, id: src.id)).parse()
    let preprocessed = Preprocessor(context: context).process(
        lexerResult, config: PreprocessorConfig()
    )
    let program = Parser(context: context, packageName: "main", preprocessed).parse()
    var programs = [program]
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
    programs = programs.map { folder.rewrite($0) }
    TypeBuilder(context: context).visitProgram(program)
    TypeChecker(context: context).visitProgram(program)
    AttributeChecker(context: context).visitProgram(program)
    ModifierChecker(context: context).visitProgram(program)
    AccessChecker(context: context).visitProgram(program)
    ControlFlowChecker(context: context).visitProgram(program)
    UnusedDeclarationChecker(context: context).checkAll(programs)
    let modules = TIRGen(context: context).generateAll(programs)
    return (context, modules[0])
}

func isUnknownSourceRange(_ range: SourceRange) -> Bool {
    range.start.buffer.filePath == TIR.unknownSourceRange.start.buffer.filePath
}

func instructions(of module: TIR.Module) -> [TIR.Instruction] {
    module.functions.flatMap { function in
        function.basicBlocks.flatMap(\.instructions)
    }
}

func function(named name: String, in module: TIR.Module) -> TIR.Function? {
    module.functions.first { $0.name.contains(name) }
}
