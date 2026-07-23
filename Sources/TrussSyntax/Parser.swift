import TrussCore
import TrussDiagnosis

public final class Parser {
    private let context: Context
    private let packageName: String
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
    public init(context: Context, packageName: String, _ lexerResult: LexerResult) {
        self.context = context
        self.packageName = packageName
        self.lexerResult = lexerResult
        self.source = context.sourceTable[lexerResult.id]!
    }
    private var buffer: SourceBuffer { source.stringSourceBuffer }
    private func emitError(_ message: String, at range: SourceRange) {
        context.diagnositicEngine.emit(Diagnostic(severity: .error, message: message, range: range))
    }

    private func emitError(_ message: String, at token: Token) {
        emitError(message, at: token.sourceRange(in: buffer))
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
            guard let t = peek else {
                break
            }
            var statement: AST.Statement?
            switch t.kind {
            case .Keyword(let keywordKind):
                switch keywordKind {
                case .Module: statement = parseModuleDecl()
                case .PrecedenceGroup: statement = parsePrecedenceGroupDecl()
                case .Struct: statement = parseStructDecl()
                case .Func: statement = parseFunctionDecl()
                case .Let: statement = parseVariableDecl()
                case .Var: statement = parseVariableDecl()
                default: statement = nil
                }
            case .Separator(let kind):
                switch kind {
                case .SemiColon:
                    self.index += 1
                    statement = AST.EmptyStatement(t, sourceRange: t.sourceRange(in: buffer))
                default: statement = nil
                }
            default:
                statement = nil
            }
            if let stmt = statement {
                statements.append(stmt)
            } else {
                break
            }
        }
        let firstRange = statements.first?.sourceRange
        let lastRange = statements.last?.sourceRange
        let programRange: SourceRange?
        if let f = firstRange, let l = lastRange {
            programRange = SourceRange(start: f.start, end: l.end)
        } else {
            programRange = nil
        }
        return AST.Program(lexerResult.id, packageName, statements, sourceRange: programRange)
    }
    private func parseBasicStatement() -> AST.Statement? {
        guard let t = peek else {
            return nil
        }
        switch t.kind {
        case .Keyword(let keywordKind):
            switch keywordKind {
            case .Module: return parseModuleDecl()
            case .PrecedenceGroup: return parsePrecedenceGroupDecl()
            case .Func: return parseFunctionDecl()
            case .Let: return parseVariableDecl()
            case .Var: return parseVariableDecl()
            default: return nil
            }
        case .Separator(let kind):
            switch kind {
            case .SemiColon:
                self.index += 1
                return AST.EmptyStatement(t, sourceRange: t.sourceRange(in: buffer))
            default: return nil
            }
        default:
            return nil
        }

    }
    private func parseModuleDecl() -> AST.Statement {
        guard let token = next else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        guard let name = next else {
            emitError("expected module name after 'module'", at: token)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'module', but got '\(name.value)'", at: name)
            return AST.ErrorStatement()
        }
        guard let openToken = next else {
            emitError("expected '{' after module name", at: name)
            return AST.ErrorStatement()
        }
        guard case .Separator(let kind) = openToken.kind, case .OpenBrace = kind else {
            emitError("expected '{' after module name, but got '\(openToken.value)'", at: openToken)
            return AST.ErrorStatement()
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind, case .CloseBrace = kind {
                break
            } else if let statement = parseBasicStatement() {
                body.append(statement)
            } else {
                break
            }
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind,
                case .CloseBrace = kind
            {
                self.index += 1
            } else {
                emitError(
                    "expected '}' after module body, but got \(closeToken.value)", at: closeToken)
            }
            endToken = closeToken
        } else {
            emitEndOfFile()
            endToken = openToken
        }
        return AST.ModuleDecl(
            token, name, body, sourceRange: SourceRange(from: token, to: endToken, in: buffer))
    }
    private func parsePrecedenceGroupDecl() -> AST.Statement {
        guard let token = next else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        guard let name = next else {
            emitError("expected module name after 'precedencegroup'", at: token)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError(
                "expected identifier after 'precedencegroup', but got '\(name.value)'", at: name)
            return AST.ErrorStatement()
        }
        guard let openToken = next else {
            emitError("expected '{' after precedencegroup name", at: name)
            return AST.ErrorStatement()
        }
        guard case .Separator(let kind) = openToken.kind, case .OpenBrace = kind else {
            emitError(
                "expected '{' after precedencegroup name, but got '\(openToken.value)'",
                at: openToken)
            return AST.ErrorStatement()
        }
        var higherThanToken: Token? = nil
        var higherThan: [AST.TypeExpression] = []
        var lowerThanToken: Token? = nil
        var lowerThan: [AST.TypeExpression] = []
        var associativityToken: Token? = nil
        var associativity: AST.PrecedenceGroupDecl.Associativity = .None
        var assignmentToken: Token? = nil
        var assignment = false
        _loop: while let t = peek {
            if case .Identifier = t.kind {
                switch t.value {
                case "associativity":
                    self.index += 1
                    if associativityToken == nil {
                        associativityToken = t
                    } else {
                        emitError("associativity can only be set once", at: t)
                    }
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError("expected ':' after 'associativity'", at: t2)
                        }
                    } else {
                        emitEndOfFile()
                    }
                    if let t2 = peek {
                        if case .Identifier = t2.kind {
                            switch t2.value {
                            case "left":
                                self.index += 1
                                associativity = .Left
                            case "right":
                                self.index += 1
                                associativity = .Right
                            case "none":
                                self.index += 1
                                associativity = .None
                            default:
                                emitError(
                                    "expected 'left', 'right' or 'none' after ':' in associativity",
                                    at: t2)
                            }
                        } else {
                            emitError(
                                "expected 'left', 'right' or 'none' after ':' in associativity",
                                at: t2)
                        }
                    } else {
                        emitEndOfFile()
                    }
                case "assignment":
                    self.index += 1
                    if assignmentToken == nil {
                        assignmentToken = t
                    } else {
                        emitError("assignment can only be set once", at: t)
                    }
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError("expected ':' after 'assignment'", at: t2)
                        }
                    } else {
                        emitEndOfFile()
                    }
                    if let t2 = peek {
                        if case .BooleanLiteral(let v) = t2.kind {
                            self.index += 1
                            assignment = v
                        } else {
                            emitError(
                                "expected 'true' or 'false' after ':' in assignment",
                                at: t2)
                        }
                    } else {
                        emitEndOfFile()
                    }
                case "higherThan":
                    self.index += 1
                    if higherThanToken == nil {
                        higherThanToken = t
                    } else {
                        emitError("higherThan can only be set once", at: t)
                    }
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError("expected ':' after 'higherThan'", at: t2)
                        }
                    } else {
                        emitEndOfFile()
                    }
                    while let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .CloseBrace = kind {
                            break
                        }
                        if case .Identifier = t2.kind,
                            ["higherThan", "lowerThan", "associativity", "assignment"].contains(
                                t2.value)
                        {
                            break
                        }
                        guard let expr = parsePrimary() else { break }
                        if let typeExpression = extractTypeExpression(expr) {
                            higherThan.append(typeExpression)
                        } else {
                            emitError(
                                "expected type expression",
                                at: expr.sourceRange ?? t2.sourceRange(in: buffer))
                        }
                        if let t3 = peek, case .Separator(let kind) = t3.kind, case .Comma = kind {
                            self.index += 1
                        } else {
                            break
                        }
                    }
                case "lowerThan":
                    self.index += 1
                    if lowerThanToken == nil {
                        lowerThanToken = t
                    } else {
                        emitError("lowerThan can only be set once", at: t)
                    }
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError("expected ':' after 'lowerThan'", at: t2)
                        }
                    } else {
                        emitEndOfFile()
                    }
                    while let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .CloseBrace = kind {
                            break
                        }
                        if case .Identifier = t2.kind,
                            ["higherThan", "lowerThan", "associativity", "assignment"].contains(
                                t2.value)
                        {
                            break
                        }
                        guard let expr = parsePrimary() else { break }
                        if let typeExpression = extractTypeExpression(expr) {
                            lowerThan.append(typeExpression)
                        } else {
                            emitError(
                                "expected type expression",
                                at: expr.sourceRange ?? t2.sourceRange(in: buffer))
                        }
                        if let t3 = peek, case .Separator(let kind) = t3.kind, case .Comma = kind {
                            self.index += 1
                        } else {
                            break
                        }
                    }
                default:
                    break _loop
                }
            } else {
                break _loop
            }
        }
        var endToken: Token = name
        if let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind,
                case .CloseBrace = kind
            {
                self.index += 1
            } else {
                emitError(
                    "expected '}' after precedencegroup body, but got \(closeToken.value)",
                    at: closeToken)
            }
            endToken = closeToken
        } else {
            emitEndOfFile()
        }
        return AST.PrecedenceGroupDecl(
            token, name, higherThanToken, higherThan, lowerThanToken, lowerThan, associativityToken,
            associativity,
            assignmentToken, assignment,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer))
    }
    private func parseStructDecl() -> AST.Statement {
        guard let token = next else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        guard let name = next else {
            emitError("expected module name after 'module'", at: token)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'module', but got '\(name.value)'", at: name)
            return AST.ErrorStatement()
        }
        var conformances: [AST.TypeExpression] = []
        if let t = peek, case .Separator(let kind) = t.kind, case .Colon = kind {
            self.index += 1
            while let t2 = peek {
                guard let expr = parsePrimary() else { break }
                if let typeExpression = extractTypeExpression(expr) {
                    conformances.append(typeExpression)
                } else {
                    emitError(
                        "expected type expression",
                        at: expr.sourceRange ?? t2.sourceRange(in: buffer))
                }
                if let t3 = peek, case .Separator(let kind) = t3.kind, case .Comma = kind {
                    self.index += 1
                } else {
                    break
                }
            }
        }
        guard let openToken = next else {
            emitError("expected '{' after module name", at: name)
            return AST.ErrorStatement()
        }
        guard case .Separator(let kind) = openToken.kind, case .OpenBrace = kind else {
            emitError("expected '{' after module name, but got '\(openToken.value)'", at: openToken)
            return AST.ErrorStatement()
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind, case .CloseBrace = kind {
                break
            }
            body.append(parseStatement())
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind,
                case .CloseBrace = kind
            {
                self.index += 1
            } else {
                emitError(
                    "expected '}' after module body, but got \(closeToken.value)", at: closeToken)
            }
            endToken = closeToken
        } else {
            emitEndOfFile()
            endToken = openToken
        }
        return AST.StructDecl(
            token, name, conformances, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer))
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
            case .Return: return parseReturn()
            default:
                emitError("expected a statement, but got \(token.value)", at: token)
                return AST.ErrorStatement()
            }
        case .Separator(let kind):
            switch kind {
            case .SemiColon:
                self.index += 1
                return AST.EmptyStatement(token, sourceRange: token.sourceRange(in: buffer))
            default:
                emitError("expected a statement, but got \(token.value)", at: token)
                return AST.ErrorStatement()
            }
        default:
            let expr = parseExpression()
            return AST.ExpressionStatement(expr, sourceRange: expr.sourceRange)
        }
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
        var endToken: Token = name
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
                        emitError(
                            "expected '}' after function body, but got \(closeToken.value)",
                            at: closeToken)
                    }
                    endToken = closeToken
                } else {
                    emitEndOfFile()
                }

                body = .Block(statements)
            case .Operator(let kind) where kind == .Assign:
                self.index += 1
                let expr = parseExpression()
                body = .Expression(expr)
            default:
                emitError("expected a statement, but got \(t.value)", at: t)
                return AST.ErrorStatement()
            }
        } else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        let range: SourceRange?
        switch body {
        case .Block:
            range = SourceRange(from: token, to: endToken, in: buffer)
        case .Expression(let expr):
            if let r = expr.sourceRange {
                range = SourceRange(start: token.sourceRange(in: buffer).start, end: r.end)
            } else {
                range = nil
            }
        }
        return AST.FunctionDecl(token, name, returnTypeExpression, body, sourceRange: range)
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
        let endRange =
            initializer?.sourceRange ?? typeExpression?.sourceRange
            ?? name.sourceRange(in: buffer)
        let range = SourceRange(
            start: token.sourceRange(in: buffer).start, end: endRange.end)
        return AST.VariableDecl(token, name, typeExpression, initializer, sourceRange: range)
    }
    private func parseReturn() -> AST.Statement {
        guard let token = next else {
            emitEndOfFile()
            return AST.ErrorStatement()
        }
        guard let t = peek else {
            return AST.Return(token, nil, sourceRange: token.sourceRange(in: buffer))
        }
        if case .Separator(let kind) = t.kind, case .SemiColon = kind {
            return AST.Return(token, nil, sourceRange: token.sourceRange(in: buffer))
        } else if token.pos.line != t.pos.line {
            return AST.Return(token, nil, sourceRange: token.sourceRange(in: buffer))
        } else {
            let expr = parseExpression()
            let range: SourceRange
            if let r = expr.sourceRange {
                range = SourceRange(start: token.sourceRange(in: buffer).start, end: r.end)
            } else {
                range = token.sourceRange(in: buffer)
            }
            return AST.Return(token, expr, sourceRange: range)
        }
    }
    private func extractTypeExpression(_ expr: AST.Expression) -> AST.TypeExpression? {
        if let te = expr as? AST.TypeExpression { return te }
        if let sequentialExpression = expr as? AST.SequentialExpression,
            sequentialExpression.operands.count == 1
        {
            return sequentialExpression.operands[0] as? AST.TypeExpression
        }
        return nil
    }
    private func parseExpression() -> AST.Expression {
        var ops: [Token] = []
        var operands: [AST.Expression] = []
        var lastIsExpression = false
        while let token = peek {
            if case .Operator = token.kind {
                ops.append(token)
                self.index += 1
                lastIsExpression = false
            } else if !lastIsExpression, let expr = parsePrimary() {
                operands.append(expr)
                lastIsExpression = true
            } else {
                break
            }
        }
        let range: SourceRange?
        if let firstRange = operands.first?.sourceRange,
            let lastRange = operands.last?.sourceRange
        {
            range = SourceRange(start: firstRange.start, end: lastRange.end)
        } else {
            range = nil
        }
        return AST.SequentialExpression(ops, operands, sourceRange: range)
    }
    private func parsePrimary() -> AST.Expression? {
        guard let token = peek else {
            emitEndOfFile()
            return nil
        }
        var expression: AST.Expression
        switch token.kind {
        case .Identifier:
            expression = AST.Variable(name: token, sourceRange: token.sourceRange(in: buffer))
        case .StringLiteral:
            expression = AST.StringLiteral(token, sourceRange: token.sourceRange(in: buffer))
        case .IntegerLiteral(let value):
            expression = AST.IntegerLiteral(
                token, value, sourceRange: token.sourceRange(in: buffer))
        case .FloatLiteral(let value):
            expression = AST.FloatLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .CharLiteral(let value):
            expression = AST.CharLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .BooleanLiteral(let value):
            expression = AST.BoolLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .NullLiteral:
            expression = AST.NullLiteral(token, sourceRange: token.sourceRange(in: buffer))
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
                        guard let base = extractTypeExpression(expression) else {
                            emitError(
                                "expected type expression",
                                at: expression.sourceRange ?? token.sourceRange(in: buffer))
                            return AST.ErrorExpression()
                        }
                        var genericArguments: [AST.TypeExpression] = []
                        while let t4 = peek {
                            if case .Operator(let kind) = t4.kind, let kind = kind,
                                case .Greater = kind
                            {
                                break
                            }
                            let expr = parseExpression()
                            if let typeExpression = expr as? AST.TypeExpression {
                                genericArguments.append(typeExpression)
                            } else {
                                emitError(
                                    "expected type expression",
                                    at: expr.sourceRange ?? t2.sourceRange(in: buffer))
                            }
                        }
                        var closeToken: Token = token
                        if let t4 = peek, case .Operator(let kind) = t4.kind, let kind = kind,
                            case .Greater = kind
                        {
                            self.index += 1
                            closeToken = t4
                        } else {
                            emitError("expected '>'", at: t2.sourceRange(in: buffer))
                        }
                        expression = AST.GenericApplication(
                            base: base, genericArguments,
                            sourceRange: SourceRange(from: token, to: closeToken, in: buffer))
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
                    expression = AST.MemberAccess(
                        expression, t, member,
                        sourceRange: SourceRange(from: token, to: member, in: buffer))
                default: break loop
                }
            default: break loop
            }
        }
        return expression
    }
    private func parseCall(_ callee: AST.Expression) -> AST.Call {
        self.index += 1
        var endToken: Token? = nil
        if let t = peek {
            if case .Separator(let kind) = t.kind,
                case .CloseParen = kind
            {
                self.index += 1
                endToken = t
            } else {
                emitError("expected ')' after call arguments", at: t)
                endToken = t
            }
        } else {
            emitEndOfFile()
        }
        let range: SourceRange?
        if let endToken = endToken, let calleeRange = callee.sourceRange {
            range = SourceRange(
                start: calleeRange.start, end: endToken.sourceRange(in: buffer).end)
        } else if let calleeRange = callee.sourceRange {
            range = calleeRange
        } else {
            range = nil
        }
        return AST.Call(callee: callee, arguments: [], sourceRange: range)
    }
}
