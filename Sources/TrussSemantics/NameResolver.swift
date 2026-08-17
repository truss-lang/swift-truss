import SwiftBetterDiagnostic
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
    public override func visitExtensionDecl(
        _ extensionDecl: AST.ExtensionDecl, additional: Any? = nil
    ) -> Any? {
        guard let base = resolveBase(extensionDecl.base) as? Symbol.NominalTypeSymbol else {
            return super.visitExtensionDecl(extensionDecl, additional: additional)
        }
        scopeStack.append(base.scope)
        typeStack.append(base)
        super.visitExtensionDecl(extensionDecl, additional: additional)
        typeStack.removeLast()
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
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil)
        -> Any?
    {
        guard let symbol = initDecl.symbol else {
            return super.visitInitDecl(initDecl, additional: additional)
        }
        scopeStack.append(symbol.scope)
        super.visitInitDecl(initDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        guard let symbol = subscriptDecl.symbol else {
            return super.visitSubscriptDecl(subscriptDecl, additional: additional)
        }
        scopeStack.append(symbol.scope)
        super.visitSubscriptDecl(subscriptDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStmt: AST.For, additional: Any? = nil) -> Any? {
        guard let scope = forStmt.scope else {
            return super.visitFor(forStmt, additional: additional)
        }
        scopeStack.append(scope)
        super.visitFor(forStmt, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil)
        -> Any?
    {
        guard let scope = deinitDecl.scope else {
            return super.visitDeinitDecl(deinitDecl, additional: additional)
        }
        scopeStack.append(scope)
        super.visitDeinitDecl(deinitDecl, additional: additional)
        scopeStack.removeLast()
        return nil
    }

    @discardableResult
    public override func visitAccessor(_ accessor: AST.Accessor, additional: Any? = nil)
        -> Any?
    {
        guard let scope = accessor.scope else {
            return super.visitAccessor(accessor, additional: additional)
        }
        scopeStack.append(scope)
        super.visitAccessor(accessor, additional: additional)
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
    public override func visitIf(_ ifExpr: AST.If, additional: Any? = nil) -> Any? {
        visit(ifExpr.condition, additional: additional)
        if let scope = ifExpr.scope {
            scopeStack.append(scope)
        }
        for statement in ifExpr.then {
            visit(statement, additional: additional)
        }
        if let elseKind = ifExpr.elseKind {
            switch elseKind {
            case let .Block(statements):
                for statement in statements {
                    visit(statement, additional: additional)
                }
            case let .If(elseIf):
                visitIf(elseIf, additional: additional)
            }
        }
        if ifExpr.scope != nil {
            scopeStack.removeLast()
        }
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStmt: AST.While, additional: Any? = nil) -> Any? {
        visit(whileStmt.condition, additional: additional)
        if let scope = whileStmt.scope {
            scopeStack.append(scope)
        }
        for statement in whileStmt.body {
            visit(statement, additional: additional)
        }
        if whileStmt.scope != nil {
            scopeStack.removeLast()
        }
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        if let scope = repeatWhile.scope {
            scopeStack.append(scope)
        }
        for statement in repeatWhile.body {
            visit(statement, additional: additional)
        }
        visit(repeatWhile.condition, additional: additional)
        if repeatWhile.scope != nil {
            scopeStack.removeLast()
        }
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
            guard let base = resolveBase(expression) as? Symbol.ClassSymbol else { continue }
            symbol.superclass = base
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
            if let sequential = expression as? AST.Sequential,
               let members = sequential.compositionMemberBaseOperands()
            {
                collectConformances(members, into: symbol)
                continue
            }
            if let binary = expression as? AST.Binary, binary.operatorToken.value == "&" {
                collectConformances([binary.left, binary.right], into: symbol)
                continue
            }
            let base = genericBase(expression)
            guard let resolved = resolvedSymbol(base) else { continue }
            if let classSymbol = symbol as? Symbol.ClassSymbol,
               let baseClass = resolved as? Symbol.ClassSymbol,
               classSymbol.superclass == nil
            {
                classSymbol.superclass = baseClass
            } else if let protocolSymbol = resolved as? Symbol.ProtocolSymbol {
                if symbol.conformances.contains(where: { $0.id == protocolSymbol.id }) {
                    context.emitError(
                        "duplicate conformance to protocol '\(protocolSymbol.name)'",
                        at: expression.sourceRange
                    )
                } else {
                    symbol.conformances.append(protocolSymbol)
                }
            }
        }
    }

    private func genericBase(_ expression: AST.Expression) -> AST.Expression {
        if let genericApplication = expression as? AST.GenericApplication {
            return genericApplication.base
        }
        if let sequential = expression as? AST.Sequential,
           sequential.genericApplicationGroupCloseIndex() != nil,
           let base = sequential.operands.first
        {
            return base
        }
        return expression
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
    public override func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        super.visitCall(call, additional: additional)
        switch call.callee {
        case let variable as AST.Variable:
            if let nominal = variable.symbol as? Symbol.NominalTypeSymbol {
                call.overloads = memberResolution("init", in: nominal).1
            } else {
                call.overloads = variable.overloads
            }
        case let memberAccess as AST.MemberAccess:
            call.overloads = memberAccess.overloads
        case let genericApplication as AST.GenericApplication:
            if let nominal = resolvedSymbol(genericApplication.base)
                as? Symbol.NominalTypeSymbol
            {
                call.overloads = memberResolution("init", in: nominal).1
            } else if let overloads = calleeOverloads(genericApplication.base) {
                call.overloads = overloads
            }
        case let sequential as AST.Sequential:
            if let base = sequential.operands.first,
               let nominal = resolvedSymbol(base) as? Symbol.NominalTypeSymbol
            {
                call.overloads = memberResolution("init", in: nominal).1
            } else if let base = sequential.operands.first,
                      let overloads = calleeOverloads(base)
            {
                call.overloads = overloads
            }
        default:
            break
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
        } else if let packageSymbol = objectSymbol as? Symbol.PackageSymbol {
            (symbol, overloads) = memberResolution(memberAccess.member.value, in: packageSymbol.scope)
        } else {
            return nil
        }
        memberAccess.symbol = symbol
        memberAccess.overloads = overloads
        return nil
    }

    @discardableResult
    public override func visitSubscript(
        _ subscriptExpression: AST.Subscript, additional: Any? = nil
    ) -> Any? {
        visit(subscriptExpression.base, additional: additional)
        for argument in subscriptExpression.arguments {
            visit(argument.value, additional: additional)
        }
        guard let baseSymbol = resolvedSymbol(subscriptExpression.base) else { return nil }
        if let typeSymbol = baseSymbol as? Symbol.NominalTypeSymbol {
            subscriptExpression.overloads = memberResolution("subscript", in: typeSymbol).1
        }
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

    private func calleeOverloads(_ expression: AST.Expression) -> [Symbol.FunctionSymbol]? {
        if let variable = expression as? AST.Variable {
            return variable.overloads
        }
        if let member = expression as? AST.MemberAccess {
            return member.overloads
        }
        if let call = expression as? AST.Call {
            return call.overloads
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
        if let selfExpression = expression as? AST.SelfExpression {
            return selfExpression.symbol
        }
        if let superExpression = expression as? AST.SuperExpression {
            return superExpression.symbol
        }
        if let generic = expression as? AST.GenericApplication {
            return resolvedSymbol(generic.base)
        }
        if let sequential = expression as? AST.Sequential,
           sequential.genericApplicationGroupCloseIndex() != nil,
           let base = sequential.operands.first
        {
            return resolvedSymbol(base)
        }
        return nil
    }

    private func resolveBase(_ expression: AST.Expression) -> Symbol.Symbol? {
        switch expression {
        case let variable as AST.Variable:
            return lookupScopeEntry(variable.name.value)?.1.first
        case let memberAccess as AST.MemberAccess:
            guard let object = resolveBase(memberAccess.object) else { return nil }
            let scope = (object as? Symbol.NominalTypeSymbol)?.scope
                ?? (object as? Symbol.ModuleSymbol)?.scope
                ?? (object as? Symbol.PackageSymbol)?.scope
            return scope?.types[memberAccess.member.value]
        case let genericApplication as AST.GenericApplication:
            return resolveBase(genericApplication.base)
        case let sequential as AST.Sequential:
            guard
                sequential.genericApplicationGroupCloseIndex() != nil,
                let base = sequential.operands.first
            else {
                return nil
            }
            return resolveBase(base)
        default:
            return nil
        }
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
        if let package = context.name2Package[name] {
            return (package.scope, [package])
        }
        return nil
    }
}
