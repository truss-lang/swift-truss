import SwiftBetterDiagnostic
import Testing
import TrussCore

private struct OwnershipVerifierHarness {
    let context = Context()
    let registry = TIR.Registry()
    let module: TIR.Module
    let builder: TIR.Builder

    init() {
        module = TIR.Module(registry: registry)
        builder = TIR.Builder(registry: registry)
    }

    var i1: Id.TIRTypeId {
        registry.primitiveType(kind: .Bool, bitWidth: 1).id
    }

    var i32: Id.TIRTypeId {
        registry.integerType(isSigned: true, bitWidth: 32).id
    }

    var classType: Id.TIRTypeId {
        registry.classType(name: "C").id
    }

    var enumType: Id.TIRTypeId {
        let ty = registry.enumType(name: "E")
        if ty.cases.isEmpty {
            ty.cases = [(name: "first", associatedTypes: []), (name: "second", associatedTypes: [])]
        }
        return ty.id
    }

    @discardableResult
    func addFunction(
        _ name: String = "main", parameters: [TIR.Parameter] = [], returnType: Id.TIRTypeId? = nil,
        parameterOwnership: [TIR.Ownership]? = nil, resultOwnership: TIR.Ownership = .Owned
    ) -> TIR.Function {
        module.addFunction(
            name: name, parameters: parameters, returnType: returnType ?? registry.voidType().id,
            isVariadic: false, isExtern: false, callingConvention: nil,
            parameterOwnership: parameterOwnership, resultOwnership: resultOwnership
        )
    }

    @discardableResult
    func addEntry(_ function: TIR.Function) -> TIR.BasicBlock {
        let block = function.addBasicBlock(name: "entry")
        builder.insertPoint = block
        return block
    }

    func verify(_ mode: TIR.Verifier.OwnershipMode) -> [TIR.Verifier.Failure] {
        TIR.Verifier(context: context, ownershipMode: mode).verify(module)
    }

    var messages: [String] {
        context.diagnosticEngine.diagnostics.map(\.message)
    }
}

private func ownershipFailures(
    _ failures: [TIR.Verifier.Failure]
) -> [TIR.Verifier.Failure] {
    failures.filter { $0.kind == .Ownership }
}

private func describeFailures(_ failures: [TIR.Verifier.Failure]) -> String {
    failures.map { "[\($0.kind.label)] \($0.message)" }.joined(separator: " | ")
}

@Test
func advisoryModeIsTheDefault() {
    let harness = OwnershipVerifierHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    harness.builder.buildReturn(nil)

    let defaultFailures = TIR.Verifier(context: harness.context).verify(harness.module)
    #expect(defaultFailures.isEmpty, "expected no failures, got: \(describeFailures(defaultFailures))")
    #expect(
        ownershipFailures(harness.verify(.Strict)).contains {
            $0.message.contains("reference value 'c'")
        },
        "strict mode should report the unconsumed owned parameter"
    )
}

@Test
func ownedParameterEntersAtOneAndGuaranteedParameterAtZero() {
    let ownedHarness = OwnershipVerifierHarness()
    let ownedParameter = TIR.Parameter(ty: ownedHarness.classType, name: "c")
    let ownedFunction = ownedHarness.addFunction(parameters: [ownedParameter])
    ownedHarness.addEntry(ownedFunction)
    ownedHarness.builder.buildReturn(nil)
    let owned = ownershipFailures(ownedHarness.verify(.Strict))
    #expect(
        owned.contains {
            $0.message.contains("reference value 'c'")
                && $0.message.contains("retain/release balance 1 at the return, expected 0")
        },
        "expected the owned parameter to enter at +1, got: \(describeFailures(owned))"
    )

    let guaranteedHarness = OwnershipVerifierHarness()
    let guaranteedParameter = TIR.Parameter(ty: guaranteedHarness.classType, name: "c")
    let guaranteedFunction = guaranteedHarness.addFunction(
        parameters: [guaranteedParameter], parameterOwnership: [.Guaranteed]
    )
    guaranteedHarness.addEntry(guaranteedFunction)
    guaranteedHarness.builder.buildReturn(nil)
    let guaranteed = guaranteedHarness.verify(.Strict)
    #expect(
        guaranteed.isEmpty,
        "guaranteed parameter starts at 0 and needs no consumption, got: \(describeFailures(guaranteed))"
    )
}

