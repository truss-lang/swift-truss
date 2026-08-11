public enum AccessLevel: Int, Comparable {
    case Open
    case Public
    case Protected
    case PackagePrivate
    case Internal
    case FilePrivate
    case Private

    public static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func isAtLeast(_ other: AccessLevel) -> Bool {
        rawValue <= other.rawValue
    }
}

public extension AST.ModifierKind {
    var accessLevel: AccessLevel? {
        switch self {
        case .Open: .Open
        case .Public: .Public
        case .Protected: .Protected
        case .PackagePrivate: .PackagePrivate
        case .Internal: .Internal
        case .FilePrivate: .FilePrivate
        case .Private: .Private
        default: nil
        }
    }
}
