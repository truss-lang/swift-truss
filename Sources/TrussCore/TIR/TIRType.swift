import SwiftAbstract

public enum TIRType {
    @abstractClass
    public class TIRType: Hashable {
        public let id: Id.TIRTypeId
        @abstractInit
        public init(id: Id.TIRTypeId) {
            self.id = id
        }

        @abstract
        public func isEqual(to other: TIRType) -> Bool
        @abstract
        public func hash(into hasher: inout Hasher)
    }

    public final class VoidType: TIRType {
        public override init(id: Id.TIRTypeId) {
            super.init(id: id)
        }

        public override func isEqual(to other: TIRType) -> Bool {
            other is VoidType
        }

        public override func hash(into hasher: inout Hasher) {}
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
        public init(id: Id.TIRTypeId, kind: PrimitiveKind, bitWidth: Int) {
            self.kind = kind
            self.bitWidth = bitWidth
            super.init(id: id)
        }

        public override func isEqual(to other: TIRType) -> Bool {
            if let other = other as? PrimitiveType {
                kind == other.kind && bitWidth == other.bitWidth
            } else {
                false
            }
        }

        public override func hash(into hasher: inout Hasher) {
            hasher.combine(kind)
            hasher.combine(bitWidth)
        }
    }

    public final class PointerType: TIRType {
        public let pointee: Id.TIRTypeId
        public init(id: Id.TIRTypeId, pointee: Id.TIRTypeId) {
            self.pointee = pointee
            super.init(id: id)
        }
    }

    public final class MetadataType: TIRType {
        public override init(id: Id.TIRTypeId) {
            super.init(id: id)
        }

        public override func isEqual(to other: TIRType) -> Bool {
            other is MetadataType
        }

        public override func hash(into hasher: inout Hasher) {}
    }

    @abstractClass
    public class NominalType: TIRType {
        public let name: String
        @abstractInit
        public init(id: Id.TIRTypeId, name: String) {
            self.name = name
            super.init(id: id)
        }
    }

    public final class StructType: NominalType {
        public var fields: [(name: String, type: Id.TIRTypeId)] = []
        public override init(id: Id.TIRTypeId, name: String) {
            super.init(id: id, name: name)
        }
    }

    public final class EnumType: NominalType {
        public var cases: [(name: String, associatedTypes: [Id.TIRTypeId])] = []
        public override init(id: Id.TIRTypeId, name: String) {
            super.init(id: id, name: name)
        }
    }

    public final class ClassType: NominalType {
        public var fields: [(name: String, type: Id.TIRTypeId)] = []
        public override init(id: Id.TIRTypeId, name: String) {
            super.init(id: id, name: name)
        }
    }

    public final class TupleType: TIRType {
        public struct Element: Hashable, Equatable {
            public let label: String?
            public let type: Id.TIRTypeId
            public init(label: String?, type: Id.TIRTypeId) {
                self.label = label
                self.type = type
            }
        }

        public var elements: [Element]
        public init(id: Id.TIRTypeId, elements: [Element]) {
            self.elements = elements
            super.init(id: id)
        }
    }

    public final class FunctionType: TIRType {
        public let parameters: [Id.TIRTypeId]
        public let returnType: Id.TIRTypeId
        public let isVariadic: Bool
        public init(id: Id.TIRTypeId, parameters: [Id.TIRTypeId], returnType: Id.TIRTypeId, isVariadic: Bool) {
            self.parameters = parameters
            self.returnType = returnType
            self.isVariadic = isVariadic
            super.init(id: id)
        }
    }
}

extension TIRType.TIRType: Equatable {
    public static func == (lhs: TIRType.TIRType, rhs: TIRType.TIRType) -> Bool {
        if type(of: lhs) == type(of: rhs) {
            lhs.isEqual(to: rhs)
        } else {
            false
        }
    }
}