@Test
func unconsumedOwnedParameterIsReportedInAdvisoryMode() {
    let harness = OwnershipVerifierHarness()
    let unused = TIR.Parameter(ty: harness.classType, name: "unused")
    let other = TIR.Parameter(ty: harness.classType, name: "other")
    let function = harness.addFunction(
        parameters: [unused, other], parameterOwnership: [.Owned, .Guaranteed]
    )
    harness.addEntry(function)
    harness.builder.buildRetain(other)
    harness.builder.buildRelease(other)
    harness.builder.buildReturn(nil)

    let reported = ownershipFailures(harness.verify(.Advisory))
    #expect(
        reported.contains {
            $0.message.contains("reference value 'unused'")
                && $0.message.contains("retain/release balance 1 at the return, expected 0")
        },
        "expected the unconsumed owned parameter to be reported, got: \(describeFailures(reported))"
    )
    #expect(
        !reported.contains { $0.message.contains("reference value 'other'") },
        "the balanced value must not be reported, got: \(describeFailures(reported))"
    )
}

@Test
func strictReportsWhatAdvisorySkipsOnUninstrumentedInput() {
    let harness = OwnershipVerifierHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildReturn(nil)

    let advisory = harness.verify(.Advisory)
    #expect(advisory.isEmpty, "advisory mode must skip uninstrumented functions, got: \(describeFailures(advisory))")

    let strict = ownershipFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("reference value 'c'")
                && $0.message.contains("retain/release balance 1 at the return, expected 0")
        },
        "strict mode should report the unconsumed owned parameter, got: \(describeFailures(strict))"
    )
    #expect(
        strict.contains { $0.message.contains("is not deallocated on every path to this return") },
        "strict mode should report the missing deallocstack, got: \(describeFailures(strict))"
    )
}

@Test
func balancedInputPassesInBothModes() {
    let harness = OwnershipVerifierHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    harness.builder.buildRelease(parameter)
    let allocation = harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildDeallocStack(allocation.result)
    harness.builder.buildReturn(nil)

    let advisory = harness.verify(.Advisory)
    #expect(advisory.isEmpty, "expected no failures, got: \(describeFailures(advisory))")
    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeFailures(strict))")
}

@Test
func ownedResultMustCarryExactlyOneReferenceAtTheReturn() {
    let balancedHarness = OwnershipVerifierHarness()
    let balancedParameter = TIR.Parameter(ty: balancedHarness.classType, name: "c")
    let balancedFunction = balancedHarness.addFunction(
        parameters: [balancedParameter], returnType: balancedHarness.classType
    )
    balancedHarness.addEntry(balancedFunction)
    balancedHarness.builder.buildReturn(balancedParameter)
    let balanced = balancedHarness.verify(.Strict)
    #expect(balanced.isEmpty, "expected the owned result transfer to pass, got: \(describeFailures(balanced))")

    let consumedHarness = OwnershipVerifierHarness()
    let consumedParameter = TIR.Parameter(ty: consumedHarness.classType, name: "c")
    let consumedFunction = consumedHarness.addFunction(
        parameters: [consumedParameter], returnType: consumedHarness.classType
    )
    consumedHarness.addEntry(consumedFunction)
    consumedHarness.builder.buildRelease(consumedParameter)
    consumedHarness.builder.buildReturn(consumedParameter)
    let consumed = ownershipFailures(consumedHarness.verify(.Strict))
    #expect(
        consumed.contains {
            $0.message.contains("reference value 'c'")
                && $0.message.contains("is transferred as an owned result with retain/release balance 0, expected 1")
        },
        "expected the released owned result to be reported, got: \(describeFailures(consumed))"
    )
}

@Test
func guaranteedResultMustBeBorrowedAtTheReturn() {
    let harness = OwnershipVerifierHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(
        parameters: [parameter], returnType: harness.classType, resultOwnership: .Guaranteed
    )
    harness.addEntry(function)
    harness.builder.buildRelease(parameter)
    harness.builder.buildReturn(parameter)
    let failures = harness.verify(.Strict)
    #expect(failures.isEmpty, "expected the borrowed result to pass, got: \(describeFailures(failures))")
}

