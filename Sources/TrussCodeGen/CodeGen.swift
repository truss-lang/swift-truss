import LLVMSwiftBinding
import TrussCore

public final class CodeGen: TIR.Visitor {
    private let context: TrussCore.Context
    private let llvmContext: LLVMSwiftBinding.Context
    private var currentModule: LLVMSwiftBinding.Module? = nil
    private var currentRegistry: TIR.Registry? = nil
    private var builder: LLVMSwiftBinding.Builder? = nil
    private var currentFunction: FunctionBinding? = nil
    private var functionMap: [ObjectIdentifier: FunctionBinding] = [:]
    private var valueMap: [ObjectIdentifier: LLVMSwiftBinding.Value] = [:]

    private struct FunctionBinding {
        public let function: LLVMSwiftBinding.Function
        public let basicBlockMap: [ObjectIdentifier: LLVMSwiftBinding.BasicBlock]?
        public init(
            function: LLVMSwiftBinding.Function,
            basicBlockMap: [ObjectIdentifier: LLVMSwiftBinding.BasicBlock]? = nil
        ) {
            self.function = function
            self.basicBlockMap = basicBlockMap
        }
    }

    public init(context: TrussCore.Context, llvmContext: LLVMSwiftBinding.Context) {
        self.context = context
        self.llvmContext = llvmContext
    }

    public func generate(_ mod: TIR.Module) -> LLVMSwiftBinding.Module {
        let llvmModule: LLVMSwiftBinding.Module = .init(name: "module", in: llvmContext)
        currentModule = llvmModule
        currentRegistry = mod.registry
        functionMap = mod.functions.reduce(into: [:]) {
            $0[ObjectIdentifier($1)] = createFunction($1)
        }
        for (tirFunction, llvmFunction) in zip(mod.functions, functionMap.values) {
            let builder: LLVMSwiftBinding.Builder = .init(in: llvmContext)
            currentFunction = llvmFunction
            self.builder = builder
            valueMap = [:]
            for (tirArgument, llvmArgument) in zip(tirFunction.arguments, llvmFunction.function.parameters) {
                valueMap[ObjectIdentifier(tirArgument)] = llvmArgument
            }
            for basicBlock in tirFunction.blocks {
                guard let llvmBasicBlock = llvmFunction.basicBlockMap![ObjectIdentifier(basicBlock)] else {
                    continue
                }
                builder.positionAtEnd(of: llvmBasicBlock)
                for instruction in basicBlock.instructions {
                    visit(instruction)
                }
            }
        }
        return llvmModule
    }

    private func createFunction(_ function: TIR.Function) -> FunctionBinding {
        let f = createFunctionDecl(function)
        let basicBlockMap = function.blocks.reduce(into: [:]) {
            $0[ObjectIdentifier($1)] = f.appendBasicBlock($1.name)
        }
        return FunctionBinding(function: f, basicBlockMap: basicBlockMap)
    }

    private func createFunctionDecl(_ function: TIR.Function) -> LLVMSwiftBinding.Function {
        guard let currentModule else {
            fatalError("unreachable")
        }
        let returnType = lowerType(function.returnType)
        let parameterTypes = function.arguments.map {
            lowerType($0.type)
        }
        let functionType = llvmContext.functionType(
            returnType: returnType,
            parameterTypes: parameterTypes,
            isVariadic: function.isVariadic
        )
        return currentModule.addFunction(function.name, type: functionType)
    }

    private func lowerType(_ type: TIRType.TIRType) -> LLVMSwiftBinding.LLVMType {
        switch type {
        case is TIRType.VoidType:
            return llvmContext.void
        case let primitive as TIRType.PrimitiveType:
            switch primitive.kind {
            case .Bool:
                return llvmContext.int1
            case .Char:
                return llvmContext.int32
            case .Signed, .Unsigned:
                return llvmContext.intType(width: UInt32(primitive.bitWidth))
            case .Float:
                switch primitive.bitWidth {
                case 32:
                    return llvmContext.float
                case 64:
                    return llvmContext.double
                default:
                    fatalError("unreachable")
                }
            }
        case let functionType as TIRType.FunctionType:
            let returnType = lowerType(functionType.returnType)
            let parameterTypes = functionType.parameters.map {
                lowerType($0.type)
            }
            return llvmContext.functionType(
                returnType: returnType,
                parameterTypes: parameterTypes,
                isVariadic: functionType.isVariadic
            )
        case let structType as TIRType.StructType:
            return llvmContext.int8
        default:
            return llvmContext.int8
        }
    }

