import TrussCore

public final class ModifierChecker: AST.Visitor {
    private let context: Context
    private var typeStack: [Symbol.NominalTypeSymbol] = []
    private var abstractClassStack: [Bool] = []

    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil) -> Any? {
        checkTypeAccess(structDecl.modifiers, on: "'struct'")
        withType(structDecl.symbol, isAbstract: false) {
            super.visitStructDecl(structDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil) -> Any? {
        check(
            classDecl.modifiers, on: "'class'", allowed: Self.plainAccess + [.Abstract, .Final]
        )
        checkCombinations(classDecl.modifiers)
        let isAbstractClass = classDecl.modifiers.contains { if case .Abstract = $0.kind { true } else { false } }
        withType(classDecl.symbol, isAbstract: isAbstractClass) {
            super.visitClassDecl(classDecl, additional: additional)
        }
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil) -> Any? {
        checkTypeAccess(enumDecl.modifiers, on: "'enum'", extraAllowed: [.Indirect])
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
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil) -> Any? {
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
        check(extensionDecl.modifiers, on: "an extension", allowed: [.Final])
        super.visitExtensionDecl(extensionDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        check(
            functionDecl.modifiers, on: "a function",
            allowed: Self.plainAccess + [
                .Static, .Mutating, .Nonmutating, .Abstract, .Final, .Override, .Isolated,
            ]
        )
        checkFunctionContext(functionDecl.modifiers)
        checkAbstractBody(functionDecl.modifiers, body: functionDecl.body)
        super.visitFunctionDecl(functionDecl, additional: additional)
        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        check(
            initDecl.modifiers, on: "an initializer",
            allowed: Self.plainAccess + [.Convenience, .Override]
        )
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
        check(
            subscriptDecl.modifiers, on: "a subscript",
            allowed: Self.plainAccess + Self.setterOnly + [.Static, .Mutating, .Final, .Override]
        )
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
        check(
            variableDecl.modifiers, on: "a property",
            allowed: Self.plainAccess + Self.setterOnly + [
                .Static, .Lazy, .Weak, .Unowned, .Final, .Override,
            ]
        )
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
                        || (type as? TrussType.GenericInstantiation).flatMap { generic in
                            generic.base.name == "Optional" ? generic.arguments.first : nil
                        } is TrussType.ClassType
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
        check(enumCaseDecl.modifiers, on: "an enum case", allowed: [.Indirect])
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
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        check(deinitDecl.modifiers, on: "a deinitializer", allowed: [])
        super.visitDeinitDecl(deinitDecl, additional: additional)
        return nil
    }

    private static var plainAccess: [AST.ModifierKind] {
        [
            .Open(setter: false), .Public(setter: false), .Protected(setter: false),
            .PackagePrivate(setter: false), .Internal(setter: false), .FilePrivate(setter: false),
            .Private(setter: false),
        ]
    }

    private static var setterOnly: [AST.ModifierKind] {
        [
            .Open(setter: true), .Public(setter: true), .Protected(setter: true),
            .PackagePrivate(setter: true), .Internal(setter: true), .FilePrivate(setter: true),
            .Private(setter: true),
        ]
    }

    private static var typeAccess: [AST.ModifierKind] {
        [
            .Public(setter: false), .PackagePrivate(setter: false), .Internal(setter: false),
            .FilePrivate(setter: false), .Private(setter: false),
        ]
    }

    private var enclosingClass: Symbol.ClassSymbol? {
        typeStack.last as? Symbol.ClassSymbol
    }

    private var enclosingStructOrEnum: Bool {
        typeStack.last is Symbol.StructSymbol || typeStack.last is Symbol.EnumSymbol
    }

    private var enclosingType: Bool {
        !typeStack.isEmpty
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

    private func check(_ modifiers: [AST.Modifier], on what: String, allowed: [AST.ModifierKind]) {
        for modifier in modifiers where !allowed.contains(modifier.kind) {
            context.emitError(
                "'\(kindText(modifier.kind))' modifier cannot be applied to \(what)",
                at: modifier.token
            )
        }
    }

    private func checkCombinations(_ modifiers: [AST.Modifier]) {
        let hasFinal = modifiers.contains { if case .Final = $0.kind { true } else { false } }
        let hasOpen = modifiers.contains { if case .Open = $0.kind { true } else { false } }
        let hasAbstract = modifiers.contains { if case .Abstract = $0.kind { true } else { false } }
        if hasFinal, hasOpen {
            for modifier in modifiers where modifier.kind == .Final {
                context.emitError(
                    "'final' modifier cannot be combined with 'open'", at: modifier.token
                )
            }
        }
        if hasFinal, hasAbstract {
            for modifier in modifiers where modifier.kind == .Final {
                context.emitError(
                    "'final' modifier cannot be combined with 'abstract'", at: modifier.token
                )
            }
        }
    }

    private func checkTypeAccess(
        _ modifiers: [AST.Modifier], on what: String, extraAllowed: [AST.ModifierKind] = []
    ) {
        check(modifiers, on: what, allowed: Self.typeAccess + extraAllowed)
        checkCombinations(modifiers)
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
                if enclosingClass != nil, !(abstractClassStack.last ?? false) {
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
                if !(typeStack.last is Symbol.ActorSymbol) {
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
            for modifier in modifiers where modifier.kind == .Mutating {
                context.emitError(
                    "'mutating' modifier cannot be combined with 'static'", at: modifier.token
                )
            }
        }
    }

    private func checkAbstractBody(_ modifiers: [AST.Modifier], body: AST.FunctionDecl.Body?) {
        for modifier in modifiers where modifier.kind == .Abstract {
            if body != nil {
                context.emitError("'abstract' method cannot have a body", at: modifier.token)
            }
        }
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
}
