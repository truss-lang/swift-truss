import LLVMSwiftBinding
import SwiftBetterDiagnostic
import TrussCore

public final class CodeGen: TIR.Visitor {
    private let context: TrussCore.Context
    private let llvmContext: LLVMSwiftBinding.Context
    private let targetTriple: String?
    private var module: LLVMSwiftBinding.Module?
    private var registry: TIR.Registry?
    private var dataLayout: LLVMSwiftBinding.DataLayout?
    private var builder: LLVMSwiftBinding.Builder?
    private var currentFunction: LLVMSwiftBinding.Function?
    private var currentLLVMBlock: LLVMSwiftBinding.BasicBlock?
    private var typeMap: [Id.TIRTypeId: LLVMSwiftBinding.LLVMType] = [:]
    private var storageTypeMap: [Id.TIRTypeId: LLVMSwiftBinding.LLVMType] = [:]
    private var functionMap: [Id.TIRFunctionId: LLVMSwiftBinding.Function] = [:]
    private var globalMap: [Id.TIRGlobalId: LLVMSwiftBinding.GlobalVariable] = [:]
    private var valueMap: [ObjectIdentifier: LLVMSwiftBinding.Value] = [:]
    private var blockMap: [ObjectIdentifier: LLVMSwiftBinding.BasicBlock] = [:]
    private var blockParamPhi: [ObjectIdentifier: [LLVMSwiftBinding.PHINode]] = [:]
    private var blockArgEdges: [ObjectIdentifier: [BlockArgEdge]] = [:]
    private var pendingPhiIncoming: [PendingIncoming] = []

    private struct BlockArgEdge {
        let target: TIR.BasicBlock
        let args: [TIR.Value]
        let from: LLVMSwiftBinding.BasicBlock
    }

    private struct PendingIncoming {
        let phi: LLVMSwiftBinding.PHINode
        let value: TIR.Value
        let block: TIR.BasicBlock
    }

    public init(
        context: TrussCore.Context, llvmContext: LLVMSwiftBinding.Context,
        target: String? = nil
    ) {
        self.context = context
        self.llvmContext = llvmContext
        targetTriple = target
        builder = LLVMSwiftBinding.Builder(in: llvmContext)
    }

    public func generate(_ mod: TIR.Module) -> LLVMSwiftBinding.Module {
        let llvmModule: LLVMSwiftBinding.Module = .init(name: "module", in: llvmContext)
        let triple = targetTriple.map(LLVMSwiftBinding.TargetMachine.normalizedTriple)
            ?? LLVMSwiftBinding.TargetMachine.defaultTriple
        llvmModule.target = triple
        LLVMSwiftBinding.TargetMachine.initializeAllTargets()
        if let target = try? LLVMSwiftBinding.Target.fromTriple(triple) {
            let targetMachine = LLVMSwiftBinding.TargetMachine(target: target, triple: triple)
            llvmModule.setDataLayout(targetMachine.dataLayout.string)
        }
        module = llvmModule
        registry = mod.registry
        dataLayout = LLVMSwiftBinding.DataLayout(string: llvmModule.dataLayout.string)
        typeMap = [:]
        valueMap = [:]
        globalMap = mod.globals.reduce(into: [:]) {
            $0[$1.id] = lowerGlobal($1)
        }
        functionMap = mod.functions.reduce(into: [:]) {
            $0[$1.id] = createFunctionDecl($1)
        }
        for tirFunction in mod.functions {
            emitFunctionBody(tirFunction)
        }
        do {
            try llvmModule.verify()
        } catch {
            if case let .parseFailed(message) = error as? LLVMSwiftBinding.LLVMError {
                context.emitError(message, at: TIR.unknownSourceRange)
            } else {
                context.emitError("\(error)", at: TIR.unknownSourceRange)
            }
        }
        module = nil
        registry = nil
        dataLayout = nil
        currentFunction = nil
        currentLLVMBlock = nil
        return llvmModule
    }

    private func lowerGlobal(_ global: TIR.GlobalVariable) -> LLVMSwiftBinding.GlobalVariable {
        guard let module else {
            fatalError("unreachable")
        }
        let ty = lowerToLLVMStorageType(global.type)
        let llvmGlobal = module.addGlobal(global.name, type: ty)
        if !global.isExtern {
            llvmGlobal.initializer = llvmContext.constantNull(ty)
        }
        return llvmGlobal
    }

    private func createFunctionDecl(_ function: TIR.Function) -> LLVMSwiftBinding.Function {
        guard let module else {
            fatalError("unreachable")
        }
        let returnType = lowerToLLVMStorageType(function.returnType)
        let parameterTypes = function.parameters.map { lowerToLLVMStorageType($0.ty) }
        let functionType = llvmContext.functionType(
            returnType: returnType,
            parameterTypes: parameterTypes,
            isVariadic: function.isVariadic
        )
        let f = module.addFunction(function.name, type: functionType)
        for (argument, tirParameter) in zip(f.parameters, function.parameters) {
            argument.name = tirParameter.name
        }
        return f
    }