    public override func visitIntegerLiteral(_ instruction: TIR.IntegerLiteral, additional: Any? = nil) -> Any? {
        let type = lowerType(instruction.literalType)
        guard let result = instruction.result else {
            context.emitError("integer literal: missing result value", at: instruction.sourceRange)
            return nil
        }
        switch type {
        case let floatType as LLVMSwiftBinding.FloatType:
            valueMap[ObjectIdentifier(result)] = llvmContext.constantFP(
                Double(instruction.value),
                type: floatType
            )
        case let integerType as LLVMSwiftBinding.IntegerType:
            valueMap[ObjectIdentifier(result)] = llvmContext.constantInt(
                signed: instruction.value,
                type: integerType
            )
        default:
            context.emitError("integer literal: unsupported lowered type", at: instruction.sourceRange)
        }
        return nil
    }

    public override func visitFloatLiteral(_ instruction: TIR.FloatLiteral, additional: Any? = nil) -> Any? {
        let type = lowerType(instruction.literalType)
        guard let result = instruction.result else {
            context.emitError("float literal: missing result value", at: instruction.sourceRange)
            return nil
        }
        guard let floatType = type as? LLVMSwiftBinding.FloatType else {
            context.emitError("float literal: unsupported lowered type", at: instruction.sourceRange)
            return nil
        }
        valueMap[ObjectIdentifier(result)] = llvmContext.constantFP(
            instruction.value,
            type: floatType
        )
        return nil
    }

    public override func visitCharLiteral(_ instruction: TIR.CharLiteral, additional: Any? = nil) -> Any? {
        guard let result = instruction.result else {
            context.emitError("char literal: missing result value", at: instruction.sourceRange)
            return nil
        }
        let packed = String(instruction.value).utf8.reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        valueMap[ObjectIdentifier(result)] = llvmContext.constantInt(
            signed: Int64(packed),
            type: llvmContext.int32
        )
        return nil
    }

    public override func visitBoolLiteral(_ instruction: TIR.BoolLiteral, additional: Any? = nil) -> Any? {
        guard let result = instruction.result else {
            context.emitError("bool literal: missing result value", at: instruction.sourceRange)
            return nil
        }
        valueMap[ObjectIdentifier(result)] = llvmContext.constantInt(
            instruction.value ? 1 : 0,
            type: llvmContext.int1
        )
        return nil
    }

    public override func visitNullptrLiteral(_ instruction: TIR.NullptrLiteral, additional: Any? = nil) -> Any? {
        guard let result = instruction.result else {
            context.emitError("null pointer literal: missing result value", at: instruction.sourceRange)
            return nil
        }
        valueMap[ObjectIdentifier(result)] = llvmContext.constantNull(lowerType(instruction.pointerType))
        return nil
    }

    public override func visitAllocStack(_ instruction: TIR.AllocStack, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let result = instruction.result else {
            context.emitError("alloc stack: missing result value", at: instruction.sourceRange)
            return nil
        }
        guard !(instruction.allocatedType is TIRType.VoidType) else {
            return nil
        }
        valueMap[ObjectIdentifier(result)] = builder.buildAlloca(lowerType(instruction.allocatedType))
        return nil
    }

    public override func visitLoad(_ instruction: TIR.Load, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let result = instruction.result else {
            context.emitError("load: missing result value", at: instruction.sourceRange)
            return nil
        }
        guard let v = valueMap[ObjectIdentifier(instruction.address)] else {
            context.emitError("load: missing address value", at: instruction.sourceRange)
            return nil
        }
        valueMap[ObjectIdentifier(result)] = builder.buildLoad(lowerType(instruction.address.type), v)
        return nil
    }

    public override func visitStore(_ instruction: TIR.Store, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let value = valueMap[ObjectIdentifier(instruction.value)] else {
            context.emitError("store: missing value operand", at: instruction.sourceRange)
            return nil
        }
        guard let address = valueMap[ObjectIdentifier(instruction.address)] else {
            context.emitError("store: missing address operand", at: instruction.sourceRange)
            return nil
        }
        builder.buildStore(value, to: address)
        return nil
    }

