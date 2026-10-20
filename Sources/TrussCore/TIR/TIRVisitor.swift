import SwiftAbstract

extension TIR {
    enum Result {
        static func results(of instruction: Instruction) -> [Value] {
            switch instruction {
            case let i as Phi:
                [i.result]
            case let i as ExtractPayload:
                [i.result]
            case let i as UnaryArith:
                [i.result]
            case let i as BinaryArith:
                [i.result]
            case let i as AllocStack:
                [i.result]
            case let i as AllocHeap:
                [i.result]
            case let i as AllocCell:
                [i.result]
            case let i as Load:
                [i.result]
            case let i as StructElementAddr:
                [i.result]
            case let i as TupleElementAddr:
                [i.result]
            case let i as ClassElementAddr:
                [i.result]
            case let i as ProjectCell:
                [i.result]
            case let i as AddressToPointer:
                [i.result]
            case let i as PointerToAddress:
                [i.result]
            case let i as StructValue:
                [i.result]
            case let i as TupleValue:
                [i.result]
            case let i as EnumValue:
                [i.result]
            case let i as Call:
                i.result.map { [$0] } ?? []
            case let i as TryCall:
                i.result.map { [$0] } ?? []
            case let i as Closure:
                [i.result]
            case let i as VirtualMethod:
                [i.result]
            case let i as Upcast:
                [i.result]
            case let i as UncheckedRefCast:
                [i.result]
            case let i as NumericCast:
                [i.result]
            case let i as BitCast:
                [i.result]
            case let i as SizeOf:
                [i.result]
            case let i as TypeMetadata:
                [i.result]
            case let i as TypeMetadataConstant:
                [i.result]
            case let i as IsInstance:
                [i.result]
            case let i as Superclass:
                [i.result]
            case let i as Copy:
                [i.result]
            case let i as BuildExistential:
                [i.result]
            case let i as OpenExistential:
                [i.result]
            case let i as WitnessMethod:
                [i.result]
            case let i as OpaqueWitnessMethod:
                [i.result]
            case let i as ExistentialCopy:
                [i.result]
            default:
                []
            }
        }
    }

