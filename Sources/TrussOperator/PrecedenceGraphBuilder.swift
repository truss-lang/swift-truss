import SwiftBetterDiagnostic
import SwiftGraph
import TrussCore

public final class PrecedenceGraphBuilder {
    private let table: OperatorTable
    private let context: Context
    private var qualifiedNames: [ObjectIdentifier: String] = [:]
    private var addedVertices: Set<ObjectIdentifier> = []

    public init(table: OperatorTable, context: Context) {
        self.table = table
        self.context = context
    }

    public func build() -> UnweightedGraph<PrecedenceGroupInfo> {
        let graph: UnweightedGraph<PrecedenceGroupInfo> = UnweightedGraph()
        resolveNamespace(table.root, modulePrefix: "", graph: graph)
        for name in table.modules.keys.sorted() {
            resolveNamespace(table.modules[name]!, modulePrefix: name, graph: graph)
        }
        reportCycles(in: graph)
        return graph
    }

    private func resolveNamespace(
        _ namespace: Namespace, modulePrefix: String, graph: UnweightedGraph<PrecedenceGroupInfo>
    ) {
        for group in namespace.precedenceGroups.values.sorted(by: { $0.name.value < $1.name.value }) {
            qualifiedNames[ObjectIdentifier(group)] =
                modulePrefix.isEmpty ? group.name.value : modulePrefix + "." + group.name.value
            if addedVertices.insert(ObjectIdentifier(group)).inserted {
                _ = graph.addVertex(group)
            }
            resolvePrecedenceGroup(group, graph: graph)
        }
    }

    private func resolvePrecedenceGroup(
        _ info: PrecedenceGroupInfo, graph: UnweightedGraph<PrecedenceGroupInfo>
    ) {
        for case let higherThan? in info.resolvedHigherThan {
            addEdge(from: info, to: higherThan, graph: graph)
        }
        for case let lowerThan? in info.resolvedLowerThan {
            addEdge(from: lowerThan, to: info, graph: graph)
        }
    }

    private func addEdge(
        from: PrecedenceGroupInfo, to: PrecedenceGroupInfo,
        graph: UnweightedGraph<PrecedenceGroupInfo>
    ) {
        if addedVertices.insert(ObjectIdentifier(from)).inserted {
            _ = graph.addVertex(from)
        }
        if addedVertices.insert(ObjectIdentifier(to)).inserted {
            _ = graph.addVertex(to)
        }
        graph.addEdge(from: from, to: to, directed: true)
    }

    private func reportCycles(in graph: UnweightedGraph<PrecedenceGroupInfo>) {
        var reported: Set<[ObjectIdentifier]> = []
        for cycle in graph.detectCycles() {
            if cycle.count == 2, cycle[0] === cycle[1] { continue }
            if cycle.count == 3, cycle[0] === cycle[2], isContradiction(cycle[0], cycle[1]) {
                continue
            }
            let ids = cycle.map { ObjectIdentifier($0) }
            if !reported.insert(ids).inserted { continue }
            let names = cycle.map { qualifiedName($0) }
            context.emitError(
                "cyclic dependency between precedence groups: "
                    + names.map { "'\($0)'" }.joined(separator: " -> "),
                at: cycle[0].name,
                notes: cycle.dropFirst().dropLast().compactMap { cycleNote(for: $0) }
            )
        }
    }

    private func isContradiction(_ lhs: PrecedenceGroupInfo, _ rhs: PrecedenceGroupInfo) -> Bool {
        lhs.resolvedHigherThan.contains(where: { $0 === rhs })
            && lhs.resolvedLowerThan.contains(where: { $0 === rhs })
            || rhs.resolvedHigherThan.contains(where: { $0 === lhs })
            && rhs.resolvedLowerThan.contains(where: { $0 === lhs })
    }

    private func cycleNote(for group: PrecedenceGroupInfo) -> Diagnostic? {
        guard let source = context.sourceTable[group.name.id] else { return nil }
        return Diagnostic(
            severity: .note,
            message: "precedence group '\(qualifiedName(group))' participates in this cycle",
            range: group.name.sourceRange(in: source.stringSourceBuffer),
            notes: group.name.expansionNotes(in: context)
        )
    }

    private func qualifiedName(_ group: PrecedenceGroupInfo) -> String {
        qualifiedNames[ObjectIdentifier(group)] ?? group.name.value
    }
}
