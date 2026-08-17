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

    final class Arith: Instruction {
        public let op: ArithOp
        public let operands: [Value]
        public init(_ op: ArithOp, operands: [Value], ty: Id.TIRTypeId, name: String) {
            self.op = op
            self.operands = operands
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitArith(self, additional: additional)
        }
    }
}
