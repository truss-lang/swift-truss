import SwiftAbstract

public final class TIRBuilder {
    public private(set) var function: TIR.Function
    public private(set) var currentBlock: TIR.BasicBlock
    private var counter = 0

    public init(function: TIR.Function) {
        self.function = function
        currentBlock = function.entryBlock
    }

    @discardableResult
    public func createBlock() -> TIR.BasicBlock {
        let block = TIR.BasicBlock(name: "bb\(counter)")
        counter += 1
        function.blocks.append(block)
        return block
    }

    public func switchToBlock(_ block: TIR.BasicBlock) {
        currentBlock = block
    }

    @discardableResult
    public func emit(_ instruction: TIR.Instruction) -> TIR.Value? {
        instruction.parentBlock = currentBlock
        currentBlock.instructions.append(instruction)
        return instruction.result
    }

    @discardableResult
    public func emitWithResult(
        _ instruction: TIR.Instruction, type: Int,
        ownership: TIRType.Ownership? = nil
    ) -> TIR.Value {
        let value = createValue(type: type, ownership: ownership ?? .Trivial)
        instruction.result = value
        value.definingInstruction = instruction
        emit(instruction)
        return value
    }

    public func createValue(type: Int, ownership: TIRType.Ownership) -> TIR.Value {
        let value = TIR.Value(name: "%\(counter)", type: type, ownership: ownership)
        counter += 1
        return value
    }

    public func createArgument(type: Int, ownership: TIRType.Ownership) -> TIR.Argument {
        let argument = TIR.Argument(name: "%\(counter)", type: type, ownership: ownership)
        counter += 1
        return argument
    }
}