    enum Operands {
        static func operands(of instruction: Instruction) -> [Value] {
            switch instruction {
            case let i as Return:
                i.value.map { [$0] } ?? []
            case let i as Branch:
                i.arguments
            case let i as ConditionalBranch:
                [i.condition] + i.trueArguments + i.falseArguments
            case let i as SwitchEnum:
                [i.value] + i.cases.flatMap(\.arguments)
            case let i as ExtractPayload:
                [i.value]
            case let i as UnaryArith:
                [i.operand]
            case let i as BinaryArith:
                [i.lhs, i.rhs]
            case let i as DeallocStack:
                [i.value]
            case let i as DeallocHeap:
                [i.value]
            case let i as DeallocCell:
                [i.value]
            case let i as Load:
                [i.ptr]
            case let i as Store:
                [i.value, i.ptr]
            case let i as StructElementAddr:
                [i.base]
            case let i as TupleElementAddr:
                [i.base]
            case let i as ClassElementAddr:
                [i.base]
            case let i as ProjectCell:
                [i.cell]
            case let i as AddressToPointer:
                [i.address]
            case let i as PointerToAddress:
                [i.pointer]
            case let i as StructValue:
                i.fields
            case let i as TupleValue:
                i.elements
            case let i as EnumValue:
                i.payload.map { [$0] } ?? []
            case let i as Call:
                [i.callee] + i.arguments
            case let i as TryCall:
                [i.callee] + i.arguments + (i.errorCell.map { [$0] } ?? [])
            case let i as Closure:
                [i.function] + i.captures
            case let i as VirtualMethod:
                [i.selfValue]
            case let i as Upcast:
                [i.value]
            case let i as UncheckedRefCast:
                [i.value]
            case let i as NumericCast:
                [i.value]
            case let i as BitCast:
                [i.value]
            case let i as TypeMetadata:
                [i.value]
            case let i as IsInstance:
                [i.metadata, i.target]
            case let i as Superclass:
                [i.metadata]
            case let i as Retain:
                [i.value]
            case let i as Release:
                [i.value]
            case let i as Copy:
                [i.value]
            case let i as Destroy:
                [i.value]
            case let i as InlineAsm:
                i.operands
            case let i as BuildExistential:
                [i.value]
            case let i as OpenExistential:
                [i.container]
            case let i as OpaqueWitnessMethod:
                [i.container]
            case let i as ExistentialCopy:
                [i.container]
            case let i as ExistentialDestroy:
                [i.container]
            default:
                []
            }
        }
    }

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
            _ blockArgument: BlockArgument, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitIntegerLiteral(
            _ integerLiteral: IntegerLiteral, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitFloatLiteral(_ floatLiteral: FloatLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitCharLiteral(_ charLiteral: CharLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitBoolLiteral(_ boolLiteral: BoolLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitStringLiteral(_ stringLiteral: StringLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitNullptrLiteral(_ nullptrLiteral: NullptrLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitVoidLiteral(_ voidLiteral: VoidLiteral, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitReturn(_ returnInstruction: Return, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBranch(_ branch: Branch, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitConditionalBranch(
            _ conditionalBranch: ConditionalBranch, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitUnreachable(_ unreachableInstruction: Unreachable, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitPhi(_ phi: Phi, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitSwitchEnum(_ switchEnum: SwitchEnum, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitExtractPayload(
            _ extractPayload: ExtractPayload, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitUnaryArith(_ unaryArith: UnaryArith, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBinaryArith(_ binaryArith: BinaryArith, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitGlobalAddr(_ globalAddr: GlobalAddr, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitAllocStack(_ allocStack: AllocStack, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocStack(
            _ deallocStack: DeallocStack, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitAllocHeap(_ allocHeap: AllocHeap, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocHeap(_ deallocHeap: DeallocHeap, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitAllocCell(_ allocCell: AllocCell, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDeallocCell(_ deallocCell: DeallocCell, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitLoad(_ loadInstruction: Load, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitStore(_ storeInstruction: Store, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitSizeOf(_ sizeOfInstruction: SizeOf, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitStructElementAddr(
            _ structElementAddr: StructElementAddr, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitTupleElementAddr(
            _ tupleElementAddr: TupleElementAddr, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitClassElementAddr(
            _ classElementAddr: ClassElementAddr, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitProjectCell(_ projectCell: ProjectCell, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitAddressToPointer(
            _ addressToPointer: AddressToPointer, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitPointerToAddress(
            _ pointerToAddress: PointerToAddress, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitStructValue(_ structValue: StructValue, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitTupleValue(_ tupleValue: TupleValue, additional: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitEnumValue(_ enumValue: EnumValue, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitCall(_ call: Call, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitFunctionRef(_ functionRef: FunctionRef, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitTryCall(_ tryCall: TryCall, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitClosure(_ closure: Closure, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitUpcast(_ upcast: Upcast, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitUncheckedRefCast(
            _ uncheckedRefCast: UncheckedRefCast, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitNumericCast(_ numericCast: NumericCast, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBitCast(_ bitCast: BitCast, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitTypeMetadata(
            _ typeMetadata: TypeMetadata, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitTypeMetadataConstant(
            _ typeMetadataConstant: TypeMetadataConstant, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitIsInstance(
            _ isInstance: IsInstance, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitSuperclass(
            _ superClassInstruction: Superclass, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitTrap(_ trap: Trap, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitRetain(_ retainInstruction: Retain, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitRelease(_ releaseInstruction: Release, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitCopy(_ copyInstruction: Copy, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitDestroy(_ destroyInstruction: Destroy, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitInlineAsm(_ inlineAsm: InlineAsm, additional: Any? = nil) -> Any? { nil }

        @discardableResult
        open func visitBuildExistential(
            _ buildExistential: BuildExistential, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitOpenExistential(
            _ openExistential: OpenExistential, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitWitnessMethod(
            _ witnessMethod: WitnessMethod, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitOpaqueWitnessMethod(
            _ opaqueWitnessMethod: OpaqueWitnessMethod, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitVirtualMethod(
            _ virtualMethod: VirtualMethod, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitExistentialCopy(
            _ existentialCopy: ExistentialCopy, additional: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitExistentialDestroy(
            _ existentialDestroy: ExistentialDestroy, additional: Any? = nil
        ) -> Any? {
            nil
        }
    }
}
