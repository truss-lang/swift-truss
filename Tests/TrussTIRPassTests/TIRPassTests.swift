import SwiftBetterDiagnostic
import Testing
import TrussCore
@testable import TrussTIRPass

private let classSource = """
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    func m() -> Int32 { return self.value }
}

func build() -> Int32 {
    let c = C()
    return c.m()
}
"""

private let assignmentPrelude = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    func m() -> Int32 { return self.value }
}

class D {
    var value: Int32 = 0
    init() { return }
    deinit { return }
    func m() -> Int32 { return self.value }
}
"""

private let twoLocalsSource = assignmentPrelude + """

func twoLocals() -> Int32 {
    let c = C()
    let d = D()
    return Builtin.builtin_add_int32(c.m(), d.m())
}
"""

private let loopSource = assignmentPrelude + """

func looped() -> Int32 {
    var total = 0
    while true {
        let c = C()
        total = Builtin.builtin_add_int32(total, c.m())
        break
    }
    return total
}
"""

private let branchSource = assignmentPrelude + """

func branched() -> Int32 {
    let c = C()
    if true {
        return c.m()
    }
    return 0
}
"""

private let passthroughSource = """
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    func m() -> Int32 { return self.value }
}

func passthrough(_ c: C) -> C {
    return c
}

func unusedSelf() -> Int32 {
    return 1
}

