import TrussCore

final class TypeLower {
    private let context: Context
    private var nominalInProgress: [Id.ASTTypeId: TIRType.NominalType] = [:]
    private var storedProperties: [Id.ASTTypeId: [(name: String, type: TrussType.TrussType)]] = [:]
    private var enumCases: [Id.ASTTypeId: [(name: String, types: [TrussType.TrussType])]] = [:]
    private var optionalEnums: [Id.TIRTypeId: TIRType.EnumType] = [:]
    private var metadataByType: [Id.TIRTypeId: Id.TIRMetadataId] = [:]
    private let mangler: Mangler
    private var modulePath: [Symbol.ModuleSymbol] = []
    private unowned let registry: TIR.Registry

    init(context: Context, mangler: Mangler, registry: TIR.Registry) {
        self.context = context
        self.mangler = mangler
        self.registry = registry
    }

    func setStoredProperties(_ stored: [Id.ASTTypeId: [(name: String, type: TrussType.TrussType)]]) {
        storedProperties = stored
    }

    func setEnumCases(_ cases: [Id.ASTTypeId: [(name: String, types: [TrussType.TrussType])]]) {
        enumCases = cases
    }

    func setModulePath(_ path: [Symbol.ModuleSymbol]) {
        modulePath = path
    }

    func metadataId(for type: TrussType.NominalType) -> Id.TIRMetadataId? {
        let lowered = lower(type)
        if let existing = metadataByType[lowered.id] {
            return existing
        }
        guard let classType = lowered as? TIRType.ClassType else { return nil }
        let record = registry.addMetadata(name: classType.name)
        metadataByType[lowered.id] = record.id
        if let superclass = superclassType(of: type), let superId = metadataId(for: superclass) {
            record.superclass = superId
        }
        return record.id
    }

    private func registerClassMetadata(
        _ type: TrussType.NominalType, classType: TIRType.ClassType
    ) {
        if metadataByType[classType.id] != nil {
            return
        }
        let record = registry.addMetadata(name: classType.name)
        metadataByType[classType.id] = record.id
        if let superclass = superclassType(of: type),
           let superLowered = lower(superclass) as? TIRType.ClassType,
           let superId = metadataByType[superLowered.id]
        {
            record.superclass = superId
        }
    }

    func lower(_ type: TrussType.TrussType) -> TIRType.TIRType {
        let lowered = lowerUnregistered(type)
        return lowered
    }

    func lowerUnregistered(_ type: TrussType.TrussType) -> TIRType.TIRType {
        switch type {
        case is TrussType.VoidType, is TrussType.NeverType, is TrussType.ErrorType:
            return registry.voidType()
        case let builtin as TrussType.BuiltinType:
            if let info = Builtin.typeInfos.first(where: { $0.name == builtin.name }) {
                return registry.primitiveType(kind: info.kind, bitWidth: info.bitWidth)
            }
            return registry.voidType()
        case let nominal as TrussType.NominalType:
            return nominalType(nominal)
        case let optional as TrussType.GenericInstantiation
            where optional.base.name == "Optional":
            if let wrapped = optional.arguments.first { return optionalEnumType(wrapped) }
            return registry.voidType()
        case let pointer as TrussType.PointerType:
            return registry.pointerType(pointee: lower(pointer.pointee).id)
        case let tuple as TrussType.TupleType:
            return registry.tupleType(elements: tuple.elements.map {
                TIRType.TupleType.Element(label: $0.label, type: lower($0.type).id)
            })
        case let function as TrussType.FunctionType:
            return registry.functionType(
                parameters: function.parameters.map { lower($0.type).id },
                returnType: lower(function.returnType).id,
                isVariadic: function.isVariadic
            )
        case let composition as TrussType.CompositionType:
            return lower(composition.members.first ?? TrussType.VoidType.INSTANCE)
        case let instantiation as TrussType.GenericInstantiation:
            return lower(instantiation.base)
        case let variable as TrussType.TypeVariableType:
            if let binding = variable.binding {
                return lower(binding)
            }
            return registry.voidType()
        case let forall as TrussType.ForallType:
            return lower(forall.body)
        case _ as TrussType.GenericParamType:
            return registry.voidType()
        default:
            return registry.voidType()
        }
    }

    private func optionalEnumType(_ wrapped: TrussType.TrussType) -> TIRType.EnumType {
        let wrappedId = lower(wrapped).id
        if let existing = optionalEnums[wrappedId] {
            return existing
        }
        let name = "Optional<" + mangler.typeName(wrapped, modulePath: modulePath) + ">"
        let enumType = registry.enumType(name: name)
        optionalEnums[wrappedId] = enumType
        enumType.cases = [("None", []), ("Some", [wrappedId])]
        return enumType
    }

    private func nominalType(_ type: TrussType.NominalType) -> TIRType.NominalType {
        if let existing = nominalInProgress[type.id] {
            return existing
        }
        let mangledName = mangler.nominalPath(type, modulePath: modulePath)
        let lowered: TIRType.NominalType = switch type {
        case is TrussType.StructType:
            registry.structType(name: mangledName)
        case is TrussType.ClassType:
            registry.classType(name: mangledName)
        case is TrussType.EnumType:
            registry.enumType(name: mangledName)
        default:
            registry.structType(name: mangledName)
        }
        nominalInProgress[type.id] = lowered
        fillMembers(lowered, type: type)
        if let classType = lowered as? TIRType.ClassType {
            registerClassMetadata(type, classType: classType)
        }
        return lowered
    }

    private func fillMembers(_ lowered: TIRType.NominalType, type: TrussType.NominalType) {
        if let structType = lowered as? TIRType.StructType {
            structType.fields = (storedProperties[type.id] ?? []).map {
                (name: $0.name, type: lower($0.type).id)
            }
        } else if let classType = lowered as? TIRType.ClassType {
            var fields: [(name: String, type: Id.TIRTypeId)] = []
            if let superclassType = superclassType(of: type),
               let superLowered = nominalType(superclassType) as? TIRType.ClassType
            {
                fields = superLowered.fields
            }
            fields.append(
                contentsOf: (storedProperties[type.id] ?? []).map {
                    (name: $0.name, type: lower($0.type).id)
                }
            )
            classType.fields = fields
        } else if let enumType = lowered as? TIRType.EnumType {
            enumType.cases = (enumCases[type.id] ?? []).map {
                (name: $0.name, associatedTypes: $0.types.map { lower($0).id })
            }
        }
    }

    private func superclassType(of type: TrussType.NominalType) -> TrussType.ClassType? {
        guard let symbol = type.symbol as? Symbol.ClassSymbol,
              let superclassSymbol = symbol.superclass,
              let typeId = superclassSymbol.typeId
        else {
            return nil
        }
        return context.typeTable[typeId] as? TrussType.ClassType
    }
}
