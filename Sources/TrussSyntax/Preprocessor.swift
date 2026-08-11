import Foundation
import SwiftBetterDiagnostic
import TrussCore

public enum TargetTriple {
    public static let host: String = {
        #if os(Linux)
            let os = "linux"
        #elseif os(macOS)
            let os = "macos"
        #elseif os(Windows)
            let os = "windows"
        #elseif os(iOS)
            let os = "ios"
        #elseif os(Android)
            let os = "android"
        #elseif os(FreeBSD)
            let os = "freebsd"
        #else
            let os = "unknown"
        #endif
        #if arch(x86_64)
            let arch = "x86_64"
        #elseif arch(arm64)
            #if os(macOS) || os(iOS)
                let arch = "arm64"
            #else
                let arch = "aarch64"
            #endif
        #elseif arch(i386)
            let arch = "i386"
        #elseif arch(arm)
            let arch = "arm"
        #else
            let arch = "unknown"
        #endif
        return "\(arch)-unknown-\(os)"
    }()
}

public struct PreprocessorConfig {
    public let flags: Set<String>
    public let defines: [String: String]
    public let target: String
    public let workingDirectory: String
    public init(
        flags: Set<String> = [], defines: [String: String] = [:],
        target: String = TargetTriple.host,
        workingDirectory: String = ""
    ) {
        self.flags = flags
        self.defines = defines
        self.target = target
        self.workingDirectory = workingDirectory
    }
}

private struct ConditionFrame {
    let parentActive: Bool
    var branchTaken: Bool
}

private enum Macro {
    case Object(name: Token, tokens: [Token])
    case Function(name: Token, params: [String], variadic: Bool, tokens: [Token])
}

public final class Preprocessor {
    private let context: Context
    private var config = PreprocessorConfig()
    private var index = 0
    private var active = true
    private var frames: [ConditionFrame] = []
    private var outerIfToken: Token?
    private var macros: [String: Macro] = [:]
    private var expanding: [String] = []
    private var includeStack: [String] = []

    public init(context: Context) {
        self.context = context
    }

    public func process(_ lexerResult: LexerResult, config: PreprocessorConfig) -> LexerResult {
        self.config = config
        index = 0
        active = true
        frames = []
        outerIfToken = nil
        macros = [:]
        expanding = []
        includeStack = []
        for (name, value) in config.defines {
            let nameToken = Token(
                value: name, kind: .Identifier,
                pos: Position(pos: 0, line: 1, col: 1, len: name.count), id: lexerResult.id
            )
            let valueTokens = Lexer(input: CharStream(content: value, id: lexerResult.id))
                .parse().tokens
            macros[name] = .Object(name: nameToken, tokens: valueTokens)
        }
        let tokens = scan(lexerResult, currentDir: config.workingDirectory)
        return LexerResult(id: lexerResult.id, tokens: tokens)
    }