func ignored(_ c: C) -> Int32 {
    return 1
}
"""

private func classTypeId(named name: String, in module: TIR.Module) -> Id.TIRTypeId? {
    module.registry.types.values.compactMap { $0 as? TIRType.ClassType }
        .first { $0.displayText == name }?.id
}

private func slot(of typeId: Id.TIRTypeId, in function: TIR.Function) -> TIR.Value? {
    allocations(ofType: typeId, in: function).first?.result
}

@Test
func classConstructionStoresTheReferenceIntoTheSlotAndDischargesIt() throws {
    let (context, module) = runTIRPass(classSource)
    #expect(strictFailures(context, module).isEmpty)
    let build = try #require(function(named: "build", in: module))
    let typeId = try #require(classTypeId(named: "C", in: module))
    let slotValue = try #require(slot(of: typeId, in: build))
    let stored = try #require(
        allInstructions(of: build).compactMap { $0 as? TIR.Store }.first { $0.ptr === slotValue }
    )
    #expect(storedValueIsRetainedBeforeTheStore(stored, in: build))
    let discharges = dischargedLoads(of: slotValue, in: build)
    #expect(discharges.count == 1)
    #expect(retains(of: slotValue, in: build).isEmpty)
    #expect(consumes(of: slotValue, in: build).isEmpty)
    #expect(deallocations(of: slotValue, in: build).count == 1)
    #expect(!allInstructions(of: module).contains { $0 is TIR.DeallocHeap || $0 is TIR.DeallocCell })
}

private func storedValueIsRetainedBeforeTheStore(_ store: TIR.Store, in function: TIR.Function) -> Bool {
    let instructions = allInstructions(of: function)
    guard let storeIndex = instructions.firstIndex(where: { $0 === store }) else {
        return false
    }
    return instructions[..<storeIndex].reversed().prefix(3).contains { instruction in
        guard let retain = instruction as? TIR.Retain else {
            return false
        }
        return retain.value === store.value || retain.value === store.ptr
    }
}

@Test
func methodReceiverIsBorrowedWhileInitializerSelfIsTransferred() throws {
    let (context, module) = runTIRPass(twoLocalsSource)
    #expect(strictFailures(context, module).isEmpty)
    let method = try #require(function(named: "_1m_", in: module))
    let selfParameter = try #require(method.parameters.first)
    #expect(consumes(of: selfParameter, in: method).isEmpty)
    #expect(retains(of: selfParameter, in: method).isEmpty)
    let twoLocals = try #require(function(named: "twoLocals", in: module))
    let instructions = allInstructions(of: twoLocals)
    #expect(instructions.allSatisfy { !($0 is TIR.Copy) })
    let typeId = try #require(classTypeId(named: "C", in: module))
    let receiver = try #require(slot(of: typeId, in: twoLocals))
    #expect(instructions.contains { ($0 as? TIR.Copy)?.value === receiver } == false)
    let allocation = try #require(
        instructions.compactMap { $0 as? TIR.AllocHeap }.first { $0.allocatedType == typeId }
    )
    #expect(retains(of: allocation.result, in: twoLocals).isEmpty)
    let initCall = try #require(
        instructions.compactMap { $0 as? TIR.Call }.first { $0.arguments.contains { $0 === allocation.result } }
    )
    #expect(initCall.arguments.count == 1)
    let initializer = try #require(module.functions.first { $0.name.contains("_4init_") })
    let initializerSelf = try #require(initializer.parameters.first)
    #expect(consumes(of: initializerSelf, in: initializer).isEmpty)
    #expect(
        initializer.basicBlocks.flatMap(\.instructions).compactMap { $0 as? TIR.Return }.first?
            .value === initializerSelf
    )
}

@Test
func deinitializedClassIsDestroyedAndPlainClassIsReleased() throws {
    let (context, module) = runTIRPass(twoLocalsSource)
    #expect(strictFailures(context, module).isEmpty)
    let twoLocals = try #require(function(named: "twoLocals", in: module))
    let plainType = try #require(classTypeId(named: "C", in: module))
    let deinitializedType = try #require(classTypeId(named: "D", in: module))
    let plain = try #require(slot(of: plainType, in: twoLocals))
    let deinitialized = try #require(slot(of: deinitializedType, in: twoLocals))
    let plainDischarges = dischargedLoads(of: plain, in: twoLocals)
    let deinitializedDischarges = dischargedLoads(of: deinitialized, in: twoLocals)
    #expect(plainDischarges.count == 1)
    #expect(deinitializedDischarges.count == 1)
    let instructions = allInstructions(of: twoLocals)
    #expect(
        instructions.contains {
            guard let release = $0 as? TIR.Release else {
                return false
            }
            return release.value === plainDischarges[0].result
        }
    )
    #expect(
        instructions.contains {
            guard let destroy = $0 as? TIR.Destroy else {
                return false
            }
            return destroy.value === deinitializedDischarges[0].result
        }
    )
}

@Test
func ownedReferenceParameterIsConsumedOrTransferred() throws {
    let (context, module) = runTIRPass(passthroughSource)
    #expect(strictFailures(context, module).isEmpty)
    let passthrough = try #require(function(named: "passthrough", in: module))
    let parameter = try #require(passthrough.parameters.first)
    let stored = allInstructions(of: passthrough).compactMap { $0 as? TIR.Store }
        .first { $0.value === parameter }
    #expect(stored != nil)
    #expect(consumes(of: parameter, in: passthrough).isEmpty)
    let ignored = try #require(function(named: "ignored", in: module))
    let ignoredParameter = try #require(ignored.parameters.first)
    #expect(consumes(of: ignoredParameter, in: ignored).isEmpty)
    #expect(retains(of: ignoredParameter, in: ignored).isEmpty)
    let classType = try #require(classTypeId(named: "C", in: module))
    let ignoredSlot = try #require(slot(of: classType, in: ignored))
    #expect(dischargedLoads(of: ignoredSlot, in: ignored).count == 1)
    let initializer = try #require(module.functions.first { $0.name.contains("_4init_") })
    let selfParameter = try #require(initializer.parameters.first)
    #expect(consumes(of: selfParameter, in: initializer).isEmpty)
    #expect(
        initializer.basicBlocks.flatMap(\.instructions).compactMap { $0 as? TIR.Return }.first?
            .value === selfParameter
    )
    #expect(allInstructions(of: passthrough).allSatisfy { !($0 is TIR.Destroy) })
}

@Test
func ownResultFromATokenHoldingSlotNeedsNoExtraRetain() throws {
    let (context, module) = runTIRPass(passthroughSource)
    let passthrough = try #require(function(named: "passthrough", in: module))
    let instructions = allInstructions(of: passthrough)
    let returned = try #require(instructions.compactMap { $0 as? TIR.Return }.first?.value)
    #expect(retains(of: returned, in: passthrough).isEmpty)
    #expect(consumes(of: returned, in: passthrough).isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func loopLocalCleanupsStayInsideTheLoopBody() throws {
    let (context, module) = runTIRPass(loopSource)
    #expect(strictFailures(context, module).isEmpty)
    let looped = try #require(function(named: "looped", in: module))
    let typeId = try #require(classTypeId(named: "C", in: module))
    let value = try #require(slot(of: typeId, in: looped))
    let allocation = try #require(allocations(ofType: typeId, in: looped).first)
    let allocationBlock = try #require(block(containing: allocation, in: looped))
    let discharge = try #require(dischargedLoads(of: value, in: looped).first)
    let deallocation = try #require(deallocations(of: value, in: looped).first)
    #expect(block(containing: discharge, in: looped) === allocationBlock)
    #expect(block(containing: deallocation, in: looped) === allocationBlock)
    #expect(dischargedLoads(of: value, in: looped).count == 1)
    #expect(consumes(of: value, in: looped).isEmpty)
    #expect(deallocations(of: value, in: looped).count == 1)
}

@Test
func branchCleanupsAreInsertedOnEveryPath() throws {
    let (context, module) = runTIRPass(branchSource)
    #expect(strictFailures(context, module).isEmpty)
    let branched = try #require(function(named: "branched", in: module))
    let typeId = try #require(classTypeId(named: "C", in: module))
    let value = try #require(slot(of: typeId, in: branched))
    let discharging = dischargedLoads(of: value, in: branched)
    #expect(discharging.count == 2)
    #expect(consumes(of: value, in: branched).isEmpty)
    let blocks = Set(
        discharging.compactMap { block(containing: $0, in: branched).map(ObjectIdentifier.init) }
    )
    #expect(blocks.count == 2)
    let deallocations = deallocations(of: value, in: branched)
    #expect(deallocations.count == 2)
    let deallocationBlocks = Set(
        deallocations.compactMap { block(containing: $0, in: branched).map(ObjectIdentifier.init) }
    )
    #expect(deallocationBlocks == blocks)
}

@Test
func everyStackAllocationIsDeallocatedExactlyOnce() throws {
    let (context, module) = runTIRPass(loopSource)
    #expect(strictFailures(context, module).isEmpty)
    for function in module.functions where !function.isExtern {
        for block in function.basicBlocks {
            for case let allocation as TIR.AllocStack in block.instructions {
                let deallocations = deallocations(of: allocation.result, in: function)
                #expect(deallocations.count == 1)
            }
        }
    }
    #expect(!allInstructions(of: module).contains { $0 is TIR.DeallocHeap || $0 is TIR.DeallocCell })
}

private func classWithMetadata(
    _ registry: TIR.Registry, module: TIR.Module, name: String, hasDeinitializer: Bool,
    pointer: Id.TIRTypeId
) -> TIRType.ClassType {
    let classType = registry.classType(name: name)
    let metadata = registry.addMetadata(name: name)
    let signature = registry.functionType(
        parameters: [], returnType: registry.voidType().id, isVariadic: false
    ).id
    let deinitializer: TIR.Function = if hasDeinitializer {
        module.addFunction(
            name: "\(name).deinit", parameters: [TIR.Parameter(ty: pointer, name: "self")],
            returnType: registry.voidType().id, isVariadic: false, isExtern: false,
            callingConvention: nil, parameterOwnership: [.Guaranteed]
        )
    } else {
        module.addFunction(
            name: "$t_noop_deinit", parameters: [TIR.Parameter(ty: pointer, name: "self")],
            returnType: registry.voidType().id, isVariadic: false, isExtern: false,
            callingConvention: nil, parameterOwnership: [.Guaranteed]
        )
    }
    deinitializer.addBasicBlock(name: "entry").instructions.append(TIR.Return())
    metadata.vtable = [TIR.VTableEntry(name: "deinit", signature: signature, function: deinitializer.id)]
    return classType
}

@Test
func structFieldStoreHoldsTheTokenAndTeardownDischargesIt() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let pointerPointer = registry.addressType(pointee: nodePointer.id)
    let holderType = registry.structType(name: "Holder")
    holderType.fields = [(name: "child", type: nodePointer.id)]
    let function = module.addFunction(
        name: "f", parameters: [TIR.Parameter(ty: pointerPointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let slot = builder.buildAllocStack(allocatedType: holderType.id, name: "holder").result
    let field = builder.buildStructElementAddr(base: slot, index: 0, name: "field").result
    let value = builder.buildLoad(ptr: function.parameters[0], name: "v").result
    builder.buildStore(value: value, to: field)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "f" })
    let instructions = allInstructions(of: lowered)
    let store = try #require(instructions.compactMap { $0 as? TIR.Store }.first)
    #expect(store.ptr === field)
    #expect(instructions.contains { ($0 as? TIR.Retain)?.value === store.value })
    let discharges = dischargedLoads(of: field, in: lowered)
    #expect(discharges.count == 1)
    let loaded = try #require(discharges.first).result
    #expect(retains(of: loaded, in: lowered).isEmpty)
    #expect(instructions.contains { ($0 as? TIR.Release)?.value === loaded })
    #expect(retains(of: slot, in: lowered).isEmpty)
    #expect(consumes(of: slot, in: lowered).isEmpty)
    #expect(deallocations(of: slot, in: lowered).count == 1)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func structFieldTeardownOfADeinitializedClassIsDestroyed() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodePointer = registry.pointerType(pointee: registry.classType(name: "Node").id)
    let pointerPointer = registry.addressType(pointee: nodePointer.id)
    _ = classWithMetadata(
        registry, module: module, name: "Node", hasDeinitializer: true, pointer: nodePointer.id
    )
    let holderType = registry.structType(name: "Holder")
    holderType.fields = [(name: "child", type: nodePointer.id)]
    let function = module.addFunction(
        name: "f", parameters: [TIR.Parameter(ty: pointerPointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let slot = builder.buildAllocStack(allocatedType: holderType.id, name: "holder").result
    let field = builder.buildStructElementAddr(base: slot, index: 0, name: "field").result
    let value = builder.buildLoad(ptr: function.parameters[0], name: "v").result
    builder.buildStore(value: value, to: field)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "f" })
    let instructions = allInstructions(of: lowered)
    let discharges = dischargedLoads(of: field, in: lowered)
    #expect(discharges.count == 1)
    let loaded = try #require(discharges.first).result
    #expect(instructions.contains { ($0 as? TIR.Destroy)?.value === loaded })
    #expect(retains(of: loaded, in: lowered).isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func overwritingAnOwningSlotDischargesTheOldValueFirst() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let function = module.addFunction(
        name: "f", parameters: [TIR.Parameter(ty: nodePointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let slot = builder.buildAllocStack(allocatedType: nodeType.id, name: "slot").result
    let first = builder.buildLoad(ptr: function.parameters[0], name: "first").result
    builder.buildStore(value: first, to: slot)
    let second = builder.buildLoad(ptr: function.parameters[0], name: "second").result
    builder.buildStore(value: second, to: slot)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "f" })
    let instructions = allInstructions(of: lowered)
    let stores = instructions.compactMap { $0 as? TIR.Store }
    #expect(stores.count == 2)
    let discharges = dischargedLoads(of: slot, in: lowered)
    #expect(discharges.count == 2)
    let secondStoreIndex = try #require(instructions.firstIndex { $0 === stores[1] })
    let overwriteLoadIndex = try #require(
        instructions.compactMap { $0 as? TIR.Load }.firstIndex { load in
            load.ptr === slot && load.result !== first && load.result !== second
        }
    )
    #expect(overwriteLoadIndex < secondStoreIndex)
    for store in stores where store.value !== first {
        #expect(instructions.contains { ($0 as? TIR.Retain)?.value === store.value })
    }
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func nestedStructFieldTeardownReachesTheLeafSlot() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let pointerPointer = registry.addressType(pointee: nodePointer.id)
    let innerType = registry.structType(name: "Inner")
    innerType.fields = [(name: "child", type: nodePointer.id)]
    let outerType = registry.structType(name: "Outer")
    outerType.fields = [(name: "inner", type: innerType.id)]
    let function = module.addFunction(
        name: "f", parameters: [TIR.Parameter(ty: pointerPointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let slot = builder.buildAllocStack(allocatedType: outerType.id, name: "outer").result
    let inner = builder.buildStructElementAddr(base: slot, index: 0, name: "inner").result
    let leaf = builder.buildStructElementAddr(base: inner, index: 0, name: "leaf").result
    let value = builder.buildLoad(ptr: function.parameters[0], name: "v").result
    builder.buildStore(value: value, to: leaf)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "f" })
    let discharges = dischargedLoads(of: leaf, in: lowered)
    #expect(discharges.count == 1)
    #expect(dischargedLoads(of: inner, in: lowered).isEmpty)
    #expect(deallocations(of: slot, in: lowered).count == 1)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func classFieldIsDischargedInTheDeinitializer() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let ownerPointer = registry.pointerType(pointee: registry.classType(name: "Owner").id)
    _ = classWithMetadata(
        registry, module: module, name: "Node", hasDeinitializer: false, pointer: nodePointer.id
    )
    let ownerType = classWithMetadata(
        registry, module: module, name: "Owner", hasDeinitializer: true, pointer: ownerPointer.id
    )
    ownerType.fields = [(name: "child", type: nodePointer.id)]
    let method = module.addFunction(
        name: "setChild",
        parameters: [
            TIR.Parameter(ty: ownerPointer.id, name: "self"),
            TIR.Parameter(ty: nodePointer.id, name: "n"),
        ],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false,
        callingConvention: nil, parameterOwnership: [.Guaranteed, .Owned]
    )
    let methodEntry = method.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = methodEntry
    let field = builder.buildClassElementAddr(base: method.parameters[0], index: 0, name: "field").result
    builder.buildStore(value: method.parameters[1], to: field)
    builder.buildReturn()
    TIRPass().run(on: module)
    let loweredMethod = try #require(module.functions.first { $0.name == "setChild" })
    let methodInstructions = allInstructions(of: loweredMethod)
    let store = try #require(methodInstructions.compactMap { $0 as? TIR.Store }.first)
    #expect(store.value === loweredMethod.parameters[1])
    let assignmentDischarges = dischargedLoads(of: field, in: loweredMethod)
    #expect(assignmentDischarges.count == 1)
    let storeIndex = try #require(methodInstructions.firstIndex { $0 === store })
    let dischargeIndex = try #require(methodInstructions.firstIndex { $0 === assignmentDischarges[0] })
    #expect(dischargeIndex < storeIndex)
    #expect(consumes(of: loweredMethod.parameters[1], in: loweredMethod).isEmpty)
    let deinitializer = try #require(module.functions.first { $0.name == "Owner.deinit" })
    let deinitializerInstructions = allInstructions(of: deinitializer)
    let selfParameter = try #require(deinitializer.parameters.first)
    let deinitField = try #require(
        deinitializerInstructions.compactMap { $0 as? TIR.ClassElementAddr }
            .first { $0.base === selfParameter }
    )
    #expect(dischargedLoads(of: deinitField.result, in: deinitializer).count == 1)
    let loaded = try #require(dischargedLoads(of: deinitField.result, in: deinitializer).first).result
    #expect(
        deinitializerInstructions.contains {
            guard let release = $0 as? TIR.Release else {
                return false
            }
            return release.value === loaded
        }
    )
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func ownResultFromABorrowIsRetained() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let pointerPointer = registry.addressType(pointee: nodePointer.id)
    let function = module.addFunction(
        name: "borrowResult", parameters: [TIR.Parameter(ty: pointerPointer.id, name: "n")],
        returnType: nodePointer.id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let value = builder.buildLoad(ptr: function.parameters[0], name: "v").result
    builder.buildReturn(value)
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "borrowResult" })
    #expect(retains(of: value, in: lowered).count == 1)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func globalStoreTransfersOwnershipIntoTheSlot() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let pointerPointer = registry.addressType(pointee: nodePointer.id)
    let global = module.addGlobal(name: "g", type: nodePointer.id, isExtern: false, hasInitializer: false)
    let function = module.addFunction(
        name: "f", parameters: [TIR.Parameter(ty: pointerPointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let address = builder.buildGlobalAddr(global: global)
    let value = builder.buildLoad(ptr: function.parameters[0], name: "v").result
    builder.buildStore(value: value, to: address)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "f" })
    let instructions = allInstructions(of: lowered)
    let store = try #require(instructions.compactMap { $0 as? TIR.Store }.first)
    let retain = try #require(instructions.compactMap { $0 as? TIR.Retain }.first { $0.value === store.value })
    let retainIndex = try #require(instructionIndex(of: retain, in: lowered))
    let storeIndex = try #require(instructionIndex(of: store, in: lowered))
    #expect(retainIndex < storeIndex)
    #expect(consumes(of: store.value, in: lowered).isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func loadFromATokenlessGlobalIsNotConsumed() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let global = module.addGlobal(name: "g", type: nodePointer.id, isExtern: false, hasInitializer: false)
    let function = module.addFunction(
        name: "f", parameters: [], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let address = builder.buildGlobalAddr(global: global)
    let value = builder.buildLoad(ptr: address, name: "v").result
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "f" })
    #expect(retains(of: value, in: lowered).isEmpty)
    #expect(consumes(of: value, in: lowered).isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func guaranteedReferenceParameterEntersAtZero() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointerType = registry.pointerType(pointee: nodeType.id)
    let function = module.addFunction(
        name: "borrow", parameters: [TIR.Parameter(ty: nodePointerType.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false,
        callingConvention: nil, parameterOwnership: [.Guaranteed]
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "borrow" })
    let parameter = try #require(lowered.parameters.first)
    #expect(consumes(of: parameter, in: lowered).isEmpty)
    #expect(retains(of: parameter, in: lowered).isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func strictVerifierAcceptsEveryProducedModule() {
    let sources = [
        classSource, twoLocalsSource, loopSource, branchSource, passthroughSource,
    ]
    for source in sources {
        let (context, module) = runTIRPass(source)
        #expect(ownershipFailures(context, module).isEmpty)
    }
}

private let branchCleanupPrelude = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32
typealias Bool = Builtin.Bool

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
    func m() -> Int32 { return self.value }
}

func take(_ c: C) -> C {
    return c
}
"""

