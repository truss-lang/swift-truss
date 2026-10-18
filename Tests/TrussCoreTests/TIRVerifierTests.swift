import SwiftBetterDiagnostic
import Testing
import TrussCore

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

    var i1: Id.TIRTypeId {
        registry.primitiveType(kind: .Bool, bitWidth: 1).id
    }

    var i8: Id.TIRTypeId {
        registry.integerType(isSigned: true, bitWidth: 8).id
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
        _ name: String = "main", parameters: [TIR.Parameter] = [], returnType: Id.TIRTypeId,
        isVariadic: Bool = false, isExtern: Bool = false
    ) -> TIR.Function {
        module.addFunction(
            name: name, parameters: parameters, returnType: returnType, isVariadic: isVariadic,
            isExtern: isExtern, callingConvention: nil
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

    var emittedMessages: [String] {
        context.diagnosticEngine.diagnostics.map(\.message)
    }
}

private func describe(_ failures: [TIR.Verifier.Failure]) -> String {
    failures.map { "\($0.kind.label): \($0.message)" }.joined(separator: " | ")
}

private func expectSingleFailure(
    _ failures: [TIR.Verifier.Failure], kind: TIR.Verifier.FailureKind, containing fragment: String
) {
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(failures.first?.kind == kind, "expected kind '\(kind.label)', got: \(describe(failures))")
    #expect(
        failures.first?.message.contains(fragment) == true,
        "expected a message containing '\(fragment)', got: \(describe(failures))"
    )
}

private func expectSingleFailure(
    _ failures: [TIR.Verifier.Failure], kind: TIR.Verifier.FailureKind, message: String
) {
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(failures.first?.kind == kind, "expected kind '\(kind.label)', got: \(describe(failures))")
    #expect(
        failures.first?.message == message,
        "expected message '\(message)', got: \(describe(failures))"
    )
}

private func expectNoFailures(_ failures: [TIR.Verifier.Failure]) {
    #expect(failures.isEmpty, "expected no failures, got: \(describe(failures))")
}

private func makeRange(offset: Int, filePath: String = "test.truss") -> SourceRange {
    SourceRange(
        location: SourceLocation(
            buffer: StringSourceBuffer(filePath: filePath, content: String(repeating: " ", count: offset + 1)),
            offset: offset, line: 1, column: offset + 1
        )
    )
}

@Test
func kindLabelsAreDistinct() {
    let kinds: [TIR.Verifier.FailureKind] = [.Structure, .Dominance, .Registry, .TypeConsistency]
    #expect(Set(kinds.map(\.label)) == ["structure", "dominance", "registry", "type"])
    #expect(Set(kinds.map(\.rawValue)).count == 4)
}

@Test
func moduleViolatingAllFourKindsReportsEachKind() {
    let harness = Harness()
    let function = harness.addFunction(returnType: Id.TIRTypeId(4096))
    let entry = harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    let orphan = TIR.InstructionResult(ty: harness.i32, name: "orphan")
    entry.instructions.append(TIR.Store(value: orphan, ptr: cell.result))
    entry.instructions.append(TIR.Load(ptr: cell.result, ty: harness.i8, name: "mismatched"))
    harness.builder.buildReturn()
    function.addBasicBlock(name: "dangling")
    let failures = harness.verify()
    #expect(failures.count == 4, "expected four failures, got: \(describe(failures))")
    #expect(
        Set(failures.map(\.kind))
            == Set([TIR.Verifier.FailureKind.Structure, .Dominance, .Registry, .TypeConsistency])
    )
    #expect(Set(failures.map(\.message)).count == 4)
}

@Test
func blockWithoutTerminatorIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.AllocStack(registry: harness.registry, allocatedType: harness.i32, name: "0")
    )
    expectSingleFailure(harness.verify(), kind: .Structure, containing: "has no terminator instruction")
}

@Test
func instructionAfterTerminatorIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    harness.builder.buildReturn()
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .Structure, containing: "has instructions after its terminator")
}

@Test
func branchTargetOutsideFunctionIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let other = harness.addFunction("other", returnType: harness.void)
    let otherEntry = harness.addEntry(other)
    harness.builder.buildReturn()
    harness.builder.insertPoint = entry
    harness.builder.buildBranch(to: otherEntry)
    expectSingleFailure(harness.verify(), kind: .Structure, containing: "is not a basic block of function 'main'")
}

