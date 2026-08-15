import TrussCore

enum TypeMangler {
    static func nominalPath(_ type: TrussType.NominalType, context: Context) -> String {
        guard let symbol = type.symbol else { return type.name }
        var result = "$t"
        let packageName = symbol.packageId.flatMap { context.id2Symbol[$0]?.name } ?? "main"
        result += mangleIdentifier(packageName)
        if let module = symbol.moduleSymbol {
            result += mangleIdentifier(module.name)
        }
        var chain: [String] = []
        var current: Id.SymbolId? = symbol.memberOf
        while let member = current, let owner = context.id2Symbol[member] {
            chain.append(owner.name)
            current = owner.memberOf
        }
        for name in chain.reversed() {
            result += "_"
            result += mangleIdentifier(name)
        }
        result += "_"
        result += mangleIdentifier(type.name)
        return result
    }

    static func mangleIdentifier(_ name: String) -> String {
        "\(name.count)\(name)"
    }
}
