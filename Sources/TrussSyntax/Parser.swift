import SwiftBetterDiagnostic
import TrussCore

public final class Parser {
    private let context: Context
    private let packageName: String
    private let lexerResult: LexerResult
    private let source: Source
    private var index: Int = 0
    private var inPatternContext: Bool = false
    private var suppressTrailingClosures: Bool = false
    private var buffer: SourceBuffer { source.stringSourceBuffer }
    public var last: Token? {
        if index - 1 < lexerResult.tokens.count {
            lexerResult.tokens[index - 1]
        } else {
            nil
        }
    }

    public var peek: Token? {
        if index < lexerResult.tokens.count {
            lexerResult.tokens[index]
        } else {
            nil
        }
    }

    public var peek2: Token? {
        if (index + 1) < lexerResult.tokens.count {
            lexerResult.tokens[index + 1]
        } else {
            nil
        }
    }

    public var peek3: Token? {
        if (index + 2) < lexerResult.tokens.count {
            lexerResult.tokens[index + 2]
        } else {
            nil
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

    private func errorToken() -> Token {
        Token(
            value: "<error>", kind: .Unknown,
            pos: Position(pos: 0, line: 0, col: 0, len: 0), id: Id.SourceId(id: 0)
        )
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
        emitError(message, at: token, notes: [])
    }

    private func note(_ message: String, at token: Token) -> Diagnostic {
        Diagnostic(severity: .note, message: message, range: token.sourceRange(in: buffer))
    }

    private func emitError(_ message: String, at token: Token, notes: [Diagnostic]) {
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: .error, message: message,
                range: token.sourceRange(in: buffer),
                notes: notes + token.expansionNotes(in: context)
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
            )
        )
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
            )
        )
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
            case let .Keyword(keywordKind):
                switch keywordKind {
                case .Import: statement = parseImport()
                case .Extern: statement = parseExtern(modifiers, attributes)
                case .TypeAlias: statement = parseTypeAliasDecl(modifiers, attributes)
                case .Module: statement = parseModuleDecl(modifiers, attributes)
                case .PrecedenceGroup: statement = parsePrecedenceGroupDecl(modifiers, attributes)
                case .Struct: statement = parseStructDecl(modifiers, attributes)
                case .Class: statement = parseClassDecl(modifiers, attributes)
                case .Enum: statement = parseEnumDecl(modifiers, attributes)
                case .ProtocolKw: statement = parseProtocolDecl(modifiers, attributes)
                case .Extension: statement = parseExtensionDecl(modifiers, attributes)
                case .Actor: statement = parseActorDecl(modifiers, attributes)
                case .Func: statement = parseFunctionDecl(modifiers, attributes)
                case .Operator: statement = parseOperatorDecl(modifiers, attributes)
                case .Let: statement = parseVariableDecl(modifiers, attributes)
                case .Var: statement = parseVariableDecl(modifiers, attributes)
                default: statement = nil
                }
            case let .Separator(kind):
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
        let programRange = if let f = firstRange, let l = lastRange {
            SourceRange(start: f.start, end: l.end)
        } else {
            SourceRange(location: endOfFile)
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
        case let .Keyword(keywordKind):
            switch keywordKind {
            case .TypeAlias: return parseTypeAliasDecl(modifiers, attributes)
            case .Module: return parseModuleDecl(modifiers, attributes)
            case .PrecedenceGroup: return parsePrecedenceGroupDecl(modifiers, attributes)
            case .Struct: return parseStructDecl(modifiers, attributes)
            case .Class: return parseClassDecl(modifiers, attributes)
            case .Enum: return parseEnumDecl(modifiers, attributes)
            case .ProtocolKw: return parseProtocolDecl(modifiers, attributes)
            case .Actor: return parseActorDecl(modifiers, attributes)
            case .Extension: return parseExtensionDecl(modifiers, attributes)
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Operator: return parseOperatorDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes)
            case .Var: return parseVariableDecl(modifiers, attributes)
            default: return nil
            }
        case let .Separator(kind):
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

        return AST.Import(
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

    private func parseExtern(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let convention = next else {
            emitError("expected calling convention after 'extern'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .StringLiteral = convention.kind else {
            emitError("expected calling convention (string literal) after 'extern'", at: convention)
            return errorStatement(from: token, to: convention)
        }
        if let t = peek {
            let body: AST.ExternDecl.Body
            if t.kind == .Separator(.OpenBrace) {
                index += 1
                var statements: [AST.Statement] = []
                _loop: while peek != nil {
                    let (modifiers, attributes) = parseAnnotations()
                    guard let t3 = peek else {
                        if !modifiers.isEmpty || !attributes.isEmpty {
                            emitError("expected statement", at: endOfFile)
                        }
                        break
                    }
                    if case let .Keyword(kind) = t3.kind {
                        switch kind {
                        case .Let: statements.append(parseVariableDecl(modifiers, attributes))
                        case .Var: statements.append(parseVariableDecl(modifiers, attributes))
                        case .Func: statements.append(parseFunctionDecl(modifiers, attributes))
                        default: break _loop
                        }
                    } else {
                        break _loop
                    }
                }
                if let closeToken = peek {
                    if case .Separator(.CloseBrace) = closeToken.kind {
                        index += 1
                    } else {
                        emitError(
                            "expected '}' after extern body, but got \(closeToken.value)",
                            at: closeToken
                        )
                    }
                } else {
                    emitError("expected '}' after extern body", at: endOfFile)
                }
                body = .Block(statements)
            } else {
                let (modifiers, attributes) = parseAnnotations()
                guard let t3 = peek else {
                    if !modifiers.isEmpty || !attributes.isEmpty {
                        emitError("expected statement", at: endOfFile)
                    }
                    return errorStatement(from: token, to: endOfFile)
                }
                let decl: AST.Decl? = switch t3.kind {
                case .Keyword(.Let): parseVariableDecl(modifiers, attributes) as? AST.Decl
                case .Keyword(.Var): parseVariableDecl(modifiers, attributes) as? AST.Decl
                case .Keyword(.Func): parseFunctionDecl(modifiers, attributes) as? AST.Decl
                default: nil
                }
                if let decl {
                    body = .Declaration(decl)
                } else {
                    emitError(
                        "expected declaration after extern calling convention, but got \(t3.value)",
                        at: t3
                    )
                    return errorStatement(from: token, to: last!)
                }
            }
            return AST.ExternDecl(
                modifiers, attributes, token, convention, body,
                sourceRange: SourceRange(from: token, to: last!, in: buffer)
            )
        } else {
            emitError("expected '{' or declaration after extern calling convention", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
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
        var typeExpression = parseExpression(isTypeContext: true)
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
        var components = [name]
        while let dotToken = peek, case .Operator(.Dot) = dotToken.kind {
            guard let afterDot = peek2 else {
                emitError("expected module name after '.'", at: endOfFile)
                return errorStatement(from: token, to: endOfFile)
            }
            guard case .Identifier = afterDot.kind else {
                emitError(
                    "expected module name after '.', but got '\(afterDot.value)'", at: afterDot
                )
                return errorStatement(from: token, to: afterDot)
            }
            index += 2
            components.append(afterDot)
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
        while peek != nil {
            if let statement = parseBasicStatement() {
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
        var moduleDecl = AST.ModuleDecl(
            modifiers, attributes, token, components.removeLast(), body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
        for component in components.reversed() {
            moduleDecl = AST.ModuleDecl(
                modifiers, attributes, token, component, [moduleDecl],
                sourceRange: SourceRange(from: token, to: endToken, in: buffer)
            )
        }
        return moduleDecl
    }

    private func parseOperatorDecl(
        _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute]
    ) -> AST.Statement {
        let token = next!
        guard let name = next else {
            emitError("expected operator name after 'operator'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Operator = name.kind else {
            emitError(
                "expected operator name after 'operator', but got '\(name.value)'", at: name
            )
            return errorStatement(from: token, to: name)
        }
        guard let kindToken = next else {
            emitError("expected 'infix', 'prefix', or 'postfix' after operator name", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        let kind: AST.OperatorDecl.Kind
        switch kindToken.kind {
        case .Keyword(.Infix):
            kind = .Infix(kindToken)
        case .Keyword(.Prefix):
            kind = .Prefix(kindToken)
        case .Keyword(.Postfix):
            kind = .Postfix(kindToken)
        default:
            emitError(
                "expected 'infix', 'prefix', or 'postfix', but got '\(kindToken.value)'",
                at: kindToken
            )
            return errorStatement(from: token, to: kindToken)
        }
        return AST.OperatorDecl(
            modifiers, attributes, token, name, kind,
            sourceRange: SourceRange(from: token, to: kindToken, in: buffer)
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
                        if case let .BooleanLiteral(v) = t2.kind {
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
                suppressTrailingClosures = true
                if let expr = parseExpression(isTypeContext: true) {
                    conformances.append(expr)
                }
                suppressTrailingClosures = false
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        let whereClause: [AST.WhereRequirement]? = if peek?.kind == .Keyword(.Where) {
            parseWhereClause()
        } else {
            nil
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
            modifiers, attributes, token, name, genericDecl, conformances, whereClause, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseEnumDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        guard let name = next else {
            emitError("expected enum name after 'enum'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError("expected identifier after 'enum', but got '\(name.value)'", at: name)
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
                suppressTrailingClosures = true
                if let expr = parseExpression(isTypeContext: true) {
                    conformances.append(expr)
                }
                suppressTrailingClosures = false
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        let whereClause: [AST.WhereRequirement]? = if peek?.kind == .Keyword(.Where) {
            parseWhereClause()
        } else {
            nil
        }
        guard let openToken = next else {
            emitError("expected '{' in enum type", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' in enum type, but got '\(openToken.value)'",
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
                    "expected '}' after enum body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            endToken = closeToken
        } else {
            emitError("expected '}' after enum body", at: endOfFile)
            endToken = openToken
        }
        return AST.EnumDecl(
            modifiers, attributes, token, name, genericDecl, conformances, whereClause, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseEnumCaseDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        var elements: [AST.EnumCaseDecl.Element] = []
        while true {
            guard let name = next else {
                emitError("expected case name", at: endOfFile)
                return errorStatement(from: token, to: endOfFile)
            }
            guard case .Identifier = name.kind else {
                emitError("expected identifier after 'case', but got '\(name.value)'", at: name)
                return errorStatement(from: token, to: name)
            }
            let elementStart = name
            var associatedValues: [AST.EnumCaseDecl.AssociatedValue] = []
            if let t = peek, case .Separator(.OpenParen) = t.kind {
                index += 1
                while peek != nil {
                    if let t = peek, case .Separator(.CloseParen) = t.kind {
                        index += 1
                        break
                    }
                    let label: Token?
                    let typeExpr: AST.Expression?
                    if let ident = peek, case .Identifier = ident.kind,
                       let colon = peek2, case .Separator(.Colon) = colon.kind
                    {
                        label = ident
                        index += 2
                        typeExpr = parseExpression(isTypeContext: true)
                    } else {
                        label = nil
                        typeExpr = parseExpression(isTypeContext: true)
                    }
                    guard let te = typeExpr else {
                        if let p = peek {
                            emitError("expected type in associated value", at: p)
                        } else {
                            emitError("expected type in associated value", at: endOfFile)
                        }
                        break
                    }
                    associatedValues.append(
                        AST.EnumCaseDecl.AssociatedValue(
                            label: label,
                            typeExpression: te,
                            sourceRange: SourceRange(from: elementStart, to: last!, in: buffer)
                        )
                    )
                    if let comma = peek, case .Separator(.Comma) = comma.kind {
                        index += 1
                    } else {
                        if let t = peek, case .Separator(.CloseParen) = t.kind {
                            index += 1
                        } else if let t = peek {
                            emitError(
                                "expected ')' or ',' in associated values, but got '\(t.value)'",
                                at: t
                            )
                        } else {
                            emitError("expected ')' after associated values", at: endOfFile)
                        }
                        break
                    }
                }
            }
            var rawValue: AST.Expression? = nil
            if let t = peek, case .Operator(.Assign) = t.kind {
                index += 1
                rawValue = parseExpression()
            }
            elements.append(
                AST.EnumCaseDecl.Element(
                    name: name,
                    associatedValues: associatedValues,
                    rawValue: rawValue,
                    sourceRange: SourceRange(from: elementStart, to: last!, in: buffer)
                )
            )
            if let comma = peek, case .Separator(.Comma) = comma.kind {
                index += 1
            } else {
                break
            }
        }
        return AST.EnumCaseDecl(
            modifiers, attributes, token, elements,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
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
                suppressTrailingClosures = true
                if let expr = parseExpression(isTypeContext: true) {
                    inheritanceClauses.append(expr)
                }
                suppressTrailingClosures = false
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        let whereClause: [AST.WhereRequirement]? = if peek?.kind == .Keyword(.Where) {
            parseWhereClause()
        } else {
            nil
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
            modifiers, attributes, token, name, genericDecl, inheritanceClauses, whereClause,
            body,
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
                suppressTrailingClosures = true
                if let expr = parseExpression(isTypeContext: true) {
                    conformances.append(expr)
                }
                suppressTrailingClosures = false
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        let whereClause: [AST.WhereRequirement]? = if peek?.kind == .Keyword(.Where) {
            parseWhereClause()
        } else {
            nil
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
            modifiers, attributes, token, name, genericDecl, conformances, whereClause, body,
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
                suppressTrailingClosures = true
                if let expr = parseExpression(isTypeContext: true) {
                    conformances.append(expr)
                }
                suppressTrailingClosures = false
                if let t3 = peek, case .Separator(.Comma) = t3.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        let whereClause: [AST.WhereRequirement]? = if peek?.kind == .Keyword(.Where) {
            parseWhereClause()
        } else {
            nil
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
            modifiers, attributes, token, name, genericDecl, conformances, whereClause, body,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseSubscriptDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        let genericDecl: AST.GenericDecl? =
            if let t = peek, case .Operator(.Less) = t.kind {
                parseGenericDecl()
            } else {
                nil
            }
        var parameters: [AST.FunctionDecl.Parameter] = []
        if peek?.kind == .Separator(.OpenParen) {
            index += 1
            while let t = peek {
                if t.kind == .Separator(.CloseParen) { break }
                if t.kind == .Separator(.Comma) {
                    index += 1
                    continue
                }
                parameters.append(parseFunctionParameter())
            }
            if peek?.kind == .Separator(.CloseParen) {
                index += 1
            } else {
                if let tok = peek {
                    emitError("expected ')' after subscript parameters", at: tok)
                } else {
                    emitError("expected ')' after subscript parameters", at: endOfFile)
                }
            }
        }
        let throwsClause = parseThrowsClause()
        guard peek?.kind == .Separator(.Arrow) else {
            if let tok = peek {
                emitError("expected '->' after subscript parameters", at: tok)
            } else {
                emitError("expected '->' after subscript parameters", at: endOfFile)
            }
            return errorStatement(from: token, to: last!)
        }
        index += 1
        suppressTrailingClosures = true
        let returnType =
            parseExpression(isTypeContext: true) ?? errorExpression(from: token, to: last!)
        suppressTrailingClosures = false
        var body: [AST.Statement] = []
        if peek?.kind == .Separator(.OpenBrace) {
            index += 1
            while let t = peek {
                if t.kind == .Separator(.CloseBrace) { break }
                if let stmt = parseStatement() {
                    body.append(stmt)
                }
            }
            if peek?.kind == .Separator(.CloseBrace) {
                index += 1
            } else {
                if let tok = peek {
                    emitError("expected '}' after subscript body", at: tok)
                } else {
                    emitError("expected '}' after subscript body", at: endOfFile)
                }
            }
        }
        return AST.SubscriptDecl(
            modifiers, attributes, token, genericDecl, parameters, throwsClause, returnType,
            body,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseAssociatedTypeDecl(
        _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute]
    ) -> AST.Statement {
        let token = next!
        guard let name = peek, name.kind == .Identifier else {
            if let tok = peek {
                emitError("expected identifier after 'associatedtype'", at: tok)
            } else {
                emitError("expected identifier after 'associatedtype'", at: endOfFile)
            }
            return errorStatement(from: token, to: peek ?? token)
        }
        index += 1
        var constraint: AST.Expression?
        if peek?.kind == .Separator(.Colon) {
            index += 1
            constraint = parseExpression(isTypeContext: true)
        }
        var whereClause: [AST.WhereRequirement]?
        if peek?.kind == .Keyword(.Where) {
            whereClause = parseWhereClause()
        }
        return AST.AssociatedTypeDecl(
            modifiers, attributes, token, name, constraint, whereClause,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseWhereClause() -> [AST.WhereRequirement] {
        index += 1
        var requirements: [AST.WhereRequirement] = []
        while let t = peek {
            suppressTrailingClosures = true
            let left =
                parseExpression(excepts: [.Equal], isTypeContext: true)
                    ?? errorExpression(from: t, to: t)
            suppressTrailingClosures = false
            let op = peek
            if op == nil {
                emitError("expected ':' or '==' in where clause", at: endOfFile)
                break
            }
            switch op!.kind {
            case .Separator(.Colon):
                index += 1
                suppressTrailingClosures = true
                let right =
                    parseExpression(isTypeContext: true) ?? errorExpression(from: op!, to: op!)
                suppressTrailingClosures = false
                requirements.append(
                    AST.WhereRequirement(left, .conformance(right))
                )
            case .Operator(.Equal):
                index += 1
                suppressTrailingClosures = true
                let right =
                    parseExpression(isTypeContext: true) ?? errorExpression(from: op!, to: op!)
                suppressTrailingClosures = false
                requirements.append(
                    AST.WhereRequirement(left, .equality(right))
                )
            default:
                emitError(
                    "expected ':' or '==' in where clause, but got '\(op!.value)'",
                    at: op!
                )
            }
            if peek?.kind == .Separator(.Comma) {
                index += 1
            } else {
                break
            }
        }
        return requirements
    }

    private func parseExtensionDecl(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute])
        -> AST.Statement
    {
        let token = next!
        suppressTrailingClosures = true
        let base =
            parseExpression(excepts: [.Less], isTypeContext: true)
                ?? errorExpression(from: token, to: token)
        suppressTrailingClosures = false
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
                suppressTrailingClosures = true
                if let expr = parseExpression(isTypeContext: true) {
                    conformances.append(expr)
                }
                suppressTrailingClosures = false
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
            if t.kind == .Operator(.Greater) {
                break
            }
            let eachToken: Token?
            var name: Token
            if t.kind == .Keyword(.Each) {
                eachToken = t
                index += 1
                if let n = next {
                    name = n
                    if n.kind != .Identifier {
                        emitError(
                            "expected identifier after 'each', but got '\(n.value)'",
                            at: n
                        )
                    }
                } else {
                    emitError("expected identifier after 'each'", at: endOfFile)
                    break
                }
            } else if t.kind == .Identifier {
                eachToken = nil
                name = t
                index += 1
            } else if t.kind == .Separator(.Comma) {
                index += 1
                continue
            } else {
                emitError(
                    "expected generic parameter name, but got '\(t.value)'",
                    at: t
                )
                index += 1
                continue
            }
            let constraint: AST.Expression?
            if let t2 = peek, case .Separator(.Colon) = t2.kind {
                index += 1
                constraint = parseExpression(excepts: [.Greater], isTypeContext: true)
            } else {
                constraint = nil
            }
            generics.append(
                AST.GenericParameter(
                    eachToken, name, constraint,
                    sourceRange: SourceRange(from: t, to: last!, in: buffer)
                )
            )
            if peek?.kind == .Separator(.Comma) {
                index += 1
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

    private func parseTypeBodyStatement(isProtocolContext: Bool = false) -> AST.Statement? {
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
        case let .Keyword(kind):
            switch kind {
            case .TypeAlias: return parseTypeAliasDecl(modifiers, attributes)
            case .PrecedenceGroup: return parsePrecedenceGroupDecl(modifiers, attributes)
            case .Struct: return parseStructDecl(modifiers, attributes)
            case .Class: return parseClassDecl(modifiers, attributes)
            case .Enum: return parseEnumDecl(modifiers, attributes)
            case .Case: return parseEnumCaseDecl(modifiers, attributes)
            case .ProtocolKw: return parseProtocolDecl(modifiers, attributes)
            case .Actor: return parseActorDecl(modifiers, attributes)
            case .Extension: return parseExtensionDecl(modifiers, attributes)
            case .Init: return parseInitDecl(modifiers, attributes)
            case .Deinit: return parseDeinitDecl(modifiers, attributes)
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Subscript: return parseSubscriptDecl(modifiers, attributes)
            case .AssociatedType: return parseAssociatedTypeDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes)
            case .Var: return parseVariableDecl(modifiers, attributes)
            default:
                index += 1
                emitError("expected a statement, but got \(token.value)", at: token)
                return errorStatement(from: startToken ?? token, to: token)
            }
        case let .Separator(kind):
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
        } else if let t = peek, t.kind == .Operator(.Not) {
            index += 1
            optionalToken = t
        } else {
            optionalToken = nil
        }
        let genericDecl: AST.GenericDecl? =
            if let t = peek, case .Operator(.Less) = t.kind {
                parseGenericDecl()
            } else {
                nil
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
        var parameters: [AST.FunctionDecl.Parameter] = []
        if let t2 = peek, case .Separator(.CloseParen) = t2.kind {
            index += 1
        } else {
            _paramLoop: while true {
                let param = parseFunctionParameter()
                parameters.append(param)
                if let comma = peek, case .Separator(.Comma) = comma.kind {
                    index += 1
                    if let cp = peek, case .Separator(.CloseParen) = cp.kind {
                        break _paramLoop
                    }
                } else {
                    break _paramLoop
                }
            }
            if let t = peek, case .Separator(.CloseParen) = t.kind {
                index += 1
            } else if let t = peek {
                emitError(
                    "expected ')' after initializer parameters, but got '\(t.value)'", at: t
                )
            } else {
                emitError("expected ')' after initializer parameters", at: endOfFile)
            }
        }
        let throwsClause = parseThrowsClause()
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
            } else {
                break
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
            modifiers, attributes, token, optionalToken, genericDecl, parameters,
            throwsClause, body,
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
            } else {
                break
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
        if let labelToken = peek, case .Identifier = labelToken.kind,
           let colonToken = peek2, case .Separator(.Colon) = colonToken.kind,
           !(peek3?.kind == .Separator(.Colon))
        {
            index += 2
            guard let body = parseStatement() else {
                emitError("expected statement after label '\(labelToken.value):'", at: endOfFile)
                return errorStatement(from: labelToken, to: endOfFile)
            }
            return AST.LabeledStatement(
                labelToken, body,
                sourceRange: body.sourceRange
            )
        }
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
        case let .Keyword(kind):
            switch kind {
            case .Func: return parseFunctionDecl(modifiers, attributes)
            case .Operator: return parseOperatorDecl(modifiers, attributes)
            case .Let: return parseVariableDecl(modifiers, attributes, inFunctionContext: true)
            case .Var: return parseVariableDecl(modifiers, attributes, inFunctionContext: true)
            case .Return: return parseReturn()
            case .Throw: return parseThrow()
            case .While: return parseWhile()
            case .Repeat: return parseRepeatWhile()
            case .Guard: return parseGuard()
            case .For: return parseFor()
            case .Defer: return parseDefer()
            case .Asm: return parseAsm()
            case .Break: return parseBreak()
            case .Continue: return parseContinue()
            case .Goto: return parseGoto()
            default:
                let savedIndex = index
                if let expr = parseExpression() {
                    return AST.ExpressionStatement(expr)
                }
                if index == savedIndex {
                    index += 1
                    emitError("expected a statement, but got \(token.value)", at: token)
                }
                return errorStatement(from: startToken ?? token, to: last ?? token)
            }
        case let .Separator(kind):
            switch kind {
            case .SemiColon:
                index += 1
                return AST.EmptyStatement(token, sourceRange: token.sourceRange(in: buffer))
            default:
                let savedIndex = index
                if let expr = parseExpression() {
                    return AST.ExpressionStatement(expr)
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
                return AST.ExpressionStatement(expr)
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
        let token = next!
        guard let name = next else {
            emitError("expected function name or operator after 'func'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if name.kind != .Identifier {
            if case .Operator = name.kind {
                // Do nothing
            } else {
                emitError(
                    "expected identifier or operator after 'func', but got '\(name.value)'",
                    at: name
                )
            }
        }
        let genericDecl: AST.GenericDecl? =
            if let t = peek, case .Operator(.Less) = t.kind {
                parseGenericDecl()
            } else {
                nil
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
        var parameters: [AST.FunctionDecl.Parameter] = []
        var varargToken: Token? = nil
        if let t2 = peek, case .Separator(.CloseParen) = t2.kind {
            index += 1
        } else {
            _paramLoop: while true {
                if let t = peek, case .Operator(.DotDotDot) = t.kind {
                    index += 1
                    varargToken = t
                    break _paramLoop
                }
                let param = parseFunctionParameter()
                parameters.append(param)
                if let comma = peek, case .Separator(.Comma) = comma.kind {
                    index += 1
                    if let cp = peek, case .Separator(.CloseParen) = cp.kind {
                        break _paramLoop
                    }
                } else {
                    break _paramLoop
                }
            }
            if let t = peek, case .Separator(.CloseParen) = t.kind {
                index += 1
            } else if let t = peek {
                emitError("expected ')' after function parameters, but got '\(t.value)'", at: t)
            } else {
                emitError("expected ')' after function parameters", at: endOfFile)
            }
        }
        let throwsClause = parseThrowsClause()
        let returnTypeExpression: AST.Expression?
        if let t = peek, case .Separator(.Arrow) = t.kind {
            index += 1
            suppressTrailingClosures = true
            returnTypeExpression = parseExpression(excepts: [.Assign], isTypeContext: true)
            suppressTrailingClosures = false
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
                    } else {
                        break
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
            modifiers, attributes, token, name, genericDecl, parameters, varargToken,
            throwsClause, returnTypeExpression, body,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseThrowsClause() -> AST.ThrowsClause? {
        guard let token = peek, case .Keyword(.Throws) = token.kind else {
            return nil
        }
        index += 1
        var types: [AST.Expression]?
        var endToken = token
        if let t = peek, case .Separator(.OpenParen) = t.kind {
            index += 1
            var collected: [AST.Expression] = []
            while let t = peek {
                if case .Separator(.CloseParen) = t.kind {
                    break
                }
                if case .Separator(.Comma) = t.kind {
                    index += 1
                    continue
                }
                if let typeExpr = parseExpression() {
                    collected.append(typeExpr)
                } else {
                    break
                }
            }
            if let t = peek {
                if case .Separator(.CloseParen) = t.kind {
                    index += 1
                    endToken = t
                } else {
                    emitError("expected ')' after thrown types, but got '\(t.value)'", at: t)
                    endToken = t
                }
            } else {
                emitError("expected ')' after thrown types", at: endOfFile)
            }
            types = collected
        }
        return AST.ThrowsClause(
            token, types,
            sourceRange: SourceRange(from: token, to: endToken, in: buffer)
        )
    }

    private func parseFunctionParameter() -> AST.FunctionDecl.Parameter {
        let startToken = peek!
        guard let first = next else {
            emitError("expected parameter", at: endOfFile)
            return AST.FunctionDecl.Parameter(
                label: nil, name: errorToken(), type: nil, defaultValue: nil,
                sourceRange: SourceRange(location: endOfFile)
            )
        }
        guard case .Identifier = first.kind else {
            emitError("expected identifier in parameter, but got '\(first.value)'", at: first)
            return AST.FunctionDecl.Parameter(
                label: nil, name: first, type: nil, defaultValue: nil,
                sourceRange: first.sourceRange(in: buffer)
            )
        }
        var label: Token? = first
        var name: Token = first
        if first.value == "_" {
            label = nil
            if let second = peek, case .Identifier = second.kind {
                index += 1
                name = second
            }
        } else if let second = peek, case .Identifier = second.kind {
            index += 1
            name = second
        }
        var type: AST.Expression? = nil
        if let colon = peek, case .Separator(.Colon) = colon.kind {
            index += 1
            type = parseExpression(excepts: [.Assign], isTypeContext: true)
        } else if let t = peek {
            emitError("expected ':' after parameter name, but got '\(t.value)'", at: t)
        } else {
            emitError("expected ':' after parameter name", at: endOfFile)
        }
        var defaultValue: AST.Expression? = nil
        if let assign = peek, case .Operator(.Assign) = assign.kind {
            index += 1
            defaultValue = parseExpression()
        }
        let endToken = last ?? first
        return AST.FunctionDecl.Parameter(
            label: label, name: name, type: type, defaultValue: defaultValue,
            sourceRange: SourceRange(from: startToken, to: endToken, in: buffer)
        )
    }

    private func parseVariableDecl(
        _ modifiers: [AST.Modifier], _ attributes: [AST.Attribute], inFunctionContext: Bool = false
    )
        -> AST.Statement
    {
        let token = next!
        let internalToken: Token?
        if token.kind == .Keyword(.Var), peek?.kind == .Separator(.OpenParen),
           peek2?.kind == .Keyword(.Internal),
           peek3?.kind == .Separator(.CloseParen)
        {
            internalToken = peek2
            index += 3
        } else {
            internalToken = nil
        }
        guard let name = next else {
            emitError("expected variable name", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        let typeExpression: AST.Expression?
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            suppressTrailingClosures = true
            typeExpression = parseExpression(excepts: [.Assign], isTypeContext: true)
            suppressTrailingClosures = false
        } else {
            typeExpression = nil
        }
        let initializer: AST.Expression?
        if let t = peek, case .Operator(.Assign) = t.kind {
            index += 1
            suppressTrailingClosures = true
            initializer = parseExpression()
            suppressTrailingClosures = false
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
            if let initializer, hasGet || hasSet {
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
                            ),
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
            modifiers, attributes, token, internalToken, name, typeExpression, initializer,
            accessors, sourceRange: SourceRange(from: token, to: last!, in: buffer)
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
                        } else {
                            break
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
                    } else {
                        break
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
                    } else {
                        break
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
                    } else {
                        break
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
                } else {
                    break
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

    private func parseThrow() -> AST.Statement {
        let token = next!
        guard let expr = parseExpression() else {
            emitError("expected expression after 'throw'", at: locationAfter(token))
            return errorStatement(from: token, to: locationAfter(token))
        }
        return AST.Throw(
            token, expr, sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseFor() -> AST.Statement {
        let token = next!
        var asyncToken: Token? = nil
        if let t = peek, t.kind == .Keyword(.Await) {
            index += 1
            asyncToken = t
        }
        var caseToken: Token? = nil
        if let t = peek, t.kind == .Keyword(.Case) {
            index += 1
            caseToken = t
        }
        inPatternContext = true
        var pattern =
            parseExpression(excepts: [.Assign])
                ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
        inPatternContext = false
        if let eq = peek, case .Operator(.Assign) = eq.kind {
            index += 1
            suppressTrailingClosures = true
            let subject =
                parseExpression()
                    ?? AST.ErrorExpression(SourceRange(location: locationAfter(eq)))
            suppressTrailingClosures = false
            pattern = AST.CaseMatch(
                caseToken ?? token, pattern, subject,
                sourceRange: SourceRange(
                    start: pattern.sourceRange.start, end: subject.sourceRange.end
                )
            )
        }
        guard let inToken = peek,
              case .Identifier = inToken.kind,
              inToken.value == "in"
        else {
            emitError(
                "expected 'in' after for pattern",
                at: SourceRange(from: token, to: last ?? token, in: buffer)
            )
            return errorStatement(from: token, to: last ?? token)
        }
        index += 1
        suppressTrailingClosures = true
        let sequence =
            parseExpression()
                ?? AST.ErrorExpression(SourceRange(location: locationAfter(inToken)))
        suppressTrailingClosures = false
        guard let openToken = next else {
            emitError("expected '{' after for-in sequence", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after for-in sequence, but got '\(openToken.value)'",
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
            } else {
                break
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after for body", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after for body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        return AST.For(
            token, asyncToken, pattern, inToken, sequence, openToken, body, closeToken,
            sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
        )
    }

    private func parseWhile() -> AST.Statement {
        let token = next!
        let condition =
            parseExpression(isCondition: true)
                ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
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
            } else {
                break
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
            } else {
                break
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
            parseExpression(isCondition: true)
                ?? AST.ErrorExpression(SourceRange(location: locationAfter(whileToken)))
        return AST.RepeatWhile(
            token, openToken, body, closeToken, whileToken, condition,
            sourceRange: SourceRange(from: token, to: whileToken, in: buffer)
        )
    }

    private func parseGuard() -> AST.Statement {
        let token = next!
        let condition =
            parseExpression(isCondition: true)
                ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
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
            } else {
                break
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
            } else {
                break
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

    private func parseAsm() -> AST.Statement {
        let token = next!
        guard let openToken = next else {
            emitError("expected '{' after 'asm'", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after 'asm', but got '\(openToken.value)'",
                at: openToken
            )
            return errorStatement(from: token, to: openToken)
        }
        var templates: [AST.StringLiteral] = []
        while let t = peek {
            guard case .StringLiteral = t.kind else { break }
            if t.isUnterminated {
                emitError("asm template must not contain string interpolation", at: t)
                index += 1
                break
            }
            index += 1
            templates.append(AST.StringLiteral(t, sourceRange: t.sourceRange(in: buffer)))
        }
        var bindings: [AST.Asm.Binding] = []
        if case .Separator(.Colon)? = peek?.kind {
            index += 1
            while let name = peek, case .Identifier = name.kind {
                index += 1
                guard let eq = peek, case .Operator(.Assign) = eq.kind else {
                    emitError("expected '=' after asm operand name, but got '\(peek?.value ?? "")'", at: peek ?? token)
                    skipAsmUntilSyncPoint()
                    break
                }
                index += 1
                guard let kind = peek, case .Identifier = kind.kind else {
                    emitError("expected operand kind after '=', but got '\(peek?.value ?? "")'", at: peek ?? token)
                    skipAsmUntilSyncPoint()
                    break
                }
                index += 1
                guard let openParen = peek, case .Separator(.OpenParen) = openParen.kind else {
                    emitError("expected '(' after asm operand kind, but got '\(peek?.value ?? "")'", at: peek ?? token)
                    skipAsmUntilSyncPoint()
                    break
                }
                index += 1
                guard let constraint = peek, case .Identifier = constraint.kind else {
                    emitError("expected constraint after '(', but got '\(peek?.value ?? "")'", at: peek ?? token)
                    skipAsmUntilSyncPoint()
                    break
                }
                index += 1
                guard let closeParen = peek, case .Separator(.CloseParen) = closeParen.kind else {
                    emitError("expected ')' after asm constraint, but got '\(peek?.value ?? "")'", at: peek ?? token)
                    skipAsmUntilSyncPoint()
                    break
                }
                index += 1
                var local: Token? = nil
                if let t = peek, case .Identifier = t.kind {
                    index += 1
                    local = t
                }
                bindings.append(
                    AST.Asm.Binding(
                        name, kind, constraint, local,
                        sourceRange: SourceRange(from: name, to: local ?? closeParen, in: buffer)
                    )
                )
                if let t = peek, case .Separator(.Comma) = t.kind {
                    index += 1
                } else {
                    break
                }
            }
        }
        var options: [Token] = []
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            while let option = peek {
                if case .Separator(.CloseBrace) = option.kind { break }
                guard case .Identifier = option.kind else {
                    emitError("expected asm option, but got '\(option.value)'", at: option)
                    skipAsmUntilSyncPoint()
                    break
                }
                index += 1
                options.append(option)
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after asm body", at: endOfFile)
            return errorStatement(from: token, to: endOfFile)
        }
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after asm body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        return AST.Asm(
            token, openToken, templates, bindings, options, closeToken,
            sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
        )
    }

    private func skipAsmUntilSyncPoint() {
        while let t = peek,
              t.kind != .Separator(.CloseBrace),
              t.kind != .Separator(.Comma),
              t.kind != .Separator(.Colon)
        {
            index += 1
        }
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

    private func parseExpression(
        excepts: [OperatorKind]? = nil, isCondition: Bool = false, isTypeContext: Bool = false
    ) -> AST.Expression? {
        var ops: [Token] = []
        var operands: [AST.Expression] = []
        var lastIsExpression = false
        var angleDepth = 0
        var justClosedAngle = false
        _loop: while let token = peek {
            switch token.kind {
            case .Separator(.OpenParen) where lastIsExpression:
                angleDepth = 0
                justClosedAngle = false
                let callee = operands.removeLast()
                let callResult = parseCall(callee)
                let postfixed = parsePostfix(callResult, excepts: excepts)
                operands.append(postfixed)
                lastIsExpression = true
            case .Separator(.OpenParen) where justClosedAngle:
                justClosedAngle = false
                let range = if let firstRange = operands.first?.sourceRange,
                               let lastRange = operands.last?.sourceRange
                {
                    SourceRange(start: firstRange.start, end: lastRange.end)
                } else {
                    SourceRange(location: endOfFile)
                }
                let callee = AST.SequentialExpression(ops, operands, sourceRange: range)
                ops = []
                operands = []
                let callResult = parseCall(callee)
                let postfixed = parsePostfix(callResult, excepts: excepts)
                operands.append(postfixed)
                lastIsExpression = true
            case .Separator(.OpenBracket) where lastIsExpression:
                angleDepth = 0
                justClosedAngle = false
                let base = operands.removeLast()
                let subscriptResult = parseSubscript(base)
                let postfixed = parsePostfix(subscriptResult, excepts: excepts)
                operands.append(postfixed)
                lastIsExpression = true
            case .Operator(.Dot) where lastIsExpression,
                 .Operator(.QuestionMarkDot) where lastIsExpression:
                index += 1
                guard let member = peek else {
                    emitError("expected member name after '\(token.value)'", at: endOfFile)
                    break _loop
                }
                switch member.kind {
                case .Identifier, .IntegerLiteral:
                    index += 1
                default:
                    emitError(
                        "expected identifier or integer literal after '\(token.value)', but got '\(member.value)'",
                        at: member
                    )
                }
                let base = operands.removeLast()
                let isOpt = token.kind == .Operator(.QuestionMarkDot)
                let memberAccess = AST.MemberAccess(
                    base, token, member, isOptional: isOpt,
                    sourceRange: SourceRange(
                        start: base.sourceRange.start,
                        end: member.sourceRange(in: buffer).end
                    )
                )
                let postfixed = parsePostfix(memberAccess, excepts: excepts)
                operands.append(postfixed)
                lastIsExpression = true
                justClosedAngle = false
            case .Operator(.Dot) where justClosedAngle,
                 .Operator(.QuestionMarkDot) where justClosedAngle:
                justClosedAngle = false
                let range = if let firstRange = operands.first?.sourceRange,
                               let lastRange = operands.last?.sourceRange
                {
                    SourceRange(start: firstRange.start, end: lastRange.end)
                } else {
                    SourceRange(location: endOfFile)
                }
                let base = AST.SequentialExpression(ops, operands, sourceRange: range)
                ops = []
                operands = []
                index += 1
                guard let member = peek else {
                    emitError("expected member name after '\(token.value)'", at: endOfFile)
                    break _loop
                }
                switch member.kind {
                case .Identifier, .IntegerLiteral:
                    index += 1
                default:
                    emitError(
                        "expected identifier or integer literal after '\(token.value)', but got '\(member.value)'",
                        at: member
                    )
                }
                let isOpt = token.kind == .Operator(.QuestionMarkDot)
                let memberAccess = AST.MemberAccess(
                    base, token, member, isOptional: isOpt,
                    sourceRange: SourceRange(
                        start: base.sourceRange.start,
                        end: member.sourceRange(in: buffer).end
                    )
                )
                let postfixed = parsePostfix(memberAccess, excepts: excepts)
                operands.append(postfixed)
                lastIsExpression = true
            case .Separator(.Comma) where angleDepth > 0:
                ops.append(token)
                index += 1
                lastIsExpression = false
                justClosedAngle = false
            case .Operator(.QuestionMark) where lastIsExpression:
                let base = operands.removeLast()
                let optional = AST.OptionalType(
                    base, token,
                    sourceRange: SourceRange(
                        start: base.sourceRange.start,
                        end: token.sourceRange(in: buffer).end
                    )
                )
                let postfixed = parsePostfix(optional, excepts: excepts)
                operands.append(postfixed)
                index += 1
                lastIsExpression = true
            case .Keyword(.As) where lastIsExpression && !suppressTrailingClosures,
                 .Keyword(.Is) where lastIsExpression && !suppressTrailingClosures:
                let left = operands.removeLast()
                index += 1
                let kind: AST.CastExpression.Kind
                if token.kind == .Keyword(.Is) {
                    kind = .Is
                } else if peek?.kind == .Operator(.QuestionMark) {
                    kind = .AsQuestion
                    index += 1
                } else if peek?.kind == .Operator(.Not) {
                    kind = .AsExclamation
                    index += 1
                } else {
                    kind = .As
                }
                suppressTrailingClosures = true
                let right =
                    parseExpression(excepts: excepts, isTypeContext: true)
                        ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
                suppressTrailingClosures = false
                let result: AST.Expression = if inPatternContext, kind == .As {
                    AST.AsPattern(
                        left, token, right,
                        sourceRange: SourceRange(
                            start: left.sourceRange.start,
                            end: right.sourceRange.end
                        )
                    )
                } else {
                    AST.CastExpression(
                        left, token, right, kind,
                        sourceRange: SourceRange(
                            start: left.sourceRange.start,
                            end: right.sourceRange.end
                        )
                    )
                }
                let postfixed = parsePostfix(result, excepts: excepts)
                operands.append(postfixed)
                lastIsExpression = true
            case .Operator(.Dollar) where !lastIsExpression:
                if let expr = parsePrimary(
                    excepts, isCondition: isCondition, isTypeContext: isTypeContext
                ) {
                    operands.append(expr)
                    lastIsExpression = true
                } else {
                    break _loop
                }
            case .Operator(.Backslash) where !lastIsExpression:
                if let expr = parsePrimary(
                    excepts, isCondition: isCondition, isTypeContext: isTypeContext
                ) {
                    operands.append(expr)
                    lastIsExpression = true
                    justClosedAngle = false
                } else {
                    break _loop
                }
            case .Separator(.OpenBrace)
                where lastIsExpression && !isCondition && !suppressTrailingClosures:
                angleDepth = 0
                justClosedAngle = false
                let expr = operands.removeLast()
                let callee: AST.Expression
                let args: [AST.LabeledArgument]
                if let existingCall = expr as? AST.Call {
                    callee = existingCall.callee
                    args = existingCall.arguments
                } else {
                    callee = expr
                    args = []
                }
                var trailing: [(Token?, AST.Closure)] = []
                while true {
                    var label: Token?
                    if let t = peek, case .Identifier = t.kind,
                       let c = peek2, case .Separator(.Colon) = c.kind,
                       let b = peek3, case .Separator(.OpenBrace) = b.kind
                    {
                        label = t
                        index += 2
                    }
                    guard peek?.kind == .Separator(.OpenBrace) else { break }
                    let closure = parseClosure()
                    trailing.append((label, closure))
                }
                let endToken = trailing.last?.1.sourceRange.end ?? expr.sourceRange.end
                let range = SourceRange(
                    start: expr.sourceRange.start, end: endToken
                )
                let call = AST.Call(
                    callee: callee, arguments: args, trailingClosures: trailing,
                    sourceRange: range
                )
                let postfixed = parsePostfix(call, excepts: excepts)
                operands.append(postfixed)
                lastIsExpression = true
            case .Operator(.DotDotDot) where lastIsExpression && isTypeContext:
                let base = operands.removeLast()
                let variadic = AST.VariadicType(
                    base, token,
                    sourceRange: SourceRange(
                        start: base.sourceRange.start,
                        end: token.sourceRange(in: buffer).end
                    )
                )
                let postfixed = parsePostfix(variadic, excepts: excepts)
                operands.append(postfixed)
                index += 1
                lastIsExpression = true
                justClosedAngle = false
            case let .Operator(kind) where kind != .Dot:
                if let excepts, let kind, excepts.contains(kind) {
                    break _loop
                }
                ops.append(token)
                index += 1
                lastIsExpression = false
                justClosedAngle = false
                if let kind {
                    switch kind {
                    case .Less:
                        angleDepth += 1
                    case .Greater:
                        let prev = angleDepth
                        angleDepth = max(0, angleDepth - 1)
                        if prev > 0, angleDepth == 0 { justClosedAngle = true }
                    case .RightShift:
                        let prev = angleDepth
                        angleDepth = max(0, angleDepth - 2)
                        if prev > 0, angleDepth == 0 { justClosedAngle = true }
                    case .GreaterEqual:
                        angleDepth = max(0, angleDepth - 1)
                    case .RightShiftAssign:
                        angleDepth = max(0, angleDepth - 2)
                    case .RightShiftLogical:
                        let prev = angleDepth
                        angleDepth = max(0, angleDepth - 3)
                        if prev > 0, angleDepth == 0 { justClosedAngle = true }
                    case .RightShiftLogicalAssign:
                        angleDepth = max(0, angleDepth - 3)
                    default:
                        break
                    }
                }
            default:
                if !lastIsExpression,
                   let expr = parsePrimary(
                       excepts, isCondition: isCondition, isTypeContext: isTypeContext
                   )
                {
                    operands.append(expr)
                    lastIsExpression = true
                    justClosedAngle = false
                } else {
                    break _loop
                }
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
        let range = if let firstRange = operands.first?.sourceRange,
                       let lastRange = operands.last?.sourceRange
        {
            SourceRange(start: firstRange.start, end: lastRange.end)
        } else if let firstOp = ops.first, let lastOp = ops.last {
            SourceRange(from: firstOp, to: lastOp, in: buffer)
        } else {
            SourceRange(location: endOfFile)
        }
        return AST.SequentialExpression(ops, operands, sourceRange: range)
    }

    private func parsePrimary(
        _ excepts: [OperatorKind]?, isCondition: Bool = false, isTypeContext: Bool = false
    )
        -> AST.Expression?
    {
        let token = peek!
        var expression: AST.Expression
        switch token.kind {
        case .Identifier:
            index += 1
            if inPatternContext, token.value == "_" {
                expression = AST.WildcardPattern(
                    token, sourceRange: token.sourceRange(in: buffer)
                )
                if let at = peek, case .Operator(.At) = at.kind {
                    index += 1
                    expression =
                        parseExpression(excepts: excepts)
                            ?? errorExpression(from: at, to: at)
                }
            } else {
                expression = AST.Variable(name: token, sourceRange: token.sourceRange(in: buffer))
            }
        case .StringLiteral:
            index += 1
            if token.isUnterminated {
                expression = parseStringInterpolation(token)
            } else {
                expression = AST.StringLiteral(
                    token, sourceRange: token.sourceRange(in: buffer)
                )
            }
        case let .IntegerLiteral(value):
            index += 1
            expression = AST.IntegerLiteral(
                token,
                value,
                sourceRange: token.sourceRange(in: buffer)
            )
        case let .FloatLiteral(value):
            index += 1
            expression = AST.FloatLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case let .CharLiteral(value):
            index += 1
            expression = AST.CharLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case let .BooleanLiteral(value):
            index += 1
            expression = AST.BoolLiteral(token, value, sourceRange: token.sourceRange(in: buffer))
        case .NullLiteral:
            index += 1
            expression = AST.NullLiteral(token, sourceRange: token.sourceRange(in: buffer))
        case let .Keyword(kind):
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
            case .Do:
                expression = parseDo()
            case .Match:
                expression = parseMatch()
            case .Let, .Var:
                if isCondition {
                    expression = parseOptionalBinding(token)
                } else if inPatternContext {
                    index += 1
                    guard let name = next else {
                        emitError("expected identifier after '\(token.value)'", at: endOfFile)
                        return errorExpression(from: token, to: endOfFile)
                    }
                    guard case .Identifier = name.kind else {
                        emitError(
                            "expected identifier after '\(token.value)', but got '\(name.value)'",
                            at: name
                        )
                        return errorExpression(from: token, to: name)
                    }
                    var typeExpression: AST.Expression? = nil
                    if let colon = peek, case .Separator(.Colon) = colon.kind {
                        index += 1
                        typeExpression =
                            parseExpression(excepts: [.Assign, .At])
                                ?? errorExpression(from: colon, to: colon)
                    }
                    var subpattern: AST.Expression? = nil
                    if let at = peek, case .Operator(.At) = at.kind {
                        index += 1
                        subpattern =
                            parseExpression(excepts: excepts)
                                ?? errorExpression(from: at, to: at)
                    }
                    let endToken =
                        subpattern?.sourceRange.end
                            ?? typeExpression?.sourceRange.end
                            ?? name.sourceRange(in: buffer).end
                    expression = AST.BindingPattern(
                        token, name, typeExpression, subpattern,
                        sourceRange: SourceRange(
                            start: token.sourceRange(in: buffer).start,
                            end: endToken
                        )
                    )
                } else {
                    return nil
                }
            case .SomeKw, .AnyKw:
                index += 1
                let wrapped =
                    parseExpression(
                        excepts: excepts, isCondition: isCondition, isTypeContext: isTypeContext
                    )
                    ?? errorExpression(from: token, to: token)
                let inner: AST.Expression = if let seq = wrapped as? AST.SequentialExpression,
                                               !seq.ops.isEmpty,
                                               seq.ops.allSatisfy({ op in
                                                   if case .Operator(.BitAnd) = op.kind { return true }
                                                   return false
                                               })
                {
                    AST.ProtocolCompositionType(
                        seq.operands, sourceRange: seq.sourceRange
                    )
                } else {
                    wrapped
                }
                if kind == .SomeKw {
                    expression = AST.SomeType(
                        token, inner,
                        sourceRange: SourceRange(
                            start: token.sourceRange(in: buffer).start,
                            end: inner.sourceRange.end
                        )
                    )
                } else {
                    expression = AST.AnyType(
                        token, inner,
                        sourceRange: SourceRange(
                            start: token.sourceRange(in: buffer).start,
                            end: inner.sourceRange.end
                        )
                    )
                }
            case .Is:
                if !inPatternContext { return nil }
                index += 1
                let typeExpr =
                    parseExpression(excepts: excepts, isTypeContext: isTypeContext)
                        ?? errorExpression(from: token, to: token)
                expression = AST.IsPattern(
                    token, typeExpr,
                    sourceRange: SourceRange(
                        start: token.sourceRange(in: buffer).start,
                        end: typeExpr.sourceRange.end
                    )
                )
            case .Case:
                if !isCondition { return nil }
                expression = parseCaseMatch(token)
            case .Try:
                expression = parseTryExpression(token, excepts, isCondition)
            case .Await:
                expression = parseAwaitExpression(token, excepts, isCondition)
            default:
                return nil
            }
        case let .Separator(kind):
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
                    guard
                        let first = parseExpression(
                            isCondition: isCondition, isTypeContext: isTypeContext
                        )
                    else {
                        emitError("expected expression after '('", at: locationAfter(token))
                        if let t = peek, case .Separator(.CloseParen) = t.kind {
                            index += 1
                        }
                        return nil
                    }
                    var label: Token? = nil
                    var value = first
                    if let variable = first as? AST.Variable,
                       let colon = peek, case .Separator(.Colon) = colon.kind
                    {
                        label = variable.name
                        index += 1
                        value =
                            parseExpression(isTypeContext: isTypeContext)
                                ?? errorExpression(from: colon, to: colon)
                    }
                    let isTuple =
                        label != nil
                            || (peek?.kind == .Separator(.Comma))
                    if isTuple {
                        var elements: [AST.LabeledArgument] = [
                            AST.LabeledArgument(
                                label: label, value: value,
                                sourceRange: SourceRange(
                                    start: first.sourceRange.start,
                                    end: value.sourceRange.end
                                )
                            ),
                        ]
                        while let comma = peek, case .Separator(.Comma) = comma.kind {
                            index += 1
                            if let cp = peek, case .Separator(.CloseParen) = cp.kind {
                                break
                            }
                            guard let elem = parseExpression(isTypeContext: isTypeContext) else {
                                emitError("expected expression after ','", at: comma)
                                break
                            }
                            var elemLabel: Token? = nil
                            var elemValue = elem
                            if let variable = elem as? AST.Variable,
                               let colon = peek, case .Separator(.Colon) = colon.kind
                            {
                                elemLabel = variable.name
                                index += 1
                                elemValue =
                                    parseExpression(isTypeContext: isTypeContext)
                                        ?? errorExpression(from: colon, to: colon)
                            }
                            elements.append(
                                AST.LabeledArgument(
                                    label: elemLabel, value: elemValue,
                                    sourceRange: SourceRange(
                                        start: elem.sourceRange.start,
                                        end: elemValue.sourceRange.end
                                    )
                                )
                            )
                        }
                        var closeToken: Token = token
                        if let t = peek, case .Separator(.CloseParen) = t.kind {
                            index += 1
                            closeToken = t
                        } else if let t = peek {
                            emitError(
                                "expected ')' after tuple elements, but got '\(t.value)'", at: t
                            )
                            closeToken = t
                        } else {
                            emitError("expected ')' after tuple elements", at: endOfFile)
                        }
                        expression = AST.TupleExpression(
                            elements,
                            sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
                        )
                    } else {
                        if let t = next {
                            if t.kind != .Separator(.CloseParen) {
                                emitError(
                                    "expected ')' after expression, but got '\(t.value)'", at: t
                                )
                            }
                            expression = AST.ParentheticalExpression(
                                value, sourceRange: SourceRange(from: token, to: t, in: buffer)
                            )
                        } else {
                            emitError("expected ')' after expression", at: token)
                            return AST.ParentheticalExpression(
                                value,
                                sourceRange: SourceRange(
                                    start: token.sourceRange(in: buffer).start,
                                    end: endOfFile
                                )
                            )
                        }
                    }
                }
            case .OpenBrace:
                expression = parseClosure()
            case .OpenBracket:
                index += 1
                expression = parseCollectionLiteral(openBracket: token)
            default: return nil
            }
        case let .Operator(kind):
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
            case .Dollar:
                index += 1
                guard let numToken = next else {
                    emitError("expected integer after '$'", at: endOfFile)
                    return errorExpression(from: token, to: endOfFile)
                }
                guard case let .IntegerLiteral(value) = numToken.kind else {
                    emitError(
                        "expected integer literal after '$', but got '\(numToken.value)'",
                        at: numToken
                    )
                    return errorExpression(from: token, to: numToken)
                }
                expression = AST.ShorthandArgument(
                    token, Int(truncatingIfNeeded: value),
                    sourceRange: SourceRange(from: token, to: numToken, in: buffer)
                )
            case .Backslash:
                index += 1
                expression = parseKeyPath(token)
            default:
                return nil
            }
        default: return nil
        }
        return parsePostfix(expression, excepts: excepts)
    }

    private func parseKeyPath(_ backslashToken: Token) -> AST.Expression {
        var root: AST.Expression? = nil
        var lastToken = backslashToken
        if let t = peek, case .Identifier = t.kind {
            index += 1
            lastToken = t
            root = AST.Variable(name: t, sourceRange: t.sourceRange(in: buffer))
        }
        var rootPostfix: Token? = nil
        if let t = peek, t.kind == .Operator(.QuestionMark) || t.kind == .Operator(.Not) {
            rootPostfix = t
            lastToken = t
            index += 1
        }
        var components: [AST.KeyPathExpression.Component] = []
        _loop: while let t = peek {
            let dot: Token
            switch t.kind {
            case .Operator(.Dot), .Operator(.QuestionMarkDot):
                dot = t
                index += 1
            default:
                break _loop
            }
            guard let name = peek else {
                emitError("expected keypath component name after '.'", at: endOfFile)
                break _loop
            }
            switch name.kind {
            case .Identifier, .IntegerLiteral, .Keyword(.SelfKw):
                index += 1
                lastToken = name
            default:
                emitError(
                    "expected identifier, integer, or 'self' after '.', but got '\(name.value)'",
                    at: name
                )
                break _loop
            }
            var postfix: Token? = nil
            if let p = peek, p.kind == .Operator(.QuestionMark) || p.kind == .Operator(.Not) {
                postfix = p
                lastToken = p
                index += 1
            }
            components.append(
                AST.KeyPathExpression.Component(dotToken: dot, name: name, postfix: postfix)
            )
        }
        if components.isEmpty {
            if let t = peek {
                emitError(
                    "expected keypath component after '\\', but got '\(t.value)'",
                    at: t
                )
            } else {
                emitError("expected keypath component after '\\'", at: endOfFile)
            }
        }
        return AST.KeyPathExpression(
            backslashToken, root, rootPostfix, components,
            sourceRange: SourceRange(from: backslashToken, to: lastToken, in: buffer)
        )
    }

    private func parseCollectionLiteral(openBracket: Token) -> AST.Expression {
        if let t = peek, case .Separator(.CloseBracket) = t.kind {
            index += 1
            return AST.ArrayLiteral(
                [], sourceRange: SourceRange(from: openBracket, to: t, in: buffer)
            )
        }
        if let colon = peek, case .Separator(.Colon) = colon.kind {
            index += 1
            if let t = peek, case .Separator(.CloseBracket) = t.kind {
                index += 1
                return AST.DictionaryLiteral(
                    [], sourceRange: SourceRange(from: openBracket, to: t, in: buffer)
                )
            }
            emitError("expected ']' after ':' to form empty dictionary", at: colon)
        }
        guard let first = parseExpression() else {
            emitError("expected expression after '['", at: locationAfter(openBracket))
            if let t = peek, case .Separator(.CloseBracket) = t.kind {
                index += 1
            }
            return errorExpression(from: openBracket, to: openBracket)
        }
        if let colon = peek, case .Separator(.Colon) = colon.kind {
            index += 1
            let value = parseExpression() ?? errorExpression(from: colon, to: colon)
            var entries: [AST.DictionaryLiteral.Entry] = [
                AST.DictionaryLiteral.Entry(
                    key: first, value: value,
                    sourceRange: SourceRange(
                        start: first.sourceRange.start, end: value.sourceRange.end
                    )
                ),
            ]
            while let comma = peek, case .Separator(.Comma) = comma.kind {
                index += 1
                if let cb = peek, case .Separator(.CloseBracket) = cb.kind {
                    break
                }
                let key = parseExpression() ?? errorExpression(from: comma, to: comma)
                if let colon2 = peek, case .Separator(.Colon) = colon2.kind {
                    index += 1
                } else if let t = peek {
                    emitError("expected ':' in dictionary entry, but got '\(t.value)'", at: t)
                } else {
                    emitError("expected ':' in dictionary entry", at: endOfFile)
                }
                let val = parseExpression() ?? errorExpression(from: comma, to: comma)
                entries.append(
                    AST.DictionaryLiteral.Entry(
                        key: key, value: val,
                        sourceRange: SourceRange(
                            start: key.sourceRange.start, end: val.sourceRange.end
                        )
                    )
                )
            }
            if let t = peek, case .Separator(.CloseBracket) = t.kind {
                index += 1
                return AST.DictionaryLiteral(
                    entries, sourceRange: SourceRange(from: openBracket, to: t, in: buffer)
                )
            } else if let t = peek {
                emitError("expected ']' after dictionary literal, but got '\(t.value)'", at: t)
                return AST.DictionaryLiteral(
                    entries, sourceRange: SourceRange(from: openBracket, to: t, in: buffer)
                )
            } else {
                emitError("expected ']' after dictionary literal", at: endOfFile)
                return AST.DictionaryLiteral(
                    entries,
                    sourceRange: SourceRange(from: openBracket, to: openBracket, in: buffer)
                )
            }
        } else {
            var elements: [AST.Expression] = [first]
            while let comma = peek, case .Separator(.Comma) = comma.kind {
                index += 1
                if let cb = peek, case .Separator(.CloseBracket) = cb.kind {
                    break
                }
                if let elem = parseExpression() {
                    elements.append(elem)
                } else {
                    break
                }
            }
            if let t = peek, case .Separator(.CloseBracket) = t.kind {
                index += 1
                return AST.ArrayLiteral(
                    elements, sourceRange: SourceRange(from: openBracket, to: t, in: buffer)
                )
            } else if let t = peek {
                emitError("expected ']' after array literal, but got '\(t.value)'", at: t)
                return AST.ArrayLiteral(
                    elements, sourceRange: SourceRange(from: openBracket, to: t, in: buffer)
                )
            } else {
                emitError("expected ']' after array literal", at: endOfFile)
                return AST.ArrayLiteral(
                    elements,
                    sourceRange: SourceRange(from: openBracket, to: openBracket, in: buffer)
                )
            }
        }
    }

    private func parsePostfix(_ expression: AST.Expression, excepts: [OperatorKind]?)
        -> AST.Expression
    {
        var expression = expression
        _loop: while let t = peek {
            switch t.kind {
            case let .Separator(kind):
                switch kind {
                case .Arrow:
                    if inPatternContext { break _loop }
                    expression = parseClosureType(expression, nil, excepts)
                default: break _loop
                }
            case .Keyword(.Throws):
                switch expression {
                case is AST.ParentheticalExpression, is AST.TupleExpression:
                    let throwsClause = parseThrowsClause()
                    guard let t = peek, case .Separator(.Arrow) = t.kind else {
                        if let tok = peek {
                            emitError(
                                "expected '->' after 'throws' in closure type, but got '\(tok.value)'",
                                at: tok
                            )
                        } else {
                            emitError("expected '->' after 'throws' in closure type", at: endOfFile)
                        }
                        break _loop
                    }
                    expression = parseClosureType(expression, throwsClause, excepts)
                default: break _loop
                }
            default: break _loop
            }
        }
        return expression
    }

    private func parseOptionalBinding(_ token: Token) -> AST.Expression {
        index += 1
        guard let name = next else {
            emitError("expected identifier after '\(token.value)'", at: endOfFile)
            return errorExpression(from: token, to: endOfFile)
        }
        guard case .Identifier = name.kind else {
            emitError(
                "expected identifier after '\(token.value)', but got '\(name.value)'", at: name
            )
            return errorExpression(from: token, to: name)
        }
        var typeExpression: AST.Expression? = nil
        if let t = peek, case .Separator(.Colon) = t.kind {
            index += 1
            suppressTrailingClosures = true
            typeExpression = parseExpression(excepts: [.Assign], isTypeContext: true)
            suppressTrailingClosures = false
        }
        guard let eq = peek, case .Operator(.Assign) = eq.kind else {
            emitError(
                "expected '=' in optional binding",
                at: SourceRange(from: token, to: name, in: buffer)
            )
            return errorExpression(from: token, to: name)
        }
        index += 1
        suppressTrailingClosures = true
        let value = parseExpression() ?? errorExpression(from: eq, to: eq)
        suppressTrailingClosures = false
        return AST.OptionalBinding(
            token, name, typeExpression, value,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseCaseMatch(_ token: Token) -> AST.Expression {
        index += 1
        inPatternContext = true
        let pattern = parseExpression(excepts: [.Assign])
        inPatternContext = false
        guard let parsedPattern = pattern else {
            emitError("expected pattern after 'case'", at: locationAfter(token))
            return errorExpression(from: token, to: token)
        }
        guard let eq = peek, case .Operator(.Assign) = eq.kind else {
            emitError(
                "expected '=' after case pattern",
                at: SourceRange(from: token, to: last ?? token, in: buffer)
            )
            return errorExpression(from: token, to: last ?? token)
        }
        index += 1
        suppressTrailingClosures = true
        let subject = parseExpression() ?? errorExpression(from: eq, to: eq)
        suppressTrailingClosures = false
        return AST.CaseMatch(
            token, parsedPattern, subject,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseTryExpression(
        _ token: Token, _ excepts: [OperatorKind]?, _ isCondition: Bool
    ) -> AST.Expression {
        index += 1
        let kind: AST.TryExpression.Kind
        if let t = peek, case .Operator(.QuestionMark) = t.kind {
            kind = .TryQuestion
            index += 1
        } else if let t = peek, case .Operator(.Not) = t.kind {
            kind = .TryExclamation
            index += 1
        } else {
            kind = .Try
        }
        guard let inner = parseExpression(excepts: excepts, isCondition: isCondition) else {
            emitError("expected expression after 'try'", at: locationAfter(token))
            return errorExpression(from: token, to: locationAfter(token))
        }
        return AST.TryExpression(
            token, kind, inner,
            sourceRange: SourceRange(
                start: token.sourceRange(in: buffer).start,
                end: inner.sourceRange.end
            )
        )
    }

    private func parseAwaitExpression(
        _ token: Token, _ excepts: [OperatorKind]?, _ isCondition: Bool
    ) -> AST.Expression {
        index += 1
        guard let inner = parseExpression(excepts: excepts, isCondition: isCondition) else {
            emitError("expected expression after 'await'", at: locationAfter(token))
            return errorExpression(from: token, to: locationAfter(token))
        }
        return AST.AwaitExpression(
            token, inner,
            sourceRange: SourceRange(
                start: token.sourceRange(in: buffer).start,
                end: inner.sourceRange.end
            )
        )
    }

    private func parseIf() -> AST.Expression {
        let token = next!
        let condition =
            parseExpression(isCondition: true) ?? errorExpression(from: token, to: token)
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
            } else {
                break
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
                    } else {
                        break
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

    private func parseDo() -> AST.Expression {
        let token = next!
        guard let openToken = peek else {
            emitError("expected '{' after 'do'", at: endOfFile)
            return errorExpression(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after 'do', but got '\(openToken.value)'",
                at: openToken
            )
            return errorExpression(from: token, to: openToken)
        }
        index += 1
        var body: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            } else {
                break
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after do body", at: endOfFile)
            return errorExpression(from: token, to: endOfFile)
        }
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after do body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        var catches: [AST.Do.CatchClause] = []
        while let t = peek, case .Keyword(.Catch) = t.kind {
            if let catchClause = parseCatchClause() {
                catches.append(catchClause)
            }
        }
        var finallyBody: [AST.Statement]? = nil
        if let finallyToken = peek, case .Keyword(.Finally) = finallyToken.kind {
            index += 1
            guard let openToken = peek else {
                emitError("expected '{' after 'finally'", at: endOfFile)
                return errorExpression(from: token, to: endOfFile)
            }
            guard case .Separator(.OpenBrace) = openToken.kind else {
                emitError(
                    "expected '{' after 'finally', but got '\(openToken.value)'",
                    at: openToken
                )
                return errorExpression(from: token, to: openToken)
            }
            index += 1
            var statements: [AST.Statement] = []
            while let closeToken = peek {
                if case .Separator(.CloseBrace) = closeToken.kind {
                    break
                }
                if let stmt = parseStatement() {
                    statements.append(stmt)
                } else {
                    break
                }
            }
            guard let closeToken = peek else {
                emitError("expected '}' after finally body", at: endOfFile)
                return errorExpression(from: token, to: endOfFile)
            }
            if case .Separator(.CloseBrace) = closeToken.kind {
                index += 1
            } else {
                emitError(
                    "expected '}' after finally body, but got \(closeToken.value)",
                    at: closeToken
                )
            }
            finallyBody = statements
        }
        return AST.Do(
            token, body, catches, finallyBody,
            sourceRange: SourceRange(from: token, to: last!, in: buffer)
        )
    }

    private func parseCatchClause() -> AST.Do.CatchClause? {
        let beginToken = next!
        var pattern: AST.Expression?
        var whereToken: Token?
        var whereCondition: AST.Expression?
        if let t = peek, case .Separator(.OpenBrace) = t.kind {
        } else if let t = peek, case .Keyword(.Where) = t.kind {
            whereToken = t
            index += 1
            suppressTrailingClosures = true
            whereCondition = parseExpression() ?? errorExpression(from: t, to: t)
            suppressTrailingClosures = false
        } else {
            inPatternContext = true
            suppressTrailingClosures = true
            pattern = parseExpression() ?? errorExpression(from: beginToken, to: beginToken)
            inPatternContext = false
            suppressTrailingClosures = false
            if let t = peek, case .Keyword(.Where) = t.kind {
                whereToken = t
                index += 1
                suppressTrailingClosures = true
                whereCondition = parseExpression() ?? errorExpression(from: t, to: t)
                suppressTrailingClosures = false
            }
        }
        guard let openToken = next else {
            emitError("expected '{' after catch clause", at: endOfFile)
            return nil
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after catch clause, but got '\(openToken.value)'",
                at: openToken
            )
            return nil
        }
        var catchBody: [AST.Statement] = []
        while let closeToken = peek {
            if case .Separator(.CloseBrace) = closeToken.kind {
                break
            }
            if let stmt = parseStatement() {
                catchBody.append(stmt)
            } else {
                break
            }
        }
        guard let closeToken = peek else {
            emitError("expected '}' after catch body", at: endOfFile)
            return nil
        }
        if case .Separator(.CloseBrace) = closeToken.kind {
            index += 1
        } else {
            emitError(
                "expected '}' after catch body, but got \(closeToken.value)",
                at: closeToken
            )
        }
        return AST.Do.CatchClause(
            pattern, whereToken, whereCondition, catchBody,
            sourceRange: SourceRange(from: beginToken, to: closeToken, in: buffer)
        )
    }

    private func parseMatch() -> AST.Expression {
        let token = next!
        suppressTrailingClosures = true
        let subject = parseExpression() ?? errorExpression(from: token, to: token)
        suppressTrailingClosures = false
        var cases: [AST.Match.Case] = []
        guard let openToken = next else {
            emitError("expected '{' after match subject", at: endOfFile)
            return errorExpression(from: token, to: endOfFile)
        }
        guard case .Separator(.OpenBrace) = openToken.kind else {
            emitError(
                "expected '{' after match subject, but got '\(openToken.value)'",
                at: openToken
            )
            return errorExpression(from: token, to: openToken)
        }
        while let t = peek {
            if t.kind == .Separator(.CloseBrace) {
                break
            }
            if let matchCase = parseMatchCase() {
                cases.append(matchCase)
            }
        }
        guard let closeToken = next else {
            emitError("expected '}' after match cases", at: endOfFile)
            return errorExpression(from: token, to: endOfFile)
        }
        guard case .Separator(.CloseBrace) = closeToken.kind else {
            emitError(
                "expected '}' after match cases, but got '\(closeToken.value)'", at: closeToken
            )
            return errorExpression(from: token, to: closeToken)
        }
        return AST.Match(
            token, subject, cases, sourceRange: SourceRange(from: token, to: closeToken, in: buffer)
        )
    }

    private func parseMatchCase() -> AST.Match.Case? {
        let beginToken = peek!
        var patterns: [AST.Expression] = []
        inPatternContext = true
        _loop: while let t = peek {
            switch t.kind {
            case .Separator(.Arrow):
                break _loop
            case .Separator(.Comma):
                index += 1
            default:
                if let pattern = parseExpression() {
                    patterns.append(pattern)
                } else {
                    break _loop
                }
            }
        }
        inPatternContext = false
        guard let arrowToken = next else {
            emitError("expected '=>' after match case pattern", at: endOfFile)
            return nil
        }
        guard case .Separator(.Arrow) = arrowToken.kind else {
            emitError(
                "expected '=>' after match case pattern, but got '\(arrowToken.value)'",
                at: arrowToken
            )
            return nil
        }
        if let t = peek {
            var body: [AST.Statement] = []
            switch t.kind {
            case .Separator(.OpenBrace):
                index += 1
                while let t = peek {
                    if case .Separator(.CloseBrace) = t.kind {
                        break
                    }
                    if let stmt = parseStatement() {
                        body.append(stmt)
                    } else {
                        break
                    }
                }
                if let t = next {
                    if t.kind != .Separator(.CloseBrace) {
                        emitError("expected '}' after block, but got '\(t.value)'", at: t)
                    }
                } else {
                    emitError("expected '}' after block", at: endOfFile)
                }
            default:
                if let expr = parseExpression() {
                    body.append(AST.ExpressionStatement(expr))
                } else {
                    emitError("expected expression after '=>'", at: locationAfter(arrowToken))
                    return nil
                }
            }
            return AST.Match.Case(
                patterns, body,
                sourceRange: SourceRange(from: beginToken, to: last!, in: buffer)
            )
        } else {
            emitError("expected '{' or expression after '=>'", at: endOfFile)
            return nil
        }
    }

    private func parseStringInterpolation(_ firstToken: Token) -> AST.Expression {
        var segments: [AST.StringSegment] = [.literal(firstToken)]
        while true {
            if let t = peek {
                guard case .Separator(.OpenParen) = t.kind else {
                    emitError("expected '(' for string interpolation", at: t)
                    return errorExpression(from: firstToken, to: t)
                }
                index += 1
                let expr = parseExpression() ?? errorExpression(from: t, to: t)
                segments.append(.expression(expr))
            } else {
                emitError("expected '(' for string interpolation", at: endOfFile)
                return errorExpression(from: firstToken, to: firstToken)
            }
            guard let close = peek else {
                emitError("expected ')' after interpolation expression", at: endOfFile)
                return errorExpression(from: firstToken, to: firstToken)
            }
            if close.kind != .Separator(.CloseParen) {
                emitError(
                    "expected ')' after interpolation expression, but got '\(close.value)'",
                    at: close
                )
                return errorExpression(from: firstToken, to: close)
            }
            index += 1
            guard let nextToken = peek else {
                emitError("expected string literal after interpolation", at: endOfFile)
                return errorExpression(from: firstToken, to: firstToken)
            }
            guard case .StringLiteral = nextToken.kind else {
                break
            }
            index += 1
            segments.append(.literal(nextToken))
            if !nextToken.isUnterminated {
                break
            }
        }
        return AST.StringInterpolation(
            segments,
            sourceRange: SourceRange(from: firstToken, to: last!, in: buffer)
        )
    }

    private func parseClosure() -> AST.Closure {
        let beginToken = next!
        let signature: AST.ClosureSignature?
        if peek?.kind == .Separator(.OpenParen) || peek?.kind == .Separator(.OpenBracket) {
            signature = parseClosureSignature()
        } else if let t = peek, t.kind == .Keyword(.Async) {
            signature = parseClosureSignature()
        } else if let t = peek, case .Identifier = t.kind,
                  let t2 = peek2, case .Identifier = t2.kind, t2.value == "in"
        {
            index += 1
            let parameter = AST.FunctionDecl.Parameter(
                label: nil, name: t, type: nil, defaultValue: nil,
                sourceRange: t.sourceRange(in: buffer)
            )
            index += 1
            signature = AST.ClosureSignature([], [parameter], nil, nil, nil, t2)
        } else {
            signature = nil
        }
        var body: [AST.Statement] = []
        while let t = peek {
            if t.kind == .Separator(.CloseBrace) {
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            } else {
                break
            }
        }
        if let t = next {
            if t.kind != .Separator(.CloseBrace) {
                emitError("expected '}' after closure body, but got '\(t.value)'", at: t)
            }
        } else {
            emitError("expected '}' after closure body", at: endOfFile)
        }
        return AST.Closure(
            signature, body,
            sourceRange: SourceRange(from: beginToken, to: last!, in: buffer)
        )
    }

    private func parseClosureSignature() -> AST.ClosureSignature {
        var captureList: [AST.CaptureItem] = []
        if peek?.kind == .Separator(.OpenBracket) {
            captureList = parseCaptureList()
        }
        var asyncToken: Token? = nil
        if let t = peek, t.kind == .Keyword(.Async) {
            index += 1
            asyncToken = t
        }
        var parameters: [AST.FunctionDecl.Parameter] = []
        if peek?.kind == .Separator(.OpenParen) {
            index += 1
            while let t = peek {
                if t.kind == .Separator(.CloseParen) { break }
                if t.kind == .Separator(.Comma) {
                    index += 1
                    continue
                }
                parameters.append(parseFunctionParameter())
            }
            let t = peek
            if t?.kind == .Separator(.CloseParen) {
                index += 1
            } else {
                if let tok = peek {
                    emitError("expected ')' after closure parameters", at: tok)
                } else {
                    emitError("expected ')' after closure parameters", at: endOfFile)
                }
            }
        }
        let throwsClause = parseThrowsClause()
        var returnType: AST.Expression? = nil
        if peek?.kind == .Separator(.Arrow) {
            index += 1
            suppressTrailingClosures = true
            returnType = parseExpression(isTypeContext: true)
            suppressTrailingClosures = false
        }
        let inToken = peek
        let isIn =
            inToken.map { t in
                if case .Identifier = t.kind, t.value == "in" { return true }
                return false
            } ?? false
        if !isIn {
            if let tok = peek {
                emitError("expected 'in' after closure signature", at: tok)
            } else {
                emitError("expected 'in' after closure signature", at: endOfFile)
            }
            let fallback =
                peek
                    ?? Token(
                        value: "", kind: .Unknown,
                        pos: Position(pos: 0, line: 0, col: 0, len: 0), id: lexerResult.id
                    )
            return AST.ClosureSignature(
                captureList, parameters, throwsClause, returnType, asyncToken, fallback
            )
        }
        index += 1
        return AST.ClosureSignature(
            captureList, parameters, throwsClause, returnType, asyncToken, inToken!
        )
    }

    private func parseCaptureList() -> [AST.CaptureItem] {
        index += 1
        var items: [AST.CaptureItem] = []
        while let t = peek {
            if t.kind == .Separator(.CloseBracket) { break }
            var specifier: Token?
            if t.value == "weak" || t.value == "unowned" {
                specifier = t
                index += 1
            }
            let name = peek
            let isWord = if let n = name {
                switch n.kind {
                case .Identifier, .Keyword: true
                default: false
                }
            } else {
                false
            }
            if !isWord {
                if let tok = peek {
                    emitError("expected identifier in capture list", at: tok)
                } else {
                    emitError("expected identifier in capture list", at: endOfFile)
                }
                break
            }
            index += 1
            items.append(AST.CaptureItem(specifier, name!))
            if peek?.kind == .Separator(.Comma) {
                index += 1
            } else {
                break
            }
        }
        let t = peek
        if t?.kind == .Separator(.CloseBracket) {
            index += 1
        } else {
            if let tok = peek {
                emitError("expected ']' after capture list", at: tok)
            } else {
                emitError("expected ']' after capture list", at: endOfFile)
            }
        }
        return items
    }

    private func parseClosureType(
        _ parameterTypes: AST.Expression, _ throwsClause: AST.ThrowsClause?,
        _ excepts: [OperatorKind]?
    ) -> AST.ClosureType {
        let token = next!
        if token.kind != .Separator(.Arrow) {
            emitError(
                "expected '->' after closure type parameters, but got '\(token.value)'",
                at: token
            )
        }
        let returnTypeExpression =
            parseExpression(excepts: excepts, isTypeContext: true)
                ?? AST.ErrorExpression(SourceRange(location: locationAfter(token)))
        return AST.ClosureType(
            parameterTypes, throwsClause, returnTypeExpression,
            sourceRange: SourceRange(
                start: parameterTypes.sourceRange.start, end: returnTypeExpression.sourceRange.end
            )
        )
    }

    private func parseArgumentList() -> [AST.LabeledArgument] {
        var arguments: [AST.LabeledArgument] = []
        _loop: while true {
            guard let expr = parseExpression() else {
                break _loop
            }
            var label: Token?
            var value = expr
            if let variable = expr as? AST.Variable,
               let colon = peek, case .Separator(.Colon) = colon.kind
            {
                label = variable.name
                index += 1
                value = parseExpression() ?? errorExpression(from: colon, to: colon)
            }
            let argRange = SourceRange(
                start: expr.sourceRange.start,
                end: value.sourceRange.end
            )
            arguments.append(AST.LabeledArgument(label: label, value: value, sourceRange: argRange))
            if let comma = peek, case .Separator(.Comma) = comma.kind {
                index += 1
            } else {
                break _loop
            }
        }
        return arguments
    }

    private func parseCall(_ callee: AST.Expression) -> AST.Call {
        index += 1
        let arguments: [AST.LabeledArgument]
        let endToken: Token?
        if let t = peek, case .Separator(.CloseParen) = t.kind {
            arguments = []
            index += 1
            endToken = t
        } else {
            arguments = parseArgumentList()
            if let t = peek, case .Separator(.CloseParen) = t.kind {
                index += 1
                endToken = t
            } else if let t = peek {
                emitError("expected ')' after call arguments, but got '\(t.value)'", at: t)
                endToken = t
            } else {
                emitError("expected ')' after call arguments", at: endOfFile)
                endToken = nil
            }
        }
        let range: SourceRange = if let endToken {
            SourceRange(
                start: callee.sourceRange.start, end: endToken.sourceRange(in: buffer).end
            )
        } else {
            callee.sourceRange
        }
        return AST.Call(
            callee: callee, arguments: arguments, trailingClosures: [], sourceRange: range
        )
    }

    private func parseSubscript(_ base: AST.Expression) -> AST.Subscript {
        index += 1
        var arguments: [AST.LabeledArgument] = []
        var endToken: Token? = nil
        if let t = peek, case .Separator(.CloseBracket) = t.kind {
            index += 1
            endToken = t
        } else {
            arguments = parseArgumentList()
            if let t = peek, case .Separator(.CloseBracket) = t.kind {
                index += 1
                endToken = t
            } else if let t = peek {
                emitError("expected ']' after subscript arguments, but got '\(t.value)'", at: t)
                endToken = t
            } else {
                emitError("expected ']' after subscript arguments", at: endOfFile)
            }
        }
        let range: SourceRange = if let endToken {
            SourceRange(
                start: base.sourceRange.start, end: endToken.sourceRange(in: buffer).end
            )
        } else {
            base.sourceRange
        }
        return AST.Subscript(base: base, arguments: arguments, sourceRange: range)
    }

    private func parseAnnotations() -> ([AST.Modifier], [AST.Attribute]) {
        var modifiers: [AST.Modifier] = []
        var attributes: [AST.Attribute] = []
        _loop: while let token = peek {
            switch token.kind {
            case let .Keyword(kind):
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
                case .Static:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Static,
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
                case .Isolated:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Isolated,
                            sourceRange: token.sourceRange(in: buffer)
                        )
                    )
                case .Async:
                    index += 1
                    modifiers.append(
                        AST.Modifier(
                            token: token,
                            kind: .Async,
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
                guard case let .Separator(t2Kind) = t2.kind else {
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