@Test
func branchArgumentCountMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let target = function.addBasicBlock(name: "target", parameters: [(name: "p", ty: harness.i32)])
    harness.builder.insertPoint = target
    harness.builder.buildReturn()
    harness.builder.insertPoint = entry
    harness.builder.buildBranch(to: target)
    expectSingleFailure(
        harness.verify(), kind: .Structure,
        containing: "passes 0 arguments but the block declares 1 parameters"
    )
}

@Test
func branchArgumentTypeMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let target = function.addBasicBlock(name: "target", parameters: [(name: "p", ty: harness.i64)])
    harness.builder.insertPoint = target
    harness.builder.buildReturn()
    harness.builder.insertPoint = entry
    harness.builder.buildBranch(
        to: target, arguments: [harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32)]
    )
    expectSingleFailure(
        harness.verify(), kind: .Structure,
        message: "branch argument 0 into block 'target' of function 'main' has type i32 but the block parameter declares type i64"
    )
}

@Test
func conditionalBranchArgumentCountMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let thenBlock = function.addBasicBlock(name: "then", parameters: [(name: "p", ty: harness.i32)])
    let elseBlock = function.addBasicBlock(name: "else")
    harness.builder.insertPoint = thenBlock
    harness.builder.buildReturn()
    harness.builder.insertPoint = elseBlock
    harness.builder.buildReturn()
    harness.builder.insertPoint = entry
    harness.builder.buildConditionalBranch(
        condition: harness.builder.buildBoolLiteral(value: true, ty: harness.i1),
        trueBranch: thenBlock, falseBranch: elseBlock
    )
    expectSingleFailure(
        harness.verify(), kind: .Structure,
        containing: "true branch into block 'then' of function 'main' passes 0 arguments"
    )
}

@Test
func entryBlockTargetedByBranchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let loop = function.addBasicBlock(name: "loop")
    harness.builder.buildBranch(to: loop)
    harness.builder.insertPoint = loop
    harness.builder.buildBranch(to: entry)
    expectSingleFailure(harness.verify(), kind: .Structure, containing: "is targeted by a branch")
}

@Test
func nonExternFunctionWithoutBlocksIsReported() {
    let harness = Harness()
    harness.addFunction(returnType: harness.void)
    expectSingleFailure(harness.verify(), kind: .Structure, containing: "has no basic blocks")
}

@Test
func externFunctionWithoutBlocksIsLegal() {
    let harness = Harness()
    harness.addFunction(
        "puts",
        parameters: [TIR.Parameter(ty: harness.i32, name: "x")],
        returnType: harness.void,
        isExtern: true
    )
    expectNoFailures(harness.verify())
}

@Test
func operandWithoutDefinitionIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let target = function.addBasicBlock(name: "target", parameters: [(name: "p", ty: harness.i32)])
    harness.builder.insertPoint = target
    harness.builder.buildReturn()
    harness.builder.insertPoint = entry
    let orphan = TIR.InstructionResult(ty: harness.i32, name: "orphan")
    harness.builder.buildBranch(to: target, arguments: [orphan])
    expectSingleFailure(harness.verify(), kind: .Dominance, containing: "has no definition")
}

@Test
func useBeforeDefinitionInSameBlockIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    let loaded = harness.builder.buildLoad(ptr: cell.result)
    entry.instructions.insert(TIR.Store(value: loaded.result, ptr: cell.result), at: 1)
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .Dominance, containing: "before its definition")
}

@Test
func useInBlockNotDominatedByDefinitionIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.i32)
    let entry = harness.addEntry(function)
    let thenBlock = function.addBasicBlock(name: "then")
    let elseBlock = function.addBasicBlock(name: "else")
    let join = function.addBasicBlock(name: "join")
    harness.builder.buildConditionalBranch(
        condition: harness.builder.buildBoolLiteral(value: true, ty: harness.i1),
        trueBranch: thenBlock, falseBranch: elseBlock
    )
    harness.builder.insertPoint = thenBlock
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = elseBlock
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = join
    harness.builder.buildReturn(harness.builder.buildLoad(ptr: cell.result).result)
    expectSingleFailure(harness.verify(), kind: .Dominance, containing: "does not dominate its use")
}

