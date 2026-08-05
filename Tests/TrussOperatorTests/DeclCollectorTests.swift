import Testing
import TrussCore
import TrussOperator

func kindNames(_ info: OperatorInfo?) -> [String] {
    guard let info else { return [] }
    return info.kinds.map { kind in
        switch kind {
        case .Infix: "infix"
        case .Prefix: "prefix"
        case .Postfix: "postfix"
        }
    }
}

func messages(_ context: Context) -> [String] {
    context.diagnositicEngine.diagnostics.map(\.message)
}

@Test func collectOperatorKinds() {
    let (_, table, _) = runDeclCollector([
        "infix operator + prefix operator - postfix operator ++",
    ])
    #expect(kindNames(table.root.operators["+"]) == ["infix"])
    #expect(kindNames(table.root.operators["-"]) == ["prefix"])
    #expect(kindNames(table.root.operators["++"]) == ["postfix"])
}

@Test func collectOperatorGroupReference() {
    let (_, table, _) = runDeclCollector(["infix operator +: P"])
    let group = table.root.operators["+"]?.group as? AST.Variable
    #expect(group?.name.value == "P")
}

@Test func infixDeclarationUpdatesGroup() {
    let (_, table, _) = runDeclCollector(["prefix operator - infix operator -: P"])
    let group = table.root.operators["-"]?.group as? AST.Variable
    #expect(group?.name.value == "P")
}

@Test func operatorAllowsMultipleKinds() {
    let (context, table, _) = runDeclCollector(["prefix operator - infix operator -"])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.root.operators["-"]) == ["prefix", "infix"])
}

@Test func duplicateOperatorKindReportsError() {
    let (context, table, _) = runDeclCollector(["infix operator + infix operator +"])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.root.operators["+"]) == ["infix"])
    #expect(messages(context).contains("invalid redeclaration of operator '+' (infix)"))
}

@Test func collectPrecedenceGroup() throws {
    let (_, table, _) = runDeclCollector([
        "precedencegroup P { associativity: left assignment: true higherThan: Bar, Baz lowerThan: Qux }",
    ])
    let info = table.root.precedenceGroups["P"]
    try #require(info != nil)
    #expect(info!.name.value == "P")
    #expect(info!.associativity == .Left)
    #expect(info!.assignment)
    try #require(info!.higherThan.count == 2)
    #expect((info!.higherThan[0] as? AST.Variable)?.name.value == "Bar")
    #expect((info!.higherThan[1] as? AST.Variable)?.name.value == "Baz")
    #expect((info!.lowerThan[0] as? AST.Variable)?.name.value == "Qux")
}

@Test func duplicatePrecedenceGroupReportsError() {
    let (context, table, _) = runDeclCollector([
        "precedencegroup P {} precedencegroup P {}",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(table.root.precedenceGroups["P"] != nil)
    #expect(messages(context).contains("invalid redeclaration of precedence group 'P'"))
}

@Test func unknownHigherThanReferenceSilent() {
    let (context, _, _) = runDeclCollector(["precedencegroup P { higherThan: Nope }"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func moduleNamespaceIsolation() {
    let (context, table, _) = runDeclCollector([
        "infix operator + module M { infix operator + }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.root.operators["+"]) == ["infix"])
    #expect(kindNames(table.modules["M"]?.operators["+"]) == ["infix"])
}

@Test func sameModuleNameSharesNamespace() {
    let (context, table, _) = runDeclCollector([
        "module M { infix operator + } module M { infix operator - }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.modules["M"]?.operators["+"]) == ["infix"])
    #expect(kindNames(table.modules["M"]?.operators["-"]) == ["infix"])
}

@Test func duplicateAcrossModulesAllowed() {
    let (context, table, _) = runDeclCollector([
        "module A { infix operator + } module B { infix operator + }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.modules["A"]?.operators["+"]) == ["infix"])
    #expect(kindNames(table.modules["B"]?.operators["+"]) == ["infix"])
}

@Test func duplicatePrecedenceGroupAcrossModulesAllowed() {
    let (context, table, _) = runDeclCollector([
        "module A { precedencegroup P {} } module B { precedencegroup P {} }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(table.modules["A"]?.precedenceGroups["P"] != nil)
    #expect(table.modules["B"]?.precedenceGroups["P"] != nil)
}

@Test func collectPrecedenceGroupInModuleBody() {
    let (_, table, _) = runDeclCollector(["module M { precedencegroup P {} }"])
    #expect(table.modules["M"]?.precedenceGroups["P"] != nil)
    #expect(table.root.precedenceGroups["P"] == nil)
}

@Test func nestedModuleNamespace() {
    let (_, table, _) = runDeclCollector(["module A { module B { infix operator + } }"])
    #expect(kindNames(table.modules["A.B"]?.operators["+"]) == ["infix"])
}
