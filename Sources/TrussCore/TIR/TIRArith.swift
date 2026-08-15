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
