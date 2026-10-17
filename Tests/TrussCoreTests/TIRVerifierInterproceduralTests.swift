import SwiftBetterDiagnostic
import Testing
import TrussCore

private struct InterproceduralHarness {
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

    func pointer(to type: Id.TIRTypeId) -> Id.TIRTypeId {
        registry.pointerType(pointee: type).id
    }

    func classType(_ name: String) -> TIRType.ClassType {
        registry.classType(name: name)
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

    @discardableResult
    func addClass(
        _ name: String, fields: [(name: String, type: Id.TIRTypeId)] = [],
        realDeinitializer: Bool = true, superclass: TIR.MetadataRecord? = nil
    ) -> (type: TIRType.ClassType, metadata: TIR.MetadataRecord, deinitializer: TIR.Function) {
        let classType = registry.classType(name: name)
        classType.fields = fields
        let metadata = registry.addMetadata(name: classType.displayText, typeId: classType.id)
        metadata.superclass = superclass?.id
        metadata.hasRealDeinitializer = realDeinitializer
        let deinitializer = module.addFunction(
            name: "\(name).deinit",
            parameters: [TIR.Parameter(ty: pointer(to: classType.id), name: "self")],
            returnType: registry.voidType().id, isVariadic: false, isExtern: false,
            callingConvention: nil, parameterOwnership: [.Guaranteed]
        )
        let entry = deinitializer.addBasicBlock(name: "entry")
        let signature = registry.functionType(
            parameters: [], returnType: registry.voidType().id, isVariadic: false
        ).id
        metadata.vtable = [
            TIR.VTableEntry(name: "deinit", signature: signature, function: deinitializer.id),
        ]
        builder.insertPoint = entry
        return (classType, metadata, deinitializer)
    }

    func verify(_ mode: TIR.Verifier.OwnershipMode) -> [TIR.Verifier.Failure] {
        TIR.Verifier(context: context, ownershipMode: mode).verify(module)
    }
}

private func interproceduralFailures(
    _ failures: [TIR.Verifier.Failure]
) -> [TIR.Verifier.Failure] {
    failures.filter { $0.kind == .Ownership }
}

private func describeInterproceduralFailures(_ failures: [TIR.Verifier.Failure]) -> String {
    failures.map { "[\($0.kind.label)] \($0.message)" }.joined(separator: " | ")
}

@Test
func deinitializerMissingANestedStructLeafIsRejected() {
    let harness = InterproceduralHarness()
    let node = harness.classType("Node")
    let holder = harness.registry.structType(name: "Holder")
    holder.fields = [(name: "child", type: node.id)]
    let owner = harness.addClass("Owner", fields: [(name: "holder", type: holder.id)])
    harness.builder.insertPoint = owner.deinitializer.basicBlocks[0]
    harness.builder.buildClassElementAddr(base: owner.deinitializer.parameters[0], index: 0)
    harness.builder.buildReturn(nil)

    let failures = interproceduralFailures(harness.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("does not discharge reference field #0.0 of 'Owner'")
        },
        "a reference leaf nested in a struct field must be discharged, got: \(describeInterproceduralFailures(failures))"
    )
}

@Test
func deinitializerDischargingNestedStructAndTupleLeavesIsAccepted() {
    let harness = InterproceduralHarness()
    let node = harness.classType("Node")
    let holder = harness.registry.structType(name: "Holder")
    holder.fields = [(name: "child", type: node.id)]
    let pair = harness.registry.tupleType(elements: [
        TIRType.TupleType.Element(label: nil, type: node.id),
        TIRType.TupleType.Element(label: nil, type: node.id),
    ])
    let owner = harness.addClass(
        "Owner", fields: [(name: "holder", type: holder.id), (name: "pair", type: pair.id)]
    )
    harness.builder.insertPoint = owner.deinitializer.basicBlocks[0]
    let holderField = harness.builder.buildClassElementAddr(
        base: owner.deinitializer.parameters[0], index: 0
    )
    let nested = harness.builder.buildStructElementAddr(base: holderField.result, index: 0)
    let nestedLoad = harness.builder.buildLoad(ptr: nested.result)
    harness.builder.buildDestroy(nestedLoad.result)
    let pairField = harness.builder.buildClassElementAddr(
        base: owner.deinitializer.parameters[0], index: 1
    )
    let first = harness.builder.buildTupleElementAddr(base: pairField.result, index: 0)
    let firstLoad = harness.builder.buildLoad(ptr: first.result)
    harness.builder.buildDestroy(firstLoad.result)
    let second = harness.builder.buildTupleElementAddr(base: pairField.result, index: 1)
    let secondLoad = harness.builder.buildLoad(ptr: second.result)
    harness.builder.buildDestroy(secondLoad.result)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "every nested reference leaf is discharged, got: \(describeInterproceduralFailures(failures))"
    )
}

