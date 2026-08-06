import Testing
import TrussCore
import TrussSemantics

@Test func buildsStructType() throws {
    let (context, programs) = runTypeBuilder(["struct S {}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let symbol = try #require(structDecl.symbol)
    let typeId = try #require(symbol.typeId)
    let builtType = try #require(context.typeTable[typeId])
    #expect(builtType is TrussType.StructType)
    #expect((builtType as! TrussType.StructType).name == "S")
    #expect((builtType as! TrussType.StructType).symbol === symbol)
}

@Test func buildsAllNominalKinds() throws {
    let (context, programs) = runTypeBuilder(["""
    struct S {}
    class C {}
    enum E {}
    protocol P {}
    actor A {}
    """])
    let program = programs[0]
    let structSymbol = try #require((program.statements[0] as! AST.StructDecl).symbol)
    let classSymbol = try #require((program.statements[1] as! AST.ClassDecl).symbol)
    let enumSymbol = try #require((program.statements[2] as! AST.EnumDecl).symbol)
    let protocolSymbol = try #require((program.statements[3] as! AST.ProtocolDecl).symbol)
    let actorSymbol = try #require((program.statements[4] as! AST.ActorDecl).symbol)
    let cases: [(Symbol.NominalTypeSymbol, TrussType.TrussType.Type)] = [
        (structSymbol, TrussType.StructType.self),
        (classSymbol, TrussType.ClassType.self),
        (enumSymbol, TrussType.EnumType.self),
        (protocolSymbol, TrussType.ProtocolType.self),
        (actorSymbol, TrussType.ActorType.self),
    ]
    for (symbol, kind) in cases {
        let builtType = try #require(context.typeTable[symbol.typeId!])
        #expect(type(of: builtType) == kind)
        #expect((builtType as! TrussType.NominalType).name == symbol.name)
        #expect((builtType as! TrussType.NominalType).symbol === symbol)
    }
}

@Test func skipsTypeAlias() {
    let (context, _) = runTypeBuilder(["typealias X = Int32"])
    #expect(context.typeTable.isEmpty)
}

@Test func skipsBuiltins() {
    let (context, _) = runTypeBuilder(["struct S {}\nlet v: Void = f()"])
    #expect(context.typeTable.count == 1)
    #expect(context.typeTable.values.allSatisfy { $0 is TrussType.StructType })
}

@Test func buildsNestedTypes() throws {
    let (context, programs) = runTypeBuilder(["struct Outer { struct Inner {} }"])
    let outerDecl = programs[0].statements[0] as! AST.StructDecl
    let innerDecl = try #require(outerDecl.body.first as? AST.StructDecl)
    let outerTypeId = try #require(outerDecl.symbol?.typeId)
    let innerTypeId = try #require(innerDecl.symbol?.typeId)
    #expect(context.typeTable.count == 2)
    #expect(context.typeTable[outerTypeId] is TrussType.StructType)
    #expect(context.typeTable[innerTypeId] is TrussType.StructType)
}

@Test func sharedAcrossPrograms() {
    let (context, _) = runTypeBuilder(["struct A {}", "struct B {}"])
    #expect(context.typeTable.count == 2)
    #expect(context.typeTable.values.contains { ($0 as! TrussType.NominalType).name == "A" })
    #expect(context.typeTable.values.contains { ($0 as! TrussType.NominalType).name == "B" })
}

@Test func fieldsDefaultEmpty() throws {
    let (context, programs) = runTypeBuilder(["class C: P {}\nprotocol P {}"])
    let classDecl = programs[0].statements[0] as! AST.ClassDecl
    let typeId = try #require(classDecl.symbol?.typeId)
    let classType = try #require(context.typeTable[typeId]) as! TrussType.ClassType
    #expect(classType.superclass == nil)
    #expect(classType.conformances.isEmpty)
}
