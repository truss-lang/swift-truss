import Testing
import TrussCore
import TrussSemantics

@Test func defaultAccessIsInternal() {
    let (_, programs) = runEnter(["let x"])
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.access == .Internal)
    #expect(variableDecl.symbol?.setterAccess == nil)
}

@Test func publicStructAccess() {
    let (_, programs) = runEnter(["public struct S {}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    #expect(structDecl.symbol?.access == .Public)
}

@Test func privateSetterOnly() {
    let (_, programs) = runEnter(["struct S {\n    private(set) var x\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let body = structDecl.body[0] as! AST.VariableDecl
    #expect(body.symbol?.access == .Internal)
    #expect(body.symbol?.setterAccess == .Private)
}

@Test func publicPrivateSetter() {
    let (_, programs) = runEnter(["public struct S {\n    public private(set) var x\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let body = structDecl.body[0] as! AST.VariableDecl
    #expect(body.symbol?.access == .Public)
    #expect(body.symbol?.setterAccess == .Private)
}

@Test func duplicateAccessModifier() {
    let (context, _) = runEnter(["public private struct S {}"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("duplicate access modifier 'private'"))
}

@Test func setterBroaderThanGetter() {
    let (context, _) = runEnter(["struct S {\n    private public(set) var x\n}"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(
        messages.contains(
            "setter access level 'public' cannot be broader than getter access level 'private'"
        )
    )
}

@Test func memberSymbolsRecordOwnerType() {
    let (_, programs) = runEnter(["struct S {\n    func f() {}\n    let v\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let structId = structDecl.symbol?.id
    let functionDecl = structDecl.body[0] as! AST.FunctionDecl
    let variableDecl = structDecl.body[1] as! AST.VariableDecl
    #expect(functionDecl.symbol?.memberOf == structId)
    #expect(variableDecl.symbol?.memberOf == structId)
    #expect(functionDecl.symbol?.packageId == programs[0].packageSymbol?.id)
}

@Test func moduleSymbolRecorded() {
    let (_, programs) = runEnter(["module M {\n    struct A {}\n}\nstruct B {}"])
    let moduleDecl = programs[0].statements[0] as! AST.ModuleDecl
    let aDecl = moduleDecl.body[0] as! AST.StructDecl
    let bDecl = programs[0].statements[1] as! AST.StructDecl
    #expect(aDecl.symbol?.moduleSymbol === moduleDecl.symbol)
    #expect(bDecl.symbol?.moduleSymbol == nil)
}

@Test func extensionMemberGetsOwnerType() {
    let (_, programs) = runEnter(["struct S {}\nextension S {\n    func f() {}\n}"])
    let extensionDecl = programs[0].statements[1] as! AST.ExtensionDecl
    let functionDecl = extensionDecl.body[0] as! AST.FunctionDecl
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    #expect(functionDecl.symbol?.memberOf == structDecl.symbol?.id)
}

@Test func caseSymbolAccess() {
    let (_, programs) = runEnter(["enum E {\n    case A\n}"])
    let enumDecl = programs[0].statements[0] as! AST.EnumDecl
    let caseDecl = enumDecl.body[0] as! AST.EnumCaseDecl
    #expect(caseDecl.symbols.first?.access == .Internal)
    #expect(caseDecl.symbols.first?.memberOf == enumDecl.symbol?.id)
}
