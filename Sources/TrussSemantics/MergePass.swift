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
        guard let packageSymbol = program.packageSymbol else { return nil }
        scopeStack.append(packageSymbol.scope)
        super.visitProgram(program, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        guard let moduleSymbol = moduleDecl.symbol else { return nil }
        scopeStack.append(moduleSymbol.scope)
        super.visitModuleDecl(moduleDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil)
        -> Any?
    {
        guard let virtualScope = extensionDecl.virtualScope else { return nil }
        if let base = resolveBase(extensionDecl.base, chain: scopeStack) {
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
                if let virtualScope = extensionDecl.virtualScope,
                   let base = resolveBase(extensionDecl.base, chain: chain)
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
            baseScope.registerType(
                symbol, at: symbol.sourceToken ?? extensionDecl.token, context: context
            )
        }
        for (_, symbols) in virtualScope.values {
            for symbol in symbols {
                baseScope.registerValue(
                    symbol, at: symbol.sourceToken ?? extensionDecl.token, context: context
                )
            }
        }
        for (_, module) in virtualScope.modules {
            baseScope.registerModule(module)
        }
        for expression in extensionDecl.conformances {
            collectConformances(expression, chain: chain, into: &base.conformances)
        }
    }

    private func collectConformances(
        _ expression: AST.Expression, chain: [Scope],
        into protocols: inout [Symbol.ProtocolSymbol]
    ) {
        if let composition = expression as? AST.ProtocolCompositionType {
            for type in composition.types {
                collectConformances(type, chain: chain, into: &protocols)
            }
            return
        }
        if let sequential = expression as? AST.SequentialExpression,
           sequential.ops.allSatisfy({ $0.value == "&" })
        {
            for operand in sequential.operands {
                collectConformances(operand, chain: chain, into: &protocols)
            }
            return
        }
        if let protocolSymbol = resolveProtocol(expression, chain: chain) {
            protocols.append(protocolSymbol)
        }
    }

    private func resolveProtocol(
        _ expression: AST.Expression, chain: [Scope]
    ) -> Symbol.ProtocolSymbol? {
        switch expression {
        case let variable as AST.Variable:
            return lookupType(variable.name.value, chain: chain) as? Symbol.ProtocolSymbol
        case let memberAccess as AST.MemberAccess:
            guard let object = resolveBase(memberAccess.object, chain: chain) else { return nil }
            return object.scope.types[memberAccess.member.value] as? Symbol.ProtocolSymbol
        case let genericApplication as AST.GenericApplication:
            return resolveProtocol(genericApplication.base, chain: chain)
        default:
            return nil
        }
    }

    private func resolveBase(_ expression: AST.Expression, chain: [Scope]) -> Symbol.NominalTypeSymbol? {
        switch expression {
        case let variable as AST.Variable:
            return lookupType(variable.name.value, chain: chain) as? Symbol.NominalTypeSymbol
        case let memberAccess as AST.MemberAccess:
            guard let object = resolveBase(memberAccess.object, chain: chain) else {
                return nil
            }
            return object.scope.types[memberAccess.member.value]
                as? Symbol.NominalTypeSymbol
        case let genericApplication as AST.GenericApplication:
            return resolveBase(genericApplication.base, chain: chain)
        default:
            return nil
        }
    }

    private func lookupType(_ name: String, chain: [Scope]) -> Symbol.Symbol? {
        for scope in chain.reversed() {
            if let symbol = scope.types[name] {
                return symbol
            }
        }
        return nil
    }

    private func baseName(_ expression: AST.Expression) -> String {
        switch expression {
        case let variable as AST.Variable:
            variable.name.value
        case let memberAccess as AST.MemberAccess:
            baseName(memberAccess.object) + "." + memberAccess.member.value
        case let genericApplication as AST.GenericApplication:
            baseName(genericApplication.base)
        default:
            "<unknown>"
        }
    }
}
