import SwiftAbstract

public enum Symbol {
    @abstractClass
    public class Symbol {
        public var parent: Id.SymbolId?
        public let id: Id.SymbolId
        public let name: String
        public var sourceToken: Token?
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
        public var typeId: Id.TypeId? = nil
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

    public final class GenericParamSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public final class CaseSymbol: Symbol {
        public init(id: Id.SymbolId, name: String) {
            super.init(id, name)
        }
    }

    public struct FunctionSignature {
        public let labels: [String?]
        public let hasDefaults: [Bool]
        public let isVararg: [Bool]
        public init(labels: [String?], hasDefaults: [Bool], isVararg: [Bool]) {
            self.labels = labels
            self.hasDefaults = hasDefaults
            self.isVararg = isVararg
        }
    }

    public final class FunctionSymbol: Symbol {
        public let scope: Scope
        public var locals: [VariableSymbol]
        public let signature: FunctionSignature
        public var functionType: TrussType.FunctionType? = nil
        public init(
            id: Id.SymbolId, name: String, locals: [VariableSymbol],
            scope: Scope, signature: FunctionSignature
        ) {
            self.locals = locals
            self.scope = scope
            self.signature = signature
            super.init(id, name)

            for local in locals {
                local.parent = self.id
            }
        }
    }

    public final class VariableSymbol: Symbol {
        public var type: TrussType.TrussType? = nil
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
            dumpScope(packageSymbol.scope, into: &out, indent: 2)
            return out
        }

        private func dumpScope(_ scope: Scope, into out: inout String, indent: Int) {
            let pad = String(repeating: " ", count: indent)
            for (name, symbol) in scope.modules.sorted(by: { $0.key < $1.key }) {
                out += "\(pad)module \(name) #\(symbol.id.id)\n"
                dumpScope(symbol.scope, into: &out, indent: indent + 2)
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
                    dumpScope(nominal.scope, into: &out, indent: indent + 2)
                }
            }
            for (name, symbols) in scope.values.sorted(by: { $0.key < $1.key }) {
                for symbol in symbols {
                    var line = "\(pad)value \(name) (\(symbolKind(symbol))) #\(symbol.id.id)"
                    if let function = symbol as? FunctionSymbol {
                        line += signatureText(function)
                    }
                    out += line + "\n"
                    if let function = symbol as? FunctionSymbol {
                        dumpScope(function.scope, into: &out, indent: indent + 2)
                    }
                }
            }
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
            case is GenericParamSymbol: "generic-param"
            case is CaseSymbol: "case"
            case is FunctionSymbol: "function"
            case is VariableSymbol: "variable"
            default: "unknown"
            }
        }
    }
}
