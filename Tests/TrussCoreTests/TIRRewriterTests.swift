import Testing
@testable import TrussCore

private struct Harness {
    let context: Context
    let registry: TIR.Registry
    let module: TIR.Module
    let builder: TIR.Builder

    init() {
        let context = Context()
        let registry = TIR.Registry()
        self.context = context
        self.registry = registry
        module = TIR.Module(registry: registry)
        builder = TIR.Builder(registry: registry)
    }

    var i32: Id.TIRTypeId {
        registry.integerType(isSigned: true, bitWidth: 32).id
    }

    var i64: Id.TIRTypeId {
        registry.integerType(isSigned: true, bitWidth: 64).id
    }

    var void: Id.TIRTypeId {
        registry.voidType().id
    }

    @discardableResult
    func addFunction(
        _ name: String, parameters: [TIR.Parameter], returnType: Id.TIRTypeId,
        parameterOwnership: [TIR.Ownership]? = nil, resultOwnership: TIR.Ownership = .Owned
    ) -> TIR.Function {
        module.addFunction(
            name: name, parameters: parameters, returnType: returnType, isVariadic: false,
            isExtern: false, callingConvention: nil, parameterOwnership: parameterOwnership,
            resultOwnership: resultOwnership
        )
    }

    @discardableResult
    func addEntry(_ function: TIR.Function) -> TIR.BasicBlock {
        let block = function.addBasicBlock(name: "entry")
        builder.insertPoint = block
        return block
    }

    func verify() -> [TIR.Verifier.Failure] {
        TIR.Verifier(context: context).verify(module)
    }
}

private final class Guaranteeing: TIR.Rewriter {
    private let registry: TIR.Registry

    init(registry: TIR.Registry) {
        self.registry = registry
    }

    override func rewriteFunctionSignature(_ function: TIR.Function) -> Id.TIRTypeId {
        registry.functionType(
            parameters: function.parameters.map(\.ty), returnType: function.returnType,
            isVariadic: function.isVariadic,
            parameterOwnership: function.parameters.map { _ in .Guaranteed },
            resultOwnership: .Guaranteed
        ).id
    }
}

private final class ArithmeticReplacement: TIR.Rewriter {
    private let target: TIR.BinaryArith
    private let signed: Bool
    private let bitWidth: Int
    private let registry: TIR.Registry
    private(set) var replacement: TIR.BinaryArith?

    init(target: TIR.BinaryArith, signed: Bool, bitWidth: Int, registry: TIR.Registry) {
        self.target = target
        self.signed = signed
        self.bitWidth = bitWidth
        self.registry = registry
    }

    override func replacement(for instruction: TIR.Instruction) -> TIR.Instruction? {
        guard let arith = instruction as? TIR.BinaryArith, arith === target else {
            return nil
        }
        let ty = registry.integerType(isSigned: signed, bitWidth: bitWidth).id
        let one = TIR.IntegerLiteral(value: 1, ty: ty, name: "one")
        let replacement = TIR.BinaryArith(
            op: arith.op, lhs: arith.lhs, rhs: one, ty: ty, name: arith.result.name
        )
        self.replacement = replacement
        return replacement
    }
}

private func describe(_ failures: [TIR.Verifier.Failure]) -> String {
    failures.map { "\($0.kind.label): \($0.message)" }.joined(separator: " | ")
}

private func functionType(of function: TIR.Function) -> TIRType.FunctionType? {
    function.module?.registry.types[function.ty] as? TIRType.FunctionType
}

private func references(_ value: TIR.Value, in module: TIR.Module) -> Bool {
    for function in module.functions {
        for block in function.basicBlocks {
            if block.parameters.contains(where: { $0 === value }) {
                return true
            }
            for instruction in block.instructions {
                if TIR.Operands.operands(of: instruction).contains(where: { $0 === value }) {
                    return true
                }
            }
        }
    }
    return false
}