private let letInBranchSource = branchCleanupPrelude + """

func letInBranch(_ flag: Bool, _ c: C) -> Int32 {
    var r = 0
    if flag {
        let d = c
        r = d.m()
    }
    return r
}
"""

private let callInBranchSource = branchCleanupPrelude + """

func callInBranch(_ flag: Bool, _ c: C) -> Int32 {
    var r = 0
    if flag {
        r = take(c).m()
    }
    return r
}
"""

private let loadInLoopSource = branchCleanupPrelude + """

func loadInLoop(_ flag: Bool, _ c: C) -> Int32 {
    var r = 0
    while flag {
        let d = c
        r = d.m()
        break
    }
    return r
}
"""

private func isTerminator(_ instruction: TIR.Instruction) -> Bool {
    instruction is TIR.Return || instruction is TIR.Branch
        || instruction is TIR.ConditionalBranch || instruction is TIR.SwitchEnum
        || instruction is TIR.Unreachable || instruction is TIR.Trap || instruction is TIR.TryCall
}

private func expectNoInstructionAfterTerminator(_ module: TIR.Module) {
    for function in module.functions where !function.isExtern {
        for block in function.basicBlocks {
            guard let terminator = block.instructions.firstIndex(where: isTerminator) else {
                continue
            }
            #expect(
                terminator == block.instructions.count - 1,
                "block '\(block.name)' has instructions after its terminator"
            )
        }
    }
}

@Test
func branchLocalCleanupsArePathComplete() throws {
    for source in [letInBranchSource, callInBranchSource, loadInLoopSource] {
        let (context, module) = runTIRPass(source)
        #expect(
            ownershipFailures(context, module).isEmpty,
            "expected a strict-clean module, got: \(ownershipFailures(context, module).map(\.message))"
        )
        expectNoInstructionAfterTerminator(module)
    }
    let (context, module) = runTIRPass(letInBranchSource)
    let letInBranch = try #require(function(named: "letInBranch", in: module))
    let typeId = try #require(classTypeId(named: "C", in: module))
    let parameterSlot = try #require(slot(of: typeId, in: letInBranch))
    let discharges = dischargedLoads(of: parameterSlot, in: letInBranch)
    #expect(discharges.count == 1)
    let deallocations = deallocations(of: parameterSlot, in: letInBranch)
    #expect(deallocations.count == 1)
    #expect(strictFailures(context, module).isEmpty)
}

private let fieldStoreSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Box {
    var child: C
    init(c: C) { self.child = c return }
    deinit { return }
}
"""

@Test
func classFieldIsDischargedOnlyByTheDeinitializer() throws {
    let (context, module) = runTIRPass(fieldStoreSource)
    #expect(strictFailures(context, module).isEmpty)
    let initializer = try #require(module.functions.first { $0.name.contains("Box_4init") })
    let initializerSelf = try #require(initializer.parameters.first)
    #expect(retains(of: initializerSelf, in: initializer).isEmpty)
    let initializerFields = allInstructions(of: initializer).compactMap { $0 as? TIR.ClassElementAddr }
    #expect(initializerFields.count == 1)
    let initializerInstructions = allInstructions(of: initializer)
    let assignmentDischarges = dischargedLoads(of: initializerFields[0].result, in: initializer)
    #expect(assignmentDischarges.count == 1)
    let initializerStore = try #require(
        initializerInstructions.compactMap { $0 as? TIR.Store }
            .first { $0.ptr === initializerFields[0].result }
    )
    let initializerStoreIndex = try #require(initializerInstructions.firstIndex { $0 === initializerStore })
    let assignmentDischargeIndex = try #require(
        initializerInstructions.firstIndex { $0 === assignmentDischarges[0] }
    )
    #expect(assignmentDischargeIndex < initializerStoreIndex)
    let topLevelDeallocations = allInstructions(of: initializer).compactMap { $0 as? TIR.DeallocStack }
    #expect(!topLevelDeallocations.isEmpty)
    #expect(!topLevelDeallocations.contains { $0.value === initializerFields[0].result })
    let deinitializer = try #require(module.functions.first { $0.name.contains("Box_6deinit") })
    let deinitializerSelf = try #require(deinitializer.parameters.first)
    #expect(consumes(of: deinitializerSelf, in: deinitializer).isEmpty)
    #expect(retains(of: deinitializerSelf, in: deinitializer).isEmpty)
    let deinitializerFields = allInstructions(of: deinitializer).compactMap { $0 as? TIR.ClassElementAddr }
    #expect(deinitializerFields.count == 1)
    #expect(dischargedLoads(of: deinitializerFields[0].result, in: deinitializer).count == 1)
}

private let fieldWithoutDeinitializerSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Holder {
    var child: C
    init(c: C) { self.child = c return }
}

func makeHolder(c: C) -> Int32 {
    let h = Holder(c: c)
    return 0
}
"""

@Test
func classWithReferenceFieldsWithoutUserDeinitializerDischargesThem() throws {
    let (context, module) = runTIRPass(fieldWithoutDeinitializerSource)
    #expect(strictFailures(context, module).isEmpty)
    let record = try #require(module.registry.metadatas.values.first { $0.name == "Holder" })
    let entry = try #require(record.vtable.first)
    let deinitializer = try #require(module.registry.functions[entry.function])
    #expect(deinitializer.name != "$t_noop_deinit")
    let fields = allInstructions(of: deinitializer).compactMap { $0 as? TIR.ClassElementAddr }
    #expect(fields.count == 1)
    #expect(dischargedLoads(of: fields[0].result, in: deinitializer).count == 1)
}

private let ownedCallResultSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
    func m() -> Int32 { return self.value }
}

var g: C = C()

func getG() -> C {
    return g
}

func useG() -> Int32 {
    return getG().m()
}
"""

@Test
func ownedCallResultIsTransferredWithoutAnExtraRetain() throws {
    let (context, module) = runTIRPass(ownedCallResultSource)
    #expect(strictFailures(context, module).isEmpty)
    let useG = try #require(function(named: "useG", in: module))
    let instructions = allInstructions(of: useG)
    let call = try #require(instructions.compactMap { $0 as? TIR.Call }.first { $0.result != nil })
    let result = try #require(call.result)
    #expect(retains(of: result, in: useG).isEmpty)
    #expect(instructions.compactMap { $0 as? TIR.Store }.contains { $0.value === result })
    let initialization = try #require(module.functions.first { $0.name.contains("global_init") })
    let heap = try #require(
        allInstructions(of: initialization).compactMap { $0 as? TIR.AllocHeap }.first
    )
    #expect(retains(of: heap.result, in: initialization).isEmpty)
    #expect(consumes(of: heap.result, in: initialization).isEmpty)
}

@Test
func globalSlotsAreKeyedByGlobalIdentity() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let pointerPointer = registry.addressType(pointee: nodePointer.id)
    let global = module.addGlobal(
        name: "g", type: nodePointer.id, isExtern: false, hasInitializer: false
    )
    let function = module.addFunction(
        name: "f", parameters: [TIR.Parameter(ty: pointerPointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let first = builder.buildGlobalAddr(global: global)
    let firstValue = builder.buildLoad(ptr: function.parameters[0], name: "v").result
    builder.buildStore(value: firstValue, to: first)
    let second = builder.buildGlobalAddr(global: global)
    let secondValue = builder.buildLoad(ptr: function.parameters[0], name: "w").result
    builder.buildStore(value: secondValue, to: second)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "f" })
    let instructions = allInstructions(of: lowered)
    let stores = instructions.compactMap { $0 as? TIR.Store }
    #expect(stores.count == 2)
    let discharges = dischargedLoads(of: second, in: lowered)
    #expect(discharges.count == 1)
    let secondStoreIndex = try #require(instructions.firstIndex { $0 === stores[1] })
    let dischargeIndex = try #require(instructions.firstIndex { $0 === discharges[0] })
    #expect(dischargeIndex < secondStoreIndex)
    #expect(strictFailures(context, module).isEmpty)
}

private let multiReturnInitializerSource = """
typealias Int32 = Builtin.Int32
typealias Bool = Builtin.Bool