@Test
func strictChecksLoopsThroughAFixpoint() {
    let balancedHarness = OwnershipVerifierHarness()
    let balancedCondition = TIR.Parameter(ty: balancedHarness.i1, name: "cond")
    let balancedParameter = TIR.Parameter(ty: balancedHarness.classType, name: "c")
    let balancedFunction = balancedHarness.addFunction(
        parameters: [balancedCondition, balancedParameter], parameterOwnership: [.Guaranteed, .Guaranteed]
    )
    let balancedEntry = balancedHarness.addEntry(balancedFunction)
    let balancedHeader = balancedFunction.addBasicBlock(name: "header")
    let balancedBody = balancedFunction.addBasicBlock(name: "body")
    let balancedExit = balancedFunction.addBasicBlock(name: "exit")
    balancedHarness.builder.insertPoint = balancedEntry
    balancedHarness.builder.buildBranch(to: balancedHeader)
    balancedHarness.builder.insertPoint = balancedHeader
    balancedHarness.builder.buildRetain(balancedParameter)
    balancedHarness.builder.buildRelease(balancedParameter)
    balancedHarness.builder.buildConditionalBranch(
        condition: balancedCondition, trueBranch: balancedBody, falseBranch: balancedExit
    )
    balancedHarness.builder.insertPoint = balancedBody
    balancedHarness.builder.buildBranch(to: balancedHeader)
    balancedHarness.builder.insertPoint = balancedExit
    balancedHarness.builder.buildReturn(nil)
    let balanced = balancedHarness.verify(.Strict)
    #expect(balanced.isEmpty, "expected the balanced loop to pass, got: \(describeFailures(balanced))")

    let leakingHarness = OwnershipVerifierHarness()
    let leakingCondition = TIR.Parameter(ty: leakingHarness.i1, name: "cond")
    let leakingParameter = TIR.Parameter(ty: leakingHarness.classType, name: "c")
    let leakingFunction = leakingHarness.addFunction(
        parameters: [leakingCondition, leakingParameter], parameterOwnership: [.Guaranteed, .Guaranteed]
    )
    let leakingEntry = leakingHarness.addEntry(leakingFunction)
    let leakingHeader = leakingFunction.addBasicBlock(name: "header")
    let leakingBody = leakingFunction.addBasicBlock(name: "body")
    let leakingExit = leakingFunction.addBasicBlock(name: "exit")
    leakingHarness.builder.insertPoint = leakingEntry
    leakingHarness.builder.buildBranch(to: leakingHeader)
    leakingHarness.builder.insertPoint = leakingHeader
    leakingHarness.builder.buildRetain(leakingParameter)
    leakingHarness.builder.buildConditionalBranch(
        condition: leakingCondition, trueBranch: leakingBody, falseBranch: leakingExit
    )
    leakingHarness.builder.insertPoint = leakingBody
    leakingHarness.builder.buildBranch(to: leakingHeader)
    leakingHarness.builder.insertPoint = leakingExit
    leakingHarness.builder.buildReturn(nil)
    let leaking = ownershipFailures(leakingHarness.verify(.Strict))
    #expect(
        leaking.contains {
            $0.message.contains("reference value 'c'")
                && $0.message.contains("retain/release balance unknown at the return, expected 0")
        },
        "expected the leaking loop to be reported, got: \(describeFailures(leaking))"
    )
}

@Test
func ownershipMessagesNameTheValueAndTheOffendingInstructionAndEmit() {
    let harness = OwnershipVerifierHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let range = SourceRange(
        location: SourceLocation(
            buffer: StringSourceBuffer(filePath: "ownership.truss", content: String(repeating: " ", count: 41)),
            offset: 40, line: 3, column: 5
        )
    )
    let ret = harness.builder.buildReturn(nil)
    ret.sourceRange = range

    let reported = ownershipFailures(harness.verify(.Strict))
    let failure = reported.first { $0.message.contains("reference value 'c'") }
    #expect(failure != nil, "expected a failure naming the value, got: \(describeFailures(reported))")
    #expect(
        failure?.message.contains("block 'entry' of function 'main'") == true,
        "expected the message to name the path, got: \(failure?.message ?? "")"
    )
    #expect(failure?.range.start.offset == 40, "expected the return instruction range")
    #expect(
        harness.messages.contains { $0.contains("TIR verification failed: ownership:") },
        "expected the failure to be emitted through context.emitError"
    )
}

