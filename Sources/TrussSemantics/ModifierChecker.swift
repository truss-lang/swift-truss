import TrussCore

public final class ModifierChecker: AST.Visitor {
    private let context: Context
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    private var abstractClassStack: [Bool] = []

    public init(context: Context) {
        self.context = context
    }

    private var enclosingClass: Symbol.ClassSymbol? {
        typeStack.last as? Symbol.ClassSymbol
    }

    private var enclosingStructOrEnum: Bool {
        typeStack.last is Symbol.StructSymbol || typeStack.last is Symbol.EnumSymbol
    }

    private var enclosingActor: Bool {
        typeStack.last is Symbol.ActorSymbol
    }

    private var enclosingType: Bool {
        !typeStack.isEmpty
    }

    private var enclosingClassIsAbstract: Bool {
        abstractClassStack.last ?? false
    }

    private func kindText(_ kind: AST.ModifierKind) -> String {
        switch kind {
        case let .Open(setter): setter ? "open(set)" : "open"
        case let .Public(setter): setter ? "public(set)" : "public"
        case let .Protected(setter): setter ? "protected(set)" : "protected"
        case let .PackagePrivate(setter): setter ? "packageprivate(set)" : "packageprivate"
        case let .Internal(setter): setter ? "internal(set)" : "internal"
        case let .FilePrivate(setter): setter ? "fileprivate(set)" : "fileprivate"
        case let .Private(setter): setter ? "private(set)" : "private"
        case .Abstract: "abstract"
        case .Final: "final"
        case .Mutating: "mutating"
        case .Nonmutating: "nonmutating"
        case .Convenience: "convenience"
        case .Override: "override"
        case .Static: "static"
        case .Lazy: "lazy"
        case .Weak: "weak"
        case .Unowned: "unowned"
        case .Indirect: "indirect"
        case .Isolated: "isolated"
        }
    }

    private func isSetterOnly(_ kind: AST.ModifierKind) -> Bool {
        switch kind {
        case .Open(true), .Public(true), .Protected(true), .PackagePrivate(true),
             .Internal(true), .FilePrivate(true), .Private(true):
            true
        default:
            false
        }
    }

    private func isPlainAccess(_ kind: AST.ModifierKind) -> Bool {
        kind.accessLevel != nil && !isSetterOnly(kind)
    }

    private func isOpen(_ kind: AST.ModifierKind) -> Bool {
        if case .Open = kind { return true }
        return false
    }

    private func isProtected(_ kind: AST.ModifierKind) -> Bool {
        if case .Protected = kind { return true }
        return false
    }

    private func isAbstract(_ kind: AST.ModifierKind) -> Bool {
        if case .Abstract = kind { return true }
        return false
    }

    private func isFinal(_ kind: AST.ModifierKind) -> Bool {
        if case .Final = kind { return true }
        return false
    }

    private func isStatic(_ kind: AST.ModifierKind) -> Bool {
        if case .Static = kind { return true }
        return false
    }

    private func isMutating(_ kind: AST.ModifierKind) -> Bool {
        if case .Mutating = kind { return true }
        return false
    }

    private func isOverride(_ kind: AST.ModifierKind) -> Bool {
        if case .Override = kind { return true }
        return false
    }

    private func isNonmutating(_ kind: AST.ModifierKind) -> Bool {
        if case .Nonmutating = kind { return true }
        return false
    }

    private func isIsolated(_ kind: AST.ModifierKind) -> Bool {
        if case .Isolated = kind { return true }
        return false
    }

    private func isConvenience(_ kind: AST.ModifierKind) -> Bool {
        if case .Convenience = kind { return true }
        return false
    }

    private func isLazy(_ kind: AST.ModifierKind) -> Bool {
        if case .Lazy = kind { return true }
        return false
    }

    private func isWeak(_ kind: AST.ModifierKind) -> Bool {
        if case .Weak = kind { return true }
        return false
    }

    private func isUnowned(_ kind: AST.ModifierKind) -> Bool {
        if case .Unowned = kind { return true }
        return false
    }

    private func check(_ modifiers: [AST.Modifier], on what: String, allowed: (AST.ModifierKind) -> Bool) {
        for modifier in modifiers {
            if !allowed(modifier.kind) {
                context.emitError(
                    "'\(kindText(modifier.kind))' modifier cannot be applied to \(what)",
                    at: modifier.token
                )
            }
        }
    }

    private func checkCombinations(_ modifiers: [AST.Modifier]) {
        var hasFinal = false
        var hasOpen = false
        var hasAbstract = false
        for modifier in modifiers {
            if isFinal(modifier.kind) { hasFinal = true }
            if isOpen(modifier.kind) { hasOpen = true }
            if isAbstract(modifier.kind) { hasAbstract = true }
        }
        if hasFinal, hasOpen {
            for modifier in modifiers where isFinal(modifier.kind) {
                context.emitError(
                    "'final' modifier cannot be combined with 'open'", at: modifier.token
                )
            }
        }
        if hasFinal, hasAbstract {
            for modifier in modifiers where isFinal(modifier.kind) {
                context.emitError(
                    "'final' modifier cannot be combined with 'abstract'", at: modifier.token
                )
            }
        }
    }