class E {
    init(_ flag: Bool) {
        if flag {
            return
        }
        return
    }
}
"""

@Test
func multiReturnInitializerTransfersSelfExactlyOnceOnEveryPath() throws {
    let (context, module) = runTIRPass(multiReturnInitializerSource)
    #expect(strictFailures(context, module).isEmpty)
    let initializer = try #require(module.functions.first { $0.name.contains("_4init_") })
    let selfParameter = try #require(initializer.parameters.first)
    #expect(retains(of: selfParameter, in: initializer).isEmpty)
    #expect(consumes(of: selfParameter, in: initializer).isEmpty)
    let returns = initializer.basicBlocks.flatMap(\.instructions).compactMap { $0 as? TIR.Return }
    #expect(returns.count == 2)
    #expect(returns.allSatisfy { $0.value === selfParameter })
    expectNoInstructionAfterTerminator(module)
}

private let structWithReferenceSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

struct S {
    var c: C
    init(c: C) { self.c = c return }
}

func makeS(c: C) -> Int32 {
    var s = S(c: c)
    return 0
}
"""

@Test
func structContainingReferencesIsDestroyedNotReleased() throws {
    let (context, module) = runTIRPass(structWithReferenceSource)
    #expect(strictFailures(context, module).isEmpty)
    let makeS = try #require(function(named: "makeS", in: module))
    let structType = try #require(
        module.registry.types.values.compactMap { $0 as? TIRType.StructType }
            .first { $0.displayText == "S" }
    )
    let structSlot = try #require(slot(of: structType.id, in: makeS))
    let discharges = dischargedLoads(of: structSlot, in: makeS)
    #expect(discharges.count == 1)
    let structValue = try #require(discharges.first).result
    #expect(allInstructions(of: makeS).contains { ($0 as? TIR.Destroy)?.value === structValue })
}

@Test
func noInstructionIsInsertedAfterATerminator() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let calleeParameter = TIR.Parameter(ty: nodePointer.id, name: "n")
    let callee = module.addFunction(
        name: "callee", parameters: [calleeParameter], returnType: nodePointer.id, isVariadic: false,
        isExtern: false, callingConvention: nil, parameterOwnership: [.Guaranteed],
        resultOwnership: .Guaranteed
    )
    callee.addBasicBlock(name: "entry").instructions.append(TIR.Return(value: calleeParameter))
    let callerParameter = TIR.Parameter(ty: nodePointer.id, name: "n")
    let caller = module.addFunction(
        name: "caller", parameters: [callerParameter], returnType: nodePointer.id, isVariadic: false,
        isExtern: false, callingConvention: nil, parameterOwnership: [.Owned]
    )
    let entry = caller.addBasicBlock(name: "entry")
    let success = caller.addBasicBlock(name: "success")
    let failure = caller.addBasicBlock(name: "failure")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let cell = builder.buildAllocStack(allocatedType: nodePointer.id, name: "cell").result
    let reference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    let tryCall = builder.buildTryCall(
        callee: reference, arguments: [callerParameter], successBlock: success, errorBlock: failure,
        errorCell: cell
    )
    builder.insertPoint = success
    builder.buildReturn(tryCall.result)
    builder.insertPoint = failure
    builder.buildReturn(callerParameter)
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "caller" })
    expectNoInstructionAfterTerminator(module)
    let result = try #require(tryCall.result)
    #expect(retains(of: result, in: lowered).count == 1)
    #expect(strictFailures(context, module).isEmpty)
}

private let crossFunctionGlobalSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

var g = C()

func reset() {
    g = C()
}

func selfAssign() {
    g = g
}
"""

private func consumesValue(_ load: TIR.Load, in instructions: [TIR.Instruction]) -> Bool {
    instructions.contains { instruction in
        switch instruction {
        case let release as TIR.Release:
            release.value === load.result
        case let destroy as TIR.Destroy:
            destroy.value === load.result
        default:
            false
        }
    }
}

@Test
func crossFunctionGlobalAssignmentDischargesTheOldValue() throws {
    let (context, module) = runTIRPass(crossFunctionGlobalSource)
    #expect(strictFailures(context, module).isEmpty)
    let reset = try #require(function(named: "reset", in: module))
    let instructions = allInstructions(of: reset)
    let store = try #require(instructions.compactMap { $0 as? TIR.Store }.first)
    let discharge = try #require(
        instructions.compactMap { $0 as? TIR.Load }.first { $0.ptr === store.ptr }
    )
    #expect(consumesValue(discharge, in: instructions))
    let retain = try #require(
        instructions.compactMap { $0 as? TIR.Retain }.first { $0.value === store.value }
    )
    let retainIndex = try #require(instructions.firstIndex { $0 === retain })
    let dischargeIndex = try #require(instructions.firstIndex { $0 === discharge })
    let storeIndex = try #require(instructions.firstIndex { $0 === store })
    #expect(retainIndex < dischargeIndex)
    #expect(dischargeIndex < storeIndex)
}

@Test
func selfAssignmentRetainsBeforeReleasingTheOldValue() throws {
    let (context, module) = runTIRPass(crossFunctionGlobalSource)
    #expect(strictFailures(context, module).isEmpty)
    let selfAssign = try #require(function(named: "selfAssign", in: module))
    let instructions = allInstructions(of: selfAssign)
    let store = try #require(instructions.compactMap { $0 as? TIR.Store }.first)
    let newValue = store.value
    let retain = try #require(
        instructions.compactMap { $0 as? TIR.Retain }.first { $0.value === newValue }
    )
    let discharge = try #require(
        instructions.compactMap { $0 as? TIR.Load }
            .first { $0.ptr === store.ptr && $0.result !== newValue }
    )
    #expect(consumesValue(discharge, in: instructions))
    let retainIndex = try #require(instructions.firstIndex { $0 === retain })
    let dischargeIndex = try #require(instructions.firstIndex { $0 === discharge })
    let storeIndex = try #require(instructions.firstIndex { $0 === store })
    #expect(retainIndex < dischargeIndex)
    #expect(dischargeIndex < storeIndex)
}

private let fieldAssignmentSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Holder {
    var child: C
    init(c: C) { self.child = c return }
    deinit { return }
    func setChild(c: C) -> Int32 {
        self.child = c
        return 0
    }
}

class Pair {
    var first: C
    var second: C
    init(a: C, b: C) {
        self.first = a
        self.second = b
        self.first = b
        return
    }
    deinit { return }
}
"""

@Test
func classFieldOverwriteInAMethodDischargesTheOldValue() throws {
    let (context, module) = runTIRPass(fieldAssignmentSource)
    #expect(strictFailures(context, module).isEmpty)
    let setter = try #require(module.functions.first { $0.name.contains("setChild") })
    let instructions = allInstructions(of: setter)
    let field = try #require(instructions.compactMap { $0 as? TIR.ClassElementAddr }.first)
    let store = try #require(
        instructions.compactMap { $0 as? TIR.Store }.first { $0.ptr === field.result }
    )
    let discharge = try #require(dischargedLoads(of: field.result, in: setter).first)
    #expect(consumesValue(discharge, in: instructions))
    let dischargeIndex = try #require(instructions.firstIndex { $0 === discharge })
    let storeIndex = try #require(instructions.firstIndex { $0 === store })
    #expect(dischargeIndex < storeIndex)
    #expect(retains(of: setter.parameters[1], in: setter).isEmpty)
    #expect(consumes(of: setter.parameters[1], in: setter).isEmpty)
}

@Test
func secondAssignmentInAnInitializerDischargesTheOldValue() throws {
    let (context, module) = runTIRPass(fieldAssignmentSource)
    #expect(strictFailures(context, module).isEmpty)
    let initializer = try #require(module.functions.first { $0.name.contains("Pair_4init") })
    let instructions = allInstructions(of: initializer)
    let fieldAddresses = instructions.compactMap { $0 as? TIR.ClassElementAddr }.map(\.result)
    #expect(!fieldAddresses.isEmpty)
    let fieldStores = instructions.compactMap { $0 as? TIR.Store }.filter { store in
        fieldAddresses.contains { $0 === store.ptr }
    }
    #expect(fieldStores.count == 3)
    let dischargedFieldLoads = instructions.compactMap { $0 as? TIR.Load }.filter { load in
        fieldAddresses.contains { $0 === load.ptr } && consumesValue(load, in: instructions)
    }
    #expect(dischargedFieldLoads.count == fieldStores.count)
    for store in fieldStores {
        let storeIndex = try #require(instructions.firstIndex { $0 === store })
        #expect(
            dischargedFieldLoads.contains { load in
                guard let index = instructions.firstIndex(where: { $0 === load }) else {
                    return false
                }
                return index < storeIndex
            }
        )
    }
}

@Test
func blockArgumentTransferIsNotConsumedBeforeTheBranch() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let boolType = registry.primitiveType(kind: .Bool, bitWidth: 1).id
    let function = module.addFunction(
        name: "merge",
        parameters: [
            TIR.Parameter(ty: boolType, name: "flag"),
            TIR.Parameter(ty: nodePointer.id, name: "n"),
        ],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let left = function.addBasicBlock(name: "left")
    let join = function.addBasicBlock(
        name: "join", parameters: [(name: "v", ty: nodePointer.id)]
    )
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    builder.buildConditionalBranch(
        condition: function.parameters[0], trueBranch: left, falseBranch: join,
        falseArguments: [function.parameters[1]]
    )
    builder.insertPoint = left
    builder.buildBranch(to: join, arguments: [function.parameters[1]])
    builder.insertPoint = join
    builder.buildReturn()
    TIRPass().run(on: module)

    let lowered = try #require(module.functions.first { $0.name == "merge" })
    let instructions = allInstructions(of: lowered)
    let joinBlock = try #require(lowered.basicBlocks.first { $0.name == "join" })
    let blockParameter = try #require(joinBlock.parameters.first)
    #expect(consumes(of: blockParameter, in: lowered).count == 1)
    let functionParameter = try #require(lowered.parameters.last)
    let consumesFunctionParameter = instructions.contains { instruction in
        switch instruction {
        case let release as TIR.Release:
            release.value === functionParameter
        case let destroy as TIR.Destroy:
            destroy.value === functionParameter
        default:
            false
        }
    }
    #expect(!consumesFunctionParameter)
    expectNoInstructionAfterTerminator(module)
    #expect(strictFailures(context, module).isEmpty)
}

