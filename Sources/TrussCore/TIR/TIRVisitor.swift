import SwiftAbstract
import SwiftBetterDiagnostic

extension TIR {
    @abstractClass
    open class Visitor {
        @abstractInit
        public init()

        @discardableResult
        open func visit(_ instruction: TIR.Instruction, additional: Any? = nil) -> Any? {
            instruction.accept(self, additional: additional)
        }

        @discardableResult
        open func visitAllocStack(_ instruction: AllocStack, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitAllocCell(_ instruction: AllocCell, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitAllocRef(_ instruction: AllocRef, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocStack(_ instruction: DeallocStack, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocCell(_ instruction: DeallocCell, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocRef(_ instruction: DeallocRef, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitLoad(_ instruction: Load, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitStore(_ instruction: Store, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitProjectCell(_ instruction: ProjectCell, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitRefElementAddr(_ instruction: RefElementAddr, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitStructElementAddr(_ instruction: StructElementAddr, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitTupleElementAddr(_ instruction: TupleElementAddr, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitAddressToPointer(_ instruction: AddressToPointer, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitCopyValue(_ instruction: CopyValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDestroyValue(_ instruction: DestroyValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitRetainValue(_ instruction: RetainValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitReleaseValue(_ instruction: ReleaseValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBorrowValue(_ instruction: BorrowValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitEndBorrow(_ instruction: EndBorrow, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitMoveValue(_ instruction: MoveValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitFunctionRef(_ instruction: FunctionRef, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitClosure(_ instruction: Closure, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitClassMethod(_ instruction: ClassMethod, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitSuperMethod(_ instruction: SuperMethod, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitWitnessMethod(_ instruction: WitnessMethod, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitApply(_ instruction: Apply, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitTryApply(_ instruction: TryApply, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitPartialApply(_ instruction: PartialApply, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitUpcast(_ instruction: Upcast, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitUncheckedRefCast(_ instruction: UncheckedRefCast, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitInitExistential(_ instruction: InitExistential, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitOpenExistential(_ instruction: OpenExistential, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitBranch(_ instruction: Branch, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitCondBranch(_ instruction: CondBranch, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitSwitchEnum(_ instruction: SwitchEnum, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitSwitchValue(_ instruction: SwitchValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitReturn(_ instruction: Return, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitThrow(_ instruction: Throw, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitUnreachable(_ instruction: Unreachable, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitTrap(_ instruction: Trap, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitIntegerLiteral(_ instruction: IntegerLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitFloatLiteral(_ instruction: FloatLiteral, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitStringLiteral(_ instruction: StringLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitCharLiteral(_ instruction: CharLiteral, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBoolLiteral(_ instruction: BoolLiteral, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitNullLiteral(_ instruction: NullLiteral, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitVoidLiteral(_ instruction: VoidLiteral, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitArrayValue(_ instruction: ArrayValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDictionaryValue(_ instruction: DictionaryValue, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitStructValue(_ instruction: StructValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitTupleValue(_ instruction: TupleValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitEnumValue(_ instruction: EnumValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitInitEnumDataAddr(_ instruction: InitEnumDataAddr, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitUncheckedEnumData(_ instruction: UncheckedEnumData, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitExistentialMetatype(_ instruction: ExistentialMetatype, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitGenericMetatype(_ instruction: GenericMetatype, additional: Any? = nil)
            -> Any?
        { nil }

        @discardableResult
        open func visitOpenArchetype(_ instruction: OpenArchetype, additional: Any? = nil) -> Any? {
            nil
        }
    }
}
