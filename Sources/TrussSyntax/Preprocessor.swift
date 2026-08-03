import SwiftBetterDiagnostic
import TrussCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct PreprocessorConfig {
    public let flags: Set<String>
    public let target: String
    public init(flags: Set<String> = [], target: String = "x86_64-unknown-linux-gnu") {
        self.flags = flags
        self.target = target
    }
}

private struct ConditionFrame {
    let parentActive: Bool
    var branchTaken: Bool
}

private enum Macro {
    case object(tokens: [Token])
    case function(params: [String], variadic: Bool, tokens: [Token])
}

public final class Preprocessor {
    private let context: Context

    private final class State {
        let config: PreprocessorConfig
        var output: [Token] = []
        var index = 0
        var active = true
        var frames: [ConditionFrame] = []
        var outerIfToken: Token? = nil
        var macros: [String: Macro] = [:]
        var expanding: [String] = []
        init(config: PreprocessorConfig) {
            self.config = config
        }
    }

    public init(context: Context) {
        self.context = context
    }

    public func process(_ tokens: [Token], config: PreprocessorConfig) -> [Token] {
        let state = State(config: config)
        while state.index < tokens.count {
            let token = tokens[state.index]
            if token.kind == .Separator(.Sharp) {
                if !self.handleDirective(state, tokens: tokens) {
                    self.emitError("unknown preprocessing directive", at: token)
                    state.index += 1
                }
                continue
            }
            if state.active {
                let result = self.expandToken(token, tokens: tokens, at: state.index, state: state)
                state.output.append(contentsOf: result.tokens)
                state.index = result.nextIndex
            } else {
                state.index += 1
            }
        }
        if let token = state.outerIfToken {
            self.emitError("unterminated #if directive", at: token)
        }
        return state.output
    }