private let fieldReadSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
    func m() -> Int32 { return self.value }
}

class Holder {
    var child: C
    init(c: C) { self.child = c return }
    deinit { return }
    func get() -> C { return self.child }
    func use() -> Int32 { return self.child.m() }
}
"""

@Test
func fieldReadIsABorrowThatRetainsOnEscape() throws {
    let (context, module) = runTIRPass(fieldReadSource)
    #expect(strictFailures(context, module).isEmpty)
    let getter = try #require(module.functions.first { $0.name.contains("_3get") })
    let getterInstructions = allInstructions(of: getter)
    let getterField = try #require(getterInstructions.compactMap { $0 as? TIR.ClassElementAddr }.first)
    let getterLoad = try #require(
        getterInstructions.compactMap { $0 as? TIR.Load }.first { $0.ptr === getterField.result }
    )
    #expect(retains(of: getterLoad.result, in: getter).count == 1)
    #expect(consumes(of: getterLoad.result, in: getter).isEmpty)
    let use = try #require(module.functions.first { $0.name.contains("_3use") })
    let useInstructions = allInstructions(of: use)
    let useField = try #require(useInstructions.compactMap { $0 as? TIR.ClassElementAddr }.first)
    let useLoad = try #require(
        useInstructions.compactMap { $0 as? TIR.Load }.first { $0.ptr === useField.result }
    )
    #expect(consumes(of: useLoad.result, in: use).isEmpty)
    #expect(retains(of: useLoad.result, in: use).count == 1)
}

private let deinitInheritanceSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Base {
    var baseChild: C
    init(c: C) { self.baseChild = c return }
    deinit { return }
}

class Sub: Base {
    var subChild: C
    init(c: C) { self.subChild = c return }
}
"""

@Test
func synthesizedDeinitializerChainsToTheInheritedDeinitializer() throws {
    let (context, module) = runTIRPass(deinitInheritanceSource)
    #expect(strictFailures(context, module).isEmpty)
    let subRecord = try #require(module.registry.metadatas.values.first { $0.name == "Sub" })
    let subEntry = try #require(subRecord.vtable.first)
    let subDeinitializer = try #require(module.registry.functions[subEntry.function])
    #expect(subDeinitializer.name != "$t_noop_deinit")
    let baseRecord = try #require(module.registry.metadatas.values.first { $0.name == "Base" })
    let baseEntry = try #require(baseRecord.vtable.first)
    let baseDeinitializer = try #require(module.registry.functions[baseEntry.function])
    let subInstructions = allInstructions(of: subDeinitializer)
    #expect(
        subInstructions.compactMap { $0 as? TIR.Call }.contains { call in
            guard let reference = call.callee as? TIR.FunctionRef else {
                return false
            }
            return reference.functionId == baseDeinitializer.id
        }
    )
    let subFields = subInstructions.compactMap { $0 as? TIR.ClassElementAddr }
    #expect(subFields.count == 1)
    #expect(subFields[0].index == 1)
    #expect(dischargedLoads(of: subFields[0].result, in: subDeinitializer).count == 1)
    let baseFields = allInstructions(of: baseDeinitializer)
        .compactMap { $0 as? TIR.ClassElementAddr }
    #expect(baseFields.count == 1)
    #expect(baseFields[0].index == 0)
}

