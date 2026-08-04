import TrussCore

public final class SymbolDumper {
    public init() {}

    public func dump(_ program: AST.Program) -> String {
        guard let packageSymbol = program.packageSymbol else { return "" }
        var out = "\(packageSymbol.name) (package)\n"
        dumpScope(packageSymbol.scope, into: &out, indent: 2)
        return out
    }

    private func dumpScope(_ scope: Scope, into out: inout String, indent: Int) {
        let pad = String(repeating: " ", count: indent)
        for (name, symbol) in scope.modules.sorted(by: { $0.key < $1.key }) {
            out += "\(pad)module \(name)\n"
            dumpScope(symbol.scope, into: &out, indent: indent + 2)
        }
        for (name, symbol) in scope.types.sorted(by: { $0.key < $1.key }) {
            out += "\(pad)type \(name) (\(symbolKind(symbol)))\n"
            if let nominal = symbol as? Symbol.NominalTypeSymbol {
                dumpScope(nominal.scope, into: &out, indent: indent + 2)
            }
        }
        for (name, symbols) in scope.values.sorted(by: { $0.key < $1.key }) {
            for symbol in symbols {
                out += "\(pad)value \(name) (\(symbolKind(symbol)))\n"
                if let function = symbol as? Symbol.FunctionSymbol {
                    dumpScope(function.scope, into: &out, indent: indent + 2)
                }
            }
        }
    }

    private func symbolKind(_ symbol: Symbol.Symbol) -> String {
        switch symbol {
        case is Symbol.NominalTypeSymbol: return "nominal"
        case is Symbol.TypeAliasSymbol: return "typealias"
        case is Symbol.GenericParamSymbol: return "generic-param"
        case is Symbol.CaseSymbol: return "case"
        case is Symbol.FunctionSymbol: return "function"
        case is Symbol.VariableSymbol: return "variable"
        default: return "unknown"
        }
    }
}
