import SwiftAbstract

public enum Symbol {
    @abstractClass
    public class Symbol {
        public var parent: Id.SymbolId? = nil
        public let id: Id.SymbolId
        public let name: String
        @abstractInit
        public init(_ id: Id.SymbolId, _ name: String) {
            self.id = id
            self.name = name
        }
    }
    public final class PackageSymbol: Symbol {
        public let scope: Scope = Scope()
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }
    public final class ModuleSymbol: Symbol {
        public let scope: Scope = Scope()
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }
    public final class FunctionSymbol: Symbol {
        public let scope: Scope
        public var locals: [VariableSymbol]
        public init(
            id: Id.SymbolId, name: String, locals: [VariableSymbol],
            scope: Scope
        ) {
            self.locals = locals
            self.scope = scope
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