@Test
func ownershipFailureKindKeepsItsLabelAndExistingKindsAreUnchanged() {
    #expect(TIR.Verifier.FailureKind.Ownership.label == "ownership")
    #expect(TIR.Verifier.FailureKind.Ownership.rawValue == "Ownership")
    #expect(TIR.Verifier.FailureKind.Structure.label == "structure")
    #expect(TIR.Verifier.FailureKind.Dominance.label == "dominance")
    #expect(TIR.Verifier.FailureKind.Registry.label == "registry")
    #expect(TIR.Verifier.FailureKind.TypeConsistency.label == "type")
    #expect(TIR.Verifier.FailureKind.TypeConsistency.rawValue == "type")
}

@Test
func destroyOfAStructContainingReferencesConsumesTheReferenceBalance() {
    let harness = OwnershipVerifierHarness()
    let holder = harness.registry.structType(name: "Holder")
    holder.fields = [(name: "child", type: harness.classType)]
    let parameter = TIR.Parameter(ty: holder.id, name: "s")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    harness.builder.buildDestroy(parameter)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "a struct holding references is torn down by destroy, got: \(describeFailures(failures))"
    )
}

@Test
func destroyingAStructContainingReferencesTwiceIsReported() {
    let harness = OwnershipVerifierHarness()
    let holder = harness.registry.structType(name: "Holder")
    holder.fields = [(name: "child", type: harness.classType)]
    let parameter = TIR.Parameter(ty: holder.id, name: "s")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    harness.builder.buildDestroy(parameter)
    harness.builder.buildDestroy(parameter)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.contains {
            $0.message.contains("reference value 's'")
                && $0.message.contains("balance -1 at the return")
        },
        "destroy must decrement the struct balance, got: \(describeFailures(failures))"
    )
}

@Test
func ownedCallArgumentsAndResultsAreBalanceTracked() {
    let harness = OwnershipVerifierHarness()
    let calleeParameter = TIR.Parameter(ty: harness.classType, name: "c")
    let callee = harness.addFunction(
        "callee", parameters: [calleeParameter], returnType: harness.classType,
        parameterOwnership: [.Owned], resultOwnership: .Owned
    )
    harness.addEntry(callee)
    harness.builder.buildReturn(calleeParameter)

    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let caller = harness.addFunction(
        "caller", parameters: [parameter], returnType: harness.classType,
        parameterOwnership: [.Owned]
    )
    harness.addEntry(caller)
    let reference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    let call = harness.builder.buildCall(callee: reference, arguments: [parameter])
    harness.builder.buildReturn(call.result)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "the owned argument transfers into the callee and the owned result transfers out, got: \(describeFailures(failures))"
    )
}

@Test
func ownedCallResultEntersAtOneAndTransfersOut() {
    let harness = OwnershipVerifierHarness()
    let calleeParameter = TIR.Parameter(ty: harness.classType, name: "n")
    let callee = harness.addFunction(
        "callee", parameters: [calleeParameter], returnType: harness.classType,
        parameterOwnership: [.Owned], resultOwnership: .Owned
    )
    harness.addEntry(callee)
    harness.builder.buildReturn(calleeParameter)

    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(
        "caller", parameters: [parameter], returnType: harness.classType,
        parameterOwnership: [.Owned]
    )
    harness.addEntry(function)
    let reference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    let call = harness.builder.buildCall(callee: reference, arguments: [parameter])
    harness.builder.buildReturn(call.result)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "an owned call result enters at +1 and transfers out, got: \(describeFailures(failures))"
    )
}

private func castAliasFailures(
    releases: Int,
    _ build: (OwnershipVerifierHarness, TIR.Value, Id.TIRTypeId) -> TIR.Value
) -> [TIR.Verifier.Failure] {
    let harness = OwnershipVerifierHarness()
    let targetClass = harness.registry.classType(name: "$s8_base").id
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let alias = build(harness, parameter, targetClass)
    for _ in 0 ..< releases {
        harness.builder.buildRelease(alias)
    }
    harness.builder.buildReturn(nil)
    return harness.verify(.Strict)
}

