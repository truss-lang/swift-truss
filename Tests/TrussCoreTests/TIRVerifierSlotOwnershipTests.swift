import SwiftBetterDiagnostic
import Testing
import TrussCore

private struct SlotOwnershipHarness {
    let context = Context()
    let registry = TIR.Registry()
    let module: TIR.Module
    let builder: TIR.Builder

    init() {
        module = TIR.Module(registry: registry)
        builder = TIR.Builder(registry: registry)
    }

    var i32: Id.TIRTypeId {
        registry.integerType(isSigned: true, bitWidth: 32).id
    }

    var classType: Id.TIRTypeId {
        registry.classType(name: "$s12_reference").id
    }

    var containerClass: Id.TIRTypeId {
        let ty = registry.classType(name: "$s12_container")
        if ty.fields.isEmpty {
            ty.fields = [(name: "ref", type: classType)]
        }
        return ty.id
    }

    var containerPointer: Id.TIRTypeId {
        registry.pointerType(pointee: containerClass).id
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
    func addGlobal(_ name: String, type: Id.TIRTypeId) -> TIR.GlobalVariable {
        module.addGlobal(name: name, type: type, isExtern: false, hasInitializer: false)
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
}

private func slotFailures(_ failures: [TIR.Verifier.Failure]) -> [TIR.Verifier.Failure] {
    failures.filter { $0.kind == .Ownership }
}

private func describeSlotFailures(_ failures: [TIR.Verifier.Failure]) -> String {
    failures.map { "[\($0.kind.label)] \($0.message)" }.joined(separator: " | ")
}

@Test
func storedSlotTeardownShapeIsAcceptedInStrictMode() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let slot = harness.builder.buildAllocStack(allocatedType: harness.classType)
    harness.builder.buildStore(value: parameter, to: slot.result)
    let loaded = harness.builder.buildLoad(ptr: slot.result)
    harness.builder.buildDestroy(loaded.result)
    harness.builder.buildDeallocStack(slot.result)
    harness.builder.buildReturn(nil)

    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeSlotFailures(strict))")
}

@Test
func bookkeepingTripleIsRejectedInStrictMode() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let slot = harness.builder.buildAllocStack(allocatedType: harness.classType)
    harness.builder.buildRetain(parameter)
    harness.builder.buildStore(value: parameter, to: slot.result)
    harness.builder.buildDestroy(parameter)
    harness.builder.buildDeallocStack(slot.result)
    harness.builder.buildReturn(nil)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("reference value 'c'")
                && $0.message.contains("is destroyed while slot '")
                && $0.message.contains("still holds a reference to it")
        },
        "expected the net-zero triple to be rejected, got: \(describeSlotFailures(strict))"
    )
    #expect(
        strict.contains {
            $0.message.contains("still holds a reference that is not discharged before this deallocstack")
        },
        "expected the undeclared slot token to be rejected at the deallocstack, got: \(describeSlotFailures(strict))"
    )
}

@Test
func overwritingATokenHoldingSlotIsRejected() {
    let harness = SlotOwnershipHarness()
    let first = TIR.Parameter(ty: harness.classType, name: "first")
    let second = TIR.Parameter(ty: harness.classType, name: "second")
    let function = harness.addFunction(parameters: [first, second])
    harness.addEntry(function)
    let slot = harness.builder.buildAllocStack(allocatedType: harness.classType)
    harness.builder.buildStore(value: first, to: slot.result)
    harness.builder.buildStore(value: second, to: slot.result)
    harness.builder.buildDeallocStack(slot.result)
    harness.builder.buildReturn(nil)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("store of 'second' into slot '")
                && $0.message.contains("overwrites a reference held by the slot that is not discharged first")
        },
        "expected the overwrite to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func releaseOfALoadFromATokenlessSlotIsRejected() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter], parameterOwnership: [.Guaranteed])
    harness.addEntry(function)
    let slot = harness.builder.buildAllocStack(allocatedType: harness.classType)
    let loaded = harness.builder.buildLoad(ptr: slot.result)
    harness.builder.buildRelease(loaded.result)
    harness.builder.buildDeallocStack(slot.result)
    harness.builder.buildReturn(nil)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("reference value '\(loaded.result.name)'")
                && $0.message.contains("retain/release balance -1 at the return, expected 0")
        },
        "expected the tokenless load discharge to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func advisoryStaysSilentWhereStrictReportsSlotProblems() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let slot = harness.builder.buildAllocStack(allocatedType: harness.classType)
    harness.builder.buildStore(value: parameter, to: slot.result)
    harness.builder.buildReturn(nil)

    let advisory = harness.verify(.Advisory)
    #expect(advisory.isEmpty, "advisory mode must stay silent, got: \(describeSlotFailures(advisory))")
    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains { $0.message.contains("is not deallocated on every path to this return") },
        "expected strict to report the missing deallocstack, got: \(describeSlotFailures(strict))"
    )
}

