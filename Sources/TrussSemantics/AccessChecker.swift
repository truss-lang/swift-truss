import SwiftBetterDiagnostic
import TrussCore

public final class AccessChecker: AST.Visitor {
    private let context: Context
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    private var scopeStack: [Scope] = []
    private var currentPackageSymbol: Symbol.PackageSymbol? = nil
    private var currentModuleSymbol: Symbol.ModuleSymbol? = nil

    private static let assignmentOperators: Set<String> = [
        "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=",
    ]

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        guard let packageSymbol = program.packageSymbol else { return nil }
        let lastPackage = currentPackageSymbol
        let lastModule = currentModuleSymbol
        currentPackageSymbol = packageSymbol
        currentModuleSymbol = nil
        scopeStack.append(packageSymbol.scope)
        super.visitProgram(program, additional: additional)
        scopeStack.removeLast()
        currentPackageSymbol = lastPackage
        currentModuleSymbol = lastModule
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil)
        -> Any?
    {
        guard let moduleSymbol = moduleDecl.symbol else { return nil }
        let lastModule = currentModuleSymbol
        currentModuleSymbol = moduleSymbol
        scopeStack.append(moduleSymbol.scope)
        super.visitModuleDecl(moduleDecl, additional: additional)
        scopeStack.removeLast()
        currentModuleSymbol = lastModule
        return nil
    }

    private func withType(_ type: Symbol.NominalTypeSymbol?, body: () -> Void) {
        guard let type else { return }
        typeStack.append(type)
        scopeStack.append(type.scope)
        body()
        scopeStack.removeLast()
        typeStack.removeLast()
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        withType(structDecl.symbol) {
            super.visitStructDecl(structDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        let symbol = classDecl.symbol as? Symbol.ClassSymbol
        if let symbol {
            if let superclass = resolveSuperclass(classDecl) {
                checkAccess(of: superclass, at: classDecl.name)
                if superclass.isFinal {
                    context.emitError(
                        "cannot inherit from final class '\(superclass.name)'",
                        at: classDecl.name
                    )
                }
                if !superclass.access.isAtLeast(symbol.access) {
                    context.emitError(
                        "'\(symbol.name)' must be declared \(superclass.access.sourceText) because its superclass '\(superclass.name)' is \(superclass.access.sourceText)",
                        at: classDecl.name
                    )
                }
            }
        }
        withType(symbol) {
            super.visitClassDecl(classDecl, additional: additional)
            if let symbol {
                checkAbstractImplementations(of: symbol, at: classDecl.name)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        withType(enumDecl.symbol) {
            super.visitEnumDecl(enumDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(
        _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
    ) -> Any? {
        withType(protocolDecl.symbol) {
            super.visitProtocolDecl(protocolDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        withType(actorDecl.symbol) {
            super.visitActorDecl(actorDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(
        _ extensionDecl: AST.ExtensionDecl, additional: Any? = nil
    ) -> Any? {
        guard let virtualScope = extensionDecl.virtualScope else { return nil }
        if let base = resolveTypeSymbol(extensionDecl.base) as? Symbol.NominalTypeSymbol {
            typeStack.append(base)
            scopeStack.append(virtualScope)
            for statement in extensionDecl.body {
                visit(statement, additional: additional)
            }
            scopeStack.removeLast()
            typeStack.removeLast()
        } else {
            scopeStack.append(virtualScope)
            for statement in extensionDecl.body {
                visit(statement, additional: additional)
            }
            scopeStack.removeLast()
        }
        return nil
    }

    private func withFunctionScope(
        _ symbol: Symbol.FunctionSymbol?, body: () -> Void
    ) {
        guard let symbol else { return }
        scopeStack.append(symbol.scope)
        body()
        scopeStack.removeLast()
    }

    private func checkAccess(of symbol: Symbol.Symbol, at token: Token) {
        if !isVisible(symbol, at: token, using: symbol.access) {
            context.emitError(
                "'\(symbol.name)' is \(symbol.access.sourceText)", at: token,
                notes: declarationNotes(of: symbol)
            )
        }
    }

    private func declarationNotes(of symbol: Symbol.Symbol) -> [Diagnostic] {
        guard let sourceToken = symbol.sourceToken,
              let source = context.sourceTable[sourceToken.id]
        else {
            return []
        }
        return [
            Diagnostic(
                severity: .note, message: "declared here",
                range: sourceToken.sourceRange(in: source.stringSourceBuffer)
            ),
        ]
    }

    private func isVisible(_ symbol: Symbol.Symbol, at token: Token, using level: AccessLevel) -> Bool {
        switch level {
        case .Open, .Public:
            return true
        case .Internal:
            if let symbolModule = symbol.moduleSymbol, let currentModule = currentModuleSymbol {
                return symbolModule === currentModule
            }
            return symbol.moduleSymbol == nil && currentModuleSymbol == nil
        case .PackagePrivate:
            return symbol.packageId == currentPackageSymbol?.id
        case .FilePrivate:
            return symbol.sourceToken?.id == token.id
        case .Private:
            return isPrivateVisible(symbol, at: token)
        case .Protected:
            return isProtectedVisible(symbol)
        }
    }

    private func isPrivateVisible(_ symbol: Symbol.Symbol, at token: Token) -> Bool {
        guard symbol.sourceToken?.id == token.id else { return false }
        guard let memberOf = symbol.memberOf else { return true }
        return typeStack.last?.id == memberOf
    }

    private func isProtectedVisible(_ symbol: Symbol.Symbol) -> Bool {
        guard let memberOf = symbol.memberOf,
              let declaring = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol,
              let accessPoint = typeStack.last
        else {
            return false
        }
        var current: Symbol.NominalTypeSymbol? = accessPoint
        while let c = current {
            if c.id == declaring.id { return true }
            current = (c as? Symbol.ClassSymbol)?.superclass
        }
        return false
    }

    private func tokenOf(_ expression: AST.Expression) -> Token? {
        switch expression {
        case let variable as AST.Variable:
            variable.name
        case let member as AST.MemberAccess:
            member.member
        case let call as AST.Call:
            tokenOf(call.callee)
        case let subscriptExpression as AST.Subscript:
            tokenOf(subscriptExpression.base)
        default:
            nil
        }
    }

    @discardableResult
    public override func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        visit(memberAccess.object, additional: additional)
        if let symbol = memberAccess.symbol ?? memberSymbol(of: memberAccess) {
            checkAccess(of: symbol, at: memberAccess.member)
        }
        return nil
    }

    @discardableResult
    public override func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        if let symbol = implicitMemberAccess.symbol {
            checkAccess(of: symbol, at: implicitMemberAccess.name)
        }
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
        if let overloads = subscriptExpression.overloads, !overloads.isEmpty,
           let token = tokenOf(subscriptExpression.base)
        {
            let anyVisible = overloads.contains {
                isVisible($0, at: token, using: $0.access)
            }
            if !anyVisible, let first = overloads.first {
                checkAccess(of: first, at: token)
            }
        }
        return nil
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil)
        -> Any?
    {
        if let symbol = variable.symbol,
           !(symbol is Symbol.ModuleSymbol),
           !(symbol is Symbol.PackageSymbol)
        {
            checkAccess(of: symbol, at: variable.name)
        }
        return nil
    }

    @discardableResult
    public override func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        visit(call.callee, additional: additional)
        for argument in call.arguments {
            visit(argument.value, additional: additional)
        }
        for (_, closure) in call.trailingClosures {
            visit(closure, additional: additional)
        }
        if let variable = call.callee as? AST.Variable,
           let symbol = variable.symbol as? Symbol.ClassSymbol,
           symbol.isAbstract
        {
            context.emitError(
                "cannot instantiate abstract class '\(symbol.name)'", at: variable.name
            )
        }
        return nil
    }

    @discardableResult
    public override func visitBinary(_ binary: AST.Binary, additional: Any? = nil) -> Any? {
        visit(binary.left, additional: additional)
        visit(binary.right, additional: additional)
        if Self.assignmentOperators.contains(binary.operatorToken.value) {
            checkWriteAccess(of: binary.left)
        }
        return nil
    }

    private func checkWriteAccess(of target: AST.Expression) {
        switch target {
        case let variable as AST.Variable:
            if let symbol = variable.symbol {
                checkSetter(of: symbol, at: variable.name)
            }
        case let member as AST.MemberAccess:
            if let symbol = member.symbol ?? memberSymbol(of: member) {
                checkSetter(of: symbol, at: member.member)
            }
        default:
            break
        }
    }

    private func checkSetter(of symbol: Symbol.Symbol, at token: Token) {
        let setter = symbol.setterAccess ?? symbol.access
        if !isVisible(symbol, at: token, using: setter) {
            context.emitError(
                "cannot assign to '\(symbol.name)': its setter is \(setter.sourceText)",
                at: token,
                notes: declarationNotes(of: symbol)
            )
        }
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        if let symbol = functionDecl.symbol {
            checkOverride(
                of: symbol,
                hasOverrideModifier: hasModifier(.Override, in: functionDecl.modifiers),
                at: functionDecl.name
            )
            checkDeclarationAccess(
                of: symbol,
                typeExpressions: functionDecl.parameters.map(\.type),
                returnExpression: functionDecl.returnTypeExpression,
                what: "method", name: functionDecl.name
            )
        }
        withFunctionScope(functionDecl.symbol) {
            super.visitFunctionDecl(functionDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil)
        -> Any?
    {
        if let symbol = initDecl.symbol {
            checkOverride(
                of: symbol,
                hasOverrideModifier: hasModifier(.Override, in: initDecl.modifiers),
                at: initDecl.token
            )
            checkDeclarationAccess(
                of: symbol,
                typeExpressions: initDecl.parameters.map(\.type),
                returnExpression: nil,
                what: "initializer", name: initDecl.token
            )
        }
        withFunctionScope(initDecl.symbol) {
            super.visitInitDecl(initDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        if let symbol = subscriptDecl.symbol {
            checkOverride(
                of: symbol,
                hasOverrideModifier: hasModifier(.Override, in: subscriptDecl.modifiers),
                at: subscriptDecl.token
            )
            checkDeclarationAccess(
                of: symbol,
                typeExpressions: subscriptDecl.parameters.map(\.type),
                returnExpression: subscriptDecl.returnType,
                what: "subscript", name: subscriptDecl.token
            )
        }
        withFunctionScope(subscriptDecl.symbol) {
            super.visitSubscriptDecl(subscriptDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        if let symbol = variableDecl.symbol {
            checkOverride(
                of: symbol,
                hasOverrideModifier: hasModifier(.Override, in: variableDecl.modifiers),
                at: variableDecl.name
            )
            checkDeclarationAccess(
                of: symbol,
                typeExpressions: [variableDecl.typeExpression],
                returnExpression: nil,
                what: "property", name: variableDecl.name
            )
        }
        super.visitVariableDecl(variableDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(
        _ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil
    ) -> Any? {
        if let symbol = typeAliasDecl.symbol {
            checkDeclarationAccess(
                of: symbol,
                typeExpressions: [typeAliasDecl.typeExpression],
                returnExpression: nil,
                what: "typealias", name: typeAliasDecl.name
            )
        }
        super.visitTypeAliasDecl(typeAliasDecl, additional: additional)
        return nil
    }

    private func hasModifier(_ kind: AST.ModifierKind, in modifiers: [AST.Modifier]) -> Bool {
        modifiers.contains { modifier in
            switch (kind, modifier.kind) {
            case (.Override, .Override): true
            default: false
            }
        }
    }

    private func checkDeclarationAccess(
        of symbol: Symbol.Symbol, typeExpressions: [AST.Expression?],
        returnExpression: AST.Expression?, what: String, name: Token
    ) {
        for typeExpression in typeExpressions {
            if let typeExpression, let typeSymbol = resolveTypeSymbol(typeExpression) {
                checkTypeUse(typeSymbol, in: symbol, at: name, what: what, name: name, detail: "parameter")
            }
        }
        if let returnExpression, let typeSymbol = resolveTypeSymbol(returnExpression) {
            checkTypeUse(typeSymbol, in: symbol, at: name, what: what, name: name, detail: "return type")
        }
    }

    private func checkTypeUse(
        _ typeSymbol: Symbol.Symbol, in declSymbol: Symbol.Symbol, at token: Token,
        what: String, name: Token, detail: String
    ) {
        guard typeSymbol is Symbol.NominalTypeSymbol || typeSymbol is Symbol.TypeAliasSymbol else {
            return
        }
        checkAccess(of: typeSymbol, at: token)
        if !typeSymbol.access.isAtLeast(declSymbol.access) {
            context.emitError(
                "\(what) '\(name.value)' must be declared \(typeSymbol.access.sourceText) because its \(detail) uses a \(typeSymbol.access.sourceText) type '\(typeSymbol.name)'",
                at: token
            )
        }
    }

    private func checkOverride(
        of symbol: Symbol.Symbol, hasOverrideModifier: Bool, at token: Token
    ) {
        guard let enclosing = typeStack.last as? Symbol.ClassSymbol else { return }
        guard let target = findOverrideTarget(symbol.name, from: enclosing.superclass) else {
            if hasOverrideModifier {
                context.emitError(
                    "method '\(symbol.name)' does not override any method from its superclass",
                    at: token
                )
            }
            return
        }
        if hasOverrideModifier {
            if target.isFinal {
                context.emitError(
                    "cannot override final member '\(target.name)'", at: token
                )
            } else if !target.isAbstract, target.access != .Open, target.access != .Protected {
                context.emitError(
                    "cannot override non-open member '\(target.name)'", at: token
                )
            }
        } else if target.access == .Open || target.access == .Protected || target.isAbstract {
            context.emitError(
                "overriding declaration requires an 'override' keyword", at: token
            )
        }
    }

    private func findOverrideTarget(
        _ name: String, from superclass: Symbol.ClassSymbol?
    ) -> Symbol.Symbol? {
        var current = superclass
        while let c = current {
            if let symbol = c.scope.values[name]?.first(where: {
                $0.access != .Private && $0.access != .FilePrivate
            }) {
                return symbol
            }
            current = c.superclass
        }
        return nil
    }

    private func checkAbstractImplementations(of classSymbol: Symbol.ClassSymbol, at token: Token) {
        guard !classSymbol.isAbstract else { return }
        var missing: [Symbol.FunctionSymbol] = []
        var current = classSymbol.superclass
        while let c = current {
            for symbol in c.scope.values.values.flatMap({ $0 }) {
                if let function = symbol as? Symbol.FunctionSymbol,
                   function.isAbstract,
                   !hasImplementation(of: function, in: classSymbol)
                {
                    missing.append(function)
                }
            }
            current = c.superclass
        }
        for function in missing {
            context.emitError(
                "missing implementation of abstract member '\(function.name)'", at: token
            )
        }
    }

    private func hasImplementation(
        of abstract: Symbol.FunctionSymbol, in classSymbol: Symbol.ClassSymbol
    ) -> Bool {
        var current: Symbol.NominalTypeSymbol? = classSymbol
        while let c = current {
            let symbols = c.scope.values[abstract.name] ?? []
            if symbols.contains(where: { symbol in
                if let function = symbol as? Symbol.FunctionSymbol {
                    return !function.isAbstract
                }
                return true
            }) {
                return true
            }
            current = (c as? Symbol.ClassSymbol)?.superclass
        }
        return false
    }

    private func memberSymbol(of memberAccess: AST.MemberAccess) -> Symbol.Symbol? {
        guard let declaring = staticTypeSymbol(of: memberAccess.object) else { return nil }
        return declaring.scope.values[memberAccess.member.value]?.first
    }

    private func staticTypeSymbol(of expression: AST.Expression) -> Symbol.NominalTypeSymbol? {
        guard let ty = expression.ty else { return nil }
        let nominal: TrussType.NominalType? =
            ty as? TrussType.NominalType
                ?? (ty as? TrussType.OptionalType)?.wrapped as? TrussType.NominalType
                ?? (ty as? TrussType.GenericInstantiation)?.base as? TrussType.NominalType
        guard let nominal else { return nil }
        for symbol in context.id2Symbol.values {
            if let nominalSymbol = symbol as? Symbol.NominalTypeSymbol,
               nominalSymbol.typeId == nominal.id
            {
                return nominalSymbol
            }
        }
        return nil
    }

    private func resolveSuperclass(_ classDecl: AST.ClassDecl) -> Symbol.ClassSymbol? {
        guard let first = classDecl.inheritanceClauses.first else { return nil }
        return resolveTypeSymbol(first) as? Symbol.ClassSymbol
    }

    private func resolveTypeSymbol(_ expression: AST.Expression) -> Symbol.Symbol? {
        switch expression {
        case let variable as AST.Variable:
            return lookupType(variable.name.value)
        case let member as AST.MemberAccess:
            guard let object = resolveTypeSymbol(member.object) else { return nil }
            let scope = (object as? Symbol.NominalTypeSymbol)?.scope
                ?? (object as? Symbol.ModuleSymbol)?.scope
            return scope?.types[member.member.value]
        case let generic as AST.GenericApplication:
            return resolveTypeSymbol(generic.base)
        case let sequential as AST.Sequential:
            guard
                sequential.genericApplicationGroupCloseIndex() != nil,
                let base = sequential.operands.first
            else {
                return nil
            }
            return resolveTypeSymbol(base)
        case let optional as AST.OptionalType:
            return resolveTypeSymbol(optional.wrappedType)
        case let variadic as AST.VariadicType:
            return resolveTypeSymbol(variadic.base)
        default:
            return nil
        }
    }

    private func lookupType(_ name: String) -> Symbol.Symbol? {
        for scope in scopeStack.reversed() {
            if let symbol = scope.types[name] {
                return symbol
            }
            if let symbol = scope.modules[name] {
                return symbol
            }
        }
        return nil
    }
}