private func makeIntegerFunction(_ harness: Harness) -> (TIR.Function, TIR.BinaryArith) {
    let parameters = [
        TIR.Parameter(ty: harness.i32, name: "a"),
        TIR.Parameter(ty: harness.i32, name: "b"),
    ]
    let function = harness.addFunction("add", parameters: parameters, returnType: harness.i32)
    harness.addEntry(function)
    let arith = harness.builder.buildBinaryArith(op: .Add, lhs: parameters[0], rhs: parameters[1])
    harness.builder.buildReturn(arith.result)
    return (function, arith)
}

@Test
func unchangedRewriteReturnsTheSameInstances() {
    let harness = Harness()
    let global = harness.module.addGlobal(
        name: "g", type: harness.i32, isExtern: false, hasInitializer: false
    )
    let (function, arith) = makeIntegerFunction(harness)
    let entry = function.basicBlocks[0]
    let identity = TIR.Rewriter()

    #expect(identity.rewrite(module: harness.module) === harness.module)
    #expect(identity.rewrite(function: function) === function)
    #expect(identity.rewrite(block: entry) === entry)
    #expect(identity.rewrite(instruction: arith) === arith)
    #expect(identity.rewrite(value: arith.result) === arith.result)
    #expect(identity.rewrite(global: global) === global)
    #expect(harness.module.functions[0] === function)
    #expect(harness.module.globals[0] === global)
    #expect(function.basicBlocks[0] === entry)
    #expect(entry.instructions[0] === arith)
    #expect(function.nextValueIndex == 1)
}

@Test
func unchangedRewritePreservesSharedObjects() {
    let harness = Harness()
    let (function, _) = makeIntegerFunction(harness)
    let registry = harness.registry
    let types = registry.types
    let functions = registry.functions
    let metadata = registry.addMetadata(name: "Box")
    let typesBefore = types.count

    TIR.Rewriter().rewrite(module: harness.module)

    #expect(registry.types.count == typesBefore)
    #expect(registry.functions.count == functions.count)
    #expect(registry.functions[function.id] === function)
    #expect(registry.metadatas[metadata.id] === metadata)
    for (id, ty) in types {
        #expect(registry.types[id] === ty)
    }
}

@Test
func replacedProducerIsRemappedAtEveryUseSite() {
    let harness = Harness()
    let (function, arith) = makeIntegerFunction(harness)
    let old = arith.result
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 64, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)

    let new = rewriter.replacement?.result
    #expect(new != nil)
    #expect(new !== old)
    #expect(rewriter.value(for: old) === new)
    let rewritten = harness.module.functions[0]
    #expect(rewritten !== function)
    let entry = rewritten.basicBlocks[0]
    #expect(entry.instructions.count == 2)
    #expect(entry.instructions[0] as? TIR.BinaryArith === rewriter.replacement)
    #expect((entry.instructions[1] as? TIR.Return)?.value === new)
    #expect(!references(old, in: harness.module))
}

@Test
func branchAndSwitchArgumentsAreRemapped() {
    let harness = Harness()
    let parameters = [
        TIR.Parameter(ty: harness.i32, name: "a"),
        TIR.Parameter(ty: harness.i32, name: "b"),
    ]
    let function = harness.addFunction("branchy", parameters: parameters, returnType: harness.i32)
    let entry = harness.addEntry(function)
    let arith = harness.builder.buildBinaryArith(op: .Add, lhs: parameters[0], rhs: parameters[1])
    let condition = harness.builder.buildBinaryArith(op: .Lt, lhs: parameters[0], rhs: parameters[1])
    harness.builder.buildBranch(to: entry, arguments: [arith.result])
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 64, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)

    let new = rewriter.replacement?.result
    #expect(new != nil)
    let branch = harness.module.functions[0].basicBlocks[0].instructions[2] as? TIR.Branch
    #expect(branch?.arguments.first === new)
    #expect(condition.result.ty != harness.i32)
    #expect(!references(arith.result, in: harness.module))
}

