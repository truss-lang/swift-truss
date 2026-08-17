public enum Id {
    public struct SourceId: Hashable, Sendable, Equatable {
        public let id: UInt64
        public init(_ id: UInt64) {
            self.id = id
        }
    }

    public struct SymbolId: Hashable, Sendable, Equatable {
        public let id: UInt64
        public init(_ id: UInt64) {
            self.id = id
        }
    }

    public struct ASTTypeId: Hashable, Sendable, Equatable {
        public let id: UInt64
        public init(_ id: UInt64) {
            self.id = id
        }
    }

    public struct TypeVariableId: Hashable, Sendable, Equatable {
        public let id: UInt64
        public init(_ id: UInt64) {
            self.id = id
        }
    }

    public struct TIRFunctionId: Hashable, Sendable, Equatable {
        public let id: UInt64
        public init(_ id: UInt64) {
            self.id = id
        }
    }

    public struct TIRTypeId: Hashable, Sendable, Equatable {
        public let id: UInt64
        public init(_ id: UInt64) {
            self.id = id
        }
    }
}
