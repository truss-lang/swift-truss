import SwiftBetterDiagnostic
import TrussCore

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
                state.output.append(contentsOf: self.expandToken(token, state: state))
            }
            state.index += 1
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
                    tokens, from: state.index + 2, directiveLine: name.pos.line)
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
        state.macros[first.value] = .object(tokens: Array(args.dropFirst()))
    }

    private func handleUndef(_ state: State, args: [Token], name: Token) {
        guard state.active else { return }
        guard let first = args.first, first.kind == .Identifier else {
            self.emitError("expected macro name after #undef", at: name)
            return
        }
        state.macros.removeValue(forKey: first.value)
    }

    private func expandToken(_ token: Token, state: State) -> [Token] {
        guard token.kind == .Identifier, let macro = state.macros[token.value],
            !state.expanding.contains(token.value)
        else {
            return [token]
        }
        switch macro {
        case .object(let body):
            return self.expandMacro(token.value, body: body, state: state)
        }
    }

    private func expandMacro(_ name: String, body: [Token], state: State) -> [Token] {
        state.expanding.append(name)
        let result = self.rescan(body, state: state)
        state.expanding.removeLast()
        return result
    }

    private func rescan(_ tokens: [Token], state: State) -> [Token] {
        var result: [Token] = []
        for token in tokens {
            result.append(contentsOf: self.expandToken(token, state: state))
        }
        return result
    }

    private func directiveArgs(_ tokens: [Token], from start: Int, directiveLine: Int)
        -> [Token]
    {
        var args: [Token] = []
        var k = start
        while k < tokens.count {
            let t = tokens[k]
            if t.kind == .Separator(.Sharp) { break }
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
        var evaluator = ConditionEvaluator(
            tokens: replaced, flags: state.config.flags, directiveToken: directiveToken,
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

private struct ConditionEvaluator {
    let tokens: [Token]
    let flags: Set<String>
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
        return value
    }

    private mutating func parseOrExpr() -> Bool? {
        guard var value = self.parseAndExpr() else { return nil }
        while self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.Or) {
            self.index += 1
            guard let rhs = self.parseAndExpr() else { return nil }
            value = value || rhs
        }
        return value
    }

    private mutating func parseAndExpr() -> Bool? {
        guard var value = self.parseUnary() else { return nil }
        while self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.And) {
            self.index += 1
            guard let rhs = self.parseUnary() else { return nil }
            value = value && rhs
        }
        return value
    }

    private mutating func parseUnary() -> Bool? {
        if self.index < self.tokens.count, self.tokens[self.index].kind == .Operator(.Not) {
            self.index += 1
            guard let value = self.parseUnary() else { return nil }
            return !value
        }
        return self.parsePrimary()
    }

    private mutating func parsePrimary() -> Bool? {
        guard self.index < self.tokens.count else {
            self.onError("expected expression in #if condition", self.tokens.last!)
            return nil
        }
        let token = self.tokens[self.index]
        switch token.kind {
        case .IntegerLiteral(let value):
            self.index += 1
            return value != 0
        case .BooleanLiteral(let value):
            self.index += 1
            return value
        case .Identifier:
            self.index += 1
            return self.flags.contains(token.value)
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
