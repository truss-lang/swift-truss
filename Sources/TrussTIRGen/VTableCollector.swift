import TrussCore

final class VTableCollector {
    private let context: Context
    private let gen: GenerationContext
    private var filled: Set<Id.TIRMetadataId> = []
    private var chainedDeinitializers: [ObjectIdentifier: TIR.Function] = [:]

    init(context: Context, gen: GenerationContext) {
        self.context = context
        self.gen = gen
    }

    func collect() {
        let classTypes = context.typeTable.values.compactMap { $0 as? TrussType.ClassType }
            .sorted { $0.name < $1.name }
        for classType in classTypes {
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
        registerDeinitializer(symbol, classType: classType, record: record)
        for (_, entries) in symbol.scope.values.sorted(by: { $0.key < $1.key }) {
            for entry in entries {
                if let function = entry as? Symbol.FunctionSymbol, isVirtual(function) {
                    register(function, metadataId: metadataId, record: record)
                } else if let variable = entry as? Symbol.VariableSymbol {
                    let accessors = variable.accessors.keys.sorted {
                        accessorRank($0) < accessorRank($1)
                    }.compactMap { variable.accessors[$0] }
                    for f in accessors {
                        if isVirtual(f) {
                            register(f, metadataId: metadataId, record: record)
                        }
                    }
                }
            }
        }
        record.hasRealDeinitializer = hasRealDeinitializer(record)
    }

    private func hasRealDeinitializer(_ record: TIR.MetadataRecord) -> Bool {
        guard let entry = record.vtable.first, entry.name == deinitializerSlotName else {
            return false
        }
        return !gen.sharedNoOpDeinitializerIds.contains(entry.function)
    }

    private func isVirtual(_ function: Symbol.FunctionSymbol) -> Bool {
        function.kind == .Method && function.kind != .StaticMethod && !function.isFinal && !function.isAbstract
    }

    private func accessorRank(_ kind: AST.Accessor.Kind) -> Int {
        switch kind {
        case .Get: 0
        case .Set: 1
        case .WillSet: 2
        case .DidSet: 3
        }
    }

    private func register(
        _ function: Symbol.FunctionSymbol, metadataId: Id.TIRMetadataId, record: TIR.MetadataRecord
    ) {
        guard let tirFunction = gen.functionsBySymbol[function.id] else {
            return
        }
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

    private func registerDeinitializer(
        _ symbol: Symbol.ClassSymbol, classType: TrussType.ClassType, record: TIR.MetadataRecord
    ) {
        let inherited = record.vtable.first?.name == deinitializerSlotName
        guard let entry = deinitializerEntry(
            for: symbol, classType: classType, inherited: inherited,
            inheritedDeinitializer: inherited ? record.vtable.first?.function : nil
        ) else {
            return
        }
        if inherited {
            record.vtable[0] = entry
        } else {
            record.vtable.insert(entry, at: 0)
        }
    }

    private func deinitializerEntry(
        for symbol: Symbol.ClassSymbol, classType: TrussType.ClassType, inherited: Bool,
        inheritedDeinitializer: Id.TIRFunctionId?
    ) -> TIR.VTableEntry? {
        if let deinitializer = symbol.deinitializer,
           let tirFunction = gen.functionsBySymbol[deinitializer.id]
        {
            if let inheritedDeinitializer,
               let chained = chainedDeinitializer(
                   for: symbol, classType: classType, body: tirFunction,
                   base: inheritedDeinitializer
               )
            {
                return TIR.VTableEntry(
                    name: deinitializerSlotName, signature: methodSignature(deinitializer),
                    function: chained.id
                )
            }
            return TIR.VTableEntry(
                name: deinitializerSlotName, signature: methodSignature(deinitializer),
                function: tirFunction.id
            )
        }
        if let fieldDeinitializer = fieldDeinitializer(
            for: symbol, classType: classType, inheritedDeinitializer: inheritedDeinitializer
        ) {
            return sharedNoOpDeinitializerEntry(fieldDeinitializer)
        }
        if let shared = gen.sharedNoOpDeinitializerByClass[ObjectIdentifier(symbol)] {
            return sharedNoOpDeinitializerEntry(shared)
        }
        guard !inherited else {
            return nil
        }
        guard let shared = gen.sharedNoOpDeinitializer(sourceRange: TIR.unknownSourceRange) else {
            return nil
        }
        return sharedNoOpDeinitializerEntry(shared)
    }

    private func chainedDeinitializer(
        for symbol: Symbol.ClassSymbol, classType: TrussType.ClassType,
        body: TIR.Function, base: Id.TIRFunctionId
    ) -> TIR.Function? {
        let key = ObjectIdentifier(symbol)
        if let existing = chainedDeinitializers[key] {
            return existing
        }
        guard let module = owningModule(of: symbol),
              let baseFunction = gen.registry.functions[base],
              let baseSelfType = baseFunction.parameters.first?.ty,
              let selfParameter = body.parameters.first
        else {
            return nil
        }
        let function = module.addFunction(
            name: fieldDeinitializerName + classType.name + "$chain",
            parameters: [TIR.Parameter(ty: selfParameter.ty, name: "self")],
            returnType: gen.registry.voidType().id, isVariadic: false, isExtern: false,
            callingConvention: nil, parameterOwnership: [.Guaranteed]
        )
        let entry = function.addBasicBlock(name: "entry")
        let parameter = function.parameters[0]
        let bodyReference = TIR.FunctionRef(
            functionId: body.id, ty: body.ty, name: body.name
        )
        entry.instructions.append(
            TIR.Call(
                callee: bodyReference, arguments: [parameter], ty: gen.registry.voidType().id,
                name: "", hasResult: false
            )
        )
        let upcast = TIR.Upcast(value: parameter, targetType: baseSelfType, name: "self")
        entry.instructions.append(upcast)
        let baseReference = TIR.FunctionRef(
            functionId: baseFunction.id, ty: baseFunction.ty, name: baseFunction.name
        )
        entry.instructions.append(
            TIR.Call(
                callee: baseReference, arguments: [upcast.result], ty: gen.registry.voidType().id,
                name: "", hasResult: false
            )
        )
        entry.instructions.append(TIR.Return())
        chainedDeinitializers[key] = function
        return function
    }

    private func fieldDeinitializer(
        for symbol: Symbol.ClassSymbol, classType: TrussType.ClassType,
        inheritedDeinitializer: Id.TIRFunctionId?
    ) -> TIR.Function? {
        let key = ObjectIdentifier(symbol)
        if let existing = gen.fieldDeinitializers[key] {
            return existing
        }
        let lowered = gen.typeLower.lower(classType)
        guard let tirClass = gen.registry.types[lowered.id] as? TIRType.ClassType,
              let module = owningModule(of: symbol)
        else {
            return nil
        }
        let ownFields = tirClass.fields.dropFirst(inheritedFieldCount(of: symbol, classType: classType))
        guard ownFields.contains(where: { hasReferenceType($0.type, visited: []) }) else {
            return nil
        }
        let pointer = gen.registry.pointerType(pointee: lowered.id)
        let selfParameter = TIR.Parameter(ty: pointer.id, name: "self")
        let function = module.addFunction(
            name: fieldDeinitializerName + tirClass.name,
            parameters: [selfParameter],
            returnType: gen.registry.voidType().id, isVariadic: false, isExtern: false,
            callingConvention: nil, parameterOwnership: [.Guaranteed]
        )
        let entry = function.addBasicBlock(name: "entry")
        if let inheritedDeinitializer, let base = gen.registry.functions[inheritedDeinitializer],
           let baseSelfType = base.parameters.first?.ty
        {
            let reference = TIR.FunctionRef(
                functionId: base.id, ty: base.ty, name: base.name
            )
            let upcast = TIR.Upcast(value: selfParameter, targetType: baseSelfType, name: "self")
            entry.instructions.append(upcast)
            entry.instructions.append(
                TIR.Call(
                    callee: reference, arguments: [upcast.result], ty: gen.registry.voidType().id,
                    name: "", hasResult: false
                )
            )
        }
        entry.instructions.append(TIR.Return())
        gen.fieldDeinitializers[key] = function
        return function
    }

    private func inheritedFieldCount(
        of symbol: Symbol.ClassSymbol, classType: TrussType.ClassType
    ) -> Int {
        var superclass = symbol.superclass
        while let current = superclass {
            if let typeId = current.typeId, let type = context.typeTable[typeId] {
                let lowered = gen.typeLower.lower(type).id
                if let inherited = gen.registry.types[lowered] as? TIRType.ClassType {
                    return inherited.fields.count
                }
            }
            superclass = current.superclass
        }
        return 0
    }

    private func owningModule(of symbol: Symbol.ClassSymbol) -> TIR.Module? {
        gen.classModules[ObjectIdentifier(symbol)]
    }

    private func hasReferenceType(_ id: Id.TIRTypeId, visited: Set<Id.TIRTypeId>) -> Bool {
        guard !visited.contains(id), let type = gen.registry.types[id] else {
            return false
        }
        switch type {
        case is TIRType.ClassType:
            return true
        case let pointer as TIRType.PointerType:
            return gen.registry.types[pointer.pointee] is TIRType.ClassType
        case let structType as TIRType.StructType:
            let nested = visited.union([id])
            return structType.fields.contains { hasReferenceType($0.type, visited: nested) }
        default:
            return false
        }
    }

    private func sharedNoOpDeinitializerEntry(_ function: TIR.Function) -> TIR.VTableEntry {
        TIR.VTableEntry(
            name: deinitializerSlotName, signature: voidDeinitializerSignature,
            function: function.id
        )
    }

    private var voidDeinitializerSignature: Id.TIRTypeId {
        gen.registry.functionType(
            parameters: [], returnType: gen.registry.voidType().id, isVariadic: false,
            parameterOwnership: ownedConventions(count: 0)
        ).id
    }

    private func methodSignature(_ function: Symbol.FunctionSymbol) -> Id.TIRTypeId {
        let parameters = (function.functionType?.parameters ?? []).map {
            gen.typeLower.lower($0.type).id
        }
        let returnType = function.functionType.map { gen.typeLower.lower($0.returnType).id }
            ?? gen.registry.voidType().id
        return gen.registry.functionType(
            parameters: parameters, returnType: returnType,
            isVariadic: function.functionType?.isVariadic ?? false,
            parameterOwnership: ownedConventions(count: parameters.count)
        ).id
    }
}