    private func handleDirective(_ state: State, tokens: [Token]) -> Bool {
        guard state.index + 1 < tokens.count else { return false }
        let sharp = tokens[state.index]
        let name = tokens[state.index + 1]
        switch name.kind {
        case .Keyword(.If):
            let args = self.directiveArgs(
                tokens, from: state.index + 2, directiveLine: name.pos.line)
            state.index = state.index + 2 + args.count
            let value = self.evaluateCondition(args, state: state, at: name)
            let errored = value == nil
            let taken = errored || (value ?? false)
            if state.outerIfToken == nil { state.outerIfToken = sharp }
            state.frames.append(ConditionFrame(parentActive: state.active, branchTaken: taken))
            state.active = state.active && !errored && (value ?? false)
            return true
        case .Keyword(.Else):
            state.index += 2
            self.handleElse(state, sharp: sharp)
            return true
        case .Identifier:
            switch name.value {
            case "elseif":
                let args = self.directiveArgs(
                    tokens, from: state.index + 2, directiveLine: name.pos.line)
                state.index = state.index + 2 + args.count
                self.handleElseIf(state, args: args, name: name, sharp: sharp)
                return true
            case "endif":
                state.index += 2
                self.handleEndIf(state, sharp: sharp)
                return true
            case "ifdef":
                let args = self.directiveArgs(
                    tokens, from: state.index + 2, directiveLine: name.pos.line)
                state.index = state.index + 2 + args.count
                self.handleIfDef(state, args: args, name: name, sharp: sharp, negated: false)
                return true
            case "ifndef":
                let args = self.directiveArgs(
                    tokens, from: state.index + 2, directiveLine: name.pos.line)
                state.index = state.index + 2 + args.count
                self.handleIfDef(state, args: args, name: name, sharp: sharp, negated: true)
                return true
            case "error":
                let args = self.directiveArgs(
                    tokens, from: state.index + 2, directiveLine: name.pos.line)
                state.index = state.index + 2 + args.count
                self.handleErrorDirective(state, args: args, name: name, severity: .error)
                return true
            case "warning":
                let args = self.directiveArgs(
                    tokens, from: state.index + 2, directiveLine: name.pos.line)
                state.index = state.index + 2 + args.count
                self.handleErrorDirective(state, args: args, name: name, severity: .warning)
                return true
            case "define":
                let args = self.directiveArgs(
                    tokens, from: state.index + 2, directiveLine: name.pos.line,
                    stopAtSharp: false)
                state.index = state.index + 2 + args.count
                self.handleDefine(state, args: args, name: name)
                return true
            case "undef":
                let args = self.directiveArgs(
                    tokens, from: state.index + 2, directiveLine: name.pos.line)
                state.index = state.index + 2 + args.count
                self.handleUndef(state, args: args, name: name)
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private func handleElse(_ state: State, sharp: Token) {
        guard let frame = state.frames.last else {
            self.emitError("unexpected #else directive", at: sharp)
            return
        }
        if frame.branchTaken {
            state.active = false
        } else {
            state.frames[state.frames.count - 1].branchTaken = true
            state.active = frame.parentActive
        }
    }

    private func handleElseIf(
        _ state: State, args: [Token], name: Token, sharp: Token
    ) {
        guard let frame = state.frames.last else {
            self.emitError("unexpected #elseif directive", at: sharp)
            return
        }
        if !frame.branchTaken {
            let value = self.evaluateCondition(args, state: state, at: name)
            if let v = value {
                if v {
                    state.frames[state.frames.count - 1].branchTaken = true
                    state.active = frame.parentActive
                } else {
                    state.active = false
                }
            } else {
                state.active = false
            }
        } else {
            state.active = false
        }
    }

    private func handleIfDef(
        _ state: State, args: [Token], name: Token, sharp: Token, negated: Bool
    ) {
        if state.outerIfToken == nil { state.outerIfToken = sharp }
        guard let first = args.first, first.kind == .Identifier else {
            self.emitError(
                "expected macro name after #\(negated ? "ifndef" : "ifdef")", at: name)
            state.frames.append(ConditionFrame(parentActive: state.active, branchTaken: true))
            state.active = false
            return
        }
        let taken = self.isDefined(first.value, state: state) != negated
        state.frames.append(ConditionFrame(parentActive: state.active, branchTaken: taken))
        state.active = state.active && taken
    }

    private func isDefined(_ name: String, state: State) -> Bool {
        state.macros[name] != nil || state.config.flags.contains(name)
    }

    private func handleEndIf(_ state: State, sharp: Token) {
        guard !state.frames.isEmpty else {
            self.emitError("unexpected #endif directive", at: sharp)
            return
        }
        let frame = state.frames.removeLast()
        if state.frames.isEmpty {
            state.outerIfToken = nil
        }
        state.active = frame.parentActive
    }

    private func handleErrorDirective(
        _ state: State, args: [Token], name: Token, severity: DiagnosticSeverity
    ) {
        guard state.active else { return }
        guard let message = args.first(where: { $0.kind == .StringLiteral }) else {
            self.emitError(
                "expected string literal in \(severity == .error ? "#error" : "#warning") directive",
                at: name)
            return
        }
        self.emitDiagnostic(severity, message: message.value, at: name)
    }

    private func handleDefine(_ state: State, args: [Token], name: Token) {
        guard state.active else { return }
        guard let first = args.first, first.kind == .Identifier else {
            self.emitError("expected macro name after #define", at: name)
            return
        }
        let rest = Array(args.dropFirst())
        let isFunctionLike = rest.first?.kind == .Separator(.OpenParen)
            && first.pos.pos + first.pos.len == rest[0].pos.pos
        if isFunctionLike {
            guard let (params, variadic, closeIndex) = self.parseMacroParams(rest, state: state, name: name)
            else {
                return
            }
            state.macros[first.value] = .function(
                params: params, variadic: variadic, tokens: Array(rest.dropFirst(closeIndex + 1)))
        } else {
            state.macros[first.value] = .object(tokens: rest)
        }
    }

    private func parseMacroParams(
        _ tokens: [Token], state: State, name: Token
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
                self.emitError("expected parameter name in #define", at: t)
                return nil
            }
        }
        self.emitError("expected ')' in #define", at: name)
        return nil
    }

    private func handleUndef(_ state: State, args: [Token], name: Token) {
        guard state.active else { return }
        guard let first = args.first, first.kind == .Identifier else {
            self.emitError("expected macro name after #undef", at: name)
            return
        }
        state.macros.removeValue(forKey: first.value)
    }

    private func expandToken(
        _ token: Token, tokens: [Token], at index: Int, state: State
    ) -> (tokens: [Token], nextIndex: Int) {
        if let builtin = self.builtinExpansion(token, state: state) {
            return (builtin, index + 1)
        }
        guard token.kind == .Identifier, let macro = state.macros[token.value],
            !state.expanding.contains(token.value)
        else {
            return ([token], index + 1)
        }
        switch macro {
        case .object(let body):
            return (self.expandMacro(token.value, body: body, state: state), index + 1)
        case .function(let params, let variadic, let body):
            guard index + 1 < tokens.count, tokens[index + 1].kind == .Separator(.OpenParen)
            else {
                return ([token], index + 1)
            }
            guard let (args, closeIndex) = self.collectArguments(tokens, from: index + 1) else {
                self.emitError("unterminated argument list for macro '\(token.value)'", at: token)
                return ([token], index + 1)
            }
            guard let expanded = self.expandFunctionMacro(
                name: token.value, params: params, variadic: variadic, body: body, args: args,
                at: token, state: state)
            else {
                return ([token], index + 1)
            }
            return (expanded, closeIndex + 1)
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
        at token: Token, state: State
    ) -> [Token]? {
        if variadic {
            guard args.count >= params.count else {
                self.emitError("too few arguments for macro '\(name)'", at: token)
                self.emitNote("macro '\(name)' defined here", at: body.first ?? token)
                return nil
            }
        } else {
            guard args.count == params.count else {
                self.emitError(
                    "macro '\(name)' expects \(params.count) arguments, but got \(args.count)",
                    at: token)
                self.emitNote("macro '\(name)' defined here", at: body.first ?? token)
                return nil
            }
        }
        let expandedArgs = args.map { self.rescan($0, state: state) }
        let pastedBody = self.pasteTokensInBody(body, params: params, args: args, state: state)
        var replaced: [Token] = []
        var k = 0
        while k < pastedBody.count {
            let bt = pastedBody[k]
            if bt.kind == .Separator(.Sharp), k + 1 < pastedBody.count {
                if let paramIndex = params.firstIndex(of: pastedBody[k + 1].value) {
                    let text = args[paramIndex].map { $0.value }.joined(separator: " ")
                    replaced.append(
                        Token(value: text, kind: .StringLiteral, pos: bt.pos, id: bt.id))
                    k += 2
                    continue
                }
                if variadic, pastedBody[k + 1].kind == .Identifier,
                    pastedBody[k + 1].value == "__VA_ARGS__"
                {
                    let text = args.dropFirst(params.count).flatMap { $0 }.map { $0.value }
                        .joined(separator: ", ")
                    replaced.append(
                        Token(value: text, kind: .StringLiteral, pos: bt.pos, id: bt.id))
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
                            Token(value: ",", kind: .Separator(.Comma), pos: bt.pos, id: bt.id))
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
        return self.rescan(replaced, state: state)
    }

    private func pasteTokensInBody(
        _ body: [Token], params: [String], args: [[Token]], state: State
    ) -> [Token] {
        var result: [Token] = []
        var k = 0
        while k < body.count {
            if k + 1 < body.count, body[k].kind == .Separator(.Sharp),
                body[k + 1].kind == .Separator(.Sharp)
            {
                guard k + 2 < body.count else {
                    self.emitError("expected token after '##' in macro body", at: body[k])
                    k += 2
                    continue
                }
                let leftBodyToken = result.removeLast()
                let leftTokens = self.pasteOperand(leftBodyToken, params: params, args: args)
                let rightTokens = self.pasteOperand(body[k + 2], params: params, args: args)
                if let left = leftTokens.last, let right = rightTokens.first {
                    if let pasted = self.pasteTokens(left, right, at: body[k]) {
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
        guard let kind = self.pastedKind(text) else {
            self.emitError("invalid token formed by '##' paste", at: token)
            return nil
        }
        return Token(value: text, kind: kind, pos: token.pos, id: token.id)
    }

    private func pastedKind(_ text: String) -> TokenKind? {
        if let value = Int128(text) {
            return .IntegerLiteral(value)
        }
        if let first = text.first, first.isLetter || first == "_",
            text.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        {
            return .Identifier
        }
        return nil
    }

    private func builtinExpansion(_ token: Token, state: State) -> [Token]? {
        guard token.kind == .Identifier else { return nil }
        switch token.value {
        case "__FILE__":
            let filepath = context.sourceTable[token.id]?.filepath ?? ""
            return [Token(value: filepath, kind: .StringLiteral, pos: token.pos, id: token.id)]
        case "__LINE__":
            return [
                Token(
                    value: String(token.pos.line),
                    kind: .IntegerLiteral(Int128(token.pos.line)), pos: token.pos, id: token.id)
            ]
        case "__DATE__", "__TIME__":
            return [Self.compilationTimeToken(date: token.value == "__DATE__", at: token)]
        default:
            return nil
        }
    }

    private static func compilationTimeToken(date: Bool, at token: Token) -> Token {
        var t = time(nil)
        var tm = localtime(&t)!.pointee
        var buf = [CChar](repeating: 0, count: 64)
        let format = date ? "%b %e %Y" : "%H:%M:%S"
        strftime(&buf, buf.count, format, &tm)
        let text = String(cString: buf)
        return Token(value: text, kind: .StringLiteral, pos: token.pos, id: token.id)
    }

    private func expandMacro(_ name: String, body: [Token], state: State) -> [Token] {
        state.expanding.append(name)
        let result = self.rescan(body, state: state)
        state.expanding.removeLast()
        return result
    }

    private func rescan(_ tokens: [Token], state: State) -> [Token] {
        var result: [Token] = []
        var k = 0
        while k < tokens.count {
            let expanded = self.expandToken(tokens[k], tokens: tokens, at: k, state: state)
            result.append(contentsOf: expanded.tokens)
            k = expanded.nextIndex
        }
        return result
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
        _ tokens: [Token], state: State, at directiveToken: Token
    ) -> Bool? {
        let replaced = self.replaceDefined(tokens, state: state)
        let expanded = self.rescan(replaced, state: state)
        var evaluator = ConditionEvaluator(
            tokens: expanded, flags: state.config.flags,
            target: TargetInfo(target: state.config.target),
            directiveToken: directiveToken,
            onError: { message, token in self.emitError(message, at: token) })
        return evaluator.evaluate()
    }

    private func replaceDefined(_ tokens: [Token], state: State) -> [Token] {
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
                    if self.isDefined(name, state: state) {
                        result.append(
                            Token(value: "1", kind: .IntegerLiteral(1), pos: token.pos, id: token.id))
                    } else {
                        result.append(
                            Token(value: "0", kind: .IntegerLiteral(0), pos: token.pos, id: token.id))
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
        self.emitDiagnostic(.error, message: message, at: token)
    }

    private func emitNote(_ message: String, at token: Token) {
        self.emitDiagnostic(.note, message: message, at: token)
    }

    private func emitDiagnostic(
        _ severity: DiagnosticSeverity, message: String, at token: Token
    ) {
        guard let source = context.sourceTable[token.id] else { return }
        context.diagnositicEngine.emit(
            Diagnostic(
                severity: severity, message: message,
                range: token.sourceRange(in: source.stringSourceBuffer)))
    }
}

private struct TargetInfo {
    let arch: String
    let os: String
    let simulator: Bool
    init(target: String) {
        let parts = target.split(separator: "-").map(String.init)
        self.arch = parts.first ?? ""
        self.simulator = parts.contains("simulator")
        self.os = TargetInfo.osName(parts.count > 2 ? parts[2] : "")
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
        if self.tokens.isEmpty {
            self.onError("expected expression in #if condition", self.directiveToken)
            return nil
        }
        guard let value = self.parseOrExpr() else { return nil }
        if self.index != self.tokens.count {
            let token = self.tokens[self.index]
            self.onError("unexpected token '\(token.value)' in #if condition", token)
            return nil
        }
        return value != 0
    }

    private mutating func parseOrExpr() -> Int128? {
        guard var value = self.parseAndExpr() else { return nil }
        while self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.Or) {
            self.index += 1
            if value != 0 {
                guard self.skipUntil(.Or) else { return nil }
            } else {
                guard let rhs = self.parseAndExpr() else { return nil }
                value = rhs != 0 ? 1 : 0
            }
        }
        return value
    }

    private mutating func parseAndExpr() -> Int128? {
        guard var value = self.parseBitOr() else { return nil }
        while self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.And) {
            self.index += 1
            if value == 0 {
                guard self.skipUntil(.And, .Or) else { return nil }
            } else {
                guard let rhs = self.parseBitOr() else { return nil }
                value = rhs != 0 ? 1 : 0
            }
        }
        return value
    }

    private mutating func skipUntil(_ operators: OperatorKind...) -> Bool {
        var depth = 0
        while self.index < self.tokens.count {
            let token = self.tokens[self.index]
            if depth == 0 {
                if case .Operator(let op) = token.kind,
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
            self.index += 1
        }
        return true
    }

    private mutating func parseBitOr() -> Int128? {
        guard var value = self.parseBitXor() else { return nil }
        while self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.BitOr) {
            self.index += 1
            guard let rhs = self.parseBitXor() else { return nil }
            value = value | rhs
        }
        return value
    }

    private mutating func parseBitXor() -> Int128? {
        guard var value = self.parseBitAnd() else { return nil }
        while self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.BitXor) {
            self.index += 1
            guard let rhs = self.parseBitAnd() else { return nil }
            value = value ^ rhs
        }
        return value
    }

    private mutating func parseBitAnd() -> Int128? {
        guard var value = self.parseEquality() else { return nil }
        while self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.BitAnd) {
            self.index += 1
            guard let rhs = self.parseEquality() else { return nil }
            value = value & rhs
        }
        return value
    }

    private mutating func parseEquality() -> Int128? {
        guard var value = self.parseRelational() else { return nil }
        while self.index < self.tokens.count {
            let op = self.tokens[self.index].kind
            if op == .Operator(.Equal) {
                self.index += 1
                guard let rhs = self.parseRelational() else { return nil }
                value = value == rhs ? 1 : 0
            } else if op == .Operator(.NotEqual) {
                self.index += 1
                guard let rhs = self.parseRelational() else { return nil }
                value = value != rhs ? 1 : 0
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseRelational() -> Int128? {
        guard var value = self.parseShift() else { return nil }
        while self.index < self.tokens.count {
            let op = self.tokens[self.index].kind
            switch op {
            case .Operator(.Less):
                self.index += 1
                guard let rhs = self.parseShift() else { return nil }
                value = value < rhs ? 1 : 0
            case .Operator(.Greater):
                self.index += 1
                guard let rhs = self.parseShift() else { return nil }
                value = value > rhs ? 1 : 0
            case .Operator(.LessEqual):
                self.index += 1
                guard let rhs = self.parseShift() else { return nil }
                value = value <= rhs ? 1 : 0
            case .Operator(.GreaterEqual):
                self.index += 1
                guard let rhs = self.parseShift() else { return nil }
                value = value >= rhs ? 1 : 0
            default:
                return value
            }
        }
        return value
    }

    private mutating func parseShift() -> Int128? {
        guard var value = self.parseAdditive() else { return nil }
        while self.index < self.tokens.count {
            let op = self.tokens[self.index].kind
            if op == .Operator(.LeftShift) || op == .Operator(.RightShift) {
                let isLeft = op == .Operator(.LeftShift)
                self.index += 1
                guard let rhs = self.parseAdditive() else { return nil }
                guard rhs >= 0, rhs < 128 else {
                    self.onError("shift count out of range in #if condition", self.tokens[self.index - 1])
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
        guard var value = self.parseMultiplicative() else { return nil }
        while self.index < self.tokens.count {
            let op = self.tokens[self.index].kind
            if op == .Operator(.Plus) {
                self.index += 1
                guard let rhs = self.parseMultiplicative() else { return nil }
                value = value &+ rhs
            } else if op == .Operator(.Minus) {
                self.index += 1
                guard let rhs = self.parseMultiplicative() else { return nil }
                value = value &- rhs
            } else {
                break
            }
        }
        return value
    }

    private mutating func parseMultiplicative() -> Int128? {
        guard var value = self.parseUnary() else { return nil }
        while self.index < self.tokens.count {
            let op = self.tokens[self.index].kind
            switch op {
            case .Operator(.Multiply):
                self.index += 1
                guard let rhs = self.parseUnary() else { return nil }
                value = value &* rhs
            case .Operator(.Divide):
                self.index += 1
                guard let rhs = self.parseUnary() else { return nil }
                guard rhs != 0 else {
                    self.onError("division by zero in #if condition", self.tokens[self.index - 1])
                    return nil
                }
                value = value / rhs
            case .Operator(.Modulus):
                self.index += 1
                guard let rhs = self.parseUnary() else { return nil }
                guard rhs != 0 else {
                    self.onError("division by zero in #if condition", self.tokens[self.index - 1])
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
        guard self.index < self.tokens.count else {
            self.onError("expected expression in #if condition", self.tokens.last!)
            return nil
        }
        let op = self.tokens[self.index].kind
        switch op {
        case .Operator(.Not):
            self.index += 1
            guard let value = self.parseUnary() else { return nil }
            return value == 0 ? 1 : 0
        case .Operator(.BitNot):
            self.index += 1
            guard let value = self.parseUnary() else { return nil }
            return ~value
        case .Operator(.Minus):
            self.index += 1
            guard let value = self.parseUnary() else { return nil }
            return 0 &- value
        case .Operator(.Plus):
            self.index += 1
            return self.parseUnary()
        default:
            return self.parsePrimary()
        }
    }

    private mutating func parseConditionFunction() -> Int128? {
        let fn = self.tokens[self.index]
        let name = fn.value
        guard name == "os" || name == "arch" || name == "targetEnvironment" else {
            self.onError("unknown function '\(name)' in #if condition", fn)
            return nil
        }
        self.index += 2
        guard self.index < self.tokens.count,
            self.tokens[self.index].kind == .Identifier
        else {
            self.onError("expected argument in '\(name)' condition", fn)
            return nil
        }
        let arg = self.tokens[self.index].value
        self.index += 1
        guard self.index < self.tokens.count,
            self.tokens[self.index].kind == .Separator(.CloseParen)
        else {
            self.onError("expected ')' after '\(name)' argument", fn)
            return nil
        }
        self.index += 1
        switch name {
        case "os":
            return arg.lowercased() == self.target.os.lowercased() ? 1 : 0
        case "arch":
            return arg.lowercased() == self.target.arch.lowercased() ? 1 : 0
        default:
            return arg == "simulator" && self.target.simulator ? 1 : 0
        }
    }

    private mutating func parsePrimary() -> Int128? {
        guard self.index < self.tokens.count else {
            self.onError("expected expression in #if condition", self.tokens.last!)
            return nil
        }
        let token = self.tokens[self.index]
        switch token.kind {
        case .IntegerLiteral(let value):
            self.index += 1
            return value
        case .CharLiteral(let ch):
            self.index += 1
            return Int128(ch.unicodeScalars.first?.value ?? 0)
        case .BooleanLiteral(let value):
            self.index += 1
            return value ? 1 : 0
        case .Identifier:
            if self.index + 1 < self.tokens.count,
                self.tokens[self.index + 1].kind == .Separator(.OpenParen)
            {
                return self.parseConditionFunction()
            }
            self.index += 1
            return self.flags.contains(token.value) ? 1 : 0
        case .Separator(.OpenParen):
            self.index += 1
            guard let value = self.parseOrExpr() else { return nil }
            guard self.index < self.tokens.count,
                self.tokens[self.index].kind == .Separator(.CloseParen)
            else {
                self.onError("expected ')' in #if condition", token)
                return nil
            }
            self.index += 1
            return value
        default:
            self.onError("unexpected token '\(token.value)' in #if condition", token)
            return nil
        }
    }
}
