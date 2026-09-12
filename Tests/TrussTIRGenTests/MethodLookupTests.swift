import Testing
import TrussCore

@Suite struct MethodLookupTests {
    @Test func virtualMethodYieldsFunctionValue() {
        let registry = TIR.Registry()
        let classType = registry.classType(name: "$tmain_1C")
        let metadata = registry.addMetadata(name: "$tmain_1C")
        let functionType = registry.functionType(
            parameters: [], returnType: registry.voidType().id, isVariadic: false
        )
        let module = TIR.Module(registry: registry)
        let f = module.addFunction(
            name: "f", parameters: [], returnType: registry.voidType().id, isVariadic: false,
            isExtern: false, callingConvention: nil
        )
        let block = f.addBasicBlock(name: "entry")
        let builder = TIR.Builder(registry: registry)
        builder.insertPoint = block
        let selfValue = builder.buildAllocStack(allocatedType: classType.id, name: "self")
        let method = builder.buildVirtualMethod(
            metadata: metadata.id, index: 2, selfValue: selfValue.result, ty: functionType.id,
            name: "m"
        )
        #expect(method.result.ty == functionType.id)
        #expect(method.selfValue === selfValue.result)
        let dump = TIR.Dumper().dump(module)
        #expect(dump.contains("%m = virtualmethod %$tmain_1C#0.2(%self)"))
    }

    @Test func witnessMethodYieldsFunctionValue() {
        let registry = TIR.Registry()
        let functionType = registry.functionType(
            parameters: [], returnType: registry.voidType().id, isVariadic: false
        )
        let protocolRecord = registry.addProtocol(name: "$tmain_1P")
        let concreteType = registry.structType(name: "$tmain_1S")
        let witness = registry.addWitness(
            protocolId: protocolRecord.id, concreteType: concreteType.id
        )
        let module = TIR.Module(registry: registry)
        let f = module.addFunction(
            name: "f", parameters: [], returnType: registry.voidType().id, isVariadic: false,
            isExtern: false, callingConvention: nil
        )
        let block = f.addBasicBlock(name: "entry")
        let builder = TIR.Builder(registry: registry)
        builder.insertPoint = block
        let method = builder.buildWitnessMethod(
            witness: witness.id, index: 1, ty: functionType.id, name: "m"
        )
        #expect(method.result.ty == functionType.id)
        let dump = TIR.Dumper().dump(module)
        #expect(dump.contains("%m = witnessmethod %$tmain_1S:$tmain_1P#0.1"))
    }

    @Test func opaqueWitnessMethodYieldsFunctionValue() {
        let registry = TIR.Registry()
        let functionType = registry.functionType(
            parameters: [], returnType: registry.voidType().id, isVariadic: false
        )
        let protocolRecord = registry.addProtocol(name: "$tmain_1P")
        let concreteType = registry.structType(name: "$tmain_1S")
        let module = TIR.Module(registry: registry)
        let f = module.addFunction(
            name: "f", parameters: [], returnType: registry.voidType().id, isVariadic: false,
            isExtern: false, callingConvention: nil
        )
        let block = f.addBasicBlock(name: "entry")
        let builder = TIR.Builder(registry: registry)
        builder.insertPoint = block
        let container = builder.buildAllocStack(allocatedType: concreteType.id, name: "container")
        let method = builder.buildOpaqueWitnessMethod(
            container: container.result, protocolId: protocolRecord.id, index: 0,
            ty: functionType.id, name: "m"
        )
        #expect(method.result.ty == functionType.id)
        let dump = TIR.Dumper().dump(module)
        #expect(dump.contains("%m = opaquewitnessmethod %container %$tmain_1P#0.0"))
    }

    @Test func vtableEntriesCarryMethodSignatures() throws {
        let tir = dumpTIR(
            """
            class Animal {
                func speak(x: Dog) { return }
            }
            class Dog: Animal {
                func bark() { return }
            }
            func ping(a: Animal, d: Dog) { return }
            """
        )
        let dog = try #require(
            tir.components(separatedBy: "\n").first { $0.contains("Dog = vtable [") }
        )
        try #require(dog.contains("0: speak (%$t4main_3Dog) -> void"))
        try #require(dog.contains("1: bark () -> void"))
    }
}
