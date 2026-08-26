import Foundation

public struct TrussPackageTocEntry {
    public let name: String
    public let offset: Int
    public let size: Int
    public init(name: String, offset: Int, size: Int) {
        self.name = name
        self.offset = offset
        self.size = size
    }
}

public struct TrussPackageDecoder {
    private var typeTable: [InterfaceTypeRef] = []

    public init() {}

    public func decode(_ bytes: [UInt8]) throws -> TrussPackageDocument {
        var reader = BitReader(bytes)
        let magic = try (0 ..< 4).map { _ in try reader.u8() }
        guard magic == TrussPackageFormat.magic else { throw TrussPackageCodecError.BadMagic }
        let version = try reader.u32()
        guard version == TrussPackageFormat.version else { throw TrussPackageCodecError.BadVersion }
        let name = try reader.string()
        let tocCount = try Int(reader.u32())
        for _ in 0 ..< tocCount {
            _ = try reader.string()
            _ = try reader.u64()
            _ = try reader.u32()
        }
        var d = TrussPackageDecoder()
        try d.decodeTypeTableInto(&reader)
        let root = try d.decodeScope(&reader)
        return TrussPackageDocument(interface: ModuleInterface(name: name, root: root))
    }

    private mutating func decodeTypeTableInto(_ reader: inout BitReader) throws {
        let count = try Int(reader.u32())
        for _ in 0 ..< count {
            try typeTable.append(decodeTypeRef(&reader))
        }
    }

    private func decodeTypeRef(_ reader: inout BitReader) throws -> InterfaceTypeRef {
        guard let kind = try InterfaceTypeRefCode(rawValue: reader.u8()) else {
            throw TrussPackageCodecError.Truncated
        }
        switch kind {
        case .Void: return .Void
        case .Never: return .Never
        case .Error: return .Error
        case .Builtin: return try .Builtin(reader.string())
        case .Nominal:
            let n = try reader.string()
            let args = try decodeRefs(&reader)
            return .Nominal(n, args)
        case .Pointer:
            let p = try decodeRef(&reader)
            let nn = try reader.bool()
            return .Pointer(p, nn)
        case .Tuple:
            let count = try Int(reader.u32())
            var els: [InterfaceTupleElement] = []
            for _ in 0 ..< count {
                let l = try reader.stringOpt()
                let t = try decodeRef(&reader)
                els.append(InterfaceTupleElement(label: l, type: t))
            }
            return .Tuple(els)
        case .Function:
            let isVar = try reader.bool()
            let isAsync = try reader.bool()
            let isThrow = try reader.bool()
            let throwCount = try Int(reader.u32())
            var throwsTypes: [InterfaceTypeRef] = []
            for _ in 0 ..< throwCount {
                try throwsTypes.append(decodeRef(&reader))
            }
            let paramCount = try Int(reader.u32())
            var params: [InterfaceTupleElement] = []
            for _ in 0 ..< paramCount {
                let l = try reader.stringOpt()
                let t = try decodeRef(&reader)
                params.append(InterfaceTupleElement(label: l, type: t))
            }
            let ret = try decodeRef(&reader)
            return .Function(InterfaceFunctionType(
                parameters: params,
                isVariadic: isVar,
                isAsync: isAsync,
                isThrowing: isThrow,
                throwsTypes: throwsTypes,
                returnType: ret
            ))
        case .Composition: return try .Composition(decodeRefs(&reader))
        case .Variadic: return try .Variadic(decodeRef(&reader))
        case .GenericParam: return try .GenericParam(reader.string())
        case .Forall:
            let count = try Int(reader.u32())
            var ps: [String] = []
            for _ in 0 ..< count {
                try ps.append(reader.string())
            }
            let b = try decodeRef(&reader)
            return .Forall(ps, b)
        case .TypeVariable: return try .TypeVariable(Int(reader.u32()))
        }
    }

    private func decodeRefs(_ reader: inout BitReader) throws -> [InterfaceTypeRef] {
        let count = try Int(reader.u32())
        var refs: [InterfaceTypeRef] = []
        for _ in 0 ..< count {
            try refs.append(decodeRef(&reader))
        }
        return refs
    }

