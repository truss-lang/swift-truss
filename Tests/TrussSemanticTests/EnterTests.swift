import Testing
import TrussCore

@Test func enterNestedModuleSymbols() throws {
    let program = parseProgram("module A.B {}")
    let outer = program.statements[0] as! AST.ModuleDecl
    let a = outer.symbol
    try #require(a != nil)
    let b = a!.scope.modules["B"]
    #expect(b != nil)
}

@Test func enterDottedAndNestedModuleMerge() throws {
    let program = parseProgram("module A.B { func f() {} } module A { func g() {} }")
    let first = program.statements[0] as! AST.ModuleDecl
    let second = program.statements[1] as! AST.ModuleDecl
    #expect(first.symbol === second.symbol)
    let a = first.symbol!
    #expect(a.scope.values["g"] != nil)
    let b = a.scope.modules["B"]
    try #require(b != nil)
    #expect(b!.scope.values["f"] != nil)
}
