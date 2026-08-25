import TrussCore

public final class OptionalDesugarPass: AST.Rewriter {
    public override func visitOptionalType(
        _ optionalType: AST.OptionalType, additional: Any? = nil
    ) -> Any? {
        let wrapped = rewrite(optionalType.wrappedType)
        let optionalToken = Token(
            value: "Optional", kind: .Identifier,
            pos: optionalType.token.pos, id: optionalType.token.id
        )
        let base = AST.Variable(name: optionalToken, sourceRange: optionalType.sourceRange)
        return AST.GenericApplication(
            base, [wrapped], sourceRange: optionalType.sourceRange
        )
    }
}
