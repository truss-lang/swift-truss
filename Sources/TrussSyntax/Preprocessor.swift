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

public final class Preprocessor {
    private let context: Context

    private final class State {
        var output: [Token] = []
        var index = 0
        var active = true
        var frames: [ConditionFrame] = []
        var outerIfToken: Token? = nil
    }

    public init(context: Context) {
        self.context = context
    }

    public func process(_ tokens: [Token], config: PreprocessorConfig) -> [Token] {
        let state = State()
        while state.index < tokens.count {
            let token = tokens[state.index]
            if token.kind == .Separator(.Sharp) {
                if !self.handleDirective(state, tokens: tokens, config: config) {
                    self.emitError("unknown preprocessing directive", at: token)
                    state.index += 1
                }
                continue
            }
            if state.active {
                state.output.append(token)
            }
            state.index += 1
        }
        if let token = state.outerIfToken {
            self.emitError("unterminated #if directive", at: token)
        }
        return state.output
    }

    private func handleDirective(
        _ state: State, tokens: [Token], config: PreprocessorConfig
    ) -> Bool {
        guard state.index + 1 < tokens.count else { return false }
        let sharp = tokens[state.index]
        let name = tokens[state.index + 1]
        switch name.kind {
        case .Keyword(.If):
            let args = self.directiveArgs(
                tokens, from: state.index + 2, directiveLine: name.pos.line)
            state.index = state.index + 2 + args.count
            let value = self.evaluateCondition(args, flags: config.flags, at: name)
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
                self.handleElseIf(state, args: args, config: config, name: name, sharp: sharp)
                return true
            case "endif":
                state.index += 2
                self.handleEndIf(state, sharp: sharp)
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
        _ state: State, args: [Token], config: PreprocessorConfig, name: Token, sharp: Token
    ) {
        guard let frame = state.frames.last else {
            self.emitError("unexpected #elseif directive", at: sharp)
            return
        }
        if !frame.branchTaken {
            let value = self.evaluateCondition(args, flags: config.flags, at: name)
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
        _ tokens: [Token], flags: Set<String>, at directiveToken: Token
    ) -> Bool? {
        var evaluator = ConditionEvaluator(
            tokens: tokens, flags: flags, directiveToken: directiveToken,
            onError: { message, token in self.emitError(message, at: token) })
        return evaluator.evaluate()
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
