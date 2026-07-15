import TrussCore

public final class Parser {
    public let lexerResult: LexerResult
    public var index: Int = 0
    public var peek: Token? {
        if self.index < self.lexerResult.tokens.count {
            return lexerResult.tokens[self.index]
        } else {
            return nil
        }
    }
    public var next: Token? {
        if self.index < self.lexerResult.tokens.count {
            let t = lexerResult.tokens[self.index]
            self.index += 1
            return t
        } else {
            return nil
        }
    }
    public init(_ lexerResult: LexerResult) {
        self.lexerResult = lexerResult
    }
    public func parse() -> AST.Program {
        var statements: [AST.Statement] = []
        while true {
            if let t = peek {
                let statement: AST.Statement? =
                    switch t.kind {
                    case .Keyword(let keywordKind):
                        switch keywordKind {
                        case .Func: parseFunctionDecl()
                        case .Let: parseVariableDecl()
                        case .Var: parseVariableDecl()
                        default: nil
                        }
                    default:
                        nil
                    }
                if let statement = statement {
                    statements.append(statement)
                } else {
                    break
                }
            }
        }
        return AST.Program(lexerResult.id, statements)
    }
    private func parseFunctionDecl() -> AST.FunctionDecl {
        guard let token = next else {
            fatalError()
        }
        guard let name = next else {
            fatalError()
        }
        if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
            self.index += 1
        } else {
            fatalError()
        }
        if let t = peek, case .Separator(let kind) = t.kind, case .CloseParen = kind {
            self.index += 1
        } else {
            fatalError()
        }
        let returnTypeExpression: AST.TypeExpression?
        if let t = peek, case .Operator(let kind) = t.kind, case .Arrow = kind {
            self.index += 1
            returnTypeExpression = parseTypeExpression()
        } else {
            returnTypeExpression = nil
        }
        let body: AST.FunctionDecl.Body
        if let t = peek {
            switch t.kind {
            case .Separator(let kind) where kind == .OpenBrace:
                var statements: [AST.Statement] = []
                while let closeToken = peek {
                    if case .Separator(let kind) = closeToken.kind, case .CloseBrace = kind {
                        break
                    } else {
                        statements.append(parseStatement())
                    }
                }
                if let closeToken = peek, case .Separator(let kind) = closeToken.kind,
                    case .CloseBrace = kind
                {
                    self.index += 1
                } else {
                    fatalError()
                }

                body = .block(statements)
            case .Operator(let kind) where kind == .Assign: body = .expression(parseExpression())
            default: fatalError()
            }
        } else {
            fatalError()
        }
        return AST.FunctionDecl(token, name, returnTypeExpression, body)
    }
    private func parseVariableDecl() -> AST.VariableDecl {
        guard let token = next else {
            fatalError()
        }
        guard let name = next else {
            fatalError()
        }
        let typeExpression: AST.TypeExpression?
        if let t = peek, case .Separator(let kind) = t.kind, case .Colon = kind {
            self.index += 1
            typeExpression = parseTypeExpression()
        } else {
            typeExpression = nil
        }
        let initializer: AST.Expression?
        if let t = peek, case .Operator(let kind) = t.kind, case .Assign = kind {
            self.index += 1
            initializer = parseExpression()
        } else {
            initializer = nil
        }
        return AST.VariableDecl(token, name, typeExpression, initializer)
    }
    private func parseStatement() -> AST.Statement {
        return AST.ExpressionStatement(parseExpression())
    }
    private func parseExpression() -> AST.Expression {
        parsePrimary()
    }
    private func parsePrimary() -> AST.Expression {
        guard let t = peek else {
            fatalError()
        }
        return switch t.kind {
        case .Identifier: AST.Variable(name: t)
        case .StringLiteral: AST.StringLiteral(t)
        case .IntegerLiteral(let value): AST.IntegerLiteral(t, value)
        case .FloatLiteral(let value): AST.FloatLiteral(t, value)
        case .CharLiteral(let value): AST.CharLiteral(t, value)
        default: fatalError()
        }
    }
    private func parseTypeExpression() -> AST.TypeExpression {
        fatalError()
    }
}
