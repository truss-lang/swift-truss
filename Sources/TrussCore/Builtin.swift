import SwiftAbstract

public enum Builtin {
    public static let packageName = "Builtin"

    public struct TypeInfo: Sendable {
        public let name: String
        public let kind: TIRType.PrimitiveKind
        public let bitWidth: Int
        public init(name: String, kind: TIRType.PrimitiveKind, bitWidth: Int) {
            self.name = name
            self.kind = kind
            self.bitWidth = bitWidth
        }
    }

    public static let typeInfos: [TypeInfo] = [
        TypeInfo(name: "Int8", kind: .Signed, bitWidth: 8),
        TypeInfo(name: "Int16", kind: .Signed, bitWidth: 16),
        TypeInfo(name: "Int32", kind: .Signed, bitWidth: 32),
        TypeInfo(name: "Int64", kind: .Signed, bitWidth: 64),
        TypeInfo(name: "Int128", kind: .Signed, bitWidth: 128),
        TypeInfo(name: "UInt8", kind: .Unsigned, bitWidth: 8),
        TypeInfo(name: "UInt16", kind: .Unsigned, bitWidth: 16),
        TypeInfo(name: "UInt32", kind: .Unsigned, bitWidth: 32),
        TypeInfo(name: "UInt64", kind: .Unsigned, bitWidth: 64),
        TypeInfo(name: "UInt128", kind: .Unsigned, bitWidth: 128),
        TypeInfo(name: "Float32", kind: .Float, bitWidth: 32),
        TypeInfo(name: "Float64", kind: .Float, bitWidth: 64),
        TypeInfo(name: "Bool", kind: .Bool, bitWidth: 1),
        TypeInfo(name: "Char", kind: .Char, bitWidth: 32),
    ]

    @discardableResult
    public static func install(context: Context) -> Symbol.PackageSymbol {
        if let existing = context.name2Package[packageName] {
            return existing
        }
        let package = Symbol.PackageSymbol(id: context.nextSymbolId, name: packageName)
        for info in typeInfos {
            let symbol = Symbol.BuiltinTypeSymbol(id: context.nextSymbolId, name: info.name)
            context.register(symbol: symbol)
            package.scope.types[info.name] = symbol
        }
        context.register(packageSymbol: package)
        return package
    }
}
