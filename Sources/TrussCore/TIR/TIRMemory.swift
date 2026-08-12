import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class AllocStack: Instruction {
        public let allocatedType: TIRType.TIRType
        public init(_ allocatedType: TIRType.TIRType, sourceRange: SourceRange) {
            self.allocatedType = allocatedType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAllocStack(self, additional: additional)
        }
    }

    final class AllocCell: Instruction {
        public let allocatedType: TIRType.TIRType
        public init(_ allocatedType: TIRType.TIRType, sourceRange: SourceRange) {
            self.allocatedType = allocatedType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAllocCell(self, additional: additional)
        }
    }

    final class AllocRef: Instruction {
        public let referenceType: TIRType.ReferenceType
        public init(_ referenceType: TIRType.ReferenceType, sourceRange: SourceRange) {
            self.referenceType = referenceType
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAllocRef(self, additional: additional)
        }
    }

    final class DeallocStack: Instruction {
        public let address: Value
        public init(_ address: Value, sourceRange: SourceRange) {
            self.address = address
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeallocStack(self, additional: additional)
        }
    }

    final class DeallocCell: Instruction {
        public let address: Value
        public init(_ address: Value, sourceRange: SourceRange) {
            self.address = address
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeallocCell(self, additional: additional)
        }
    }

    final class DeallocRef: Instruction {
        public let reference: Value
        public init(_ reference: Value, sourceRange: SourceRange) {
            self.reference = reference
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeallocRef(self, additional: additional)
        }
    }

    final class Load: Instruction {
        public let address: Value
        public init(_ address: Value, sourceRange: SourceRange) {
            self.address = address
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitLoad(self, additional: additional)
        }
    }

    final class Store: Instruction {
        public let value: Value
        public let address: Value
        public init(_ value: Value, to address: Value, sourceRange: SourceRange) {
            self.value = value
            self.address = address
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStore(self, additional: additional)
        }
    }

    final class ProjectCell: Instruction {
        public let address: Value
        public init(_ address: Value, sourceRange: SourceRange) {
            self.address = address
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitProjectCell(self, additional: additional)
        }
    }

    final class RefElementAddr: Instruction {
        public let reference: Value
        public let fieldIndex: Int
        public let fieldName: String
        public init(
            _ reference: Value, fieldIndex: Int, fieldName: String, sourceRange: SourceRange
        ) {
            self.reference = reference
            self.fieldIndex = fieldIndex
            self.fieldName = fieldName
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitRefElementAddr(self, additional: additional)
        }
    }

    final class StructElementAddr: Instruction {
        public let structAddress: Value
        public let fieldIndex: Int
        public let fieldName: String
        public init(
            _ structAddress: Value, fieldIndex: Int, fieldName: String, sourceRange: SourceRange
        ) {
            self.structAddress = structAddress
            self.fieldIndex = fieldIndex
            self.fieldName = fieldName
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStructElementAddr(self, additional: additional)
        }
    }

    final class TupleElementAddr: Instruction {
        public let tupleAddress: Value
        public let index: Int
        public init(_ tupleAddress: Value, index: Int, sourceRange: SourceRange) {
            self.tupleAddress = tupleAddress
            self.index = index
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTupleElementAddr(self, additional: additional)
        }
    }

    final class AddressToPointer: Instruction {
        public let address: Value
        public init(_ address: Value, sourceRange: SourceRange) {
            self.address = address
            super.init(sourceRange)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAddressToPointer(self, additional: additional)
        }
    }
}