@Test
func deinitializerDischargeResolvesMetadataByTypeIdNotDisplayName() {
    let harness = InterproceduralHarness()
    let node = harness.classType("Node")
    let owner = harness.registry.classType(name: "Owner")
    owner.fields = [(name: "child", type: node.id)]
    let metadata = harness.registry.addMetadata(name: "RenamedOwner", typeId: owner.id)
    metadata.hasRealDeinitializer = true
    let deinitializer = harness.addFunction(
        "Owner.deinit", parameters: [TIR.Parameter(ty: harness.pointer(to: owner.id), name: "self")],
        parameterOwnership: [.Guaranteed]
    )
    let entry = deinitializer.addBasicBlock(name: "entry")
    let signature = harness.registry.functionType(
        parameters: [], returnType: harness.registry.voidType().id, isVariadic: false
    ).id
    metadata.vtable = [
        TIR.VTableEntry(name: "deinit", signature: signature, function: deinitializer.id),
    ]
    harness.builder.insertPoint = entry
    harness.builder.buildReturn(nil)

    let failures = interproceduralFailures(harness.verify(.Strict))
    #expect(
        failures.contains { $0.message.contains("does not discharge reference field #0 of 'Owner'") },
        "the metadata must be found through its type id, got: \(describeInterproceduralFailures(failures))"
    )
}

@Test
func subclassDeinitializerOnlyDischargesItsOwnFields() {
    let harness = InterproceduralHarness()
    let node = harness.classType("Node")
    let base = harness.addClass("Base", fields: [(name: "baseChild", type: node.id)])
    harness.builder.insertPoint = base.deinitializer.basicBlocks[0]
    let baseField = harness.builder.buildClassElementAddr(
        base: base.deinitializer.parameters[0], index: 0
    )
    let baseLoad = harness.builder.buildLoad(ptr: baseField.result)
    harness.builder.buildDestroy(baseLoad.result)
    harness.builder.buildReturn(nil)

    let sub = harness.addClass(
        "Sub",
        fields: [(name: "baseChild", type: node.id), (name: "subChild", type: node.id)],
        superclass: base.metadata
    )
    harness.builder.insertPoint = sub.deinitializer.basicBlocks[0]
    let subField = harness.builder.buildClassElementAddr(
        base: sub.deinitializer.parameters[0], index: 1
    )
    let subLoad = harness.builder.buildLoad(ptr: subField.result)
    harness.builder.buildDestroy(subLoad.result)
    harness.builder.buildReturn(nil)

    let failures = harness.verify(.Strict)
    #expect(
        failures.isEmpty,
        "the inherited field belongs to the superclass deinitializer, got: \(describeInterproceduralFailures(failures))"
    )

    let missing = InterproceduralHarness()
    let missingNode = missing.classType("Node")
    let missingBase = missing.addClass("Base", fields: [(name: "baseChild", type: missingNode.id)])
    missing.builder.insertPoint = missingBase.deinitializer.basicBlocks[0]
    let missingBaseField = missing.builder.buildClassElementAddr(
        base: missingBase.deinitializer.parameters[0], index: 0
    )
    let missingBaseLoad = missing.builder.buildLoad(ptr: missingBaseField.result)
    missing.builder.buildDestroy(missingBaseLoad.result)
    missing.builder.buildReturn(nil)
    let missingSub = missing.addClass(
        "Sub",
        fields: [(name: "baseChild", type: missingNode.id), (name: "subChild", type: missingNode.id)],
        superclass: missingBase.metadata
    )
    missing.builder.insertPoint = missingSub.deinitializer.basicBlocks[0]
    missing.builder.buildReturn(nil)

    let missingFailures = interproceduralFailures(missing.verify(.Strict))
    #expect(
        missingFailures.contains { $0.message.contains("does not discharge reference field #1 of 'Sub'") },
        "the subclass must discharge its own field, got: \(describeInterproceduralFailures(missingFailures))"
    )
    #expect(
        !missingFailures.contains { $0.message.contains("reference field #0 of 'Sub'") },
        "the inherited field is not the subclass deinitializer's duty, got: \(describeInterproceduralFailures(missingFailures))"
    )
}