@Test
func heapAllocationReturnedFromACalleeAndConsumedByTheCallerIsAccepted() {
    let harness = OwnershipVerifierHarness()
    let callee = harness.addFunction(
        "make", returnType: harness.registry.pointerType(pointee: harness.classType).id,
        resultOwnership: .Owned
    )
    harness.addEntry(callee)
    let allocation = harness.builder.buildAllocHeap(allocatedType: harness.classType)
    harness.builder.buildReturn(allocation.result)

    let caller = harness.addFunction("caller")
    harness.addEntry(caller)
    let reference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    let call = harness.builder.buildCall(callee: reference, arguments: [])
    if let result = call.result {
        harness.builder.buildRelease(result)
    }
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "the owned heap result transfers out of the callee and is released by the caller, got: \(describeFailures(failures))"
    )
}

@Test
func callerThatLeaksTheCalleesOwnedHeapResultIsRejected() {
    let harness = OwnershipVerifierHarness()
    let callee = harness.addFunction(
        "make", returnType: harness.registry.pointerType(pointee: harness.classType).id,
        resultOwnership: .Owned
    )
    harness.addEntry(callee)
    let allocation = harness.builder.buildAllocHeap(allocatedType: harness.classType)
    harness.builder.buildReturn(allocation.result)

    let caller = harness.addFunction("caller")
    harness.addEntry(caller)
    let reference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    let call = harness.builder.buildCall(callee: reference, arguments: [])
    harness.builder.buildReturn(nil)

    let name = call.result?.name ?? ""
    let failures = ownershipFailures(harness.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("reference value '\(name)'")
                && $0.message.contains("retain/release balance 1 at the return, expected 0")
        },
        "expected the leaked owned heap result to be reported, got: \(describeFailures(failures))"
    )
}

@Test
func ownedCallArgumentMustCarryExactlyOneReferenceAtTheCall() {
    let harness = OwnershipVerifierHarness()
    let calleeParameter = TIR.Parameter(ty: harness.classType, name: "c")
    let callee = harness.addFunction("take", parameters: [calleeParameter], parameterOwnership: [.Owned])
    harness.addEntry(callee)
    harness.builder.buildRelease(calleeParameter)
    harness.builder.buildReturn(nil)

    let emptyParameter = TIR.Parameter(ty: harness.classType, name: "empty")
    let emptyCaller = harness.addFunction("emptyCaller", parameters: [emptyParameter])
    harness.addEntry(emptyCaller)
    harness.builder.buildRelease(emptyParameter)
    let emptyReference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    harness.builder.buildCall(callee: emptyReference, arguments: [emptyParameter])
    harness.builder.buildReturn(nil)

    let doubledParameter = TIR.Parameter(ty: harness.classType, name: "doubled")
    let doubledCaller = harness.addFunction("doubledCaller", parameters: [doubledParameter])
    harness.addEntry(doubledCaller)
    harness.builder.buildRetain(doubledParameter)
    let doubledReference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    harness.builder.buildCall(callee: doubledReference, arguments: [doubledParameter])
    harness.builder.buildReturn(nil)

    let failures = ownershipFailures(harness.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("reference value 'empty'")
                && $0.message.contains("is passed as an owned argument to 'take'")
                && $0.message.contains("retain/release balance 0, expected 1")
        },
        "expected the duplicated-token path to be rejected, got: \(describeFailures(failures))"
    )
    #expect(
        failures.contains {
            $0.message.contains("reference value 'doubled'")
                && $0.message.contains("is passed as an owned argument to 'take'")
                && $0.message.contains("retain/release balance 2, expected 1")
        },
        "expected the over-retained argument to be rejected, got: \(describeFailures(failures))"
    )
}

@Test
func castAliasConsumedAtOneIsAcceptedAndASecondReleaseIsRejected() {
    let accepted = castAliasFailures(releases: 1) { harness, value, target in
        harness.builder.buildUpcast(value: value, to: target).result
    }
    #expect(
        accepted.isEmpty,
        "an upcast alias carries the moved token and is released once, got: \(describeFailures(accepted))"
    )

    let doubled = castAliasFailures(releases: 2) { harness, value, target in
        harness.builder.buildUpcast(value: value, to: target).result
    }
    #expect(
        doubled.contains {
            $0.message.contains("is consumed by release with no owned instance left")
        },
        "expected the second release of the upcast alias to be rejected, got: \(describeFailures(doubled))"
    )
}