@Test
func conditionalBranchArgumentsAreRemapped() {
    let harness = Harness()
    let parameters = [
        TIR.Parameter(ty: harness.i32, name: "a"),
        TIR.Parameter(ty: harness.i32, name: "b"),
    ]
    let function = harness.addFunction("cond", parameters: parameters, returnType: harness.i32)
    let entry = harness.addEntry(function)
    let arith = harness.builder.buildBinaryArith(op: .Add, lhs: parameters[0], rhs: parameters[1])
    let condition = harness.builder.buildBinaryArith(op: .Lt, lhs: parameters[0], rhs: parameters[1])
    let taken = function.addBasicBlock(name: "taken", parameters: [(name: "merge", ty: harness.i32)])
    let alternative = function.addBasicBlock(
        name: "alternative", parameters: [(name: "merge", ty: harness.i32)]
    )
    harness.builder.insertPoint = taken
    harness.builder.buildReturn(taken.parameters[0])
    harness.builder.insertPoint = alternative
    harness.builder.buildReturn(alternative.parameters[0])
    harness.builder.insertPoint = entry
    harness.builder.buildConditionalBranch(
        condition: condition.result, trueBranch: taken, falseBranch: alternative,
        trueArguments: [arith.result], falseArguments: [parameters[0]]
    )
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 64, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)

    let new = rewriter.replacement?.result
    #expect(new != nil)
    let branch = harness.module.functions[0].basicBlocks[0].instructions[2] as? TIR.ConditionalBranch
    #expect(branch?.trueArguments.first === new)
    #expect(branch?.falseArguments.first === parameters[0])
    #expect(!references(arith.result, in: harness.module))
}

@Test
func storeAndCallOperandsAreRemapped() {
    let harness = Harness()
    let parameters = [
        TIR.Parameter(ty: harness.i32, name: "a"),
        TIR.Parameter(ty: harness.i32, name: "b"),
    ]
    let function = harness.addFunction("consumers", parameters: parameters, returnType: harness.i32)
    harness.addEntry(function)
    let arith = harness.builder.buildBinaryArith(op: .Add, lhs: parameters[0], rhs: parameters[1])
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildStore(value: arith.result, to: cell.result)
    let loaded = harness.builder.buildLoad(ptr: cell.result)
    let callee = TIR.FunctionRef(functionId: function.id, ty: function.ty, name: function.name)
    harness.builder.buildCall(callee: callee, arguments: [loaded.result])
    harness.builder.buildReturn(loaded.result)
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 64, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)

    let new = rewriter.replacement?.result
    #expect(new != nil)
    let instructions = harness.module.functions[0].basicBlocks[0].instructions
    #expect(instructions.count == 6)
    #expect((instructions[2] as? TIR.Store)?.value === new)
    #expect((instructions[3] as? TIR.Load)?.ptr === cell.result)
    #expect((instructions[3] as? TIR.Load) === loaded)
    #expect((instructions[4] as? TIR.Call)?.arguments.first === loaded.result)
    #expect((instructions[5] as? TIR.Return)?.value === loaded.result)
    #expect(!references(arith.result, in: harness.module))
}

