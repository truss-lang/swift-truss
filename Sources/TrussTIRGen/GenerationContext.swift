import TrussCore

struct AccessorPair {
    var getter: TIR.Function?
    var setter: TIR.Function?
    var willSet: TIR.Function?
    var didSet: TIR.Function?
}

final class GenerationContext {
    let context: Context
    let registry: TIR.Registry
    let mangler: Mangler
    let typeLower: TypeLower
    var modules: [TIR.Module] = []
    var currentModule: TIR.Module?
    var builder: TIR.Builder?
    var functionsBySymbol: [Id.SymbolId: TIR.Function] = [:]
    var globalsBySymbol: [Id.SymbolId: TIR.GlobalVariable] = [:]
    var env: [Id.SymbolId: TIR.Value] = [:]
    var modulePathStack: [Symbol.ModuleSymbol] = []
    var externContextStack: [String] = []
    var collectTypeStack: [Symbol.NominalTypeSymbol] = []
    var staticVariableSymbols: Set<Id.SymbolId> = []
    var initFunctionsByType: [Id.SymbolId: TIR.Function] = [:]
    var accessorFunctions: [Id.SymbolId: AccessorPair] = [:]
    var deinitFunctions: [ObjectIdentifier: TIR.Function] = [:]
    var deinitOwners: [ObjectIdentifier: Symbol.NominalTypeSymbol] = [:]
    var existentialBoxes: [Id.SymbolId: ExistentialBox] = [:]

    struct ExistentialBox {
        let witnesses: [Id.TIRProtocolId: Id.TIRWitnessId]
        let concreteType: Id.TIRTypeId
        let containerType: Id.TIRTypeId
    }

    init(context: Context) {
        self.context = context
        registry = TIR.Registry()
        mangler = Mangler(context: context)
        typeLower = TypeLower(context: context, mangler: mangler, registry: registry)
    }

    func makeModule() -> TIR.Module {
        let module = TIR.Module(registry: registry)
        modules.append(module)
        currentModule = module
        return module
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
