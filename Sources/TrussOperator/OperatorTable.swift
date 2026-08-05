import TrussCore

public final class OperatorTable {
    public final class Namespace {
        public internal(set) var precedenceGroups: [String: PrecedenceGroupInfo] = [:]
        public internal(set) var operators: [String: OperatorInfo] = [:]
        public internal(set) var children: [String: Namespace] = [:]
        public internal(set) weak var parent: Namespace? = nil

        public init() {}
    }

    public final class PrecedenceGroupInfo {
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
    }

    public final class OperatorInfo {
        public let name: Token
        public internal(set) var kinds: [AST.OperatorDecl.Kind]

        public init(name: Token, kinds: [AST.OperatorDecl.Kind]) {
            self.name = name
            self.kinds = kinds
        }
    }

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
