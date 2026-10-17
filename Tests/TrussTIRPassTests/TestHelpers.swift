import SwiftBetterDiagnostic
import TrussCore
import TrussOperator
import TrussSemantics
import TrussSyntax
import TrussTIRGen
import TrussTIRPass

func runTIRPass(_ source: String, filepath: String = "test.truss") -> (Context, TIR.Module) {
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
    ImportProcessor(context: context).visitProgram(program)
    let desugar = OptionalDesugarPass()
    programs = programs.map { desugar.rewrite($0) }
    Enter(context: context).visitProgram(program)
    let merger = MergePass(context: context)
    merger.visitProgram(program)
    merger.resolvePending()
    NameResolver(context: context).visitProgram(program)
    let table = OperatorTable()
    TrussOperator.DeclCollector(table: table, context: context).visitProgram(program)
    OperatorImportProcessor(table: table, context: context).visitProgram(program)
    PrecedenceResolver(table: table, context: context).resolve()
    let folder = ExpressionFolder(context: context, table: table)
    programs = programs.map { folder.rewrite($0) }
    TypeBuilder(context: context).visitProgram(program)
    TypeChecker(context: context).checkAll(programs)
    AttributeChecker(context: context).visitProgram(program)
    ModifierChecker(context: context).visitProgram(program)
    AccessChecker(context: context).visitProgram(program)
    ControlFlowChecker(context: context).visitProgram(program)
    UnusedDeclarationChecker(context: context).checkAll(programs)
    let modules = TIRGen(context: context).generateAll(programs)
    let pass = TIRPass()
    let lowered = modules.map { pass.run(on: $0).module }
    return (context, lowered[0])
}

func strictFailures(_ context: Context, _ module: TIR.Module) -> [TIR.Verifier.Failure] {
    TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
}

func ownershipFailures(_ context: Context, _ module: TIR.Module) -> [TIR.Verifier.Failure] {
    strictFailures(context, module).filter { $0.kind == .Ownership }
}

func allInstructions(of module: TIR.Module) -> [TIR.Instruction] {
    module.functions.flatMap { function in
        function.basicBlocks.flatMap(\.instructions)
    }
}

func function(named name: String, in module: TIR.Module) -> TIR.Function? {
    module.functions.first { $0.name.contains(name) }
}

func allocations(ofType type: Id.TIRTypeId, in function: TIR.Function) -> [TIR.AllocStack] {
    function.basicBlocks.flatMap(\.instructions).compactMap { instruction in
        guard let allocation = instruction as? TIR.AllocStack,
              allocation.allocatedType == type
        else {
            return nil
        }
        return allocation
    }
}

func consumes(of value: TIR.Value, in function: TIR.Function) -> [TIR.Instruction] {
    function.basicBlocks.flatMap(\.instructions).filter { instruction in
        switch instruction {
        case let i as TIR.Release:
            i.value === value
        case let i as TIR.Destroy:
            i.value === value
        default:
            false
        }
    }
}

func consumes(of value: TIR.Value, in module: TIR.Module) -> [TIR.Instruction] {
    module.functions.flatMap { consumes(of: value, in: $0) }
}

func retains(of value: TIR.Value, in function: TIR.Function) -> [TIR.Retain] {
    function.basicBlocks.flatMap(\.instructions).compactMap { instruction in
        guard let retain = instruction as? TIR.Retain, retain.value === value else {
            return nil
        }
        return retain
    }
}

func releases(of value: TIR.Value, in function: TIR.Function) -> [TIR.Release] {
    function.basicBlocks.flatMap(\.instructions).compactMap { instruction in
        guard let release = instruction as? TIR.Release, release.value === value else {
            return nil
        }
        return release
    }
}

func deallocations(of value: TIR.Value, in function: TIR.Function) -> [TIR.DeallocStack] {
    function.basicBlocks.flatMap(\.instructions).compactMap { instruction in
        guard let deallocation = instruction as? TIR.DeallocStack, deallocation.value === value else {
            return nil
        }
        return deallocation
    }
}

func block(containing instruction: TIR.Instruction, in function: TIR.Function) -> TIR.BasicBlock? {
    function.basicBlocks.first { block in
        block.instructions.contains { $0 === instruction }
    }
}

func loads(of value: TIR.Value, in function: TIR.Function) -> [TIR.Load] {
    function.basicBlocks.flatMap(\.instructions).compactMap { instruction in
        guard let load = instruction as? TIR.Load, load.ptr === value else {
            return nil
        }
        return load
    }
}

func dischargedLoads(of slot: TIR.Value, in function: TIR.Function) -> [TIR.Load] {
    let instructions = allInstructions(of: function)
    return loads(of: slot, in: function).filter { load in
        instructions.contains { instruction in
            switch instruction {
            case let i as TIR.Release:
                i.value === load.result
            case let i as TIR.Destroy:
                i.value === load.result
            default:
                false
            }
        }
    }
}

func instructionIndex(of instruction: TIR.Instruction, in function: TIR.Function) -> Int? {
    let instructions = function.basicBlocks.flatMap(\.instructions)
    return instructions.firstIndex { $0 === instruction }
}

func allInstructions(of function: TIR.Function) -> [TIR.Instruction] {
    function.basicBlocks.flatMap(\.instructions)
}
