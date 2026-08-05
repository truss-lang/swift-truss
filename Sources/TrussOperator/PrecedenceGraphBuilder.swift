import SwiftGraph
import TrussCore

public final class PrecedenceGraphBuilder {
    private let table: OperatorTable
    private let context: Context

    public init(table: OperatorTable, context: Context) {
        self.table = table
        self.context = context
    }

    public func build() -> UnweightedGraph<PrecedenceGroupInfo> {
        fatalError()
    }
}
