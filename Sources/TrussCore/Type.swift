import SwiftAbstract

public enum TrussType {
    @abstractClass
    public class TrussType {
        @abstractInit
        public init() {}
    }

    public final class VoidType: TrussType, @unchecked Sendable {
        public static let INSTANCE = VoidType()
        private override init() {}
    }

    public final class NeverType: TrussType, @unchecked Sendable {
        public static let INSTANCE = NeverType()
        private override init() {}
    }

    @abstractClass
    public class NominalType: TrussType {
        public let id: Id.TypeId
        public let name: String
        public var symbol: Symbol.NominalTypeSymbol? = nil
        @abstractInit
        public init(_ id: Id.TypeId, _ name: String) {
            self.id = id
            self.name = name
        }
    }

    public final class StructType: NominalType {
        public var conformances: [ProtocolType] = []
        public init(id: Id.TypeId, name: String) {
            super.init(id, name)
        }
    }

    public final class ClassType: NominalType {
        public var superclass: ClassType?
        public var conformances: [ProtocolType] = []
        public init(id: Id.TypeId, name: String) {
            super.init(id, name)
        }
    }

    public final class EnumType: NominalType {
        public var conformances: [ProtocolType] = []
        public init(id: Id.TypeId, name: String) {
            super.init(id, name)
        }
    }

    public final class ProtocolType: NominalType {
        public var conformances: [ProtocolType] = []
        public init(id: Id.TypeId, name: String) {
            super.init(id, name)
        }
    }

    public final class ActorType: NominalType {
        public var conformances: [ProtocolType] = []
        public init(id: Id.TypeId, name: String) {
            super.init(id, name)
        }
    }
}
