import TrussCore

final class TypeLower {
    private let context: Context
    private var cache: [Id.TypeId: TIRType.TIRType] = [:]
    private var archetypes: [String: TIRType.ArchetypeType] = [:]

    init(context: Context) {
        self.context = context
    }

    func lower(_ type: TrussType.TrussType) -> TIRType.TIRType {
        switch type {
        case is TrussType.VoidType, is TrussType.NeverType, is TrussType.ErrorType:
            return TIRType.TupleType([])
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
                isAsync: function.isAsync,
                isThrowing: function.isThrowing,
                throwsTypes: function.throwsTypes.map(lower),
                returnType: lower(function.returnType)
            )
        case let composition as TrussType.CompositionType:
            return TIRType.ExistentialType(composition.members.map(lower))
        case let instantiation as TrussType.GenericInstantiation:
            return lower(instantiation.base)
        case let variable as TrussType.TypeVariableType:
            if let binding = variable.binding {
                return lower(binding)
            }
            return TIRType.TupleType([])
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
            return TIRType.TupleType([])
        }
    }

    private func nominalType(_ type: TrussType.NominalType) -> TIRType.TIRType {
        if let cached = cache[type.id] {
            return cached
        }
        let lowered: TIRType.NominalType = switch type {
        case is TrussType.StructType:
            TIRType.StructType(type.id, type.name)
        case is TrussType.ClassType:
            TIRType.ReferenceType(type.id, type.name)
        case is TrussType.EnumType:
            TIRType.EnumType(type.id, type.name)
        case is TrussType.ProtocolType:
            TIRType.ProtocolType(type.id, type.name)
        case is TrussType.ActorType:
            TIRType.ReferenceType(type.id, type.name)
        default:
            TIRType.ReferenceType(type.id, type.name)
        }
        lowered.symbol = type.symbol
        cache[type.id] = lowered
        return lowered
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
