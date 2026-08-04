import TrussCore

public final class NameResolver: AST.Visitor {
    private let context: Context
    private var scopeStack: [Scope] = []
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
    public override func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        visit(memberAccess.object, additional: additional)
        guard let objectSymbol = resolvedSymbol(memberAccess.object) else { return nil }
        let scope: Scope?
        if let typeSymbol = objectSymbol as? Symbol.NominalTypeSymbol {
            scope = typeSymbol.scope
        } else if let moduleSymbol = objectSymbol as? Symbol.ModuleSymbol {
            scope = moduleSymbol.scope
        } else {
            return nil
        }
        guard let scope = scope else { return nil }
        let name = memberAccess.member.value
        if let typeEntry = scope.types[name] {
            memberAccess.symbol = typeEntry
        } else if let entries = scope.values[name] {
            if entries.allSatisfy({ $0 is Symbol.FunctionSymbol }) {
                memberAccess.overloads = entries.map { $0 as! Symbol.FunctionSymbol }
            } else {
                memberAccess.symbol = entries[0]
            }
        } else if let moduleEntry = scope.modules[name] {
            memberAccess.symbol = moduleEntry
        }
        return nil
    }

    private func resolvedSymbol(_ expression: AST.Expression) -> Symbol.Symbol? {
        if let variable = expression as? AST.Variable {
            return variable.symbol
        }
        if let member = expression as? AST.MemberAccess {
            return member.symbol
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
