import Testing
import TrussCore

@Test func enterNestedModuleSymbols() {
    let program = parseProgram("module A.B {}")
    let outer = program.statements[0] as! AST.ModuleDecl
    let a = outer.symbol
    #expect(a != nil)
    let b = a!.scope.modules["B"] as? Symbol.ModuleSymbol
    #expect(b != nil)
}

@Test func enterDottedAndNestedModuleMerge() {
    let program = parseProgram("module A.B { func f() {} } module A { func g() {} }")
    let first = program.statements[0] as! AST.ModuleDecl
    let second = program.statements[1] as! AST.ModuleDecl
    #expect(first.symbol === second.symbol)
    let a = first.symbol!
    #expect(a.scope.values["g"] != nil)
    let b = a.scope.modules["B"] as? Symbol.ModuleSymbol
    #expect(b != nil)
    #expect(b!.scope.values["f"] != nil)
}