@Test
func tryCallSuccessorsParticipateInDominance() {
    let harness = Harness()
    let callee = harness.addFunction("callee", returnType: harness.void, isExtern: true)
    let function = harness.addFunction(returnType: harness.i32)
    let entry = harness.addEntry(function)
    let success = function.addBasicBlock(name: "success")
    let failure = function.addBasicBlock(name: "failure")
    let join = function.addBasicBlock(name: "join")
    entry.instructions.append(
        TIR.TryCall(
            callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"),
            arguments: [], successBlock: success, errorBlock: failure, errorCell: nil,
            ty: harness.void, name: "0", hasResult: false
        )
    )
    harness.builder.insertPoint = success
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = failure
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = join
    harness.builder.buildReturn(harness.builder.buildLoad(ptr: cell.result).result)
    expectSingleFailure(harness.verify(), kind: .Dominance, containing: "does not dominate its use")
}

@Test
func parameterOperandsAreAttributable() {
    let harness = Harness()
    let function = harness.addFunction(
        parameters: [TIR.Parameter(ty: harness.i32, name: "p")], returnType: harness.i32
    )
    let entry = harness.addEntry(function)
    let parameter = function.parameters[0]
    harness.builder.buildReturn(parameter)
    expectNoFailures(harness.verify())
}

@Test
func blockArgumentOperandsAreAttributable() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.i32)
    let entry = harness.addEntry(function)
    let join = function.addBasicBlock(name: "join", parameters: [(name: "p", ty: harness.i32)])
    harness.builder.buildBranch(to: join, arguments: [harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32)])
    harness.builder.insertPoint = join
    harness.builder.buildReturn(join.parameters[0])
    expectNoFailures(harness.verify())
}

@Test
func typeIdMissingFromRegistryIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: Id.TIRTypeId(4096))
    harness.addEntry(function)
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .Registry, message: "type#4096 is not in registry.types"
    )
}

@Test
func functionTypeMismatchIsReported() {
    let harness = Harness()
    let functionType = harness.registry.functionType(parameters: [], returnType: harness.i8, isVariadic: false)
    let function = TIR.Function(
        module: harness.module, id: harness.registry.nextFunctionId, name: "main", ty: functionType.id,
        parameters: [], returnType: harness.i32, isVariadic: false, isExtern: false,
        callingConvention: nil
    )
    harness.module.functions.append(function)
    harness.registry.functions[function.id] = function
    harness.addEntry(function)
    harness.builder.buildReturn(harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32))
    expectSingleFailure(
        harness.verify(), kind: .Registry,
        message: "function 'main' has type fn()->i8 returning type i8 but the function declares return type i32"
    )
}

@Test
func functionParameterTypeMismatchIsReported() {
    let harness = Harness()
    let functionType = harness.registry.functionType(parameters: [], returnType: harness.void, isVariadic: false)
    let function = TIR.Function(
        module: harness.module, id: harness.registry.nextFunctionId, name: "main", ty: functionType.id,
        parameters: [TIR.Parameter(ty: harness.i32, name: "p")], returnType: harness.void, isVariadic: false,
        isExtern: false, callingConvention: nil
    )
    harness.module.functions.append(function)
    harness.registry.functions[function.id] = function
    harness.addEntry(function)
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .Registry,
        message: "function 'main' has type fn()->void with parameter types [i32] but the function declares []"
    )
}

@Test
func functionReferenceOutsideRegistryIsReported() {
    let harness = Harness()
    let callee = harness.addFunction("callee", returnType: harness.i32, isExtern: true)
    let function = harness.addFunction(returnType: harness.i32)
    harness.addEntry(function)
    let reference = TIR.FunctionRef(functionId: Id.TIRFunctionId(4096), ty: callee.ty, name: "ghost")
    let call = harness.builder.buildCall(callee: reference, arguments: [])
    harness.builder.buildReturn(call.result)
    expectSingleFailure(harness.verify(), kind: .Registry, containing: "not in registry.functions")
}

@Test
func globalReferenceOutsideRegistryIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    let address = TIR.GlobalAddr(
        globalId: Id.TIRGlobalId(4096), ty: harness.registry.pointerType(pointee: harness.i32).id, name: "ghost"
    )
    harness.builder.buildStore(
        value: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32), to: address
    )
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .Registry, containing: "not in registry.globals")
}

