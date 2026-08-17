import SwiftBetterDiagnostic
import TrussCore

public final class AttributeChecker: AST.Visitor {
    private let context: Context

    public init(context: Context) {
        self.context = context
    }

    private func checkAttributes(_ attributes: [AST.Attribute], scope: SourceRange) {
        for attribute in attributes {
            switch attribute.name.value {
            case "allow":
                checkAllow(attribute, scope: scope)
            case "cname", "builtin":
                break
            default:
                context.emitError("unknown attribute '\(attribute.name.value)'", at: attribute.name)
            }
        }
    }

    private func checkAllow(_ attribute: AST.Attribute, scope: SourceRange) {
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

    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil) -> Any? {
        checkAttributes(moduleDecl.attributes, scope: moduleDecl.sourceRange)
        return super.visitModuleDecl(moduleDecl, additional: additional)
    }

    public override func visitTypeAliasDecl(_ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil) -> Any? {
        checkAttributes(typeAliasDecl.attributes, scope: typeAliasDecl.sourceRange)
        return super.visitTypeAliasDecl(typeAliasDecl, additional: additional)
    }

    public override func visitOperatorDecl(_ operatorDecl: AST.OperatorDecl, additional: Any? = nil) -> Any? {
        checkAttributes(operatorDecl.attributes, scope: operatorDecl.sourceRange)
        return super.visitOperatorDecl(operatorDecl, additional: additional)
    }

    public override func visitPrecedenceGroupDecl(
        _ precedenceGroupDecl: AST.PrecedenceGroupDecl, additional: Any? = nil
    ) -> Any? {
        checkAttributes(precedenceGroupDecl.attributes, scope: precedenceGroupDecl.sourceRange)
        return super.visitPrecedenceGroupDecl(precedenceGroupDecl, additional: additional)
    }

    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil) -> Any? {
        checkAttributes(externDecl.attributes, scope: externDecl.sourceRange)
        return super.visitExternDecl(externDecl, additional: additional)
    }

    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil) -> Any? {
        checkAttributes(structDecl.attributes, scope: structDecl.sourceRange)
        return super.visitStructDecl(structDecl, additional: additional)
    }

    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil) -> Any? {
        checkAttributes(classDecl.attributes, scope: classDecl.sourceRange)
        return super.visitClassDecl(classDecl, additional: additional)
    }

    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil) -> Any? {
        checkAttributes(actorDecl.attributes, scope: actorDecl.sourceRange)
        return super.visitActorDecl(actorDecl, additional: additional)
    }

    public override func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional: Any? = nil) -> Any? {
        checkAttributes(protocolDecl.attributes, scope: protocolDecl.sourceRange)
        return super.visitProtocolDecl(protocolDecl, additional: additional)
    }

    public override func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil) -> Any? {
        checkAttributes(extensionDecl.attributes, scope: extensionDecl.sourceRange)
        return super.visitExtensionDecl(extensionDecl, additional: additional)
    }

    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil) -> Any? {
        checkAttributes(enumDecl.attributes, scope: enumDecl.sourceRange)
        return super.visitEnumDecl(enumDecl, additional: additional)
    }

    public override func visitEnumCaseDecl(_ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil) -> Any? {
        checkAttributes(enumCaseDecl.attributes, scope: enumCaseDecl.sourceRange)
        return super.visitEnumCaseDecl(enumCaseDecl, additional: additional)
    }

    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        checkAttributes(initDecl.attributes, scope: initDecl.sourceRange)
        return super.visitInitDecl(initDecl, additional: additional)
    }

    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        checkAttributes(deinitDecl.attributes, scope: deinitDecl.sourceRange)
        return super.visitDeinitDecl(deinitDecl, additional: additional)
    }

    public override func visitFunctionDecl(_ functionDecl: AST.FunctionDecl, additional: Any? = nil) -> Any? {
        checkAttributes(functionDecl.attributes, scope: functionDecl.sourceRange)
        return super.visitFunctionDecl(functionDecl, additional: additional)
    }

    public override func visitVariableDecl(_ variableDecl: AST.VariableDecl, additional: Any? = nil) -> Any? {
        checkAttributes(variableDecl.attributes, scope: variableDecl.sourceRange)
        return super.visitVariableDecl(variableDecl, additional: additional)
    }

    public override func visitSubscriptDecl(_ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil) -> Any? {
        checkAttributes(subscriptDecl.attributes, scope: subscriptDecl.sourceRange)
        return super.visitSubscriptDecl(subscriptDecl, additional: additional)
    }

    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        checkAttributes(associatedTypeDecl.attributes, scope: associatedTypeDecl.sourceRange)
        return super.visitAssociatedTypeDecl(associatedTypeDecl, additional: additional)
    }
}