    private func scan(_ lexerResult: LexerResult, currentDir: String) -> [Token] {
        let tokens = lexerResult.tokens
        var output: [Token] = []
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .Separator(.Sharp) {
                if let directiveOutput = handleDirective(
                    tokens: tokens, currentDir: currentDir
                ) {
                    output.append(contentsOf: directiveOutput)
                } else {
                    emitError("unknown preprocessing directive", at: token)
                    index += 1
                }
                continue
            }
            if active {
                let result = expandToken(token, tokens: tokens, at: index)
                output.append(contentsOf: result.tokens)
                index = result.nextIndex
            } else {
                index += 1
            }
        }
        if let token = outerIfToken {
            emitError("unterminated #if directive", at: token)
        }
        return output.filter { !self.isPlaceholder($0) }
    }

    private func handleDirective(tokens: [Token], currentDir: String) -> [Token]? {
        guard index + 1 < tokens.count else { return nil }
        let sharp = tokens[index]
        let name = tokens[index + 1]
        switch name.kind {
        case .Keyword(.If):
            let args = directiveArgs(
                tokens, from: index + 2, directiveLine: name.pos.line
            )
            index = index + 2 + args.count
            let value = evaluateCondition(args, at: name)
            let errored = value == nil
            let taken = errored || (value ?? false)
            if outerIfToken == nil { outerIfToken = sharp }
            frames.append(ConditionFrame(parentActive: active, branchTaken: taken))
            active = active && !errored && (value ?? false)
            return []
        case .Keyword(.Else):
            index += 2
            handleElse(sharp: sharp)
            return []
        case .Identifier:
            switch name.value {
            case "elseif":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                handleElseIf(args: args, name: name, sharp: sharp)
                return []
            case "endif":
                index += 2
                handleEndIf(sharp: sharp)
                return []
            case "ifdef":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                handleIfDef(args: args, name: name, sharp: sharp, negated: false)
                return []
            case "ifndef":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                handleIfDef(args: args, name: name, sharp: sharp, negated: true)
                return []
            case "error":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                handleErrorDirective(args: args, name: name, severity: .error)
                return []
            case "warning":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                handleErrorDirective(args: args, name: name, severity: .warning)
                return []
            case "define":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line,
                    stopAtSharp: false
                )
                index = index + 2 + args.count
                handleDefine(args: args, name: name)
                return []
            case "undef":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                handleUndef(args: args, name: name)
                return []
            case "include":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                return handleInclude(args: args, name: name, currentDir: currentDir)
            case "pragma":
                let args = directiveArgs(
                    tokens, from: index + 2, directiveLine: name.pos.line
                )
                index = index + 2 + args.count
                return []
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func handleInclude(args: [Token], name: Token, currentDir: String) -> [Token] {
        guard active else { return [] }
        guard let path = includePath(args) else {
            emitError("expected file path in #include", at: name)
            return []
        }
        let fullPath = currentDir.isEmpty ? path : "\(currentDir)/\(path)"
        guard !includeStack.contains(fullPath) else {
            emitError("circular #include of '\(path)'", at: name)
            return []
        }
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            emitError("file not found: '\(path)'", at: name)
            return []
        }
        let source = Source(id: context.nextSourceId, filepath: fullPath, content: content)
        context.register(source: source)
        let lexerResult = Lexer(input: CharStream(content: content, id: source.id)).parse()
        let savedActive = active
        let savedFrames = frames
        let savedOuterIf = outerIfToken
        let savedIndex = index
        frames = []
        outerIfToken = nil
        index = 0
        includeStack.append(fullPath)
        let dir = (fullPath as NSString).deletingLastPathComponent
        let result = scan(lexerResult, currentDir: dir)
        includeStack.removeLast()
        index = savedIndex
        frames = savedFrames
        outerIfToken = savedOuterIf
        active = savedActive
        return result
    }

    private func includePath(_ args: [Token]) -> String? {
        if let first = args.first, first.kind == .StringLiteral {
            return first.value
        }
        if let first = args.first, first.kind == .Operator(.Less) {
            var parts: [String] = []
            var k = 1
            while k < args.count {
                if args[k].kind == .Operator(.Greater) {
                    return parts.joined()
                }
                parts.append(args[k].value)
                k += 1
            }
            return nil
        }
        return nil
    }

    private func handleElse(sharp: Token) {
        guard let frame = frames.last else {
            emitError("unexpected #else directive", at: sharp)
            return
        }
        if frame.branchTaken {
            active = false
        } else {
            frames[frames.count - 1].branchTaken = true
            active = frame.parentActive
        }
    }

    private func handleElseIf(args: [Token], name: Token, sharp: Token) {
        guard let frame = frames.last else {
            emitError("unexpected #elseif directive", at: sharp)
            return
        }
        if !frame.branchTaken {
            let value = evaluateCondition(args, at: name)
            if let v = value {
                if v {
                    frames[frames.count - 1].branchTaken = true
                    active = frame.parentActive
                } else {
                    active = false
                }
            } else {
                active = false
            }
        } else {
            active = false
        }
    }

    private func handleIfDef(args: [Token], name: Token, sharp: Token, negated: Bool) {
        if outerIfToken == nil { outerIfToken = sharp }
        guard let first = args.first, first.kind == .Identifier else {
            emitError(
                "expected macro name after #\(negated ? "ifndef" : "ifdef")", at: name
            )
            frames.append(ConditionFrame(parentActive: active, branchTaken: true))
            active = false
            return
        }
        let taken = isDefined(first.value) != negated
        frames.append(ConditionFrame(parentActive: active, branchTaken: taken))
        active = active && taken
    }

    private func isDefined(_ name: String) -> Bool {
        macros[name] != nil || config.flags.contains(name)
    }

    private func handleEndIf(sharp: Token) {
        guard !frames.isEmpty else {
            emitError("unexpected #endif directive", at: sharp)
            return
        }
        let frame = frames.removeLast()
        if frames.isEmpty {
            outerIfToken = nil
        }
        active = frame.parentActive
    }

    private func handleErrorDirective(
        args: [Token], name: Token, severity: DiagnosticSeverity
    ) {
        guard active else { return }
        guard let message = args.first(where: { $0.kind == .StringLiteral }) else {
            emitError(
                "expected string literal in \(severity == .error ? "#error" : "#warning") directive",
                at: name
            )
            return
        }
        emitDiagnostic(severity, message: message.value, at: name)
    }

    private func handleDefine(args: [Token], name: Token) {
        guard active else { return }
        guard let first = args.first, first.kind == .Identifier else {
            emitError("expected macro name after #define", at: name)
            return
        }
        let rest = Array(args.dropFirst())
        let isFunctionLike =
            rest.first?.kind == .Separator(.OpenParen)
                && first.pos.pos + first.pos.len == rest[0].pos.pos
        if isFunctionLike {
            guard let (params, variadic, closeIndex) = parseMacroParams(rest, name: name)
            else {
                return
            }
            macros[first.value] = .Function(
                name: first, params: params, variadic: variadic,
                tokens: Array(rest.dropFirst(closeIndex + 1))
            )
        } else {
            macros[first.value] = .Object(name: first, tokens: rest)
        }
    }

    private func parseMacroParams(
        _ tokens: [Token], name: Token
    ) -> (params: [String], variadic: Bool, closeIndex: Int)? {
        var params: [String] = []
        var variadic = false
        var k = 1
        while k < tokens.count {
            let t = tokens[k]
            switch t.kind {
            case .Separator(.CloseParen):
                return (params, variadic, k)
            case .Separator(.Comma):
                k += 1
            case .Operator(.DotDotDot):
                variadic = true
                k += 1
            case .Identifier:
                params.append(t.value)
                k += 1
            default:
                emitError("expected parameter name in #define", at: t)
                return nil
            }
        }
        emitError("expected ')' in #define", at: name)
        return nil
    }

    private func handleUndef(args: [Token], name: Token) {
        guard active else { return }
        guard let first = args.first, first.kind == .Identifier else {
            emitError("expected macro name after #undef", at: name)
            return
        }
        macros.removeValue(forKey: first.value)
    }

    private func expandToken(
        _ token: Token, tokens: [Token], at index: Int
    ) -> (tokens: [Token], nextIndex: Int) {
        if let builtin = builtinExpansion(token) {
            return (builtin, index + 1)
        }
        guard token.kind == .Identifier, let macro = macros[token.value],
              !self.expanding.contains(token.value)
        else {
            return ([token], index + 1)
        }
        switch macro {
        case let .Object(nameToken, body):
            let expanded = expandMacro(token.value, body: body, at: token)
            return (relocate(expanded, to: token, site: site(of: nameToken)), index + 1)
        case let .Function(nameToken, params, variadic, body):
            guard index + 1 < tokens.count, tokens[index + 1].kind == .Separator(.OpenParen)
            else {
                return ([token], index + 1)
            }
            guard let (rawArgs, closeIndex) = collectArguments(tokens, from: index + 1) else {
                emitError("unterminated argument list for macro '\(token.value)'", at: token)
                return ([token], index + 1)
            }
            let args = params.isEmpty ? emptyCallArgs(rawArgs) : rawArgs
            let (expanded, tailIsMacro) = expandFunctionMacro(
                name: token.value, params: params, variadic: variadic, body: body, args: args,
                at: token
            )
            guard let expanded else {
                return ([token], index + 1)
            }
            let tail =
                tailIsMacro
                    ? expandTail(expanded, tokens: tokens, at: closeIndex + 1)
                    : (tokens: expanded, nextIndex: closeIndex + 1)
            return (
                relocate(tail.tokens, to: token, site: site(of: nameToken)),
                tail.nextIndex
            )
        }
    }

    private func expandTail(
        _ expanded: [Token], tokens: [Token], at index: Int
    ) -> (tokens: [Token], nextIndex: Int) {
        guard let last = expanded.last, last.kind == .Identifier,
              let macro = macros[last.value], !self.expanding.contains(last.value)
        else {
            return (expanded, index)
        }
        switch macro {
        case let .Function(_, params, variadic, body):
            guard index < tokens.count, tokens[index].kind == .Separator(.OpenParen) else {
                return (expanded, index)
            }
            guard let (rawArgs, closeIndex) = collectArguments(tokens, from: index) else {
                emitError("unterminated argument list for macro '\(last.value)'", at: last)
                return (expanded, index)
            }
            let args = params.isEmpty ? emptyCallArgs(rawArgs) : rawArgs
            let (result, _) = expandFunctionMacro(
                name: last.value, params: params, variadic: variadic, body: body, args: args,
                at: last
            )
            guard let result else {
                return (expanded, index)
            }
            return expandTail(
                Array(expanded.dropLast()) + result, tokens: tokens, at: closeIndex + 1
            )
        case .Object:
            return (expanded, index)
        }
    }

    private func emptyCallArgs(_ args: [[Token]]) -> [[Token]] {
        if args.count == 1, args[0].isEmpty {
            return []
        }
        return args
    }

    private func site(of nameToken: Token) -> MacroExpansionSite {
        MacroExpansionSite(
            name: nameToken.value, definitionPosition: nameToken.pos,
            definitionSourceId: nameToken.id
        )
    }

    private func relocate(_ tokens: [Token], to token: Token, site: MacroExpansionSite)
        -> [Token]
    {
        tokens.map { t in
            Token(
                value: t.value, kind: t.kind, pos: token.pos, id: token.id,
                isUnterminated: t.isUnterminated, expansion: (t.expansion ?? []) + [site]
            )
        }
    }

    private func collectArguments(
        _ tokens: [Token], from openParenIndex: Int
    ) -> (args: [[Token]], closeIndex: Int)? {
        var args: [[Token]] = []
        var current: [Token] = []
        var depth = 0
        var k = openParenIndex + 1
        while k < tokens.count {
            let t = tokens[k]
            if t.kind == .Separator(.OpenParen) {
                depth += 1
                current.append(t)
            } else if t.kind == .Separator(.CloseParen) {
                if depth == 0 {
                    args.append(current)
                    return (args, k)
                }
                depth -= 1
                current.append(t)
            } else if t.kind == .Separator(.Comma), depth == 0 {
                args.append(current)
                current = []
            } else {
                current.append(t)
            }
            k += 1
        }
        return nil
    }

    private func expandFunctionMacro(
        name: String, params: [String], variadic: Bool, body: [Token], args: [[Token]],
        at token: Token
    ) -> (tokens: [Token]?, tailIsMacro: Bool) {
        if variadic {
            guard args.count >= params.count else {
                emitError("too few arguments for macro '\(name)'", at: token)
                emitNote("macro '\(name)' defined here", at: body.first ?? token)
                return (nil, false)
            }
        } else {
            guard args.count == params.count else {
                emitError(
                    "macro '\(name)' expects \(params.count) arguments, but got \(args.count)",
                    at: token
                )
                emitNote("macro '\(name)' defined here", at: body.first ?? token)
                return (nil, false)
            }
        }
        let expandedArgs = args.map { self.rescan($0) }
        let pastedBody = pasteTokensInBody(body, params: params, args: args)
        var replaced: [Token] = []
        var k = 0
        while k < pastedBody.count {
            let bt = pastedBody[k]
            if bt.kind == .Separator(.Sharp), k + 1 < pastedBody.count {
                if let paramIndex = params.firstIndex(of: pastedBody[k + 1].value) {
                    let text = args[paramIndex].map(\.value).joined(separator: " ")
                    replaced.append(
                        Token(value: text, kind: .StringLiteral, pos: bt.pos, id: bt.id)
                    )
                    k += 2
                    continue
                }
                if variadic, pastedBody[k + 1].kind == .Identifier,
                   pastedBody[k + 1].value == "__VA_ARGS__"
                {
                    let text = args.dropFirst(params.count).flatMap { $0 }.map(\.value)
                        .joined(separator: ", ")
                    replaced.append(
                        Token(value: text, kind: .StringLiteral, pos: bt.pos, id: bt.id)
                    )
                    k += 2
                    continue
                }
            }
            if bt.kind == .Identifier, let paramIndex = params.firstIndex(of: bt.value) {
                replaced.append(contentsOf: expandedArgs[paramIndex])
                k += 1
                continue
            }
            if variadic, bt.kind == .Identifier, bt.value == "__VA_ARGS__" {
                let variadicArgs = expandedArgs.dropFirst(params.count)
                var first = true
                for va in variadicArgs {
                    if !first {
                        replaced.append(
                            Token(value: ",", kind: .Separator(.Comma), pos: bt.pos, id: bt.id)
                        )
                    }
                    replaced.append(contentsOf: va)
                    first = false
                }
                k += 1
                continue
            }
            replaced.append(bt)
            k += 1
        }
        let result = rescan(replaced)
        if result.isEmpty {
            return ([placeholder(at: token)], false)
        }
        let tailIsMacro =
            replaced.last?.kind == .Identifier
                && macros[replaced.last!.value] != nil
        return (result, tailIsMacro)
    }

    private func pasteTokensInBody(
        _ body: [Token], params: [String], args: [[Token]]
    ) -> [Token] {
        var result: [Token] = []
        var k = 0
        while k < body.count {
            if k + 1 < body.count, body[k].kind == .Separator(.Sharp),
               body[k + 1].kind == .Separator(.Sharp)
            {
                guard k + 2 < body.count else {
                    emitError("expected token after '##' in macro body", at: body[k])
                    k += 2
                    continue
                }
                let leftBodyToken = result.removeLast()
                let leftTokens = pasteOperand(leftBodyToken, params: params, args: args)
                let rightTokens = pasteOperand(body[k + 2], params: params, args: args)
                if let left = leftTokens.last, let right = rightTokens.first {
                    if let pasted = pasteTokens(left, right, at: body[k]) {
                        result.append(pasted)
                    } else {
                        result.append(contentsOf: leftTokens)
                        result.append(contentsOf: rightTokens)
                    }
                } else {
                    result.append(contentsOf: leftTokens)
                    result.append(contentsOf: rightTokens)
                }
                k += 3
                continue
            }
            result.append(body[k])
            k += 1
        }
        return result
    }

    private func pasteOperand(
        _ token: Token, params: [String], args: [[Token]]
    ) -> [Token] {
        if token.kind == .Identifier, let paramIndex = params.firstIndex(of: token.value) {
            return args[paramIndex]
        }
        return [token]
    }

    private func pasteTokens(_ left: Token, _ right: Token, at token: Token) -> Token? {
        let text = left.value + right.value
        guard let kind = pastedKind(text, id: token.id) else {
            emitError("invalid token formed by '##' paste", at: token)
            return nil
        }
        return Token(value: text, kind: kind, pos: token.pos, id: token.id)
    }

    private func pastedKind(_ text: String, id: Id.SourceId) -> TokenKind? {
        let stream = CharStream(content: text, id: id)
        let tokens = Lexer(input: stream).parse().tokens
        guard tokens.count == 1 else { return nil }
        return tokens[0].kind
    }

    private func builtinExpansion(_ token: Token) -> [Token]? {
        guard token.kind == .Identifier else { return nil }
        switch token.value {
        case "__FILE__":
            let filepath = context.sourceTable[token.id]?.filepath ?? ""
            return [Token(value: filepath, kind: .StringLiteral, pos: token.pos, id: token.id)]
        case "__LINE__":
            return [
                Token(
                    value: String(token.pos.line),
                    kind: .IntegerLiteral(Int128(token.pos.line)), pos: token.pos, id: token.id
                ),
            ]
        case "__DATE__", "__TIME__":
            return [Self.compilationTimeToken(date: token.value == "__DATE__", at: token)]
        default:
            return nil
        }
    }

    private static let monthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    private static func compilationTimeToken(date: Bool, at token: Token) -> Token {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date()
        )
        let text: String
        if date {
            let day = String(format: "%2d", components.day!)
            text = "\(monthNames[components.month! - 1]) \(day) \(components.year!)"
        } else {
            text = String(
                format: "%02d:%02d:%02d",
                components.hour!, components.minute!, components.second!
            )
        }
        return Token(value: text, kind: .StringLiteral, pos: token.pos, id: token.id)
    }

    private func expandMacro(_ name: String, body: [Token], at token: Token) -> [Token] {
        expanding.append(name)
        let result = rescan(body)
        expanding.removeLast()
        return result.isEmpty ? [placeholder(at: token)] : result
    }

    private func placeholder(at token: Token) -> Token {
        Token(value: "", kind: .Unknown, pos: token.pos, id: token.id)
    }

    private func isPlaceholder(_ token: Token) -> Bool {
        token.kind == .Unknown && token.value.isEmpty
    }

    private func rescan(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var k = 0
        while k < tokens.count {
            let expanded = expandToken(tokens[k], tokens: tokens, at: k)
            result.append(contentsOf: expanded.tokens)
            k = expanded.nextIndex
        }
        return result.filter { !self.isPlaceholder($0) }
    }

    private func directiveArgs(
        _ tokens: [Token], from start: Int, directiveLine: Int, stopAtSharp: Bool = true
    ) -> [Token] {
        var args: [Token] = []
        var k = start
        while k < tokens.count {
            let t = tokens[k]
            if stopAtSharp, t.kind == .Separator(.Sharp) { break }
            if t.pos.line > directiveLine { break }
            args.append(t)
            k += 1
        }
        return args
    }

    private func evaluateCondition(
        _ tokens: [Token], at directiveToken: Token
    ) -> Bool? {
        let replaced = replaceDefined(tokens)
        let expanded = rescan(replaced).filter { !self.isPlaceholder($0) }
        var evaluator = ConditionEvaluator(
            tokens: expanded, flags: config.flags,
            target: TargetInfo(target: config.target),
            directiveToken: directiveToken,
            onError: { message, token in self.emitError(message, at: token) }
        )
        return evaluator.evaluate()
    }

    private func replaceDefined(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var k = 0
        while k < tokens.count {
            let token = tokens[k]
            if token.kind == .Identifier, token.value == "defined" {
                let name: String?
                if k + 1 < tokens.count, tokens[k + 1].kind == .Separator(.OpenParen),
                   k + 2 < tokens.count, tokens[k + 2].kind == .Identifier,
                   k + 3 < tokens.count, tokens[k + 3].kind == .Separator(.CloseParen)
                {
                    name = tokens[k + 2].value
                    k += 4
                } else if k + 1 < tokens.count, tokens[k + 1].kind == .Identifier {
                    name = tokens[k + 1].value
                    k += 2
                } else {
                    name = nil
                    k += 1
                }
                if let name {
                    if isDefined(name) {
                        result.append(
                            Token(
                                value: "1", kind: .IntegerLiteral(1), pos: token.pos, id: token.id
                            )
                        )
                    } else {
                        result.append(
                            Token(
                                value: "0", kind: .IntegerLiteral(0), pos: token.pos, id: token.id
                            )
                        )
                    }
                } else {
                    result.append(token)
                }
            } else {
                result.append(token)
                k += 1
            }
        }
        return result
    }

    private func emitError(_ message: String, at token: Token) {
        emitDiagnostic(.error, message: message, at: token)
    }

    private func emitNote(_ message: String, at token: Token) {
        emitDiagnostic(.note, message: message, at: token)
    }

    private func emitDiagnostic(
        _ severity: DiagnosticSeverity, message: String, at token: Token
    ) {
        guard let source = context.sourceTable[token.id] else { return }
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: severity, message: message,
                range: token.sourceRange(in: source.stringSourceBuffer),
                notes: token.expansionNotes(in: context)
            )
        )
    }
}