@Test
func consumeWithoutAnOwnedInstanceIsRejected() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let function = module.addFunction(
        name: "consume", parameters: [TIR.Parameter(ty: nodePointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false,
        callingConvention: nil, parameterOwnership: [.Guaranteed]
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    builder.buildRetain(function.parameters[0])
    builder.buildRelease(function.parameters[0])
    builder.buildRelease(function.parameters[0])
    builder.buildRetain(function.parameters[0])
    builder.buildReturn()
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(
        failures.contains { $0.message.contains("no owned instance left") },
        "expected the second release to be rejected"
    )
}

private func mergeModule(
    withDestroyBeforeBranch: Bool
) -> (Context, TIR.Module, TIR.Function, TIR.BasicBlock) {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let function = module.addFunction(
        name: "merge", parameters: [TIR.Parameter(ty: nodePointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let join = function.addBasicBlock(name: "join", parameters: [(name: "v", ty: nodePointer.id)])
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    if withDestroyBeforeBranch {
        builder.buildDestroy(function.parameters[0])
    }
    builder.buildBranch(to: join, arguments: [function.parameters[0]])
    builder.insertPoint = join
    builder.buildDestroy(join.parameters[0])
    builder.buildReturn()
    return (context, module, function, join)
}

@Test
func blockArgumentTransferEntersTheParameterAtOne() throws {
    let (context, module, _, _) = mergeModule(withDestroyBeforeBranch: false)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(failures.isEmpty, "expected the transfer shape to verify, got: \(failures.map(\.message))")
}

@Test
func destroyingAValueBeforePassingItAsABlockArgumentIsRejected() throws {
    let (context, module, _, _) = mergeModule(withDestroyBeforeBranch: true)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(
        failures.contains {
            $0.message.contains("reference value 'n'") && $0.message.contains("balance -1")
        },
        "expected the destroyed block argument to be rejected, got: \(failures.map(\.message))"
    )
}

private func deinitializerModule(
    discharge: Bool
) -> (Context, TIR.Module, TIR.Function) {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let ownerType = classWithMetadata(
        registry, module: module, name: "Owner",
        hasDeinitializer: true, pointer: registry.pointerType(pointee: registry.classType(name: "Owner").id).id
    )
    ownerType.fields = [(name: "child", type: nodeType.id)]
    guard let deinitializer = module.functions.first(where: { $0.name == "Owner.deinit" }),
          let entry = deinitializer.basicBlocks.first
    else {
        return (context, module, TIR.Function(
            module: module, id: registry.nextFunctionId, name: "", ty: registry.voidType().id,
            parameters: [], returnType: registry.voidType().id, isVariadic: false,
            isExtern: false, callingConvention: nil
        ))
    }
    entry.instructions.removeAll()
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    if discharge {
        let field = builder.buildClassElementAddr(base: deinitializer.parameters[0], index: 0)
        let loaded = builder.buildLoad(ptr: field.result)
        builder.buildDestroy(loaded.result)
    }
    builder.buildReturn()
    return (context, module, deinitializer)
}

@Test
func deinitializerWithoutFieldDischargeIsRejected() throws {
    let (context, module, _) = deinitializerModule(discharge: false)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(
        failures.contains { $0.message.contains("does not discharge reference field") },
        "expected the missing field discharge to be reported, got: \(failures.map(\.message))"
    )
}

@Test
func deinitializerWithFieldDischargeIsAccepted() throws {
    let (context, module, _) = deinitializerModule(discharge: true)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(failures.isEmpty, "expected the discharge shape to verify, got: \(failures.map(\.message))")
}

private let ifJoinAssignmentSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32
typealias Bool = Builtin.Bool

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

func make() -> C {
    return C()
}

var g = C()

func assignGlobal(_ flag: Bool) {
    if flag {
        g = make()
    } else {
        g = make()
    }
}

func assignLocal(_ flag: Bool) {
    var x = make()
    if flag {
        x = make()
    } else {
        x = make()
    }
}

class Holder {
    var child: C
    init(c: C) { self.child = c return }
    deinit { return }
    func assignField(flag: Bool, a: C, b: C) {
        if flag {
            self.child = a
        } else {
            self.child = b
        }
    }
}

func usedIf(_ flag: Bool) -> C {
    let x = if flag { make() } else { make() }
    return x
}
"""

@Test
func ifJoinAssignmentIsStrictCleanAndKeepsTheJoinArgumentOwned() throws {
    let (context, module) = runTIRPass(ifJoinAssignmentSource)
    #expect(
        ownershipFailures(context, module).isEmpty,
        "if/else assignment must verify, got: \(ownershipFailures(context, module).map(\.message))"
    )
    expectNoInstructionAfterTerminator(module)
    let assignGlobal = try #require(function(named: "assignGlobal", in: module))
    let globalInstructions = allInstructions(of: assignGlobal)
    let join = try #require(assignGlobal.basicBlocks.first { !$0.parameters.isEmpty })
    let joinParameter = try #require(join.parameters.first)
    #expect(consumes(of: joinParameter, in: assignGlobal).count == 1)
    for block in assignGlobal.basicBlocks where block !== join {
        let stores = block.instructions.compactMap { $0 as? TIR.Store }
        for store in stores {
            guard let branch = block.instructions.last as? TIR.Branch,
                  branch.arguments.contains(where: { $0 === store.value })
            else {
                continue
            }
            #expect(
                retains(of: store.value, in: assignGlobal).count == 1,
                "the join argument must be retained once when the store consumed its +1"
            )
        }
    }
    let assignLocal = try #require(function(named: "assignLocal", in: module))
    let localJoin = try #require(assignLocal.basicBlocks.first { !$0.parameters.isEmpty })
    #expect(try consumes(of: #require(localJoin.parameters.first), in: assignLocal).count == 1)
    let holder = try #require(module.functions.first { $0.name.contains("assignField") })
    let fieldJoin = try #require(holder.basicBlocks.first { !$0.parameters.isEmpty })
    #expect(try consumes(of: #require(fieldJoin.parameters.first), in: holder).count == 1)
}

@Test
func ifExpressionWithATokenArgumentAddsNoSpeculativeRetain() throws {
    let (context, module) = runTIRPass(ifJoinAssignmentSource)
    #expect(strictFailures(context, module).isEmpty)
    let usedIf = try #require(function(named: "usedIf", in: module))
    let instructions = allInstructions(of: usedIf)
    let join = try #require(usedIf.basicBlocks.first { !$0.parameters.isEmpty })
    let joinParameter = try #require(join.parameters.first)
    let armCalls = instructions.compactMap { $0 as? TIR.Call }.filter { $0.result != nil }
    #expect(!armCalls.isEmpty)
    for call in armCalls {
        let result = try #require(call.result)
        #expect(
            retains(of: result, in: usedIf).isEmpty,
            "a branch value whose +1 is transferred must not be retained"
        )
    }
    #expect(retains(of: joinParameter, in: usedIf).isEmpty)
}

private func ifJoinMutantModule(
    retainBeforeBranch: Bool, consumeJoinParameter: Bool
) -> (Context, TIR.Module) {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let global = module.addGlobal(
        name: "g", type: nodePointer.id, isExtern: false, hasInitializer: false
    )
    let parameter = TIR.Parameter(ty: nodePointer.id, name: "n")
    let function = module.addFunction(
        name: "mutant", parameters: [parameter], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let join = function.addBasicBlock(name: "join", parameters: [(name: "v", ty: nodePointer.id)])
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let address = builder.buildGlobalAddr(global: global)
    let old = builder.buildLoad(ptr: address)
    builder.buildRelease(old.result)
    builder.buildStore(value: parameter, to: address)
    if retainBeforeBranch {
        builder.buildRetain(parameter)
    }
    builder.buildBranch(to: join, arguments: [parameter])
    builder.insertPoint = join
    if consumeJoinParameter {
        builder.buildDestroy(join.parameters[0])
    }
    builder.buildReturn()
    return (context, module)
}

@Test
func branchArgumentWhoseTokenWasStoredNeedsAnAcquire() throws {
    let (context, module) = ifJoinMutantModule(retainBeforeBranch: false, consumeJoinParameter: true)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(
        !failures.isEmpty,
        "a branch argument whose +1 the store consumed must be rejected without a retain"
    )
}

@Test
func joinParameterWithoutConsumerIsRejected() throws {
    let (context, module) = ifJoinMutantModule(retainBeforeBranch: true, consumeJoinParameter: false)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(
        failures.contains { $0.message.contains("balance 1 at the return, expected 0") },
        "an unconsumed join parameter must be rejected, got: \(failures.map(\.message))"
    )
}

@Test
func joinArgumentWithAcquireAndConsumerIsAccepted() throws {
    let (context, module) = ifJoinMutantModule(retainBeforeBranch: true, consumeJoinParameter: true)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(failures.isEmpty, "expected the balanced shape to verify, got: \(failures.map(\.message))")
}

@Test
func switchEnumEdgeTransfersAJoinArgument() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let enumType = registry.enumType(name: "E")
    enumType.cases = [(name: "A", associatedTypes: []), (name: "B", associatedTypes: [])]
    let function = module.addFunction(
        name: "switchJoin",
        parameters: [TIR.Parameter(ty: enumType.id, name: "e"), TIR.Parameter(ty: nodePointer.id, name: "n")],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let join = function.addBasicBlock(name: "join", parameters: [(name: "v", ty: nodePointer.id)])
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    builder.buildSwitchEnum(
        value: function.parameters[0],
        cases: [TIR.SwitchEnum.Case(tag: 0, block: join, arguments: [function.parameters[1]])],
        defaultBlock: join
    )
    builder.insertPoint = join
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "switchJoin" })
    let joinBlock = try #require(lowered.basicBlocks.first { $0.name == "join" })
    let parameter = try #require(joinBlock.parameters.first)
    #expect(consumes(of: parameter, in: lowered).count == 1)
    let failures = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(
        failures.isEmpty,
        "switch edge transfer must verify, got: \(failures.map(\.message))"
    )
}

private let deinitBodySource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Reader {
    var child: C
    init(c: C) { self.child = c return }
    deinit {
        let x = self.child
        return
    }
}

class Base {
    var baseChild: C
    init(c: C) { self.baseChild = c return }
    deinit { return }
}

class Sub: Base {
    var subChild: C
    init(c: C) { self.subChild = c return }
    deinit { return }
}
"""

@Test
func userDeinitializerDischargesFieldsAfterTheBody() throws {
    let (context, module) = runTIRPass(deinitBodySource)
    #expect(strictFailures(context, module).isEmpty)
    let deinitializer = try #require(module.functions.first { $0.name.contains("Reader_6deinit") })
    let instructions = allInstructions(of: deinitializer)
    let fieldUse = try #require(
        instructions.firstIndex { $0 is TIR.Load } ?? nil
    )
    let discharge = try #require(
        instructions.compactMap { $0 as? TIR.Load }
            .first { load in
                instructions.contains { instruction in
                    switch instruction {
                    case let destroy as TIR.Destroy:
                        destroy.value === load.result
                    case let release as TIR.Release:
                        release.value === load.result
                    default:
                        false
                    }
                }
            }
    )
    let dischargeIndex = try #require(instructions.firstIndex { $0 === discharge })
    #expect(fieldUse < dischargeIndex)
}

@Test
func userSubclassDeinitializerChainsToTheBase() throws {
    let (context, module) = runTIRPass(deinitBodySource)
    #expect(strictFailures(context, module).isEmpty)
    let subRecord = try #require(module.registry.metadatas.values.first { $0.name == "Sub" })
    let subDeinit = try #require(subRecord.vtable.first.flatMap { module.registry.functions[$0.function] })
    let baseRecord = try #require(module.registry.metadatas.values.first { $0.name == "Base" })
    let baseDeinit = try #require(baseRecord.vtable.first.flatMap { module.registry.functions[$0.function] })
    let userDeinit = try #require(module.functions.first { $0.name.contains("Sub_6deinit") })
    let wrapperInstructions = allInstructions(of: subDeinit)
    let calls = wrapperInstructions.compactMap { $0 as? TIR.Call }
    #expect(calls.contains { ($0.callee as? TIR.FunctionRef)?.functionId == userDeinit.id })
    #expect(calls.contains { ($0.callee as? TIR.FunctionRef)?.functionId == baseDeinit.id })
    let ownFields = wrapperInstructions.compactMap { $0 as? TIR.ClassElementAddr }
    #expect(ownFields.count == 1)
    #expect(ownFields[0].index == 1)
    #expect(dischargedLoads(of: ownFields[0].result, in: subDeinit).count == 1)
}

@Test
func borrowBranchArgumentsAreRetained() throws {
    let source = """
    precedencegroup AssignmentPrecedence {
        associativity: right
        assignment: true
    }
    infix operator = : AssignmentPrecedence
    typealias Int32 = Builtin.Int32
    typealias Bool = Builtin.Bool

    class C {
        var value: Int32 = 0
        init() { return }
        deinit { return }
    }

    var g = C()

    func globalBorrowIf(_ cond: Bool) -> C {
        let x = if cond { g } else { g }
        return x
    }

    class Holder {
        var child: C
        init(c: C) { self.child = c return }
        deinit { return }
        func fieldBorrowIf(_ cond: Bool) -> C {
            let x = if cond { self.child } else { self.child }
            return x
        }
    }
    """
    let (context, module) = runTIRPass(source)
    #expect(
        ownershipFailures(context, module).isEmpty,
        "borrow branch arguments must verify, got: \(ownershipFailures(context, module).map(\.message))"
    )
    for name in ["globalBorrowIf", "fieldBorrowIf"] {
        let lowered = try #require(function(named: name, in: module))
        let join = try #require(lowered.basicBlocks.first { !$0.parameters.isEmpty })
        let joinParameter = try #require(join.parameters.first)
        #expect(
            consumes(of: joinParameter, in: lowered).count
                + retains(of: joinParameter, in: lowered).count <= 1
        )
        let armRetains = lowered.basicBlocks
            .filter { $0 !== join }
            .flatMap(\.instructions)
            .compactMap { $0 as? TIR.Retain }
        #expect(
            !armRetains.isEmpty,
            "a borrow branch argument must be acquired before the transfer"
        )
    }
}

@Test
func advisoryModeDoesNotEnforceTheDeinitializerDischargeRule() throws {
    let (context, module, _) = deinitializerModule(discharge: false)
    let advisory = TIR.Verifier(context: context, ownershipMode: .Advisory).verify(module)
    #expect(
        !advisory.contains { $0.message.contains("does not discharge reference field") },
        "advisory must not enforce the deinitializer rule"
    )
    let strict = TIR.Verifier(context: context, ownershipMode: .Strict).verify(module)
    #expect(strict.contains { $0.message.contains("does not discharge reference field") })
}

@Test
func passDoesNotRegisterHelperNominalTypes() throws {
    let (_, module) = runTIRPass(deinitBodySource)
    let fabricated = module.registry.types.values.compactMap { type in
        (type as? TIRType.NominalType).map(\.name)
    }.filter { $0.contains("$own") || $0.contains("$view") }
    #expect(
        fabricated.isEmpty,
        "the own-field discharge must not fabricate nominal types, got: \(fabricated)"
    )
    let dump = TIR.Dumper().dump(module)
    #expect(!dump.contains("$own"))
}

private enum ReferenceCast {
    case Upcast
    case UncheckedRefCast
    case BitCast
}

