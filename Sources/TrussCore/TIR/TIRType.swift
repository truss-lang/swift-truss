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
        public var id: Int = -1
        @abstractInit
        public init() {}
    }

    @abstractClass
    public class NominalType: TIRType {
        public let name: String
        @abstractInit
        public init(_ name: String) {
            self.name = name
        }
    }

    public final class StructType: NominalType {
        public var fields: [(name: String, type: Int)] = []
        public override init(_ name: String) {
            super.init(name)
        }
    }

    public final class EnumType: NominalType {
        public var cases: [(name: String, associatedTypeIds: [Int])] = []
        public override init(_ name: String) {
            super.init(name)
        }
    }

    public final class ReferenceType: NominalType {
        public var fields: [(name: String, type: Int)] = []
        public override init(_ name: String) {
            super.init(name)
        }
    }

    public final class ProtocolType: NominalType {
        public override init(_ name: String) {
            super.init(name)
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
            public let type: Int
            public init(label: String?, type: Int) {
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
        public let wrapped: Int
        public init(_ wrapped: Int) {
            self.wrapped = wrapped
        }
    }

    public final class FunctionType: TIRType {
        public struct Parameter {
            public let label: String?
            public let type: Int
            public init(label: String?, type: Int) {
                self.label = label
                self.type = type
            }
        }

        public let parameters: [Parameter]
        public let isVariadic: Bool
        public let isAsync: Bool
        public let isThrowing: Bool
        public let throwsTypes: [Int]
        public let returnType: Int
        public init(
            parameters: [Parameter], isVariadic: Bool = false, isAsync: Bool = false, isThrowing: Bool = false,
            throwsTypes: [Int] = [], returnType: Int
        ) {
            self.parameters = parameters
            self.isVariadic = isVariadic
            self.isAsync = isAsync
            self.isThrowing = isThrowing
            self.throwsTypes = throwsTypes
            self.returnType = returnType
        }
    }

    public final class AddressType: TIRType {
        public let pointee: Int
        public init(_ pointee: Int) {
            self.pointee = pointee
        }
    }

    public final class MetatypeType: TIRType {
        public let instance: Int
        public init(_ instance: Int) {
            self.instance = instance
        }
    }

    public final class ExistentialType: TIRType {
        public let protocolTypes: [Int]
        public init(_ protocolTypes: [Int]) {
            self.protocolTypes = protocolTypes
        }
    }

    public final class ArchetypeType: TIRType {
        public let name: String
        public init(_ name: String) {
            self.name = name
        }
    }

    public final class PointerType: TIRType {
        public let pointee: Int
        public init(_ pointee: Int) {
            self.pointee = pointee
        }
    }

    public final class GenericSignature {
        public let parameters: [String]
        public var requirements: [Requirement] = []
        public init(parameters: [String]) {
            self.parameters = parameters
        }
    }

    public struct Requirement {
        public let subject: Int
        public enum Kind {
            case Conformance(Int)
            case Equality(Int)
        }

        public let kind: Kind
        public init(subject: Int, kind: Kind) {
            self.subject = subject
            self.kind = kind
        }
    }
}
