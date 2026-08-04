import TrussCore

public final class NameResolver: AST.Visitor {
    private let context: Context
    private var scopeStack: [Scope] = []
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    override public func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        scopeStack.append(program.packageSymbol!.scope)
        super.visitProgram(program, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        scopeStack.append(moduleDecl.symbol!.scope)
        super.visitModuleDecl(moduleDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil)
        -> Any?
    {
        scopeStack.append(functionDecl.symbol!.scope)
        super.visitFunctionDecl(functionDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        guard let scope = closure.scope else {
            return super.visitClosure(closure, additional: additional)
        }
        scopeStack.append(scope)
        super.visitClosure(closure, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = structDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitStructDecl(structDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        resolveSuperclass(classDecl)
        guard let symbol = classDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitClassDecl(classDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil) -> Any? {
        guard let symbol = enumDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitEnumDecl(enumDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitProtocolDecl(
        _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = protocolDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitProtocolDecl(protocolDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    override public func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = actorDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitActorDecl(actorDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        return nil
    }

    private func resolveSuperclass(_ classDecl: AST.ClassDecl) {
        guard let first = classDecl.inheritanceClauses.first else { return }
        let nameExpression = (first as? AST.GenericApplication)?.base ?? first
        guard let variable = nameExpression as? AST.Variable,
              let (_, entries) = lookupScopeEntry(variable.name.value),
              let symbol = entries.first as? Symbol.NominalTypeSymbol,
              symbol.kind == .classDecl
        else { return }
        classDecl.symbol?.superclass = symbol
    }

    @discardableResult
    override public func visitVariable(_ variable: AST.Variable, additional _: Any? = nil) -> Any? {
        guard let (_, entries) = lookupScopeEntry(variable.name.value) else { return nil }
        if entries.allSatisfy({ $0 is Symbol.FunctionSymbol }) {
            variable.overloads = entries.map { $0 as! Symbol.FunctionSymbol }
            variable.symbol = nil
        } else {
            variable.symbol = entries[0]
        }
        return nil
    }

    @discardableResult
    override public func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional _: Any? = nil
    ) -> Any? {
        selfExpression.symbol = typeStack.last
        return nil
    }

    @discardableResult
    override public func visitSuperExpression(
        _ superExpression: AST.SuperExpression, additional _: Any? = nil
    ) -> Any? {
        superExpression.symbol = typeStack.last?.superclass
        return nil
    }

    @discardableResult
    override public func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        visit(memberAccess.object, additional: additional)
        guard let objectSymbol = resolvedSymbol(memberAccess.object) else { return nil }
        let (symbol, overloads): (Symbol.Symbol?, [Symbol.FunctionSymbol]?)
        if let typeSymbol = objectSymbol as? Symbol.NominalTypeSymbol {
            (symbol, overloads) = memberResolution(memberAccess.member.value, in: typeSymbol)
        } else if let moduleSymbol = objectSymbol as? Symbol.ModuleSymbol {
            (symbol, overloads) = memberResolution(memberAccess.member.value, in: moduleSymbol.scope)
        } else {
            return nil
        }
        memberAccess.symbol = symbol
        memberAccess.overloads = overloads
        return nil
    }

    @discardableResult
    override public func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional _: Any? = nil
    ) -> Any? {
        guard let type = typeStack.last else { return nil }
        let (symbol, overloads) = memberResolution(implicitMemberAccess.name.value, in: type)
        implicitMemberAccess.symbol = symbol
        implicitMemberAccess.overloads = overloads
        return nil
    }

    private func memberResolution(
        _ name: String, in type: Symbol.NominalTypeSymbol
    ) -> (Symbol.Symbol?, [Symbol.FunctionSymbol]?) {
        var current: Symbol.NominalTypeSymbol? = type
        while let currentType = current {
            let result = memberResolution(name, in: currentType.scope)
            if result.0 != nil || result.1 != nil {
                return result
            }
            current = currentType.superclass
        }
        return (nil, nil)
    }

    private func memberResolution(_ name: String, in scope: Scope) -> (
        Symbol.Symbol?, [Symbol.FunctionSymbol]?
    ) {
        if let typeEntry = scope.types[name] {
            return (typeEntry, nil)
        }
        if let entries = scope.values[name] {
            if entries.allSatisfy({ $0 is Symbol.FunctionSymbol }) {
                return (nil, entries.map { $0 as! Symbol.FunctionSymbol })
            }
            return (entries[0], nil)
        }
        if let moduleEntry = scope.modules[name] {
            return (moduleEntry, nil)
        }
        return (nil, nil)
    }

    private func resolvedSymbol(_ expression: AST.Expression) -> Symbol.Symbol? {
        if let variable = expression as? AST.Variable {
            return variable.symbol
        }
        if let member = expression as? AST.MemberAccess {
            return member.symbol
        }
        if let selfExpression = expression as? AST.SelfExpression {
            return selfExpression.symbol
        }
        if let superExpression = expression as? AST.SuperExpression {
            return superExpression.symbol
        }
        return nil
    }

    private func lookupScopeEntry(_ name: String) -> (Scope, [Symbol.Symbol])? {
        for scope in scopeStack.reversed() {
            if let symbol = scope.types[name] {
                return (scope, [symbol])
            }
            if let symbols = scope.values[name] {
                return (scope, symbols)
            }
            if let symbol = scope.modules[name] {
                return (scope, [symbol])
            }
        }
        return nil
    }
}
