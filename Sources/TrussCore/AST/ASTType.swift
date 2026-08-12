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

    public final class ErrorType: TrussType, @unchecked Sendable {
        public static let INSTANCE = ErrorType()
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

    public final class OptionalType: TrussType {
        public let wrapped: TrussType
        public init(_ wrapped: TrussType) {
            self.wrapped = wrapped
        }
    }

    public final class TupleType: TrussType {
        public struct Element {
            public let label: String?
            public let type: TrussType
            public init(label: String?, type: TrussType) {
                self.label = label
                self.type = type
            }
        }

        public let elements: [Element]
        public init(_ elements: [Element]) {
            self.elements = elements
        }
    }

    public final class FunctionType: TrussType {
        public struct Parameter {
            public let label: String?
            public let type: TrussType
            public init(label: String?, type: TrussType) {
                self.label = label
                self.type = type
            }
        }

        public let parameters: [Parameter]
        public let isAsync: Bool
        public let isThrowing: Bool
        public let throwsTypes: [TrussType]
        public let returnType: TrussType
        public init(
            parameters: [Parameter], isAsync: Bool = false, isThrowing: Bool = false,
            throwsTypes: [TrussType] = [], returnType: TrussType = VoidType.INSTANCE
        ) {
            self.parameters = parameters
            self.isAsync = isAsync
            self.isThrowing = isThrowing
            self.throwsTypes = throwsTypes
            self.returnType = returnType
        }
    }

    public final class CompositionType: TrussType {
        public let members: [TrussType]
        public init(_ members: [TrussType]) {
            self.members = members
        }
    }

    public final class VariadicType: TrussType {
        public let base: TrussType
        public init(_ base: TrussType) {
            self.base = base
        }
    }

    public final class GenericInstantiation: TrussType {
        public let base: NominalType
        public let arguments: [TrussType]
        public init(base: NominalType, arguments: [TrussType]) {
            self.base = base
            self.arguments = arguments
        }
    }

    public final class TypeVariableType: TrussType {
        public let id: Id.TypeVariableId
        public let name: String?
        public var binding: TrussType? = nil
        public init(_ id: Id.TypeVariableId, _ name: String? = nil) {
            self.id = id
            self.name = name
        }
    }

    public final class ForallType: TrussType {
        public let parameters: [Symbol.GenericParamSymbol]
        public let body: TrussType
        public init(parameters: [Symbol.GenericParamSymbol], body: TrussType) {
            self.parameters = parameters
            self.body = body
        }
    }

    public final class GenericParamType: TrussType {
        public let name: String
        public let symbol: Symbol.GenericParamSymbol?
        public init(_ name: String, _ symbol: Symbol.GenericParamSymbol? = nil) {
            self.name = name
            self.symbol = symbol
        }
    }

    public final class BuiltinType: TrussType {
        public let name: String
        public init(_ name: String) {
            self.name = name
        }
    }
}