@Test
func metadataReferenceOutsideRegistryIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.VirtualMethod(
            metadata: Id.TIRMetadataId(4096), index: 0,
            selfValue: harness.builder.buildIntegerLiteral(value: 0, ty: harness.i64),
            ty: harness.i32, name: "0"
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .Registry, containing: "not in registry.metadatas")
}

@Test
func witnessReferenceOutsideRegistryIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.WitnessMethod(witness: Id.TIRWitnessId(4096), index: 0, ty: harness.i32, name: "0")
    )
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .Registry, containing: "not in registry.witnesses")
}

@Test
func protocolReferenceOutsideRegistryIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.OpaqueWitnessMethod(
            container: harness.builder.buildIntegerLiteral(value: 0, ty: harness.i64),
            protocolId: Id.TIRProtocolId(4096), index: 0, ty: harness.i32, name: "0"
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .Registry, containing: "not in registry.protocols")
}

@Test
func registryTypeIdentityBreachIsReported() {
    let harness = Harness()
    let integer = harness.registry.integerType(isSigned: true, bitWidth: 32)
    let pointer = harness.registry.pointerType(pointee: integer.id)
    harness.registry.types[integer.id] = pointer
    expectSingleFailure(harness.verify(), kind: .Registry, containing: "registry.types[")
}

@Test
func loadResultTypeMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    entry.instructions.append(TIR.Load(ptr: cell.result, ty: harness.i8, name: "mismatched"))
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "load result in block 'entry' of function 'main' has type i8 but the pointer points to type i32"
    )
}

@Test
func storeValueTypeMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildStore(
        value: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i8), to: cell.result
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "store value in block 'entry' of function 'main' has type i8 but the pointer points to type i32"
    )
}

@Test
func missingReturnValueIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.i32)
    harness.addEntry(function)
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "function 'main' returns type i32 but its return instruction in block 'entry' of function 'main' has no value"
    )
}

@Test
func returnValueTypeMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.i32)
    harness.addEntry(function)
    harness.builder.buildReturn(harness.builder.buildIntegerLiteral(value: 1, ty: harness.i8))
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "function 'main' returns type i32 but its return instruction in block 'entry' of function 'main' yields type i8"
    )
}

@Test
func valueReturnedFromVoidFunctionIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    harness.builder.buildReturn(harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32))
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "function 'main' returns void but its return instruction in block 'entry' of function 'main' yields type i32"
    )
}

@Test
func callCalleeWithoutFunctionTypeIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.Call(
            callee: harness.builder.buildIntegerLiteral(value: 0, ty: harness.i64),
            arguments: [], ty: harness.void, name: "0", hasResult: false
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call callee in block 'entry' of function 'main' has type i64, expected a function type"
    )
}

@Test
func callArgumentCountMismatchIsReported() {
    let harness = Harness()
    let callee = harness.addFunction(
        "callee", parameters: [TIR.Parameter(ty: harness.i32, name: "x")], returnType: harness.void,
        isExtern: true
    )
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    harness.builder.buildCall(
        callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"), arguments: []
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call in block 'entry' of function 'main' passes 0 arguments but the callee declares 1 parameters"
    )
}

@Test
func callArgumentTypeMismatchIsReported() {
    let harness = Harness()
    let callee = harness.addFunction(
        "callee", parameters: [TIR.Parameter(ty: harness.i32, name: "x")], returnType: harness.void,
        isExtern: true
    )
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    harness.builder.buildCall(
        callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"),
        arguments: [harness.builder.buildIntegerLiteral(value: 1, ty: harness.i8)]
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call argument 0 in block 'entry' of function 'main' has type i8 but the callee declares type i32"
    )
}

@Test
func callArgumentTypeNamesRenderNominalAndPointerTypes() {
    let harness = Harness()
    let structType = harness.registry.structType(name: "S")
    structType.fields = [(name: "a", type: harness.i32)]
    let structPointer = harness.registry.pointerType(pointee: structType.id).id
    let integerPointer = harness.registry.pointerType(pointee: harness.i64).id
    let callee = harness.addFunction(
        "callee", parameters: [TIR.Parameter(ty: structPointer, name: "s")], returnType: harness.void,
        isExtern: true
    )
    let function = harness.addFunction(
        parameters: [TIR.Parameter(ty: integerPointer, name: "p")], returnType: harness.void
    )
    harness.addEntry(function)
    harness.builder.buildCall(
        callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"),
        arguments: [function.parameters[0]]
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call argument 0 in block 'entry' of function 'main' has type *i64 but the callee declares type *S"
    )
}

