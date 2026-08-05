import TrussCore

public final class NameResolver: AST.Visitor {
    private let context: Context
    private var scopeStack: [Scope] = []
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        scopeStack.append(program.packageSymbol!.scope)
        super.visitProgram(program, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        scopeStack.append(moduleDecl.symbol!.scope)
        super.visitModuleDecl(moduleDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil)
        -> Any?
    {
        scopeStack.append(functionDecl.symbol!.scope)
        super.visitFunctionDecl(functionDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        guard let scope = closure.scope else {
            return super.visitClosure(closure, additional: additional)
        }
        scopeStack.append(scope)
        super.visitClosure(closure, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = structDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitStructDecl(structDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        collectConformances(structDecl.conformances, into: symbol)
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = classDecl.symbol else { return nil }
        if let classSymbol = symbol as? Symbol.ClassSymbol {
            resolveSuperclass(classDecl.inheritanceClauses, into: classSymbol)
        }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitClassDecl(classDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        collectConformances(classDecl.inheritanceClauses, into: symbol)
        return nil
    }

    private func resolveSuperclass(
        _ clauses: [AST.Expression], into symbol: Symbol.ClassSymbol
    ) {
        for expression in clauses {
            let base = (expression as? AST.GenericApplication)?.base ?? expression
            guard let variable = base as? AST.Variable,
                  let (_, entries) = lookupScopeEntry(variable.name.value),
                  let classSymbol = entries.first as? Symbol.ClassSymbol
            else { continue }
            symbol.superclass = classSymbol
            return
        }
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil) -> Any? {
        guard let symbol = enumDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitEnumDecl(enumDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        collectConformances(enumDecl.conformances, into: symbol)
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(
        _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = protocolDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitProtocolDecl(protocolDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        collectConformances(protocolDecl.conformances, into: symbol)
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = actorDecl.symbol else { return nil }
        scopeStack.append(symbol.scope)
        typeStack.append(symbol)
        super.visitActorDecl(actorDecl, additional: additional)
        typeStack.removeLast()
        scopeStack.removeLast()
        collectConformances(actorDecl.conformances, into: symbol)
        return nil
    }

    private func collectConformances(
        _ expressions: [AST.Expression], into symbol: Symbol.NominalTypeSymbol
    ) {
        for expression in expressions {
            if let composition = expression as? AST.ProtocolCompositionType {
                for type in composition.types {
                    collectConformances([type], into: symbol)
                }
                continue
            }
            if let sequential = expression as? AST.SequentialExpression,
               sequential.ops.allSatisfy({ $0.value == "&" })
            {
                for operand in sequential.operands {
                    collectConformances([operand], into: symbol)
                }
                continue
            }
            if let binary = expression as? AST.Binary, binary.operatorToken.value == "&" {
                collectConformances([binary.left, binary.right], into: symbol)
                continue
            }
            let base = (expression as? AST.GenericApplication)?.base ?? expression
            guard let resolved = resolvedSymbol(base) else { continue }
            if let classSymbol = symbol as? Symbol.ClassSymbol,
               let baseClass = resolved as? Symbol.ClassSymbol,
               classSymbol.superclass == nil
            {
                classSymbol.superclass = baseClass
            } else if let protocolSymbol = resolved as? Symbol.ProtocolSymbol {
                symbol.conformances.append(protocolSymbol)
            }
        }
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
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
    public override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        selfExpression.symbol = typeStack.last
        return nil
    }

    @discardableResult
    public override func visitSuperExpression(
        _ superExpression: AST.SuperExpression, additional: Any? = nil
    ) -> Any? {
        superExpression.symbol = (typeStack.last as? Symbol.ClassSymbol)?.superclass
        return nil
    }

    @discardableResult
    public override func visitMemberAccess(
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
    public override func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        guard let type = typeStack.last else { return nil }
        let (symbol, overloads) = memberResolution(implicitMemberAccess.name.value, in: type)
        implicitMemberAccess.symbol = symbol
        implicitMemberAccess.overloads = overloads
        return nil
    }

    @discardableResult
    public override func visitKeyPathExpression(
        _ keyPathExpression: AST.KeyPathExpression, additional: Any? = nil
    ) -> Any? {
        if let root = keyPathExpression.root {
            visit(root, additional: additional)
        }
        var base = keyPathExpression.root.flatMap { resolvedSymbol($0) }
        for component in keyPathExpression.components {
            guard let baseSymbol = base else { break }
            if component.name.kind == .Keyword(.SelfKw) {
                component.symbol = baseSymbol
                continue
            }
            let (symbol, overloads): (Symbol.Symbol?, [Symbol.FunctionSymbol]?)
            if let typeSymbol = baseSymbol as? Symbol.NominalTypeSymbol {
                (symbol, overloads) = memberResolution(component.name.value, in: typeSymbol)
            } else if let moduleSymbol = baseSymbol as? Symbol.ModuleSymbol {
                (symbol, overloads) = memberResolution(component.name.value, in: moduleSymbol.scope)
            } else {
                break
            }
            component.symbol = symbol
            component.overloads = overloads
            if let typeSymbol = symbol as? Symbol.NominalTypeSymbol {
                base = typeSymbol
            } else {
                base = nil
            }
        }
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
            current = (currentType as? Symbol.ClassSymbol)?.superclass
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
