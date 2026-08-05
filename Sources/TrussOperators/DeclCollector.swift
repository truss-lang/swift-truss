import TrussCore

public final class DeclCollector: AST.Visitor {
    private let table: OperatorTable
    private let context: Context
    private var namespaceStack: [OperatorTable.Namespace] = []

    public init(table: OperatorTable, context: Context) {
        self.table = table
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        namespaceStack.append(table.root)
        let result = super.visitProgram(program, additional: additional)
        namespaceStack.removeLast()
        return result
    }

    @discardableResult
    public override func visitModuleDecl(
        _ moduleDecl: AST.ModuleDecl, additional: Any? = nil
    ) -> Any? {
        namespaceStack.append(table.namespace(forModule: moduleDecl.name.value))
        let result = super.visitModuleDecl(moduleDecl, additional: additional)
        namespaceStack.removeLast()
        return result
    }

    @discardableResult
    public override func visitOperatorDecl(
        _ operatorDecl: AST.OperatorDecl, additional: Any? = nil
    ) -> Any? {
        let namespace = namespaceStack.last!
        let name = operatorDecl.name.value
        if let info = namespace.operators[name] {
            if info.kinds.contains(where: { kind(of: $0) == kind(of: operatorDecl.kind) }) {
                context.emitError(
                    "invalid redeclaration of operator '\(name)' (\(kindText(operatorDecl.kind)))",
                    at: operatorDecl.name
                )
                return nil
            }
            info.kinds.append(operatorDecl.kind)
        } else {
            namespace.operators[name] = OperatorTable.OperatorInfo(
                name: operatorDecl.name, kinds: [operatorDecl.kind]
            )
        }
        return nil
    }

    @discardableResult
    public override func visitPrecedenceGroupDecl(
        _ precedenceGroupDecl: AST.PrecedenceGroupDecl, additional: Any? = nil
    ) -> Any? {
        let namespace = namespaceStack.last!
        let name = precedenceGroupDecl.name.value
        if namespace.precedenceGroups[name] != nil {
            context.emitError(
                "invalid redeclaration of precedence group '\(name)'",
                at: precedenceGroupDecl.name
            )
            return nil
        }
        namespace.precedenceGroups[name] = OperatorTable.PrecedenceGroupInfo(
            name: precedenceGroupDecl.name,
            associativity: precedenceGroupDecl.associativity,
            assignment: precedenceGroupDecl.assignment,
            higherThan: precedenceGroupDecl.higherThan,
            lowerThan: precedenceGroupDecl.lowerThan
        )
        return nil
    }

    private func kind(of kind: AST.OperatorDecl.Kind) -> Kind {
        switch kind {
        case .Infix: .infix
        case .Prefix: .prefix
        case .Postfix: .postfix
        }
    }

    private func kindText(_ kind: AST.OperatorDecl.Kind) -> String {
        switch kind {
        case .Infix: "infix"
        case .Prefix: "prefix"
        case .Postfix: "postfix"
        }
    }

    private enum Kind {
        case infix
        case prefix
        case postfix
    }
}
