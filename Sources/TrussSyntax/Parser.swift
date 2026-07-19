import TrussCore
import TrussDiagnosis

public final class Parser {
    private let context: Context
    private let lexerResult: LexerResult
    private let source: Source
    private var index: Int = 0
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
    public init(context: Context, _ lexerResult: LexerResult) {
        self.context = context
        self.lexerResult = lexerResult
        self.source = context.sourceTable[lexerResult.id]!
    }
    private func emitError(_ message: String, at range: SourceRange) {
        context.diagnositicEngine.emit(Diagnostic(severity: .error, message: message, range: range))
    }

    private func emitError(_ message: String, at token: Token) {
        let buffer = source.stringSourceBuffer
        let start = SourceLocation(
            buffer: buffer, offset: token.pos.pos, line: token.pos.line, column: token.pos.col)
        let end = SourceLocation(
            buffer: buffer, offset: token.pos.pos + token.pos.len, line: token.pos.line,
            column: token.pos.col + token.pos.len)
        emitError(message, at: SourceRange(start: start, end: end))
    }

    private func emitError(_ message: String, atOffset offset: Int) {
        let buffer = source.stringSourceBuffer
        let converter = LocationConverter(source: source.content)
        let (line, column) = converter.lineAndColumn(for: offset)
        let loc = SourceLocation(buffer: buffer, offset: offset, line: line, column: column)
        emitError(message, at: SourceRange(start: loc, end: loc))
    }

    private func emitEndOfFile() {
        emitError("unexpected end of file", atOffset: source.content.utf8.count)
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
            } else {
                break
            }
        }
        return AST.Program(lexerResult.id, statements)
    }
    private func parseFunctionDecl() -> AST.Statement {
        guard let token = next else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        guard let name = next else {
            emitError("expected function name after 'func'", at: token)
            return AST.ErrorStatement()
        }
        if let t = peek {
            if case .Separator(let kind) = t.kind, case .OpenParen = kind {
                self.index += 1
            } else {
                emitError("expected '(' after function name", at: t)
            }
        } else {
            emitEndOfFile()
        }
        if let t = peek {
            if case .Separator(let kind) = t.kind, case .CloseParen = kind {
                self.index += 1
            } else {
                emitError("expected ')' after function parameters", at: t)
            }
        } else {
            emitEndOfFile()
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
                if let closeToken = peek {
                    if case .Separator(let kind) = closeToken.kind,
                        case .CloseBrace = kind
                    {
                        self.index += 1
                    } else {
                        emitError("expected '}' after function body, but found \(t.value)", at: t)
                    }
                } else {
                    emitEndOfFile()
                }

                body = .Block(statements)
            case .Operator(let kind) where kind == .Assign:
                self.index += 1
                body = .Expression(parseExpression())
            default:
                emitError("expected a statement, but found \(t.value)", at: t)
                return AST.ErrorStatement()
            }
        } else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        return AST.FunctionDecl(token, name, returnTypeExpression, body)
    }
    private func parseVariableDecl() -> AST.Statement {
        guard let token = next else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        guard let name = next else {
            emitError("expected variable name", at: token)
            return AST.ErrorStatement()
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
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        switch token.kind {
        case .Keyword(let kind):
            switch kind {
            case .Func: return parseFunctionDecl()
            case .Let: return parseVariableDecl()
            case .Var: return parseVariableDecl()
            default:
                emitError("expected a statement, but found \(token.value)", at: token)
                return AST.ErrorStatement()
            }
        case .Separator(let kind):
            switch kind {
            case .SemiColon:
                self.index += 1
                return AST.EmptyStatement(token)
            default:
                emitError("expected a statement, but found \(token.value)", at: token)
                return AST.ErrorStatement()
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
            } else if let expr = parsePrimary() {
                operands.append(expr)
            } else {
                break
            }
        }
        return AST.Infix(ops, operands)
    }
    private func parsePrimary() -> AST.Expression? {
        guard let token = peek else {
            emitEndOfFile()
            return nil
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
                        emitError("expected member name after '.'", at: t)
                        break loop
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
        if let t = peek {
            if case .Separator(let kind) = t.kind,
                case .CloseParen = kind
            {
                self.index += 1
            } else {
                emitError("expected ')' after call arguments", at: t)
            }
        } else {
            emitEndOfFile()
        }
        return AST.Call(callee: callee, arguments: [])
    }
}
