import TrussCore

public enum Precedence: UInt8 {
    case None = 0
    case Assignment
    case Or
    case And
    case NullCoalescing
    case BitOr
    case BitAnd
    case Equality
    case Relational
    case Range
    case Shift
    case Additive
    case Multiplicative
    case Postfix
    case Cast
}

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
    public var peek2: Token? {
        if (self.index + 1) < self.lexerResult.tokens.count {
            return lexerResult.tokens[self.index + 1]
        } else {
            return nil
        }
    }
    public var peek3: Token? {
        if (self.index + 2) < self.lexerResult.tokens.count {
            return lexerResult.tokens[self.index + 2]
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
                let statement: AST.Statement?
                switch t.kind {
                case .Keyword(let keywordKind):
                    switch keywordKind {
                    case .Func: statement = parseFunctionDecl()
                    case .Let: statement = parseVariableDecl()
                    case .Var: statement = parseVariableDecl()
                    default: statement = nil
                    }
                case .Separator(let kind):
                    switch kind {
                    case .SemiColon:
                        self.index += 1
                        statement = AST.EmptyStatement(t)
                    default: statement = nil
                    }
                default:
                    statement = nil
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
        let returnTypeExpression: AST.Expression?
        if let t = peek, case .Operator(let kind) = t.kind, case .Arrow = kind {
            self.index += 1
            returnTypeExpression = parseExpression()
        } else {
            returnTypeExpression = nil
        }
        let body: AST.FunctionDecl.Body
        if let t = peek {
            switch t.kind {
            case .Separator(let kind) where kind == .OpenBrace:
                self.index += 1
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

                body = .Block(statements)
            case .Operator(let kind) where kind == .Assign:
                self.index += 1
                body = .Expression(parseExpression())
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
        let typeExpression: AST.Expression?
        if let t = peek, case .Separator(let kind) = t.kind, case .Colon = kind {
            self.index += 1
            typeExpression = parseExpression()
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
        guard let token = peek else {
            fatalError()
        }
        switch token.kind {
        case .Keyword(let kind):
            switch kind {
            case .Func: return parseFunctionDecl()
            case .Let: return parseVariableDecl()
            case .Var: return parseVariableDecl()
            default: fatalError()
            }
        case .Separator(let kind):
            switch kind {
            case .SemiColon:
                self.index += 1
                return AST.EmptyStatement(token)
            default: fatalError()
            }
        default:
            return AST.ExpressionStatement(parseExpression())
        }
    }
    private func parseExpression() -> AST.Expression {
        var ops: [Token] = []
        var operands: [AST.Expression] = []
        while let token = peek {
            if case .Operator = token.kind {
                ops.append(token)
                self.index += 1
            } else if let expr = parsePrefix() {
                operands.append(expr)
            } else {
                break
            }
        }
        return AST.Infix(ops, operands)
    }
    private func parsePrefix() -> AST.Expression? {
        guard let token = peek else {
            fatalError()
        }
        var expression: AST.Expression
        switch token.kind {
        case .Identifier: expression = AST.Variable(name: token)
        case .StringLiteral: expression = AST.StringLiteral(token)
        case .IntegerLiteral(let value): expression = AST.IntegerLiteral(token, value)
        case .FloatLiteral(let value): expression = AST.FloatLiteral(token, value)
        case .CharLiteral(let value): expression = AST.CharLiteral(token, value)
        case .BooleanLiteral(let value): expression = AST.BoolLiteral(token, value)
        case .NullLiteral: expression = AST.NullLiteral(token)
        default: return nil
        }
        self.index += 1
        loop: while let t = peek {
            switch t.kind {
            case .Separator(let kind):
                switch kind {
                case .OpenParen:
                    expression = parseCall(expression)
                case .Colon:
                    if let t2 = peek2, case .Separator(let k) = t2.kind, case .Colon = k,
                        let t3 = peek3, case .Operator(let k2) = t3.kind, let k2 = k2,
                        case .Less = k2
                    {
                        self.index += 3
                        var genericArguments: [AST.Expression] = []
                        while let t4 = peek {
                            if case .Operator(let kind) = t4.kind, let kind = kind,
                                case .Greater = kind
                            {
                                break
                            } else {
                                genericArguments.append(parseExpression())
                            }
                        }
                        if let t4 = peek, case .Operator(let kind) = t4.kind, let kind = kind,
                            case .Greater = kind
                        {
                            self.index += 1
                        } else {
                            fatalError()
                        }
                        expression = AST.GenericApplication(base: expression, genericArguments)
                    } else {
                        break loop
                    }
                default: break loop
                }
            case .Operator(let kind):
                switch kind {
                case .Dot:
                    self.index += 1
                    guard let member = next else {
                        fatalError()
                    }
                    expression = AST.MemberAccess(expression, t, member)
                default: break loop
                }
            default: break loop
            }
        }
        return expression
    }
    private func parseCall(_ callee: AST.Expression) -> AST.Call {
        self.index += 1
        if let t = peek, case .Separator(let kind) = t.kind,
            case .CloseParen = kind
        {
            self.index += 1
        } else {
            fatalError()
        }
        return AST.Call(callee: callee, arguments: [])
    }
}
