import TrussCore

public extension AccessLevel {
    var sourceText: String {
        switch self {
        case .Open: "open"
        case .Public: "public"
        case .Protected: "protected"
        case .PackagePrivate: "packageprivate"
        case .Internal: "internal"
        case .FilePrivate: "fileprivate"
        case .Private: "private"
        }
    }
}

enum AccessExtractor {
    static func apply(
        to symbol: Symbol.Symbol, modifiers: [AST.Modifier], context: Context
    ) {
        var access: AccessLevel?
        var setter: AccessLevel?
        var setterToken: Token?
        for modifier in modifiers {
            guard let level = modifier.kind.accessLevel else { continue }
            let isSetter: Bool = switch modifier.kind {
            case let .Open(setterFlag): setterFlag
            case let .Public(setterFlag): setterFlag
            case let .Protected(setterFlag): setterFlag
            case let .PackagePrivate(setterFlag): setterFlag
            case let .Internal(setterFlag): setterFlag
            case let .FilePrivate(setterFlag): setterFlag
            case let .Private(setterFlag): setterFlag
            default: false
            }
            if isSetter {
                if setter != nil {
                    context.emitError(
                        "duplicate access modifier '\(modifier.token.value)'", at: modifier.token
                    )
                }
                setter = level
                setterToken = modifier.token
            } else {
                if access != nil {
                    context.emitError(
                        "duplicate access modifier '\(modifier.token.value)'", at: modifier.token
                    )
                }
                access = level
            }
        }
        if let access {
            symbol.access = access
        }
        if let setter {
            symbol.setterAccess = setter
            let getter = access ?? .Internal
            if setter.rawValue < getter.rawValue, let setterToken {
                context.emitError(
                    "setter access level '\(setter.sourceText)' cannot be broader than getter access level '\(getter.sourceText)'",
                    at: setterToken
                )
            }
        }
    }

    static func record(
        _ symbol: Symbol.Symbol, package: Symbol.PackageSymbol?, module: Symbol.ModuleSymbol?
    ) {
        symbol.packageId = package?.id
        symbol.moduleSymbol = module
    }
}
