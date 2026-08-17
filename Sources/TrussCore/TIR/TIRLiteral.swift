import SwiftAbstract

public extension TIR {
    @abstractClass
    class Literal: Value {
        @abstractInit
        public override init(ty: Id.TIRTypeId, name: String) {
            super.init(ty: ty, name: name)
        }
    }

    final class IntegerLiteral: Literal {
        public let value: UInt64
        public init(value: UInt64, ty: Id.TIRTypeId, name: String) {
            self.value = value
            super.init(ty: ty, name: name)
        }
    }

    final class FloatLiteral: Literal {
        public let value: Float64
        public init(value: Float64, ty: Id.TIRTypeId, name: String) {
            self.value = value
            super.init(ty: ty, name: name)
        }
    }

    final class CharLiteral: Literal {
        public let value: Character
        public init(value: Character, ty: Id.TIRTypeId, name: String) {
            self.value = value
            super.init(ty: ty, name: name)
        }
    }

    final class BoolLiteral: Literal {
        public let value: Bool
        public init(value: Bool, ty: Id.TIRTypeId, name: String) {
            self.value = value
            super.init(ty: ty, name: name)
        }
    }

    final class StringLiteral: Literal {
        public let value: String
        public init(value: String, ty: Id.TIRTypeId, name: String) {
            self.value = value
            super.init(ty: ty, name: name)
        }
    }

    final class NullptrLiteral: Literal {
        public override init(ty: Id.TIRTypeId, name: String) {
            super.init(ty: ty, name: name)
        }
    }
}
