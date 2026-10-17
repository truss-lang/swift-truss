import Testing
import TrussCore
import TrussTIRGen

private let metadataSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

class Plain {
    var value: Int32 = 0
    init() { return }
}

class Cleanup {
    var value: Int32 = 0
    init() { return }
    deinit { return }
}

class Node {
    var value: Int32 = 0
    init() { return }
}

class Holder {
    var child: Node = Node()
    init() { return }
}
"""

@Test
func metadataRecordsCarryDefaultsForUnrelatedShapes() {
    let record = TIR.MetadataRecord(id: Id.TIRMetadataId(0), name: "Untracked")
    #expect(record.typeId == nil)
    #expect(record.hasRealDeinitializer == false)
}

@Test
func metadataRecordsCarryTypeIdentityAndTeardownKind() throws {
    let (_, module) = runTIRGen(metadataSource)
    let registry = module.registry
    let expected: [String: Bool] = [
        "Cleanup": true,
        "Holder": true,
        "Node": false,
        "Plain": false,
    ]
    for (name, hasRealDeinitializer) in expected {
        let record = try #require(registry.metadatas.values.first { $0.name == name })
        let typeId = try #require(record.typeId)
        let classType = try #require(registry.types[typeId] as? TIRType.ClassType)
        #expect(classType.displayText == name)
        #expect(record.hasRealDeinitializer == hasRealDeinitializer)
        let entry = try #require(record.vtable.first)
        #expect(entry.name == "deinit")
        let function = try #require(registry.functions[entry.function])
        #expect((function.name == "$t_noop_deinit") == !hasRealDeinitializer)
    }
}