private func castIntoSlotModule(
    _ cast: ReferenceCast
) -> (Context, TIR.Module, TIR.Parameter, TIR.Value, TIR.Value) {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodePointer = registry.pointerType(pointee: registry.classType(name: "Node").id).id
    let parameter = TIR.Parameter(ty: nodePointer, name: "n")
    let function = module.addFunction(
        name: "castStore", parameters: [parameter], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil, parameterOwnership: [.Owned]
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let slot = builder.buildAllocStack(allocatedType: nodePointer, name: "slot").result
    let casted: TIR.Value = switch cast {
    case .Upcast:
        builder.buildUpcast(value: parameter, to: nodePointer).result
    case .UncheckedRefCast:
        builder.buildUncheckedRefCast(value: parameter, to: nodePointer).result
    case .BitCast:
        builder.buildBitCast(value: parameter, to: nodePointer).result
    }
    builder.buildStore(value: casted, to: slot)
    builder.buildReturn()
    return (context, module, parameter, casted, slot)
}

@Test
func referenceCastMovesTheTokenInsteadOfAcquiringANewOne() throws {
    for cast in [ReferenceCast.Upcast, .UncheckedRefCast, .BitCast] {
        let (context, module, parameter, casted, slot) = castIntoSlotModule(cast)
        let result = TIRPass().run(on: module)
        #expect(result.failures.isEmpty)
        let lowered = try #require(module.functions.first { $0.name == "castStore" })
        #expect(
            retains(of: casted, in: lowered).isEmpty,
            "a reference cast moves the operand token, so its result needs no acquire"
        )
        #expect(
            consumes(of: parameter, in: lowered).isEmpty,
            "the pass must neither release nor destroy a moved operand"
        )
        #expect(consumes(of: casted, in: lowered).isEmpty)
        #expect(dischargedLoads(of: slot, in: lowered).count == 1)
        #expect(deallocations(of: slot, in: lowered).count == 1)
        #expect(context.diagnosticEngine.diagnostics.isEmpty)
    }
}

@Test
func copyProducesANewOwnedInstanceAndKeepsTheOperandToken() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodePointer = registry.pointerType(pointee: registry.classType(name: "Node").id).id
    let parameter = TIR.Parameter(ty: nodePointer, name: "n")
    let function = module.addFunction(
        name: "copyStore", parameters: [parameter], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil, parameterOwnership: [.Owned]
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let slot = builder.buildAllocStack(allocatedType: nodePointer, name: "slot").result
    let copied = builder.buildCopy(parameter, name: "copy").result
    builder.buildStore(value: copied, to: slot)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "copyStore" })
    #expect(
        retains(of: copied, in: lowered).isEmpty,
        "a copy already yields a fresh +1, so the store must take it without an acquire"
    )
    #expect(dischargedLoads(of: slot, in: lowered).count == 1)
    #expect(deallocations(of: slot, in: lowered).count == 1)
    #expect(
        releases(of: parameter, in: lowered).count == 1,
        "the operand of a copy keeps its token and is released at the end of its life"
    )
}

@Test
func castOfABorrowedValueIsRetainedAtTheTransferSite() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodePointer = registry.pointerType(pointee: registry.classType(name: "Node").id).id
    let pointerPointer = registry.addressType(pointee: nodePointer).id
    let parameter = TIR.Parameter(ty: pointerPointer, name: "slot")
    let function = module.addFunction(
        name: "borrowCast", parameters: [parameter], returnType: nodePointer,
        isVariadic: false, isExtern: false, callingConvention: nil, parameterOwnership: [.Owned]
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let borrowed = builder.buildLoad(ptr: parameter, name: "borrowed").result
    let casted = builder.buildUpcast(value: borrowed, to: nodePointer).result
    builder.buildReturn(casted)
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "borrowCast" })
    #expect(
        retains(of: casted, in: lowered).count == 1,
        "casting a borrow invents no token, so the transfer site must acquire one"
    )
    #expect(consumes(of: casted, in: lowered).isEmpty)
    #expect(consumes(of: borrowed, in: lowered).isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}

private func upcastConsumerModule() -> (
    Context, TIR.Module, TIR.Parameter, TIR.Value, TIR.Function, TIR.Value
) {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let base = registry.classType(name: "Base")
    let nodePointer = registry.pointerType(pointee: registry.classType(name: "Node").id).id
    let basePointer = registry.pointerType(pointee: base.id).id
    let consumeParameter = TIR.Parameter(ty: nodePointer, name: "n")
    let consume = module.addFunction(
        name: "consume", parameters: [consumeParameter], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil,
        parameterOwnership: [.Owned], resultOwnership: .Owned
    )
    consume.addBasicBlock(name: "entry").instructions.append(TIR.Return())
    let liftParameter = TIR.Parameter(ty: nodePointer, name: "n")
    let lift = module.addFunction(
        name: "lift", parameters: [liftParameter], returnType: basePointer,
        isVariadic: false, isExtern: false, callingConvention: nil,
        parameterOwnership: [.Owned], resultOwnership: .Owned
    )
    let liftEntry = lift.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = liftEntry
    let lifted = builder.buildUpcast(value: liftParameter, to: basePointer, name: "lifted").result
    builder.buildReturn(lifted)
    let callerParameter = TIR.Parameter(ty: nodePointer, name: "n")
    let caller = module.addFunction(
        name: "consumeLifted", parameters: [callerParameter], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil, parameterOwnership: [.Owned]
    )
    let callerEntry = caller.addBasicBlock(name: "entry")
    builder.insertPoint = callerEntry
    let reference = TIR.FunctionRef(functionId: lift.id, ty: lift.ty, name: lift.name)
    let call = builder.buildCall(callee: reference, arguments: [callerParameter], name: "result")
    let consumeReference = TIR.FunctionRef(functionId: consume.id, ty: consume.ty, name: consume.name)
    builder.buildCall(callee: consumeReference, arguments: [call.result!])
    builder.buildReturn()
    return (context, module, liftParameter, lifted, caller, call.result!)
}

@Test
func upcastOfAnOwnedValueIsTransferredToTheCallerWithoutAnAcquire() throws {
    let (context, module, liftParameter, lifted, caller, callResult) = upcastConsumerModule()
    TIRPass().run(on: module)
    let lift = try #require(module.functions.first { $0.name == "lift" })
    #expect(
        retains(of: lifted, in: lift).isEmpty,
        "the upcast result owns the moved token, so returning it needs no acquire"
    )
    #expect(consumes(of: lifted, in: lift).isEmpty)
    #expect(consumes(of: liftParameter, in: lift).isEmpty)
    let loweredCaller = try #require(module.functions.first { $0.name == "consumeLifted" })
    #expect(
        retains(of: callResult, in: loweredCaller).isEmpty,
        "the caller receives the owned upcast and forwards it to an owned parameter"
    )
    #expect(consumes(of: callResult, in: loweredCaller).isEmpty)
    #expect(caller.parameters.count == 1)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

private func branchConsumeOrReturnModule(
    speculativeRetainOnReturn: Bool
) -> (Context, TIR.Module, TIR.Parameter) {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id).id
    let boolType = registry.primitiveType(kind: .Bool, bitWidth: 1).id
    let consumeParameter = TIR.Parameter(ty: nodePointer, name: "n")
    let consume = module.addFunction(
        name: "consume", parameters: [consumeParameter], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil,
        parameterOwnership: [.Owned], resultOwnership: .Owned
    )
    consume.addBasicBlock(name: "entry").instructions.append(TIR.Return())
    let parameter = TIR.Parameter(ty: nodePointer, name: "n")
    let function = module.addFunction(
        name: "branch",
        parameters: [TIR.Parameter(ty: boolType, name: "flag"), parameter],
        returnType: nodePointer, isVariadic: false, isExtern: false, callingConvention: nil,
        parameterOwnership: [.Owned, .Owned], resultOwnership: .Owned
    )
    let entry = function.addBasicBlock(name: "entry")
    let left = function.addBasicBlock(name: "left")
    let right = function.addBasicBlock(name: "right")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    builder.buildConditionalBranch(
        condition: function.parameters[0], trueBranch: left, falseBranch: right
    )
    builder.insertPoint = left
    let reference = TIR.FunctionRef(functionId: consume.id, ty: consume.ty, name: consume.name)
    builder.buildCall(callee: reference, arguments: [parameter])
    let fresh = builder.buildAllocHeap(allocatedType: nodeType.id, name: "fresh").result
    builder.buildReturn(fresh)
    builder.insertPoint = right
    if speculativeRetainOnReturn {
        builder.buildRetain(parameter)
    }
    builder.buildReturn(parameter)
    return (context, module, parameter)
}

@Test
func branchConsumedValueGetsNoSpeculativeAcquireOnTheOtherPath() throws {
    let (context, module, parameter) = branchConsumeOrReturnModule(speculativeRetainOnReturn: false)
    let result = TIRPass().run(on: module)
    #expect(result.failures.isEmpty)
    let lowered = try #require(module.functions.first { $0.name == "branch" })
    let returned = try #require(lowered.parameters.last)
    #expect(returned === parameter)
    #expect(
        ownershipFailures(context, module).isEmpty,
        "a value consumed on one branch must not be treated as consumed on the other, got: \(ownershipFailures(context, module).map(\.message))"
    )
    #expect(
        retains(of: parameter, in: lowered).isEmpty,
        "the branch that transfers the value needs no acquire for it"
    )
    #expect(consumes(of: parameter, in: lowered).isEmpty)
    let left = try #require(lowered.basicBlocks.first { $0.name == "left" })
    let right = try #require(lowered.basicBlocks.first { $0.name == "right" })
    #expect(
        left.instructions.compactMap { $0 as? TIR.Call }.contains { call in
            call.arguments.contains { $0 === parameter }
        }
    )
    #expect(
        right.instructions.compactMap { $0 as? TIR.Return }.contains { $0.value === parameter }
    )
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func speculativeAcquireOnTheUnconsumedBranchIsRejected() throws {
    let (context, module, _) = branchConsumeOrReturnModule(speculativeRetainOnReturn: true)
    let failures = ownershipFailures(context, module)
    #expect(
        failures.contains {
            $0.message.contains("is transferred as an owned result with retain/release balance 2")
        },
        "a retain on the untouched branch must be rejected, got: \(failures.map(\.message))"
    )
}