private struct TargetInfo {
    let arch: String
    let os: String
    let simulator: Bool
    init(target: String) {
        let parts = target.split(separator: "-").map(String.init)
        arch = parts.first ?? ""
        simulator = parts.contains("simulator")
        os = TargetInfo.osName(parts.count > 2 ? parts[2] : "")
    }

    private static func osName(_ raw: String) -> String {
        if raw.hasPrefix("linux") { return "Linux" }
        if raw.hasPrefix("darwin") || raw.hasPrefix("macos") { return "macOS" }
        if raw.hasPrefix("windows") { return "Windows" }
        if raw.hasPrefix("freebsd") { return "FreeBSD" }
        if raw.hasPrefix("ios") { return "iOS" }
        if raw.hasPrefix("android") { return "Android" }
        return raw
    }
}

private struct ConditionEvaluator {
    let tokens: [Token]
    let flags: Set<String>
    let target: TargetInfo
    let directiveToken: Token
    let onError: (String, Token) -> Void
    var index = 0

    mutating func evaluate() -> Bool? {
        if tokens.isEmpty {
            onError("expected expression in #if condition", directiveToken)
            return nil
        }
        guard let value = parseOrExpr() else { return nil }
        if index != tokens.count {
            let token = tokens[index]
            onError("unexpected token '\(token.value)' in #if condition", token)
            return nil
        }
        return value != 0
    }

