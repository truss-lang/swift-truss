import TrussCore

final class VTableCollector {
    private let context: Context
    private let gen: GenerationContext
    private var filled: Set<Id.TIRMetadataId> = []

    init(context: Context, gen: GenerationContext) {
        self.context = context
        self.gen = gen
    }

    func collect() {
        for (_, entry) in context.typeTable {
            guard let classType = entry as? TrussType.ClassType else { continue }
            fill(classType)
        }
    }

    private func fill(_ classType: TrussType.ClassType) {
        guard let symbol = classType.symbol as? Symbol.ClassSymbol,
              let metadataId = gen.typeLower.metadataId(for: classType),
              let record = gen.registry.metadatas[metadataId],
              filled.insert(metadataId).inserted
        else {
            return
        }
        if let superclass = symbol.superclass,
           let superTypeId = superclass.typeId,
           let superType = context.typeTable[superTypeId] as? TrussType.ClassType
        {
            fill(superType)
            if let superMetadataId = gen.typeLower.metadataId(for: superType),
               let superRecord = gen.registry.metadatas[superMetadataId]
            {
                record.vtable = superRecord.vtable
            }
        }
        for (_, entries) in symbol.scope.values.sorted(by: { $0.key < $1.key }) {
            for entry in entries {
                guard let function = entry as? Symbol.FunctionSymbol, isVirtual(function) else {
                    continue
                }
                register(function, metadataId: metadataId, record: record)
            }
        }
    }

    private func isVirtual(_ function: Symbol.FunctionSymbol) -> Bool {
        function.kind == .Method && !function.isStatic && !function.isFinal && !function.isAbstract
    }

    private func register(
        _ function: Symbol.FunctionSymbol, metadataId: Id.TIRMetadataId, record: TIR.MetadataRecord
    ) {
        guard let tirFunction = gen.functionsBySymbol[function.id] else { return }
        let signature = methodSignature(function)
        if let index = record.vtable.firstIndex(where: {
            $0.name == function.name && $0.signature == signature
        }) {
            record.vtable[index].function = tirFunction.id
            gen.virtualMethodSlots[function.id] = VirtualMethodSlot(
                metadata: metadataId, index: index
            )
        } else {
            record.vtable.append(
                TIR.VTableEntry(name: function.name, signature: signature, function: tirFunction.id)
            )
            gen.virtualMethodSlots[function.id] = VirtualMethodSlot(
                metadata: metadataId, index: record.vtable.count - 1
            )
        }
    }

    private func methodSignature(_ function: Symbol.FunctionSymbol) -> Id.TIRTypeId {
        let parameters = (function.functionType?.parameters ?? []).map {
            gen.typeLower.lower($0.type).id
        }
        let returnType = function.functionType.map { gen.typeLower.lower($0.returnType).id }
            ?? gen.registry.voidType().id
        return gen.registry.functionType(
            parameters: parameters, returnType: returnType,
            isVariadic: function.functionType?.isVariadic ?? false
        ).id
    }
}