@Test
func switchCasesAndPhiIncomingsAreRemapped() {
    let harness = Harness()
    let kindType = harness.registry.enumType(name: "$t8_kind")
    kindType.cases = [("first", []), ("second", [])]
    let parameters = [
        TIR.Parameter(ty: harness.i32, name: "a"),
        TIR.Parameter(ty: harness.i32, name: "b"),
    ]
    let function = harness.addFunction("switchy", parameters: parameters, returnType: harness.i32)
    let entry = harness.addEntry(function)
    let arith = harness.builder.buildBinaryArith(op: .Add, lhs: parameters[0], rhs: parameters[1])
    let kind = harness.builder.buildEnumValue(caseIndex: 0, payload: nil, ty: kindType.id)
    let taken = function.addBasicBlock(name: "taken", parameters: [(name: "x", ty: harness.i32)])
    let alternative = function.addBasicBlock(name: "alternative", parameters: [])
    harness.builder.insertPoint = taken
    let phi = harness.builder.buildPhi(
        incomings: [TIR.Phi.Incoming(value: arith.result, block: entry)]
    )
    harness.builder.buildReturn(phi.result)
    harness.builder.insertPoint = alternative
    harness.builder.buildReturn(parameters[0])
    harness.builder.insertPoint = entry
    harness.builder.buildSwitchEnum(
        value: kind.result, cases: [TIR.SwitchEnum.Case(tag: 0, block: taken, arguments: [arith.result])],
        defaultBlock: alternative
    )
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 64, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)

    let new = rewriter.replacement?.result
    #expect(new != nil)
    let rewrittenBlocks = harness.module.functions[0].basicBlocks
    let switchEnum = rewrittenBlocks[0].instructions[2] as? TIR.SwitchEnum
    #expect(switchEnum?.cases.first?.arguments.first === new)
    #expect(switchEnum?.defaultBlock === alternative)
    let rewrittenPhi = rewrittenBlocks[1].instructions[0] as? TIR.Phi
    #expect(rewrittenPhi?.incomings.first?.value === new)
    #expect(rewrittenPhi?.incomings.first?.block === entry)
    #expect(!references(arith.result, in: harness.module))
}

@Test
func tryCallOperandsAreRemapped() {
    let harness = Harness()
    let calleeParameters = [TIR.Parameter(ty: harness.i32, name: "value")]
    let callee = harness.addFunction("callee", parameters: calleeParameters, returnType: harness.i32)
    let parameters = [
        TIR.Parameter(ty: harness.i32, name: "a"),
        TIR.Parameter(ty: harness.i32, name: "b"),
    ]
    let caller = harness.addFunction("caller", parameters: parameters, returnType: harness.i32)
    harness.addEntry(caller)
    let arith = harness.builder.buildBinaryArith(op: .Add, lhs: parameters[0], rhs: parameters[1])
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    let success = caller.addBasicBlock(name: "success", parameters: [])
    let failure = caller.addBasicBlock(name: "failure", parameters: [])
    let reference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    let tryCall = harness.builder.buildTryCall(
        callee: reference, arguments: [arith.result], successBlock: success, errorBlock: failure,
        errorCell: cell.result
    )
    harness.builder.insertPoint = success
    harness.builder.buildReturn(tryCall.result)
    harness.builder.insertPoint = failure
    harness.builder.buildReturn(parameters[0])
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 64, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)

    let new = rewriter.replacement?.result
    #expect(new != nil)
    let rewrittenCaller = harness.module.functions[1]
    #expect(rewrittenCaller !== caller)
    #expect(harness.module.functions[0] === callee)
    let rewritten = rewrittenCaller.basicBlocks[0].instructions[2] as? TIR.TryCall
    #expect(rewritten?.arguments.first === new)
    #expect(rewritten?.errorCell === cell.result)
    #expect(rewritten?.callee === reference)
    #expect(!references(arith.result, in: harness.module))
}