    private func withType(
        _ type: Symbol.NominalTypeSymbol?, isAbstract: Bool, body: () -> Void
    ) {
        guard let type else { return }
        typeStack.append(type)
        abstractClassStack.append(isAbstract)
        body()
        abstractClassStack.removeLast()
        typeStack.removeLast()
    }

    private func checkTypeAccess(
        _ modifiers: [AST.Modifier], on what: String,
        extraAllowed: (AST.ModifierKind) -> Bool = { _ in false }
    ) {
        check(modifiers, on: what, allowed: { kind in
            (isPlainAccess(kind) && !isOpen(kind) && !isProtected(kind)) || extraAllowed(kind)
        })
        checkCombinations(modifiers)
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        checkTypeAccess(structDecl.modifiers, on: "'struct'")
        withType(structDecl.symbol, isAbstract: false) {
            super.visitStructDecl(structDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        check(classDecl.modifiers, on: "'class'", allowed: { kind in
            isPlainAccess(kind) || isAbstract(kind) || isFinal(kind)
        })
        checkCombinations(classDecl.modifiers)
        let isAbstractClass = classDecl.modifiers.contains { isAbstract($0.kind) }
        withType(classDecl.symbol, isAbstract: isAbstractClass) {
            super.visitClassDecl(classDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        checkTypeAccess(enumDecl.modifiers, on: "'enum'", extraAllowed: { kind in
            if case .Indirect = kind { return true }
            return false
        })
        withType(enumDecl.symbol, isAbstract: false) {
            super.visitEnumDecl(enumDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(
        _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
    ) -> Any? {
        checkTypeAccess(protocolDecl.modifiers, on: "'protocol'")
        withType(protocolDecl.symbol, isAbstract: false) {
            super.visitProtocolDecl(protocolDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        checkTypeAccess(actorDecl.modifiers, on: "'actor'")
        withType(actorDecl.symbol, isAbstract: false) {
            super.visitActorDecl(actorDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(
        _ extensionDecl: AST.ExtensionDecl, additional: Any? = nil
    ) -> Any? {
        check(extensionDecl.modifiers, on: "an extension", allowed: { kind in
            isFinal(kind)
        })
        super.visitExtensionDecl(extensionDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        check(functionDecl.modifiers, on: "a function", allowed: { kind in
            isPlainAccess(kind) || isStatic(kind) || isMutating(kind)
                || isNonmutating(kind) || isAbstract(kind) || isFinal(kind)
                || isOverride(kind) || isIsolated(kind)
        })
        checkFunctionContext(functionDecl.modifiers)
        checkAbstractBody(functionDecl.modifiers, body: functionDecl.body)
        super.visitFunctionDecl(functionDecl, additional: additional)
        return nil
    }

    private func checkFunctionContext(_ modifiers: [AST.Modifier]) {
        var hasStatic = false
        var hasMutating = false
        for modifier in modifiers {
            switch modifier.kind {
            case .Static:
                hasStatic = true
                if !enclosingType {
                    context.emitError(
                        "'static' modifier can only be applied to type members",
                        at: modifier.token
                    )
                }
            case .Mutating:
                hasMutating = true
                if !enclosingStructOrEnum {
                    context.emitError(
                        "'mutating' modifier can only be applied to a struct or enum method",
                        at: modifier.token
                    )
                }
            case .Nonmutating:
                if !enclosingStructOrEnum {
                    context.emitError(
                        "'nonmutating' modifier can only be applied to a struct or enum method",
                        at: modifier.token
                    )
                }
            case .Abstract:
                if !(enclosingClass != nil || typeStack.last is Symbol.ProtocolSymbol) {
                    context.emitError(
                        "'abstract' modifier can only be applied to a class or protocol member",
                        at: modifier.token
                    )
                }
                if enclosingClass != nil, !enclosingClassIsAbstract {
                    context.emitError(
                        "'abstract' member in non-abstract class", at: modifier.token
                    )
                }
            case .Final:
                if enclosingClass == nil {
                    context.emitError(
                        "'final' modifier can only be applied to a class member",
                        at: modifier.token
                    )
                }
            case .Override:
                if enclosingClass == nil {
                    context.emitError(
                        "'override' modifier can only be applied to a class member",
                        at: modifier.token
                    )
                }
            case .Open:
                if enclosingClass == nil {
                    context.emitError(
                        "'open' modifier can only be applied to a class or class member",
                        at: modifier.token
                    )
                }
            case .Protected:
                if enclosingClass == nil {
                    context.emitError(
                        "'protected' modifier can only be applied to a class member",
                        at: modifier.token
                    )
                }
            case .Isolated:
                if !enclosingActor {
                    context.emitError(
                        "'isolated' modifier can only be applied to an actor member",
                        at: modifier.token
                    )
                }
            default:
                break
            }
        }
        if hasStatic, hasMutating {
            for modifier in modifiers where isMutating(modifier.kind) {
                context.emitError(
                    "'mutating' modifier cannot be combined with 'static'", at: modifier.token
                )
            }
        }
    }

    private func checkAbstractBody(_ modifiers: [AST.Modifier], body: AST.FunctionDecl.Body?) {
        for modifier in modifiers where isAbstract(modifier.kind) {
            if body != nil {
                context.emitError("'abstract' method cannot have a body", at: modifier.token)
            }
        }
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil)
        -> Any?
    {
        check(initDecl.modifiers, on: "an initializer", allowed: { kind in
            isPlainAccess(kind) || isConvenience(kind) || isOverride(kind)
        })
        for modifier in initDecl.modifiers {
            switch modifier.kind {
            case .Convenience:
                if enclosingClass == nil {
                    context.emitError(
                        "'convenience' initializer must be in a class", at: modifier.token
                    )
                }
            case .Override:
                if enclosingClass == nil {
                    context.emitError(
                        "'override' modifier can only be applied to a class member",
                        at: modifier.token
                    )
                }
            case .Open:
                if enclosingClass == nil {
                    context.emitError(
                        "'open' modifier can only be applied to a class or class member",
                        at: modifier.token
                    )
                }
            case .Protected:
                if enclosingClass == nil {
                    context.emitError(
                        "'protected' modifier can only be applied to a class member",
                        at: modifier.token
                    )
                }
            default:
                break
            }
        }
        super.visitInitDecl(initDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        check(subscriptDecl.modifiers, on: "a subscript", allowed: { kind in
            isPlainAccess(kind) || isSetterOnly(kind) || isStatic(kind) || isMutating(kind)
                || isFinal(kind) || isOverride(kind)
        })
        for modifier in subscriptDecl.modifiers {
            switch modifier.kind {
            case .Static:
                if !enclosingType {
                    context.emitError(
                        "'static' modifier can only be applied to type members",
                        at: modifier.token
                    )
                }
            case .Mutating:
                if !enclosingStructOrEnum {
                    context.emitError(
                        "'mutating' modifier can only be applied to a struct or enum method",
                        at: modifier.token
                    )
                }
            case .Final, .Override, .Open, .Protected:
                if enclosingClass == nil {
                    let what = kindText(modifier.kind) == "open" ? "a class or class member" : "a class member"
                    context.emitError(
                        "'\(kindText(modifier.kind))' modifier can only be applied to \(what)",
                        at: modifier.token
                    )
                }
            default:
                break
            }
        }
        super.visitSubscriptDecl(subscriptDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        check(variableDecl.modifiers, on: "a property", allowed: { kind in
            isPlainAccess(kind) || isSetterOnly(kind) || isStatic(kind) || isLazy(kind)
                || isWeak(kind) || isUnowned(kind) || isFinal(kind) || isOverride(kind)
        })
        let isVar = variableDecl.token.value == "var"
        let hasInitializer = variableDecl.initializer != nil
        for modifier in variableDecl.modifiers {
            switch modifier.kind {
            case .Static:
                if !enclosingType {
                    context.emitError(
                        "'static' modifier can only be applied to type members",
                        at: modifier.token
                    )
                }
            case .Final, .Override, .Open, .Protected:
                if enclosingClass == nil {
                    let what = kindText(modifier.kind) == "open" ? "a class or class member" : "a class member"
                    context.emitError(
                        "'\(kindText(modifier.kind))' modifier can only be applied to \(what)",
                        at: modifier.token
                    )
                }
            case .Lazy:
                if !isVar {
                    context.emitError("'lazy' property must be a var", at: modifier.token)
                }
                if !hasInitializer {
                    context.emitError(
                        "'lazy' property must have an initializer", at: modifier.token
                    )
                }
            case .Weak, .Unowned:
                if !isVar {
                    context.emitError("'weak' property must be a var", at: modifier.token)
                }
                if let type = variableDecl.symbol?.type {
                    let isClass = type is TrussType.ClassType
                        || (type as? TrussType.OptionalType)?.wrapped is TrussType.ClassType
                    if !isClass {
                        context.emitError(
                            "'weak' property must be of class type", at: modifier.token
                        )
                    }
                }
            default:
                break
            }
        }
        super.visitVariableDecl(variableDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitEnumCaseDecl(
        _ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil
    ) -> Any? {
        check(enumCaseDecl.modifiers, on: "an enum case", allowed: { kind in
            if case .Indirect = kind { return true }
            return false
        })
        super.visitEnumCaseDecl(enumCaseDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(
        _ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil
    ) -> Any? {
        checkTypeAccess(typeAliasDecl.modifiers, on: "a typealias")
        super.visitTypeAliasDecl(typeAliasDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        checkTypeAccess(associatedTypeDecl.modifiers, on: "an associated type")
        super.visitAssociatedTypeDecl(associatedTypeDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil)
        -> Any?
    {
        check(deinitDecl.modifiers, on: "a deinitializer", allowed: { _ in false })
        super.visitDeinitDecl(deinitDecl, additional: additional)
        return nil
    }
}