    private func emitFunctionBody(_ function: TIR.Function) {
        guard let builder else {
            fatalError("unreachable")
        }
        let blocks = reachableBlocks(function)
        let llvmFunction = functionMap[function.id]!
        guard !blocks.isEmpty else {
            fatalError()
        }
        currentFunction = llvmFunction
        currentLLVMBlock = nil
        valueMap = [:]
        blockMap = [:]

        for (tirParameter, llvmArgument) in zip(
            function.parameters, llvmFunction.parameters
        ) {
            valueMap[ObjectIdentifier(tirParameter)] = llvmArgument
        }
        for block in blocks {
            blockMap[ObjectIdentifier(block)] = llvmFunction.appendBasicBlock(block.name)
        }
        for block in blocks {
            guard let llvmBlock = blockMap[ObjectIdentifier(block)] else {
                continue
            }
            builder.positionAtEnd(of: llvmBlock)
            currentLLVMBlock = llvmBlock
            for instruction in block.instructions {
                visit(instruction)
            }
        }

        currentFunction = nil
        currentLLVMBlock = nil
    }

    private func lowerToLLVMStorageType(_ ty: Id.TIRTypeId) -> LLVMSwiftBinding.LLVMType {
        if let existing = storageTypeMap[ty] {
            return existing
        }
        let lowered = lowerToLLVMType(ty)
        storageTypeMap[ty] = lowered
        return lowered
    }

    private func lowerToLLVMType(_ ty: Id.TIRTypeId) -> LLVMSwiftBinding.LLVMType {
        if let existing = typeMap[ty] {
            return existing
        }
        guard let registry, let type = registry.type(ty) else {
            let fallback: LLVMSwiftBinding.LLVMType = llvmContext.int8
            typeMap[ty] = fallback
            return fallback
        }
        switch type {
        case is TIRType.VoidType:
            let lowered: LLVMSwiftBinding.LLVMType = llvmContext.void
            typeMap[ty] = lowered
            return lowered
        case let primitive as TIRType.PrimitiveType:
            let lowered: LLVMSwiftBinding.LLVMType = switch primitive.kind {
            case .Bool:
                llvmContext.int1
            case .Char:
                llvmContext.int32
            case .Signed, .Unsigned:
                llvmContext.intType(width: UInt32(primitive.bitWidth))
            case .Float:
                switch primitive.bitWidth {
                case 32:
                    llvmContext.float
                default:
                    llvmContext.double
                }
            }
            typeMap[ty] = lowered
            return lowered
        case is TIRType.PointerType:
            let lowered: LLVMSwiftBinding.LLVMType = llvmContext.pointerType()
            typeMap[ty] = lowered
            return lowered
        case let functionType as TIRType.FunctionType:
            let returnType = lowerToLLVMStorageType(functionType.returnType)
            let parameterTypes = functionType.parameters.map { lowerToLLVMStorageType($0) }
            let lowered = llvmContext.functionType(
                returnType: returnType,
                parameterTypes: parameterTypes,
                isVariadic: functionType.isVariadic
            )
            typeMap[ty] = lowered
            return lowered
        case let structType as TIRType.StructType:
            let named = llvmContext.namedStructType(name: structType.name)
            typeMap[ty] = named
            let elementTypes = structType.fields.map { lowerToLLVMStorageType($0.type) }
            named.setElementTypes(elementTypes, isPacked: false)
            return named
        /*
         case let enumType as TIRType.EnumType:
             let lowered = enumLLVMType(enumType)
             typeMap[key] = lowered
             return lowered
         */
        case let tupleType as TIRType.TupleType:
            let elementTypes = tupleType.elements.map { lowerToLLVMStorageType($0.type) }
            let lowered = llvmContext.structType(elementTypes: elementTypes, isPacked: false)
            typeMap[ty] = lowered
            return lowered
        default:
            let lowered: LLVMSwiftBinding.LLVMType = llvmContext.int8
            typeMap[ty] = lowered
            return lowered
        }
    }