@Test
func blockArgumentsAreRebuiltAndRemapped() {
    let harness = Harness()
    let parameters = [TIR.Parameter(ty: harness.i32, name: "a")]
    let function = harness.addFunction("joins", parameters: parameters, returnType: harness.i32)
    let entry = harness.addEntry(function)
    let join = function.addBasicBlock(name: "join", parameters: [(name: "x", ty: harness.i32)])
    harness.builder.buildBranch(to: join, arguments: [parameters[0]])
    harness.builder.insertPoint = join
    harness.builder.buildReturn(join.parameters[0])
    let replacement = TIR.BlockArgument(ty: harness.i32, name: "x", index: 0)
    let rewriter = TIR.Rewriter()
    rewriter.map(value: join.parameters[0], to: replacement)
    rewriter.rewrite(module: harness.module)

    let rewrittenFunction = harness.module.functions[0]
    #expect(rewrittenFunction !== function)
    #expect(harness.registry.functions[rewrittenFunction.id] === rewrittenFunction)
    let rewrittenBlocks = rewrittenFunction.basicBlocks
    #expect(rewrittenBlocks[0] === entry)
    #expect(rewrittenBlocks[1] !== join)
    #expect(rewrittenBlocks[1].parameters.first === replacement)
    #expect(rewrittenBlocks[1].function === rewrittenFunction)
    #expect((rewrittenBlocks[1].instructions[0] as? TIR.Return)?.value === replacement)
    let branch = rewrittenBlocks[0].instructions[0] as? TIR.Branch
    #expect(branch?.target === rewrittenBlocks[1])
    #expect(branch?.arguments.first === parameters[0])
    let failures = TIR.Verifier(context: harness.context).verify(harness.module)
    #expect(failures.isEmpty, "expected no failures, got: \(describe(failures))")
}

@Test
func blockArgumentRewriteRebuildsTheFunctionWithoutInstructionChanges() {
    let harness = Harness()
    let parameters = [TIR.Parameter(ty: harness.i32, name: "a")]
    let function = harness.addFunction("params", parameters: parameters, returnType: harness.i32)
    let entry = harness.addEntry(function)
    let join = function.addBasicBlock(name: "join", parameters: [(name: "x", ty: harness.i32)])
    harness.builder.buildBranch(to: join, arguments: [parameters[0]])
    harness.builder.insertPoint = join
    harness.builder.buildReturn(parameters[0])
    let replacement = TIR.BlockArgument(ty: harness.i32, name: "x", index: 0)
    let rewriter = TIR.Rewriter()
    rewriter.map(value: join.parameters[0], to: replacement)
    rewriter.rewrite(module: harness.module)

    let rewritten = harness.module.functions[0]
    #expect(rewritten !== function)
    #expect(rewritten.ty == function.ty)
    #expect(harness.registry.functions[rewritten.id] === rewritten)
    let blocks = rewritten.basicBlocks
    #expect(blocks[0] === entry)
    #expect(blocks[1] !== join)
    #expect(blocks[1].parameters.first === replacement)
    #expect(blocks[1].function === rewritten)
    #expect((blocks[1].instructions[0] as? TIR.Return)?.value === parameters[0])
    #expect((blocks[0].instructions[0] as? TIR.Branch)?.target === blocks[1])
    let failures = TIR.Verifier(context: harness.context).verify(harness.module)
    #expect(failures.isEmpty, "expected no failures, got: \(describe(failures))")
}

@Test
func ownershipConventionsSurviveARewrite() {
    let harness = Harness()
    let parameters = [TIR.Parameter(ty: harness.i64, name: "self")]
    let function = harness.addFunction(
        "takes", parameters: parameters, returnType: harness.i32,
        parameterOwnership: [.Guaranteed], resultOwnership: .Guaranteed
    )
    harness.addEntry(function)
    let lhs = harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32)
    let rhs = harness.builder.buildIntegerLiteral(value: 2, ty: harness.i32)
    let arith = harness.builder.buildBinaryArith(op: .Add, lhs: lhs, rhs: rhs)
    harness.builder.buildReturn(arith.result)
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 32, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)

    let rewritten = harness.module.functions[0]
    #expect(rewritten !== function)
    let rewrittenFunctionType = functionType(of: rewritten)
    #expect(rewrittenFunctionType?.parameterOwnership == [.Guaranteed])
    #expect(rewrittenFunctionType?.resultOwnership == .Guaranteed)
    #expect(
        rewritten.ty == harness.registry.functionType(
            parameters: [harness.i64], returnType: harness.i32, isVariadic: false,
            parameterOwnership: [.Guaranteed], resultOwnership: .Guaranteed
        ).id
    )
}

