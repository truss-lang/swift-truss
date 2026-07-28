import SwiftBetterDiagnostic
import TrussCore

public final class Parser {
    private let context: Context
    private let packageName: String
    private let lexerResult: LexerResult
    private let source: Source
    private var index: Int = 0
    private var buffer: SourceBuffer { source.stringSourceBuffer }
    public var last: Token? {
        if index - 1 < lexerResult.tokens.count {
            return lexerResult.tokens[index - 1]
        } else {
            return nil
        }
    }

    public var peek: Token? {
        if index < lexerResult.tokens.count {
            return lexerResult.tokens[index]
        } else {
            return nil
        }
    }

    public var peek2: Token? {
        if (index + 1) < lexerResult.tokens.count {
            return lexerResult.tokens[index + 1]
        } else {
            return nil
        }
    }

    public var peek3: Token? {
        if (index + 2) < lexerResult.tokens.count {
            return lexerResult.tokens[index + 2]
        } else {
            return nil
        }
    }

    public var next: Token? {
        if index < lexerResult.tokens.count {
            let t = lexerResult.tokens[index]
            index += 1
            return t
        } else {
            return nil
        }
    }

    public init(context: Context, packageName: String, _ lexerResult: LexerResult) {
        self.context = context
        self.packageName = packageName
        self.lexerResult = lexerResult
        source = context.sourceTable[lexerResult.id]!
    }

    private var endOfFile: SourceLocation {
        let converter = LocationConverter(source: source.content)
        let (line, column) = converter.lineAndColumn(for: source.content.utf8.count)
        return SourceLocation(
            buffer: buffer, offset: source.content.utf8.count, line: line, column: column
        )
    }

