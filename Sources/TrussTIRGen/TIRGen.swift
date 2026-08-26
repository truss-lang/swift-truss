import TrussCore

public final class TIRGen {
    private let gen: GenerationContext
    private let collector: TypeCollector
    private let functionCollector: FunctionCollector
    private let witnessCollector: WitnessCollector
    private let emitter: TIREmitter

    public init(context: Context) {
        gen = GenerationContext(context: context)
        collector = TypeCollector(context: context)
        functionCollector = FunctionCollector(context: context, gen: gen)
        witnessCollector = WitnessCollector(context: context, gen: gen)
        emitter = TIREmitter(context: context, gen: gen)
    }

    public func generate(_ program: AST.Program) -> TIR.Module {
        generateAll([program])[0]
    }

    public func generateAll(_ programs: [AST.Program]) -> [TIR.Module] {
        for program in programs {
            collector.collect(program)
        }
        gen.typeLower.setStoredProperties(collector.storedProperties)
        gen.typeLower.setEnumCases(collector.enumCases)
        let modules: [TIR.Module] = programs.map {
            let module = gen.makeModule()
            functionCollector.collect(in: $0)
            return module
        }
        witnessCollector.collect()
        for program in programs {
            gen.builder = nil
            gen.env = [:]
            gen.modulePathStack = []
            gen.externContextStack = []
            gen.collectTypeStack = []
            gen.typeLower.setModulePath([])
            emitter.visitProgram(program)
        }
        return modules
    }
}
