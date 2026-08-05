import Testing
import TrussCore
import TrussOperator

func kindNames(_ info: OperatorTable.OperatorInfo?) -> [String] {
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
        "operator + infix operator - prefix operator ++ postfix",
    ])
    #expect(kindNames(table.root.operators["+"]) == ["infix"])
    #expect(kindNames(table.root.operators["-"]) == ["prefix"])
    #expect(kindNames(table.root.operators["++"]) == ["postfix"])
}

@Test func operatorAllowsMultipleKinds() {
    let (context, table, _) = runDeclCollector(["operator - prefix operator - infix"])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.root.operators["-"]) == ["prefix", "infix"])
}

@Test func duplicateOperatorKindReportsError() {
    let (context, table, _) = runDeclCollector(["operator + infix operator + infix"])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.root.operators["+"]) == ["infix"])
    #expect(messages(context).contains("invalid redeclaration of operator '+' (infix)"))
}

@Test func collectPrecedenceGroup() {
    let (_, table, _) = runDeclCollector([
        "precedencegroup P { associativity: left assignment: true higherThan: Bar, Baz lowerThan: Qux }",
    ])
    let info = table.root.precedenceGroups["P"]
    #expect(info != nil)
    #expect(info!.name.value == "P")
    #expect(info!.associativity == .Left)
    #expect(info!.assignment)
    #expect(info!.higherThan.count == 2)
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
        "operator + infix module M { operator + infix }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.root.operators["+"]) == ["infix"])
    #expect(kindNames(table.modules["M"]?.operators["+"]) == ["infix"])
}

@Test func sameModuleNameSharesNamespace() {
    let (context, table, _) = runDeclCollector([
        "module M { operator + infix } module M { operator - infix }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(kindNames(table.modules["M"]?.operators["+"]) == ["infix"])
    #expect(kindNames(table.modules["M"]?.operators["-"]) == ["infix"])
}

@Test func duplicateAcrossModulesAllowed() {
    let (context, table, _) = runDeclCollector([
        "module A { operator + infix } module B { operator + infix }",
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
    let (_, table, _) = runDeclCollector(["module A { module B { operator + infix } }"])
    #expect(kindNames(table.modules["A.B"]?.operators["+"]) == ["infix"])
}