    private func locationAfter(_ token: Token) -> SourceLocation {
        let converter = LocationConverter(source: source.content)
        let offset = token.pos.pos + token.pos.len
        let (line, column) = converter.lineAndColumn(for: offset)
        return SourceLocation(buffer: buffer, offset: offset, line: line, column: column)
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
                range: token.sourceRange(in: buffer), notes: notes
            ))
    }

    private func errorStatement(from startToken: Token, to endToken: Token)
        -> AST.ErrorStatement
    {
        AST.ErrorStatement(sourceRange: SourceRange(from: startToken, to: endToken, in: buffer))
    }

    private func errorStatement(from startToken: Token, to endLocation: SourceLocation)
        -> AST.ErrorStatement
    {
        AST.ErrorStatement(
            sourceRange: SourceRange(
                start: startToken.sourceRange(in: buffer).start, end: endLocation
            ))
    }

    private func errorExpression(from startToken: Token, to endToken: Token)
        -> AST.ErrorExpression
    {
        AST.ErrorExpression(SourceRange(from: startToken, to: endToken, in: buffer))
    }

    private func errorExpression(from startToken: Token, to endLocation: SourceLocation)
        -> AST.ErrorExpression
    {
        AST.ErrorExpression(
            SourceRange(
                start: startToken.sourceRange(in: buffer).start, end: endLocation
            ))
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
                case .Import: statement = parseImport()
                case .TypeAlias: statement = parseTypeAliasDecl(modifiers, attributes)
                case .Module: statement = parseModuleDecl(modifiers, attributes)
                case .PrecedenceGroup: statement = parsePrecedenceGroupDecl(modifiers, attributes)
                case .Struct: statement = parseStructDecl(modifiers, attributes)
                case .Class: statement = parseClassDecl(modifiers, attributes)
                case .ProtocolKw: statement = parseProtocolDecl(modifiers, attributes)
                case .Extension: statement = parseExtensionDecl(modifiers, attributes)
                case .Actor: statement = parseActorDecl(modifiers, attributes)
                case .Func: statement = parseFunctionDecl(modifiers, attributes)
                case .Let: statement = parseVariableDecl(modifiers, attributes)
                case .Var: statement = parseVariableDecl(modifiers, attributes)
                default: statement = nil
                }
            case .Separator(let kind):
                switch kind {
                case .SemiColon:
                    index += 1
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
        let programRange: SourceRange
        if let f = firstRange, let l = lastRange {
            programRange = SourceRange(start: f.start, end: l.end)
        } else {
            programRange = SourceRange(location: endOfFile)
        }
        return AST.Program(lexerResult.id, packageName, statements, sourceRange: programRange)
    }

    private func parseBasicStatement() -> AST.Statement? {
        let startToken = peek
        let (modifiers, attributes) = parseAnnotations()
        guard let t = peek else {
            if modifiers.isEmpty, attributes.isEmpty {
                return nil
            } else {
                emitError("expected statement", at: endOfFile)
                return errorStatement(from: startToken!, to: endOfFile)
            }
        }
        switch t.kind {
        case .Keyword(let keywordKind):
            switch keywordKind {
            case .TypeAlias: return parseTypeAliasDecl(modifiers, attributes)
            case .Module: return parseModuleDecl(modifiers, attributes)
            case .PrecedenceGroup: return parsePrecedenceGroupDecl(modifiers, attributes)
            case .Struct: return parseStructDecl(modifiers, attributes)
            case .Class: return parseClassDecl(modifiers, attributes)
            case .ProtocolKw: return parseProtocolDecl(modifiers, attributes)
            case .Actor: return parseActorDecl(modifiers, attributes)
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes)
            case .Var: return parseVariableDecl(modifiers, attributes)
            default: return nil
            }
        case .Separator(let kind):
            switch kind {
            case .SemiColon:
                index += 1
                return AST.EmptyStatement(t, sourceRange: t.sourceRange(in: buffer))
            default: return nil
            }
        default:
            return nil
        }
    }

    private func parseImport() -> AST.Statement {
        let token = next!
        var components: [AST.PathComponent] = []
        guard let first = peek else {
            emitError("expected module path after 'import'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        switch first.kind {
        case .Identifier:
            index += 1
            components.append(.identifier(first))
        case .Keyword(.SelfTypeKw):
            index += 1
            components.append(.self_(first))
        case .Keyword(.SelfKw):
            emitError(
                "'self' is not allowed in import path, use 'Self' instead", at: first
            )
            index += 1
            components.append(.self_(first))
        default:
            emitError(
                "expected module path after 'import', but got '\(first.value)'", at: first
            )
            return errorStatement(from: token, to: first)
        }

        var selector: AST.ImportSelector? = nil
        var endToken: Token = first
        _pathLoop: while let dotToken = peek, case .Operator(.Dot) = dotToken.kind {
            guard let afterDot = peek2 else {
                break _pathLoop
            }
            switch afterDot.kind {
            case .Operator(.Multiply):
                index += 2
                selector = .wildcard
                endToken = afterDot
                if let asToken = peek, case .Keyword(.As) = asToken.kind {
                    emitError("cannot alias a wildcard import", at: asToken)
                    index += 1
                    if let aliasToken = peek, case .Identifier = aliasToken.kind {
                        index += 1
                        endToken = aliasToken
                    }
                }
                break _pathLoop
            case .Separator(.OpenBrace):
                index += 2
                endToken = afterDot
                var items: [AST.ImportItem] = []
                while let t = peek {
                    if case .Separator(.CloseBrace) = t.kind {
                        break
                    }
                    let item = parseImportItem()
                    items.append(item)
                    if let lastComp = peek, case .Separator(.CloseBrace) = lastComp.kind {
                        break
                    }
                    if let comma = peek, case .Separator(.Comma) = comma.kind {
                        index += 1
                    } else {
                        break
                    }
                }
                if items.isEmpty {
                    emitError("expected import item after '{'", at: endToken)
                }
                if let closeToken = peek, case .Separator(.CloseBrace) = closeToken.kind {
                    index += 1
                    endToken = closeToken
                } else {
                    emitError("expected '}' after import items", at: endOfFile)
                }
                selector = .explicit(items)
                break _pathLoop
            default:
                index += 1
                guard let comp = peek else {
                    emitError("expected module name after '.'", at: endOfFile)
                    endToken = dotToken
                    break _pathLoop
                }
                switch comp.kind {
                case .Identifier:
                    index += 1
                    components.append(.identifier(comp))
                    endToken = comp
                case .Keyword(.SelfTypeKw):
                    emitError(
                        "'Self' can only appear at the beginning of an import path", at: comp
                    )
                    index += 1
                    components.append(.self_(comp))
                    endToken = comp
                case .Keyword(.SelfKw):
                    emitError(
                        "'self' is not allowed in import path, use 'Self' instead", at: comp
                    )
                    index += 1
                    components.append(.self_(comp))
                    endToken = comp
                default:
                    emitError(
                        "expected module name after '.', but got '\(comp.value)'", at: comp
                    )
                    endToken = dotToken
                    break _pathLoop
                }
            }
        }

        if selector == nil {
            var alias: Token? = nil
            if let asToken = peek, case .Keyword(.As) = asToken.kind {
                index += 1
                if let aliasToken = peek {
                    if case .Identifier = aliasToken.kind {
                        index += 1
                        alias = aliasToken
                        endToken = aliasToken
                    } else {
                        emitError(
                            "expected identifier after 'as', but got '\(aliasToken.value)'",
                            at: aliasToken
                        )
                        endToken = asToken
                    }
                } else {
                    emitError("expected identifier after 'as'", at: endOfFile)
                    endToken = asToken
                }
                if let asToken2 = peek, case .Keyword(.As) = asToken2.kind {
                    emitError("unexpected 'as'", at: asToken2)
                    index += 1
                    if let aliasToken2 = peek, case .Identifier = aliasToken2.kind {
                        index += 1
                        endToken = aliasToken2
                    }
                }
            }
            selector = .wholeModule(alias: alias)
        }

        return AST.ImportDecl(
            token, AST.ImportPath(components), selector!,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseImportItem() -> AST.ImportItem {
        guard let t = peek else {
            return AST.ImportItem(.name(errorToken()), alias: nil)
        }
        let kind: AST.ImportItem.Kind
        switch t.kind {
        case .Keyword(.SelfKw):
            index += 1
            kind = .self_(t)
        case .Identifier:
            index += 1
            kind = .name(t)
        case .Keyword(.SelfTypeKw):
            emitError(
                "'Self' is not allowed in import selector, use 'self' instead", at: t
            )
            index += 1
            kind = .self_(t)
        default:
            emitError(
                "expected import item name, but got '\(t.value)'", at: t
            )
            index += 1
            kind = .name(t)
        }
        var alias: Token? = nil
        if let asToken = peek, case .Keyword(.As) = asToken.kind {
            index += 1
            if let aliasToken = peek {
                if case .Identifier = aliasToken.kind {
                    index += 1
                    alias = aliasToken
                } else {
                    emitError(
                        "expected identifier after 'as', but got '\(aliasToken.value)'",
                        at: aliasToken
                    )
                }
            } else {
                emitError("expected identifier after 'as'", at: endOfFile)
            }
            if let asToken2 = peek, case .Keyword(.As) = asToken2.kind {
                emitError("unexpected 'as'", at: asToken2)
                index += 1
                if let aliasToken2 = peek, case .Identifier = aliasToken2.kind {
                    index += 1
                }
            }
        }
        return AST.ImportItem(kind, alias: alias)
    }

    private func errorToken() -> Token {
        return Token(
            value: "<error>", kind: .Unknown,
            pos: Position(pos: 0, line: 0, col: 0, len: 0), id: Id.SourceId(id: 0)
        )
    }

    private func parseTypeAliasDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected type name after 'typealias'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if name.kind != .Identifier {
            emitError("expected identifier after 'typealias', but got '\(name.value)'", at: name)
        }
        guard let equalToken = next else {
            emitError("expected '=' after type alias name", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if equalToken.kind != .Operator(.Assign) {
            emitError(
                "expected '=' after type alias name, but got '\(equalToken.value)'",
                at: equalToken
            )
        }
        var typeExpression = parseExpression()
        if typeExpression == nil {
            emitError("expected type expression after '='", at: locationAfter(equalToken))
            typeExpression = AST.ErrorExpression(SourceRange(location: locationAfter(equalToken)))
        }
        return AST.TypeAliasDecl(
            modifiers, attributes, token, name, typeExpression!,
            sourceRange: token.sourceRange(in: buffer)
        )
    }

    private func parseModuleDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected module name after 'module'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'module', but got '\(name.value)'", at: name)
            return errorStatement(from: token, to: name)
        }
        guard let openToken = next else {
            emitError("expected '{' after module name", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError("expected '{' after module name, but got '\(openToken.value)'", at: openToken)
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            } else if let statement = parseBasicStatement() {
                body.append(statement)
            } else {
                break
            }
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
            } else {
                emitError(
                    "expected '}' after module body, but got \(closeToken.value)", at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after module body", at: endOfFile)
            endToken = openToken
        }
        return AST.ModuleDecl(
            modifiers, attributes, token, name, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parsePrecedenceGroupDecl(
        _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute]
    ) -> AST.Statement {
        let token = next!
        guard let name = next else {
            emitError("expected precedence group name after 'precedencegroup'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError(
                "expected identifier after 'precedencegroup', but got '\(name.value)'",
                at: name
            )
            return errorStatement(from: token, to: name)
        }
        guard let openToken = next else {
            emitError("expected '{' after precedencegroup name", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after precedencegroup name, but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var higherThanTokens: [Token] = []
        var higherThan: [AST.Expression] = []
        var lowerThanTokens: [Token] = []
        var lowerThan: [AST.Expression] = []
        var associativityToken: Token? = nil
        var associativity: AST.PrecedenceGroupDecl.Associativity = .None
        var assignmentToken: Token? = nil
        var assignment = false
        _loop: while let t = peek {
            if case .Identifier = t.kind {
                switch t.value {
                case "associativity":
                    index += 1
                    if associativityToken == nil {
                        associativityToken = t
                    } else {
                        emitError(
                            "associativity can only be set once", at: t,
                            notes: [note("previous definition here", at: associativityToken!)]
                        )
                    }
                    if let t2 = peek {
                        if case .Separator(.Colon) = t2.kind {
                            index += 1
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
                                index += 1
                                associativity = .Left
                            case "right":
                                index += 1
                                associativity = .Right
                            case "none":
                                index += 1
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
                    index += 1
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
                        if case .Separator(.Colon) = t2.kind {
                            index += 1
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
                            index += 1
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
                    index += 1
                    higherThanTokens.append(t)
                    if let t2 = peek {
                        if case .Separator(.Colon) = t2.kind {
                            index += 1
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
                        if case .Separator(.CloseBrace) = t2.kind {
                            break
                        }
                        if case .Identifier = t2.kind,
                            ["higherThan", "lowerThan", "associativity", "assignment"].contains(
                                t2.value)
                        {
                            break
                        }
                        if let expr = parseExpression() {
                            higherThan.append(expr)
                        }
                        if let t3 = peek, case .Separator(.Comma) = t3.kind {
                            index += 1
                        } else {
                            break
                        }
                    }
                case "lowerThan":
                    index += 1
                    lowerThanTokens.append(t)
                    if let t2 = peek {
                        if case .Separator(.Colon) = t2.kind {
                            index += 1
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
                        if case .Separator(.CloseBrace) = t2.kind {
                            break
                        }
                        if case .Identifier = t2.kind,
                            ["higherThan", "lowerThan", "associativity", "assignment"].contains(
                                t2.value)
                        {
                            break
                        }
                        if let expr = parseExpression() {
                            lowerThan.append(expr)
                        }
                        if let t3 = peek, case .Separator(.Comma) = t3.kind {
                            index += 1
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
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
            } else {
                emitError(
                    "expected '}' after precedencegroup body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after precedencegroup body", at: endOfFile)
        }
        return AST.PrecedenceGroupDecl(
            modifiers, attributes, token, name, higherThanTokens, higherThan, lowerThanTokens,
            lowerThan, associativityToken, associativity, assignmentToken, assignment,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseStructDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected struct name after 'struct'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'struct', but got '\(name.value)'", at: name)
            return errorStatement(from: token, to: name)
        }
        let genericDecl: AST.GenericDecl? =
            if let t = peek, case .Operator(.Less) = t.kind {
                parseGenericDecl()
            } else {
                nil
            }
        var conformances: [AST.Expression] = []
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            while peek != nil {
                if let expr = parseExpression() {
                    conformances.append(expr)
                }
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        guard let openToken = next else {
            emitError("expected '{' in struct type", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' in struct type, but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseTypeBodyStatement() {
                body.append(stmt)
            }
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
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
            modifiers, attributes, token, name, genericDecl, conformances, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseClassDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected class name after 'class'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'class', but got '\(name.value)'", at: name)
            return errorStatement(from: token, to: name)
        }
        let genericDecl: AST.GenericDecl? =
            if let t = peek, case .Operator(.Less) = t.kind {
                parseGenericDecl()
            } else {
                nil
            }
        var inheritanceClauses: [AST.Expression] = []
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            while peek != nil {
                if let expr = parseExpression() {
                    inheritanceClauses.append(expr)
                }
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        guard let openToken = next else {
            emitError("expected '{' in class type", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' in class type, but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseTypeBodyStatement() {
                body.append(stmt)
            }
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
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
            modifiers, attributes, token, name, genericDecl, inheritanceClauses, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseActorDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected actor name after 'actor'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'actor', but got '\(name.value)'", at: name)
            return errorStatement(from: token, to: name)
        }
        let genericDecl: AST.GenericDecl? =
            if let t = peek, case .Operator(.Less) = t.kind {
                parseGenericDecl()
            } else {
                nil
            }
        var conformances: [AST.Expression] = []
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            while peek != nil {
                if let expr = parseExpression() {
                    conformances.append(expr)
                }
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        guard let openToken = next else {
            emitError("expected '{' in actor type", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' in actor type, but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseTypeBodyStatement() {
                body.append(stmt)
            }
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
            } else {
                emitError(
                    "expected '}' after actor body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after actor body", at: endOfFile)
            endToken = openToken
        }
        return AST.ActorDecl(
            modifiers, attributes, token, name, genericDecl, conformances, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseProtocolDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected protocol name after 'protocol'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'protocol', but got '\(name.value)'", at: name)
            return errorStatement(from: token, to: name)
        }
        let genericDecl: AST.GenericDecl? =
            if let t = peek, case .Operator(.Less) = t.kind {
                parseGenericDecl()
            } else {
                nil
            }
        var conformances: [AST.Expression] = []
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            while peek != nil {
                if let expr = parseExpression() {
                    conformances.append(expr)
                }
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        guard let openToken = next else {
            emitError("expected '{' in protocol type", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError("expected '{' in protocol type, but got '\(openToken.value)'", at: openToken)
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let t = peek {
            if case .Separator(.CloseBrace) = t.kind {
                break
            }
            if let stmt = parseTypeBodyStatement(isProtocolContext: true) {
                body.append(stmt)
            }
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
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
            modifiers, attributes, token, name, genericDecl, conformances, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseExtensionDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        let base =
            parseExpression(excepts: [.Less])
            ?? errorExpression(from: token, to: token)
        if let t = peek, case .Operator(.Less) = t.kind {
            let genericDecl = parseGenericDecl()
            emitError(
                "declaring generic type in extension is not allowed",
                at: genericDecl?.sourceRange ?? t.sourceRange(in: buffer)
            )
        }
        var conformances: [AST.Expression] = []
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            while peek != nil {
                if let expr = parseExpression() {
                    conformances.append(expr)
                }
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        guard let openToken = next else {
            emitError("expected '{' in extension", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError("expected '{' in extension, but got '\(openToken.value)'", at: openToken)
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseTypeBodyStatement(isProtocolContext: true) {
                body.append(stmt)
            }
        }
        let endToken: Token
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
            } else {
                emitError(
                    "expected '}' after extension body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after extension body", at: endOfFile)
            endToken = openToken
        }
        return AST.ExtensionDecl(
            modifiers, attributes, token, base, conformances, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseGenericDecl() -> AST.GenericDecl? {
        let begin = next!
        var generics: [AST.GenericParameter] = []
        while let t = peek {
            if t.kind == .Operator(.Greater) || t.kind == .Keyword(.Each) {
                break
            }
            index += 1
            if t.kind == .Separator(.Comma) {
                continue
            }
            if t.kind != .Identifier {
                emitError(
                    "expected identifier after 'each', but got '\(t.value)'",
                    at: t
                )
            }
        }
        if let t = peek, case .Keyword(.Each) = t.kind {
            let l = last!
            if l.kind != .Operator(.Greater), l.kind != .Separator(.Comma) {
                emitError("expected ',' before 'each'", at: l)
            }
            index += 1
            if let name = next {
                if name.kind != .Identifier {
                    emitError(
                        "expected identifier after 'each', but got '\(name.value)'",
                        at: name
                    )
                }
                let constraint: AST.Expression?
                if let t2 = peek, case .Separator(.Colon) = t2.kind {
                    index += 1
                    constraint = parseExpression(excepts: [.Greater])
                } else {
                    constraint = nil
                }
                generics.append(
                    AST.GenericParameter(
                        t, name, constraint,
                        sourceRange: SourceRange(from: t, to: last!, in: buffer)
                    )
                )
            } else {
                emitError("expected identifier after 'each'", at: endOfFile)
            }
        }
        guard let end = peek else {
            emitError("expected '>' after generic parameters", at: endOfFile)
            return nil
        }
        if case .Operator(.Greater) = end.kind {
            index += 1
        } else {
            emitError("expected '>' after generic parameters, but got '\(end.value)'", at: end)
        }
        return AST.GenericDecl(
            begin, generics, end,
            sourceRange: SourceRange(from: begin, to: end, in: buffer)
        )
    }

    private func parseTypeBodyStatement(isProtocolContext _: Bool = false) -> AST.Statement? {
        let startToken = peek
        let (modifiers, attributes) = parseAnnotations()
        guard let token = peek else {
            if modifiers.isEmpty, attributes.isEmpty {
                return nil
            } else {
                emitError("expected statement", at: endOfFile)
                return errorStatement(from: startToken!, to: endOfFile)
            }
        }
        switch token.kind {
        case .Keyword(let kind):
            switch kind {
            case .TypeAlias: return parseTypeAliasDecl(modifiers, attributes)
            case .PrecedenceGroup: return parsePrecedenceGroupDecl(modifiers, attributes)
            case .Struct: return parseStructDecl(modifiers, attributes)
            case .Class: return parseClassDecl(modifiers, attributes)
            case .ProtocolKw: return parseProtocolDecl(modifiers, attributes)
            case .Actor: return parseActorDecl(modifiers, attributes)
            case .Extension: return parseExtensionDecl(modifiers, attributes)
            case .Init: return parseInitDecl(modifiers, attributes)
            case .Deinit: return parseDeinitDecl(modifiers, attributes)
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes)
            case .Var: return parseVariableDecl(modifiers, attributes)
            default:
                index += 1
                emitError("expected a statement, but got \(token.value)", at: token)
                return errorStatement(from: startToken ?? token, to: token)
            }
        case .Separator(let kind):
            switch kind {
            case .SemiColon:
                index += 1
                return AST.EmptyStatement(token, sourceRange: token.sourceRange(in: buffer))
            default:
                index += 1
                emitError("expected a statement, but got \(token.value)", at: token)
                return errorStatement(from: startToken ?? token, to: token)
            }
        default:
            index += 1
            emitError("expected a statement, but got \(token.value)", at: token)
            return errorStatement(from: startToken ?? token, to: token)
        }
    }

    private func parseInitDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        let optionalToken: Token?
        if let t = peek, t.kind == .Operator(.QuestionMark) {
            index += 1
            optionalToken = t
        } else {
            optionalToken = nil
        }
        guard let t1 = peek else {
            emitError("expected '(' after 'init'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenParen) = t1.kind else {
            emitError("expected '(' after 'init', but got '\(t1.value)'", at: t1)
            return errorStatement(from: token, to: t1)
        }
        index += 1
        guard let t2 = peek else {
            emitError("expected ')' after initializer parameters", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Separator(.CloseParen) = t2.kind {
            index += 1
        } else {
            emitError("expected ')' after initializer parameters, but got '\(t2.value)'", at: t2)
        }
        guard let t3 = peek else {
            emitError("expected '{' after initializer parameters", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = t3.kind else {
            emitError("expected '{' after initializer parameters, but got '\(t3.value)'", at: t3)
            return errorStatement(from: token, to: t3)
        }
        index += 1
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
            } else {
                emitError(
                    "expected '}' after initializer body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
        } else {
            emitError("expected '}' after initializer body", at: endOfFile)
        }
        return AST.InitDecl(
            modifiers, attributes, token, optionalToken, body,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }
    private func parseDeinitDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let t3 = peek else {
            emitError("expected '{' after 'deinit'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = t3.kind else {
            emitError("expected '{' after 'deinit', but got '\(t3.value)'", at: t3)
            return errorStatement(from: token, to: t3)
        }
        index += 1
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        if let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
            } else {
                emitError(
                    "expected '}' after deinitializer body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
        } else {
            emitError("expected '}' after deinitializer body", at: endOfFile)
        }
        return AST.DeinitDecl(
            modifiers, attributes, token, body,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }
    private func parseStatement() -> AST.Statement? {
        let startToken = peek
        let (modifiers, attributes) = parseAnnotations()
        guard let token = peek else {
            if modifiers.isEmpty, attributes.isEmpty {
                return nil
            } else {
                emitError("expected statement", at: endOfFile)
                return errorStatement(from: startToken!, to: endOfFile)
            }
        }
        switch token.kind {
        case .Keyword(let kind):
            switch kind {
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes, inFunctionContext: true)
            case .Var: return parseVariableDecl(modifiers, attributes, inFunctionContext: true)
            case .Return: return parseReturn()
            case .While: return parseWhile()
            case .Repeat: return parseRepeatWhile()
            case .Guard: return parseGuard()
            case .Defer: return parseDefer()
            case .Break: return parseBreak()
            case .Continue: return parseContinue()
            case .Goto: return parseGoto()
            default:
                let savedIndex = index
                if let expr = parseExpression() {
                    return AST.ExpressionStatement(expr, sourceRange: expr.sourceRange)
                }
                if index == savedIndex {
                    index += 1
                    emitError("expected a statement, but got \(token.value)", at: token)
                }
                return errorStatement(from: startToken ?? token, to: last ?? token)
            }
        case .Separator(let kind):
            switch kind {
            case .SemiColon:
                index += 1
                return AST.EmptyStatement(token, sourceRange: token.sourceRange(in: buffer))
            default:
                let savedIndex = index
                if let expr = parseExpression() {
                    return AST.ExpressionStatement(expr, sourceRange: expr.sourceRange)
                }
                if index == savedIndex {
                    index += 1
                    emitError("expected a statement, but got \(token.value)", at: token)
                }
                return errorStatement(from: startToken ?? token, to: last ?? token)
            }
        default:
            let savedIndex = index
            if let expr = parseExpression() {
                return AST.ExpressionStatement(expr, sourceRange: expr.sourceRange)
            }
            if index == savedIndex {
                index += 1
                emitError("expected a statement, but got \(token.value)", at: token)
            }
            return errorStatement(from: startToken ?? token, to: last ?? token)
        }
    }

    private func parseFunctionDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        guard let token = next else {
            return AST.ErrorStatement(sourceRange: SourceRange(location: endOfFile))
        }
        guard let name = next else {
            emitError("expected function name after 'func'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard let t1 = peek else {
            emitError("expected '(' after function name", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenParen) = t1.kind else {
            emitError("expected '(' after function name, but got '\(t1.value)'", at: t1)
            return errorStatement(from: token, to: t1)
        }
        index += 1
        guard let t2 = peek else {
            emitError("expected ')' after function parameters", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Separator(.CloseParen) = t2.kind {
            index += 1
        } else {
            emitError("expected ')' after function parameters, but got '\(t2.value)'", at: t2)
        }
        let returnTypeExpression: AST.Expression?
        if let t = peek, case .Separator(.Arrow) = t.kind {
            index += 1
            returnTypeExpression = parseExpression(excepts: [.Assign])
        } else {
            returnTypeExpression = nil
        }
        let body: AST.FunctionDecl.Body?
        if let t = peek {
            switch t.kind {
            case .Separator(.OpenBrace):
                index += 1
                var statements: [AST.Statement] = []
                while let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        break
                    }
                    if let stmt = parseStatement() {
                        statements.append(stmt)
                    }
                }
                if let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        index += 1
                    } else {
                        emitError(
                            "expected '}' after function body, but got \(closeToken.value)",
                            at: closeToken
                        )
                    }
                } else {
                    emitError("expected '}' after function body", at: endOfFile)
                }

                body = .Block(statements)
            case .Operator(.Assign):
                index += 1
                let expr = parseExpression() ?? errorExpression(from: t, to: t)
                body = .Expression(expr)
            default:
                body = nil
            }
        } else {
            body = nil
        }
        return AST.FunctionDecl(
            modifiers, attributes, token, name, returnTypeExpression, body,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseVariableDecl(
        _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], inFunctionContext: Bool = false
    )
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected variable name", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        let typeExpression: AST.Expression?
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            typeExpression = parseExpression(excepts: [.Assign])
        } else {
            typeExpression = nil
        }
        let initializer: AST.Expression?
        if let t = peek, case .Operator(.Assign) = t.kind {
            index += 1
            initializer = parseExpression()
        } else {
            initializer = nil
        }
        let accessors: [AST.Accessor]
        if let t = peek, case .Separator(.OpenBrace) = t.kind {
            accessors = parseAccessors()
            let hasGet = accessors.contains { $0.kind == .Get }
            let hasSet = accessors.contains { $0.kind == .Set }
            let hasObserver = accessors.contains {
                $0.kind == .WillSet || $0.kind == .DidSet
            }
            var seenKinds: Set<AST.Accessor.Kind> = []
            for accessor in accessors {
                if seenKinds.contains(accessor.kind) {
                    let first = accessors.first { $0.kind == accessor.kind }!
                    emitError(
                        "duplicate '\(accessor.token!.value)' accessor",
                        at: accessor.token!,
                        notes: [note("first declared here", at: first.token!)]
                    )
                }
                seenKinds.insert(accessor.kind)
            }
            if inFunctionContext, hasObserver {
                let observer = accessors.first {
                    $0.kind == .WillSet || $0.kind == .DidSet
                }!
                emitError(
                    "property observers are not allowed in function context",
                    at: observer.sourceRange
                )
            }
            if let initializer = initializer, hasGet || hasSet {
                let accessor = accessors.first {
                    $0.kind == .Get || $0.kind == .Set
                }!
                context.diagnositicEngine.emit(
                    Diagnostic(
                        severity: .error,
                        message: "stored property cannot have a getter or setter",
                        range: accessor.sourceRange,
                        notes: [
                            Diagnostic(
                                severity: .note,
                                message: "initializer makes this a stored property",
                                range: initializer.sourceRange
                            )
                        ]
                    )
                )
            }
            if initializer == nil, hasGet, hasObserver {
                let observer = accessors.first {
                    $0.kind == .WillSet || $0.kind == .DidSet
                }!
                emitError(
                    "computed property cannot have 'willSet' or 'didSet' observers",
                    at: observer.sourceRange
                )
            }
            if hasSet, !hasGet {
                let setter = accessors.first { $0.kind == .Set }!
                emitError("setter requires a getter", at: setter.sourceRange)
            }
            if initializer == nil, hasGet || hasSet, typeExpression == nil {
                emitError("computed property must have a type annotation", at: name)
            }
        } else {
            accessors = []
        }
        return AST.VariableDecl(
            modifiers, attributes, token, name, typeExpression, initializer, accessors,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseAccessors() -> [AST.Accessor] {
        let beginToken = next!
        var hasError = false
        var accessors: [AST.Accessor] = []
        _loop: while let t = peek {
            if t.kind == .Separator(.CloseBrace) {
                break
            }
            let (modifiers, attributes) = parseAnnotations()
            guard let t2 = peek else {
                emitError(
                    "expected 'get', 'set', 'willSet', 'didSet' or getter body", at: endOfFile
                )
                hasError = true
                break
            }
            guard case .Identifier = t2.kind else {
                break
            }
            index += 1
            switch t2.value {
            case "get":
                guard let t3 = peek else {
                    emitError("expected '=' or '{'", at: endOfFile)
                    hasError = true
                    break _loop
                }
                let body: AST.FunctionDecl.Body
                switch t3.kind {
                case .Separator(.OpenBrace):
                    index += 1
                    var statements: [AST.Statement] = []
                    while let closeToken = peek {
                        if case .Separator(.CloseBrace) = closeToken.kind {
                            break
                        }
                        if let stmt = parseStatement() {
                            statements.append(stmt)
                        }
                    }
                    if let closeToken = peek {
                        if case .Separator(.CloseBrace) = closeToken.kind {
                            index += 1
                        } else {
                            emitError(
                                "expected '}' after getter body, but got \(closeToken.value)",
                                at: closeToken
                            )
                        }
                    } else {
                        emitError("expected '}' after getter body", at: endOfFile)
                    }

                    body = .Block(statements)
                case .Operator(.Assign):
                    index += 1
                    let expr = parseExpression() ?? errorExpression(from: t3, to: t3)
                    body = .Expression(expr)
                default:
                    emitError("expected '=' or '{', but got \(t3.value)", at: t3)
                    hasError = true
                    break _loop
                }
                accessors.append(
                    AST.Accessor(
                        modifiers, attributes, t2, nil, body, kind: .Get,
                        sourceRange: SourceRange(from: t, to: last!, in: buffer)
                    )
                )
            case "set":
                let parameterName: Token?
                if let t3 = peek, case .Separator(.OpenParen) = t3.kind {
                    index += 1
                    if let name = peek {
                        index += 1
                        parameterName = name
                        if name.kind != .Identifier {
                            emitError(
                                "expected identifier after '(', but got '\(name.value)'", at: name
                            )
                        }
                    } else {
                        emitError("expected parameter name", at: endOfFile)
                        hasError = true
                        break _loop
                    }
                    if let t4 = peek {
                        if case .Separator(.CloseParen) = t4.kind {
                            index += 1
                        } else {
                            emitError("expected ')', but got '\(t4.value)'", at: t4)
                        }
                    } else {
                        emitError("expected ')'", at: endOfFile)
                        hasError = true
                        break _loop
                    }
                } else {
                    parameterName = nil
                }
                guard let t3 = peek else {
                    emitError("expected '{'", at: endOfFile)
                    hasError = true
                    break _loop
                }
                guard case .Separator(.OpenBrace) = t3.kind else {
                    emitError("expected '{', but got \(t3.value)", at: t3)
                    hasError = true
                    break _loop
                }
                index += 1
                var statements: [AST.Statement] = []
                while let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        break
                    }
                    if let stmt = parseStatement() {
                        statements.append(stmt)
                    }
                }
                if let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        index += 1
                    } else {
                        emitError(
                            "expected '}' after setter body, but got \(closeToken.value)",
                            at: closeToken
                        )
                    }
                } else {
                    emitError("expected '}' after setter body", at: endOfFile)
                }

                let body: AST.FunctionDecl.Body = .Block(statements)
                accessors.append(
                    AST.Accessor(
                        modifiers, attributes, t2, parameterName, body, kind: .Set,
                        sourceRange: SourceRange(from: t, to: last!, in: buffer)
                    )
                )
            case "willSet":
                let parameterName: Token?
                if let t3 = peek, case .Separator(.OpenParen) = t3.kind {
                    index += 1
                    if let name = peek {
                        index += 1
                        parameterName = name
                        if name.kind != .Identifier {
                            emitError(
                                "expected identifier after '(', but got '\(name.value)'", at: name
                            )
                        }
                    } else {
                        emitError("expected parameter name", at: endOfFile)
                        hasError = true
                        break _loop
                    }
                    if let t4 = peek {
                        if case .Separator(.CloseParen) = t4.kind {
                            index += 1
                        } else {
                            emitError("expected ')', but got '\(t4.value)'", at: t4)
                        }
                    } else {
                        emitError("expected ')'", at: endOfFile)
                        hasError = true
                        break _loop
                    }
                } else {
                    parameterName = nil
                }
                guard let t3 = peek else {
                    emitError("expected '{'", at: endOfFile)
                    hasError = true
                    break _loop
                }
                guard case .Separator(.OpenBrace) = t3.kind else {
                    emitError("expected '{', but got \(t3.value)", at: t3)
                    hasError = true
                    break _loop
                }
                index += 1
                var statements: [AST.Statement] = []
                while let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        break
                    }
                    if let stmt = parseStatement() {
                        statements.append(stmt)
                    }
                }
                if let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        index += 1
                    } else {
                        emitError(
                            "expected '}' after willSet body, but got \(closeToken.value)",
                            at: closeToken
                        )
                    }
                } else {
                    emitError("expected '}' after willSet body", at: endOfFile)
                }
                let body: AST.FunctionDecl.Body = .Block(statements)
                accessors.append(
                    AST.Accessor(
                        modifiers, attributes, t2, parameterName, body, kind: .WillSet,
                        sourceRange: SourceRange(from: t, to: last!, in: buffer)
                    )
                )
            case "didSet":
                let parameterName: Token?
                if let t3 = peek, case .Separator(.OpenParen) = t3.kind {
                    index += 1
                    if let name = peek {
                        index += 1
                        parameterName = name
                        if name.kind != .Identifier {
                            emitError(
                                "expected identifier after '(', but got '\(name.value)'", at: name
                            )
                        }
                    } else {
                        emitError("expected parameter name", at: endOfFile)
                        hasError = true
                        break _loop
                    }
                    if let t4 = peek {
                        if case .Separator(.CloseParen) = t4.kind {
                            index += 1
                        } else {
                            emitError("expected ')', but got '\(t4.value)'", at: t4)
                        }
                    } else {
                        emitError("expected ')'", at: endOfFile)
                        hasError = true
                        break _loop
                    }
                } else {
                    parameterName = nil
                }
                guard let t3 = peek else {
                    emitError("expected '{'", at: endOfFile)
                    hasError = true
                    break _loop
                }
                guard case .Separator(.OpenBrace) = t3.kind else {
                    emitError("expected '{', but got \(t3.value)", at: t3)
                    hasError = true
                    break _loop
                }
                index += 1
                var statements: [AST.Statement] = []
                while let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        break
                    }
                    if let stmt = parseStatement() {
                        statements.append(stmt)
                    }
                }
                if let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        index += 1
                    } else {
                        emitError(
                            "expected '}' after didSet body, but got \(closeToken.value)",
                            at: closeToken
                        )
                    }
                } else {
                    emitError("expected '}' after didSet body", at: endOfFile)
                }
                let body: AST.FunctionDecl.Body = .Block(statements)
                accessors.append(
                    AST.Accessor(
                        modifiers, attributes, t2, parameterName, body, kind: .DidSet,
                        sourceRange: SourceRange(from: t, to: last!, in: buffer)
                    )
                )
            default:
                break _loop
            }
        }
        if !hasError, accessors.isEmpty {
            var statements: [AST.Statement] = []
            while let closeToken = peek {
                if case .Separator(.CloseBrace) = closeToken.kind {
                    break
                }
                if let stmt = parseStatement() {
                    statements.append(stmt)
                }
            }
            if let closeToken = peek {
                if case .Separator(.CloseBrace) = closeToken.kind {
                    index += 1
                } else {
                    emitError(
                        "expected '}' after didSet body, but got \(closeToken.value)",
                        at: closeToken
                    )
                }
            } else {
                emitError("expected '}' after didSet body", at: endOfFile)
            }
            let body: AST.FunctionDecl.Body = .Block(statements)
            accessors.append(
                AST.Accessor(
                    [], [], nil, nil, body, kind: .Get,
                    sourceRange: SourceRange(from: beginToken, to: last!, in: buffer)
                )
            )
        } else {
            if let closeToken = peek {
                if case .Separator(.CloseBrace) = closeToken.kind {
                    index += 1
                } else {
                    emitError(
                        "expected '}' after accessors, but got \(closeToken.value)",
                        at: closeToken
                    )
                }
            } else {
                emitError("expected '}' after accessors", at: endOfFile)
            }
        }
        return accessors
    }

    private func parseReturn() -> AST.Statement {
        let token = next!
        guard let t = peek else {
            return AST.Return(token, nil, sourceRange: token.sourceRange(in: buffer))
        }
        if case .Separator(.SemiColon) = t.kind {
            return AST.Return(token, nil, sourceRange: token.sourceRange(in: buffer))
        } else if token.pos.line != t.pos.line {
            return AST.Return(token, nil, sourceRange: token.sourceRange(in: buffer))
        } else {
            guard let expr = parseExpression() else {
                return AST.Return(token, nil, sourceRange: token.sourceRange(in: buffer))
            }
            return AST.Return(
                token, expr, sourceRange: SourceRange(from: token, to: last!, in: buffer)
            )
        }
    }

    private func parseWhile() -> AST.Statement {
        let token = next!
        let condition =
            parseExpression() ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
        guard let openToken = next else {
            emitError("expected '{' after while condition", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after while condition, but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after while body", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after while body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        return AST.While(
            token, condition, openToken, body, closeToken,
            sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
        )
    }

    private func parseRepeatWhile() -> AST.Statement {
        let token = next!
        guard let openToken = next else {
            emitError("expected '{' after 'repeat", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after 'repeat', but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        guard let closeToken = next else {
            emitError("expected '}' after repeat body", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.CloseBrace) = closeToken.kind else {
            emitError(
                "expected '}' after repeat body, but got \(closeToken.value)",
                at: closeToken
            )
            return errorStatement(from: token, to: closeToken)
        }
        guard let whileToken = peek else {
            emitError("expected 'while' after '}'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Keyword(.While) = whileToken.kind {
            index += 1
        } else {
            emitError(
                "expected 'while' after '}', but got \(whileToken.value)",
                at: whileToken
            )
        }
        let condition =
            parseExpression()
            ?? AST.ErrorExpression(SourceRange(location: locationAfter(whileToken)))
        return AST.RepeatWhile(
            token, openToken, body, closeToken, whileToken, condition,
            sourceRange: SourceRange(from: token, to: whileToken, in: buffer)
        )
    }

    private func parseGuard() -> AST.Statement {
        let token = next!
        let condition =
            parseExpression() ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
        guard let t = next else {
            emitError("expected 'else' after guard condition", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Keyword(.Else) = t.kind else {
            emitError(
                "expected 'else' after guard condition, but got '\(t.value)'",
                at: t
            )
            return errorStatement(from: token, to: t)
        }
        guard let openToken = next else {
            emitError("expected '{' after 'else'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after 'else', but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after guard body", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after guard body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        return AST.Guard(
            token, condition, openToken, body, closeToken,
            sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
        )
    }

    private func parseDefer() -> AST.Statement {
        let token = next!
        guard let openToken = next else {
            emitError("expected '{' after 'defer'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after 'defer', but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after defer body", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after defer body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        return AST.Defer(
            token, openToken, body, closeToken,
            sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
        )
    }

    private func parseBreak() -> AST.Statement {
        let token = next!
        guard let t = peek, token.pos.line == t.pos.line else {
            return AST.Break(token, nil, sourceRange: token.sourceRange(in: buffer))
        }
        if case .Identifier = t.kind {
            index += 1
            return AST.Break(token, t, sourceRange: SourceRange(from: token, to: t, in: buffer))
        } else {
            emitError("expected identifier after 'break', but got '\(t.value)'", at: t)
            return AST.Break(token, nil, sourceRange: token.sourceRange(in: buffer))
        }
    }

    private func parseContinue() -> AST.Statement {
        let token = next!
        guard let t = peek, token.pos.line == t.pos.line else {
            return AST.Continue(token, nil, sourceRange: token.sourceRange(in: buffer))
        }
        if case .Identifier = t.kind {
            index += 1
            return AST.Continue(token, t, sourceRange: SourceRange(from: token, to: t, in: buffer))
        } else {
            emitError("expected identifier after 'continue', but got '\(t.value)'", at: t)
            return AST.Continue(token, nil, sourceRange: token.sourceRange(in: buffer))
        }
    }

    private func parseGoto() -> AST.Statement {
        let token = next!
        guard let t = next else {
            emitError("expected identifier after 'goto'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if t.kind != .Identifier {
            emitError("expected identifier after 'goto', but got '\(t.value)'", at: t)
        }
        return AST.Goto(token, t, sourceRange: SourceRange(from: token, to: t, in: buffer))
    }

    private func parseExpression(excepts: [OperatorKind]? = nil) -> AST.Expression? {
        var ops: [Token] = []
        var operands: [AST.Expression] = []
        var lastIsExpression = false
        while let token = peek {
            if case .Operator(let kind) = token.kind, kind != .Dot {
                if let excepts = excepts, let kind = kind, excepts.contains(kind) {
                    break
                } else {
                    ops.append(token)
                    index += 1
                    lastIsExpression = false
                }
            } else if !lastIsExpression, let expr = parsePrimary(excepts) {
                operands.append(expr)
                lastIsExpression = true
            } else {
                break
            }
        }
        if ops.isEmpty, operands.isEmpty {
            return nil
        }
        if !ops.isEmpty, operands.isEmpty {
            let lastOp = ops.last!
            emitError(
                "expected expression after operator '\(lastOp.value)'",
                at: locationAfter(lastOp)
            )
            return errorExpression(from: ops.first!, to: ops.last!)
        }
        if ops.isEmpty, operands.count == 1 {
            return operands[0]
        }
        let range: SourceRange
        if let firstRange = operands.first?.sourceRange,
            let lastRange = operands.last?.sourceRange
        {
            range = SourceRange(start: firstRange.start, end: lastRange.end)
        } else if let firstOp = ops.first, let lastOp = ops.last {
            range = SourceRange(from: firstOp, to: lastOp, in: buffer)
        } else {
            range = SourceRange(location: endOfFile)
        }
        return AST.SequentialExpression(ops, operands, sourceRange: range)
    }

    private func parsePrimary(_ excepts: [OperatorKind]?) -> AST.Expression? {
        let token = peek!
        var expression: AST.Expression
        switch token.kind {
        case .Identifier:
            index += 1
            expression = AST.Variable(name: token, sourceRange: token.sourceRange(in: buffer))
        case .StringLiteral:
            index += 1
            expression = AST.StringLiteral(token, sourceRange: token.sourceRange(in: buffer))
        case .IntegerLiteral(let value):
            index += 1
            expression = AST.IntegerLiteral(
                token,
                value,
                sourceRange: token.sourceRange(in: buffer)
            )
        case .FloatLiteral(let value):
            index += 1
            expression = AST.FloatLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .CharLiteral(let value):
            index += 1
            expression = AST.CharLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .BooleanLiteral(let value):
            index += 1
            expression = AST.BoolLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .NullLiteral:
            index += 1
            expression = AST.NullLiteral(token, sourceRange: token.sourceRange(in: buffer))
        case .Keyword(let kind):
            switch kind {
            case .SelfKw:
                index += 1
                expression = AST.SelfExpression(token, sourceRange: token.sourceRange(in: buffer))
            case .SelfTypeKw:
                index += 1
                expression = AST.SelfTypeExpression(
                    token,
                    sourceRange: token.sourceRange(in: buffer)
                )
            case .SuperKw:
                index += 1
                expression = AST.SuperExpression(token, sourceRange: token.sourceRange(in: buffer))
            case .If:
                expression = parseIf()
            default:
                return nil
            }
        case .Separator(let kind):
            switch kind {
            case .OpenParen:
                index += 1
                if let t = peek, t.kind == .Separator(.CloseParen) {
                    index += 1
                    expression = AST.VoidLiteral(
                        token, t,
                        sourceRange: SourceRange(from: token, to: t, in: buffer)
                    )
                } else {
                    guard let expr = parseExpression() else {
                        emitError("expected expression after '('", at: locationAfter(token))
                        if let t = peek, case .Separator(.CloseParen) = t.kind {
                            index += 1
                        }
                        return nil
                    }
                    expression = expr
                    if let t = peek {
                        if case .Separator(.CloseParen) = t.kind {
                            index += 1
                        } else {
                            emitError("expected ')' after expression, but got '\(t.value)'", at: t)
                        }
                    } else {
                        emitError("expected ')' after expression", at: token)
                        return expression
                    }
                }
            case .OpenBrace:
                expression = parseClosure()
            default: return nil
            }
        case .Operator(let kind):
            switch kind {
            case .Dot:
                index += 1
                guard let member = next else {
                    emitError("expected member name after '.'", at: endOfFile)
                    return nil
                }
                if member.kind != .Identifier {
                    emitError(
                        "expected identifier after '.', but got '\(member.value)'",
                        at: member
                    )
                }
                expression = AST.ImplicitMemberAccess(
                    token,
                    member,
                    sourceRange: token.sourceRange(in: buffer)
                )
            default:
                return nil
            }
        default: return nil
        }
        _loop: while let t = peek {
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
                        index += 3
                        let base = expression
                        var genericArguments: [AST.Expression] = []
                        while let t4 = peek {
                            if case .Operator(.Greater) = t4.kind {
                                break
                            }
                            if case .Separator(.Comma) = t4.kind {
                                index += 1
                            }
                            if let expr = parseExpression(excepts: [.Greater]) {
                                genericArguments.append(expr)
                            }
                        }
                        var closeToken: Token = token
                        if let t4 = peek, case .Operator(.Greater) = t4.kind {
                            index += 1
                            closeToken = t4
                        } else {
                            emitError("expected '>'", at: t2.sourceRange(in: buffer))
                        }
                        expression = AST.GenericApplication(
                            base, genericArguments,
                            sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
                        )
                    } else {
                        break _loop
                    }
                case .Arrow:
                    expression = parseClosureType(expression, excepts)
                default: break _loop
                }
            case .Operator(let kind):
                switch kind {
                case .Dot:
                    index += 1
                    guard let member = peek else {
                        emitError("expected member name after '.'", at: endOfFile)
                        break _loop
                    }
                    switch member.kind {
                    case .Identifier, .IntegerLiteral:
                        index += 1
                    default:
                        emitError(
                            "expected identifier or integer literal after '.', but got '\(member.value)'",
                            at: member
                        )
                    }
                    expression = AST.MemberAccess(
                        expression, t, member,
                        sourceRange: SourceRange(from: token, to: member, in: buffer)
                    )
                default: break _loop
                }
            default: break _loop
            }
        }
        return expression
    }

    private func parseIf() -> AST.Expression {
        let token = next!
        let condition = parseExpression() ?? errorExpression(from: token, to: token)
        guard let openToken = next else {
            emitError("expected '{' after if condition", at: endOfFile)
            return errorExpression(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after if condition, but got '\(openToken.value)'",
                at: openToken
            )
            return errorExpression(from: token, to: openToken)
        }
        var then: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                then.append(stmt)
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after if body", at: endOfFile)
            return errorExpression(from: token, to: endOfFile)
        }
        var endToken = closeToken
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after if body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        let elseKind: AST.If.ElseKind?
        if let elseToken = peek, case .Keyword(.Else) = elseToken.kind, let t = peek2 {
            index += 1
            switch t.kind {
            case .Keyword(.If):
                if let ifExpression = parseIf() as? AST.If {
                    elseKind = .If(ifExpression)
                    endToken = last!
                } else {
                    elseKind = nil
                }
            case .Separator(.OpenBrace):
                index += 1
                var statements: [AST.Statement] = []
                while let closeToken2 = peek {
                    if case .Separator(.CloseBrace) = closeToken2.kind {
                        break
                    }
                    if let stmt = parseStatement() {
                        statements.append(stmt)
                    }
                }
                guard let closeToken2 = peek else {
                    emitError("expected '}' after if body", at: endOfFile)
                    elseKind = .Block(statements)
                    endToken = last!
                    break
                }
                if case .Separator(.CloseBrace) = closeToken2.kind {
                    index += 1
                } else {
                    emitError(
                        "expected '}' after if body, but got \(closeToken2.value)",
                        at: closeToken2
                    )
                }
                elseKind = .Block(statements)
                endToken = last!
            default:
                elseKind = nil
            }
        } else {
            elseKind = nil
        }
        return AST.If(
            token, condition, then, elseKind,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseClosure() -> AST.Closure {
        let beginToken = next!
        var body: [AST.Statement] = []
        while let t = peek {
            if t.kind == .Separator(.CloseBrace) {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        if let t = next {
            if t.kind != .Separator(.CloseBrace) {
                emitError("expected '}' after closure body, but got '\(t.value)'", at: t)
            }
        } else {
            emitError("expected '}' after closure body", at: endOfFile)
        }
        return AST.Closure(body, sourceRange: SourceRange(from: beginToken, to: last!, in: buffer))
    }

    private func parseClosureType(_ parameterTypes: AST.Expression, _ excepts: [OperatorKind]?)
        -> AST.ClosureType
    {
        let token = next!
        if token.kind != .Separator(.Arrow) {
            emitError(
                "expected '->' after closure type parameters, but got '\(token.value)'",
                at: token
            )
        }
        let returnTypeExpression =
            parseExpression(excepts: excepts)
            ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
        return AST.ClosureType(
            parameterTypes, returnTypeExpression,
            sourceRange: SourceRange(
                start: parameterTypes.sourceRange.start, end: returnTypeExpression.sourceRange.end
            )
        )
    }

    private func parseCall(_ callee: AST.Expression) -> AST.Call {
        index += 1
        var endToken: Token? = nil
        if let t = peek {
            if case .Separator(.CloseParen) = t.kind {
                index += 1
                endToken = t
            } else {
                emitError("expected ')' after call arguments, but got '\(t.value)'", at: t)
                endToken = t
            }
        } else {
            emitError("expected ')' after call arguments", at: endOfFile)
        }
        let range: SourceRange
        if let endToken = endToken {
            range = SourceRange(
                start: callee.sourceRange.start, end: endToken.sourceRange(in: buffer).end
            )
        } else {
            range = callee.sourceRange
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
                    index += 1
                    if let t = peek, case .Separator(.OpenParen) = t.kind {
                        index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(.CloseParen) = t3.kind {
                            index += 1
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
                    index += 1
                    if let t = peek, case .Separator(.OpenParen) = t.kind {
                        index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(.CloseParen) = t3.kind {
                            index += 1
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
                    index += 1
                    if let t = peek, case .Separator(.OpenParen) = t.kind {
                        index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(.CloseParen) = t3.kind {
                            index += 1
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
                    index += 1
                    if let t = peek, case .Separator(.OpenParen) = t.kind {
                        index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(.CloseParen) = t3.kind {
                            index += 1
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
                    index += 1
                    if let t = peek, case .Separator(.OpenParen) = t.kind {
                        index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(.CloseParen) = t3.kind {
                            index += 1
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
                    index += 1
                    if let t = peek, case .Separator(.OpenParen) = t.kind {
                        index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(.CloseParen) = t3.kind {
                            index += 1
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
                    index += 1
                    if let t = peek, case .Separator(.OpenParen) = t.kind {
                        index += 1
                        guard let t2 = peek else {
                            emitError("expected 'set' after '('", at: endOfFile)
                            break _loop
                        }
                        if case .Identifier = t2.kind, t2.value == "set" {
                            index += 1
                        } else {
                            emitError("expected 'set' after '(', but got '\(t2.value)'", at: t2)
                        }
                        guard let t3 = peek else {
                            emitError("expected ')' after 'set'", at: endOfFile)
                            break _loop
                        }
                        if case .Separator(.CloseParen) = t3.kind {
                            index += 1
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
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Abstract,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Final:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Final,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Mutating:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Mutating,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Nonmutating:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Nonmutating,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Convenience:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token, kind: .Convenience,
                            sourceRange: token.sourceRange(in: buffer)
                        ))
                case .Override:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Override,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Lazy:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Lazy,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Weak:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Weak,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Unowned:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Unowned,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Indirect:
                    index += 1
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
            case .Separator(.Sharp):
                guard let t = peek2, case .Separator(.OpenBracket) = t.kind
                else {
                    break _loop
                }
                index += 2
                guard let name = peek else {
                    emitError("expected attribute name after '#['", at: endOfFile)
                    break _loop
                }
                guard case .Identifier = name.kind else {
                    emitError(
                        "expected attribute name after '#[' but got '\(name.value)'", at: name
                    )
                    break _loop
                }
                index += 1
                guard let t2 = peek else {
                    emitError("expected '(' or ']' after attribute name", at: endOfFile)
                    break _loop
                }
                guard case .Separator(let t2Kind) = t2.kind else {
                    emitError(
                        "expected '(' or ']' after attribute name, but got '\(t2.value)'", at: t2
                    )
                    break _loop
                }
                var arguments: [[Token]] = []
                var labeledArguments: [Token: [Token]] = [:]
                if case .OpenParen = t2Kind {
                    index += 1
                    while let t = peek {
                        if case .Separator(.CloseParen) = t.kind { break }
                        index += 1
                        if case .Identifier = t.kind, let t2 = peek,
                            case .Separator(.Colon) = t2.kind
                        {
                            index += 1
                            var args: [Token] = []
                            while let t2 = peek {
                                if case .Separator(.CloseParen) = t2.kind {
                                    break
                                }
                                index += 1
                                if case .Separator(.Comma) = t2.kind {
                                    break
                                }
                                args.append(t2)
                            }
                            labeledArguments[t] = args
                        } else {
                            var args: [Token] = [t]
                            while let t2 = peek {
                                if case .Separator(.CloseParen) = t2.kind {
                                    break
                                }
                                index += 1
                                if case .Separator(.Comma) = t2.kind {
                                    break
                                }
                                args.append(t2)
                            }
                            arguments.append(args)
                        }
                    }
                    if let t = peek {
                        if case .Separator(.CloseParen) = t.kind {
                            index += 1
                        } else {
                            emitError(
                                "expected ')' after attribute arguments, but got '\(t.value)'",
                                at: t
                            )
                        }
                    } else {
                        emitError("expected ')' after attribute arguments", at: endOfFile)
                        break _loop
                    }
                }
                if let t = peek {
                    if case .Separator(.CloseBracket) = t.kind {
                        index += 1
                    } else {
                        emitError(
                            "expected ']' after attribute arguments, but got '\(t.value)'",
                            at: t
                        )
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
                        sourceRange: SourceRange(from: token, to: last!, in: buffer)
                    )
                )
            default:
                break _loop
            }
        }
        return (modifiers, attributes)
    }
}
