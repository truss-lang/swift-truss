import Foundation

public struct InterfaceExtractor {
    private let context: Context
    public init(context: Context) { self.context = context }

    public func extract(from program: AST.Program) -> ModuleInterface {
        let name = program.packageSymbol?.name ?? program.packageName
        let root: InterfaceScope =
            if let package = program.packageSymbol {
                extractScope(package.scope)
            } else {
                InterfaceScope()
            }
        return ModuleInterface(name: name, root: root)
    }

    private func extractScope(_ scope: Scope) -> InterfaceScope {
        var modules: [InterfaceModule] = []
        for (name, mod) in scope.modules.sorted(by: { $0.key < $1.key }) {
            modules.append(InterfaceModule(name: name, scope: extractScope(mod.scope)))
        }
        var types: [InterfaceType] = []
        for (name, symbol) in scope.types.sorted(by: { $0.key < $1.key }) {
            if !isExported(symbol) { continue }
            if let t = extractType(name, symbol) {
                types.append(t)
            }
        }
        var values: [InterfaceValue] = []
        for (name, symbols) in scope.values.sorted(by: { $0.key < $1.key }) {
            for symbol in symbols {
                if !isExported(symbol) { continue }
                if let v = extractValue(name, symbol) {
                    values.append(v)
                }
            }
        }
        return InterfaceScope(modules: modules, types: types, values: values)
    }

    private func isExported(_ symbol: Symbol.Symbol) -> Bool {
        symbol.access == .Open || symbol.access == .Public
    }

    private func extractType(_ name: String, _ symbol: Symbol.Symbol) -> InterfaceType? {
        switch symbol {
        case let s as Symbol.StructSymbol:
            return .nominal(extractNominal(s, kind: .structType))
        case let s as Symbol.ClassSymbol:
            var n = extractNominal(s, kind: .classType)
            n.superclass = s.superclass?.name
            return .nominal(n)
        case let s as Symbol.EnumSymbol:
            return .nominal(extractNominal(s, kind: .enumType))
        case let s as Symbol.ProtocolSymbol:
            return .nominal(extractNominal(s, kind: .protocolType))
        case let s as Symbol.ActorSymbol:
            return .nominal(extractNominal(s, kind: .actorType))
        case let s as Symbol.TypeAliasSymbol:
            return .typeAlias(InterfaceTypealias(name: s.name, target: s.targetType.map(typeRef)))
        case let s as Symbol.AssociatedTypeSymbol:
            return .associatedType(InterfaceSimple(name: s.name))
        case let s as Symbol.BuiltinTypeSymbol:
            return .builtin(InterfaceSimple(name: s.name))
        default:
            return nil
        }
    }

    private func extractNominal(_ s: Symbol.NominalTypeSymbol, kind: InterfaceNominalKind) -> InterfaceNominal {
        let conformances = s.conformances.map(\.name)
        return InterfaceNominal(
            kind: kind, name: s.name, conformances: conformances, superclass: nil,
            scope: extractScope(s.scope)
        )
    }

    private func extractValue(_ name: String, _ symbol: Symbol.Symbol) -> InterfaceValue? {
        switch symbol {
        case let f as Symbol.FunctionSymbol:
            let labels = f.signature.labels
            let defs = f.signature.hasDefaults
            let vars = f.signature.isVararg
            return .function(InterfaceFunction(
                name: f.name, labels: labels, hasDefaults: defs, isVararg: vars,
                isVariadic: f.signature.isVariadic, isStatic: f.isStatic,
                functionType: f.functionType.map(typeRef)
            ))
        case let v as Symbol.VariableSymbol:
            return .variable(InterfaceVariable(
                name: v.name, isMutable: v.isMutable, type: v.type.map(typeRef)
            ))
        default:
            return nil
        }
    }

    public func typeRef(_ type: TrussType.TrussType) -> InterfaceTypeRef {
        switch type {
        case is TrussType.VoidType: .void
        case is TrussType.NeverType: .never
        case is TrussType.ErrorType: .error
        case let b as TrussType.BuiltinType: .builtin(b.name)
        case let o as TrussType.OptionalType: .optional(typeRef(o.wrapped))
        case let p as TrussType.PointerType: .pointer(typeRef(p.pointee), p.isNonnull)
        case let t as TrussType.TupleType:
            .tuple(t.elements.map { InterfaceTupleElement(label: $0.label, type: typeRef($0.type)) })
        case let f as TrussType.FunctionType:
            .function(InterfaceFunctionType(
                parameters: f.parameters.map { InterfaceTupleElement(label: $0.label, type: typeRef($0.type)) },
                isVariadic: f.isVariadic, isAsync: f.isAsync, isThrowing: f.isThrowing,
                throwsTypes: f.throwsTypes.map(typeRef), returnType: typeRef(f.returnType)
            ))
        case let n as TrussType.NominalType:
            .nominal(n.name, [])
        case let gi as TrussType.GenericInstantiation:
            .nominal(gi.base.name, gi.arguments.map(typeRef))
        case let c as TrussType.CompositionType:
            .composition(c.members.map(typeRef))
        case let v as TrussType.VariadicType:
            .variadic(typeRef(v.base))
        case let gp as TrussType.GenericParamType:
            .genericParam(gp.name)
        case let f as TrussType.ForallType:
            .forall(f.parameters.map(\.name), typeRef(f.body))
        case let tv as TrussType.TypeVariableType:
            .typeVariable(Int(tv.id.id))
        default:
            .builtin("unknown")
        }
    }
}
