import TrussCore

final class GenerationContext {
    let context: Context
    let registry: TIR.Registry
    let builder: TIR.Builder
    let typeLower: TypeLower
    let index: DeclarationIndex
    var module: TIR.Module
    var metadataGlobals: [Id.TIRTypeId: TIR.GlobalVariable] = [:]
    var errUnionByFunction: [Id.SymbolId: TIRType.EnumType] = [:]

    init(
        context: Context, registry: TIR.Registry, builder: TIR.Builder, typeLower: TypeLower,
        index: DeclarationIndex, module: TIR.Module
    ) {
        self.context = context
        self.registry = registry
        self.builder = builder
        self.typeLower = typeLower
        self.index = index
        self.module = module
    }
}