    private mutating func parseOrExpr() -> Int128? {
        guard var value = parseAndExpr() else { return nil }
        while index < tokens.count, tokens[index].kind == .Operator(.Or) {
            index += 1
            if value != 0 {
                guard skipUntil(.Or) else { return nil }
            } else {
                guard let rhs = parseAndExpr() else { return nil }
                value = rhs != 0 ? 1 : 0
            }
        }
        return value
    }

    private mutating func parseAndExpr() -> Int128? {
        guard var value = parseBitOr() else { return nil }
        while index < tokens.count, tokens[index].kind == .Operator(.And) {
            index += 1
            if value == 0 {
                guard skipUntil(.And, .Or) else { return nil }
            } else {
                guard let rhs = parseBitOr() else { return nil }
                value = rhs != 0 ? 1 : 0
            }
        }
        return value
    }

    private mutating func skipUntil(_ operators: OperatorKind...) -> Bool {
        var depth = 0
        while index < tokens.count {
            let token = tokens[index]
            if depth == 0 {
                if case let .Operator(op) = token.kind,
                   operators.contains(where: { $0 == op })
                {
                    return true
                }
                if token.kind == .Separator(.CloseParen) {
                    return true
                }
                if token.kind == .Separator(.OpenParen) {
                    depth += 1
                }
            } else {
                if token.kind == .Separator(.OpenParen) {
                    depth += 1
                } else if token.kind == .Separator(.CloseParen) {
                    depth -= 1
                }
            }
            index += 1
        }
        return true
    }