    private func reachableBlocks(_ function: TIR.Function) -> [TIR.BasicBlock] {
        guard let entry = function.basicBlocks.first else {
            return []
        }
        var visited: Set<ObjectIdentifier> = []
        var queue: [TIR.BasicBlock] = [entry]
        var result: [TIR.BasicBlock] = []
        while let block = queue.first {
            queue.removeFirst()
            let id = ObjectIdentifier(block)
            if visited.contains(id) {
                continue
            }
            visited.insert(id)
            result.append(block)
            for instruction in block.instructions {
                switch instruction {
                case let branch as TIR.Branch:
                    queue.append(branch.target)
                case let conditional as TIR.ConditionalBranch:
                    queue.append(conditional.trueBranch)
                    queue.append(conditional.falseBranch)
                case let switchEnum as TIR.SwitchEnum:
                    for caseInfo in switchEnum.cases {
                        queue.append(caseInfo.block)
                    }
                    if let defaultBlock = switchEnum.defaultBlock {
                        queue.append(defaultBlock)
                    }
                default:
                    break
                }
            }
        }
        return result
    }

    @discardableResult
    public override func visitAllocStack(_ instruction: TIR.AllocStack, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let built = builder.buildAlloca(
            lowerToLLVMStorageType(instruction.allocatedType),
            name: instruction.result.name
        )
        valueMap[ObjectIdentifier(instruction.result)] = built
        return nil
    }

    @discardableResult
    public override func visitDeallocStack(_ instruction: TIR.DeallocStack, additional: Any? = nil) -> Any? {
        // Do nothing
        nil
    }

    @discardableResult
    public override func visitLoad(_ instruction: TIR.Load, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let ptr = llvmValue(of: instruction.ptr)!
        let built = builder.buildLoad(
            lowerToLLVMStorageType(instruction.result.ty),
            ptr,
            name: instruction.result.name
        )
        valueMap[ObjectIdentifier(instruction.result)] = built
        return nil
    }

    @discardableResult
    public override func visitStore(_ instruction: TIR.Store, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let value = llvmValue(of: instruction.value)!
        let ptr = llvmValue(of: instruction.ptr)!
        builder.buildStore(value, to: ptr)
        return nil
    }

    @discardableResult
    public override func visitReturn(_ instruction: TIR.Return, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        if let returned = instruction.value {
            builder.buildRet(llvmValue(of: returned)!)
        } else {
            builder.buildRetVoid()
        }
        return nil
    }

    @discardableResult
    public override func visitBinaryArith(_ instruction: TIR.BinaryArith, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let lhs = llvmValue(of: instruction.lhs)!
        let rhs = llvmValue(of: instruction.rhs)!
        let kind = (registry?.type(instruction.lhs.ty) as? TIRType.PrimitiveType)?.kind
        let built: LLVMSwiftBinding.Value = switch instruction.op {
        case .Add:
            kind == .Float ? builder.buildFAdd(lhs, rhs) : builder.buildAdd(lhs, rhs)
        case .Sub:
            kind == .Float ? builder.buildFSub(lhs, rhs) : builder.buildSub(lhs, rhs)
        case .Mul:
            kind == .Float ? builder.buildFMul(lhs, rhs) : builder.buildMul(lhs, rhs)
        case .SDiv:
            kind == .Float ? builder.buildFDiv(lhs, rhs) : builder.buildSDiv(lhs, rhs)
        case .UDiv:
            kind == .Float ? builder.buildFDiv(lhs, rhs) : builder.buildUDiv(lhs, rhs)
        case .SRem:
            kind == .Float ? builder.buildFRem(lhs, rhs) : builder.buildSRem(lhs, rhs)
        case .URem:
            kind == .Float ? builder.buildFRem(lhs, rhs) : builder.buildURem(lhs, rhs)
        case .FDiv:
            builder.buildFDiv(lhs, rhs)
        case .FRem:
            builder.buildFRem(lhs, rhs)
        case .And:
            builder.buildAnd(lhs, rhs)
        case .Or:
            builder.buildOr(lhs, rhs)
        case .Xor:
            builder.buildXor(lhs, rhs)
        case .Shl:
            builder.buildShl(lhs, rhs)
        case .Shr:
            kind == .Unsigned ? builder.buildLShr(lhs, rhs) : builder.buildAShr(lhs, rhs)
        case .Eq:
            compare(instruction, lhs: lhs, rhs: rhs, kind: kind, predicate: .EQ)
        case .Ne:
            compare(instruction, lhs: lhs, rhs: rhs, kind: kind, predicate: .NE)
        case .Lt:
            compare(instruction, lhs: lhs, rhs: rhs, kind: kind, predicate: nil)
        case .Le:
            compare(instruction, lhs: lhs, rhs: rhs, kind: kind, predicate: nil)
        case .Gt:
            compare(instruction, lhs: lhs, rhs: rhs, kind: kind, predicate: nil)
        case .Ge:
            compare(instruction, lhs: lhs, rhs: rhs, kind: kind, predicate: nil)
        case .Neg, .Not, .Bitnot:
            fatalError("unreachable")
        }
        built.name = instruction.result.name
        valueMap[ObjectIdentifier(instruction.result)] = built
        return nil
    }

