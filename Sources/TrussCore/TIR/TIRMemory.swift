public extension TIR {
    final class AllocStack: Instruction {
        public let allocatedType: Id.TIRTypeId
        public init(registry: TIR.Registry, allocatedType: Id.TIRTypeId, name: String) {
            self.allocatedType = allocatedType
            super.init(ty: registry.pointerType(pointee: allocatedType).id, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAllocStack(self, additional: additional)
        }
    }

    final class DeallocStack: Instruction {
        public let value: Value
        public init(registry: Registry, value: Value) {
            self.value = value
            super.init(ty: registry.voidType().id, name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeallocStack(self, additional: additional)
        }
    }

    final class AllocHeap: Instruction {
        public let allocatedType: Id.TIRTypeId
        public init(registry: TIR.Registry, allocatedType: Id.TIRTypeId, name: String) {
            self.allocatedType = allocatedType
            super.init(ty: registry.pointerType(pointee: allocatedType).id, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAllocHeap(self, additional: additional)
        }
    }

    final class DeallocHeap: Instruction {
        public let value: Value
        public init(registry: Registry, value: Value) {
            self.value = value
            super.init(ty: registry.voidType().id, name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeallocHeap(self, additional: additional)
        }
    }

    final class AllocCell: Instruction {
        public let allocatedType: Id.TIRTypeId
        public init(registry: TIR.Registry, allocatedType: Id.TIRTypeId, name: String) {
            self.allocatedType = allocatedType
            super.init(ty: registry.pointerType(pointee: allocatedType).id, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitAllocCell(self, additional: additional)
        }
    }

    final class DeallocCell: Instruction {
        public let value: Value
        public init(registry: Registry, value: Value) {
            self.value = value
            super.init(ty: registry.voidType().id, name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitDeallocCell(self, additional: additional)
        }
    }

    final class Load: Instruction {
        public let ptr: Value
        public init(ptr: Value, ty: Id.TIRTypeId, name: String) {
            self.ptr = ptr
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitLoad(self, additional: additional)
        }
    }

    final class Store: Instruction {
        public let value: Value
        public let ptr: Value
        public init(registry: Registry, value: Value, ptr: Value) {
            self.value = value
            self.ptr = ptr
            super.init(ty: registry.voidType().id, name: "")
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStore(self, additional: additional)
        }
    }

    final class GlobalAddr: Instruction {
        public let global: GlobalVariable
        public init(registry: Registry, global: GlobalVariable, name: String) {
            self.global = global
            super.init(ty: registry.pointerType(pointee: global.type).id, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitGlobalAddr(self, additional: additional)
        }
    }

    final class StructElementAddr: Instruction {
        public let base: Value
        public let index: Int
        public init(registry: Registry, base: Value, index: Int, name: String) {
            self.base = base
            self.index = index
            super.init(ty: registry.elementPointerType(base: base.ty, at: index), name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitStructElementAddr(self, additional: additional)
        }
    }

    final class TupleElementAddr: Instruction {
        public let base: Value
        public let index: Int
        public init(registry: Registry, base: Value, index: Int, name: String) {
            self.base = base
            self.index = index
            super.init(ty: registry.elementPointerType(base: base.ty, at: index), name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitTupleElementAddr(self, additional: additional)
        }
    }

    final class RefElementAddr: Instruction {
        public let base: Value
        public let index: Int
        public init(registry: Registry, base: Value, index: Int, name: String) {
            self.base = base
            self.index = index
            super.init(ty: registry.elementPointerType(base: base.ty, at: index), name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitRefElementAddr(self, additional: additional)
        }
    }

    final class ProjectCell: Instruction {
        public let cell: Value
        public init(registry: Registry, cell: Value, name: String) {
            self.cell = cell
            super.init(ty: cell.ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitProjectCell(self, additional: additional)
        }
    }
}
