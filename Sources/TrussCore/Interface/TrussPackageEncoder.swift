import Foundation

public final class TrussPackageEncoder {
    private let interface: ModuleInterface
    private var typeTable: [InterfaceTypeRef] = []
    private var typeIndex: [InterfaceTypeRef: Int] = [:]

    public init(interface: ModuleInterface) { self.interface = interface }

    public func encode() -> [UInt8] {
        collectTypes(in: interface.root)
        let body = BitWriter()
        let toc = TocBuilder()
        body.u32(UInt32(typeTable.count))
        for t in typeTable {
            encodeType(t, into: body)
        }
        encodeScope(interface.root, into: body, toc: toc, prefix: interface.name)

        let header = BitWriter()
        header.appendBytes(TrussPackageFormat.magic)
        header.u32(TrussPackageFormat.version)
        header.string(interface.name)
        header.u32(UInt32(toc.entries.count))
        for e in toc.entries {
            header.string(e.name)
            header.u64(UInt64(e.offset))
            header.u32(UInt32(e.size))
        }
        header.appendBytes(body.bytes)
        return header.bytes
    }

    private func collectTypes(in scope: InterfaceScope) {
        for type in scope.types {
            switch type {
            case let .Nominal(n):
                for c in n.cases {
                    for t in c.associatedTypes {
                        indexType(t)
                    }
                }
                collectTypes(in: n.scope)
            case let .TypeAlias(a): if let t = a.target { indexType(t) }
            case .AssociatedType, .Builtin, .GenericParam: break
            }
        }
        for value in scope.values {
            switch value {
            case let .Function(f): if let t = f.functionType { indexType(t) }
            case let .Variable(v): if let t = v.type { indexType(t) }
            }
        }
        for m in scope.modules {
            collectTypes(in: m.scope)
        }
    }

    private func indexType(_ t: InterfaceTypeRef) {
        if typeIndex[t] != nil { return }
        for child in typeChildren(t) {
            indexType(child)
        }
        typeIndex[t] = typeTable.count
        typeTable.append(t)
    }

    private func typeChildren(_ t: InterfaceTypeRef) -> [InterfaceTypeRef] {
        switch t {
        case .Void, .Never, .Error, .Builtin, .GenericParam, .TypeVariable: []
        case let .Nominal(_, args): args
        case let .Pointer(p, _): [p]
        case let .Tuple(els): els.map(\.type)
        case let .Function(f): f.parameters.map(\.type) + f.throwsTypes + [f.returnType]
        case let .Composition(m): m
        case let .Variadic(b): [b]
        case let .Forall(_, b): [b]
        }
    }

    private func encodeType(_ t: InterfaceTypeRef, into w: BitWriter) {
        switch t {
        case .Void: w.u8(InterfaceTypeRefCode.Void.rawValue)
        case .Never: w.u8(InterfaceTypeRefCode.Never.rawValue)
        case .Error: w.u8(InterfaceTypeRefCode.Error.rawValue)
        case let .Builtin(n): w.u8(InterfaceTypeRefCode.Builtin.rawValue); w.string(n)
        case let .Nominal(n, args):
            w.u8(InterfaceTypeRefCode.Nominal.rawValue); w.string(n); encodeRefs(args, w)
        case let .Pointer(x, nn):
            w.u8(InterfaceTypeRefCode.Pointer.rawValue); encodeRef(x, w); w.bool(nn)
        case let .Tuple(els):
            w.u8(InterfaceTypeRefCode.Tuple.rawValue); w.u32(UInt32(els.count))
            for e in els {
                w.stringOpt(e.label); encodeRef(e.type, w)
            }
        case let .Function(f):
            w.u8(InterfaceTypeRefCode.Function.rawValue)
            w.bool(f.isVariadic); w.bool(f.isAsync); w.bool(f.isThrowing)
            w.u32(UInt32(f.throwsTypes.count)); for x in f.throwsTypes {
                encodeRef(x, w)
            }
            w.u32(UInt32(f.parameters.count))
            for p in f.parameters {
                w.stringOpt(p.label); encodeRef(p.type, w)
            }
            encodeRef(f.returnType, w)
        case let .Composition(m): w.u8(InterfaceTypeRefCode.Composition.rawValue); encodeRefs(m, w)
        case let .Variadic(b): w.u8(InterfaceTypeRefCode.Variadic.rawValue); encodeRef(b, w)
        case let .GenericParam(n): w.u8(InterfaceTypeRefCode.GenericParam.rawValue); w.string(n)
        case let .Forall(ps, b):
            w.u8(InterfaceTypeRefCode.Forall.rawValue); w.u32(UInt32(ps.count)); for p in ps {
                w.string(p)
            }; encodeRef(b, w)
        case let .TypeVariable(i): w.u8(InterfaceTypeRefCode.TypeVariable.rawValue); w.u32(UInt32(i))
        }
    }

    private func encodeRef(_ t: InterfaceTypeRef, _ w: BitWriter) {
        guard let idx = typeIndex[t] else {
            w.u32(UInt32.max)
            return
        }
        w.u32(UInt32(idx))
    }

