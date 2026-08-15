import SwiftAbstract

public enum Builtin {
    public static let packageName = "Builtin"

    public static let arithOpNames = ["add", "sub", "mul", "div", "rem", "neg"]

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

    public static func builtinFunctionInfo(named name: String) -> (opName: String, typeName: String)? {
        let prefix = "builtin_"
        guard name.hasPrefix(prefix) else { return nil }
        let rest = name.dropFirst(prefix.count)
        guard let separator = rest.firstIndex(of: "_") else { return nil }
        let opName = String(rest[..<separator])
        let typeName = String(rest[rest.index(after: separator)...])
        guard arithOpNames.contains(opName) else { return nil }
        return (opName, typeName)
    }

    @discardableResult
    public static func install(context: Context) -> Symbol.PackageSymbol {
        if let existing = context.name2Package[packageName] {
            return existing
        }
        let package = Symbol.PackageSymbol(id: context.nextSymbolId, name: packageName)
        for info in typeInfos {
            let symbol = Symbol.BuiltinTypeSymbol(id: context.nextSymbolId, name: info.name)
            symbol.access = .Public
            context.register(symbol: symbol)
            package.scope.types[info.name] = symbol
            let builtinType = TrussType.BuiltinType(info.name)
            for opName in arithOpNames {
                let functionName = "builtin_\(opName)_\(info.name.lowercased())"
                let function = Symbol.FunctionSymbol(
                    id: context.nextSymbolId, name: functionName,
                    locals: [], scope: package.scope,
                    signature: Symbol.FunctionSignature(
                        labels: opName == "neg" ? [nil] : [nil, nil],
                        hasDefaults: opName == "neg" ? [false] : [false, false],
                        isVararg: opName == "neg" ? [false] : [false, false],
                        isVariadic: false
                    )
                )
                function.isBuiltin = true
                let parameterType = builtinType
                let parameters: [TrussType.FunctionType.Parameter] =
                    opName == "neg"
                        ? [TrussType.FunctionType.Parameter(label: nil, type: parameterType)]
                        : [
                            TrussType.FunctionType.Parameter(label: nil, type: parameterType),
                            TrussType.FunctionType.Parameter(label: nil, type: parameterType),
                        ]
                function.functionType = TrussType.FunctionType(
                    parameters: parameters, returnType: builtinType
                )
                context.register(symbol: function)
                package.scope.values[functionName, default: []].append(function)
            }
        }
        context.register(packageSymbol: package)
        return package
    }
}
