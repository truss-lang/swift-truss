import LLVMSwiftBinding
import TrussCore

public final class CodeGen: TIR.Visitor {
    private static let ReferenceHeaderSize = 2
    private let context: TrussCore.Context
    private let llvmContext: LLVMSwiftBinding.Context
    private var currentModule: LLVMSwiftBinding.Module? = nil
    private var currentRegistry: TIR.Registry? = nil
    private var builder: LLVMSwiftBinding.Builder? = nil
    private var currentFunction: FunctionBinding? = nil
    private var typeMap: [Int: LLVMSwiftBinding.LLVMType] = [:]
    private var functionMap: [Int: FunctionBinding] = [:]
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
        typeMap = [:]
        functionMap = mod.functions.reduce(into: [:]) {
            $0[$1.id] = createFunction($1)
        }
        for tirFunction in mod.functions {
            guard let llvmFunction = functionMap[tirFunction.id] else { continue }
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

    private func lowerType(_ typeId: Int) -> LLVMSwiftBinding.LLVMType {
        if let ty = typeMap[typeId] {
            return ty
        }
        guard let currentRegistry else {
            fatalError("unreachable")
        }
        guard let type = currentRegistry.type(typeId) else {
            let lowered = llvmContext.int8
            typeMap[typeId] = lowered
            return lowered
        }
        switch type {
        case is TIRType.VoidType:
            let lowered = llvmContext.void
            typeMap[typeId] = lowered
            return lowered
        case let primitive as TIRType.PrimitiveType:
            let lowered: LLVMSwiftBinding.LLVMType
            switch primitive.kind {
            case .Bool:
                lowered = llvmContext.int1
            case .Char:
                lowered = llvmContext.int32
            case .Signed, .Unsigned:
                lowered = llvmContext.intType(width: UInt32(primitive.bitWidth))
            case .Float:
                switch primitive.bitWidth {
                case 32:
                    lowered = llvmContext.float
                case 64:
                    lowered = llvmContext.double
                default:
                    fatalError("unreachable")
                }
            }
            typeMap[typeId] = lowered
            return lowered
        case let functionType as TIRType.FunctionType:
            let returnType = lowerType(functionType.returnType)
            let parameterTypes = functionType.parameters.map {
                lowerType($0.type)
            }
            let lowered = llvmContext.functionType(
                returnType: returnType,
                parameterTypes: parameterTypes,
                isVariadic: functionType.isVariadic
            )
            typeMap[typeId] = lowered
            return lowered
        case let addressType as TIRType.AddressType:
            let lowered = lowerType(addressType.pointee)
            typeMap[typeId] = lowered
            return lowered
        case let structType as TIRType.StructType:
            let lowered = llvmContext.namedStructType(name: structType.name)
            typeMap[typeId] = lowered
            let elementTypes = structType.fields.map {
                lowerType($0.type)
            }
            lowered.setElementTypes(elementTypes, isPacked: false)
            return lowered
        case let refType as TIRType.ReferenceType:
            let lowered = llvmContext.namedStructType(name: refType.name)
            typeMap[typeId] = lowered
            let elementTypes = [llvmContext.pointerType(), llvmContext.int64] + refType.fields.map {
                lowerType($0.type)
            }
            lowered.setElementTypes(elementTypes, isPacked: false)
            return lowered
        default:
            let lowered = llvmContext.int8
            typeMap[typeId] = lowered
            return lowered
        }
    }

    public override func visitIntegerLiteral(_ instruction: TIR.IntegerLiteral, additional: Any? = nil) -> Any? {
        let type = lowerType(instruction.literalType.id)
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
        let type = lowerType(instruction.literalType.id)
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
        valueMap[ObjectIdentifier(result)] = llvmContext.constantNull(lowerType(instruction.pointerType.id))
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
        valueMap[ObjectIdentifier(result)] = builder.buildAlloca(lowerType(instruction.allocatedType.id))
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

    public override func visitStructElementAddr(_ instruction: TIR.StructElementAddr, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let structAddress = valueMap[ObjectIdentifier(instruction.structAddress)] else {
            context.emitError("struct element addr: missing address operand", at: instruction.sourceRange)
            return nil
        }
        guard let structType = lowerType(instruction.structAddress.type) as? LLVMSwiftBinding.StructType else {
            context.emitError("struct element addr: unsupported operand type", at: instruction.sourceRange)
            return nil
        }
        guard let result = instruction.result else {
            // TODO: emit error
            return nil
        }
        valueMap[ObjectIdentifier(result)] = builder.buildStructGEP(
            structType,
            structAddress,
            index: UInt32(instruction.fieldIndex + 2)
        )
        return nil
    }

    public override func visitRefElementAddr(_ instruction: TIR.RefElementAddr, additional: Any? = nil) -> Any? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let structAddress = valueMap[ObjectIdentifier(instruction.reference)] else {
            context.emitError("ref element addr: missing address operand", at: instruction.sourceRange)
            return nil
        }
        guard let structType = lowerType(instruction.reference.type) as? LLVMSwiftBinding.StructType else {
            context.emitError("ref element addr: unsupported operand type", at: instruction.sourceRange)
            return nil
        }
        guard let result = instruction.result else {
            // TODO: emit error
            return nil
        }
        valueMap[ObjectIdentifier(result)] = builder.buildStructGEP(
            structType,
            structAddress,
            index: UInt32(instruction.fieldIndex + CodeGen.ReferenceHeaderSize)
        )
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
        if let binding = functionMap[f.id] {
            valueMap[ObjectIdentifier(result)] = binding.function
        } else {
            let llvmFunction = createFunctionDecl(f)
            functionMap[f.id] = FunctionBinding(function: llvmFunction)
            valueMap[ObjectIdentifier(result)] = llvmFunction
        }
        return nil
    }

    public override func visitArith(_ instruction: TIR.Arith, additional: Any? = nil) -> Any? {
        guard let builder, let currentRegistry else {
            fatalError("unreachable")
        }
        guard let result = instruction.result else {
            context.emitError("arith: missing result value", at: instruction.sourceRange)
            return nil
        }
        guard instruction.operands.count == 2 || instruction.op.isUnary else {
            context.emitError("arith: wrong operand count", at: instruction.sourceRange)
            return nil
        }
        guard let lhs = valueMap[ObjectIdentifier(instruction.operands[0])],
              let operandTypeId = currentRegistry.type(instruction.operands[0].type)
        else {
            context.emitError("arith: missing operand value", at: instruction.sourceRange)
            return nil
        }
        let kind = (operandTypeId as? TIRType.PrimitiveType)?.kind
        let built: LLVMSwiftBinding.Value? = switch instruction.op {
        case .Neg, .Not, .Bitnot:
            emitUnaryArith(instruction, lhs: lhs, kind: kind)
        case .Add, .Sub, .Mul, .Div, .Rem:
            emitBinaryArith(instruction, lhs: lhs, kind: kind)
        case .Eq, .Ne, .Lt, .Le, .Gt, .Ge:
            emitCompareArith(instruction, lhs: lhs, kind: kind)
        }
        if let built {
            valueMap[ObjectIdentifier(result)] = built
        }
        return nil
    }

    private func emitUnaryArith(
        _ instruction: TIR.Arith, lhs: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else {
            fatalError("unreachable")
        }
        switch instruction.op {
        case .Neg:
            if kind == .Float {
                return builder.buildFNeg(lhs)
            }
            if kind == .Signed || kind == .Unsigned {
                return builder.buildNeg(lhs)
            }
            context.emitError("arith neg: unsupported operand type", at: instruction.sourceRange)
            return nil
        case .Not:
            if kind == .Bool {
                return builder.buildNot(lhs)
            }
            context.emitError("arith not: unsupported operand type", at: instruction.sourceRange)
            return nil
        case .Bitnot:
            if kind == .Signed || kind == .Unsigned {
                return builder.buildNot(lhs)
            }
            context.emitError("arith bitnot: unsupported operand type", at: instruction.sourceRange)
            return nil
        default:
            return nil
        }
    }

    private func emitBinaryArith(
        _ instruction: TIR.Arith, lhs: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let rhs = valueMap[ObjectIdentifier(instruction.operands[1])] else {
            context.emitError("arith: missing operand value", at: instruction.sourceRange)
            return nil
        }
        guard let kind else {
            context.emitError("arith: unsupported operand type", at: instruction.sourceRange)
            return nil
        }
        switch (instruction.op, kind) {
        case (.Add, .Signed), (.Add, .Unsigned):
            return builder.buildAdd(lhs, rhs)
        case (.Add, .Float):
            return builder.buildFAdd(lhs, rhs)
        case (.Sub, .Signed), (.Sub, .Unsigned):
            return builder.buildSub(lhs, rhs)
        case (.Sub, .Float):
            return builder.buildFSub(lhs, rhs)
        case (.Mul, .Signed), (.Mul, .Unsigned):
            return builder.buildMul(lhs, rhs)
        case (.Mul, .Float):
            return builder.buildFMul(lhs, rhs)
        case (.Div, .Signed):
            return builder.buildSDiv(lhs, rhs)
        case (.Div, .Unsigned):
            return builder.buildUDiv(lhs, rhs)
        case (.Div, .Float):
            return builder.buildFDiv(lhs, rhs)
        case (.Rem, .Signed):
            return builder.buildSRem(lhs, rhs)
        case (.Rem, .Unsigned):
            return builder.buildURem(lhs, rhs)
        case (.Rem, .Float):
            return builder.buildFRem(lhs, rhs)
        default:
            context.emitError("arith: unsupported operand type", at: instruction.sourceRange)
            return nil
        }
    }

    private func emitCompareArith(
        _ instruction: TIR.Arith, lhs: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else {
            fatalError("unreachable")
        }
        guard let rhs = valueMap[ObjectIdentifier(instruction.operands[1])] else {
            context.emitError("arith: missing operand value", at: instruction.sourceRange)
            return nil
        }
        guard let kind else {
            context.emitError("arith: unsupported operand type", at: instruction.sourceRange)
            return nil
        }
        switch kind {
        case .Float:
            guard let predicate = realPredicate(for: instruction.op) else {
                context.emitError("arith compare: unsupported operand type", at: instruction.sourceRange)
                return nil
            }
            return builder.buildFCmp(predicate, lhs, rhs)
        case .Signed:
            guard let predicate = intPredicate(for: instruction.op, unsigned: false) else {
                context.emitError("arith compare: unsupported operand type", at: instruction.sourceRange)
                return nil
            }
            return builder.buildICmp(predicate, lhs, rhs)
        case .Unsigned:
            guard let predicate = intPredicate(for: instruction.op, unsigned: true) else {
                context.emitError("arith compare: unsupported operand type", at: instruction.sourceRange)
                return nil
            }
            return builder.buildICmp(predicate, lhs, rhs)
        case .Bool, .Char:
            switch instruction.op {
            case .Eq:
                return builder.buildICmp(.EQ, lhs, rhs)
            case .Ne:
                return builder.buildICmp(.NE, lhs, rhs)
            default:
                context.emitError("arith compare: unsupported operand type", at: instruction.sourceRange)
                return nil
            }
        }
    }

    private func intPredicate(
        for op: TIR.ArithOp, unsigned: Bool
    ) -> LLVMSwiftBinding.IntPredicate? {
        switch (op, unsigned) {
        case (.Eq, _):
            .EQ
        case (.Ne, _):
            .NE
        case (.Lt, false):
            .SLT
        case (.Lt, true):
            .ULT
        case (.Le, false):
            .SLE
        case (.Le, true):
            .ULE
        case (.Gt, false):
            .SGT
        case (.Gt, true):
            .UGT
        case (.Ge, false):
            .SGE
        case (.Ge, true):
            .UGE
        default:
            nil
        }
    }

    private func realPredicate(for op: TIR.ArithOp) -> LLVMSwiftBinding.RealPredicate? {
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
            nil
        }
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
