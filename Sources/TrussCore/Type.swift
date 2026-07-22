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
    public final class NamedType: TrussType {
        public let name: String
        public var symbol: Symbol.Symbol? = nil
        public init(_ name: String) {
            self.name = name
        }
    }
}