    private func encodeRefs(_ ts: [InterfaceTypeRef], _ w: BitWriter) {
        w.u32(UInt32(ts.count))
        for t in ts {
            encodeRef(t, w)
        }
    }

    private func encodeScope(_ scope: InterfaceScope, into w: BitWriter, toc: TocBuilder, prefix: String) {
        w.u32(UInt32(scope.modules.count))
        for m in sortedModules(scope.modules) {
            let start = w.byteCount()
            w.string(m.name)
            encodeScope(m.scope, into: w, toc: toc, prefix: prefix + "." + m.name)
            toc.add(name: prefix + "." + m.name, offset: start, size: w.byteCount() - start)
        }
        w.u32(UInt32(scope.types.count))
        for (name, type) in sortedTypes(scope.types) {
            let start = w.byteCount()
            encodeTypeDecl(type, into: w)
            let full = prefix + "." + name
            toc.add(name: full, offset: start, size: w.byteCount() - start)
        }
        w.u32(UInt32(scope.values.count))
        for (name, value) in sortedValues(scope.values) {
            let start = w.byteCount()
            encodeValueDecl(value, into: w)
            let full = prefix + "." + name
            toc.add(name: full, offset: start, size: w.byteCount() - start)
        }
    }

    private func encodeTypeDecl(_ t: InterfaceType, into w: BitWriter) {
        switch t {
        case let .Nominal(n):
            w.u8(InterfaceTypeDeclCode.Nominal.rawValue); w.u8(n.kind.rawValue); w.string(n.name)
            w.u32(UInt32(n.conformances.count)); for c in n.conformances {
                w.string(c)
            }
            w.stringOpt(n.superclass)
            w.u32(UInt32(n.cases.count))
            for c in n.cases {
                w.string(c.name)
                encodeRefs(c.associatedTypes, w)
            }
            encodeScope(n.scope, into: w, toc: TocBuilder(), prefix: n.name)
        case let .TypeAlias(a):
            w.u8(InterfaceTypeDeclCode.TypeAlias.rawValue)
            w.string(a.name); w.bool(a.target != nil); if let t = a.target { encodeRef(t, w) }
        case let .AssociatedType(s):
            w.u8(InterfaceTypeDeclCode.AssociatedType.rawValue); w.string(s.name)
        case let .Builtin(s): w.u8(InterfaceTypeDeclCode.Builtin.rawValue); w.string(s.name)
        case let .GenericParam(s): w.u8(InterfaceTypeDeclCode.GenericParam.rawValue); w.string(s.name)
        }
    }

    private func encodeValueDecl(_ v: InterfaceValue, into w: BitWriter) {
        switch v {
        case let .Function(f):
            w.u8(InterfaceValueDeclCode.Function.rawValue); w.string(f.name)
            w.u32(UInt32(f.labels.count)); for l in f.labels {
                w.stringOpt(l)
            }
            w.u32(UInt32(f.hasDefaults.count)); for b in f.hasDefaults {
                w.bool(b)
            }
            w.u32(UInt32(f.isVararg.count)); for b in f.isVararg {
                w.bool(b)
            }
            w.bool(f.isVariadic); w.bool(f.isStatic)
            w.bool(f.functionType != nil); if let t = f.functionType { encodeRef(t, w) }
        case let .Variable(v):
            w.u8(InterfaceValueDeclCode.Variable.rawValue)
            w.string(v.name); w.bool(v.isMutable)
            w.bool(v.type != nil); if let t = v.type { encodeRef(t, w) }
        }
    }

    private func sortedModules(_ ms: [InterfaceModule]) -> [InterfaceModule] { ms.sorted { $0.name < $1.name } }
    private func sortedTypes(_ ts: [InterfaceType]) -> [(String, InterfaceType)] {
        ts.compactMap { t -> (String, InterfaceType)? in
            switch t {
            case let .Nominal(n): (n.name, t)
            case let .TypeAlias(a): (a.name, t)
            case let .AssociatedType(s): (s.name, t)
            case let .Builtin(s): (s.name, t)
            case let .GenericParam(s): (s.name, t)
            }
        }.sorted { $0.0 < $1.0 }
    }

    private func sortedValues(_ vs: [InterfaceValue]) -> [(String, InterfaceValue)] {
        vs.compactMap { v -> (String, InterfaceValue)? in
            switch v {
            case let .Function(f): (f.name, v)
            case let .Variable(x): (x.name, v)
            }
        }.sorted { $0.0 < $1.0 }
    }

    private final class TocEntry {
        let name: String
        let offset: Int
        let size: Int
        init(name: String, offset: Int, size: Int) {
            self.name = name
            self.offset = offset
            self.size = size
        }
    }

    private final class TocBuilder {
        var entries: [TocEntry] = []
        func add(name: String, offset: Int, size: Int) {
            entries.append(TocEntry(name: name, offset: offset, size: size))
        }
    }
}
