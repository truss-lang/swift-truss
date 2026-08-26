import Foundation

public struct ModuleInterfaceDumper {
    public init() {}

    public func dump(_ interface: ModuleInterface) -> String {
        var out = "module \(interface.name) {\n"
        dumpScope(interface.root, into: &out, indent: 1)
        out += "}\n"
        return out
    }

    private func dumpScope(_ scope: InterfaceScope, into out: inout String, indent: Int) {
        let pad = String(repeating: "    ", count: indent)
        for m in scope.modules.sorted(by: { $0.name < $1.name }) {
            out += "\(pad)module \(m.name) {\n"
            dumpScope(m.scope, into: &out, indent: indent + 1)
            out += "\(pad)}\n"
        }
        for t in scope.types {
            switch t {
            case let .Nominal(n):
                out += "\(pad)\(kindName(n.kind)) \(n.name)"
                if !n.conformances.isEmpty {
                    out += ": \(n.conformances.joined(separator: ", "))"
                }
                if let sup = n.superclass { out += " : \(sup)" }
                out += " {\n"
                for c in n.cases {
                    let assoc = c.associatedTypes.isEmpty
                        ? ""
                        : "(\(c.associatedTypes.map(typeText).joined(separator: ", ")))"
                    out += "\(pad)    case \(c.name)\(assoc)\n"
                }
                dumpScope(n.scope, into: &out, indent: indent + 1)
                out += "\(pad)}\n"
            case let .TypeAlias(a):
                out += "\(pad)typealias \(a.name)"
                if let tgt = a.target { out += " = \(typeText(tgt))" }
                out += "\n"
            case let .AssociatedType(s): out += "\(pad)associatedtype \(s.name)\n"
            case let .Builtin(s): out += "\(pad)builtin \(s.name)\n"
            case let .GenericParam(s): out += "\(pad)generic \(s.name)\n"
            }
        }
        for v in scope.values {
            switch v {
            case let .Function(f):
                if let ft = f.functionType {
                    out += "\(pad)func \(f.name)\(typeText(ft))\n"
                } else {
                    out += "\(pad)func \(f.name)\(signatureText(f))\n"
                }
            case let .Variable(x):
                out += "\(pad)var \(x.name)"
                if let ty = x.type { out += ": \(typeText(ty))" }
                out += "\n"
            }
        }
    }

    private func kindName(_ k: InterfaceNominalKind) -> String {
        switch k {
        case .StructType: "struct"
        case .ClassType: "class"
        case .EnumType: "enum"
        case .ProtocolType: "protocol"
        case .ActorType: "actor"
        }
    }

    private func signatureText(_ f: InterfaceFunction) -> String {
        let parts = f.labels.enumerated().map { i, label in
            var p = label ?? "_"
            if i < f.hasDefaults.count, f.hasDefaults[i] { p += " = _default" }
            return p
        }
        return "(\(parts.joined(separator: ", ")))"
    }

    public func typeText(_ ref: InterfaceTypeRef) -> String {
        switch ref {
        case .Void: "Void"
        case .Never: "Never"
        case .Error: "Error"
        case let .Builtin(n): n
        case let .Nominal(n, args):
            args.isEmpty ? n : "\(n)<\(args.map(typeText).joined(separator: ", "))>"
        case let .Pointer(p, nn): nn ? "&\(typeText(p))" : "&mut \(typeText(p))"
        case let .Tuple(els):
            "(\(els.map { ($0.label.map { "\($0): " } ?? "") + typeText($0.type) }.joined(separator: ", ")))"
        case let .Function(f):
            "(\(f.parameters.map { typeText($0.type) }.joined(separator: ", "))) -> \(typeText(f.returnType))"
        case let .Composition(m): m.map(typeText).joined(separator: " & ")
        case let .Variadic(b): "\(typeText(b))..."
        case let .GenericParam(n): n
        case let .Forall(ps, b): "<\(ps.joined(separator: ", "))> \(typeText(b))"
        case let .TypeVariable(i): "T\(i)"
        }
    }
}
