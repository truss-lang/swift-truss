import Testing
import TrussCore
import TrussTIRGen

@Test
func closureTypeInterningDeduplicatesBySignature() throws {
    let registry = TIR.Registry()
    let void = registry.voidType().id
    let i32 = registry.integerType(isSigned: true, bitWidth: 32).id
    let first = registry.closureType(parameters: [i32], returnType: void, isVariadic: false)
    let second = registry.closureType(parameters: [i32], returnType: void, isVariadic: false)
    #expect(first === second)
    #expect(first.id == second.id)
    let differentReturn = registry.closureType(parameters: [i32], returnType: i32, isVariadic: false)
    let differentParameters = registry.closureType(parameters: [], returnType: void, isVariadic: false)
    let variadic = registry.closureType(parameters: [i32], returnType: void, isVariadic: true)
    let guaranteed = registry.closureType(
        parameters: [i32], returnType: void, isVariadic: false, parameterOwnership: [.Guaranteed]
    )
    #expect(first.id != differentReturn.id)
    #expect(first.id != differentParameters.id)
    #expect(first.id != variadic.id)
    #expect(first.id != guaranteed.id)
    let stored = try #require(registry.type(first.id))
    #expect(stored is TIRType.ClosureType)
    #expect(!(stored is TIRType.FunctionType))
    let function = registry.functionType(parameters: [i32], returnType: void, isVariadic: false)
    #expect(function.id != first.id)
    #expect(registry.type(function.id) is TIRType.FunctionType)
}

@Test
func typeLowerMapsClosureAndFunctionTypesToDistinctTIRTypes() throws {
    let source = """
    typealias Int32 = Builtin.Int32

    func takeClosure(_ body: (Int32) -> Int32) -> Int32 {
        return 0
    }

    func takeFunction(_ body: func(Int32) -> Int32) -> Int32 {
        return 0
    }
    """
    let (context, module) = runTIRGen(source)
    #expect(!context.diagnosticEngine.hasErrors)
    let closureFunction = try #require(module.functions.first { $0.name.contains("takeClosure") })
    let functionFunction = try #require(module.functions.first { $0.name.contains("takeFunction") })
    let closureParameter = try #require(closureFunction.parameters.first)
    let functionParameter = try #require(functionFunction.parameters.first)
    let closureType = try #require(module.registry.types[closureParameter.ty] as? TIRType.ClosureType)
    let functionType = try #require(module.registry.types[functionParameter.ty] as? TIRType.FunctionType)
    #expect(closureType.parameters.count == 1)
    #expect(closureType.parameters[0] == registryInteger(module: module, bitWidth: 32))
    #expect(closureType.returnType == registryInteger(module: module, bitWidth: 32))
    #expect(functionType.parameters.count == 1)
    #expect(closureType.id != functionType.id)
}

@Test
func closureSignaturesMangleWithADistinctTag() throws {
    let source = """
    typealias Int32 = Builtin.Int32

    func takeA(_ body: (Int32) -> Int32) -> Int32 {
        return 0
    }

    func takeB(_ body: func(Int32) -> Int32) -> Int32 {
        return 0
    }

    func takeC(_ body: () -> Int32) -> Int32 {
        return 0
    }
    """
    let (_, module) = runTIRGen(source)
    let closureWithParameter = try #require(module.functions.first { $0.name.contains("takeA") })
    let functionWithParameter = try #require(module.functions.first { $0.name.contains("takeB") })
    let closureWithoutParameter = try #require(module.functions.first { $0.name.contains("takeC") })
    #expect(closureWithParameter.name.contains("K"))
    #expect(!closureWithParameter.name.contains("F"))
    #expect(functionWithParameter.name.contains("F"))
    #expect(!functionWithParameter.name.contains("K"))
    #expect(closureWithParameter.name != functionWithParameter.name)
    #expect(closureWithParameter.name != closureWithoutParameter.name)
}

@Test
func variadicClosureSignaturesMangleWithADistinctMarker() throws {
    let source = """
    typealias Int32 = Builtin.Int32

    func pick(_ body: (Int32) -> Int32) -> Int32 {
        return 0
    }

    func pick(_ body: (Int32...) -> Int32) -> Int32 {
        return 0
    }
    """
    let (context, module) = runTIRGen(source)
    #expect(!context.diagnosticEngine.hasErrors)
    let picked = module.functions.filter { $0.name.contains("pick") }
    #expect(picked.count == 2)
    #expect(Set(picked.map(\.name)).count == 2)
    #expect(picked.contains { $0.name.contains("VR") })
    #expect(picked.contains { !$0.name.contains("VR") })
}

@Test
func functionToClosureConversionsLowerToClosureTypedValues() throws {
    let source = """
    typealias Int32 = Builtin.Int32

    func id(x: Int32) -> Int32 {
        return x
    }

    func apply(f: (Int32) -> Int32) -> Int32 {
        return 1
    }

    func make() -> (Int32) -> Int32 {
        return id
    }

    func main() -> Int32 {
        let g: (Int32) -> Int32 = id
        let made = make()
        return apply(f: id)
    }
    """
    let (context, module) = runTIRGen(source)
    #expect(!context.diagnosticEngine.hasErrors)
    #expect(TIR.Verifier(context: context).verify(module).isEmpty)
    let closureTypes = module.registry.types.values.compactMap { $0 as? TIRType.ClosureType }
    #expect(!closureTypes.isEmpty)
    let closureIDs = Set(closureTypes.map(\.id))
    let closureValues = instructions(of: module).compactMap { $0 as? TIR.Closure }
        .filter { closureIDs.contains($0.result.ty) }
    #expect(closureValues.count >= 3)
    let makeFunction = try #require(module.functions.first { $0.name.contains("make") })
    #expect(module.registry.types[makeFunction.returnType] is TIRType.ClosureType)
}

private func registryInteger(module: TIR.Module, bitWidth: Int) -> Id.TIRTypeId {
    module.registry.integerType(isSigned: true, bitWidth: bitWidth).id
}
