import Testing
import TrussCore
import TrussOperator
import TrussSyntax

func runOperatorImports(
    _ sources: [String]
) -> (Context, OperatorTable, [AST.Program]) {
    let (context, table, programs) = runDeclCollector(sources)
    for program in programs {
        OperatorImportProcessor(table: table, context: context).visitProgram(program)
    }
    return (context, table, programs)
}

@Test func operatorWildcardImportCopiesModuleOperators() {
    let (context, table, _) = runOperatorImports([
        "module Ops { infix operator + prefix operator - }",
        "import operator Ops.*",
    ])
    #expect(table.root.operators["+"] != nil)
    #expect(table.root.operators["-"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func operatorSingleImportCopiesOneOperator() {
    let (context, table, _) = runOperatorImports([
        "module Ops { infix operator + prefix operator - }",
        "import operator Ops.+",
    ])
    #expect(table.root.operators["+"] != nil)
    #expect(table.root.operators["-"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func operatorListImportCopiesSelectedOperators() {
    let (context, table, _) = runOperatorImports([
        "module Ops { infix operator + infix operator * infix operator - }",
        "import operator Ops.{ +, - }",
    ])
    #expect(table.root.operators["+"] != nil)
    #expect(table.root.operators["-"] != nil)
    #expect(table.root.operators["*"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func operatorImportIntoNestedModuleSubmodule() {
    let (context, table, _) = runOperatorImports([
        "module Ops { module Inner { infix operator + } }",
        "import operator Ops.Inner.*",
    ])
    #expect(table.root.operators["+"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func unresolvedOperatorModuleReportsError() {
    let (context, table, _) = runOperatorImports(["import operator Missing.*"])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(context.diagnositicEngine.diagnostics.contains {
        $0.message.contains("unresolved import 'Missing.*'")
    })
    #expect(table.root.operators.isEmpty)
}

@Test func unresolvedOperatorInModuleReportsError() {
    let (context, _, _) = runOperatorImports([
        "module Ops { infix operator + }",
        "import operator Ops.-",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    #expect(context.diagnositicEngine.diagnostics.contains {
        $0.message.contains("unresolved import 'Ops.-'")
    })
}