    @discardableResult
    public override func visitUnaryArith(
        _ instruction: TIR.UnaryArith, additional: Any? = nil
    ) -> Any? {
        guard let builder, let registry else {
            fatalError("unreachable")
        }
        let operand = llvmValue(of: instruction.operand)!
        let kind = (registry.type(instruction.operand.ty) as! TIRType.PrimitiveType).kind
        let built: LLVMSwiftBinding.Value = switch instruction.op {
        case .Neg:
            kind == .Float ? builder.buildFNeg(operand) : builder.buildNeg(operand)
        case .Not:
            builder.buildNot(operand)
        case .Bitnot:
            builder.buildNot(operand)
        default:
            fatalError("unreachable")
        }
        built.name = instruction.result.name
        valueMap[ObjectIdentifier(instruction.result)] = built
        return nil
    }

    @discardableResult
    public override func visitCall(_ instruction: TIR.Call, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        let callee = llvmValue(of: instruction.callee)!
        let functionType = lowerToLLVMStorageType(instruction.callee.ty) as! LLVMSwiftBinding.FunctionType
        let arguments = instruction.arguments.compactMap { llvmValue(of: $0) }
        let built = builder.buildCall(callee, type: functionType, arguments)
        if let result = instruction.result {
            built.name = result.name
            valueMap[ObjectIdentifier(result)] = built
        }
        return nil
    }

    private func compare(
        _ instruction: TIR.BinaryArith, lhs: LLVMSwiftBinding.Value,
        rhs: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?,
        predicate: LLVMSwiftBinding.IntPredicate?
    ) -> LLVMSwiftBinding.Value {
        guard let builder else {
            fatalError("unreachable")
        }
        switch kind {
        case .Float:
            return builder.buildFCmp(realPredicate(for: instruction.op), lhs, rhs)
        case .Signed, .Unsigned:
            let isUnsigned = kind == .Unsigned
            return builder.buildICmp(intPredicate(for: instruction.op, unsigned: isUnsigned), lhs, rhs)
        default:
            if let predicate {
                return builder.buildICmp(predicate, lhs, rhs)
            }
            return builder.buildICmp(intPredicate(for: instruction.op, unsigned: false), lhs, rhs)
        }
    }

    private func intPredicate(
        for op: TIR.ArithOp, unsigned: Bool
    ) -> LLVMSwiftBinding.IntPredicate {
        switch op {
        case .Eq:
            .EQ
        case .Ne:
            .NE
        case .Lt:
            unsigned ? .ULT : .SLT
        case .Le:
            unsigned ? .ULE : .SLE
        case .Gt:
            unsigned ? .UGT : .SGT
        case .Ge:
            unsigned ? .UGE : .SGE
        default:
            .EQ
        }
    }

    private func realPredicate(for op: TIR.ArithOp) -> LLVMSwiftBinding.RealPredicate {
        switch op {
        case .Eq:
            .OEQ
        case .Ne:
            .ONE
        case .Lt:
            .OLT
        case .Le:
            .OLE
        case .Gt:
            .OGT
        case .Ge:
            .OGE
        default:
            .OEQ
        }
    }

    private func llvmValue(of value: TIR.Value) -> LLVMSwiftBinding.Value? {
        let key = ObjectIdentifier(value)
        if let existing = valueMap[key] {
            return existing
        }
        switch value {
        case let literal as TIR.IntegerLiteral:
            let type = lowerToLLVMStorageType(literal.ty) as! LLVMSwiftBinding.IntegerType
            return llvmContext.constantInt(literal.value, type: type)
        /*
         case let literal as TIR.FloatLiteral:
             return materialize(literal)
         case let literal as TIR.CharLiteral:
             return materialize(literal)
         case let literal as TIR.BoolLiteral:
             return materialize(literal)
         case let literal as TIR.NullptrLiteral:
             return materialize(literal)
         case let literal as TIR.StringLiteral:
             unsupported("string literal", at: literal.sourceRange)
             return nil
         case let globalAddress as TIR.GlobalAddr:
             return globalValue(for: globalAddress.globalId, at: globalAddress.sourceRange)
             */
        case let functionReference as TIR.FunctionRef:
            return functionValue(for: functionReference.functionId)
        case is TIR.InstructionResult:
            fatalError("unreachable")
        default:
            fatalError("unsupported value of kind \(type(of: value))")
        }
    }

    private func functionValue(for functionId: Id.TIRFunctionId) -> LLVMSwiftBinding.Function? {
        if let existing = functionMap[functionId] {
            return existing
        }

        guard let registry else {
            fatalError("unreachable")
        }
        guard let function = registry.functions[functionId] else {
            fatalError()
        }
        let declared = createFunctionDecl(function)
        functionMap[functionId] = declared
        return declared
    }
}