@Test
func callArgumentTypeNamesRenderMangledNominalNamesFromTheRegistry() {
    let harness = Harness()
    let structType = harness.registry.structType(name: "$t4main_1S")
    structType.fields = [(name: "a", type: harness.i32)]
    let structPointer = harness.registry.pointerType(pointee: structType.id).id
    let callee = harness.addFunction(
        "callee", parameters: [TIR.Parameter(ty: structPointer, name: "s")], returnType: structType.id,
        isExtern: true
    )
    let function = harness.addFunction(returnType: structType.id)
    let entry = harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: structType.id)
    let loaded = harness.builder.buildLoad(ptr: cell.result)
    harness.builder.buildCall(
        callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"),
        arguments: [loaded.result]
    )
    harness.builder.buildReturn(loaded.result)
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call argument 0 in block 'entry' of function 'main' has type struct $t4main_1S but the callee declares type *$t4main_1S"
    )
}

@Test
func callArgumentTypeNamesPreferSourceNamesOverMangledNames() {
    let harness = Harness()
    let structType = harness.registry.structType(name: "$t4main_1S", displayName: "S")
    structType.fields = [(name: "a", type: harness.i32)]
    let structPointer = harness.registry.pointerType(pointee: structType.id).id
    let callee = harness.addFunction(
        "callee", parameters: [TIR.Parameter(ty: structPointer, name: "s")], returnType: structType.id,
        isExtern: true
    )
    let function = harness.addFunction(returnType: structType.id)
    let entry = harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: structType.id)
    let loaded = harness.builder.buildLoad(ptr: cell.result)
    harness.builder.buildCall(
        callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"),
        arguments: [loaded.result]
    )
    harness.builder.buildReturn(loaded.result)
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call argument 0 in block 'entry' of function 'main' has type struct S but the callee declares type *S"
    )
}

@Test
func calleeTypeNameRendersTupleType() {
    let harness = Harness()
    let tupleType = harness.registry.tupleType(
        elements: [
            TIRType.TupleType.Element(label: "x", type: harness.i32),
            TIRType.TupleType.Element(label: nil, type: harness.i64),
        ]
    )
    let function = harness.addFunction(
        parameters: [TIR.Parameter(ty: tupleType.id, name: "t")], returnType: harness.void
    )
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.Call(callee: function.parameters[0], arguments: [], ty: harness.void, name: "0", hasResult: false)
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call callee in block 'entry' of function 'main' has type (x: i32,i64), expected a function type"
    )
}

@Test
func calleeTypeNameRendersFunctionTypeBehindPointer() {
    let harness = Harness()
    let functionType = harness.registry.functionType(
        parameters: [harness.i32], returnType: harness.i32, isVariadic: false
    )
    let functionPointer = harness.registry.pointerType(pointee: functionType.id).id
    let function = harness.addFunction(
        parameters: [TIR.Parameter(ty: functionPointer, name: "fp")], returnType: harness.void
    )
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.Call(callee: function.parameters[0], arguments: [], ty: harness.void, name: "0", hasResult: false)
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call callee in block 'entry' of function 'main' has type *fn(i32)->i32, expected a function type"
    )
}

@Test
func calleeTypeNameRendersExistentialType() {
    let harness = Harness()
    let protocolRecord = harness.registry.addProtocol(name: "P")
    let existential = harness.registry.existentialType(protocols: [protocolRecord.id], name: "P")
    let function = harness.addFunction(
        parameters: [TIR.Parameter(ty: existential.id, name: "e")], returnType: harness.void
    )
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.Call(callee: function.parameters[0], arguments: [], ty: harness.void, name: "0", hasResult: false)
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call callee in block 'entry' of function 'main' has type any P, expected a function type"
    )
}

@Test
func calleeTypeNameRendersMetadataType() {
    let harness = Harness()
    let metadata = harness.registry.metadataType()
    let function = harness.addFunction(
        parameters: [TIR.Parameter(ty: metadata.id, name: "m")], returnType: harness.void
    )
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.Call(callee: function.parameters[0], arguments: [], ty: harness.void, name: "0", hasResult: false)
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "call callee in block 'entry' of function 'main' has type meta, expected a function type"
    )
}

