import TrussCore

public final class TypeBuilder: AST.Visitor {
    private let context: Context
    public init(context: Context) {
        self.context = context
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil)
        -> Any?
    {
        build(structDecl.symbol) { TrussType.StructType(id: $0, name: $1) }
        return super.visitStructDecl(structDecl, additional: additional)
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil)
        -> Any?
    {
        build(classDecl.symbol) { TrussType.ClassType(id: $0, name: $1) }
        return super.visitClassDecl(classDecl, additional: additional)
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil)
        -> Any?
    {
        build(enumDecl.symbol) { TrussType.EnumType(id: $0, name: $1) }
        return super.visitEnumDecl(enumDecl, additional: additional)
    }

    @discardableResult
    public override func visitProtocolDecl(
        _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
    ) -> Any? {
        build(protocolDecl.symbol) { TrussType.ProtocolType(id: $0, name: $1) }
        return super.visitProtocolDecl(protocolDecl, additional: additional)
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil)
        -> Any?
    {
        build(actorDecl.symbol) { TrussType.ActorType(id: $0, name: $1) }
        return super.visitActorDecl(actorDecl, additional: additional)
    }

    private func build(
        _ symbol: Symbol.NominalTypeSymbol?,
        make: (Id.TypeId, String) -> TrussType.NominalType
    ) {
        guard let symbol else { return }
        let typeId = context.nextTypeId
        let type = make(typeId, symbol.name)
        type.symbol = symbol
        context.register(type: type)
        symbol.typeId = typeId
    }
}
