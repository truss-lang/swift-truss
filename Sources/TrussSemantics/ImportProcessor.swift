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
        let path = importStatement.path.components.map(componentName)
        let fullPath = path.joined(separator: ".")
        guard let first = path.first else { return nil }
        guard let root = resolveRoot(first, at: importStatement.token) else {
            emitUnresolved(
                fullPath, missing: first, parent: "the current scope",
                at: importStatement
            )
            return nil
        }
        let descendCount = switch importStatement.selector {
        case .WholeModule: path.count - 1
        case .Wildcard, .Explicit: path.count
        }
        var namespace = root
        if descendCount > 1 {
            for index in 1 ..< descendCount {
                let component = path[index]
                guard let module = namespace.scope.modules[component] else {
                    emitUnresolved(
                        fullPath, missing: component, parent: namespace.name,
                        at: importStatement
                    )
                    return nil
                }
                namespace = Namespace(name: module.name, symbol: module, scope: module.scope)
            }
        }
        switch importStatement.selector {
        case let .WholeModule(alias):
            if path.count == 1 {
                if let alias {
                    registerNamespaceAlias(namespace, as: alias.value, into: scope)
                }
            } else {
                importTerminal(
                    path[path.count - 1], from: namespace, alias: alias?.value,
                    fullPath: fullPath, at: importStatement, into: scope
                )
            }
        case .Wildcard:
            importAll(from: namespace, into: scope)
        case let .Explicit(items):
            importExplicit(
                items, from: namespace, fullPath: fullPath,
                at: importStatement, into: scope
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
        at importStatement: AST.Import, into scope: Scope
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
            emitUnresolved(
                fullPath, missing: name, parent: namespace.name, at: importStatement
            )
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

    private func importExplicit(
        _ items: [AST.ImportItem], from namespace: Namespace, fullPath: String,
        at importStatement: AST.Import, into scope: Scope
    ) {
        for item in items {
            switch item.kind {
            case let .Name(token):
                let name = token.value
                let importName = item.alias?.value ?? name
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
                    emitUnresolved(
                        fullPath, missing: name, parent: namespace.name,
                        at: importStatement
                    )
                }
            case .Self_:
                break
            }
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
        _ fullPath: String, missing: String, parent: String,
        at importStatement: AST.Import
    ) {
        guard let source = context.sourceTable[importStatement.token.id] else { return }
        let buffer = source.stringSourceBuffer
        let range = importStatement.token.sourceRange(in: buffer)
        let note = Diagnostic(
            severity: .note, message: "could not find '\(missing)' in \(parent)",
            range: range
        )
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: .error, message: "unresolved import '\(fullPath)'",
                range: range, notes: [note] + importStatement.token.expansionNotes(in: context)
            )
        )
    }

    private struct Namespace {
        let name: String
        let symbol: Symbol.Symbol
        let scope: Scope
    }
}
