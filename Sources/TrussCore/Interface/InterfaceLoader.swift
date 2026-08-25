import Foundation

public struct InterfaceLoader {
    private let context: Context
    public init(context: Context) { self.context = context }

    @discardableResult
    public func load(_ interface: ModuleInterface) -> Symbol.PackageSymbol {
        if let existing = context.name2Package[interface.name] {
            return existing
        }
        let package = Symbol.PackageSymbol(id: context.nextSymbolId, name: interface.name)
        context.register(packageSymbol: package)
        loadScope(interface.root, into: package.scope, package: package)
        return package
    }

    private func loadScope(_ scope: InterfaceScope, into scope_: Scope, package: Symbol.PackageSymbol) {
        for m in scope.modules {
            let mod = Symbol.ModuleSymbol(id: context.nextSymbolId, name: m.name)
            mod.packageId = package.id
            context.register(symbol: mod)
            scope_.registerModule(mod)
            loadScope(m.scope, into: mod.scope, package: package)
        }
        for type in scope.types {
            loadType(type, into: scope_, package: package)
        }
        for value in scope.values {
            loadValue(value, into: scope_, package: package)
        }
    }

    private func loadType(_ t: InterfaceType, into scope: Scope, package: Symbol.PackageSymbol) {
        switch t {
        case let .nominal(n):
            let symbol: Symbol.NominalTypeSymbol = switch n.kind {
            case .structType: Symbol.StructSymbol(id: context.nextSymbolId, name: n.name)
            case .classType: Symbol.ClassSymbol(id: context.nextSymbolId, name: n.name)
            case .enumType: Symbol.EnumSymbol(id: context.nextSymbolId, name: n.name)
            case .protocolType: Symbol.ProtocolSymbol(id: context.nextSymbolId, name: n.name)
            case .actorType: Symbol.ActorSymbol(id: context.nextSymbolId, name: n.name)
            }
            symbol.access = .Public
            symbol.packageId = package.id

            for conf in n.conformances {
                if let proto = context.name2Package.values.compactMap({ $0.scope.types[conf] }).first as? Symbol
                    .ProtocolSymbol
                {
                    symbol.conformances.append(proto)
                }
            }
            context.register(symbol: symbol)
            let type = makeNominalType(n.kind, id: context.nextTypeId, name: n.name)
            type.symbol = symbol
            symbol.typeId = type.id
            context.register(type: type)
            scope.registerType(symbol, at: syntheticToken(n.name), context: context)
            loadScope(n.scope, into: symbol.scope, package: package)
        case let .typeAlias(a):
            let symbol = Symbol.TypeAliasSymbol(id: context.nextSymbolId, name: a.name)
            symbol.access = .Public
            symbol.packageId = package.id
            symbol.targetType = a.target.map(makeTypeRef)
            context.register(symbol: symbol)
            scope.registerType(symbol, at: syntheticToken(a.name), context: context)
        case let .associatedType(s):
            let symbol = Symbol.AssociatedTypeSymbol(id: context.nextSymbolId, name: s.name)
            symbol.access = .Public
            symbol.packageId = package.id
            context.register(symbol: symbol)
            scope.registerType(symbol, at: syntheticToken(s.name), context: context)
        case let .builtin(s):
            let symbol = Symbol.BuiltinTypeSymbol(id: context.nextSymbolId, name: s.name)
            symbol.access = .Public
            symbol.packageId = package.id
            context.register(symbol: symbol)
            scope.registerType(symbol, at: syntheticToken(s.name), context: context)
        case let .genericParam(s):
            let symbol = Symbol.GenericParamSymbol(id: context.nextSymbolId, name: s.name)
            symbol.access = .Public
            symbol.packageId = package.id
            context.register(symbol: symbol)
            scope.registerType(symbol, at: syntheticToken(s.name), context: context)
        }
    }