@Test
func classFieldStoreWithDischargeIsAcceptedInTheStoringFunction() {
    let harness = SlotOwnershipHarness()
    let selfParameter = TIR.Parameter(ty: harness.containerPointer, name: "self")
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(
        parameters: [selfParameter, parameter], returnType: harness.containerPointer
    )
    harness.addEntry(function)
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    harness.builder.buildRetain(parameter)
    let old = harness.builder.buildLoad(ptr: field.result)
    harness.builder.buildRelease(old.result)
    harness.builder.buildStore(value: parameter, to: field.result)
    harness.builder.buildRelease(parameter)
    harness.builder.buildReturn(selfParameter)

    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeSlotFailures(strict))")
}

@Test
func classFieldStoreWithoutDischargeIsRejectedInTheStoringFunction() {
    let harness = SlotOwnershipHarness()
    let selfParameter = TIR.Parameter(ty: harness.containerPointer, name: "self")
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(
        parameters: [selfParameter, parameter], returnType: harness.containerPointer
    )
    harness.addEntry(function)
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    harness.builder.buildRetain(parameter)
    harness.builder.buildStore(value: parameter, to: field.result)
    harness.builder.buildRelease(parameter)
    harness.builder.buildReturn(selfParameter)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("store of 'c' into slot '0'")
                && $0.message.contains("overwrites a reference held by the slot that is not discharged first")
        },
        "expected the field store without a discharge to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func deinitializerLoadAndDischargeIsChecked() {
    let harness = SlotOwnershipHarness()
    let selfParameter = TIR.Parameter(ty: harness.containerPointer, name: "self")
    let function = harness.addFunction(parameters: [selfParameter])
    harness.addEntry(function)
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    let loaded = harness.builder.buildLoad(ptr: field.result)
    harness.builder.buildRelease(loaded.result)
    harness.builder.buildRelease(selfParameter)
    harness.builder.buildReturn(nil)

    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeSlotFailures(strict))")
}

@Test
func fieldReadTransferredAsOwnedResultWithoutRetainIsRejected() {
    let harness = SlotOwnershipHarness()
    let selfParameter = TIR.Parameter(ty: harness.containerPointer, name: "self")
    let function = harness.addFunction(
        parameters: [selfParameter], returnType: harness.classType, resultOwnership: .Owned
    )
    harness.addEntry(function)
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    let loaded = harness.builder.buildLoad(ptr: field.result)
    harness.builder.buildRelease(selfParameter)
    harness.builder.buildReturn(loaded.result)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("reference value '\(loaded.result.name)'")
                && $0.message.contains("transferred as an owned result with retain/release balance 0, expected 1")
        },
        "expected the borrowed field read to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func fieldReadIsNotADischargeOfTheSlot() {
    let harness = SlotOwnershipHarness()
    let selfParameter = TIR.Parameter(ty: harness.containerPointer, name: "self")
    let function = harness.addFunction(
        parameters: [selfParameter], returnType: harness.classType, resultOwnership: .Owned
    )
    harness.addEntry(function)
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    let loaded = harness.builder.buildLoad(ptr: field.result)
    harness.builder.buildRetain(loaded.result)
    harness.builder.buildRelease(selfParameter)
    harness.builder.buildReturn(loaded.result)

    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeSlotFailures(strict))")
}

