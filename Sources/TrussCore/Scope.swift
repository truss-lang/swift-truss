import SwiftBetterDiagnostic

public final class Scope {
    public var types: [String: Symbol.Symbol] = [:]
    public var values: [String: [Symbol.Symbol]] = [:]
    public var modules: [String: Symbol.ModuleSymbol] = [:]
    public init() {}
}

public extension Scope {
    @discardableResult
    func registerType(_ symbol: Symbol.Symbol, at token: Token, context: Context)
        -> Bool
    {
        if symbol.sourceToken == nil {
            symbol.sourceToken = token
        }
        if types[symbol.name] != nil {
            context.emitError("invalid redeclaration of type '\(symbol.name)'", at: token)
            return false
        }
        types[symbol.name] = symbol
        return true
    }

    @discardableResult
    func registerValue(_ symbol: Symbol.Symbol, at token: Token, context: Context)
        -> Bool
    {
        if symbol.sourceToken == nil {
            symbol.sourceToken = token
        }
        if let existing = values[symbol.name] {
            if symbol is Symbol.FunctionSymbol,
               existing.allSatisfy({ $0 is Symbol.FunctionSymbol })
            {
                values[symbol.name]!.append(symbol)
                return true
            }
            context.emitError("invalid redeclaration of '\(symbol.name)'", at: token)
            return false
        }
        values[symbol.name] = [symbol]
        return true
    }

    @discardableResult
    func registerModule(_ symbol: Symbol.ModuleSymbol) -> Bool {
        if modules[symbol.name] != nil {
            return false
        }
        modules[symbol.name] = symbol
        return true
    }
}
