import TrussCore

final class TypeCollector {
    private let context: Context
    var storedProperties: [Id.ASTTypeId: [(name: String, type: TrussType.TrussType)]] = [:]
    var enumCases: [Id.ASTTypeId: [(name: String, types: [TrussType.TrussType])]] = [:]

    init(context: Context) {
        self.context = context
    }

    func collect(_ program: AST.Program) {
        collectStatements(program.statements)
    }

    private func collectStatements(_ statements: [AST.Statement]) {
        for statement in statements {
            switch statement {
            case let decl as AST.EnumDecl:
                collectEnumCases(decl)
                collectStatements(decl.body)
            case let decl as AST.ModuleDecl:
                collectStatements(decl.body)
            case let decl as AST.ExtensionDecl:
                collectStatements(decl.body)
            case let decl as AST.StructDecl:
                collectStatements(decl.body)
            case let decl as AST.ClassDecl:
                collectStatements(decl.body)
            case let decl as AST.ActorDecl:
                collectStatements(decl.body)
            case let decl as AST.VariableDecl:
                collectStoredProperty(decl)
            default:
                break
            }
        }
    }

    private func collectStoredProperty(_ decl: AST.VariableDecl) {
        guard let symbol = decl.symbol, let memberOf = symbol.memberOf,
              !decl.accessors.contains(where: { $0.kind == .Get || $0.kind == .Set })
        else {
            return
        }
        if isStaticDecl(decl) {
            return
        }
        guard let owner = context.id2Symbol[memberOf] as? Symbol.NominalTypeSymbol,
              let typeId = owner.typeId, let type = symbol.type
        else {
            return
        }
        storedProperties[typeId, default: []].append((name: symbol.name, type: type))
    }

    private func collectEnumCases(_ decl: AST.EnumDecl) {
        guard let typeId = decl.symbol?.typeId else { return }
        for statement in decl.body {
            if let caseDecl = statement as? AST.EnumCaseDecl {
                for caseSymbol in caseDecl.symbols {
                    enumCases[typeId, default: []].append(
                        (name: caseSymbol.name, types: caseSymbol.associatedTypes)
                    )
                }
            }
        }
    }

    private func isStaticDecl(_ decl: AST.VariableDecl) -> Bool {
        decl.modifiers.contains { modifier in
            if case .Static = modifier.kind { return true }
            return false
        }
    }
}