    private func makeNominalType(_ kind: InterfaceNominalKind, id: Id.ASTTypeId, name: String) -> TrussType
        .NominalType
    {
        switch kind {
        case .structType: TrussType.StructType(id: id, name: name)
        case .classType: TrussType.ClassType(id: id, name: name)
        case .enumType: TrussType.EnumType(id: id, name: name)
        case .protocolType: TrussType.ProtocolType(id: id, name: name)
        case .actorType: TrussType.ActorType(id: id, name: name)
        }
    }

    private func loadValue(_ v: InterfaceValue, into scope: Scope, package: Symbol.PackageSymbol) {
        switch v {
        case let .function(f):
            let signature = Symbol.FunctionSignature(
                labels: f.labels, hasDefaults: f.hasDefaults, isVararg: f.isVararg, isVariadic: f.isVariadic
            )
            let symbol = Symbol.FunctionSymbol(
                id: context.nextSymbolId, name: f.name, locals: [], scope: scope,
                signature: signature, isStatic: f.isStatic
            )
            symbol.access = .Public
            symbol.packageId = package.id
            symbol.functionType = f.functionType.flatMap { makeTypeRef($0) as? TrussType.FunctionType }
            context.register(symbol: symbol)
            scope.registerValue(symbol, at: syntheticToken(f.name), context: context)
        case let .variable(x):
            let symbol = Symbol.VariableSymbol(id: context.nextSymbolId, name: x.name)
            symbol.access = .Public
            symbol.packageId = package.id
            symbol.type = x.type.map(makeTypeRef)
            symbol.isMutable = x.isMutable
            context.register(symbol: symbol)
            scope.registerValue(symbol, at: syntheticToken(x.name), context: context)
        }
    }

    private func syntheticToken(_ name: String) -> Token {
        Token(value: name, kind: .Identifier, pos: Position(pos: 0, line: 1, col: 1, len: 1), id: Id.SourceId(0))
    }

    public func makeTypeRef(_ ref: InterfaceTypeRef) -> TrussType.TrussType {
        switch ref {
        case .void: return TrussType.VoidType.INSTANCE
        case .never: return TrussType.NeverType.INSTANCE
        case .error: return TrussType.ErrorType.INSTANCE
        case let .builtin(n): return TrussType.BuiltinType(n)
        case let .nominal(n, args):
            if let proto = findProtocol(n) {
                let t = TrussType.ProtocolType(id: proto.typeId ?? context.nextTypeId, name: n)
                t.symbol = proto
                if proto.typeId == nil { context.register(type: t); proto.typeId = t.id }
                return t
            }
            let t = TrussType.StructType(id: context.nextTypeId, name: n)
            return t
        case let .optional(w): return TrussType.OptionalType(makeTypeRef(w))
        case let .pointer(p, nn): return TrussType.PointerType(makeTypeRef(p), isNonnull: nn)
        case let .tuple(els):
            return TrussType
                .TupleType(els.map { TrussType.TupleType.Element(label: $0.label, type: makeTypeRef($0.type)) })
        case let .function(f):
            return TrussType.FunctionType(
                parameters: f.parameters.map { TrussType.FunctionType.Parameter(
                    label: $0.label,
                    type: makeTypeRef($0.type)
                ) },
                isVariadic: f.isVariadic, isAsync: f.isAsync, isThrowing: f.isThrowing,
                throwsTypes: f.throwsTypes.map(makeTypeRef), returnType: makeTypeRef(f.returnType)
            )
        case let .composition(m): return TrussType.CompositionType(m.map(makeTypeRef))
        case let .variadic(b): return TrussType.VariadicType(makeTypeRef(b))
        case let .genericParam(n): return TrussType.GenericParamType(n)
        case let .forall(ps, b):
            let params = ps.map { Symbol.GenericParamSymbol(id: context.nextSymbolId, name: $0) }
            return TrussType.ForallType(parameters: params, body: makeTypeRef(b))
        case let .typeVariable(i): return TrussType.TypeVariableType(Id.TypeVariableId(UInt64(i)))
        }
    }

    private func findProtocol(_ name: String) -> Symbol.ProtocolSymbol? {
        for package in context.name2Package.values {
            if let s = package.scope.types[name] as? Symbol.ProtocolSymbol {
                return s
            }
        }
        return nil
    }
}
