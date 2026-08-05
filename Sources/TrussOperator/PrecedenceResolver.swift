import TrussCore

public final class PrecedenceResolver {
    private let table: OperatorTable
    private let context: Context

    public init(table: OperatorTable, context: Context) {
        self.table = table
        self.context = context
    }

    public func resolve() {
        resolveNamespace(table.root, modulePath: [])
        for name in table.modules.keys.sorted() {
            resolveNamespace(table.modules[name]!, modulePath: name.split(separator: ".").map(String.init))
        }
    }

    private func resolveNamespace(_ namespace: OperatorTable.Namespace, modulePath: [String]) {
        for group in namespace.precedenceGroups.values {
            resolveGroup(group, modulePath: modulePath)
        }
    }

    private func resolveGroup(
        _ group: OperatorTable.PrecedenceGroupInfo, modulePath: [String]
    ) {
        group.resolvedHigherThan = resolveReferences(
            group.higherThan, group: group, modulePath: modulePath, relation: "higher"
        )
        group.resolvedLowerThan = resolveReferences(
            group.lowerThan, group: group, modulePath: modulePath, relation: "lower"
        )
        var reported: [ObjectIdentifier] = []
        for (index, target) in group.resolvedHigherThan.enumerated() {
            guard let target else { continue }
            guard group.resolvedLowerThan.contains(where: { $0 === target }) else { continue }
            let id = ObjectIdentifier(target)
            if reported.contains(id) { continue }
            reported.append(id)
            context.emitError(
                "precedence group '\(group.name.value)' is both higher than and lower than '\(target.name.value)'",
                at: referencePath(group.higherThan[index])!.1
            )
        }
    }

    private func resolveReferences(
        _ references: [AST.Expression], group: OperatorTable.PrecedenceGroupInfo,
        modulePath: [String], relation: String
    ) -> [OperatorTable.PrecedenceGroupInfo?] {
        references.map { expression in
            guard let (path, location) = referencePath(expression) else {
                context.emitError(
                    "expected a precedence group reference", at: group.name
                )
                return nil
            }
            guard let target = lookup(path, modulePath: modulePath, at: location)
            else { return nil }
            if target === group {
                context.emitError(
                    "precedence group '\(group.name.value)' cannot be \(relation) than itself",
                    at: location
                )
            }
            return target
        }
    }

    private func lookup(
        _ path: [String], modulePath: [String], at location: Token
    ) -> OperatorTable.PrecedenceGroupInfo? {
        if path.count == 1 {
            let name = path[0]
            var chain = modulePath
            while !chain.isEmpty {
                if let group = table.modules[chain.joined(separator: ".")]?.precedenceGroups[name] {
                    return group
                }
                chain.removeLast()
            }
            if let group = table.root.precedenceGroups[name] {
                return group
            }
            context.emitError("unknown precedence group '\(name)'", at: location)
            return nil
        }
        let moduleComponents = Array(path.dropLast())
        let groupName = path.last!
        var current: OperatorTable.Namespace? =
            modulePath.isEmpty ? table.root : table.modules[modulePath.joined(separator: ".")]
        var moduleFound = false
        while let namespace = current {
            if let moduleNamespace = descend(namespace, moduleComponents) {
                moduleFound = true
                if let group = moduleNamespace.precedenceGroups[groupName] {
                    return group
                }
            }
            current = namespace.parent
        }
        if moduleFound {
            context.emitError(
                "unknown precedence group '\(path.joined(separator: "."))'", at: location
            )
        } else {
            context.emitError(
                "unknown module '\(moduleComponents.joined(separator: "."))'", at: location
            )
        }
        return nil
    }

    private func descend(
        _ namespace: OperatorTable.Namespace, _ path: [String]
    ) -> OperatorTable.Namespace? {
        var current = namespace
        for component in path {
            guard let child = current.children[component] else { return nil }
            current = child
        }
        return current
    }

    private func referencePath(_ expression: AST.Expression) -> ([String], Token)? {
        if let variable = expression as? AST.Variable {
            return ([variable.name.value], variable.name)
        }
        if let member = expression as? AST.MemberAccess {
            guard let (path, _) = referencePath(member.object) else { return nil }
            return (path + [member.member.value], member.member)
        }
        return nil
    }
}