    private func decodeRef(_ reader: inout BitReader) throws -> InterfaceTypeRef {
        let idx = try Int(reader.u32())
        guard idx != Int(UInt32.max) else { throw TrussPackageCodecError.TypeIndexOutOfRange(-1) }
        guard idx >= 0, idx < typeTable.count else {
            throw TrussPackageCodecError.TypeIndexOutOfRange(idx)
        }
        return typeTable[idx]
    }

    private func decodeScope(_ reader: inout BitReader) throws -> InterfaceScope {
        var modules: [InterfaceModule] = []
        var types: [InterfaceType] = []
        var values: [InterfaceValue] = []
        let moduleCount = try Int(reader.u32())
        for _ in 0 ..< moduleCount {
            let name = try reader.string()
            let scope = try decodeScope(&reader)
            modules.append(InterfaceModule(name: name, scope: scope))
        }
        let typeCount = try Int(reader.u32())
        for _ in 0 ..< typeCount {
            try types.append(decodeTypeDecl(&reader))
        }
        let valueCount = try Int(reader.u32())
        for _ in 0 ..< valueCount {
            try values.append(decodeValueDecl(&reader))
        }
        return InterfaceScope(modules: modules, types: types, values: values)
    }

    private func decodeTypeDecl(_ reader: inout BitReader) throws -> InterfaceType {
        guard let kind = try InterfaceTypeDeclCode(rawValue: reader.u8()) else {
            throw TrussPackageCodecError.Truncated
        }
        switch kind {
        case .Nominal:
            guard let nkind = try InterfaceNominalKind(rawValue: reader.u8()) else {
                throw TrussPackageCodecError.Truncated
            }
            let name = try reader.string()
            let confCount = try Int(reader.u32())
            var confs: [String] = []
            for _ in 0 ..< confCount {
                try confs.append(reader.string())
            }
            let superclass = try reader.stringOpt()
            let caseCount = try Int(reader.u32())
            var cases: [InterfaceCase] = []
            for _ in 0 ..< caseCount {
                let caseName = try reader.string()
                let assocTypes = try decodeRefs(&reader)
                cases.append(InterfaceCase(name: caseName, associatedTypes: assocTypes))
            }
            let scope = try decodeScope(&reader)
            return .Nominal(InterfaceNominal(
                kind: nkind,
                name: name,
                conformances: confs,
                superclass: superclass,
                cases: cases,
                scope: scope
            ))
        case .TypeAlias:
            let name = try reader.string()
            let hasTarget = try reader.bool()
            let target = hasTarget ? try decodeRef(&reader) : nil
            return .TypeAlias(InterfaceTypealias(name: name, target: target))
        case .AssociatedType: return try .AssociatedType(InterfaceSimple(name: reader.string()))
        case .Builtin: return try .Builtin(InterfaceSimple(name: reader.string()))
        case .GenericParam: return try .GenericParam(InterfaceSimple(name: reader.string()))
        }
    }

    private func decodeValueDecl(_ reader: inout BitReader) throws -> InterfaceValue {
        guard let kind = try InterfaceValueDeclCode(rawValue: reader.u8()) else {
            throw TrussPackageCodecError.Truncated
        }
        switch kind {
        case .Function:
            let name = try reader.string()
            let labelCount = try Int(reader.u32())
            var labels: [String?] = []
            for _ in 0 ..< labelCount {
                try labels.append(reader.stringOpt())
            }
            let defCount = try Int(reader.u32())
            var defs: [Bool] = []
            for _ in 0 ..< defCount {
                try defs.append(reader.bool())
            }
            let varCount = try Int(reader.u32())
            var vars: [Bool] = []
            for _ in 0 ..< varCount {
                try vars.append(reader.bool())
            }
            let isVariadic = try reader.bool()
            let isStatic = try reader.bool()
            let hasType = try reader.bool()
            let ft = hasType ? try decodeRef(&reader) : nil
            return .Function(InterfaceFunction(
                name: name,
                labels: labels,
                hasDefaults: defs,
                isVararg: vars,
                isVariadic: isVariadic,
                isStatic: isStatic,
                functionType: ft
            ))
        case .Variable:
            let name = try reader.string()
            let isMutable = try reader.bool()
            let hasType = try reader.bool()
            let t = hasType ? try decodeRef(&reader) : nil
            return .Variable(InterfaceVariable(name: name, isMutable: isMutable, type: t))
        }
    }
}
