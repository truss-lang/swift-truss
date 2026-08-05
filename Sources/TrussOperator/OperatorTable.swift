import TrussCore

public final class OperatorTable {
    public let root: Namespace
    public private(set) var modules: [String: Namespace] = [:]

    public init() {
        root = Namespace()
    }

    public func namespace(forModule name: String) -> Namespace {
        if let namespace = modules[name] {
            return namespace
        }
        let components = name.split(separator: ".").map(String.init)
        var current = root
        var path = ""
        for component in components {
            path = path.isEmpty ? component : path + "." + component
            if let existing = current.children[component] {
                current = existing
            } else {
                let child = Namespace()
                child.parent = current
                current.children[component] = child
                current = child
            }
            if modules[path] == nil {
                modules[path] = current
            }
        }
        return current
    }
}

public final class Namespace {
    public internal(set) var precedenceGroups: [String: PrecedenceGroupInfo] = [:]
    public internal(set) var operators: [String: OperatorInfo] = [:]
    public internal(set) var children: [String: Namespace] = [:]
    public internal(set) weak var parent: Namespace?

    public init() {}
}

public final class PrecedenceGroupInfo: Equatable, Codable {
    public let name: Token
    public let associativity: AST.PrecedenceGroupDecl.Associativity
    public let assignment: Bool
    public let higherThan: [AST.Expression]
    public let lowerThan: [AST.Expression]
    public internal(set) var resolvedHigherThan: [PrecedenceGroupInfo?] = []
    public internal(set) var resolvedLowerThan: [PrecedenceGroupInfo?] = []

    public init(
        name: Token, associativity: AST.PrecedenceGroupDecl.Associativity,
        assignment: Bool, higherThan: [AST.Expression], lowerThan: [AST.Expression]
    ) {
        self.name = name
        self.associativity = associativity
        self.assignment = assignment
        self.higherThan = higherThan
        self.lowerThan = lowerThan
    }

    public static func == (lhs: PrecedenceGroupInfo, rhs: PrecedenceGroupInfo) -> Bool {
        lhs === rhs
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case associativity
        case assignment
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name.value, forKey: .name)
        try container.encode(associativity.code, forKey: .associativity)
        try container.encode(assignment, forKey: .assignment)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nameValue = try container.decode(String.self, forKey: .name)
        let code = try container.decode(String.self, forKey: .associativity)
        name = Token(
            value: nameValue, kind: .Identifier,
            pos: Position(pos: 0, line: 0, col: 0, len: 0), id: Id.SourceId(id: 0)
        )
        associativity = switch code {
        case "left": .Left
        case "right": .Right
        default: .None
        }
        assignment = try container.decode(Bool.self, forKey: .assignment)
        higherThan = []
        lowerThan = []
        resolvedHigherThan = []
        resolvedLowerThan = []
    }
}

private extension AST.PrecedenceGroupDecl.Associativity {
    var code: String {
        switch self {
        case .Left: "left"
        case .Right: "right"
        case .None: "none"
        }
    }
}

public final class OperatorInfo {
    public let name: Token
    public internal(set) var kinds: [AST.OperatorDecl.Kind]
    public internal(set) var group: AST.Expression?
    public internal(set) var resolvedGroup: PrecedenceGroupInfo?
    public internal(set) var defaultGroup: PrecedenceGroupInfo?

    public init(name: Token, kinds: [AST.OperatorDecl.Kind], group: AST.Expression?) {
        self.name = name
        self.kinds = kinds
        self.group = group
    }
}
