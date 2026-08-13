import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class InlineAsm: Instruction {
        public let template: String
        public let constraints: [String]
        public let operands: [Value]
        public let options: [String]
        public init(
            template: String, constraints: [String], operands: [Value], options: [String],
            sourceRange: SourceRange
        ) {
            self.template = template
            self.constraints = constraints
            self.operands = operands
            self.options = options
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitInlineAsm(self, additional: additional)
        }
    }
}
