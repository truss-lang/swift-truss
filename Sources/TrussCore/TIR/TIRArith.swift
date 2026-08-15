import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    enum ArithOp: String {
        case Add = "add"
        case Sub = "sub"
        case Mul = "mul"
        case Div = "div"
        case Rem = "rem"
        case Neg = "neg"
        case Not = "not"
        case Bitnot = "bitnot"
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
        public init(_ op: ArithOp, operands: [Value], sourceRange: SourceRange) {
            self.op = op
            self.operands = operands
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitArith(self, additional: additional)
        }
    }
}
