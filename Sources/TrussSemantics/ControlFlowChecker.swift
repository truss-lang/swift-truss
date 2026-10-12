import SwiftBetterDiagnostic
import TrussCore

public final class ControlFlowChecker: AST.Visitor {
    private final class LabelCollector: AST.Visitor {
        private(set) var labels: Set<String> = []

        public override func visitLabeledStatement(
            _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
        ) -> Any? {
            labels.insert(labeledStatement.label.value)
            return super.visitLabeledStatement(labeledStatement, additional: additional)
        }
    }

    private struct DeferBoundary {
        let loopDepth: Int
        let labelCount: Int
        let labels: Set<String>
    }

    private let context: Context
    private var loopDepth = 0
    private var functionReturnType: TrussType.TrussType?
    private var functionLabels: Set<String> = []
    private var enclosingLabels: [String] = []
    private var deferBoundaries: [DeferBoundary] = []

    public init(context: Context) {
        self.context = context
    }

    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
        let savedReturn = functionReturnType
        let savedLabels = functionLabels
        let savedDeferBoundaries = deferBoundaries
        functionReturnType = functionDecl.symbol?.functionType?.returnType
        functionLabels = collectLabels(functionDecl.body)
        deferBoundaries = []
        if case let .Block(statements) = functionDecl.body {
            checkUnreachable(statements)
        }
        super.visitFunctionDecl(functionDecl, additional: additional)
        if let returnType = functionReturnType, !(returnType is TrussType.VoidType),
           case let .Block(statements) = functionDecl.body, !hasReturnPath(statements)
        {
            context.emitError(
                "missing return in a function expected to return '\(returnType)'",
                at: functionDecl.name
            )
        }
        functionReturnType = savedReturn
        functionLabels = savedLabels
        deferBoundaries = savedDeferBoundaries
        return nil
    }

    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        let savedLoopDepth = loopDepth
        let savedDeferBoundaries = deferBoundaries
        loopDepth = 0
        deferBoundaries = []
        checkUnreachable(closure.body)
        super.visitClosure(closure, additional: additional)
        loopDepth = savedLoopDepth
        deferBoundaries = savedDeferBoundaries
        return nil
    }

    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
        checkConstantCondition(whileStatement.condition)
        checkUnreachable(whileStatement.body)
        loopDepth += 1
        super.visitWhile(whileStatement, additional: additional)
        loopDepth -= 1
        return nil
    }

    public override func visitRepeatWhile(
        _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
    ) -> Any? {
        checkConstantCondition(repeatWhile.condition)
        checkUnreachable(repeatWhile.body)
        loopDepth += 1
        super.visitRepeatWhile(repeatWhile, additional: additional)
        loopDepth -= 1
        return nil
    }

    public override func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
        checkUnreachable(forStatement.body)
        loopDepth += 1
        super.visitFor(forStatement, additional: additional)
        loopDepth -= 1
        return nil
    }

    public override func visitLoop(_ loopStatement: AST.Loop, additional: Any? = nil) -> Any? {
        checkUnreachable(loopStatement.body)
        loopDepth += 1
        super.visitLoop(loopStatement, additional: additional)
        loopDepth -= 1
        return nil
    }

    public override func visitGuard(_ guardStatement: AST.Guard, additional: Any? = nil) -> Any? {
        checkUnreachable(guardStatement.body)
        return super.visitGuard(guardStatement, additional: additional)
    }

    public override func visitIf(_ ifExpression: AST.If, additional: Any? = nil) -> Any? {
        checkConstantCondition(ifExpression.condition)
        checkUnreachable(ifExpression.then)
        if let elseKind = ifExpression.elseKind {
            switch elseKind {
            case let .Block(statements):
                checkUnreachable(statements)
            case .If:
                break
            }
        }
        return super.visitIf(ifExpression, additional: additional)
    }

    public override func visitMatch(_ match: AST.Match, additional: Any? = nil) -> Any? {
        for matchCase in match.cases {
            checkUnreachable(matchCase.body)
        }
        return super.visitMatch(match, additional: additional)
    }

    public override func visitDo(_ doExpression: AST.Do, additional: Any? = nil) -> Any? {
        checkUnreachable(doExpression.body)
        for catchClause in doExpression.catches {
            if catchClause.body.isEmpty, !context.isWarningAllowed(at: catchClause.sourceRange) {
                context.emitWarning("empty catch block", at: catchClause.sourceRange)
            }
            checkUnreachable(catchClause.body)
        }
        if let finallyBody = doExpression.finallyBody {
            checkUnreachable(finallyBody)
        }
        return super.visitDo(doExpression, additional: additional)
    }

    public override func visitDefer(_ deferStatement: AST.Defer, additional: Any? = nil) -> Any? {
        checkUnreachable(deferStatement.body)
        deferBoundaries.append(
            DeferBoundary(
                loopDepth: loopDepth,
                labelCount: enclosingLabels.count,
                labels: collectLabels(deferStatement.body)
            )
        )
        super.visitDefer(deferStatement, additional: additional)
        deferBoundaries.removeLast()
        return nil
    }

    public override func visitLabeledStatement(
        _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
    ) -> Any? {
        functionLabels.insert(labeledStatement.label.value)
        enclosingLabels.append(labeledStatement.label.value)
        super.visitLabeledStatement(labeledStatement, additional: additional)
        enclosingLabels.removeLast()
        return nil
    }

    public override func visitBreak(_ breakStatement: AST.Break, additional: Any? = nil) -> Any? {
        if loopDepth == 0 {
            context.emitError("'break' outside of a loop", at: breakStatement.token)
        }
        if let label = breakStatement.label, !enclosingLabels.contains(label.value) {
            context.emitError(
                "cannot find label '\(label.value)' for 'break'", at: label
            )
        }
        if let label = breakStatement.label {
            if escapesDeferLabel(label) {
                context.emitError(
                    "'break' cannot transfer control out of a defer statement", at: breakStatement.token
                )
            }
        } else if loopDepth > 0, escapesDeferLoop() {
            context.emitError(
                "'break' cannot transfer control out of a defer statement", at: breakStatement.token
            )
        }
        return nil
    }

    public override func visitContinue(
        _ continueStatement: AST.Continue, additional: Any? = nil
    ) -> Any? {
        if loopDepth == 0 {
            context.emitError("'continue' outside of a loop", at: continueStatement.token)
        }
        if let label = continueStatement.label, !enclosingLabels.contains(label.value) {
            context.emitError(
                "cannot find label '\(label.value)' for 'continue'", at: label
            )
        }
        if let label = continueStatement.label {
            if escapesDeferLabel(label) {
                context.emitError(
                    "'continue' cannot transfer control out of a defer statement", at: continueStatement.token
                )
            }
        } else if loopDepth > 0, escapesDeferLoop() {
            context.emitError(
                "'continue' cannot transfer control out of a defer statement", at: continueStatement.token
            )
        }
        return nil
    }

    public override func visitGoto(_ gotoStatement: AST.Goto, additional: Any? = nil) -> Any? {
        if !functionLabels.contains(gotoStatement.label.value) {
            context.emitError(
                "cannot find label '\(gotoStatement.label.value)' for 'goto'",
                at: gotoStatement.label
            )
        } else if escapesDeferGoto(gotoStatement.label) {
            context.emitError(
                "'goto' cannot transfer control out of a defer statement", at: gotoStatement.token
            )
        }
        return nil
    }

    public override func visitReturn(_ returnStatement: AST.Return, additional: Any? = nil) -> Any? {
        if !deferBoundaries.isEmpty {
            context.emitError(
                "'return' cannot transfer control out of a defer statement", at: returnStatement.token
            )
        }
        return super.visitReturn(returnStatement, additional: additional)
    }

    public override func visitThrow(_ throwStatement: AST.Throw, additional: Any? = nil) -> Any? {
        if !deferBoundaries.isEmpty {
            context.emitError("errors cannot be thrown out of a defer body", at: throwStatement.token)
        }
        return super.visitThrow(throwStatement, additional: additional)
    }

    private func hasReturnPath(_ statements: [AST.Statement]) -> Bool {
        guard let last = statements.last else {
            return false
        }
        if last is AST.Return || last is AST.Throw {
            return true
        }
        if let expressionStatement = last as? AST.ExpressionStatement {
            return expressionHasReturnPath(expressionStatement.expression)
        }
        return false
    }

    private func expressionHasReturnPath(_ expression: AST.Expression) -> Bool {
        if let ifExpression = expression as? AST.If {
            guard let elseKind = ifExpression.elseKind else {
                return false
            }
            switch elseKind {
            case let .Block(elseStatements):
                return hasReturnPath(ifExpression.then) && hasReturnPath(elseStatements)
            case let .If(elseIf):
                return hasReturnPath(ifExpression.then) && expressionHasReturnPath(elseIf)
            }
        }
        if let match = expression as? AST.Match {
            return !match.cases.isEmpty && match.cases.allSatisfy { hasReturnPath($0.body) }
        }
        if let doExpression = expression as? AST.Do {
            return hasReturnPath(doExpression.body)
        }
        return true
    }

    private func escapesDeferLoop() -> Bool {
        guard let boundary = deferBoundaries.last else {
            return false
        }
        return loopDepth <= boundary.loopDepth
    }

    private func escapesDeferLabel(_ label: Token) -> Bool {
        guard let boundary = deferBoundaries.last else {
            return false
        }
        guard let index = enclosingLabels.lastIndex(of: label.value) else {
            return false
        }
        return index < boundary.labelCount
    }

    private func escapesDeferGoto(_ label: Token) -> Bool {
        guard let boundary = deferBoundaries.last else {
            return false
        }
        return !boundary.labels.contains(label.value)
    }

    private func collectLabels(_ statements: [AST.Statement]) -> Set<String> {
        let collector = LabelCollector()
        for statement in statements {
            collector.visit(statement)
        }
        return collector.labels
    }

    private func collectLabels(_ body: AST.FunctionDecl.Body?) -> Set<String> {
        guard let body else {
            return []
        }
        let collector = LabelCollector()
        switch body {
        case let .Block(statements):
            for statement in statements {
                collector.visit(statement)
            }
        case let .Expression(expression):
            collector.visit(expression)
        }
        return collector.labels
    }

    private func checkUnreachable(_ statements: [AST.Statement]) {
        var terminated = false
        for statement in statements {
            if terminated, !(statement is AST.LabeledStatement),
               !context.isWarningAllowed(at: statement.sourceRange)
            {
                context.emitWarning("unreachable code", at: statement.sourceRange)
            }
            if statement is AST.Return || statement is AST.Throw || statement is AST.Break
                || statement is AST.Continue || statement is AST.Goto
            {
                terminated = true
            }
            if statement is AST.LabeledStatement {
                terminated = false
            }
        }
    }

    private func checkConstantCondition(_ condition: AST.Expression) {
        if let literal = condition as? AST.BoolLiteral, !context.isWarningAllowed(at: literal.token) {
            context.emitWarning(
                "condition is always \(literal.token.value)", at: literal.token
            )
        }
    }
}
