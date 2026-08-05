import SwiftAbstract

public enum Symbol {
    @abstractClass
    public class Symbol {
        public var parent: Id.SymbolId?
        public let id: Id.SymbolId
        public let name: String
        public var sourceToken: Token?
        @abstractInit
        public init(_ id: Id.SymbolId, _ name: String) {
            self.id = id
            self.name = name
        }
    }

    public final class PackageSymbol: Symbol {
        public let scope: Scope = .init()
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ModuleSymbol: Symbol {
        public let scope: Scope = .init()
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    @abstractClass
    public class NominalTypeSymbol: Symbol {
        public var conformances: [ProtocolSymbol] = []
        public let scope: Scope = .init()
        @abstractInit
        public override init(_ id: Id.SymbolId, _ name: String) {
            super.init(id, name)
        }
    }

    public final class StructSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ClassSymbol: NominalTypeSymbol {
        public var superclass: ClassSymbol?
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class EnumSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ProtocolSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ActorSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class AssociatedTypeSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class TypeAliasSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class GenericParamSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class CaseSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public struct FunctionSignature {
        public let labels: [String?]
        public let hasDefaults: [Bool]
        public let isVararg: [Bool]
        public init(labels: [String?], hasDefaults: [Bool], isVararg: [Bool]) {
            self.labels = labels
            self.hasDefaults = hasDefaults
            self.isVararg = isVararg
        }
    }

    public final class FunctionSymbol: Symbol {
        public let scope: Scope
        public var locals: [VariableSymbol]
        public let signature: FunctionSignature
        public init(
            id: Id.SymbolId, name: String, locals: [VariableSymbol],
            scope: Scope, signature: FunctionSignature
        ) {
            self.locals = locals
            self.scope = scope
            self.signature = signature
            super.init(id, name)

            for local in locals {
                local.parent = self.id
            }
        }
    }

    public final class VariableSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class Dumper {
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
                if let nominal = symbol as? NominalTypeSymbol {
                    dumpScope(nominal.scope, into: &out, indent: indent + 2)
                }
            }
            for (name, symbols) in scope.values.sorted(by: { $0.key < $1.key }) {
                for symbol in symbols {
                    out += "\(pad)value \(name) (\(symbolKind(symbol)))\n"
                    if let function = symbol as? FunctionSymbol {
                        dumpScope(function.scope, into: &out, indent: indent + 2)
                    }
                }
            }
        }

        private func symbolKind(_ symbol: Symbol) -> String {
            switch symbol {
            case is StructSymbol: "struct"
            case is ClassSymbol: "class"
            case is EnumSymbol: "enum"
            case is ProtocolSymbol: "protocol"
            case is ActorSymbol: "actor"
            case is AssociatedTypeSymbol: "associated-type"
            case is TypeAliasSymbol: "typealias"
            case is GenericParamSymbol: "generic-param"
            case is CaseSymbol: "case"
            case is FunctionSymbol: "function"
            case is VariableSymbol: "variable"
            default: "unknown"
            }
        }
    }
}
