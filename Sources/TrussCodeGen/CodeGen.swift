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
    private var typeMap: [Int: LLVMSwiftBinding.LLVMType] = [:]
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
            context.emitError("verification failed: \(error)", at: TIR.unknownSourceRange)
        }
        module = nil
        registry = nil
        dataLayout = nil
        currentFunction = nil
        currentLLVMBlock = nil
        return llvmModule
    }

    private func lowerGlobal(_ global: TIR.GlobalVariable) -> LLVMSwiftBinding.GlobalVariable {
        guard let module else { fatalError("unreachable") }
        let valueType = lowerType(global.type)
        let globalType: LLVMSwiftBinding.LLVMType =
            valueType is LLVMSwiftBinding.FunctionType ? llvmContext.pointerType() : valueType
        let llvmGlobal = module.addGlobal(global.name, type: globalType)
        if !global.isExtern {
            llvmGlobal.initializer = llvmContext.constantNull(globalType)
        }
        return llvmGlobal
    }

    private func createFunctionDecl(_ tirFunction: TIR.Function) -> LLVMSwiftBinding.Function {
        guard let module else { fatalError("unreachable") }
        let returnType = lowerType(tirFunction.returnType)
        let parameterTypes = tirFunction.parameters.map { lowerType($0.ty) }
        let functionType = llvmContext.functionType(
            returnType: returnType,
            parameterTypes: parameterTypes,
            isVariadic: tirFunction.isVariadic
        )
        return module.addFunction(tirFunction.name, type: functionType)
    }

    private func emitFunctionBody(_ tirFunction: TIR.Function) {
        let blocks = reachableBlocks(tirFunction)
        guard !blocks.isEmpty,
              let llvmFunction = functionMap[tirFunction.id]
        else { return }
        currentFunction = llvmFunction
        currentLLVMBlock = nil
        valueMap = [:]
        blockMap = [:]
        blockParamPhi = [:]
        blockArgEdges = [:]
        pendingPhiIncoming = []
        for (tirParameter, llvmArgument) in zip(
            tirFunction.parameters, llvmFunction.parameters
        ) {
            valueMap[ObjectIdentifier(tirParameter)] = llvmArgument
        }
        for block in blocks {
            blockMap[ObjectIdentifier(block)] = llvmFunction.appendBasicBlock(block.name)
        }
        for block in blocks {
            guard let llvmBlock = blockMap[ObjectIdentifier(block)] else { continue }
            builder?.positionAtEnd(of: llvmBlock)
            var phis: [LLVMSwiftBinding.PHINode] = []
            for parameter in block.parameters {
                let phi = builder?.buildPhi(lowerType(parameter.ty), name: parameter.name) ?? nil
                if let phi {
                    valueMap[ObjectIdentifier(parameter)] = phi
                    phis.append(phi)
                }
            }
            if !phis.isEmpty {
                blockParamPhi[ObjectIdentifier(block)] = phis
            }
            for instruction in block.instructions {
                if let phiInstruction = instruction as? TIR.Phi {
                    let phi = builder?.buildPhi(lowerType(phiInstruction.result.ty)) ?? nil
                    if let phi {
                        valueMap[ObjectIdentifier(phiInstruction.result)] = phi
                        for incoming in phiInstruction.incomings {
                            pendingPhiIncoming.append(
                                PendingIncoming(
                                    phi: phi, value: incoming.value, block: incoming.block
                                )
                            )
                        }
                    }
                }
            }
        }
        for block in blocks {
            guard let llvmBlock = blockMap[ObjectIdentifier(block)] else { continue }
            builder?.positionAtEnd(of: llvmBlock)
            currentLLVMBlock = llvmBlock
            for instruction in block.instructions {
                if instruction is TIR.Phi {
                    continue
                }
                _ = visit(instruction)
            }
        }
        for (blockID, phis) in blockParamPhi {
            for edge in blockArgEdges[blockID] ?? [] {
                for (index, phi) in phis.enumerated() {
                    guard index < edge.args.count,
                          let incoming = value(edge.args[index])
                    else { continue }
                    phi.addIncoming(incoming, from: edge.from)
                }
            }
        }
        for pending in pendingPhiIncoming {
            guard let from = blockMap[ObjectIdentifier(pending.block)],
                  let incoming = value(pending.value)
            else { continue }
            pending.phi.addIncoming(incoming, from: from)
        }
        currentFunction = nil
        currentLLVMBlock = nil
    }

    private func reachableBlocks(_ function: TIR.Function) -> [TIR.BasicBlock] {
        guard let entry = function.basicBlocks.first else { return [] }
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

    private func lowerType(_ typeId: Id.TIRTypeId) -> LLVMSwiftBinding.LLVMType {
        let key = Int(typeId.id)
        if let existing = typeMap[key] {
            return existing
        }
        guard let registry, let type = registry.type(typeId) else {
            let fallback: LLVMSwiftBinding.LLVMType = llvmContext.int8
            typeMap[key] = fallback
            return fallback
        }
        switch type {
        case is TIRType.VoidType:
            let lowered: LLVMSwiftBinding.LLVMType = llvmContext.void
            typeMap[key] = lowered
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
            typeMap[key] = lowered
            return lowered
        case is TIRType.PointerType:
            let lowered: LLVMSwiftBinding.LLVMType = llvmContext.pointerType()
            typeMap[key] = lowered
            return lowered
        case let functionType as TIRType.FunctionType:
            let returnType = lowerType(functionType.returnType)
            let parameterTypes = functionType.parameters.map { lowerType($0) }
            let lowered = llvmContext.functionType(
                returnType: returnType,
                parameterTypes: parameterTypes,
                isVariadic: functionType.isVariadic
            )
            typeMap[key] = lowered
            return lowered
        case let structType as TIRType.StructType:
            let named = llvmContext.namedStructType(name: structType.name)
            typeMap[key] = named
            let elementTypes = structType.fields.map { lowerType($0.type) }
            named.setElementTypes(elementTypes, isPacked: false)
            return named
        case let enumType as TIRType.EnumType:
            let lowered = enumLLVMType(enumType)
            typeMap[key] = lowered
            return lowered
        case let tupleType as TIRType.TupleType:
            let elementTypes = tupleType.elements.map { lowerType($0.type) }
            let lowered = llvmContext.structType(elementTypes: elementTypes, isPacked: false)
            typeMap[key] = lowered
            return lowered
        default:
            let lowered: LLVMSwiftBinding.LLVMType = llvmContext.int8
            typeMap[key] = lowered
            return lowered
        }
    }

    private func discriminantType(_ enumType: TIRType.EnumType) -> LLVMSwiftBinding.IntegerType {
        let count = enumType.cases.count
        let width: UInt32 = if count <= 256 {
            8
        } else if count <= 65536 {
            16
        } else if count <= 4_294_967_296 {
            32
        } else {
            64
        }
        return llvmContext.intType(width: width)
    }

    private func enumHasPayload(_ enumType: TIRType.EnumType) -> Bool {
        enumType.cases.contains { caseInfo in
            !caseInfo.associatedTypes.isEmpty
        }
    }

    private func payloadByteSize(_ enumType: TIRType.EnumType) -> Int {
        enumType.cases
            .flatMap(\.associatedTypes)
            .map { associatedType in
                let bits = dataLayout?.sizeOfTypeInBits(lowerType(associatedType)) ?? 0
                return (Int(bits) + 7) / 8
            }
            .max() ?? 0
    }

    private func enumLLVMType(_ enumType: TIRType.EnumType) -> LLVMSwiftBinding.LLVMType {
        let discriminant = discriminantType(enumType)
        if enumHasPayload(enumType) {
            let buffer = llvmContext.arrayType(
                elementType: llvmContext.int8, count: UInt32(max(payloadByteSize(enumType), 1))
            )
            return llvmContext.namedStructType(
                name: enumType.name,
                elementTypes: [discriminant, buffer],
                isPacked: false
            )
        }
        return discriminant
    }

    private func pointeeTypeID(_ typeId: Id.TIRTypeId) -> Id.TIRTypeId {
        if let pointer = registry?.type(typeId) as? TIRType.PointerType {
            return pointer.pointee
        }
        return typeId
    }

    private func enumType(of value: TIR.Value) -> TIRType.EnumType? {
        guard let registry else { return nil }
        if let enumType = registry.type(pointeeTypeID(value.ty)) as? TIRType.EnumType {
            return enumType
        }
        return nil
    }

    private func loadDiscriminant(
        from slot: LLVMSwiftBinding.Value, enumType: TIRType.EnumType
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else { return nil }
        let discriminant = discriminantType(enumType)
        if enumHasPayload(enumType) {
            let structType = lowerType(enumType.id)
            let discriminantPointer = builder.buildStructGEP(
                structType, slot, index: 0
            )
            return builder.buildLoad(discriminant, discriminantPointer)
        }
        return builder.buildLoad(discriminant, slot)
    }

    private func discriminantValue(
        from enumValue: TIR.Value, enumType: TIRType.EnumType
    ) -> LLVMSwiftBinding.Value? {
        guard let builder, let resolved = value(enumValue) else { return nil }
        if lowerType(enumValue.ty) is LLVMSwiftBinding.PointerType {
            return loadDiscriminant(from: resolved, enumType: enumType)
        }
        if enumHasPayload(enumType) {
            return builder.buildExtractValue(resolved, index: 0)
        }
        return resolved
    }

    private func slotPointer(
        from enumValue: TIR.Value, structType: LLVMSwiftBinding.LLVMType
    ) -> LLVMSwiftBinding.Value? {
        guard let builder, let resolved = value(enumValue) else { return nil }
        if lowerType(enumValue.ty) is LLVMSwiftBinding.PointerType {
            return resolved
        }
        let slot = builder.buildAlloca(structType, name: "enum.slot")
        builder.buildStore(resolved, to: slot)
        return slot
    }

    private func value(_ value: TIR.Value) -> LLVMSwiftBinding.Value? {
        let key = ObjectIdentifier(value)
        if let existing = valueMap[key] {
            return existing
        }
        switch value {
        case let literal as TIR.IntegerLiteral:
            return materialize(literal)
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
        case let functionReference as TIR.FunctionRef:
            return functionValue(for: functionReference.functionId)
        default:
            unsupported("value of kind \(type(of: value))", at: value.sourceRange)
            return nil
        }
    }

    private func globalValue(
        for globalId: Id.TIRGlobalId, at range: SourceRange
    ) -> LLVMSwiftBinding.Value? {
        if let existing = globalMap[globalId] {
            return existing
        }
        guard let module, let tirGlobal = registry?.globals[globalId] else {
            unsupported("global \(globalId)", at: range)
            return nil
        }
        let valueType = lowerType(tirGlobal.type)
        let globalType: LLVMSwiftBinding.LLVMType =
            valueType is LLVMSwiftBinding.FunctionType ? llvmContext.pointerType() : valueType
        let llvmGlobal = module.addGlobal(tirGlobal.name, type: globalType)
        globalMap[globalId] = llvmGlobal
        return llvmGlobal
    }

    private func functionValue(for functionId: Id.TIRFunctionId) -> LLVMSwiftBinding.Function? {
        if let existing = functionMap[functionId] {
            return existing
        }
        guard let registry, let tirFunction = registry.functions[functionId] else {
            return nil
        }
        let declared = createFunctionDecl(tirFunction)
        functionMap[functionId] = declared
        return declared
    }

    private func materialize(_ literal: TIR.IntegerLiteral) -> LLVMSwiftBinding.Value? {
        let type = lowerType(literal.ty)
        switch type {
        case let floatType as LLVMSwiftBinding.FloatType:
            return llvmContext.constantFP(Double(literal.value), type: floatType)
        case let integerType as LLVMSwiftBinding.IntegerType:
            return llvmContext.constantInt(literal.value, type: integerType)
        default:
            unsupported("integer literal", at: literal.sourceRange)
            return nil
        }
    }

    private func materialize(_ literal: TIR.FloatLiteral) -> LLVMSwiftBinding.Value? {
        guard let floatType = lowerType(literal.ty) as? LLVMSwiftBinding.FloatType else {
            unsupported("float literal", at: literal.sourceRange)
            return nil
        }
        return llvmContext.constantFP(literal.value, type: floatType)
    }

    private func materialize(_ literal: TIR.CharLiteral) -> LLVMSwiftBinding.Value? {
        let packed = String(literal.value).utf8.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        return llvmContext.constantInt(UInt64(packed), type: llvmContext.int32)
    }

    private func materialize(_ literal: TIR.BoolLiteral) -> LLVMSwiftBinding.Value? {
        llvmContext.constantInt(literal.value ? 1 : 0, type: llvmContext.int1)
    }

    private func materialize(_ literal: TIR.NullptrLiteral) -> LLVMSwiftBinding.Value? {
        llvmContext.constantNull(lowerType(literal.ty))
    }

    private func recordBlockArgEdge(
        target: TIR.BasicBlock, arguments: [TIR.Value]
    ) {
        guard let currentLLVMBlock else { return }
        blockArgEdges[ObjectIdentifier(target), default: []].append(
            BlockArgEdge(target: target, args: arguments, from: currentLLVMBlock)
        )
    }

    private func unsupported(_ what: String, at range: SourceRange) {
        context.emitError("unsupported: cannot lower \(what)", at: range)
    }

    public override func visitReturn(_ instruction: TIR.Return, additional: Any? = nil) -> Any? {
        guard let builder else { return nil }
        if let returned = instruction.value {
            guard let value = value(returned) else { return nil }
            builder.buildRet(value)
        } else {
            builder.buildRetVoid()
        }
        return nil
    }

    public override func visitBranch(_ instruction: TIR.Branch, additional: Any? = nil) -> Any? {
        guard let builder, let target = blockMap[ObjectIdentifier(instruction.target)] else {
            return nil
        }
        builder.buildBr(target)
        recordBlockArgEdge(target: instruction.target, arguments: instruction.arguments)
        return nil
    }

    public override func visitConditionalBranch(
        _ instruction: TIR.ConditionalBranch, additional: Any? = nil
    ) -> Any? {
        guard let builder,
              let condition = value(instruction.condition),
              let trueBlock = blockMap[ObjectIdentifier(instruction.trueBranch)],
              let falseBlock = blockMap[ObjectIdentifier(instruction.falseBranch)]
        else { return nil }
        builder.buildCondBr(condition, then: trueBlock, else: falseBlock)
        recordBlockArgEdge(target: instruction.trueBranch, arguments: instruction.trueArguments)
        recordBlockArgEdge(target: instruction.falseBranch, arguments: instruction.falseArguments)
        return nil
    }

    public override func visitUnreachable(
        _ instruction: TIR.Unreachable, additional: Any? = nil
    ) -> Any? {
        builder?.buildUnreachable()
        return nil
    }

    public override func visitPhi(_ instruction: TIR.Phi, additional: Any? = nil) -> Any? {
        nil
    }

    public override func visitSwitchEnum(
        _ instruction: TIR.SwitchEnum, additional: Any? = nil
    ) -> Any? {
        guard let builder, let enumType = enumType(of: instruction.value)
        else { return nil }
        let discriminant = discriminantType(enumType)
        guard let condition = discriminantValue(from: instruction.value, enumType: enumType)
        else { return nil }
        let defaultBlock: LLVMSwiftBinding.BasicBlock
        if let tirDefault = instruction.defaultBlock,
           let llvmDefault = blockMap[ObjectIdentifier(tirDefault)]
        {
            defaultBlock = llvmDefault
        } else {
            guard let currentFunction, let currentLLVMBlock else { return nil }
            defaultBlock = currentFunction.appendBasicBlock("default")
            builder.positionAtEnd(of: defaultBlock)
            builder.buildUnreachable()
            builder.positionAtEnd(of: currentLLVMBlock)
        }
        let switchInstruction = builder.buildSwitch(
            condition, default: defaultBlock, numCases: UInt32(instruction.cases.count)
        )
        for caseInfo in instruction.cases {
            guard let caseBlock = blockMap[ObjectIdentifier(caseInfo.block)] else { continue }
            switchInstruction.addCase(
                llvmContext.constantInt(UInt64(caseInfo.tag), type: discriminant),
                caseBlock
            )
            recordBlockArgEdge(target: caseInfo.block, arguments: caseInfo.arguments)
        }
        return nil
    }

    public override func visitExtractPayload(
        _ instruction: TIR.ExtractPayload, additional: Any? = nil
    ) -> Any? {
        guard let builder, let enumType = enumType(of: instruction.value)
        else { return nil }
        let payloadType = lowerType(instruction.result.ty)
        let structType = lowerType(enumType.id)
        guard let slot = slotPointer(from: instruction.value, structType: structType) else {
            return nil
        }
        let bufferPointer = builder.buildStructGEP(structType, slot, index: 1)
        let loaded = builder.buildLoad(payloadType, bufferPointer)
        valueMap[ObjectIdentifier(instruction.result)] = loaded
        return nil
    }

    public override func visitAllocStack(
        _ instruction: TIR.AllocStack, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let lowered = lowerType(instruction.allocatedType)
        guard lowered is LLVMSwiftBinding.VoidType == false else { return nil }
        let alloca = builder.buildAlloca(lowered, name: instruction.result.name)
        valueMap[ObjectIdentifier(instruction.result)] = alloca
        return nil
    }

    public override func visitDeallocStack(
        _ instruction: TIR.DeallocStack, additional: Any? = nil
    ) -> Any? {
        nil
    }

    public override func visitLoad(_ instruction: TIR.Load, additional: Any? = nil) -> Any? {
        guard let builder, let pointer = value(instruction.ptr) else { return nil }
        let loaded = builder.buildLoad(lowerType(instruction.result.ty), pointer)
        valueMap[ObjectIdentifier(instruction.result)] = loaded
        return nil
    }

    public override func visitStore(_ instruction: TIR.Store, additional: Any? = nil) -> Any? {
        guard let builder,
              let stored = value(instruction.value),
              let pointer = value(instruction.ptr)
        else { return nil }
        builder.buildStore(stored, to: pointer)
        return nil
    }

    public override func visitSizeOf(_ instruction: TIR.SizeOf, additional: Any? = nil) -> Any? {
        let sized = llvmContext.sizeOf(lowerType(instruction.sizedType))
        valueMap[ObjectIdentifier(instruction.result)] = sized
        return nil
    }

    public override func visitStructElementAddr(
        _ instruction: TIR.StructElementAddr, additional: Any? = nil
    ) -> Any? {
        guard let builder, let base = value(instruction.base) else { return nil }
        let structType = lowerType(pointeeTypeID(instruction.base.ty))
        let address = builder.buildStructGEP(structType, base, index: UInt32(instruction.index))
        valueMap[ObjectIdentifier(instruction.result)] = address
        return nil
    }

    public override func visitTupleElementAddr(
        _ instruction: TIR.TupleElementAddr, additional: Any? = nil
    ) -> Any? {
        guard let builder, let base = value(instruction.base) else { return nil }
        let tupleType = lowerType(pointeeTypeID(instruction.base.ty))
        let address = builder.buildStructGEP(tupleType, base, index: UInt32(instruction.index))
        valueMap[ObjectIdentifier(instruction.result)] = address
        return nil
    }

    public override func visitStructValue(
        _ instruction: TIR.StructValue, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let structType = lowerType(instruction.result.ty)
        let slot = builder.buildAlloca(structType, name: instruction.result.name)
        for (index, field) in instruction.fields.enumerated() {
            guard let fieldValue = value(field) else { continue }
            let fieldPointer = builder.buildStructGEP(structType, slot, index: UInt32(index))
            builder.buildStore(fieldValue, to: fieldPointer)
        }
        valueMap[ObjectIdentifier(instruction.result)] = slot
        return nil
    }

    public override func visitTupleValue(
        _ instruction: TIR.TupleValue, additional: Any? = nil
    ) -> Any? {
        guard let builder else { return nil }
        let tupleType = lowerType(instruction.result.ty)
        let slot = builder.buildAlloca(tupleType, name: instruction.result.name)
        for (index, element) in instruction.elements.enumerated() {
            guard let elementValue = value(element) else { continue }
            let elementPointer = builder.buildStructGEP(tupleType, slot, index: UInt32(index))
            builder.buildStore(elementValue, to: elementPointer)
        }
        valueMap[ObjectIdentifier(instruction.result)] = slot
        return nil
    }

    public override func visitEnumValue(
        _ instruction: TIR.EnumValue, additional: Any? = nil
    ) -> Any? {
        guard let builder, let enumType = registry?.type(instruction.result.ty) as? TIRType.EnumType
        else { return nil }
        let discriminant = discriminantType(enumType)
        if enumHasPayload(enumType) {
            let structType = lowerType(enumType.id)
            let slot = builder.buildAlloca(structType, name: instruction.result.name)
            let discriminantPointer = builder.buildStructGEP(structType, slot, index: 0)
            builder.buildStore(
                llvmContext.constantInt(UInt64(instruction.caseIndex), type: discriminant),
                to: discriminantPointer
            )
            if let payload = instruction.payload, let payloadValue = value(payload) {
                let bufferPointer = builder.buildStructGEP(structType, slot, index: 1)
                builder.buildStore(payloadValue, to: bufferPointer)
            }
            valueMap[ObjectIdentifier(instruction.result)] = slot
        } else {
            let slot = builder.buildAlloca(discriminant, name: instruction.result.name)
            builder.buildStore(
                llvmContext.constantInt(UInt64(instruction.caseIndex), type: discriminant),
                to: slot
            )
            valueMap[ObjectIdentifier(instruction.result)] = slot
        }
        return nil
    }

    public override func visitUnaryArith(
        _ instruction: TIR.UnaryArith, additional: Any? = nil
    ) -> Any? {
        guard let builder, let operand = value(instruction.operand) else { return nil }
        let kind = (registry?.type(instruction.operand.ty) as? TIRType.PrimitiveType)?.kind
        let built: LLVMSwiftBinding.Value? = switch instruction.op {
        case .Neg:
            kind == .Float ? builder.buildFNeg(operand) : builder.buildNeg(operand)
        case .Not:
            builder.buildNot(operand)
        case .Bitnot:
            builder.buildNot(operand)
        default:
            nil
        }
        if let built {
            valueMap[ObjectIdentifier(instruction.result)] = built
        }
        return nil
    }

    public override func visitBinaryArith(
        _ instruction: TIR.BinaryArith, additional: Any? = nil
    ) -> Any? {
        guard let builder,
              let lhs = value(instruction.lhs),
              let rhs = value(instruction.rhs)
        else { return nil }
        let kind = (registry?.type(instruction.lhs.ty) as? TIRType.PrimitiveType)?.kind
        let built: LLVMSwiftBinding.Value? = switch instruction.op {
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
        default:
            nil
        }
        if let built {
            valueMap[ObjectIdentifier(instruction.result)] = built
        }
        return nil
    }

    private func compare(
        _ instruction: TIR.BinaryArith, lhs: LLVMSwiftBinding.Value,
        rhs: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?,
        predicate: LLVMSwiftBinding.IntPredicate?
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else { return nil }
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

    public override func visitCall(_ instruction: TIR.Call, additional: Any? = nil) -> Any? {
        guard let builder,
              let callee = value(instruction.callee)
        else { return nil }
        if let functionReference = instruction.callee as? TIR.FunctionRef,
           let tirFunction = registry?.functions[functionReference.functionId],
           let builtinOp = builtinArithOp(from: tirFunction.name)
        {
            emitBuiltin(builtinOp, instruction)
            return nil
        }
        guard let functionType = lowerType(instruction.callee.ty) as? LLVMSwiftBinding.FunctionType
        else { return nil }
        let arguments = instruction.arguments.compactMap { value($0) }
        let call = builder.buildCall(callee, type: functionType, arguments, name: "")
        if let result = instruction.result {
            valueMap[ObjectIdentifier(result)] = call
        }
        return nil
    }

    private func builtinArithOp(from name: String) -> TIR.ArithOp? {
        guard name.hasPrefix("builtin_") else { return nil }
        let rest = String(name.dropFirst("builtin_".count))
        guard
            let opName = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true).first
        else { return nil }
        switch opName {
        case "add":
            return .Add
        case "sub":
            return .Sub
        case "mul":
            return .Mul
        case "div":
            return .SDiv
        case "rem":
            return .SRem
        case "neg":
            return .Neg
        case "not":
            return .Not
        case "bitnot":
            return .Bitnot
        case "and":
            return .And
        case "or":
            return .Or
        case "xor":
            return .Xor
        case "shl":
            return .Shl
        case "shr":
            return .Shr
        case "eq":
            return .Eq
        case "ne":
            return .Ne
        case "lt":
            return .Lt
        case "le":
            return .Le
        case "gt":
            return .Gt
        case "ge":
            return .Ge
        default:
            return nil
        }
    }

    private func emitBuiltin(_ op: TIR.ArithOp, _ instruction: TIR.Call) {
        if op.isUnary {
            guard let argument = instruction.arguments.first,
                  let operand = value(argument)
            else { return }
            let kind = (registry?.type(argument.ty) as? TIRType.PrimitiveType)?.kind
            let built = emitBuiltinUnary(op: op, operand: operand, kind: kind)
            if let built, let result = instruction.result {
                valueMap[ObjectIdentifier(result)] = built
            }
            return
        }
        guard let lhs = instruction.arguments.first,
              let rhs = instruction.arguments.dropFirst().first,
              let lhsValue = value(lhs), let rhsValue = value(rhs)
        else { return }
        let kind = (registry?.type(lhs.ty) as? TIRType.PrimitiveType)?.kind
        let built: LLVMSwiftBinding.Value? = if op.isCompare {
            emitBuiltinCompare(op: op, lhs: lhsValue, rhs: rhsValue, kind: kind)
        } else {
            emitBuiltinBinary(op: op, lhs: lhsValue, rhs: rhsValue, kind: kind)
        }
        if let built, let result = instruction.result {
            valueMap[ObjectIdentifier(result)] = built
        }
    }

    private func emitBuiltinUnary(
        op: TIR.ArithOp, operand: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else { return nil }
        switch op {
        case .Neg:
            return kind == .Float ? builder.buildFNeg(operand) : builder.buildNeg(operand)
        case .Not, .Bitnot:
            return builder.buildNot(operand)
        default:
            return nil
        }
    }

    private func emitBuiltinBinary(
        op: TIR.ArithOp, lhs: LLVMSwiftBinding.Value,
        rhs: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else { return nil }
        switch op {
        case .Add:
            return kind == .Float ? builder.buildFAdd(lhs, rhs) : builder.buildAdd(lhs, rhs)
        case .Sub:
            return kind == .Float ? builder.buildFSub(lhs, rhs) : builder.buildSub(lhs, rhs)
        case .Mul:
            return kind == .Float ? builder.buildFMul(lhs, rhs) : builder.buildMul(lhs, rhs)
        case .SDiv:
            return kind == .Float
                ? builder.buildFDiv(lhs, rhs)
                : (kind == .Unsigned ? builder.buildUDiv(lhs, rhs) : builder.buildSDiv(lhs, rhs))
        case .SRem:
            return kind == .Float
                ? builder.buildFRem(lhs, rhs)
                : (kind == .Unsigned ? builder.buildURem(lhs, rhs) : builder.buildSRem(lhs, rhs))
        case .And:
            return builder.buildAnd(lhs, rhs)
        case .Or:
            return builder.buildOr(lhs, rhs)
        case .Xor:
            return builder.buildXor(lhs, rhs)
        case .Shl:
            return builder.buildShl(lhs, rhs)
        case .Shr:
            return kind == .Unsigned ? builder.buildLShr(lhs, rhs) : builder.buildAShr(lhs, rhs)
        default:
            return nil
        }
    }

    private func emitBuiltinCompare(
        op: TIR.ArithOp, lhs: LLVMSwiftBinding.Value,
        rhs: LLVMSwiftBinding.Value, kind: TIRType.PrimitiveKind?
    ) -> LLVMSwiftBinding.Value? {
        guard let builder else { return nil }
        switch kind {
        case .Float:
            return builder.buildFCmp(realPredicate(for: op), lhs, rhs)
        default:
            return builder.buildICmp(intPredicate(for: op, unsigned: kind == .Unsigned), lhs, rhs)
        }
    }

    public override func visitFunctionRef(
        _ instruction: TIR.FunctionRef, additional: Any? = nil
    ) -> Any? {
        if let function = functionValue(for: instruction.functionId) {
            valueMap[ObjectIdentifier(instruction)] = function
        }
        return nil
    }

    public override func visitGlobalAddr(
        _ value: TIR.GlobalAddr, additional: Any? = nil
    ) -> Any? {
        if let llvmGlobal = globalMap[value.globalId] {
            valueMap[ObjectIdentifier(value)] = llvmGlobal
        }
        return nil
    }

    public override func visitAllocHeap(
        _ instruction: TIR.AllocHeap, additional: Any? = nil
    ) -> Any? {
        unsupported("AllocHeap", at: instruction.sourceRange)
        return nil
    }

    public override func visitDeallocHeap(
        _ instruction: TIR.DeallocHeap, additional: Any? = nil
    ) -> Any? {
        unsupported("DeallocHeap", at: instruction.sourceRange)
        return nil
    }

    public override func visitAllocCell(
        _ instruction: TIR.AllocCell, additional: Any? = nil
    ) -> Any? {
        unsupported("AllocCell", at: instruction.sourceRange)
        return nil
    }

    public override func visitDeallocCell(
        _ instruction: TIR.DeallocCell, additional: Any? = nil
    ) -> Any? {
        unsupported("DeallocCell", at: instruction.sourceRange)
        return nil
    }

    public override func visitClassElementAddr(
        _ instruction: TIR.ClassElementAddr, additional: Any? = nil
    ) -> Any? {
        unsupported("ClassElementAddr", at: instruction.sourceRange)
        return nil
    }

    public override func visitProjectCell(
        _ instruction: TIR.ProjectCell, additional: Any? = nil
    ) -> Any? {
        unsupported("ProjectCell", at: instruction.sourceRange)
        return nil
    }

    public override func visitTryCall(_ instruction: TIR.TryCall, additional: Any? = nil) -> Any? {
        unsupported("TryCall", at: instruction.sourceRange)
        return nil
    }

    public override func visitClosure(_ instruction: TIR.Closure, additional: Any? = nil) -> Any? {
        unsupported("Closure", at: instruction.sourceRange)
        return nil
    }

    public override func visitUpcast(_ instruction: TIR.Upcast, additional: Any? = nil) -> Any? {
        unsupported("Upcast", at: instruction.sourceRange)
        return nil
    }

    public override func visitUncheckedRefCast(
        _ instruction: TIR.UncheckedRefCast, additional: Any? = nil
    ) -> Any? {
        unsupported("UncheckedRefCast", at: instruction.sourceRange)
        return nil
    }

    public override func visitTypeMetadata(
        _ instruction: TIR.TypeMetadata, additional: Any? = nil
    ) -> Any? {
        unsupported("TypeMetadata", at: instruction.sourceRange)
        return nil
    }

    public override func visitTypeMetadataConstant(
        _ instruction: TIR.TypeMetadataConstant, additional: Any? = nil
    ) -> Any? {
        unsupported("TypeMetadataConstant", at: instruction.sourceRange)
        return nil
    }

    public override func visitIsInstance(
        _ instruction: TIR.IsInstance, additional: Any? = nil
    ) -> Any? {
        unsupported("IsInstance", at: instruction.sourceRange)
        return nil
    }

    public override func visitSuperclass(
        _ instruction: TIR.Superclass, additional: Any? = nil
    ) -> Any? {
        unsupported("Superclass", at: instruction.sourceRange)
        return nil
    }

    public override func visitTrap(
        _ instruction: TIR.Trap, additional: Any? = nil
    ) -> Any? {
        unsupported("Trap", at: instruction.sourceRange)
        return nil
    }

    public override func visitRetain(_ instruction: TIR.Retain, additional: Any? = nil) -> Any? {
        unsupported("Retain", at: instruction.sourceRange)
        return nil
    }

    public override func visitRelease(_ instruction: TIR.Release, additional: Any? = nil) -> Any? {
        unsupported("Release", at: instruction.sourceRange)
        return nil
    }

    public override func visitCopy(_ instruction: TIR.Copy, additional: Any? = nil) -> Any? {
        unsupported("Copy", at: instruction.sourceRange)
        return nil
    }

    public override func visitDestroy(_ instruction: TIR.Destroy, additional: Any? = nil) -> Any? {
        unsupported("Destroy", at: instruction.sourceRange)
        return nil
    }

    public override func visitInlineAsm(
        _ instruction: TIR.InlineAsm, additional: Any? = nil
    ) -> Any? {
        guard let builder, let module else { return nil }
        let operandValues = instruction.operands.compactMap { value($0) }
        let operandTypes = instruction.operands.compactMap { lowerType($0.ty) }
        let functionType = llvmContext.functionType(
            returnType: llvmContext.void, parameterTypes: operandTypes
        )
        let sideEffects = instruction.options.contains("volatile")
            || instruction.options.contains("sideeffect")
        let inlineAsm = llvmContext.constantInlineAsm(
            functionType,
            asmString: instruction.template,
            constraints: instruction.constraints.joined(separator: ","),
            hasSideEffects: sideEffects,
            isAlignStack: false
        )
        builder.buildCall(inlineAsm, type: functionType, operandValues, name: "")
        return nil
    }

    public override func visitIntegerLiteral(
        _ literal: TIR.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        if let materialized = materialize(literal) {
            valueMap[ObjectIdentifier(literal)] = materialized
        }
        return nil
    }

    public override func visitFloatLiteral(
        _ literal: TIR.FloatLiteral, additional: Any? = nil
    ) -> Any? {
        if let materialized = materialize(literal) {
            valueMap[ObjectIdentifier(literal)] = materialized
        }
        return nil
    }

    public override func visitCharLiteral(
        _ literal: TIR.CharLiteral, additional: Any? = nil
    ) -> Any? {
        if let materialized = materialize(literal) {
            valueMap[ObjectIdentifier(literal)] = materialized
        }
        return nil
    }

    public override func visitBoolLiteral(
        _ literal: TIR.BoolLiteral, additional: Any? = nil
    ) -> Any? {
        if let materialized = materialize(literal) {
            valueMap[ObjectIdentifier(literal)] = materialized
        }
        return nil
    }

    public override func visitNullptrLiteral(
        _ literal: TIR.NullptrLiteral, additional: Any? = nil
    ) -> Any? {
        if let materialized = materialize(literal) {
            valueMap[ObjectIdentifier(literal)] = materialized
        }
        return nil
    }

    public override func visitStringLiteral(
        _ literal: TIR.StringLiteral, additional: Any? = nil
    ) -> Any? {
        unsupported("string literal", at: literal.sourceRange)
        return nil
    }
}