@Test
func signatureRebuildCarriesOwnershipConventions() {
    let harness = Harness()
    let parameters = [
        TIR.Parameter(ty: harness.i64, name: "self"),
        TIR.Parameter(ty: harness.i32, name: "value"),
    ]
    let function = harness.addFunction("owned", parameters: parameters, returnType: harness.i32)
    harness.addEntry(function)
    harness.builder.buildReturn(parameters[1])
    let rewriter = Guaranteeing(registry: harness.registry)
    rewriter.rewrite(module: harness.module)

    let rewritten = harness.module.functions[0]
    #expect(rewritten !== function)
    #expect(rewritten.ty != function.ty)
    let rewrittenFunctionType = functionType(of: rewritten)
    #expect(rewrittenFunctionType?.parameterOwnership == [.Guaranteed, .Guaranteed])
    #expect(rewrittenFunctionType?.resultOwnership == .Guaranteed)
    #expect(
        rewritten.ty == harness.registry.functionType(
            parameters: [harness.i64, harness.i32], returnType: harness.i32, isVariadic: false,
            parameterOwnership: [.Guaranteed, .Guaranteed], resultOwnership: .Guaranteed
        ).id
    )
    let failures = TIR.Verifier(context: harness.context).verify(harness.module)
    #expect(failures.isEmpty, "expected no failures, got: \(describe(failures))")
}

@Test
func typeSubstitutionRewritesInstructionTypes() {
    let harness = Harness()
    let structA = harness.registry.structType(name: "$t8_a")
    let structB = harness.registry.structType(name: "$t8_b")
    let pointerA = harness.registry.pointerType(pointee: structA.id).id
    let parameters = [TIR.Parameter(ty: pointerA, name: "ptr")]
    let function = harness.addFunction("sized", parameters: parameters, returnType: harness.i64)
    harness.addEntry(function)
    let size = harness.builder.buildSizeOf(sizedType: structA.id)
    harness.builder.buildReturn(size.result)
    let rewriter = TIR.Rewriter()
    rewriter.map(type: structA.id, to: structB.id)
    rewriter.rewrite(module: harness.module)

    let rewritten = harness.module.functions[0]
    #expect(rewritten !== function)
    #expect(rewritten.ty == function.ty)
    let instructions = rewritten.basicBlocks[0].instructions
    #expect((instructions[0] as? TIR.SizeOf)?.sizedType == structB.id)
    #expect((instructions[1] as? TIR.Return)?.value === (instructions[0] as? TIR.SizeOf)?.result)
    let failures = TIR.Verifier(context: harness.context).verify(harness.module)
    #expect(failures.isEmpty, "expected no failures, got: \(describe(failures))")
}

@Test
func rewrittenModulesKeepTheirVerifierFailureCount() {
    let harness = Harness()
    let (_, arith) = makeIntegerFunction(harness)
    let original = TIR.Verifier(context: harness.context).verify(harness.module).count
    TIR.Rewriter().rewrite(module: harness.module)
    let identity = TIR.Verifier(context: harness.context).verify(harness.module).count
    #expect(identity == original)
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 32, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)
    let modified = TIR.Verifier(context: harness.context).verify(harness.module)
    #expect(modified.count == original, "expected no new failures, got: \(describe(modified))")
}

@Test
func rewrittenModuleWithoutChangesStaysValid() {
    let harness = Harness()
    let (_, arith) = makeIntegerFunction(harness)
    let rewriter = ArithmeticReplacement(
        target: arith, signed: true, bitWidth: 32, registry: harness.registry
    )
    rewriter.rewrite(module: harness.module)
    let failures = TIR.Verifier(context: harness.context).verify(harness.module)
    #expect(failures.isEmpty, "expected no failures, got: \(describe(failures))")
}
