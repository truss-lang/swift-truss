import SwiftAbstract

extension TIR {
    @abstractClass
    open class Visitor {
        @abstractInit
        public init() {}

        @discardableResult
        open func visit(_ value: TIR.Value, additional: Any? = nil) -> Any? {
            value.accept(self, additional: additional)
        }

        @discardableResult
        open func visit(_ instruction: TIR.Instruction, additional: Any? = nil) -> Any? {
            instruction.accept(self, additional: additional)
        }

        @discardableResult
        open func visitParameter(_ parameter: Parameter, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitBlockArgument(
            _ argument: BlockArgument, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitIntegerLiteral(
            _ literal: IntegerLiteral, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitFloatLiteral(_ literal: FloatLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitCharLiteral(_ literal: CharLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitBoolLiteral(_ literal: BoolLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitStringLiteral(_ literal: StringLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitNullptrLiteral(_ literal: NullptrLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitVoidLiteral(_ literal: VoidLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitReturn(_ instruction: Return, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBranch(_ instruction: Branch, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitConditionalBranch(
            _ instruction: ConditionalBranch, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitUnreachable(_ instruction: Unreachable, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitPhi(_ instruction: Phi, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitSwitchEnum(_ instruction: SwitchEnum, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitExtractPayload(
            _ instruction: ExtractPayload, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitUnaryArith(_ instruction: UnaryArith, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBinaryArith(_ instruction: BinaryArith, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitGlobalAddr(_ value: GlobalAddr, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitAllocStack(_ instruction: AllocStack, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocStack(
            _ instruction: DeallocStack, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitAllocHeap(_ instruction: AllocHeap, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocHeap(_ instruction: DeallocHeap, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitAllocCell(_ instruction: AllocCell, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocCell(_ instruction: DeallocCell, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitLoad(_ instruction: Load, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitStore(_ instruction: Store, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitSizeOf(_ instruction: SizeOf, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitStructElementAddr(
            _ instruction: StructElementAddr, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitTupleElementAddr(
            _ instruction: TupleElementAddr, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitClassElementAddr(
            _ instruction: ClassElementAddr, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitProjectCell(_ instruction: ProjectCell, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitStructValue(_ instruction: StructValue, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitTupleValue(_ instruction: TupleValue, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitEnumValue(_ instruction: EnumValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitCall(_ instruction: Call, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitFunctionRef(_ instruction: FunctionRef, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitTryCall(_ instruction: TryCall, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitClosure(_ instruction: Closure, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitUpcast(_ instruction: Upcast, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitUncheckedRefCast(
            _ instruction: UncheckedRefCast, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitTypeMetadata(
            _ instruction: TypeMetadata, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitTypeMetadataConstant(
            _ instruction: TypeMetadataConstant, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitIsInstance(
            _ instruction: IsInstance, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitSuperclass(
            _ instruction: Superclass, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitTrap(_ instruction: Trap, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitRetain(_ instruction: Retain, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitRelease(_ instruction: Release, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitCopy(_ instruction: Copy, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDestroy(_ instruction: Destroy, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitInlineAsm(_ instruction: InlineAsm, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBuildExistential(
            _ instruction: BuildExistential, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitOpenExistential(
            _ instruction: OpenExistential, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitWitnessMethod(
            _ instruction: WitnessMethod, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitOpaqueWitnessMethod(
            _ instruction: OpaqueWitnessMethod, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitExistentialCopy(
            _ instruction: ExistentialCopy, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitExistentialDestroy(
            _ instruction: ExistentialDestroy, additional: Any? = nil
        ) -> Any? {
            nil
        }
    }
}