@Test
func releaseOfAClassWithARealDeinitializerIsRejected() {
    let rejected = InterproceduralHarness()
    let owned = rejected.addClass("Owner", realDeinitializer: true)
    rejected.builder.buildReturn(nil)
    let parameter = TIR.Parameter(ty: owned.type.id, name: "o")
    let function = rejected.addFunction(parameters: [parameter], parameterOwnership: [.Owned])
    rejected.addEntry(function)
    rejected.builder.buildRelease(parameter)
    rejected.builder.buildReturn(nil)

    let failures = interproceduralFailures(rejected.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("reference value 'o'")
                && $0.message.contains("is released but 'Owner' has a real deinitializer, destroy is required")
        },
        "a real teardown cannot be released, got: \(describeInterproceduralFailures(failures))"
    )

    let accepted = InterproceduralHarness()
    let destroyed = accepted.addClass("Owner", realDeinitializer: true)
    accepted.builder.buildReturn(nil)
    let destroyedParameter = TIR.Parameter(ty: destroyed.type.id, name: "o")
    let destroyedFunction = accepted.addFunction(
        parameters: [destroyedParameter], parameterOwnership: [.Owned]
    )
    accepted.addEntry(destroyedFunction)
    accepted.builder.buildDestroy(destroyedParameter)
    accepted.builder.buildReturn(nil)

    let acceptedFailures = accepted.verify(.Strict)
    #expect(
        acceptedFailures.isEmpty,
        "destroy is the teardown of a class with a real deinitializer, got: \(describeInterproceduralFailures(acceptedFailures))"
    )
}

@Test
func destroyOfAClassWithASharedNoOpDeinitializerIsRejected() {
    let rejected = InterproceduralHarness()
    let plain = rejected.addClass("Plain", realDeinitializer: false)
    rejected.builder.buildReturn(nil)
    let parameter = TIR.Parameter(ty: plain.type.id, name: "p")
    let function = rejected.addFunction(parameters: [parameter], parameterOwnership: [.Owned])
    rejected.addEntry(function)
    rejected.builder.buildDestroy(parameter)
    rejected.builder.buildReturn(nil)

    let failures = interproceduralFailures(rejected.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("reference value 'p'")
                && $0.message.contains("is destroyed but 'Plain' has no real deinitializer, release is required")
        },
        "a shared no-op teardown must be released, got: \(describeInterproceduralFailures(failures))"
    )

    let accepted = InterproceduralHarness()
    let released = accepted.addClass("Plain", realDeinitializer: false)
    accepted.builder.buildReturn(nil)
    let releasedParameter = TIR.Parameter(ty: released.type.id, name: "p")
    let releasedFunction = accepted.addFunction(
        parameters: [releasedParameter], parameterOwnership: [.Owned]
    )
    accepted.addEntry(releasedFunction)
    accepted.builder.buildRelease(releasedParameter)
    accepted.builder.buildReturn(nil)

    let acceptedFailures = accepted.verify(.Strict)
    #expect(
        acceptedFailures.isEmpty,
        "release is the teardown of a plain class, got: \(describeInterproceduralFailures(acceptedFailures))"
    )
}

@Test
func classWithReferenceFieldsRequiresDestroyEvenWithoutARealDeinitializer() {
    let harness = InterproceduralHarness()
    let node = harness.classType("Node")
    let holder = harness.addClass(
        "Holder", fields: [(name: "child", type: node.id)], realDeinitializer: false
    )
    harness.builder.buildReturn(nil)
    let parameter = TIR.Parameter(ty: holder.type.id, name: "h")
    let function = harness.addFunction(parameters: [parameter], parameterOwnership: [.Owned])
    harness.addEntry(function)
    harness.builder.buildRelease(parameter)
    harness.builder.buildReturn(nil)

    let failures = interproceduralFailures(harness.verify(.Strict))
    #expect(
        failures.contains {
            $0.message.contains("reference value 'h'")
                && $0.message.contains("is released but 'Holder' has a real deinitializer, destroy is required")
        },
        "a class that still owns reference fields is torn down by destroy, got: \(describeInterproceduralFailures(failures))"
    )
}
