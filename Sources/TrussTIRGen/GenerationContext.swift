import TrussCore

final class GenerationContext {
    let context: Context
    let mangler: TypeMangler
    let typeLower: TypeLower
    let registry: TIR.Registry
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
    var deinitFunctions: [ObjectIdentifier: TIR.Function] = [:]
    var deinitOwners: [ObjectIdentifier: Symbol.NominalTypeSymbol] = [:]

    init(context: Context, mangler: TypeMangler, typeLower: TypeLower) {
        self.context = context
        self.mangler = mangler
        self.typeLower = typeLower
        registry = TIR.Registry()
        typeLower.registry = registry
    }

    func makeModule() -> TIR.Module {
        let module = TIR.Module(registry: registry)
        modules.append(module)
        currentModule = module
        typeLower.registry = registry
        return module
    }
}
