import Testing
import TrussCore

@Suite struct RegistryTests {
    @Test func sameStructureDedupedToSameId() {
        let registry = TIR.Registry()
        let intId = registry.registerType(TIRType.PrimitiveType(kind: .Signed, bitWidth: 64))
        let id1 = registry.registerType(TIRType.OptionalType(intId))
        let id2 = registry.registerType(TIRType.OptionalType(intId))
        #expect(id1 == id2)
        #expect(registry.types.count == 2)
    }

    @Test func differentStructuresDifferentIds() {
        let registry = TIR.Registry()
        let i32 = registry.registerType(TIRType.PrimitiveType(kind: .Signed, bitWidth: 32))
        let i64 = registry.registerType(TIRType.PrimitiveType(kind: .Signed, bitWidth: 64))
        let opt32 = registry.registerType(TIRType.OptionalType(i32))
        let opt64 = registry.registerType(TIRType.OptionalType(i64))
        #expect(opt32 != opt64)
    }

    @Test func voidTypeReusesSingleId() {
        let registry = TIR.Registry()
        let id1 = registry.registerType(TIRType.VoidType())
        let id2 = registry.registerType(TIRType.VoidType())
        #expect(id1 == id2)
        #expect(registry.type(id1) is TIRType.VoidType)
    }

    @Test func tupleLabelParticipatesInKey() {
        let registry = TIR.Registry()
        let intId = registry.registerType(TIRType.PrimitiveType(kind: .Signed, bitWidth: 32))
        let labeled = registry.registerType(
            TIRType.TupleType([TIRType.TupleType.Element(label: "x", type: intId)])
        )
        let unlabeled = registry.registerType(
            TIRType.TupleType([TIRType.TupleType.Element(label: nil, type: intId)])
        )
        #expect(labeled != unlabeled)
    }

    @Test func nominalTypeKeyedByTypeId() {
        let registry = TIR.Registry()
        let a = TIRType.StructType(Id.TypeId(id: 1), "A")
        let b = TIRType.StructType(Id.TypeId(id: 1), "A")
        let id1 = registry.registerType(a)
        let id2 = registry.registerType(b)
        #expect(id1 == id2)
    }

    @Test func fieldTypeIdsResolveInRegistry() {
        let registry = TIR.Registry()
        let intId = registry.registerType(TIRType.PrimitiveType(kind: .Signed, bitWidth: 32))
        let structType = TIRType.StructType(Id.TypeId(id: 7), "S")
        registry.registerType(structType)
        structType.fields = [(name: "x", type: intId)]
        #expect(registry.type(structType.fields[0].type) is TIRType.PrimitiveType)
    }

    @Test func functionIdsAllocatedByRegistry() {
        let registry = TIR.Registry()
        let voidId = registry.registerType(TIRType.VoidType())
        let f = TIR.Function(name: "f", returnType: voidId)
        let id = registry.registerFunction(f)
        #expect(id == 0)
        #expect(f.id == id)
        #expect(registry.functions[id] === f)
        let g = TIR.Function(name: "g", returnType: voidId)
        let gid = registry.registerFunction(g)
        #expect(gid == 1)
        #expect(registry.functions.count == 2)
    }

    @Test func unresolvedIdReturnsNil() {
        let registry = TIR.Registry()
        #expect(registry.type(99) == nil)
    }
}