@Test
func pointeeTypeNameRendersVoid() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.void)
    harness.builder.buildStore(
        value: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32), to: cell.result
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "store value in block 'entry' of function 'main' has type i32 but the pointer points to type void"
    )
}

@Test
func typesMissingFromTheRegistryRenderAsTypeHashIds() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let cast = TIR.NumericCast(
        value: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i8), op: .SExt,
        targetType: Id.TIRTypeId(4096), name: "0"
    )
    cast.result = TIR.InstructionResult(ty: harness.i8, name: "0")
    entry.instructions.append(cast)
    harness.builder.buildReturn()
    let failures = harness.verify()
    #expect(failures.count == 2, "expected two failures, got: \(describe(failures))")
    #expect(
        failures.map(\.message).contains("type#4096 is not in registry.types"),
        "expected the unresolved id to render as type#4096, got: \(describe(failures))"
    )
    #expect(
        failures.map(\.message).contains(
            "numeric cast result in block 'entry' of function 'main' has type i8 but the instruction casts to type type#4096"
        ),
        "expected the fallback type name in the cast diagnostic, got: \(describe(failures))"
    )
}

@Test
func callResultForVoidCalleeIsReported() {
    let harness = Harness()
    let callee = harness.addFunction("callee", returnType: harness.void, isExtern: true)
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.Call(
            callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"),
            arguments: [], ty: harness.void, name: "0", hasResult: true
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .TypeConsistency, containing: "but produces a result")
}

@Test
func callWithoutResultForNonVoidCalleeIsReported() {
    let harness = Harness()
    let callee = harness.addFunction("callee", returnType: harness.i32, isExtern: true)
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.Call(
            callee: TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: "callee"),
            arguments: [], ty: harness.i32, name: "0", hasResult: false
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(harness.verify(), kind: .TypeConsistency, containing: "produces no result")
}

@Test
func conditionalBranchConditionWithoutI1IsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let thenBlock = function.addBasicBlock(name: "then")
    let elseBlock = function.addBasicBlock(name: "else")
    harness.builder.buildConditionalBranch(
        condition: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32),
        trueBranch: thenBlock, falseBranch: elseBlock
    )
    harness.builder.insertPoint = thenBlock
    harness.builder.buildReturn()
    harness.builder.insertPoint = elseBlock
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "conditional branch condition in block 'entry' of function 'main' has type i32, expected bool"
    )
}

@Test
func binaryArithOperandTypeMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.BinaryArith(
            op: .Add, lhs: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32),
            rhs: harness.builder.buildIntegerLiteral(value: 2, ty: harness.i8), ty: harness.i32, name: "0"
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "add operands in block 'entry' of function 'main' have type i32 and i8"
    )
}

@Test
func unaryArithResultTypeMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.UnaryArith(
            op: .Neg, operand: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32),
            ty: harness.i8, name: "0"
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "neg result in block 'entry' of function 'main' has type i8 but its operand has type i32"
    )
}

@Test
func comparisonResultWithoutI1IsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(
        TIR.BinaryArith(
            op: .Eq, lhs: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32),
            rhs: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32), ty: harness.i32, name: "0"
        )
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "comparison result in block 'entry' of function 'main' has type i32, expected bool"
    )
}

@Test
func allocationResultWithoutPointerTypeIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let allocation = TIR.AllocStack(registry: harness.registry, allocatedType: harness.i32, name: "0")
    allocation.result = TIR.InstructionResult(ty: harness.i32, name: "0")
    entry.instructions.append(allocation)
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "allocstack result in block 'entry' of function 'main' has type i32, expected a pointer to type i32"
    )
}

@Test
func allocationResultPointingToOtherTypeIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let allocation = TIR.AllocStack(registry: harness.registry, allocatedType: harness.i32, name: "0")
    allocation.result = TIR.InstructionResult(
        ty: harness.registry.pointerType(pointee: harness.i8).id, name: "0"
    )
    entry.instructions.append(allocation)
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "allocstack result in block 'entry' of function 'main' points to type i8 but the instruction allocates type i32"
    )
}

@Test
func castResultTypeMismatchIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let cast = TIR.NumericCast(
        value: harness.builder.buildIntegerLiteral(value: 1, ty: harness.i8), op: .SExt,
        targetType: harness.i32, name: "0"
    )
    cast.result = TIR.InstructionResult(ty: harness.i8, name: "0")
    entry.instructions.append(cast)
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "numeric cast result in block 'entry' of function 'main' has type i8 but the instruction casts to type i32"
    )
}

