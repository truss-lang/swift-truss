import TrussCore

public final class TypeBuilder: AST.Visitor {
    private let context: Context
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitNominalTypeDecl(
        _ nominalTypeDecl: AST.NominalTypeDecl, additional: Any? = nil
    ) -> Any? {
        let symbol = nominalTypeDecl.symbol!
        build(symbol) { typeId, name in
            let type: TrussType.NominalType = switch symbol {
            case is Symbol.StructSymbol:
                TrussType.StructType(id: typeId, name: name)
            case is Symbol.ClassSymbol:
                TrussType.ClassType(id: typeId, name: name)
            case is Symbol.EnumSymbol:
                TrussType.EnumType(id: typeId, name: name)
            case is Symbol.ProtocolSymbol:
                TrussType.ProtocolType(id: typeId, name: name)
            case is Symbol.ActorSymbol:
                TrussType.ActorType(id: typeId, name: name)
            default:
                fatalError("unreachable: unknown nominal type symbol \(Swift.type(of: symbol))")
            }
            return type
        }
        return super.visitNominalTypeDecl(nominalTypeDecl, additional: additional)
    }

    private func build(
        _ symbol: Symbol.NominalTypeSymbol,
        make: (Id.ASTTypeId, String) -> TrussType.NominalType
    ) {
        let typeId = context.nextTypeId
        let type = make(typeId, symbol.name)
        type.symbol = symbol
        context.register(type: type)
        symbol.typeId = typeId
    }
}
