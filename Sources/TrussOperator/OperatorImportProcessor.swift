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
        let path = operatorImport.path.components.map(componentName)
        let modulePath = path.joined(separator: ".")
        let fullPath = modulePath + selectorText(operatorImport.selector)
        guard let source = resolveNamespace(path, at: operatorImport.token) else {
            emitUnresolved(
                fullPath, missing: path.first ?? "", parent: "the current module",
                at: operatorImport.token
            )
            return nil
        }
        switch operatorImport.selector {
        case .Wildcard:
            importAll(from: source, into: table.root)
        case let .Operator(token):
            importOperator(
                token.value, from: source, into: table.root,
                fullPath: fullPath, at: token
            )
        case let .List(items):
            importList(
                items, from: source, into: table.root,
                fullPath: fullPath, at: operatorImport.token
            )
        }
        return nil
    }

    private func componentName(_ component: AST.PathComponent) -> String {
        switch component {
        case let .Identifier(token): token.value
        case let .Self_(token): token.value
        }
    }

    private func selectorText(_ selector: AST.OperatorImportSelector) -> String {
        switch selector {
        case .Wildcard: ".*"
        case let .Operator(token): ".\(token.value)"
        case let .List(items): " { \(items.map(itemText).joined(separator: ", ")) }"
        }
    }

    private func itemText(_ item: AST.OperatorImportItem) -> String {
        switch item {
        case let .Operator(token): token.value
        case let .Submodule(token, selector): "\(token.value).\(selectorText(selector))"
        }
    }

    private func resolveNamespace(_ path: [String], at token: Token) -> Namespace? {
        var current: Namespace? = table.root
        for component in path {
            guard let child = current?.children[component] else { return nil }
            current = child
        }
        return current
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

    private func importList(
        _ items: [AST.OperatorImportItem], from source: Namespace, into target: Namespace,
        fullPath: String, at token: Token
    ) {
        for item in items {
            switch item {
            case let .Operator(operatorToken):
                importOperator(
                    operatorToken.value, from: source, into: target,
                    fullPath: fullPath, at: operatorToken
                )
            case let .Submodule(moduleToken, selector):
                guard let child = source.children[moduleToken.value] else {
                    emitUnresolved(
                        fullPath, missing: moduleToken.value, parent: "module",
                        at: moduleToken
                    )
                    continue
                }
                importSelector(selector, from: child, into: target, fullPath: fullPath, at: moduleToken)
            }
        }
    }

    private func importSelector(
        _ selector: AST.OperatorImportSelector, from source: Namespace, into target: Namespace,
        fullPath: String, at token: Token
    ) {
        switch selector {
        case .Wildcard:
            importAll(from: source, into: target)
        case let .Operator(operatorToken):
            importOperator(
                operatorToken.value, from: source, into: target,
                fullPath: fullPath, at: operatorToken
            )
        case let .List(items):
            importList(items, from: source, into: target, fullPath: fullPath, at: token)
        }
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
