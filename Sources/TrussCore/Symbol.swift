import SwiftAbstract

public enum Symbol {
    @abstractClass
    public class Symbol {
        public var parent: Id.SymbolId?
        public let id: Id.SymbolId
        public let name: String
        public var sourceToken: Token?
        public var access: AccessLevel = .Internal
        public var setterAccess: AccessLevel?
        public var memberOf: Id.SymbolId?
        public var packageId: Id.SymbolId?
        public var moduleSymbol: TrussCore.Symbol.ModuleSymbol?
        public var isAbstract: Bool = false
        public var isFinal: Bool = false
        @abstractInit
        public init(_ id: Id.SymbolId, _ name: String) {
            self.id = id
            self.name = name
        }
    }

    public final class PackageSymbol: Symbol {
        public let scope: Scope = .init()
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ModuleSymbol: Symbol {
        public let scope: Scope = .init()
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    @abstractClass
    public class NominalTypeSymbol: Symbol {
        public var conformances: [ProtocolSymbol] = []
        public var typeId: Id.ASTTypeId? = nil
        public var initializers: [FunctionSymbol] = []
        public var deinitializer: FunctionSymbol? = nil
        public let scope: Scope = .init()
        @abstractInit
        public override init(_ id: Id.SymbolId, _ name: String) {
            super.init(id, name)
        }
    }

    public final class StructSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ClassSymbol: NominalTypeSymbol {
        public var superclass: ClassSymbol?
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class EnumSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ProtocolSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class ActorSymbol: NominalTypeSymbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class AssociatedTypeSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class TypeAliasSymbol: Symbol {
        public var targetType: TrussType.TrussType? = nil
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class BuiltinTypeSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class GenericParamSymbol: Symbol {
        public enum Constraint {
            case Conformance(TrussType.TrussType)
            case Equality(TrussType.TrussType)
        }

        public var constraints: [Constraint] = []
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class CaseSymbol: Symbol {
        public var associatedLabels: [String?] = []
        public var associatedTypes: [TrussType.TrussType] = []
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public struct FunctionSignature {
        public let labels: [String?]
        public let hasDefaults: [Bool]
        public let isVararg: [Bool]
        public let isVariadic: Bool
        public init(labels: [String?], hasDefaults: [Bool], isVararg: [Bool], isVariadic: Bool) {
            self.labels = labels
            self.hasDefaults = hasDefaults
            self.isVararg = isVararg
            self.isVariadic = isVariadic
        }
    }

    public final class FunctionSymbol: Symbol {
        public let scope: Scope
        public var locals: [VariableSymbol]
        public let signature: FunctionSignature
        public let isStatic: Bool
        public var isBuiltin: Bool = false
        public var functionType: TrussType.FunctionType? = nil
        public var forallType: TrussType.ForallType? = nil
        public init(
            id: Id.SymbolId, name: String, locals: [VariableSymbol],
            scope: Scope, signature: FunctionSignature, isStatic: Bool = false
        ) {
            self.locals = locals
            self.scope = scope
            self.signature = signature
            self.isStatic = isStatic
            super.init(id, name)

            for local in locals {
                local.parent = self.id
            }
        }
    }

    public final class VariableSymbol: Symbol {
        public var type: TrussType.TrussType? = nil
        public var isMutable: Bool = true
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class Dumper {
        private let context: Context
        public init(context: Context) {
            self.context = context
        }

        public func dump(_ program: AST.Program) -> String {
            guard let packageSymbol = program.packageSymbol else { return "" }
            var out = "\(packageSymbol.name) (package) #\(packageSymbol.id.id)\n"
            dumpScope(packageSymbol.scope, into: &out, indent: 2, program: program)
            return out
        }

        private func valuePrefix(_ symbol: Symbol) -> String {
            switch symbol {
            case is FunctionSymbol: "function"
            case is VariableSymbol: "var"
            case is CaseSymbol: "case"
            default: "value"
            }
        }

        private func dumpScope(
            _ scope: Scope, into out: inout String, indent: Int, program: AST.Program? = nil
        ) {
            let pad = String(repeating: " ", count: indent)
            for (name, symbol) in scope.modules.sorted(by: { $0.key < $1.key }) {
                out += "\(pad)module \(name) #\(symbol.id.id)\n"
                dumpScope(symbol.scope, into: &out, indent: indent + 2, program: program)
            }
            for (name, symbol) in scope.types.sorted(by: { $0.key < $1.key }) {
                var line = "\(pad)type \(name) (\(symbolKind(symbol))) #\(symbol.id.id)"
                if let nominal = symbol as? NominalTypeSymbol {
                    line += tyText(nominal)
                    line += conformsText(nominal)
                    if let classSymbol = symbol as? ClassSymbol {
                        line += superText(classSymbol)
                    }
                }
                out += line + "\n"
                if let nominal = symbol as? NominalTypeSymbol {
                    dumpScope(nominal.scope, into: &out, indent: indent + 2, program: program)
                }
            }
            for (name, symbols) in scope.values.sorted(by: { $0.key < $1.key }) {
                for symbol in symbols {
                    let prefix = valuePrefix(symbol)
                    var line = "\(pad)\(prefix) \(name) #\(symbol.id.id)"
                    if let function = symbol as? FunctionSymbol {
                        line += signatureText(function)
                    }
                    out += line + "\n"
                    if let function = symbol as? FunctionSymbol {
                        dumpScope(function.scope, into: &out, indent: indent + 2, program: program)
                        if let program, let body = findFunctionBody(function, in: program) {
                            dumpInnerScopes(body, into: &out, indent: indent + 2)
                        }
                    }
                }
            }
        }

        private func findFunctionBody(
            _ function: FunctionSymbol, in program: AST.Program
        ) -> [AST.Statement]? {
            for statement in program.statements {
                if let result = findFunctionBodyInStatement(function, statement) {
                    return result
                }
            }
            return nil
        }

        private func findFunctionBodyInStatement(
            _ function: FunctionSymbol, _ statement: AST.Statement
        ) -> [AST.Statement]? {
            switch statement {
            case let moduleDecl as AST.ModuleDecl:
                for stmt in moduleDecl.body {
                    if let result = findFunctionBodyInStatement(function, stmt) {
                        return result
                    }
                }
            case let structDecl as AST.StructDecl:
                for stmt in structDecl.body {
                    if let result = findFunctionBodyInStatement(function, stmt) {
                        return result
                    }
                }
            case let classDecl as AST.ClassDecl:
                for stmt in classDecl.body {
                    if let result = findFunctionBodyInStatement(function, stmt) {
                        return result
                    }
                }
            case let enumDecl as AST.EnumDecl:
                for stmt in enumDecl.body {
                    if let result = findFunctionBodyInStatement(function, stmt) {
                        return result
                    }
                }
            case let protocolDecl as AST.ProtocolDecl:
                for stmt in protocolDecl.body {
                    if let result = findFunctionBodyInStatement(function, stmt) {
                        return result
                    }
                }
            case let actorDecl as AST.ActorDecl:
                for stmt in actorDecl.body {
                    if let result = findFunctionBodyInStatement(function, stmt) {
                        return result
                    }
                }
            case let functionDecl as AST.FunctionDecl:
                guard functionDecl.symbol?.id == function.id else { return nil }
                switch functionDecl.body {
                case let .Block(statements):
                    return statements
                case .none, .Expression:
                    return nil
                }
            case let initDecl as AST.InitDecl:
                guard initDecl.symbol?.id == function.id else { return nil }
                return initDecl.body
            default:
                break
            }
            return nil
        }

        private func dumpInnerScopes(_ statements: [AST.Statement], into out: inout String, indent: Int) {
            for statement in statements {
                dumpInnerScopeIfPresent(statement, into: &out, indent: indent)
            }
        }

        private func dumpInnerScopeIfPresent(
            _ statement: AST.Statement, into out: inout String, indent: Int
        ) {
            let pad = String(repeating: " ", count: indent)
            switch statement {
            case let whileStmt as AST.While:
                if let scope = whileStmt.scope {
                    out += "\(pad)while\(locationText(whileStmt)) (scope):\n"
                    dumpScope(scope, into: &out, indent: indent + 2)
                    dumpInnerScopes(whileStmt.body, into: &out, indent: indent + 2)
                }
            case let repeatWhile as AST.RepeatWhile:
                if let scope = repeatWhile.scope {
                    out += "\(pad)repeatWhile\(locationText(repeatWhile)) (scope):\n"
                    dumpScope(scope, into: &out, indent: indent + 2)
                    dumpInnerScopes(repeatWhile.body, into: &out, indent: indent + 2)
                }
            case let forStmt as AST.For:
                if let scope = forStmt.scope {
                    out += "\(pad)for\(locationText(forStmt)) (scope):\n"
                    dumpScope(scope, into: &out, indent: indent + 2)
                    dumpInnerScopes(forStmt.body, into: &out, indent: indent + 2)
                }
            case let exprStmt as AST.ExpressionStatement:
                dumpInnerScopeIfPresentExpression(exprStmt.expression, into: &out, indent: indent)
            default:
                break
            }
        }

        private func dumpInnerScopeIfPresentExpression(
            _ expression: AST.Expression, into out: inout String, indent: Int
        ) {
            let pad = String(repeating: " ", count: indent)
            switch expression {
            case let ifExpr as AST.If:
                if let scope = ifExpr.scope {
                    out += "\(pad)if\(locationText(ifExpr)) (scope):\n"
                    dumpScope(scope, into: &out, indent: indent + 2)
                    dumpInnerScopes(ifExpr.then, into: &out, indent: indent + 2)
                    switch ifExpr.elseKind {
                    case let .Block(statements):
                        dumpInnerScopes(statements, into: &out, indent: indent + 2)
                    case let .If(elseIf):
                        dumpInnerScopeIfPresentExpression(elseIf, into: &out, indent: indent)
                    case .none:
                        break
                    }
                }
            case let closure as AST.Closure:
                if let scope = closure.scope {
                    out += "\(pad)closure\(locationText(closure)) (scope):\n"
                    dumpScope(scope, into: &out, indent: indent + 2)
                }
            default:
                break
            }
        }

        private func locationText(_ node: AST.AstNode) -> String {
            let start = node.sourceRange.start
            return " at \(start.line):\(start.column)"
        }

        private func tyText(_ symbol: NominalTypeSymbol) -> String {
            guard let typeId = symbol.typeId, let type = context.typeTable[typeId] else {
                return ""
            }
            switch type {
            case is TrussType.VoidType: return " ty:VoidType"
            case is TrussType.NeverType: return " ty:NeverType"
            case let nominal as TrussType.NominalType:
                return " ty:\(nominalKind(nominal))(\(nominal.name))#\(nominal.id.id)"
            default: return " ty:?"
            }
        }

        private func nominalKind(_ type: TrussType.NominalType) -> String {
            switch type {
            case is TrussType.StructType: "StructType"
            case is TrussType.ClassType: "ClassType"
            case is TrussType.EnumType: "EnumType"
            case is TrussType.ProtocolType: "ProtocolType"
            case is TrussType.ActorType: "ActorType"
            default: "NominalType"
            }
        }

        private func conformsText(_ symbol: NominalTypeSymbol) -> String {
            if symbol.conformances.isEmpty { return "" }
            return " conforms:"
                + symbol.conformances.map { "\($0.name)#\($0.id.id)" }.joined(separator: ", ")
        }

        private func superText(_ symbol: ClassSymbol) -> String {
            guard let superclass = symbol.superclass else { return "" }
            return " super:\(superclass.name)#\(superclass.id.id)"
        }

        private func signatureText(_ symbol: FunctionSymbol) -> String {
            var text = " ("
            let labels = symbol.signature.labels
            let hasDefaults = symbol.signature.hasDefaults
            let isVararg = symbol.signature.isVararg
            for (index, label) in labels.enumerated() {
                if index > 0 { text += ", " }
                if let label {
                    text += label
                } else {
                    text += "_"
                }
                text += ":"
                if index < hasDefaults.count, hasDefaults[index] { text += " =" }
                if index < isVararg.count, isVararg[index] { text += " ..." }
            }
            text += ")"
            return text
        }

        private func symbolKind(_ symbol: Symbol) -> String {
            switch symbol {
            case is StructSymbol: "struct"
            case is ClassSymbol: "class"
            case is EnumSymbol: "enum"
            case is ProtocolSymbol: "protocol"
            case is ActorSymbol: "actor"
            case is AssociatedTypeSymbol: "associated-type"
            case is TypeAliasSymbol: "typealias"
            case is BuiltinTypeSymbol: "builtin"
            case is GenericParamSymbol: "generic-param"
            case is CaseSymbol: "case"
            case is FunctionSymbol: "function"
            case is VariableSymbol: "variable"
            default: "unknown"
            }
        }
    }
}