@Test
func uncheckedRefCastAndBitCastAlsoMoveTheReferenceToken() {
    let unchecked = castAliasFailures(releases: 1) { harness, value, target in
        harness.builder.buildUncheckedRefCast(value: value, to: target).result
    }
    #expect(
        unchecked.isEmpty,
        "an unchecked ref cast alias moves the token, got: \(describeFailures(unchecked))"
    )

    let bitCast = castAliasFailures(releases: 1) { harness, value, target in
        harness.builder.buildBitCast(value: value, to: target).result
    }
    #expect(
        bitCast.isEmpty,
        "a bit cast alias moves the token, got: \(describeFailures(bitCast))"
    )
}

@Test
func copyProducesANewOwnedReferenceWhileTheOperandKeepsItsToken() {
    let harness = OwnershipVerifierHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let copy = harness.builder.buildCopy(parameter)
    let slot = harness.builder.buildAllocStack(allocatedType: harness.classType)
    harness.builder.buildStore(value: copy.result, to: slot.result)
    let loaded = harness.builder.buildLoad(ptr: slot.result)
    harness.builder.buildDestroy(loaded.result)
    harness.builder.buildDeallocStack(slot.result)
    harness.builder.buildRelease(parameter)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "the copy result enters at +1, is stored, discharged and the operand keeps its token, got: \(describeFailures(failures))"
    )
}

@Test
func castOfAGuaranteedReferenceDoesNotFabricateAToken() {
    let harness = OwnershipVerifierHarness()
    let targetClass = harness.registry.classType(name: "$s8_base").id
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter], parameterOwnership: [.Guaranteed])
    harness.addEntry(function)
    _ = harness.builder.buildUpcast(value: parameter, to: targetClass)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "a cast of a guaranteed reference moves no token and creates none, got: \(describeFailures(failures))"
    )
}

@Test
func phiOwnedOnEachPredecessorIsAccepted() {
    let harness = OwnershipVerifierHarness()
    let condition = TIR.Parameter(ty: harness.i1, name: "cond")
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(
        parameters: [condition, parameter], parameterOwnership: [.Guaranteed, .Guaranteed]
    )
    let entry = harness.addEntry(function)
    let left = function.addBasicBlock(name: "left")
    let right = function.addBasicBlock(name: "right")
    let join = function.addBasicBlock(name: "join")
    harness.builder.insertPoint = entry
    harness.builder.buildConditionalBranch(
        condition: condition, trueBranch: left, falseBranch: right
    )
    harness.builder.insertPoint = left
    harness.builder.buildRetain(parameter)
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = right
    harness.builder.buildRetain(parameter)
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = join
    let phi = harness.builder.buildPhi(incomings: [
        TIR.Phi.Incoming(value: parameter, block: left),
        TIR.Phi.Incoming(value: parameter, block: right),
    ])
    harness.builder.buildRelease(phi.result)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "each predecessor transfers its own token into the phi, got: \(describeFailures(failures))"
    )
}

@Test
func phiWithAnIncomingThatTransfersNoTokenIsRejected() {
    let harness = OwnershipVerifierHarness()
    let condition = TIR.Parameter(ty: harness.i1, name: "cond")
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(
        parameters: [condition, parameter], parameterOwnership: [.Guaranteed, .Guaranteed]
    )
    let entry = harness.addEntry(function)
    let left = function.addBasicBlock(name: "left")
    let right = function.addBasicBlock(name: "right")
    let join = function.addBasicBlock(name: "join")
    harness.builder.insertPoint = entry
    harness.builder.buildConditionalBranch(
        condition: condition, trueBranch: left, falseBranch: right
    )
    harness.builder.insertPoint = left
    harness.builder.buildRetain(parameter)
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = right
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = join
    let phi = harness.builder.buildPhi(incomings: [
        TIR.Phi.Incoming(value: parameter, block: left),
        TIR.Phi.Incoming(value: parameter, block: right),
    ])
    harness.builder.buildRelease(phi.result)
    harness.builder.buildReturn(nil)

    let failures = ownershipFailures(harness.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("reference value 'c'")
                && $0.message.contains("retain/release balance unknown at the return, expected 0")
        },
        "the predecessor without a token must unbalance the phi, got: \(describeFailures(failures))"
    )
}

