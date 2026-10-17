import Testing
import TrussCore
import TrussTIRGen

private let preamble = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32
"""

private let defaultInitializerSource = preamble + """

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Holder {
    var child: C = C()
}

class Holder2 {
    var child: C = C()
    init() { return }
    deinit { return }
}

func makeHolder() -> Holder {
    return Holder()
}

func makeHolder2() -> Holder2 {
    return Holder2()
}
"""

private func initializer(named name: String, in module: TIR.Module) -> TIR.Function? {
    module.functions.first { $0.name.contains(name) && $0.name.contains("_4init_") }
}

@Test
func defaultInitializerConstructsAndStoresDefaultReferenceFields() throws {
    let (_, modules) = runTIRGenModules([defaultInitializerSource])
    let module = try #require(modules.first)
    let holderInit = try #require(initializer(named: "6Holder", in: module))
    let instructions = holderInit.basicBlocks.flatMap(\.instructions)
    let allocations = instructions.compactMap { $0 as? TIR.AllocHeap }
    #expect(allocations.count == 1)
    let calls = instructions.compactMap { $0 as? TIR.Call }
    #expect(calls.contains { ($0.callee as? TIR.FunctionRef)?.name.contains("_1C_4init_") == true })
    let fieldAddresses = instructions.compactMap { $0 as? TIR.ClassElementAddr }
    #expect(fieldAddresses.count == 1)
    let stores = instructions.compactMap { $0 as? TIR.Store }
    #expect(stores.contains { $0.ptr === fieldAddresses[0].result })
    let makeHolder = try #require(function(named: "makeHolder", in: module))
    let makeHolderInstructions = makeHolder.basicBlocks.flatMap(\.instructions)
    #expect(makeHolderInstructions.contains { $0 is TIR.AllocHeap })
    #expect(
        makeHolderInstructions.compactMap { $0 as? TIR.Call }
            .contains { ($0.callee as? TIR.FunctionRef)?.name == holderInit.name }
    )
}

@Test
func explicitInitializerEmitsDefaultFieldInitializers() throws {
    let (_, modules) = runTIRGenModules([defaultInitializerSource])
    let module = try #require(modules.first)
    let holder2Init = try #require(initializer(named: "7Holder2", in: module))
    let instructions = holder2Init.basicBlocks.flatMap(\.instructions)
    #expect(instructions.contains { $0 is TIR.AllocHeap })
    let fieldAddresses = instructions.compactMap { $0 as? TIR.ClassElementAddr }
    #expect(fieldAddresses.count == 1)
    #expect(instructions.compactMap { $0 as? TIR.Store }.contains { $0.ptr === fieldAddresses[0].result })
    #expect(module.functions.filter { $0.name.contains("7Holder2") && $0.name.contains("_4init_") }.count == 1)
    let record = try #require(module.registry.metadatas.values.first { $0.name == "Holder2" })
    let entry = try #require(record.vtable.first)
    #expect(module.registry.functions[entry.function]?.name.contains("7Holder2_6deinit") == true)
}

private let moduleASource = preamble + """

class C {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Holder {
    var child: C = C()
}
"""

private let moduleBSource = """
func makeHolder() -> Holder {
    return Holder()
}
"""

@Test
func memberlessClassKeepsItsWrappersInItsOwnModule() throws {
    let (_, modules) = runTIRGenModules([moduleASource, moduleBSource])
    #expect(modules.count == 2)
    let moduleA = try #require(modules.first)
    let moduleB = try #require(modules.dropFirst().first)
    let holderInit = try #require(initializer(named: "6Holder", in: moduleA))
    #expect(holderInit.module === moduleA)
    let wrapper = try #require(
        moduleA.functions.first { $0.name.contains("field_deinit") && $0.name.contains("6Holder") }
    )
    #expect(wrapper.module === moduleA)
    #expect(!moduleB.functions.contains { $0.name.contains("field_deinit") })
    let record = try #require(moduleA.registry.metadatas.values.first { $0.name == "Holder" })
    let entry = try #require(record.vtable.first)
    #expect(moduleA.registry.functions[entry.function]?.module === moduleA)
    #expect(entry.function == wrapper.id)
}

private let determinismSource = preamble + """

protocol Sorted {
    func zulu() -> Int32
    func alpha() -> Int32
}

class Zeta {
    var value: Int32 = 0
    init() { return }
    func zulu() -> Int32 { return 1 }
    func alpha() -> Int32 { return 2 }
    func middle() -> Int32 { return 3 }
}

class Alpha: Sorted {
    init() { return }
    func zulu() -> Int32 { return 1 }
    func alpha() -> Int32 { return 2 }
}
"""

@Test
func vtableAndWitnessEmissionUsesStableOrder() throws {
    let (_, modules) = runTIRGenModules([determinismSource])
    let module = try #require(modules.first)
    let zeta = try #require(module.registry.metadatas.values.first { $0.name == "Zeta" })
    #expect(zeta.vtable.map(\.name) == ["deinit", "alpha", "middle", "zulu"])
    let alpha = try #require(module.registry.metadatas.values.first { $0.name == "Alpha" })
    #expect(alpha.vtable.map(\.name) == ["deinit", "alpha", "zulu"])
    let conformedNames = alpha.conformedProtocols.compactMap { module.registry.protocols[$0]?.name }
    #expect(conformedNames == ["$t4main_6Sorted"])
    let witness = try #require(module.registry.witnesses.values.first)
    #expect(witness.entries.map(\.name) == ["alpha", "zulu"])
}