    public override func visitReturn(_ instruction: TIR.Return, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        if let value = instruction.value {
            guard let v = valueMap[ObjectIdentifier(value)] else {
                context.emitError("return: missing value operand", at: instruction.sourceRange)
                return nil
            }
            builder.buildRet(v)
        } else {
            builder.buildRetVoid()
        }
        return nil
    }

    public override func visitBranch(_ instruction: TIR.Branch, additional: Any? = nil) -> Any? {
        guard let builder, let currentFunction else {
            fatalError("unreachable")
        }
        guard let target = currentFunction.basicBlockMap![ObjectIdentifier(instruction.target)] else {
            context.emitError("branch: missing target basic block", at: instruction.sourceRange)
            return nil
        }
        builder.buildBr(target)
        return nil
    }

    public override func visitCondBranch(_ instruction: TIR.CondBranch, additional: Any? = nil) -> Any? {
        guard let builder, let currentFunction else {
            fatalError("unreachable")
        }
        guard let condValue = valueMap[ObjectIdentifier(instruction.condition)] else {
            context.emitError("cond branch: missing condition value", at: instruction.sourceRange)
            return nil
        }
        guard let trueBranch = currentFunction.basicBlockMap![ObjectIdentifier(instruction.trueBlock)] else {
            context.emitError("cond branch: missing true target basic block", at: instruction.sourceRange)
            return nil
        }
        guard let falseBranch = currentFunction.basicBlockMap![ObjectIdentifier(instruction.falseBlock)] else {
            context.emitError("cond branch: missing false target basic block", at: instruction.sourceRange)
            return nil
        }
        builder.buildCondBr(condValue, then: trueBranch, else: falseBranch)
        return nil
    }

    public override func visitUnreachable(_ instruction: TIR.Unreachable, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        builder.buildUnreachable()
        return nil
    }

    public override func visitPhi(_ instruction: TIR.Phi, additional: Any? = nil) -> Any? {
        guard let builder, let currentFunction else {
            fatalError("unreachable")
        }
        guard let result = instruction.result else {
            context.emitError("phi: missing result value", at: instruction.sourceRange)
            return nil
        }
        let phi = builder.buildPhi(lowerType(result.type))
        for incoming in instruction.incomings {
            guard let v = valueMap[ObjectIdentifier(incoming.value)] else {
                context.emitError("phi: missing incoming value", at: instruction.sourceRange)
                continue
            }
            guard let from = currentFunction.basicBlockMap![ObjectIdentifier(incoming.block)] else {
                context.emitError("phi: missing incoming basic block", at: instruction.sourceRange)
                continue
            }
            phi.addIncoming(v, from: from)
        }
        valueMap[ObjectIdentifier(result)] = phi
        return nil
    }

    public override func visitFunctionRef(_ instruction: TIR.FunctionRef, additional: Any? = nil) -> Any? {
        guard let currentRegistry else {
            fatalError("unreachable")
        }
        guard let result = instruction.result else {
            context.emitError("function ref: missing result value", at: instruction.sourceRange)
            return nil
        }
        guard let f = currentRegistry.functions[instruction.functionId] else {
            context.emitError(
                "function ref: function \(instruction.functionId) not found in registry",
                at: instruction.sourceRange
            )
            return nil
        }
        if let binding = functionMap[ObjectIdentifier(f)] {
            valueMap[ObjectIdentifier(result)] = binding.function
        } else {
            let llvmFunction = createFunctionDecl(f)
            functionMap[ObjectIdentifier(f)] = FunctionBinding(function: llvmFunction)
            valueMap[ObjectIdentifier(result)] = llvmFunction
        }
        return nil
    }

    public override func visitApply(_ instruction: TIR.Apply, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let result = instruction.result else {
            context.emitError("apply: missing result value", at: instruction.sourceRange)
            return nil
        }
        guard let callee = valueMap[ObjectIdentifier(instruction.callee)] else {
            context.emitError("apply: missing callee value", at: instruction.sourceRange)
            return nil
        }
        guard let functionType = lowerType(instruction.callee.type) as? LLVMSwiftBinding.FunctionType else {
            context.emitError("apply: callee is not a function type", at: instruction.sourceRange)
            return nil
        }
        let args = instruction.arguments.compactMap {
            let v = valueMap[ObjectIdentifier($0)]
            if v == nil {
                context.emitError("apply: missing argument value", at: instruction.sourceRange)
            }
            return v
        }
        valueMap[ObjectIdentifier(result)] = builder.buildCall(callee, type: functionType, args)
        return nil
    }
}
