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
        guard magic == TrussPackageFormat.magic else { throw TrussPackageCodecError.badMagic }
        let version = try reader.u32()
        guard version == TrussPackageFormat.version else { throw TrussPackageCodecError.badVersion }
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
        let kind = try reader.u8()
        switch kind {
        case 0: return .void
        case 1: return .never
        case 2: return .error
        case 3: return try .builtin(reader.string())
        case 4:
            let n = try reader.string()
            let args = try decodeRefs(&reader)
            return .nominal(n, args)
        case 5: return try .optional(decodeRef(&reader))
        case 6:
            let p = try decodeRef(&reader)
            let nn = try reader.bool()
            return .pointer(p, nn)
        case 7:
            let count = try Int(reader.u32())
            var els: [InterfaceTupleElement] = []
            for _ in 0 ..< count {
                let l = try reader.stringOpt()
                let t = try decodeRef(&reader)
                els.append(InterfaceTupleElement(label: l, type: t))
            }
            return .tuple(els)
        case 8:
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
            return .function(InterfaceFunctionType(
                parameters: params,
                isVariadic: isVar,
                isAsync: isAsync,
                isThrowing: isThrow,
                throwsTypes: throwsTypes,
                returnType: ret
            ))
        case 9: return try .composition(decodeRefs(&reader))
        case 10: return try .variadic(decodeRef(&reader))
        case 11: return try .genericParam(reader.string())
        case 12:
            let count = try Int(reader.u32())
            var ps: [String] = []
            for _ in 0 ..< count {
                try ps.append(reader.string())
            }
            let b = try decodeRef(&reader)
            return .forall(ps, b)
        case 13: return try .typeVariable(Int(reader.u32()))
        default: throw TrussPackageCodecError.truncated
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
        guard idx != Int(UInt32.max) else { throw TrussPackageCodecError.typeIndexOutOfRange(-1) }
        guard idx >= 0, idx < typeTable.count else {
            throw TrussPackageCodecError.typeIndexOutOfRange(idx)
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
        let kind = try reader.u8()
        switch kind {
        case 0:
            let nkind = try decodeKind(reader.u8())
            let name = try reader.string()
            let confCount = try Int(reader.u32())
            var confs: [String] = []
            for _ in 0 ..< confCount {
                try confs.append(reader.string())
            }
            let superclass = try reader.stringOpt()
            let scope = try decodeScope(&reader)
            return .nominal(InterfaceNominal(
                kind: nkind,
                name: name,
                conformances: confs,
                superclass: superclass,
                scope: scope
            ))
        case 1:
            let name = try reader.string()
            let hasTarget = try reader.bool()
            let target = hasTarget ? try decodeRef(&reader) : nil
            return .typeAlias(InterfaceTypealias(name: name, target: target))
        case 2: return try .associatedType(InterfaceSimple(name: reader.string()))
        case 3: return try .builtin(InterfaceSimple(name: reader.string()))
        case 4: return try .genericParam(InterfaceSimple(name: reader.string()))
        default: throw TrussPackageCodecError.truncated
        }
    }

    private func decodeKind(_ raw: UInt8) throws -> InterfaceNominalKind {
        switch raw {
        case 0: .structType
        case 1: .classType
        case 2: .enumType
        case 3: .protocolType
        case 4: .actorType
        default: throw TrussPackageCodecError.truncated
        }
    }

    private func decodeValueDecl(_ reader: inout BitReader) throws -> InterfaceValue {
        let kind = try reader.u8()
        switch kind {
        case 0:
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
            return .function(InterfaceFunction(
                name: name,
                labels: labels,
                hasDefaults: defs,
                isVararg: vars,
                isVariadic: isVariadic,
                isStatic: isStatic,
                functionType: ft
            ))
        case 1:
            let name = try reader.string()
            let isMutable = try reader.bool()
            let hasType = try reader.bool()
            let t = hasType ? try decodeRef(&reader) : nil
            return .variable(InterfaceVariable(name: name, isMutable: isMutable, type: t))
        default: throw TrussPackageCodecError.truncated
        }
    }
}
