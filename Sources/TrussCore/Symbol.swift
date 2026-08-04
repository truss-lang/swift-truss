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

    public final class NominalTypeSymbol: Symbol {
        public let scope: Scope = .init()
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
}
