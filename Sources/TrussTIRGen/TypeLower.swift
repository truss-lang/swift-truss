import TrussCore

final class TypeLower {
    private let context: Context
    private var cache: [Id.TypeId: TIRType.TIRType] = [:]
    private var archetypes: [String: TIRType.ArchetypeType] = [:]
    private var registered: [ObjectIdentifier: Int] = [:]
    var registry: TIR.Registry?
    var storedProperties: [Id.TypeId: [(name: String, type: TrussType.TrussType)]] = [:]
    var enumCases: [Id.TypeId: [(name: String, types: [TrussType.TrussType])]] = [:]

    init(context: Context) {
        self.context = context
    }

    func lower(_ type: TrussType.TrussType) -> TIRType.TIRType {
        let lowered = lowerUnregistered(type)
        register(lowered)
        return lowered
    }

    @discardableResult
    func register(_ type: TIRType.TIRType) -> Int {
        let key = ObjectIdentifier(type)
        if let existing = registered[key] {
            return existing
        }
        guard let registry else {
            fatalError("type registry is not configured")
        }
        let id = registry.nextTypeId
        registry.types[id] = type
        registered[key] = id
        return id
    }

    func lowerUnregistered(_ type: TrussType.TrussType) -> TIRType.TIRType {
        switch type {
        case is TrussType.VoidType, is TrussType.NeverType, is TrussType.ErrorType:
            return TIRType.VoidType()
        case let builtin as TrussType.BuiltinType:
            if let info = Builtin.typeInfos.first(where: { $0.name == builtin.name }) {
                return TIRType.PrimitiveType(kind: info.kind, bitWidth: info.bitWidth)
            }
            return TIRType.VoidType()
        case let nominal as TrussType.NominalType:
            return nominalType(nominal)
        case let optional as TrussType.OptionalType:
            return TIRType.OptionalType(lower(optional.wrapped))
        case let tuple as TrussType.TupleType:
            return TIRType.TupleType(
                tuple.elements.map {
                    TIRType.TupleType.Element(label: $0.label, type: lower($0.type))
                }
            )
        case let function as TrussType.FunctionType:
            return TIRType.FunctionType(
                parameters: function.parameters.map {
                    TIRType.FunctionType.Parameter(label: $0.label, type: lower($0.type))
                },
                isVariadic: function.isVariadic,
                isAsync: function.isAsync,
                isThrowing: function.isThrowing,
                throwsTypes: function.throwsTypes.map(lower),
                returnType: lower(function.returnType)
            )
        case let pointer as TrussType.PointerType:
            return TIRType.PointerType(lower(pointer.pointee))
        case let composition as TrussType.CompositionType:
            return TIRType.ExistentialType(composition.members.map(lower))
        case let instantiation as TrussType.GenericInstantiation:
            return lower(instantiation.base)
        case let variable as TrussType.TypeVariableType:
            if let binding = variable.binding {
                return lower(binding)
            }
            return TIRType.VoidType()
        case let forall as TrussType.ForallType:
            return lower(forall.body)
        case let genericParam as TrussType.GenericParamType:
            if let archetype = archetypes[genericParam.name] {
                return archetype
            }
            let archetype = TIRType.ArchetypeType(genericParam.name, genericParam.symbol)
            archetypes[genericParam.name] = archetype
            return archetype
        default:
            return TIRType.VoidType()
        }
    }

    private func nominalType(_ type: TrussType.NominalType) -> TIRType.TIRType {
        if let cached = cache[type.id] {
            return cached
        }
        let mangledName = mangleTypeName(type)
        let lowered: TIRType.NominalType = switch type {
        case is TrussType.StructType:
            TIRType.StructType(type.id, mangledName)
        case is TrussType.ClassType:
            TIRType.ReferenceType(type.id, mangledName)
        case is TrussType.EnumType:
            TIRType.EnumType(type.id, mangledName)
        case is TrussType.ProtocolType:
            TIRType.ProtocolType(type.id, mangledName)
        case is TrussType.ActorType:
            TIRType.ReferenceType(type.id, mangledName)
        default:
            TIRType.ReferenceType(type.id, mangledName)
        }
        cache[type.id] = lowered
        register(lowered)
        fillMembers(lowered, type: type)
        return lowered
    }

    private func fillMembers(_ lowered: TIRType.NominalType, type: TrussType.NominalType) {
        if let structType = lowered as? TIRType.StructType {
            structType.fields = (storedProperties[type.id] ?? []).map {
                (name: $0.name, type: register(lower($0.type)))
            }
        } else if let referenceType = lowered as? TIRType.ReferenceType {
            referenceType.fields = (storedProperties[type.id] ?? []).map {
                (name: $0.name, type: register(lower($0.type)))
            }
        } else if let enumType = lowered as? TIRType.EnumType {
            enumType.cases = (enumCases[type.id] ?? []).map {
                (name: $0.name, associatedTypeIds: $0.types.map { register(lower($0)) })
            }
        }
    }

    private func mangleTypeName(_ type: TrussType.NominalType) -> String {
        TypeMangler.nominalPath(type, context: context)
    }

    func ownership(for type: TIRType.TIRType) -> TIRType.Ownership {
        switch type {
        case is TIRType.ReferenceType:
            .Owned
        default:
            .Trivial
        }
    }

    func archetype(named name: String) -> TIRType.ArchetypeType? {
        archetypes[name]
    }
}