@Test
func branchConsumedValueIsStoredWithoutAnAcquireOnTheOtherPath() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id).id
    let boolType = registry.primitiveType(kind: .Bool, bitWidth: 1).id
    let consumeParameter = TIR.Parameter(ty: nodePointer, name: "n")
    let consume = module.addFunction(
        name: "consume", parameters: [consumeParameter], returnType: registry.voidType().id,
        isVariadic: false, isExtern: false, callingConvention: nil,
        parameterOwnership: [.Owned], resultOwnership: .Owned
    )
    consume.addBasicBlock(name: "entry").instructions.append(TIR.Return())
    let parameter = TIR.Parameter(ty: nodePointer, name: "n")
    let function = module.addFunction(
        name: "branchStore",
        parameters: [TIR.Parameter(ty: boolType, name: "flag"), parameter],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false,
        callingConvention: nil, parameterOwnership: [.Owned, .Owned]
    )
    let global = module.addGlobal(
        name: "g", type: nodePointer, isExtern: false, hasInitializer: false
    )
    let entry = function.addBasicBlock(name: "entry")
    let left = function.addBasicBlock(name: "left")
    let right = function.addBasicBlock(name: "right")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    builder.buildConditionalBranch(
        condition: function.parameters[0], trueBranch: left, falseBranch: right
    )
    builder.insertPoint = left
    let reference = TIR.FunctionRef(functionId: consume.id, ty: consume.ty, name: consume.name)
    builder.buildCall(callee: reference, arguments: [parameter])
    builder.buildReturn()
    builder.insertPoint = right
    let address = builder.buildGlobalAddr(global: global)
    let store = builder.buildStore(value: parameter, to: address)
    builder.buildReturn()
    TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "branchStore" })
    #expect(
        retains(of: parameter, in: lowered).isEmpty,
        "the storing branch still holds the token, so the store takes it without an acquire"
    )
    #expect(consumes(of: parameter, in: lowered).isEmpty)
    #expect(
        lowered.basicBlocks.compactMap { $0.instructions.first { $0 === store } as? TIR.Store }
            .contains { $0.value === parameter }
    )
    #expect(strictFailures(context, module).isEmpty)
}

private func unsplittableDischargeModule() -> (
    Context, TIR.Module, TIR.Function, TIR.BasicBlock, TIR.Instruction, TIR.Value
) {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodePointer = registry.pointerType(pointee: registry.classType(name: "Node").id).id
    let boolType = registry.primitiveType(kind: .Bool, bitWidth: 1).id
    let calleeParameter = TIR.Parameter(ty: nodePointer, name: "n")
    let callee = module.addFunction(
        name: "callee", parameters: [calleeParameter], returnType: nodePointer,
        isVariadic: false, isExtern: false, callingConvention: nil,
        parameterOwnership: [.Guaranteed], resultOwnership: .Guaranteed
    )
    callee.addBasicBlock(name: "entry").instructions.append(TIR.Return(value: calleeParameter))
    let parameter = TIR.Parameter(ty: nodePointer, name: "n")
    let function = module.addFunction(
        name: "tryEdge",
        parameters: [TIR.Parameter(ty: boolType, name: "flag"), parameter],
        returnType: registry.voidType().id, isVariadic: false, isExtern: false,
        callingConvention: nil, parameterOwnership: [.Owned, .Owned]
    )
    let entry = function.addBasicBlock(name: "entry")
    let dirty = function.addBasicBlock(name: "dirty")
    let success = function.addBasicBlock(name: "success")
    let failure = function.addBasicBlock(name: "failure")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let slot = builder.buildAllocStack(allocatedType: nodePointer, name: "slot").result
    builder.buildConditionalBranch(
        condition: function.parameters[0], trueBranch: dirty, falseBranch: success
    )
    builder.insertPoint = dirty
    builder.buildStore(value: parameter, to: slot)
    let reference = TIR.FunctionRef(functionId: callee.id, ty: callee.ty, name: callee.name)
    let tryCall = builder.buildTryCall(
        callee: reference, arguments: [], successBlock: success, errorBlock: failure
    )
    builder.insertPoint = success
    builder.buildReturn()
    builder.insertPoint = failure
    builder.buildReturn()
    return (context, module, function, dirty, tryCall, slot)
}

private func knownSourceRange(_ context: Context, filepath: String, offset: Int = 4) -> SourceRange {
    let source = Source(id: context.nextSourceId, filepath: filepath, content: "0123456789")
    context.register(source: source)
    let location = SourceLocation(
        buffer: source.stringSourceBuffer, offset: offset, line: 1, column: offset + 1
    )
    return SourceRange(location: location)
}

@Test
func unsplittableEdgeDischargeIsReportedInsteadOfSkipped() throws {
    let (context, module, _, _, _, slot) = unsplittableDischargeModule()
    let result = TIRPass().run(on: module)
    let reported = try #require(result.failures.first)
    #expect(result.failures.count == 1)
    #expect(reported.slotName == slot.name)
    #expect(reported.functionName == "tryEdge")
    #expect(reported.fromBlockName == "dirty")
    #expect(reported.toBlockName == "success")
    #expect(reported.message.contains("cannot discharge live slot '\(slot.name)'"))
    #expect(reported.message.contains("of function 'tryEdge'"))
    #expect(reported.message.contains("on the edge from 'dirty' to 'success'"))
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func unsplittableFailureCarriesTheTerminatorSourceRange() throws {
    let (context, module, _, _, tryCall, _) = unsplittableDischargeModule()
    let terminatorRange = knownSourceRange(context, filepath: "terminator.truss")
    tryCall.sourceRange = terminatorRange
    let result = TIRPass().run(on: module)
    let reported = try #require(result.failures.first)
    #expect(reported.sourceRange == terminatorRange)
}

@Test
func unsplittableFailureFallsBackToTheBlockSourceRange() throws {
    let (context, module, _, dirty, _, _) = unsplittableDischargeModule()
    let blockRange = knownSourceRange(context, filepath: "block.truss", offset: 2)
    dirty.sourceRange = blockRange
    let result = TIRPass().run(on: module)
    let reported = try #require(result.failures.first)
    #expect(reported.sourceRange == blockRange)
}

@Test
func unsplittableFailureFallsBackToTheFunctionSourceRange() throws {
    let (context, module, function, _, _, _) = unsplittableDischargeModule()
    let functionRange = knownSourceRange(context, filepath: "function.truss", offset: 6)
    function.sourceRange = functionRange
    let result = TIRPass().run(on: module)
    let reported = try #require(result.failures.first)
    #expect(reported.sourceRange == functionRange)
}

@Test
func driverSeamEmitsOneErrorDiagnosticPerFailureWithItsRange() throws {
    let (context, module, _, _, tryCall, _) = unsplittableDischargeModule()
    let terminatorRange = knownSourceRange(context, filepath: "driver_seam.truss")
    tryCall.sourceRange = terminatorRange
    let result = TIRPass().run(on: module)
    let reported = try #require(result.failures.first)
    #expect(!context.diagnosticEngine.hasErrors)
    TIRPass.emitFailures(result.failures, in: context)
    #expect(context.diagnosticEngine.hasErrors)
    #expect(context.diagnosticEngine.diagnostics.count == result.failures.count)
    let diagnostic = try #require(context.diagnosticEngine.diagnostics.first)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.message == reported.message)
    #expect(diagnostic.message.contains(reported.slotName))
    #expect(diagnostic.message.contains("tryEdge"))
    #expect(diagnostic.message.contains(reported.fromBlockName))
    #expect(diagnostic.message.contains(reported.toBlockName))
    #expect(diagnostic.range == terminatorRange)
    let other = TIRPassFailure(
        functionName: reported.functionName, slotName: "other",
        fromBlockName: reported.fromBlockName, toBlockName: reported.toBlockName,
        sourceRange: terminatorRange
    )
    TIRPass.emitFailures([other], in: context)
    #expect(context.diagnosticEngine.diagnostics.count == result.failures.count + 1)
    #expect(context.diagnosticEngine.diagnostics.last?.message == other.message)
}

@Test
func exhaustedSplitAttemptsReportEveryRemainingPendingDischarge() throws {
    let (_, module, _, _, _, slot) = unsplittableDischargeModule()
    let splitter = EdgeDischargeSplitter(registry: module.registry, attemptLimit: 0)
    let discharges = splitter.split(module: module)
    #expect(discharges.isEmpty)
    #expect(splitter.failures.count == 1)
    let reported = try #require(splitter.failures.first)
    #expect(reported.slotName == slot.name)
    #expect(reported.functionName == "tryEdge")
    #expect(reported.fromBlockName == "dirty")
    #expect(reported.toBlockName == "success")
}

@Test
func splittableEdgeDischargesReportNoFailures() throws {
    let (context, module, _) = branchConsumeOrReturnModule(speculativeRetainOnReturn: false)
    let result = TIRPass().run(on: module)
    #expect(result.failures.isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}

@Test
func closureCalleeOwnershipFollowsItsSignature() throws {
    let context = Context()
    let registry = TIR.Registry()
    let module = TIR.Module(registry: registry)
    let nodeType = registry.classType(name: "Node")
    let nodePointer = registry.pointerType(pointee: nodeType.id)
    let slot = registry.addressType(pointee: nodePointer.id)
    let closureType = registry.closureType(
        parameters: [nodePointer.id], returnType: nodePointer.id, isVariadic: false
    )
    let function = module.addFunction(
        name: "callClosure",
        parameters: [
            TIR.Parameter(ty: closureType.id, name: "body"),
            TIR.Parameter(ty: slot.id, name: "slot"),
        ],
        returnType: nodePointer.id, isVariadic: false, isExtern: false, callingConvention: nil
    )
    let entry = function.addBasicBlock(name: "entry")
    let builder = TIR.Builder(registry: registry)
    builder.insertPoint = entry
    let borrowed = builder.buildLoad(ptr: function.parameters[1], name: "borrowed").result
    let call = builder.buildCall(callee: function.parameters[0], arguments: [borrowed])
    builder.buildReturn(call.result)
    let result = TIRPass().run(on: module)
    let lowered = try #require(module.functions.first { $0.name == "callClosure" })
    #expect(retains(of: borrowed, in: lowered).count == 1)
    #expect(result.failures.isEmpty)
    #expect(strictFailures(context, module).isEmpty)
}
