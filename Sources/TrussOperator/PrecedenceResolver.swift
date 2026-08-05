import TrussCore

public final class PrecedenceResolver {
    private let table: OperatorTable
    private let context: Context

    public init(table: OperatorTable, context: Context) {
        self.table = table
        self.context = context
    }

    public func resolve() {
        resolveNamespace(table.root, modulePath: nil)
        for name in table.modules.keys.sorted() {
            resolveNamespace(table.modules[name]!, modulePath: name)
        }
    }

    private func resolveNamespace(_ namespace: OperatorTable.Namespace, modulePath: String?) {
        for group in namespace.precedenceGroups.values {
            resolveGroup(group, namespace: namespace, modulePath: modulePath)
        }
    }

    private func resolveGroup(
        _ group: OperatorTable.PrecedenceGroupInfo, namespace: OperatorTable.Namespace,
        modulePath: String?
    ) {
        group.resolvedHigherThan = resolveReferences(
            group.higherThan, group: group, namespace: namespace, modulePath: modulePath,
            relation: "higher"
        )
        group.resolvedLowerThan = resolveReferences(
            group.lowerThan, group: group, namespace: namespace, modulePath: modulePath,
            relation: "lower"
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
        namespace: OperatorTable.Namespace, modulePath: String?, relation: String
    ) -> [OperatorTable.PrecedenceGroupInfo?] {
        references.map { expression in
            guard let (path, location) = referencePath(expression) else {
                context.emitError(
                    "expected a precedence group reference", at: group.name
                )
                return nil
            }
            guard let target = lookup(path, namespace: namespace, modulePath: modulePath, at: location)
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
        _ path: [String], namespace: OperatorTable.Namespace, modulePath: String?, at location: Token
    ) -> OperatorTable.PrecedenceGroupInfo? {
        if path.count == 1 {
            let name = path[0]
            if let group = namespace.precedenceGroups[name] {
                return group
            }
            if let group = table.root.precedenceGroups[name] {
                return group
            }
            context.emitError("unknown precedence group '\(name)'", at: location)
            return nil
        }
        let moduleName = path.dropLast().joined(separator: ".")
        let groupName = path.last!
        guard let moduleNamespace = table.modules[moduleName] else {
            context.emitError("unknown module '\(moduleName)'", at: location)
            return nil
        }
        guard let group = moduleNamespace.precedenceGroups[groupName] else {
            context.emitError("unknown precedence group '\(moduleName).\(groupName)'", at: location)
            return nil
        }
        return group
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
