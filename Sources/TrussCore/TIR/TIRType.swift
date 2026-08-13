import SwiftAbstract
import SwiftBetterDiagnostic

public enum TIRType {
    public enum Ownership {
        case Owned
        case Borrowing
        case Trivial
        case MutableBorrowing
    }

    @abstractClass
    public class TIRType {
        @abstractInit
        public init() {}
    }

    @abstractClass
    public class NominalType: TIRType {
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
        public override init(_ id: Id.TypeId, _ name: String) {
            super.init(id, name)
        }
    }

    public final class EnumType: NominalType {
        public override init(_ id: Id.TypeId, _ name: String) {
            super.init(id, name)
        }
    }

    public final class ReferenceType: NominalType {
        public override init(_ id: Id.TypeId, _ name: String) {
            super.init(id, name)
        }
    }

    public final class ProtocolType: NominalType {
        public override init(_ id: Id.TypeId, _ name: String) {
            super.init(id, name)
        }
    }

    public enum PrimitiveKind: Sendable {
        case Signed
        case Unsigned
        case Float
        case Bool
        case Char
    }

    public final class PrimitiveType: TIRType {
        public let kind: PrimitiveKind
        public let bitWidth: Int
        public init(kind: PrimitiveKind, bitWidth: Int) {
            self.kind = kind
            self.bitWidth = bitWidth
        }
    }

    public final class VoidType: TIRType {
        public override init() {}
    }

    public final class TupleType: TIRType {
        public struct Element {
            public let label: String?
            public let type: TIRType
            public init(label: String?, type: TIRType) {
                self.label = label
                self.type = type
            }
        }

        public let elements: [Element]

        public init(_ elements: [Element]) {
            self.elements = elements
        }
    }

    public final class OptionalType: TIRType {
        public let wrapped: TIRType
        public init(_ wrapped: TIRType) {
            self.wrapped = wrapped
        }
    }

    public final class FunctionType: TIRType {
        public struct Parameter {
            public let label: String?
            public let type: TIRType
            public init(label: String?, type: TIRType) {
                self.label = label
                self.type = type
            }
        }

        public let parameters: [Parameter]
        public let isAsync: Bool
        public let isThrowing: Bool
        public let throwsTypes: [TIRType]
        public let returnType: TIRType
        public init(
            parameters: [Parameter], isAsync: Bool = false, isThrowing: Bool = false,
            throwsTypes: [TIRType] = [], returnType: TIRType
        ) {
            self.parameters = parameters
            self.isAsync = isAsync
            self.isThrowing = isThrowing
            self.throwsTypes = throwsTypes
            self.returnType = returnType
        }
    }

    public final class AddressType: TIRType {
        public let pointee: TIRType
        public init(_ pointee: TIRType) {
            self.pointee = pointee
        }
    }

    public final class MetatypeType: TIRType {
        public let instance: TIRType
        public init(_ instance: TIRType) {
            self.instance = instance
        }
    }

    public final class ExistentialType: TIRType {
        public let protocolTypes: [TIRType]
        public init(_ protocolTypes: [TIRType]) {
            self.protocolTypes = protocolTypes
        }
    }

    public final class ArchetypeType: TIRType {
        public let name: String
        public var genericParam: Symbol.GenericParamSymbol? = nil
        public init(_ name: String, _ genericParam: Symbol.GenericParamSymbol? = nil) {
            self.name = name
            self.genericParam = genericParam
        }
    }

    public final class PointerType: TIRType {
        public let pointee: TIRType
        public init(_ pointee: TIRType) {
            self.pointee = pointee
        }
    }

    public final class GenericSignature {
        public let parameters: [Symbol.GenericParamSymbol]
        public var requirements: [Requirement] = []
        public init(parameters: [Symbol.GenericParamSymbol]) {
            self.parameters = parameters
        }
    }

    public struct Requirement {
        public let subject: TIRType
        public enum Kind {
            case Conformance(TIRType)
            case Equality(TIRType)
        }

        public let kind: Kind
        public init(subject: TIRType, kind: Kind) {
            self.subject = subject
            self.kind = kind
        }
    }
}
