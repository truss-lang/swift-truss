import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class InlineAsm: Instruction {
        public let template: String
        public let constraints: [String]
        public let operands: [Value]
        public let options: [String]
        public init(
            registry: Registry, template: String, constraints: [String], operands: [Value], options: [String],
        ) {
            self.template = template
            self.constraints = constraints
            self.operands = operands
            self.options = options
            super.init(ty: registry.voidType().id, name: "")
        }
    }
}
