import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    enum ArithOp: String {
        case Add = "add"
        case Sub = "sub"
        case Mul = "mul"
        case SDiv = "sdiv"
        case UDiv = "udiv"
        case SRem = "srem"
        case URem = "urem"
        case FDiv = "fdiv"
        case FRem = "frem"
        case Neg = "neg"
        case Not = "not"
        case Bitnot = "bitnot"
        case And = "and"
        case Or = "or"
        case Xor = "xor"
        case Shl = "shl"
        case Shr = "shr"
        case Eq = "eq"
        case Ne = "ne"
        case Lt = "lt"
        case Le = "le"
        case Gt = "gt"
        case Ge = "ge"

        public var isUnary: Bool {
            switch self {
            case .Neg, .Not, .Bitnot:
                true
            default:
                false
            }
        }

        public var isCompare: Bool {
            switch self {
            case .Eq, .Ne, .Lt, .Le, .Gt, .Ge:
                true
            default:
                false
            }
        }
    }

    final class UnaryArith: Instruction {
        public let op: ArithOp
        public let operand: Value
        public var result: Value
        public init(op: ArithOp, operand: Value, ty: Id.TIRTypeId, name: String) {
            self.op = op
            self.operand = operand
            result = InstructionResult(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitUnaryArith(self, additional: additional)
        }
    }

    final class BinaryArith: Instruction {
        public let op: ArithOp
        public let lhs: Value
        public let rhs: Value
        public var result: Value
        public init(op: ArithOp, lhs: Value, rhs: Value, ty: Id.TIRTypeId, name: String) {
            self.op = op
            self.lhs = lhs
            self.rhs = rhs
            result = InstructionResult(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitBinaryArith(self, additional: additional)
        }
    }
}
