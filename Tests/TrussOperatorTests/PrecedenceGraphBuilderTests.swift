import SwiftGraph
import Testing
import TrussCore
import TrussOperator

func builtMessages(_ context: Context) -> [String] {
    context.diagnositicEngine.diagnostics.map(\.message)
}

@Test func acyclicGraphBuildsWithoutDiagnostics() {
    let (context, graph) = runBuilt([
        "precedencegroup A {} precedencegroup B {} precedencegroup C { higherThan: B }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(graph.vertexCount == 3)
    #expect(graph.edgeCount == 1)
}

@Test func moduleGroupsAddedOnce() {
    let (context, graph) = runBuilt([
        "module M { precedencegroup B { higherThan: A } } precedencegroup A {}",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(graph.vertexCount == 2)
    #expect(graph.edgeCount == 1)
}

@Test func twoGroupCycleReportsError() {
    let (context, _) = runBuilt([
        "precedencegroup A { higherThan: B } precedencegroup B { higherThan: A }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(
        builtMessages(context).contains(
            "cyclic dependency between precedence groups: 'A' -> 'B' -> 'A'"
        )
    )
}

@Test func threeGroupCycleExpandsNotes() {
    let (context, _) = runBuilt([
        "precedencegroup A { higherThan: B } precedencegroup B { higherThan: C } "
            + "precedencegroup C { higherThan: A }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(
        builtMessages(context).contains(
            "cyclic dependency between precedence groups: 'A' -> 'B' -> 'C' -> 'A'"
        )
    )
    let notes = context.diagnositicEngine.diagnostics.flatMap(\.notes).map(\.message)
    #expect(notes.count == 2)
    #expect(
        notes.contains("precedence group 'B' participates in this cycle")
    )
    #expect(
        notes.contains("precedence group 'C' participates in this cycle")
    )
}

@Test func crossModuleCycleUsesQualifiedNames() {
    let (context, _) = runBuilt([
        "precedencegroup A { higherThan: M.B } module M { precedencegroup B { higherThan: A } }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(
        builtMessages(context).contains(
            "cyclic dependency between precedence groups: 'A' -> 'M.B' -> 'A'"
        )
    )
}

@Test func nestedModuleGroupBuildsIntoGraph() {
    let (context, graph) = runBuilt([
        "module M { module N { precedencegroup P {} } } precedencegroup Q { higherThan: M.N.P }",
    ])
    #expect(!context.diagnositicEngine.hasErrors)
    #expect(graph.vertexCount == 2)
    #expect(graph.edgeCount == 1)
}

@Test func lowerThanCycleReportsError() {
    let (context, _) = runBuilt([
        "precedencegroup A { lowerThan: B } precedencegroup B { lowerThan: A }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(
        builtMessages(context).contains(
            "cyclic dependency between precedence groups: 'A' -> 'B' -> 'A'"
        )
    )
}

@Test func selfReferenceNotRepeatedByBuilder() {
    let (context, _) = runBuilt(["precedencegroup A { higherThan: A }"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = builtMessages(context)
    #expect(messages.filter { $0.hasPrefix("cyclic dependency") }.isEmpty)
    #expect(
        messages.filter { $0 == "precedence group 'A' cannot be higher than itself" }
            .count == 1
    )
}

@Test func contradictionNotRepeatedByBuilder() {
    let (context, _) = runBuilt([
        "precedencegroup A {} precedencegroup B { higherThan: A lowerThan: A }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = builtMessages(context)
    #expect(messages.filter { $0.hasPrefix("cyclic dependency") }.isEmpty)
    #expect(
        messages.filter {
            $0 == "precedence group 'B' is both higher than and lower than 'A'"
        }.count == 1
    )
}

@Test func multipleCyclesReportSeparately() {
    let (context, _) = runBuilt([
        "precedencegroup A { higherThan: B } precedencegroup B { higherThan: A } "
            + "precedencegroup C { higherThan: D } precedencegroup D { higherThan: C }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    let cycles = builtMessages(context).filter { $0.hasPrefix("cyclic dependency") }
    #expect(cycles.count == 2)
}

@Test func cycleMixedWithNormalEdges() {
    let (context, graph) = runBuilt([
        "precedencegroup A { higherThan: B } precedencegroup B { higherThan: A } "
            + "precedencegroup C { higherThan: B }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(builtMessages(context).filter { $0.hasPrefix("cyclic dependency") }.count == 1)
    #expect(graph.vertexCount == 3)
    #expect(graph.edgeCount == 3)
}