@Test
func switchCaseArgumentsCarryTheirOwnOwnershipBalance() {
    let accepted = OwnershipVerifierHarness()
    let acceptedParameter = TIR.Parameter(ty: accepted.classType, name: "c")
    let acceptedSubject = TIR.Parameter(ty: accepted.enumType, name: "e")
    let acceptedFunction = accepted.addFunction(
        parameters: [acceptedParameter, acceptedSubject], parameterOwnership: [.Guaranteed, .Guaranteed]
    )
    let acceptedEntry = accepted.addEntry(acceptedFunction)
    let acceptedFirst = acceptedFunction.addBasicBlock(
        name: "first", parameters: [(name: "arg", ty: accepted.classType)]
    )
    let acceptedSecond = acceptedFunction.addBasicBlock(
        name: "second", parameters: [(name: "arg", ty: accepted.classType)]
    )
    accepted.builder.insertPoint = acceptedEntry
    accepted.builder.buildRetain(acceptedParameter)
    accepted.builder.buildSwitchEnum(
        value: acceptedSubject,
        cases: [
            TIR.SwitchEnum.Case(tag: 0, block: acceptedFirst, arguments: [acceptedParameter]),
            TIR.SwitchEnum.Case(tag: 1, block: acceptedSecond, arguments: [acceptedParameter]),
        ]
    )
    accepted.builder.insertPoint = acceptedFirst
    accepted.builder.buildDestroy(acceptedFirst.parameters[0])
    accepted.builder.buildReturn(nil)
    accepted.builder.insertPoint = acceptedSecond
    accepted.builder.buildDestroy(acceptedSecond.parameters[0])
    accepted.builder.buildReturn(nil)

    let acceptedFailures = accepted.verify(.Strict)
    #expect(
        acceptedFailures.isEmpty,
        "each switch case transfers one token, got: \(describeFailures(acceptedFailures))"
    )

    let rejected = OwnershipVerifierHarness()
    let rejectedParameter = TIR.Parameter(ty: rejected.classType, name: "c")
    let rejectedOther = TIR.Parameter(ty: rejected.classType, name: "other")
    let rejectedSubject = TIR.Parameter(ty: rejected.enumType, name: "e")
    let rejectedFunction = rejected.addFunction(
        parameters: [rejectedParameter, rejectedOther, rejectedSubject],
        parameterOwnership: [.Guaranteed, .Guaranteed, .Guaranteed]
    )
    let rejectedEntry = rejected.addEntry(rejectedFunction)
    let rejectedFirst = rejectedFunction.addBasicBlock(
        name: "first", parameters: [(name: "arg", ty: rejected.classType)]
    )
    let rejectedSecond = rejectedFunction.addBasicBlock(
        name: "second", parameters: [(name: "arg", ty: rejected.classType)]
    )
    rejected.builder.insertPoint = rejectedEntry
    rejected.builder.buildRetain(rejectedParameter)
    rejected.builder.buildSwitchEnum(
        value: rejectedSubject,
        cases: [
            TIR.SwitchEnum.Case(tag: 0, block: rejectedFirst, arguments: [rejectedParameter]),
            TIR.SwitchEnum.Case(tag: 1, block: rejectedSecond, arguments: [rejectedOther]),
        ]
    )
    rejected.builder.insertPoint = rejectedFirst
    rejected.builder.buildDestroy(rejectedFirst.parameters[0])
    rejected.builder.buildReturn(nil)
    rejected.builder.insertPoint = rejectedSecond
    rejected.builder.buildDestroy(rejectedSecond.parameters[0])
    rejected.builder.buildReturn(nil)

    let rejectedFailures = ownershipFailures(rejected.verify(.Strict))
    #expect(
        rejectedFailures.contains {
            $0.message.contains("reference value 'other'")
                && $0.message.contains("retain/release balance -1 at the return, expected 0")
        },
        "the case that passes a value without a token must be rejected, got: \(describeFailures(rejectedFailures))"
    )
    #expect(
        !rejectedFailures.contains { $0.message.contains("block 'first'") },
        "the case that transfers its retained token must stay clean, got: \(describeFailures(rejectedFailures))"
    )
}

