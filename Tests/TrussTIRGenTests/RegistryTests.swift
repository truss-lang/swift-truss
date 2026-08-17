import Testing
import TrussCore

@Suite struct RegistryTests {
    @Test func sameStructureDedupedToSameId() {
        let registry = TIR.Registry()
        let intId = registry.integerType(isSigned: true, bitWidth: 64).id
        let ptr1 = registry.pointerType(pointee: intId).id
        let ptr2 = registry.pointerType(pointee: intId).id
        #expect(ptr1 == ptr2)
        #expect(registry.types.count == 2)
    }

    @Test func differentStructuresDifferentIds() {
        let registry = TIR.Registry()
        let i32 = registry.integerType(isSigned: true, bitWidth: 32).id
        let i64 = registry.integerType(isSigned: true, bitWidth: 64).id
        let ptr32 = registry.pointerType(pointee: i32).id
        let ptr64 = registry.pointerType(pointee: i64).id
        #expect(ptr32 != ptr64)
    }

    @Test func voidTypeReusesSingleId() {
        let registry = TIR.Registry()
        let id1 = registry.voidType().id
        let id2 = registry.voidType().id
        #expect(id1 == id2)
        #expect(registry.type(id1) is TIRType.VoidType)
    }

    @Test func tupleLabelParticipatesInKey() {
        let registry = TIR.Registry()
        let intId = registry.integerType(isSigned: true, bitWidth: 32).id
        let labeled = registry.tupleType(
            elements: [TIRType.TupleType.Element(label: "x", type: intId)]
        ).id
        let unlabeled = registry.tupleType(
            elements: [TIRType.TupleType.Element(label: nil, type: intId)]
        ).id
        #expect(labeled != unlabeled)
    }

    @Test func nominalTypeKeyedByName() {
        let registry = TIR.Registry()
        let a1 = registry.structType(name: "A").id
        let a2 = registry.structType(name: "A").id
        let b = registry.structType(name: "B").id
        #expect(a1 == a2)
        #expect(a1 != b)
    }

    @Test func fieldTypeIdsResolveInRegistry() {
        let registry = TIR.Registry()
        let intId = registry.integerType(isSigned: true, bitWidth: 32).id
        let structType = registry.structType(name: "S")
        structType.fields = [(name: "x", type: intId)]
        #expect(registry.type(structType.fields[0].type) is TIRType.PrimitiveType)
    }

    @Test func functionIdsAllocatedByRegistry() {
        let registry = TIR.Registry()
        let voidId = registry.voidType().id
        let module = TIR.Module(registry: registry)
        let f = module.addFunction(
            name: "f", parameters: [], returnType: voidId, isVariadic: false, isExtern: false,
            callingConvention: nil
        )
        #expect(f.id == Id.TIRFunctionId(0))
        #expect(registry.functions[f.id] === f)
        let g = module.addFunction(
            name: "g", parameters: [], returnType: voidId, isVariadic: false, isExtern: false,
            callingConvention: nil
        )
        #expect(g.id == Id.TIRFunctionId(1))
        #expect(registry.functions.count == 2)
    }

    @Test func unresolvedIdReturnsNil() {
        let registry = TIR.Registry()
        #expect(registry.type(Id.TIRTypeId(99)) == nil)
    }
}
