import SwiftBetterDiagnostic
import TrussCore

public final class Parser {
    private let context: Context
    private let packageName: String
    private let lexerResult: LexerResult
    private let source: Source
    private var index: Int = 0
    private var buffer: SourceBuffer { source.stringSourceBuffer }
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
    private var endOfFile: SourceLocation {
        let converter = LocationConverter(source: source.content)
        let (line, column) = converter.lineAndColumn(for: source.content.utf8.count)
        return SourceLocation(
            buffer: buffer, offset: source.content.utf8.count, line: line, column: column)
    }
    private func emitError(_ message: String, at range: SourceRange) {
        context.diagnositicEngine.emit(Diagnostic(severity: .error, message: message, range: range))
    }
    private func emitError(_ message: String, at location: SourceLocation) {
        emitError(message, at: SourceRange(location: location))
    }

    private func emitError(_ message: String, at token: Token) {
        emitError(message, at: token.sourceRange(in: buffer))
    }

    private func emitEndOfFile() {
        emitError("unexpected end of file", at: SourceRange(location: endOfFile))
    }

    private func note(_ message: String, at token: Token) -> Diagnostic {
        Diagnostic(severity: .note, message: message, range: token.sourceRange(in: buffer))
    }

    private func emitError(_ message: String, at token: Token, notes: [Diagnostic]) {
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: .error, message: message,
                range: token.sourceRange(in: buffer), notes: notes))
    }

    public func parse() -> AST.Program {
        var statements: [AST.Statement] = []
        while let t = peek {
            let (modifiers, attributes) = parseAnnotations()
            guard let token = peek else {
                if !modifiers.isEmpty || !attributes.isEmpty {
                    emitError("expected statement", at: endOfFile)
                }
                break
            }
            var statement: AST.Statement?
            switch token.kind {
            case .Keyword(let keywordKind):
                switch keywordKind {
                case .Module: statement = parseModuleDecl(modifiers, attributes)
                case .PrecedenceGroup: statement = parsePrecedenceGroupDecl(modifiers, attributes)
                case .Struct: statement = parseStructDecl(modifiers, attributes)
                case .Class: statement = parseClassDecl(modifiers, attributes)
                case .ProtocolKw: statement = parseProtocolDecl(modifiers, attributes)
                case .Func: statement = parseFunctionDecl(modifiers, attributes)
                case .Let: statement = parseVariableDecl(modifiers, attributes)
                case .Var: statement = parseVariableDecl(modifiers, attributes)
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
        let (modifiers, attributes) = parseAnnotations()
        guard let t = peek else {
            if modifiers.isEmpty && attributes.isEmpty {
                return nil
            } else {
                emitError("expected statement", at: endOfFile)
                return AST.ErrorStatement()
            }
        }
        switch t.kind {
        case .Keyword(let keywordKind):
            switch keywordKind {
            case .Module: return parseModuleDecl(modifiers, attributes)
            case .PrecedenceGroup: return parsePrecedenceGroupDecl(modifiers, attributes)
            case .Struct: return parseStructDecl(modifiers, attributes)
            case .Class: return parseClassDecl(modifiers, attributes)
            case .ProtocolKw: return parseProtocolDecl(modifiers, attributes)
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes)
            case .Var: return parseVariableDecl(modifiers, attributes)
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
    private func parseModuleDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        guard let token = next else {
            fatalError("unreachable")
        }
        guard let name = next else {
            emitError("expected module name after 'module'", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'module', but got '\(name.value)'", at: name)
            return AST.ErrorStatement()
        }
        guard let openToken = next else {
            emitError("expected '{' after module name", at: endOfFile)
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
            emitError("expected '}' after module body", at: endOfFile)
            endToken = openToken
        }
        return AST.ModuleDecl(
            modifiers, attributes, token, name, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer))
    }
    private func parsePrecedenceGroupDecl(
        _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute]
    ) -> AST.Statement {
        guard let token = next else {
            fatalError("unreachable")
        }
        guard let name = next else {
            emitError("expected module name after 'precedencegroup'", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError(
                "expected identifier after 'precedencegroup', but got '\(name.value)'",
                at: name
            )
            return AST.ErrorStatement()
        }
        guard let openToken = next else {
            emitError("expected '{' after precedencegroup name", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Separator(let kind) = openToken.kind, case .OpenBrace = kind else {
            emitError(
                "expected '{' after precedencegroup name, but got '\(openToken.value)'",
                at: openToken)
            return AST.ErrorStatement()
        }
        var higherThanTokens: [Token] = []
        var higherThan: [AST.TypeExpression] = []
        var lowerThanTokens: [Token] = []
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
                        emitError(
                            "associativity can only be set once", at: t,
                            notes: [note("previous definition here", at: associativityToken!)])
                    }
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError(
                                "expected ':' after 'associativity', but got '\(t2.value)'",
                                at: t2
                            )
                        }
                    } else {
                        emitError("expected ':' after 'associativity", at: endOfFile)
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
                                    "expected 'left', 'right' or 'none' after ':' in associativity, but got '\(t2.value)'",
                                    at: t2
                                )
                            }
                        } else {
                            emitError(
                                "expected 'left', 'right' or 'none' after ':' in associativity, but got '\(t2.value)'",
                                at: t2
                            )
                        }
                    } else {
                        emitError(
                            "expected 'left', 'right' or 'none' after ':' in associativity",
                            at: endOfFile
                        )
                    }
                case "assignment":
                    self.index += 1
                    if assignmentToken == nil {
                        assignmentToken = t
                    } else {
                        emitError(
                            "assignment can only be set once",
                            at: t,
                            notes: [note("previous definition here", at: assignmentToken!)]
                        )
                    }
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError(
                                "expected ':' after 'assignment', but got '\(t2.value)'",
                                at: t2
                            )
                        }
                    } else {
                        emitError("expected ':' after 'assignment'", at: endOfFile)
                    }
                    if let t2 = peek {
                        if case .BooleanLiteral(let v) = t2.kind {
                            self.index += 1
                            assignment = v
                        } else {
                            emitError(
                                "expected 'true' or 'false' after ':' in assignment, but got '\(t2.value)'",
                                at: t2
                            )
                        }
                    } else {
                        emitError(
                            "expected 'true' or 'false' after ':' in assignment",
                            at: endOfFile
                        )
                    }
                case "higherThan":
                    self.index += 1
                    higherThanTokens.append(t)
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError(
                                "expected ':' after 'higherThan', but got '\(t2.value)'",
                                at: t2
                            )
                        }
                    } else {
                        emitError("expected ':' after 'higherThan'", at: endOfFile)
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
                        let expr = parseExpression()
                        if let typeExpression = expr as? AST.TypeExpression {
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
                    lowerThanTokens.append(t)
                    if let t2 = peek {
                        if case .Separator(let kind) = t2.kind, case .Colon = kind {
                            self.index += 1
                        } else {
                            emitError(
                                "expected ':' after 'lowerThan', but got '\(t2.value)'",
                                at: t2
                            )
                        }
                    } else {
                        emitError("expected ':' after 'lowerThan'", at: endOfFile)
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
                        let expr = parseExpression()
                        if let typeExpression = expr as? AST.TypeExpression {
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
            emitError("expected '}' after precedencegroup body", at: endOfFile)
        }
        return AST.PrecedenceGroupDecl(
            modifiers, attributes, token, name, higherThanTokens, higherThan, lowerThanTokens,
            lowerThan, associativityToken, associativity, assignmentToken, assignment,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer))
    }
    private func parseStructDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        guard let token = next else {
            fatalError("unreachable")
        }
        guard let name = next else {
            emitError("expected module name after 'struct'", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'struct', but got '\(name.value)'", at: name)
            return AST.ErrorStatement()
        }
        var conformances: [AST.TypeExpression] = []
        if let t = peek, case .Separator(let kind) = t.kind, case .Colon = kind {
            self.index += 1
            while let t2 = peek {
                let expr = parseExpression()
                if let typeExpression = expr as? AST.TypeExpression {
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
            emitError("expected '{' in struct type", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Separator(let kind) = openToken.kind, case .OpenBrace = kind else {
            emitError(
                "expected '{' in struct type, but got '\(openToken.value)'",
                at: openToken)
            return AST.ErrorStatement()
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind, case .CloseBrace = kind {
                break
            }
            if let stmt = parseTypeBodyStatement() {
                body.append(stmt)
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
                    "expected '}' after struct body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after struct body", at: endOfFile)
            endToken = openToken
        }
        return AST.StructDecl(
            modifiers, attributes, token, name, conformances, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer))
    }
    private func parseClassDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        guard let token = next else {
            fatalError("unreachable")
        }
        guard let name = next else {
            emitError("expected module name after 'class'", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'class', but got '\(name.value)'", at: name)
            return AST.ErrorStatement()
        }
        var inheritanceClauses: [AST.TypeExpression] = []
        if let t = peek, case .Separator(let kind) = t.kind, case .Colon = kind {
            self.index += 1
            while let t2 = peek {
                let expr = parseExpression()
                if let typeExpression = expr as? AST.TypeExpression {
                    inheritanceClauses.append(typeExpression)
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
            emitError("expected '{' in class type", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Separator(let kind) = openToken.kind, case .OpenBrace = kind else {
            emitError(
                "expected '{' in class type, but got '\(openToken.value)'",
                at: openToken)
            return AST.ErrorStatement()
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind, case .CloseBrace = kind {
                break
            }
            if let stmt = parseTypeBodyStatement() {
                body.append(stmt)
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
                    "expected '}' after class body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after class body", at: endOfFile)
            endToken = openToken
        }
        return AST.ClassDecl(
            modifiers, attributes, token, name, inheritanceClauses, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer))
    }
    private func parseProtocolDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        guard let token = next else {
            fatalError("unreachable")
        }
        guard let name = next else {
            emitError("expected module name after 'protocol'", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'protocol', but got '\(name.value)'", at: name)
            return AST.ErrorStatement()
        }
        var conformances: [AST.TypeExpression] = []
        if let t = peek, case .Separator(let kind) = t.kind, case .Colon = kind {
            self.index += 1
            while let t2 = peek {
                let expr = parseExpression()
                if let typeExpression = expr as? AST.TypeExpression {
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
            emitError("expected '{' in protocol type", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard case .Separator(let kind) = openToken.kind, case .OpenBrace = kind else {
            emitError("expected '{' in protocol type, but got '\(openToken.value)'", at: openToken)
            return AST.ErrorStatement()
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(let kind) = closeToken.kind, case .CloseBrace = kind {
                break
            }
            if let stmt = parseTypeBodyStatement() {
                body.append(stmt)
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
                    "expected '}' after protocol body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after protocol body", at: endOfFile)
            endToken = openToken
        }
        return AST.ProtocolDecl(
            modifiers, attributes, token, name, conformances, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer))
    }
    private func parseTypeBodyStatement() -> AST.Statement? {
        let (modifiers, attributes) = parseAnnotations()
        guard let token = peek else {
            if modifiers.isEmpty && attributes.isEmpty {
                return nil
            } else {
                emitError("expected statement", at: endOfFile)
                return AST.ErrorStatement()
            }
        }
        switch token.kind {
        case .Keyword(let kind):
            switch kind {
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes)
            case .Var: return parseVariableDecl(modifiers, attributes)
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
            emitError("expected a statement, but got \(token.value)", at: token)
            return AST.ErrorStatement()
        }
    }
    private func parseStatement() -> AST.Statement? {
        let (modifiers, attributes) = parseAnnotations()
        guard let token = peek else {
            if modifiers.isEmpty && attributes.isEmpty {
                return nil
            } else {
                emitError("expected statement", at: endOfFile)
                return AST.ErrorStatement()
            }
        }
        switch token.kind {
        case .Keyword(let kind):
            switch kind {
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes)
            case .Var: return parseVariableDecl(modifiers, attributes)
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
    private func parseFunctionDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        guard let token = next else {
            return AST.ErrorStatement()
        }
        guard let name = next else {
            emitError("expected function name after 'func'", at: endOfFile)
            return AST.ErrorStatement()
        }
        guard let t1 = peek else {
            emitError("expected '(' after function name", at: name)
            return AST.ErrorStatement()
        }
        if case .Separator(let kind) = t1.kind, case .OpenParen = kind {
            self.index += 1
        } else {
            emitError("expected '(' after function name, but got '\(t1.value)'", at: t1)
        }
        guard let t2 = peek else {
            emitError("expected ')' after function parameters", at: endOfFile)
            return AST.ErrorStatement()
        }
        if case .Separator(let kind) = t2.kind, case .CloseParen = kind {
            self.index += 1
        } else {
            emitError("expected ')' after function parameters, but got '\(t2.value)'", at: t2)
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
                    }
                    if let stmt = parseStatement() {
                        statements.append(stmt)
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
                            at: closeToken
                        )
                    }
                    endToken = closeToken
                } else {
                    emitError("expected '}' after function body", at: endOfFile)
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
            emitError("expected function body", at: endOfFile)
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
        return AST.FunctionDecl(
            modifiers, attributes, token, name, returnTypeExpression, body, sourceRange: range)
    }
    private func parseVariableDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        guard let token = next else {
            fatalError("unreachable")
        }
        guard let name = next else {
            emitError("expected variable name", at: endOfFile)
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
        return AST.VariableDecl(
            modifiers, attributes, token, name, typeExpression, initializer, sourceRange: range)
    }
    private func parseReturn() -> AST.Statement {
        guard let token = next else {
            fatalError("unreachable")
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
        if ops.isEmpty && operands.count == 1 {
            return operands[0]
        } else {
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
    }
    private func parsePrimary() -> AST.Expression? {
        guard let token = peek else {
            fatalError("unreachable")
        }
        var expression: AST.Expression
        switch token.kind {
        case .Identifier:
            self.index += 1
            expression = AST.Variable(name: token, sourceRange: token.sourceRange(in: buffer))
        case .StringLiteral:
            self.index += 1
            expression = AST.StringLiteral(token, sourceRange: token.sourceRange(in: buffer))
        case .IntegerLiteral(let value):
            self.index += 1
            expression = AST.IntegerLiteral(
                token,
                value,
                sourceRange: token.sourceRange(in: buffer)
            )
        case .FloatLiteral(let value):
            self.index += 1
            expression = AST.FloatLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .CharLiteral(let value):
            self.index += 1
            expression = AST.CharLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .BooleanLiteral(let value):
            self.index += 1
            expression = AST.BoolLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .NullLiteral:
            self.index += 1
            expression = AST.NullLiteral(token, sourceRange: token.sourceRange(in: buffer))
        case .Keyword(let kind):
            switch kind {
            case .SelfKw:
                self.index += 1
                expression = AST.SelfExpression(token, sourceRange: token.sourceRange(in: buffer))
            case .SelfTypeKw:
                self.index += 1
                expression = AST.SelfTypeExpression(
                    token,
                    sourceRange: token.sourceRange(in: buffer)
                )
            case .SuperKw:
                self.index += 1
                expression = AST.SuperExpression(token, sourceRange: token.sourceRange(in: buffer))
            default:
                return nil
            }
        default: return nil
        }
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
                        guard let base = expression as? AST.TypeExpression else {
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
                        emitError("expected member name after '.'", at: endOfFile)
                        break loop
                    }
                    if member.kind != .Identifier {
                        emitError(
                            "expected identifier after '.', but got '\(member.value)'",
                            at: member
                        )
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
    private func parseIf() -> AST.Expression {
        guard let token = next else {
            return AST.ErrorExpression()
        }
        fatalError()
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
                emitError("expected ')' after call arguments, but got '\(t.value)'", at: t)
                endToken = t
            }
        } else {
            emitError("expected ')' after call arguments", at: endOfFile)
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
    private func parseAnnotations() -> ([AST.Modifier], [AST.Attribute]) {
        var modifiers: [AST.Modifier] = []
        var attributes: [AST.Attribute] = []
        _loop: while let token = peek {
            switch token.kind {
            case .Keyword(let kind):
                switch kind {
                case .Open:
                    self.index += 1
                    if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
                        self.index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            self.index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(let kind) = t3.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                            modifiers.append(
                                AST.Modifier(
                                    token: token,
                                    kind: .Open(setter: true),
                                    sourceRange: SourceRange(from: token, to: t3, in: buffer)
                                )
                            )
                        } else {
                            emitError("expected ')' after 'set', but got '\(t3.value)'", at: t3)
                        }
                    } else {
                        modifiers.append(
                            AST.Modifier(
                                token: token,
                                kind: .Open(setter: false),
                                sourceRange: token.sourceRange(in: buffer)
                            )
                        )
                    }
                case .Public:
                    self.index += 1
                    if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
                        self.index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            self.index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(let kind) = t3.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                            modifiers.append(
                                AST.Modifier(
                                    token: token,
                                    kind: .Public(setter: true),
                                    sourceRange: SourceRange(from: token, to: t3, in: buffer)
                                )
                            )
                        } else {
                            emitError("expected ')' after 'set', but got '\(t3.value)'", at: t3)
                        }
                    } else {
                        modifiers.append(
                            AST.Modifier(
                                token: token,
                                kind: .Public(setter: false),
                                sourceRange: token.sourceRange(in: buffer)
                            )
                        )
                    }
                case .Protected:
                    self.index += 1
                    if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
                        self.index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            self.index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(let kind) = t3.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                            modifiers.append(
                                AST.Modifier(
                                    token: token,
                                    kind: .Protected(setter: true),
                                    sourceRange: SourceRange(from: token, to: t3, in: buffer)
                                )
                            )
                        } else {
                            emitError("expected ')' after 'set', but got '\(t3.value)'", at: t3)
                        }
                    } else {
                        modifiers.append(
                            AST.Modifier(
                                token: token,
                                kind: .Protected(setter: false),
                                sourceRange: token.sourceRange(in: buffer)
                            )
                        )
                    }
                case .PackagePrivate:
                    self.index += 1
                    if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
                        self.index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            self.index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(let kind) = t3.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                            modifiers.append(
                                AST.Modifier(
                                    token: token,
                                    kind: .PackagePrivate(setter: true),
                                    sourceRange: SourceRange(from: token, to: t3, in: buffer)
                                )
                            )
                        } else {
                            emitError("expected ')' after 'set', but got '\(t3.value)'", at: t3)
                        }
                    } else {
                        modifiers.append(
                            AST.Modifier(
                                token: token,
                                kind: .PackagePrivate(setter: false),
                                sourceRange: token.sourceRange(in: buffer)
                            )
                        )
                    }
                case .Internal:
                    self.index += 1
                    if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
                        self.index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            self.index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(let kind) = t3.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                            modifiers.append(
                                AST.Modifier(
                                    token: token,
                                    kind: .Internal(setter: true),
                                    sourceRange: SourceRange(from: token, to: t3, in: buffer)
                                )
                            )
                        } else {
                            emitError("expected ')' after 'set', but got '\(t3.value)'", at: t3)
                        }
                    } else {
                        modifiers.append(
                            AST.Modifier(
                                token: token,
                                kind: .Internal(setter: false),
                                sourceRange: token.sourceRange(in: buffer)
                            )
                        )
                    }
                case .FilePrivate:
                    self.index += 1
                    if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
                        self.index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            self.index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(let kind) = t3.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                            modifiers.append(
                                AST.Modifier(
                                    token: token,
                                    kind: .FilePrivate(setter: true),
                                    sourceRange: SourceRange(from: token, to: t3, in: buffer)
                                )
                            )
                        } else {
                            emitError("expected ')' after 'set', but got '\(t3.value)'", at: t3)
                        }
                    } else {
                        modifiers.append(
                            AST.Modifier(
                                token: token,
                                kind: .FilePrivate(setter: false),
                                sourceRange: token.sourceRange(in: buffer)
                            )
                        )
                    }
                case .Private:
                    self.index += 1
                    if let t = peek, case .Separator(let kind) = t.kind, case .OpenParen = kind {
                        self.index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            self.index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(let kind) = t3.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                            modifiers.append(
                                AST.Modifier(
                                    token: token,
                                    kind: .Private(setter: true),
                                    sourceRange: SourceRange(from: token, to: t3, in: buffer)
                                )
                            )
                        } else {
                            emitError("expected ')' after 'set', but got '\(t3.value)'", at: t3)
                        }
                    } else {
                        modifiers.append(
                            AST.Modifier(
                                token: token,
                                kind: .Private(setter: false),
                                sourceRange: token.sourceRange(in: buffer)
                            )
                        )
                    }
                case .Abstract:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Abstract,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Final:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Final,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Mutating:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Mutating,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Nonmutating:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Nonmutating,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Convenience:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token, kind: .Convenience,
                            sourceRange: token.sourceRange(in: buffer)))
                case .Override:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Override,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Lazy:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Lazy,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Weak:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Weak,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Unowned:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Unowned,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Indirect:
                    self.index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Indirect,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                default:
                    break _loop
                }
            case .Separator(let kind) where kind == .Sharp:
                guard let t = peek2,
                    case .Separator(let kind) = t.kind,
                    kind == .OpenBracket
                else {
                    break _loop
                }
                self.index += 2
                guard let name = peek else {
                    emitError("expected attribute name after '#['", at: endOfFile)
                    break _loop
                }
                guard case .Identifier = name.kind else {
                    emitError(
                        "expected attribute name after '#[' but got '\(name.value)'", at: name)
                    break _loop
                }
                self.index += 1
                guard let t2 = peek else {
                    emitError("expected '(' or ']' after attribute name", at: endOfFile)
                    break _loop
                }
                guard case .Separator(let t2Kind) = t2.kind else {
                    emitError(
                        "expected '(' or ']' after attribute name, but got '\(t2.value)'", at: t2)
                    break _loop
                }
                var arguments: [[Token]] = []
                var labeledArguments: [Token: [Token]] = [:]
                if case .OpenParen = t2Kind {
                    self.index += 1
                    while let t = peek {
                        self.index += 1
                        if case .Identifier = t.kind, let t2 = peek,
                            case .Separator(let kind) = t2.kind,
                            case .Colon = kind
                        {
                            self.index += 1
                            var args: [Token] = []
                            while let t2 = peek {
                                if case .Separator(let kind) = t2.kind, case .CloseParen = kind {
                                    break
                                }
                                self.index += 1
                                if case .Separator(let kind) = t2.kind, case .Comma = kind {
                                    break
                                }
                                args.append(t2)
                            }
                            labeledArguments[t] = args
                        } else {
                            var args: [Token] = [t]
                            while let t2 = peek {
                                if case .Separator(let kind) = t2.kind, case .CloseParen = kind {
                                    break
                                }
                                self.index += 1
                                if case .Separator(let kind) = t2.kind, case .Comma = kind {
                                    break
                                }
                                args.append(t2)
                            }
                            arguments.append(args)
                        }
                    }
                    if let t = peek {
                        if case .Separator(let kind) = t.kind,
                            case .CloseParen = kind
                        {
                            self.index += 1
                        } else {
                            emitError(
                                "expected ')' after attribute arguments, but got '\(t.value)'",
                                at: t)
                        }
                    } else {
                        emitError("expected ')' after attribute arguments", at: endOfFile)
                        break _loop
                    }
                }
                if let t = peek {
                    if case .Separator(let kind) = t.kind, case .CloseBracket = kind {
                        self.index += 1
                    } else {
                        emitError(
                            "expected ']' after attribute arguments, but got '\(t.value)'",
                            at: t)
                    }
                } else {
                    emitError("expected ']' in attribute", at: endOfFile)
                    break _loop
                }
                attributes.append(
                    AST.Attribute(
                        name: name,
                        arguments: arguments,
                        labeledArguments: labeledArguments,
                        sourceRange: SourceRange(
                            start: token.sourceRange(in: buffer).start,
                            end: endOfFile
                        )
                    )
                )
            default:
                break _loop
            }
        }
        return (modifiers, attributes)
    }
}
