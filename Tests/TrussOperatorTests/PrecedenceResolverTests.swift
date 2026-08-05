import Testing
import TrussCore
import TrussOperator

func resolvedMessages(_ context: Context) -> [String] {
    context.diagnositicEngine.diagnostics.map(\.message)
}

@Test func resolveHigherThan() {
    let (_, table, _) = runResolved([
        "precedencegroup A {} precedencegroup B {} precedencegroup C { higherThan: B }",
    ])
    let b = table.root.precedenceGroups["B"]!
    let c = table.root.precedenceGroups["C"]!
    #expect(c.resolvedHigherThan.count == 1)
    #expect(c.resolvedHigherThan[0] === b)
}

@Test func resolveLowerThan() {
    let (_, table, _) = runResolved([
        "precedencegroup A {} precedencegroup B {} precedencegroup C { lowerThan: A }",
    ])
    let a = table.root.precedenceGroups["A"]!
    let c = table.root.precedenceGroups["C"]!
    #expect(c.resolvedLowerThan.count == 1)
    #expect(c.resolvedLowerThan[0] === a)
}

@Test func unknownReferenceReportsError() {
    let (context, table, _) = runResolved(["precedencegroup A { higherThan: Nope }"])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(resolvedMessages(context).contains("unknown precedence group 'Nope'"))
    let a = table.root.precedenceGroups["A"]!
    #expect(a.resolvedHigherThan.count == 1)
    #expect(a.resolvedHigherThan[0] == nil)
}

@Test func moduleReferenceResolvesWithinModule() {
    let (_, table, _) = runResolved([
        "module M { precedencegroup A {} precedencegroup B { higherThan: A } }",
    ])
    let m = table.modules["M"]!
    let a = m.precedenceGroups["A"]!
    let b = m.precedenceGroups["B"]!
    #expect(b.resolvedHigherThan[0] === a)
}

@Test func moduleReferenceFallsBackToRoot() {
    let (_, table, _) = runResolved([
        "precedencegroup A {} module M { precedencegroup B { higherThan: A } }",
    ])
    let rootA = table.root.precedenceGroups["A"]!
    let mB = table.modules["M"]!.precedenceGroups["B"]!
    #expect(mB.resolvedHigherThan[0] === rootA)
}

@Test func moduleQualifiedReference() {
    let (_, table, _) = runResolved([
        "precedencegroup A {} module M { precedencegroup B {} } precedencegroup C { higherThan: M.B }",
    ])
    let mB = table.modules["M"]!.precedenceGroups["B"]!
    let c = table.root.precedenceGroups["C"]!
    #expect(c.resolvedHigherThan[0] === mB)
}

@Test func nestedModuleQualifiedReference() {
    let (_, table, _) = runResolved([
        "module M { module N { precedencegroup P {} } } precedencegroup Q { higherThan: M.N.P }",
    ])
    let p = table.modules["M.N"]!.precedenceGroups["P"]!
    let q = table.root.precedenceGroups["Q"]!
    #expect(q.resolvedHigherThan[0] === p)
}

@Test func unknownModuleReportsError() {
    let (context, table, _) = runResolved([
        "precedencegroup B { higherThan: Nope.P }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(resolvedMessages(context).contains("unknown module 'Nope'"))
    let b = table.root.precedenceGroups["B"]!
    #expect(b.resolvedHigherThan[0] == nil)
}

@Test func unknownGroupInModuleReportsError() {
    let (context, table, _) = runResolved([
        "module M {} precedencegroup B { higherThan: M.Nope }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(resolvedMessages(context).contains("unknown precedence group 'M.Nope'"))
    let b = table.root.precedenceGroups["B"]!
    #expect(b.resolvedHigherThan[0] == nil)
}

@Test func selfReferenceReportsError() {
    let (context, table, _) = runResolved(["precedencegroup A { higherThan: A }"])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(resolvedMessages(context).contains("precedence group 'A' cannot be higher than itself"))
    let a = table.root.precedenceGroups["A"]!
    #expect(a.resolvedHigherThan[0] === a)
}

@Test func selfReferenceViaModuleReportsError() {
    let (context, _, _) = runResolved([
        "module M { precedencegroup A { higherThan: M.A } }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(resolvedMessages(context).contains("precedence group 'A' cannot be higher than itself"))
}

@Test func contradictionReportsError() {
    let (context, table, _) = runResolved([
        "precedencegroup A {} precedencegroup B { higherThan: A lowerThan: A }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(resolvedMessages(context).contains("precedence group 'B' is both higher than and lower than 'A'"))
    let a = table.root.precedenceGroups["A"]!
    let b = table.root.precedenceGroups["B"]!
    #expect(b.resolvedHigherThan[0] === a)
    #expect(b.resolvedLowerThan[0] === a)
}

@Test func nonReferenceFormReportsError() {
    let (context, table, _) = runResolved(["precedencegroup A { higherThan: 42 }"])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(resolvedMessages(context).contains("expected a precedence group reference"))
    let a = table.root.precedenceGroups["A"]!
    #expect(a.resolvedHigherThan.count == 1)
    #expect(a.resolvedHigherThan[0] == nil)
}

@Test func crossFileReference() {
    let (_, table, _) = runResolved([
        "precedencegroup A { higherThan: B }",
        "precedencegroup B {}",
    ])
    let a = table.root.precedenceGroups["A"]!
    let b = table.root.precedenceGroups["B"]!
    #expect(a.resolvedHigherThan[0] === b)
}