@Test
func balancedSlotFreeFunctionPassesInBothModes() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    harness.builder.buildRelease(parameter)
    let allocation = harness.builder.buildAllocStack(allocatedType: harness.i32)
    harness.builder.buildDeallocStack(allocation.result)
    harness.builder.buildReturn(nil)

    let advisory = harness.verify(.Advisory)
    #expect(advisory.isEmpty, "expected no failures, got: \(describeSlotFailures(advisory))")
    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeSlotFailures(strict))")
}

@Test
func globalStoreWithDischargeTransfersOwnershipOutOfTheStoringFunction() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let global = harness.addGlobal("g", type: harness.classType)
    let address = harness.builder.buildGlobalAddr(global: global)
    let old = harness.builder.buildLoad(ptr: address)
    harness.builder.buildRelease(old.result)
    harness.builder.buildStore(value: parameter, to: address)
    harness.builder.buildReturn(nil)

    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeSlotFailures(strict))")
}

@Test
func globalStoreWithoutDischargeIsRejectedInTheStoringFunction() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let global = harness.addGlobal("g", type: harness.classType)
    harness.builder.buildStore(value: parameter, to: harness.builder.buildGlobalAddr(global: global))
    harness.builder.buildReturn(nil)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("store of 'c' into slot 'g'")
                && $0.message.contains("overwrites a reference held by the slot that is not discharged first")
        },
        "expected the global store without a discharge to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func overwritingATokenHoldingGlobalIsRejected() {
    let harness = SlotOwnershipHarness()
    let first = TIR.Parameter(ty: harness.classType, name: "first")
    let second = TIR.Parameter(ty: harness.classType, name: "second")
    let function = harness.addFunction(parameters: [first, second])
    harness.addEntry(function)
    let global = harness.addGlobal("g", type: harness.classType)
    let address = harness.builder.buildGlobalAddr(global: global)
    harness.builder.buildStore(value: first, to: address)
    harness.builder.buildStore(value: second, to: address)
    harness.builder.buildReturn(nil)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("store of 'second' into slot 'g'")
                && $0.message.contains("overwrites a reference held by the slot that is not discharged first")
        },
        "expected the global overwrite to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func loadFromATokenHoldingGlobalBalances() {
    let harness = SlotOwnershipHarness()
    let parameter = TIR.Parameter(ty: harness.classType, name: "c")
    let function = harness.addFunction(parameters: [parameter])
    harness.addEntry(function)
    let global = harness.addGlobal("g", type: harness.classType)
    let address = harness.builder.buildGlobalAddr(global: global)
    let old = harness.builder.buildLoad(ptr: address)
    harness.builder.buildRelease(old.result)
    harness.builder.buildStore(value: parameter, to: address)
    let loaded = harness.builder.buildLoad(ptr: address)
    harness.builder.buildRetain(loaded.result)
    harness.builder.buildRelease(loaded.result)
    harness.builder.buildReturn(nil)

    let strict = harness.verify(.Strict)
    #expect(strict.isEmpty, "expected no failures, got: \(describeSlotFailures(strict))")
}