@Test
func elementAddressIndexOutOfRangeIsReported() {
    let harness = Harness()
    let structType = harness.registry.structType(name: "S")
    structType.fields = [
        (name: "a", type: harness.i32), (name: "b", type: harness.i64), (name: "c", type: harness.i8),
    ]
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    let aggregate = harness.builder.buildAllocStack(allocatedType: structType.id)
    harness.builder.buildStructElementAddr(base: aggregate.result, index: 2)
    structType.fields = [(name: "a", type: harness.i32), (name: "b", type: harness.i64)]
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "struct element address index 2 in block 'entry' of function 'main' is out of range for type struct S with 2 elements"
    )
}

@Test
func elementAddressBaseWithoutAggregateTypeIsReported() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    entry.instructions.append(
        TIR.StructElementAddr(registry: harness.registry, base: cell.result, index: 0, name: "0")
    )
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "struct element address base in block 'entry' of function 'main' has type *i32, expected a pointer to a struct, class or tuple"
    )
}

@Test
func enumValueCaseIndexOutOfRangeIsReported() {
    let harness = Harness()
    let enumType = harness.registry.enumType(name: "E")
    enumType.cases = [(name: "A", associatedTypes: [])]
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    entry.instructions.append(TIR.EnumValue(caseIndex: 3, payload: nil, ty: enumType.id, name: "0"))
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "enum value in block 'entry' of function 'main' uses case index 3 but enum 'E' declares 1 cases"
    )
}

@Test
func extractPayloadCaseIndexOutOfRangeIsReported() {
    let harness = Harness()
    let enumType = harness.registry.enumType(name: "E")
    enumType.cases = [(name: "A", associatedTypes: [harness.i32]), (name: "B", associatedTypes: [])]
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let value = TIR.EnumValue(caseIndex: 0, payload: nil, ty: enumType.id, name: "0")
    entry.instructions.append(value)
    entry.instructions.append(TIR.ExtractPayload(value: value.result, caseIndex: 5, ty: harness.i32, name: "1"))
    harness.builder.buildReturn()
    expectSingleFailure(
        harness.verify(), kind: .TypeConsistency,
        message: "extract payload in block 'entry' of function 'main' uses case index 5 but enum 'E' declares 2 cases"
    )
}

@Test
func legalModuleHasNoFailures() {
    let harness = Harness()
    let structType = harness.registry.structType(name: "S")
    structType.fields = [(name: "a", type: harness.i32), (name: "b", type: harness.i64)]
    let global = harness.module.addGlobal(name: "g", type: harness.i32, isExtern: true, hasInitializer: false)
    let callee = harness.addFunction(
        "callee", parameters: [TIR.Parameter(ty: harness.i32, name: "x")], returnType: harness.i32,
        isExtern: true
    )
    let function = harness.addFunction("main", returnType: harness.i32)
    let entry = harness.addEntry(function)
    let thenBlock = function.addBasicBlock(name: "then")
    let elseBlock = function.addBasicBlock(name: "else")
    let join = function.addBasicBlock(name: "join", parameters: [(name: "p", ty: harness.i32)])

    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    let aggregate = harness.builder.buildAllocStack(allocatedType: structType.id)
    let one = harness.builder.buildIntegerLiteral(value: 1, ty: harness.i32)
    harness.builder.buildStore(value: one, to: cell.result)
    let loaded = harness.builder.buildLoad(ptr: cell.result)
    let address = harness.builder.buildGlobalAddr(global: global)
    harness.builder.buildStore(value: loaded.result, to: address)
    let two = harness.builder.buildIntegerLiteral(value: 2, ty: harness.i64)
    let fieldAddress = harness.builder.buildStructElementAddr(base: aggregate.result, index: 1)
    harness.builder.buildStore(value: two, to: fieldAddress.result)
    harness.builder.buildLoad(ptr: fieldAddress.result)
    let three = harness.builder.buildIntegerLiteral(value: 3, ty: harness.i32)
    let sum = harness.builder.buildBinaryArith(op: .Add, lhs: loaded.result, rhs: three)
    let comparison = TIR.BinaryArith(op: .Eq, lhs: sum.result, rhs: three, ty: harness.i1, name: "compare")
    entry.instructions.append(comparison)
    harness.builder.buildConditionalBranch(
        condition: comparison.result, trueBranch: thenBlock, falseBranch: elseBlock
    )
    harness.builder.insertPoint = thenBlock
    let call = harness.builder.buildCall(
        callee: harness.builder.buildFunctionRef(function: callee), arguments: [sum.result]
    )
    harness.builder.buildBranch(to: join, arguments: [call.result!])
    harness.builder.insertPoint = elseBlock
    harness.builder.buildBranch(to: join, arguments: [loaded.result])
    harness.builder.insertPoint = join
    harness.builder.buildReturn(join.parameters[0])
    expectNoFailures(harness.verify())
}

