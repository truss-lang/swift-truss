import TrussCore

public final class MergePass: AST.Visitor {
    private let context: Context
    private var scopeStack: [Scope] = []
    private var pending: [(AST.ExtensionDecl, [Scope])] = []
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        let packageSymbol = program.packageSymbol!
        scopeStack.append(packageSymbol.scope)
        super.visitProgram(program, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil) -> Any? {
        let moduleSymbol = moduleDecl.symbol!
        scopeStack.append(moduleSymbol.scope)
        super.visitModuleDecl(moduleDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil) -> Any? {
        let virtualScope = extensionDecl.virtualScope!
        if let base = resolveBase(extensionDecl.base, chain: scopeStack)
            as? Symbol.NominalTypeSymbol
        {
            merge(virtualScope, into: base, chain: scopeStack, extensionDecl: extensionDecl)
        } else {
            pending.append((extensionDecl, scopeStack))
        }
        return nil
    }

    public func resolvePending() {
        var progressed = true
        while progressed, !pending.isEmpty {
            progressed = false
            var remaining: [(AST.ExtensionDecl, [Scope])] = []
            for (extensionDecl, chain) in pending {
                let virtualScope = extensionDecl.virtualScope!
                if let base = resolveBase(extensionDecl.base, chain: chain)
                    as? Symbol.NominalTypeSymbol
                {
                    merge(virtualScope, into: base, chain: chain, extensionDecl: extensionDecl)
                    progressed = true
                } else {
                    remaining.append((extensionDecl, chain))
                }
            }
            pending = remaining
        }
        for (extensionDecl, _) in pending {
            context.emitError(
                "extension of type '\(baseName(extensionDecl.base))' has no matching declaration",
                at: extensionDecl.token
            )
        }
        pending = []
    }

    private func merge(
        _ virtualScope: Scope, into base: Symbol.NominalTypeSymbol, chain: [Scope],
        extensionDecl: AST.ExtensionDecl
    ) {
        let baseScope = base.scope
        for (_, symbol) in virtualScope.types {
            symbol.memberOf = base.id
            baseScope.registerType(
                symbol, at: symbol.sourceToken ?? extensionDecl.token, context: context
            )
        }
        for (_, symbols) in virtualScope.values {
            for symbol in symbols {
                adopt(symbol, into: base.id)
                if let function = symbol as? Symbol.FunctionSymbol, function.kind == .Initializer {
                    base.initializers.append(function)
                }
                baseScope.registerValue(
                    symbol, at: symbol.sourceToken ?? extensionDecl.token, context: context
                )
            }
        }
        adoptAccessors(of: extensionDecl, into: base.id)
        for (_, module) in virtualScope.modules {
            baseScope.registerModule(module)
        }
        for expression in extensionDecl.conformances {
            base.conformances.append(contentsOf: collectConformances(expression, chain: chain))
        }
    }

    private func adopt(_ symbol: Symbol.Symbol, into base: Id.SymbolId) {
        symbol.memberOf = base
        switch symbol {
        case let function as Symbol.FunctionSymbol:
            if function.kind == .Function {
                function.kind = .Method
            }
            adoptSelfSymbols(in: function.scope, into: base)
        case let subscriptSymbol as Symbol.SubscriptSymbol:
            adopt(subscriptSymbol.getter, into: base)
            if let setter = subscriptSymbol.setter {
                adopt(setter, into: base)
            }
        default:
            break
        }
    }

    private func adoptAccessors(of extensionDecl: AST.ExtensionDecl, into base: Id.SymbolId) {
        for statement in extensionDecl.body {
            guard let variableDecl = statement as? AST.VariableDecl else { continue }
            for accessor in variableDecl.accessors {
                if let symbol = accessor.symbol {
                    adopt(symbol, into: base)
                }
            }
        }
    }

    private func adoptSelfSymbols(in scope: Scope, into base: Id.SymbolId) {
        for symbols in scope.values.values {
            for symbol in symbols where symbol is Symbol.SelfSymbol {
                symbol.memberOf = base
            }
        }
    }

    private func collectConformances(
        _ expression: AST.Expression, chain: [Scope]
    ) -> [Symbol.ProtocolSymbol] {
        if let composition = expression as? AST.ProtocolCompositionType {
            return composition.types.flatMap { collectConformances($0, chain: chain) }
        }
        if let sequential = expression as? AST.Sequential,
           let members = sequential.compositionMemberBaseOperands()
        {
            return members.flatMap { collectConformances($0, chain: chain) }
        }
        if let binary = expression as? AST.Binary, binary.operatorToken.value == "&" {
            return collectConformances(binary.left, chain: chain)
                + collectConformances(binary.right, chain: chain)
        }
        if let protocolSymbol = resolveBase(expression, chain: chain) as? Symbol.ProtocolSymbol {
            return [protocolSymbol]
        }
        return []
    }

    private func resolveBase(_ expression: AST.Expression, chain: [Scope]) -> Symbol.Symbol? {
        switch expression {
        case let variable as AST.Variable:
            return lookupType(variable.name.value, chain: chain)
        case let memberAccess as AST.MemberAccess:
            guard let object = resolveBase(memberAccess.object, chain: chain) else {
                return nil
            }
            let scope = (object as? Symbol.NominalTypeSymbol)?.scope
                ?? (object as? Symbol.ModuleSymbol)?.scope
            return scope?.types[memberAccess.member.value]
        case let genericApplication as AST.GenericApplication:
            return resolveBase(genericApplication.base, chain: chain)
        case let sequential as AST.Sequential:
            guard
                sequential.genericApplicationGroupCloseIndex() != nil,
                let base = sequential.operands.first
            else {
                return nil
            }
            return resolveBase(base, chain: chain)
        default:
            return nil
        }
    }

    private func lookupType(_ name: String, chain: [Scope]) -> Symbol.Symbol? {
        for scope in chain.reversed() {
            if let symbol = scope.types[name] {
                return symbol
            }
            if let symbol = scope.modules[name] {
                return symbol
            }
        }
        return nil
    }

    private func baseName(_ expression: AST.Expression) -> String {
        switch expression {
        case let variable as AST.Variable:
            return variable.name.value
        case let memberAccess as AST.MemberAccess:
            return baseName(memberAccess.object) + "." + memberAccess.member.value
        case let genericApplication as AST.GenericApplication:
            return baseName(genericApplication.base)
        case let sequential as AST.Sequential:
            guard
                sequential.genericApplicationGroupCloseIndex() != nil,
                let base = sequential.operands.first
            else {
                return "<unknown>"
            }
            return baseName(base)
        default:
            return "<unknown>"
        }
    }
}