@Test
func loopCarriedPhiReachesAFixpoint() {
    let harness = OwnershipVerifierHarness()
    let condition = TIR.Parameter(ty: harness.i1, name: "cond")
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let borrowed = TIR.Parameter(ty: harness.classType, name: "borrowed")
    let function = harness.addFunction(
        parameters: [condition, parameter, borrowed],
        parameterOwnership: [.Guaranteed, .Owned, .Guaranteed]
    )
    let entry = harness.addEntry(function)
    let header = function.addBasicBlock(name: "header")
    let body = function.addBasicBlock(name: "body")
    let exit = function.addBasicBlock(name: "exit")
    harness.builder.insertPoint = entry
    harness.builder.buildBranch(to: header)
    harness.builder.insertPoint = header
    let phi = harness.builder.buildPhi(incomings: [
        TIR.Phi.Incoming(value: parameter, block: entry),
        TIR.Phi.Incoming(value: borrowed, block: body),
    ])
    harness.builder.buildConditionalBranch(
        condition: condition, trueBranch: body, falseBranch: exit
    )
    harness.builder.insertPoint = body
    harness.builder.buildRetain(borrowed)
    harness.builder.buildBranch(to: header)
    harness.builder.insertPoint = exit
    harness.builder.buildRelease(phi.result)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "the loop-carried phi must converge to one token per edge, got: \(describeFailures(failures))"
    )
}

@Test
func nonAdjacentDischargeOfAFieldLoadIsAccepted() {
    let harness = OwnershipVerifierHarness()
    let holder = harness.registry.classType(name: "Holder")
    holder.fields = [(name: "child", type: harness.classType)]
    let holderPointer = harness.registry.pointerType(pointee: holder.id).id
    let selfParameter = TIR.Parameter(ty: holderPointer, name: "self")
    let function = harness.addFunction(parameters: [selfParameter], parameterOwnership: [.Owned])
    harness.addEntry(function)
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    let loaded = harness.builder.buildLoad(ptr: field.result)
    let scratch = harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildDeallocStack(scratch.result)
    harness.builder.buildRelease(loaded.result)
    harness.builder.buildRelease(selfParameter)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "a field load discharged later on every path is a take, got: \(describeFailures(failures))"
    )
}

@Test
func fieldLoadDischargedOnOnlyOnePathIsABorrowAndItsReleaseIsRejected() {
    let harness = OwnershipVerifierHarness()
    let holder = harness.registry.classType(name: "Holder")
    holder.fields = [(name: "child", type: harness.classType)]
    let holderPointer = harness.registry.pointerType(pointee: holder.id).id
    let condition = TIR.Parameter(ty: harness.i1, name: "cond")
    let selfParameter = TIR.Parameter(ty: holderPointer, name: "self")
    let function = harness.addFunction(
        parameters: [condition, selfParameter], parameterOwnership: [.Guaranteed, .Owned]
    )
    let entry = harness.addEntry(function)
    let discharging = function.addBasicBlock(name: "discharging")
    let skipping = function.addBasicBlock(name: "skipping")
    let join = function.addBasicBlock(name: "join")
    harness.builder.insertPoint = entry
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    let loaded = harness.builder.buildLoad(ptr: field.result)
    harness.builder.buildConditionalBranch(
        condition: condition, trueBranch: discharging, falseBranch: skipping
    )
    harness.builder.insertPoint = discharging
    harness.builder.buildRelease(loaded.result)
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = skipping
    harness.builder.buildBranch(to: join)
    harness.builder.insertPoint = join
    harness.builder.buildRelease(selfParameter)
    harness.builder.buildReturn(nil)

    let failures = ownershipFailures(harness.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("reference value '\(loaded.result.name)'")
                && $0.message.contains("is consumed by release with no owned instance left")
        },
        "the partially discharged load is a borrow, so its release must be rejected, got: \(describeFailures(failures))"
    )
}
