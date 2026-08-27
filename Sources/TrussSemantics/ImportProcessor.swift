import SwiftBetterDiagnostic
import TrussCore

public final class ImportProcessor: AST.Visitor {
    private let context: Context
    private var currentScope: Scope?

    public init(context: Context) {
        self.context = context
    }

    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        guard let packageSymbol = program.packageSymbol else { return nil }
        let lastScope = currentScope
        currentScope = packageSymbol.scope
        importStd(into: currentScope!)
        super.visitProgram(program, additional: additional)
        currentScope = lastScope
        return nil
    }

    private func importStd(into scope: Scope) {
        guard let package = context.name2Package["Truss"] else { return }
        let namespace = Namespace(
            name: package.name, symbol: package, scope: package.scope
        )
        importAll(from: namespace, into: scope)
    }

    public override func visitImport(_ importStatement: AST.Import, additional: Any? = nil) -> Any? {
        guard let scope = currentScope else { return nil }
        process(importStatement.node, namespace: nil, atRoot: true, into: scope, pathParts: [])
        return nil
    }

    private func process(
        _ node: AST.ImportNode, namespace: Namespace?, atRoot: Bool, into scope: Scope,
        pathParts: [String]
    ) {
        switch node {
        case let .Member(name, sub):
            let nameStr = name.value
            let child: Namespace
            if let namespace {
                guard let module = namespace.scope.modules[nameStr] else {
                    emitUnresolved(
                        fullPath(at: pathParts, name: nameStr, sub: sub),
                        missing: nameStr, parent: namespace.name, at: name
                    )
                    return
                }
                child = Namespace(name: module.name, symbol: module, scope: module.scope)
            } else {
                guard let root = resolveRoot(nameStr, at: name) else {
                    emitUnresolved(
                        fullPath(at: pathParts, name: nameStr, sub: sub),
                        missing: nameStr, parent: "the current scope", at: name
                    )
                    return
                }
                child = root
            }
            process(
                sub, namespace: child, atRoot: false, into: scope,
                pathParts: pathParts + [nameStr]
            )
        case let .Name(token):
            if isSelf(token) { return }
            if atRoot {
                guard let _ = resolveRoot(token.value, at: token) else {
                    emitUnresolved(
                        (pathParts + [token.value]).joined(separator: "."),
                        missing: token.value, parent: "the current scope", at: token
                    )
                    return
                }
            } else if let namespace {
                importTerminal(
                    token.value, from: namespace, alias: nil,
                    fullPath: (pathParts + [token.value]).joined(separator: "."),
                    at: token, into: scope
                )
            }
        case let .Alias(token, alias):
            if isSelf(token) { return }
            if atRoot {
                guard let root = resolveRoot(token.value, at: token) else {
                    emitUnresolved(
                        (pathParts + [token.value]).joined(separator: "."),
                        missing: token.value, parent: "the current scope", at: token
                    )
                    return
                }
                registerNamespaceAlias(root, as: alias.value, into: scope)
            } else if let namespace {
                importTerminal(
                    token.value, from: namespace, alias: alias.value,
                    fullPath: (pathParts + [token.value]).joined(separator: "."),
                    at: token, into: scope
                )
            }
        case .Wildcard:
            if let namespace {
                importAll(from: namespace, into: scope)
            }
        case let .List(items):
            for item in items {
                process(
                    item, namespace: namespace, atRoot: false, into: scope,
                    pathParts: pathParts
                )
            }
        case .Self_:
            break
        }
    }

    private func fullPath(at pathParts: [String], name: String, sub: AST.ImportNode) -> String {
        let remaining = firstDottedPath(of: sub)
        let current = remaining.isEmpty ? name : name + "." + remaining
        return (pathParts + [current]).joined(separator: ".")
    }

    private func firstDottedPath(of node: AST.ImportNode) -> String {
        switch node {
        case let .Member(token, sub):
            let rest = firstDottedPath(of: sub)
            return rest.isEmpty ? token.value : token.value + "." + rest
        case let .Name(token), let .Self_(token): return token.value
        case let .Alias(token, _): return token.value
        case .Wildcard: return "*"
        case let .List(items): return items.first.map { firstDottedPath(of: $0) } ?? ""
        }
    }

    private func isSelf(_ token: Token) -> Bool {
        if case let .Keyword(kind) = token.kind {
            return kind == .SelfKw || kind == .SelfTypeKw
        }
        return false
    }

    private func resolveRoot(_ first: String, at token: Token) -> Namespace? {
        if let package = context.name2Package[first] {
            return Namespace(name: first, symbol: package, scope: package.scope)
        }
        if let module = currentScope?.modules[first] {
            return Namespace(name: first, symbol: module, scope: module.scope)
        }
        return nil
    }

    private func importTerminal(
        _ name: String, from namespace: Namespace, alias: String?, fullPath: String,
        at token: Token, into scope: Scope
    ) {
        let importName = alias ?? name
        var found = false
        if let module = namespace.scope.modules[name] {
            registerModule(module, as: importName, into: scope)
            found = true
        }
        if let type = namespace.scope.types[name] {
            registerType(type, as: importName, into: scope)
            found = true
        }
        if let values = namespace.scope.values[name] {
            registerValues(values, as: importName, into: scope)
            found = true
        }
        if !found {
            emitUnresolved(fullPath, missing: name, parent: namespace.name, at: token)
        }
    }

    private func importAll(from namespace: Namespace, into scope: Scope) {
        for (name, module) in namespace.scope.modules {
            registerModule(module, as: name, into: scope)
        }
        for (name, type) in namespace.scope.types {
            registerType(type, as: name, into: scope)
        }
        for (name, values) in namespace.scope.values {
            registerValues(values, as: name, into: scope)
        }
    }

    private func registerNamespaceAlias(
        _ namespace: Namespace, as alias: String, into scope: Scope
    ) {
        if let module = namespace.symbol as? Symbol.ModuleSymbol {
            if scope.modules[alias] == nil {
                scope.modules[alias] = module
            }
        }
    }

    private func registerModule(
        _ symbol: Symbol.ModuleSymbol, as name: String, into scope: Scope
    ) {
        if scope.modules[name] == nil {
            scope.modules[name] = symbol
        }
    }

    private func registerType(
        _ symbol: Symbol.Symbol, as name: String, into scope: Scope
    ) {
        if scope.types[name] == nil {
            scope.types[name] = symbol
        }
    }

    private func registerValues(
        _ symbols: [Symbol.Symbol], as name: String, into scope: Scope
    ) {
        if scope.values[name] == nil {
            scope.values[name] = symbols
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

    private struct Namespace {
        let name: String
        let symbol: Symbol.Symbol
        let scope: Scope
    }
}
