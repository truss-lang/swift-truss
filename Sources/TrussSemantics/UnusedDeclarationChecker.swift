import SwiftBetterDiagnostic
import TrussCore

public final class UnusedDeclarationChecker: AST.Visitor {
    private let context: Context
    private var usedIds: Set<Id.SymbolId> = []
    private var candidates: [Candidate] = []
    private var functionDepth = 0
    private var externDepth = 0
    private var emptyBodies: [Token] = []

    private struct Candidate {
        let symbol: Symbol.Symbol
        let token: Token
        let message: String
    }

    public init(context: Context) {
        self.context = context
    }

    public func checkAll(_ programs: [AST.Program]) {
        for program in programs {
            visitProgram(program)
        }
        report()
    }

    private func report() {
        for candidate in candidates {
            if !usedIds.contains(candidate.symbol.id),
               !context.isWarningAllowed(at: candidate.token)
            {
                context.emitWarning(candidate.message, at: candidate.token)
            }
        }
        for token in emptyBodies {
            if !context.isWarningAllowed(at: token) {
                context.emitWarning("function has an empty body", at: token)
            }
        }
    }

    public override func visit(_ node: AST.AstNode, additional: Any? = nil) -> Any? {
        if let expression = node as? AST.Expression {
            collectSymbols(expression)
        }
        return super.visit(node, additional: additional)
    }

    private func collectSymbols(_ expression: AST.Expression) {
        switch expression {
        case let variable as AST.Variable:
            insert(variable.symbol, overloads: variable.overloads)
        case let call as AST.Call:
            insert(
                TypeChecker.resolvedFunctionSymbol(of: call.callee),
                overloads: TypeChecker.resolvedFunctionSymbols(of: call.callee)
            )
        case let memberAccess as AST.MemberAccess:
            insert(memberAccess.symbol, overloads: memberAccess.overloads)
        case let selfExpression as AST.SelfExpression:
            insert(selfExpression.symbol, overloads: nil)
        case let superExpression as AST.SuperExpression:
            insert(superExpression.symbol, overloads: nil)
        case let implicitMemberAccess as AST.ImplicitMemberAccess:
            insert(implicitMemberAccess.symbol, overloads: implicitMemberAccess.overloads)
        case let binary as AST.Binary:
            insert(binary.symbol, overloads: nil)
        case let prefix as AST.Prefix:
            insert(prefix.symbol, overloads: nil)
        case let postfix as AST.Postfix:
            insert(postfix.symbol, overloads: nil)
        case let subscriptExpression as AST.Subscript:
            insert(subscriptExpression.symbol, overloads: subscriptExpression.overloads)
        case let keyPath as AST.KeyPathExpression:
            for component in keyPath.components {
                insert(component.symbol, overloads: component.overloads)
            }
        default:
            break
        }
    }

    private func insert(_ symbol: Symbol.Symbol?, overloads: [Symbol.FunctionSymbol]?) {
        if let symbol {
            usedIds.insert(symbol.id)
        }
        if let overloads {
            for symbol in overloads {
                usedIds.insert(symbol.id)
            }
        }
    }

    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
        if let symbol = functionDecl.symbol {
            for local in symbol.locals {
                if !local.name.hasPrefix("_") {
                    candidates.append(
                        Candidate(
                            symbol: local,
                            token: local.sourceToken ?? functionDecl.name,
                            message: "unused variable '\(local.name)'"
                        )
                    )
                }
            }
            if isPrivate(symbol.access), !isOverride(functionDecl), externDepth == 0,
               !functionDecl.modifiers.contains(where: { isAbstract($0.kind) }),
               functionDecl.body != nil
            {
                candidates.append(
                    Candidate(
                        symbol: symbol,
                        token: functionDecl.name,
                        message: "function '\(symbol.name)' is never used"
                    )
                )
            }
            if let body = functionDecl.body, case let .Block(statements) = body,
               statements.isEmpty, externDepth == 0,
               !functionDecl.modifiers.contains(where: { isAbstract($0.kind) })
            {
                emptyBodies.append(functionDecl.name)
            }
        }
        functionDepth += 1
        super.visitFunctionDecl(functionDecl, additional: additional)
        functionDepth -= 1
        return nil
    }

    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        if let symbol = initDecl.symbol {
            for local in symbol.locals {
                if !local.name.hasPrefix("_") {
                    candidates.append(
                        Candidate(
                            symbol: local,
                            token: local.sourceToken ?? initDecl.token,
                            message: "unused variable '\(local.name)'"
                        )
                    )
                }
            }
        }
        return super.visitInitDecl(initDecl, additional: additional)
    }

    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil) -> Any? {
        if let symbol = variableDecl.symbol, functionDepth == 0,
           isPrivate(symbol.access), !symbol.name.hasPrefix("_")
        {
            let message = symbol.memberOf == nil
                ? "variable '\(symbol.name)' is never used"
                : "member '\(symbol.name)' is never used"
            candidates.append(
                Candidate(
                    symbol: symbol,
                    token: variableDecl.name,
                    message: message
                )
            )
        }
        return super.visitVariableDecl(variableDecl, additional: additional)
    }

    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil) -> Any? {
        externDepth += 1
        super.visitExternDecl(externDecl, additional: additional)
        externDepth -= 1
        return nil
    }

    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil) -> Any? {
        collectTypeCandidate(structDecl.symbol, token: structDecl.name)
        return super.visitStructDecl(structDecl, additional: additional)
    }

    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil) -> Any? {
        collectTypeCandidate(classDecl.symbol, token: classDecl.name)
        return super.visitClassDecl(classDecl, additional: additional)
    }

    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil) -> Any? {
        collectTypeCandidate(enumDecl.symbol, token: enumDecl.name)
        return super.visitEnumDecl(enumDecl, additional: additional)
    }

    public override func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional: Any? = nil) -> Any? {
        collectTypeCandidate(protocolDecl.symbol, token: protocolDecl.name)
        return super.visitProtocolDecl(protocolDecl, additional: additional)
    }

    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil) -> Any? {
        collectTypeCandidate(actorDecl.symbol, token: actorDecl.name)
        return super.visitActorDecl(actorDecl, additional: additional)
    }

    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil) -> Any? {
        collectTypeCandidate(typeAliasDecl.symbol, token: typeAliasDecl.name)
        return super.visitTypeAliasDecl(typeAliasDecl, additional: additional)
    }

    private func collectTypeCandidate(_ symbol: Symbol.Symbol?, token: Token) {
        if let symbol, isPrivate(symbol.access) {
            candidates.append(
                Candidate(
                    symbol: symbol,
                    token: token,
                    message: "type '\(symbol.name)' is never used"
                )
            )
        }
    }

    private func isPrivate(_ access: AccessLevel) -> Bool {
        access == .Private || access == .FilePrivate
    }

    private func isOverride(_ functionDecl: AST.FunctionDecl) -> Bool {
        functionDecl.modifiers.contains { modifier in
            if case .Override = modifier.kind { return true }
            return false
        }
    }

    private func isAbstract(_ kind: AST.ModifierKind) -> Bool {
        if case .Abstract = kind { return true }
        return false
    }
}