@Test
func failuresAreEmittedAsDiagnostics() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    harness.addEntry(function)
    let failures = harness.verify()
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(
        harness.emittedMessages
            == ["TIR verification failed: structure: block 'entry' of function 'main' has no terminator instruction"]
    )
}

@Test
func instructionRangeIsPreferredForDiagnostics() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    function.sourceRange = makeRange(offset: 5)
    let entry = harness.addEntry(function)
    entry.sourceRange = makeRange(offset: 23)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    let load = TIR.Load(ptr: cell.result, ty: harness.i8, name: "1")
    load.sourceRange = makeRange(offset: 42)
    entry.instructions.append(load)
    harness.builder.buildReturn()
    let failures = harness.verify()
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(
        failures.first?.range == makeRange(offset: 42),
        "expected the instruction range, got: \(describe(failures))"
    )
    #expect(failures.first?.range.start.buffer.filePath == "test.truss")
}

@Test
func blockRangeIsUsedWhenInstructionRangeIsUnknown() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    function.sourceRange = makeRange(offset: 5)
    let entry = harness.addEntry(function)
    entry.sourceRange = makeRange(offset: 23)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    entry.instructions.append(TIR.Load(ptr: cell.result, ty: harness.i8, name: "1"))
    harness.builder.buildReturn()
    let failures = harness.verify()
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(failures.first?.range == makeRange(offset: 23), "expected the block range, got: \(describe(failures))")
}

@Test
func functionRangeIsUsedWhenInstructionRangeIsUnknown() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    function.sourceRange = makeRange(offset: 5)
    let entry = harness.addEntry(function)
    let cell = harness.builder.buildAllocStack(allocatedType: harness.i32)
    entry.instructions.append(TIR.Load(ptr: cell.result, ty: harness.i8, name: "1"))
    harness.builder.buildReturn()
    let failures = harness.verify()
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(failures.first?.range == makeRange(offset: 5), "expected the function range, got: \(describe(failures))")
}

@Test
func blockWithoutTerminatorReportsTheBlockRange() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    function.sourceRange = makeRange(offset: 5)
    let entry = harness.addEntry(function)
    entry.sourceRange = makeRange(offset: 7)
    entry.instructions.append(
        TIR.AllocStack(registry: harness.registry, allocatedType: harness.i32, name: "0")
    )
    let failures = harness.verify()
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(failures.first?.kind == .Structure)
    #expect(failures.first?.range == makeRange(offset: 7), "expected the block range, got: \(describe(failures))")
}

@Test
func branchArgumentCountMismatchReportsTheBranchingBlockRange() {
    let harness = Harness()
    let function = harness.addFunction(returnType: harness.void)
    let entry = harness.addEntry(function)
    let target = function.addBasicBlock(name: "target", parameters: [(name: "p", ty: harness.i32)])
    harness.builder.insertPoint = target
    harness.builder.buildReturn()
    harness.builder.insertPoint = entry
    harness.builder.buildBranch(to: target)
    entry.sourceRange = makeRange(offset: 11)
    target.sourceRange = makeRange(offset: 99)
    function.sourceRange = makeRange(offset: 5)
    let failures = harness.verify()
    #expect(failures.count == 1, "expected exactly one failure, got: \(describe(failures))")
    #expect(failures.first?.kind == .Structure)
    #expect(
        failures.first?.range == makeRange(offset: 11),
        "expected the branching block range, got: \(describe(failures))"
    )
}

@Test
func emptyModuleHasNoFailures() {
    let harness = Harness()
    expectNoFailures(harness.verify())
}
