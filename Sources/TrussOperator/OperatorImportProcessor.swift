import SwiftBetterDiagnostic
import TrussCore

public final class OperatorImportProcessor: AST.Visitor {
    private let table: OperatorTable
    private let context: Context

    public init(table: OperatorTable, context: Context) {
        self.table = table
        self.context = context
    }

    @discardableResult
    public override func visitOperatorImport(
        _ operatorImport: AST.OperatorImport, additional: Any? = nil
    ) -> Any? {
        let fullPath = renderPath(of: operatorImport.node)
        process(operatorImport.node, source: table.root, into: table.root, fullPath: fullPath)
        return nil
    }

    private func process(
        _ node: AST.ImportNode, source: Namespace, into target: Namespace, fullPath: String
    ) {
        switch node {
        case let .Member(name, sub):
            guard let child = source.children[name.value] else {
                emitUnresolved(fullPath, missing: name.value, parent: "module", at: name)
                return
            }
            process(sub, source: child, into: target, fullPath: fullPath)
        case let .Name(token):
            if isSelf(token) { return }
            importOperator(
                token.value, from: source, into: target, fullPath: fullPath, at: token
            )
        case let .Alias(token, _):
            if isSelf(token) { return }
            importOperator(
                token.value, from: source, into: target, fullPath: fullPath, at: token
            )
        case .Wildcard:
            importAll(from: source, into: target)
        case let .List(items):
            for item in items {
                process(item, source: source, into: target, fullPath: fullPath)
            }
        case .Self_:
            break
        }
    }

    private func renderPath(of node: AST.ImportNode) -> String {
        switch node {
        case let .Member(token, sub):
            token.value + "." + renderPath(of: sub)
        case let .Name(token), let .Self_(token): token.value
        case let .Alias(token, _): token.value
        case .Wildcard: "*"
        case let .List(items):
            "{" + items.map { renderPath(of: $0) }.joined(separator: ", ") + "}"
        }
    }

    private func isSelf(_ token: Token) -> Bool {
        if case let .Keyword(kind) = token.kind {
            return kind == .SelfKw || kind == .SelfTypeKw
        }
        return false
    }

    private func importAll(from source: Namespace, into target: Namespace) {
        for (name, info) in source.operators {
            register(info, as: name, into: target)
        }
    }

    private func importOperator(
        _ name: String, from source: Namespace, into target: Namespace,
        fullPath: String, at token: Token
    ) {
        guard let info = source.operators[name] else {
            emitUnresolved(fullPath, missing: name, parent: "module", at: token)
            return
        }
        register(info, as: name, into: target)
    }

    private func register(_ info: OperatorInfo, as name: String, into target: Namespace) {
        if target.operators[name] == nil {
            target.operators[name] = info
        }
    }

    private func emitUnresolved(
        _ fullPath: String, missing: String, parent: String, at token: Token
    ) {
        guard let source = context.sourceTable[token.id] else { return }
        let buffer = source.stringSourceBuffer
        let range = token.sourceRange(in: buffer)
        let note = Diagnostic(
            severity: .note, message: "could not find '\(missing)' in \(parent)",
            range: range
        )
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: .error, message: "unresolved import '\(fullPath)'",
                range: range, notes: [note] + token.expansionNotes(in: context)
            )
        )
    }
}
