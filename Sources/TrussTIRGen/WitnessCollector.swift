import TrussCore

final class WitnessCollector {
    private let context: Context
    private let gen: GenerationContext

    init(context: Context, gen: GenerationContext) {
        self.context = context
        self.gen = gen
    }

    func collect() {
        for (concrete, protocolSymbol) in gen.typeLower.conformancePairs() {
            guard let typeId = protocolSymbol.typeId,
                  let protocolType = context.typeTable[typeId] as? TrussType.ProtocolType,
                  let symbol = concrete.symbol
            else {
                continue
            }
            let protocolId = gen.typeLower.protocolId(for: protocolType)
            let concreteId = gen.typeLower.lower(concrete).id
            let witness = gen.registry.addWitness(protocolId: protocolId, concreteType: concreteId)
            guard let protocolRecord = gen.registry.protocols[protocolId] else { continue }
            for requirement in protocolRecord.requirements {
                if let function = resolveFunction(requirement, in: symbol) {
                    witness.entries.append(
                        TIR.WitnessEntry(name: requirement, function: function.id)
                    )
                }
            }
            fillMetadataConformance(symbol, protocolId: protocolId)
        }
    }

    private func resolveFunction(
        _ name: String, in type: Symbol.NominalTypeSymbol
    ) -> TIR.Function? {
        var current: Symbol.NominalTypeSymbol? = type
        while let currentType = current {
            if let entries = currentType.scope.values[name] {
                if let functionSymbol = entries.first as? Symbol.FunctionSymbol,
                   let function = gen.functionsBySymbol[functionSymbol.id]
                {
                    return function
                }
                if let variableSymbol = entries.first as? Symbol.VariableSymbol,
                   let getter = gen.accessorFunctions[variableSymbol.id]?.getter
                {
                    return getter
                }
            }
            current = (currentType as? Symbol.ClassSymbol)?.superclass
        }
        return nil
    }

    private func fillMetadataConformance(
        _ symbol: Symbol.NominalTypeSymbol, protocolId: Id.TIRProtocolId
    ) {
        guard symbol is Symbol.ClassSymbol,
              let typeId = symbol.typeId,
              let type = context.typeTable[typeId] as? TrussType.ClassType,
              let metadataId = gen.typeLower.metadataId(for: type),
              let record = gen.registry.metadatas[metadataId]
        else {
            return
        }
        if !record.conformedProtocols.contains(protocolId) {
            record.conformedProtocols.append(protocolId)
        }
    }
}