@Test
func doubleDischargeOfAGlobalIsRejected() {
    let harness = SlotOwnershipHarness()
    let function = harness.addFunction()
    harness.addEntry(function)
    let global = harness.addGlobal("g", type: harness.classType)
    let address = harness.builder.buildGlobalAddr(global: global)
    let first = harness.builder.buildLoad(ptr: address)
    harness.builder.buildRelease(first.result)
    let second = harness.builder.buildLoad(ptr: address)
    harness.builder.buildRelease(second.result)
    harness.builder.buildReturn(nil)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("reference value '\(second.result.name)'")
                && $0.message.contains("retain/release balance -1 at the return, expected 0")
        },
        "expected the second discharge to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func doubleDischargeOfAClassFieldIsRejected() {
    let harness = SlotOwnershipHarness()
    let selfParameter = TIR.Parameter(ty: harness.containerPointer, name: "self")
    let function = harness.addFunction(
        parameters: [selfParameter], returnType: harness.containerPointer
    )
    harness.addEntry(function)
    let field = harness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    let first = harness.builder.buildLoad(ptr: field.result)
    harness.builder.buildRelease(first.result)
    let second = harness.builder.buildLoad(ptr: field.result)
    harness.builder.buildRelease(second.result)
    harness.builder.buildRelease(selfParameter)
    harness.builder.buildReturn(nil)

    let strict = slotFailures(harness.verify(.Strict))
    #expect(
        strict.contains {
            $0.message.contains("reference value '\(second.result.name)'")
                && $0.message.contains("retain/release balance -1 at the return, expected 0")
        },
        "expected the second field discharge to be reported, got: \(describeSlotFailures(strict))"
    )
}

@Test
func globalAndClassFieldOverwriteMessagesMatch() {
    let globalHarness = SlotOwnershipHarness()
    let globalFirst = TIR.Parameter(ty: globalHarness.classType, name: "first")
    let globalSecond = TIR.Parameter(ty: globalHarness.classType, name: "second")
    let globalFunction = globalHarness.addFunction(parameters: [globalFirst, globalSecond])
    globalHarness.addEntry(globalFunction)
    let global = globalHarness.addGlobal("g", type: globalHarness.classType)
    let address = globalHarness.builder.buildGlobalAddr(global: global)
    let globalOld = globalHarness.builder.buildLoad(ptr: address)
    globalHarness.builder.buildRelease(globalOld.result)
    globalHarness.builder.buildStore(value: globalFirst, to: address)
    globalHarness.builder.buildStore(value: globalSecond, to: address)
    globalHarness.builder.buildReturn(nil)
    let globalMessage = slotFailures(globalHarness.verify(.Strict)).first {
        $0.message.contains("overwrites a reference held by the slot that is not discharged first")
    }?.message

    let fieldHarness = SlotOwnershipHarness()
    let selfParameter = TIR.Parameter(ty: fieldHarness.containerPointer, name: "self")
    let fieldFirst = TIR.Parameter(ty: fieldHarness.classType, name: "first")
    let fieldSecond = TIR.Parameter(ty: fieldHarness.classType, name: "second")
    let fieldFunction = fieldHarness.addFunction(
        parameters: [selfParameter, fieldFirst, fieldSecond], returnType: fieldHarness.containerPointer
    )
    fieldHarness.addEntry(fieldFunction)
    let field = fieldHarness.builder.buildClassElementAddr(base: selfParameter, index: 0)
    let fieldOld = fieldHarness.builder.buildLoad(ptr: field.result)
    fieldHarness.builder.buildRelease(fieldOld.result)
    fieldHarness.builder.buildStore(value: fieldFirst, to: field.result)
    fieldHarness.builder.buildStore(value: fieldSecond, to: field.result)
    fieldHarness.builder.buildRelease(selfParameter)
    fieldHarness.builder.buildReturn(nil)
    let fieldMessage = slotFailures(fieldHarness.verify(.Strict)).first {
        $0.message.contains("overwrites a reference held by the slot that is not discharged first")
    }?.message

    #expect(
        globalMessage != nil && fieldMessage != nil,
        "expected both twins to report an overwrite, got global: \(globalMessage ?? "nil"), field: \(fieldMessage ?? "nil")"
    )
    #expect(
        globalMessage?.contains("store of 'second'") == true
            && fieldMessage?.contains("store of 'second'") == true,
        "expected both twins to name the overwriting value"
    )
    #expect(
        globalMessage?.hasSuffix("overwrites a reference held by the slot that is not discharged first") == true
            && fieldMessage?.hasSuffix("overwrites a reference held by the slot that is not discharged first") == true,
        "expected both twins to share the message tail"
    )
}