    private mutating func parseBitOr() -> Int128? {
        guard var value = parseBitXor() else { return nil }
        while index < tokens.count, tokens[index].kind == .Operator(.BitOr) {
            index += 1
            guard let rhs = parseBitXor() else { return nil }
            value = value | rhs
        }
        return value
    }

    private mutating func parseBitXor() -> Int128? {
        guard var value = parseBitAnd() else { return nil }
        while index < tokens.count, tokens[index].kind == .Operator(.BitXor) {
            index += 1
            guard let rhs = parseBitAnd() else { return nil }
            value = value ^ rhs
        }
        return value
    }

    private mutating func parseBitAnd() -> Int128? {
        guard var value = parseEquality() else { return nil }
        while index < tokens.count, tokens[index].kind == .Operator(.BitAnd) {
            index += 1
            guard let rhs = parseEquality() else { return nil }
            value = value & rhs
        }
        return value
    }

    private mutating func parseEquality() -> Int128? {
        guard var value = parseRelational() else { return nil }
        while index < tokens.count {
            let op = tokens[index].kind
            if op == .Operator(.Equal) {
                index += 1
                guard let rhs = parseRelational() else { return nil }
                value = value == rhs ? 1 : 0
            } else if op == .Operator(.NotEqual) {
                index += 1
                guard let rhs = parseRelational() else { return nil }
                value = value != rhs ? 1 : 0
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseRelational() -> Int128? {
        guard var value = parseShift() else { return nil }
        while index < tokens.count {
            let op = tokens[index].kind
            switch op {
            case .Operator(.Less):
                index += 1
                guard let rhs = parseShift() else { return nil }
                value = value < rhs ? 1 : 0
            case .Operator(.Greater):
                index += 1
                guard let rhs = parseShift() else { return nil }
                value = value > rhs ? 1 : 0
            case .Operator(.LessEqual):
                index += 1
                guard let rhs = parseShift() else { return nil }
                value = value <= rhs ? 1 : 0
            case .Operator(.GreaterEqual):
                index += 1
                guard let rhs = parseShift() else { return nil }
                value = value >= rhs ? 1 : 0
            default:
                return value
            }
        }
        return value
    }

    private mutating func parseShift() -> Int128? {
        guard var value = parseAdditive() else { return nil }
        while index < tokens.count {
            let op = tokens[index].kind
            if op == .Operator(.LeftShift) || op == .Operator(.RightShift) {
                let isLeft = op == .Operator(.LeftShift)
                index += 1
                guard let rhs = parseAdditive() else { return nil }
                guard rhs >= 0, rhs < 128 else {
                    onError(
                        "shift count out of range in #if condition", tokens[index - 1]
                    )
                    return nil
                }
                value = isLeft ? value << rhs : value >> rhs
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseAdditive() -> Int128? {
        guard var value = parseMultiplicative() else { return nil }
        while index < tokens.count {
            let op = tokens[index].kind
            if op == .Operator(.Plus) {
                index += 1
                guard let rhs = parseMultiplicative() else { return nil }
                value = value &+ rhs
            } else if op == .Operator(.Minus) {
                index += 1
                guard let rhs = parseMultiplicative() else { return nil }
                value = value &- rhs
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseMultiplicative() -> Int128? {
        guard var value = parseUnary() else { return nil }
        while index < tokens.count {
            let op = tokens[index].kind
            switch op {
            case .Operator(.Multiply):
                index += 1
                guard let rhs = parseUnary() else { return nil }
                value = value &* rhs
            case .Operator(.Divide):
                index += 1
                guard let rhs = parseUnary() else { return nil }
                guard rhs != 0 else {
                    onError("division by zero in #if condition", tokens[index - 1])
                    return nil
                }
                value = value / rhs
            case .Operator(.Modulus):
                index += 1
                guard let rhs = parseUnary() else { return nil }
                guard rhs != 0 else {
                    onError("division by zero in #if condition", tokens[index - 1])
                    return nil
                }
                value = value % rhs
            default:
                return value
            }
        }
        return value
    }

    private mutating func parseUnary() -> Int128? {
        guard index < tokens.count else {
            onError("expected expression in #if condition", tokens.last!)
            return nil
        }
        let op = tokens[index].kind
        switch op {
        case .Operator(.Not):
            index += 1
            guard let value = parseUnary() else { return nil }
            return value == 0 ? 1 : 0
        case .Operator(.BitNot):
            index += 1
            guard let value = parseUnary() else { return nil }
            return ~value
        case .Operator(.Minus):
            index += 1
            guard let value = parseUnary() else { return nil }
            return 0 &- value
        case .Operator(.Plus):
            index += 1
            return parseUnary()
        default:
            return parsePrimary()
        }
    }

    private mutating func parseConditionFunction() -> Int128? {
        let fn = tokens[index]
        let name = fn.value
        guard name == "os" || name == "arch" || name == "targetEnvironment" else {
            onError("unknown function '\(name)' in #if condition", fn)
            return nil
        }
        index += 2
        guard index < tokens.count,
              tokens[index].kind == .Identifier
        else {
            onError("expected argument in '\(name)' condition", fn)
            return nil
        }
        let arg = tokens[index].value
        index += 1
        guard index < tokens.count,
              tokens[index].kind == .Separator(.CloseParen)
        else {
            onError("expected ')' after '\(name)' argument", fn)
            return nil
        }
        index += 1
        switch name {
        case "os":
            return arg.lowercased() == target.os.lowercased() ? 1 : 0
        case "arch":
            return arg.lowercased() == target.arch.lowercased() ? 1 : 0
        default:
            return arg == "simulator" && target.simulator ? 1 : 0
        }
    }

    private mutating func parsePrimary() -> Int128? {
        guard index < tokens.count else {
            onError("expected expression in #if condition", tokens.last!)
            return nil
        }
        let token = tokens[index]
        switch token.kind {
        case let .IntegerLiteral(value):
            index += 1
            return value
        case let .CharLiteral(ch):
            index += 1
            return Int128(ch.unicodeScalars.first?.value ?? 0)
        case let .BooleanLiteral(value):
            index += 1
            return value ? 1 : 0
        case .Identifier:
            if index + 1 < tokens.count,
               tokens[index + 1].kind == .Separator(.OpenParen)
            {
                return parseConditionFunction()
            }
            index += 1
            return flags.contains(token.value) ? 1 : 0
        case .Separator(.OpenParen):
            index += 1
            guard let value = parseOrExpr() else { return nil }
            guard index < tokens.count,
                  tokens[index].kind == .Separator(.CloseParen)
            else {
                onError("expected ')' in #if condition", token)
                return nil
            }
            index += 1
            return value
        default:
            onError("unexpected token '\(token.value)' in #if condition", token)
            return nil
        }
    }
}
