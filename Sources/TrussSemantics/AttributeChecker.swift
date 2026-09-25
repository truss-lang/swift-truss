import SwiftBetterDiagnostic
import TrussCore

public final class AttributeChecker: AST.Visitor {
    private let context: Context

    public init(context: Context) {
        self.context = context
    }

    public override func visit(_ node: AST.AstNode, additional: Any? = nil) -> Any? {
        if let decl = node as? AST.Decl {
            checkAttributes(decl.attributes, scope: decl.sourceRange)
        }
        return super.visit(node, additional: additional)
    }

    private static let attributeHandlers: [String: @Sendable (AST.Attribute, SourceRange, Context) -> Void] = [
        "allow": { attribute, scope, context in
            checkAllow(attribute, scope: scope, context: context)
        },
        "cname": { _, _, _ in },
        "builtin": { _, _, _ in },
    ]

    private func checkAttributes(_ attributes: [AST.Attribute], scope: SourceRange) {
        for attribute in attributes {
            guard let handler = Self.attributeHandlers[attribute.name.value] else {
                context.emitError("unknown attribute '\(attribute.name.value)'", at: attribute.name)
                continue
            }
            handler(attribute, scope, context)
        }
    }

    private static func checkAllow(
        _ attribute: AST.Attribute, scope: SourceRange, context: Context
    ) {
        if !attribute.labeledArguments.isEmpty {
            context.emitError(
                "expected a lint name in '#[allow(...)]', but found labeled argument",
                at: attribute.name
            )
            return
        }
        guard !attribute.arguments.isEmpty else {
            context.emitError("expected a lint name in '#[allow(...)]'", at: attribute.name)
            return
        }
        for argument in attribute.arguments {
            guard let lint = argument.first, argument.count == 1 else {
                context.emitError("expected a lint name in '#[allow(...)]'", at: attribute.name)
                return
            }
            if lint.value != "warning" {
                context.emitError("unknown lint '\(lint.value)' in '#[allow]'", at: lint)
                return
            }
        }
        context.allowWarning(in: scope)
    }
}
