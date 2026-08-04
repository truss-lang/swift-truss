extension AST.ModifierKind {
    var sourceText: String {
        switch self {
        case .Open(let setter): return setter ? "open(set)" : "open"
        case .Public(let setter): return setter ? "public(set)" : "public"
        case .Protected(let setter): return setter ? "protected(set)" : "protected"
        case .PackagePrivate(let setter): return setter ? "packageprivate(set)" : "packageprivate"
        case .Internal(let setter): return setter ? "internal(set)" : "internal"
        case .FilePrivate(let setter): return setter ? "fileprivate(set)" : "fileprivate"
        case .Private(let setter): return setter ? "private(set)" : "private"
        case .Abstract: return "abstract"
        case .Final: return "final"
        case .Mutating: return "mutating"
        case .Nonmutating: return "nonmutating"
        case .Convenience: return "convenience"
        case .Override: return "override"
        case .Lazy: return "lazy"
        case .Weak: return "weak"
        case .Unowned: return "unowned"
        case .Indirect: return "indirect"
        case .Isolated: return "isolated"
        case .Async: return "async"
        }
    }
}

public final class ASTDumper: AST.Visitor {
    private final class Writer {
        var lines: [String] = []
        private var prefixes: [String] = []
        private var connector = ""

        func node(_ text: String) {
            lines.append(prefixes.dropLast().joined() + connector + text)
        }

        func branch(_ isLast: Bool, _ body: () -> Void) {
            prefixes.append(isLast ? "  " : "| ")
            let saved = connector
            connector = isLast ? "`-" : "|-"
            body()
            connector = saved
            prefixes.removeLast()
        }
    }

    private let writer = Writer()

    public func dump(_ node: AST.AstNode) -> String {
        visit(node)
        return writer.lines.joined(separator: "\n")
    }

    private func dumpNode(_ text: String, children: [() -> Void] = []) {
        writer.node(text)
        for (index, child) in children.enumerated() {
            writer.branch(index == children.count - 1, child)
        }
    }

    private func modifiersText(_ modifiers: [AST.Modifier]) -> String {
        if modifiers.isEmpty { return "" }
        return " [" + modifiers.map { $0.kind.sourceText }.joined(separator: ", ") + "]"
    }

    private func attributesText(_ attributes: [AST.Attribute]) -> String {
        if attributes.isEmpty { return "" }
        return " " + attributes.map { attribute in
            var parts: [String] = []
            if !attribute.arguments.isEmpty {
                parts.append(
                    "(" + attribute.arguments.map { $0.map(\.value).joined(separator: " ") }
                        .joined(separator: ", ") + ")"
                )
            }
            if !attribute.labeledArguments.isEmpty {
                let sorted = attribute.labeledArguments.sorted { $0.key.pos.pos < $1.key.pos.pos }
                let labeled = sorted.map {
                    "\($0.key.value): \($0.value.map(\.value).joined(separator: " "))"
                }.joined(separator: ", ")
                parts.append("(" + labeled + ")")
            }
            return "#[" + attribute.name.value + parts.joined() + "]"
        }.joined(separator: " ")
    }

    private func tyText(_ ty: TrussType.TrussType?) -> String {
        guard let ty else { return "" }
        switch ty {
        case is TrussType.VoidType: return " ty:VoidType"
        case is TrussType.NeverType: return " ty:NeverType"
        case let named as TrussType.NamedType: return " ty:NamedType(\(named.name))"
        default: return " ty:?"
        }
    }

    private func symText(_ symbol: Symbol.Symbol?) -> String {
        guard let symbol else { return "" }
        return " sym:\(symbol.name)"
    }

    private func overloadsText(_ overloads: [Symbol.FunctionSymbol]?) -> String {
        guard let overloads, !overloads.isEmpty else { return "" }
        return " overloads:\(overloads.count)"
    }

    private func escapeString(_ value: String) -> String {
        var result = ""
        for ch in value {
            switch ch {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case "\0": result += "\\0"
            default: result.append(ch)
            }
        }
        return result
    }

    private func throwsText(_ throwsClause: AST.ThrowsClause?) -> String {
        guard let throwsClause else { return "" }
        if throwsClause.types == nil { return " throws" }
        return " throws(\(throwsClause.types!.count) types)"
    }

    private func declText(_ name: String, _ decl: AST.Decl) -> String {
        name + modifiersText(decl.modifiers) + attributesText(decl.attributes)
    }

    private func parameterNodes(_ parameters: [AST.FunctionDecl.Parameter]) -> [() -> Void] {
        parameters.map { parameter in
            {
                var text = "Parameter \(parameter.name.value)"
                if let label = parameter.label { text += " label:\(label.value)" }
                var children: [() -> Void] = []
                if let type = parameter.type { children.append { self.visit(type) } }
                if let defaultValue = parameter.defaultValue {
                    children.append { self.dumpNode("Default", children: [ { self.visit(defaultValue) } ]) }
                }
                self.dumpNode(text, children: children)
            }
        }
    }

    private func whereRequirementNode(_ requirement: AST.WhereRequirement) {
        var children: [() -> Void] = [ { self.visit(requirement.left) } ]
        switch requirement.constraint {
        case .conformance(let expression):
            children.append {
                self.dumpNode("Conformance", children: [ { self.visit(expression) } ])
            }
        case .equality(let expression):
            children.append {
                self.dumpNode("Equality", children: [ { self.visit(expression) } ])
            }
        }
        dumpNode("WhereRequirement", children: children)
    }

    private func whereClauseNodes(_ requirements: [AST.WhereRequirement]) -> [() -> Void] {
        requirements.map { requirement in
            { self.whereRequirementNode(requirement) }
        }
    }

    private func throwsClauseNodes(_ throwsClause: AST.ThrowsClause?) -> [() -> Void] {
        guard let throwsClause, let types = throwsClause.types else { return [] }
        return types.map { type in
            { self.dumpNode("Throws", children: [ { self.visit(type) } ]) }
        }
    }

    private func statementNodes(_ statements: [AST.Statement]) -> [() -> Void] {
        statements.map { statement in
            { self.visit(statement) }
        }
    }

    @discardableResult
    public override func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
        dumpNode("Program \"\(program.packageName)\"", children: statementNodes(program.statements))
        return nil
    }

    @discardableResult
    public override func visitGenericDecl(_ genericDecl: AST.GenericDecl, additional: Any? = nil) -> Any? {
        dumpNode(
            "GenericDecl",
            children: genericDecl.generics.map { generic in
                { self.visitGenericParameter(generic, additional: additional) }
            }
        )
        return nil
    }

    @discardableResult
    public override func visitGenericParameter(
        _ genericParameter: AST.GenericParameter, additional: Any? = nil
    ) -> Any? {
        var text = "GenericParameter "
        if genericParameter.eachToken != nil { text += "each " }
        text += genericParameter.name.value
        var children: [() -> Void] = []
        if let constraint = genericParameter.constraint {
            children.append { self.visit(constraint) }
        }
        dumpNode(text, children: children)
        return nil
    }

    @discardableResult
    public override func visitEmptyStatement(
        _ emptyStatement: AST.EmptyStatement, additional: Any? = nil
    ) -> Any? {
        dumpNode("EmptyStatement")
        return nil
    }

    @discardableResult
    public override func visitErrorStatement(
        _ errorStatement: AST.ErrorStatement, additional: Any? = nil
    ) -> Any? {
        dumpNode("ErrorStatement")
        return nil
    }

    @discardableResult
    public override func visitImport(_ importStatement: AST.Import, additional: Any? = nil) -> Any? {
        var text = "Import "
        text += importStatement.path.components.map { component in
            switch component {
            case .identifier(let token), .self_(let token): return token.value
            }
        }.joined(separator: ".")
        switch importStatement.selector {
        case .wholeModule(let alias):
            if let alias { text += " as \(alias.value)" }
        case .wildcard:
            text += ".*"
        case .explicit(let items):
            let rendered = items.map { item in
                var itemText: String
                switch item.kind {
                case .self_(let token), .name(let token): itemText = token.value
                }
                if let alias = item.alias { itemText += " as \(alias.value)" }
                return itemText
            }.joined(separator: ", ")
            text += ".{\(rendered)}"
        }
        dumpNode(text)
        return nil
    }

    @discardableResult
    public override func visitExternDecl(_ externDecl: AST.ExternDecl, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = []
        switch externDecl.body {
        case .Block(let statements):
            children.append(contentsOf: statementNodes(statements))
        case .Declaration(let decl):
            children.append { self.visit(decl) }
        }
        dumpNode(declText("ExternDecl \(externDecl.convention.value)", externDecl), children: children)
        return nil
    }

    @discardableResult
    public override func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
    ) -> Any? {
        dumpNode("ExpressionStatement", children: [ { self.visit(expressionStatement.expression) } ])
        return nil
    }

    @discardableResult
    public override func visitTypeAliasDecl(
        _ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil
    ) -> Any? {
        dumpNode(
            declText("TypeAliasDecl \(typeAliasDecl.name.value)", typeAliasDecl),
            children: [ { self.visit(typeAliasDecl.typeExpression) } ]
        )
        return nil
    }

    @discardableResult
    public override func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional: Any? = nil) -> Any? {
        dumpNode(
            declText("ModuleDecl \(moduleDecl.name.value)", moduleDecl) + symText(moduleDecl.symbol),
            children: statementNodes(moduleDecl.body)
        )
        return nil
    }

    @discardableResult
    public override func visitOperatorDecl(
        _ operatorDecl: AST.OperatorDecl, additional: Any? = nil
    ) -> Any? {
        let kindText: String
        switch operatorDecl.kind {
        case .Infix(let token): kindText = "infix \(token.value)"
        case .Prefix(let token): kindText = "prefix \(token.value)"
        case .Postfix(let token): kindText = "postfix \(token.value)"
        }
        dumpNode(declText("OperatorDecl \(kindText)", operatorDecl))
        return nil
    }

    @discardableResult
    public override func visitPrecedenceGroupDecl(
        _ precedenceGroupDecl: AST.PrecedenceGroupDecl, additional: Any? = nil
    ) -> Any? {
        var text = declText("PrecedenceGroupDecl \(precedenceGroupDecl.name.value)", precedenceGroupDecl)
        switch precedenceGroupDecl.associativity {
        case .Left: text += " [left]"
        case .Right: text += " [right]"
        case .None: break
        }
        if precedenceGroupDecl.assignment { text += " [assignment]" }
        var children: [() -> Void] = []
        if !precedenceGroupDecl.higherThan.isEmpty {
            children.append {
                self.dumpNode(
                    "HigherThan",
                    children: precedenceGroupDecl.higherThan.map { expression in
                        { self.visit(expression) }
                    }
                )
            }
        }
        if !precedenceGroupDecl.lowerThan.isEmpty {
            children.append {
                self.dumpNode(
                    "LowerThan",
                    children: precedenceGroupDecl.lowerThan.map { expression in
                        { self.visit(expression) }
                    }
                )
            }
        }
        dumpNode(text, children: children)
        return nil
    }

    private func typeDeclNodes(
        _ genericDecl: AST.GenericDecl?, _ conformances: [AST.Expression],
        _ whereClause: [AST.WhereRequirement]?, _ body: [AST.Statement]
    ) -> [() -> Void] {
        var children: [() -> Void] = []
        if let genericDecl { children.append { self.visitGenericDecl(genericDecl) } }
        for conformance in conformances {
            children.append { self.dumpNode("Conformance", children: [ { self.visit(conformance) } ]) }
        }
        if let whereClause { children.append(contentsOf: whereClauseNodes(whereClause)) }
        children.append(contentsOf: statementNodes(body))
        return children
    }

    @discardableResult
    public override func visitStructDecl(_ structDecl: AST.StructDecl, additional: Any? = nil) -> Any? {
        dumpNode(
            declText("StructDecl \(structDecl.name.value)", structDecl),
            children: typeDeclNodes(
                structDecl.genericDecl, structDecl.conformances, structDecl.whereClause, structDecl.body)
        )
        return nil
    }

    @discardableResult
    public override func visitClassDecl(_ classDecl: AST.ClassDecl, additional: Any? = nil) -> Any? {
        dumpNode(
            declText("ClassDecl \(classDecl.name.value)", classDecl),
            children: typeDeclNodes(
                classDecl.genericDecl, classDecl.inheritanceClauses, classDecl.whereClause,
                classDecl.body)
        )
        return nil
    }

    @discardableResult
    public override func visitActorDecl(_ actorDecl: AST.ActorDecl, additional: Any? = nil) -> Any? {
        dumpNode(
            declText("ActorDecl \(actorDecl.name.value)", actorDecl),
            children: typeDeclNodes(
                actorDecl.genericDecl, actorDecl.conformances, actorDecl.whereClause, actorDecl.body)
        )
        return nil
    }

    @discardableResult
    public override func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional: Any? = nil) -> Any? {
        dumpNode(
            declText("ProtocolDecl \(protocolDecl.name.value)", protocolDecl),
            children: typeDeclNodes(
                protocolDecl.genericDecl, protocolDecl.conformances, protocolDecl.whereClause,
                protocolDecl.body)
        )
        return nil
    }

    @discardableResult
    public override func visitExtensionDecl(_ extensionDecl: AST.ExtensionDecl, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [ { self.visit(extensionDecl.base) } ]
        for conformance in extensionDecl.conformances {
            children.append { self.dumpNode("Conformance", children: [ { self.visit(conformance) } ]) }
        }
        children.append(contentsOf: statementNodes(extensionDecl.body))
        dumpNode(declText("ExtensionDecl", extensionDecl), children: children)
        return nil
    }

    @discardableResult
    public override func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional: Any? = nil) -> Any? {
        dumpNode(
            declText("EnumDecl \(enumDecl.name.value)", enumDecl),
            children: typeDeclNodes(
                enumDecl.genericDecl, enumDecl.conformances, enumDecl.whereClause, enumDecl.body)
        )
        return nil
    }

    @discardableResult
    public override func visitEnumCaseDecl(
        _ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = []
        for element in enumCaseDecl.elements {
            children.append {
                var elementChildren: [() -> Void] = []
                for associatedValue in element.associatedValues {
                    elementChildren.append {
                        var text = "AssociatedValue "
                        if let label = associatedValue.label { text += "\(label.value):" }
                        self.dumpNode(text, children: [ { self.visit(associatedValue.typeExpression) } ])
                    }
                }
                if let rawValue = element.rawValue {
                    elementChildren.append { self.dumpNode("RawValue", children: [ { self.visit(rawValue) } ]) }
                }
                self.dumpNode("Element \(element.name.value)", children: elementChildren)
            }
        }
        dumpNode(declText("EnumCaseDecl", enumCaseDecl), children: children)
        return nil
    }

    @discardableResult
    public override func visitInitDecl(_ initDecl: AST.InitDecl, additional: Any? = nil) -> Any? {
        var text = declText("InitDecl", initDecl)
        if initDecl.optionalToken != nil { text += " ?" }
        var children: [() -> Void] = []
        if let genericDecl = initDecl.genericDecl { children.append { self.visitGenericDecl(genericDecl) } }
        children.append(contentsOf: parameterNodes(initDecl.parameters))
        if let throwsClause = initDecl.throwsClause {
            text += throwsText(throwsClause)
            children.append(contentsOf: throwsClauseNodes(throwsClause))
        }
        children.append(contentsOf: statementNodes(initDecl.body))
        dumpNode(text, children: children)
        return nil
    }

    @discardableResult
    public override func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional: Any? = nil) -> Any? {
        dumpNode(declText("DeinitDecl", deinitDecl), children: statementNodes(deinitDecl.body))
        return nil
    }

    @discardableResult
    public override func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional: Any? = nil
    ) -> Any? {
        var text = declText("FunctionDecl \(functionDecl.name.value)", functionDecl)
        if functionDecl.varargToken != nil { text += " [vararg]" }
        if let throwsClause = functionDecl.throwsClause { text += throwsText(throwsClause) }
        text += symText(functionDecl.symbol)
        var children: [() -> Void] = []
        if let genericDecl = functionDecl.genericDecl { children.append { self.visitGenericDecl(genericDecl) } }
        children.append(contentsOf: parameterNodes(functionDecl.parameters))
        if let throwsClause = functionDecl.throwsClause {
            children.append(contentsOf: throwsClauseNodes(throwsClause))
        }
        if let returnTypeExpression = functionDecl.returnTypeExpression {
            children.append { self.visit(returnTypeExpression) }
        }
        switch functionDecl.body {
        case .Block(let statements):
            children.append(contentsOf: statementNodes(statements))
        case .Expression(let expression):
            children.append { self.dumpNode("BodyExpression", children: [ { self.visit(expression) } ]) }
        case nil:
            break
        }
        dumpNode(text, children: children)
        return nil
    }

    @discardableResult
    public override func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        var text = declText("VariableDecl \(variableDecl.name.value)", variableDecl)
        if variableDecl.internalToken != nil { text += " [internal]" }
        text += symText(variableDecl.symbol)
        var children: [() -> Void] = []
        if let typeExpression = variableDecl.typeExpression {
            children.append { self.dumpNode("Type", children: [ { self.visit(typeExpression) } ]) }
        }
        if let initializer = variableDecl.initializer {
            children.append { self.dumpNode("Initializer", children: [ { self.visit(initializer) } ]) }
        }
        for accessor in variableDecl.accessors {
            children.append { self.visitAccessor(accessor, additional: additional) }
        }
        dumpNode(text, children: children)
        return nil
    }

    @discardableResult
    public override func visitReturn(_ ret: AST.Return, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = []
        if let value = ret.value { children.append { self.visit(value) } }
        dumpNode("Return", children: children)
        return nil
    }

    @discardableResult
    public override func visitThrow(_ throwStatement: AST.Throw, additional: Any? = nil) -> Any? {
        dumpNode("Throw", children: [ { self.visit(throwStatement.expression) } ])
        return nil
    }

    @discardableResult
    public override func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [ { self.visit(whileStatement.condition) } ]
        children.append(contentsOf: statementNodes(whileStatement.body))
        dumpNode("While", children: children)
        return nil
    }

    @discardableResult
    public override func visitRepeatWhile(_ repeatWhile: AST.RepeatWhile, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = []
        children.append(contentsOf: statementNodes(repeatWhile.body))
        children.append { self.visit(repeatWhile.condition) }
        dumpNode("RepeatWhile", children: children)
        return nil
    }

    @discardableResult
    public override func visitGuard(_ guardStatement: AST.Guard, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [ { self.visit(guardStatement.condition) } ]
        children.append(contentsOf: statementNodes(guardStatement.body))
        dumpNode("Guard", children: children)
        return nil
    }

    @discardableResult
    public override func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
        var text = "For"
        if forStatement.asyncToken != nil { text += " async" }
        var children: [() -> Void] = [
            { self.dumpNode("Pattern", children: [ { self.visit(forStatement.pattern) } ]) },
            { self.dumpNode("Sequence", children: [ { self.visit(forStatement.sequence) } ]) },
        ]
        children.append(contentsOf: statementNodes(forStatement.body))
        dumpNode(text, children: children)
        return nil
    }

    @discardableResult
    public override func visitDefer(_ deferStatement: AST.Defer, additional: Any? = nil) -> Any? {
        dumpNode("Defer", children: statementNodes(deferStatement.body))
        return nil
    }

    @discardableResult
    public override func visitAsm(_ asmStatement: AST.Asm, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = []
        for template in asmStatement.templates {
            children.append { self.visit(template) }
        }
        for binding in asmStatement.bindings {
            children.append {
                var text = "Binding \(binding.name.value) = \(binding.kind.value)(\(binding.constraint.value))"
                if let local = binding.local { text += " \(local.value)" }
                self.dumpNode(text)
            }
        }
        if !asmStatement.options.isEmpty {
            children.append {
                self.dumpNode("Options \(asmStatement.options.map(\.value).joined(separator: ", "))")
            }
        }
        dumpNode("Asm", children: children)
        return nil
    }

    @discardableResult
    public override func visitBreak(_ breakStatement: AST.Break, additional: Any? = nil) -> Any? {
        var text = "Break"
        if let label = breakStatement.label { text += " \(label.value)" }
        dumpNode(text)
        return nil
    }

    @discardableResult
    public override func visitContinue(_ continueStatement: AST.Continue, additional: Any? = nil) -> Any? {
        var text = "Continue"
        if let label = continueStatement.label { text += " \(label.value)" }
        dumpNode(text)
        return nil
    }

    @discardableResult
    public override func visitGoto(_ gotoStatement: AST.Goto, additional: Any? = nil) -> Any? {
        dumpNode("Goto \(gotoStatement.label.value)")
        return nil
    }

    @discardableResult
    public override func visitLabeledStatement(
        _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
    ) -> Any? {
        dumpNode(
            "LabeledStatement \(labeledStatement.label.value)",
            children: [ { self.visit(labeledStatement.body) } ]
        )
        return nil
    }

    @discardableResult
    public override func visitAccessor(_ accessor: AST.Accessor, additional: Any? = nil) -> Any? {
        var text: String
        switch accessor.kind {
        case .Get: text = "Accessor get"
        case .Set: text = "Accessor set"
        case .WillSet: text = "Accessor willSet"
        case .DidSet: text = "Accessor didSet"
        }
        if let parameterName = accessor.parameterName { text += " \(parameterName.value)" }
        text += modifiersText(accessor.modifiers) + attributesText(accessor.attributes)
        var children: [() -> Void] = []
        switch accessor.body {
        case .Block(let statements):
            children.append(contentsOf: statementNodes(statements))
        case .Expression(let expression):
            children.append { self.dumpNode("BodyExpression", children: [ { self.visit(expression) } ]) }
        }
        dumpNode(text, children: children)
        return nil
    }

    @discardableResult
    public override func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
    ) -> Any? {
        var text = declText("SubscriptDecl", subscriptDecl)
        if let throwsClause = subscriptDecl.throwsClause { text += throwsText(throwsClause) }
        var children: [() -> Void] = []
        if let genericDecl = subscriptDecl.genericDecl { children.append { self.visitGenericDecl(genericDecl) } }
        children.append(contentsOf: parameterNodes(subscriptDecl.parameters))
        if let throwsClause = subscriptDecl.throwsClause {
            children.append(contentsOf: throwsClauseNodes(throwsClause))
        }
        children.append { self.dumpNode("ReturnType", children: [ { self.visit(subscriptDecl.returnType) } ]) }
        children.append(contentsOf: statementNodes(subscriptDecl.body))
        dumpNode(text, children: children)
        return nil
    }

    @discardableResult
    public override func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = []
        if let constraint = associatedTypeDecl.constraint {
            children.append { self.dumpNode("Constraint", children: [ { self.visit(constraint) } ]) }
        }
        if let whereClause = associatedTypeDecl.whereClause {
            children.append(contentsOf: whereClauseNodes(whereClause))
        }
        dumpNode(declText("AssociatedTypeDecl \(associatedTypeDecl.name.value)", associatedTypeDecl), children: children)
        return nil
    }

    @discardableResult
    public override func visitErrorExpression(
        _ errorExpression: AST.ErrorExpression, additional: Any? = nil
    ) -> Any? {
        dumpNode("ErrorExpression" + tyText(errorExpression.ty))
        return nil
    }

    @discardableResult
    public override func visitParentheticalExpression(
        _ parentheticalExpression: AST.ParentheticalExpression, additional: Any? = nil
    ) -> Any? {
        dumpNode(
            "ParentheticalExpression" + tyText(parentheticalExpression.ty),
            children: [ { self.visit(parentheticalExpression.inner) } ]
        )
        return nil
    }

    @discardableResult
    public override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        dumpNode(
            "Variable \(variable.name.value)" + tyText(variable.ty) + symText(variable.symbol)
                + overloadsText(variable.overloads))
        return nil
    }

    @discardableResult
    public override func visitGenericApplication(
        _ genericApplication: AST.GenericApplication, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = [ { self.visit(genericApplication.base) } ]
        for argument in genericApplication.genericArguments {
            children.append { self.dumpNode("Argument", children: [ { self.visit(argument) } ]) }
        }
        dumpNode("GenericApplication" + tyText(genericApplication.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode("IntegerLiteral \(integerLiteral.token.value)" + tyText(integerLiteral.ty))
        return nil
    }

    @discardableResult
    public override func visitFloatLiteral(
        _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode("FloatLiteral \(floatLiteral.token.value)" + tyText(floatLiteral.ty))
        return nil
    }

    @discardableResult
    public override func visitStringLiteral(
        _ stringLiteral: AST.StringLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode("StringLiteral \"\(escapeString(stringLiteral.token.value))\"" + tyText(stringLiteral.ty))
        return nil
    }

    @discardableResult
    public override func visitCharLiteral(
        _ charLiteral: AST.CharLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode("CharLiteral \(charLiteral.token.value)" + tyText(charLiteral.ty))
        return nil
    }

    @discardableResult
    public override func visitBoolLiteral(
        _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode("BoolLiteral \(boolLiteral.token.value)" + tyText(boolLiteral.ty))
        return nil
    }

    @discardableResult
    public override func visitNullLiteral(
        _ nullLiteral: AST.NullLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode("NullLiteral" + tyText(nullLiteral.ty))
        return nil
    }

    @discardableResult
    public override func visitVoidLiteral(
        _ voidLiteral: AST.VoidLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode("VoidLiteral" + tyText(voidLiteral.ty))
        return nil
    }

    @discardableResult
    public override func visitIf(_ ifExpression: AST.If, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [
            { self.dumpNode("Condition", children: [ { self.visit(ifExpression.condition) } ]) }
        ]
        children.append(contentsOf: statementNodes(ifExpression.then))
        if let elseKind = ifExpression.elseKind {
            switch elseKind {
            case .Block(let statements):
                children.append { self.dumpNode("Else", children: self.statementNodes(statements)) }
            case .If(let elseIfExpression):
                children.append { self.dumpNode("Else", children: [ { self.visitIf(elseIfExpression) } ]) }
            }
        }
        dumpNode("If" + tyText(ifExpression.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitMatch(_ matchExpression: AST.Match, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [
            { self.dumpNode("Subject", children: [ { self.visit(matchExpression.subject) } ]) }
        ]
        for matchCase in matchExpression.cases {
            children.append {
                var caseChildren: [() -> Void] = []
                for pattern in matchCase.patterns {
                    caseChildren.append { self.dumpNode("Pattern", children: [ { self.visit(pattern) } ]) }
                }
                caseChildren.append(contentsOf: self.statementNodes(matchCase.body))
                self.dumpNode("Case", children: caseChildren)
            }
        }
        dumpNode("Match" + tyText(matchExpression.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitDo(_ doExpression: AST.Do, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = []
        children.append(contentsOf: statementNodes(doExpression.body))
        for catchClause in doExpression.catches {
            children.append {
                var catchChildren: [() -> Void] = []
                if let pattern = catchClause.pattern {
                    catchChildren.append { self.dumpNode("Pattern", children: [ { self.visit(pattern) } ]) }
                }
                if let whereCondition = catchClause.whereCondition {
                    catchChildren.append {
                        self.dumpNode("Where", children: [ { self.visit(whereCondition) } ])
                    }
                }
                catchChildren.append(contentsOf: self.statementNodes(catchClause.body))
                self.dumpNode("Catch", children: catchChildren)
            }
        }
        if let finallyBody = doExpression.finallyBody {
            children.append { self.dumpNode("Finally", children: self.statementNodes(finallyBody)) }
        }
        dumpNode("Do" + tyText(doExpression.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [ { self.visit(call.callee) } ]
        for argument in call.arguments {
            children.append {
                var text = "Argument"
                if let label = argument.label { text += " label:\(label.value)" }
                self.dumpNode(text, children: [ { self.visit(argument.value) } ])
            }
        }
        for (label, closure) in call.trailingClosures {
            children.append {
                var text = "TrailingClosure"
                if let label { text += " label:\(label.value)" }
                self.dumpNode(text, children: [ { self.visitClosure(closure) } ])
            }
        }
        dumpNode("Call" + tyText(call.ty) + overloadsText(call.overloads), children: children)
        return nil
    }

    @discardableResult
    public override func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional: Any? = nil
    ) -> Any? {
        var text = "MemberAccess \(memberAccess.member.value)"
        if memberAccess.isOptional { text += " ?" }
        dumpNode(
            text + tyText(memberAccess.ty) + symText(memberAccess.symbol)
                + overloadsText(memberAccess.overloads),
            children: [ { self.visit(memberAccess.object) } ])
        return nil
    }

    @discardableResult
    public override func visitSelfTypeExpression(
        _ selfTypeExpression: AST.SelfTypeExpression, additional: Any? = nil
    ) -> Any? {
        dumpNode("SelfTypeExpression" + tyText(selfTypeExpression.ty))
        return nil
    }

    @discardableResult
    public override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        dumpNode("SelfExpression" + tyText(selfExpression.ty))
        return nil
    }

    @discardableResult
    public override func visitSuperExpression(
        _ superExpression: AST.SuperExpression, additional: Any? = nil
    ) -> Any? {
        dumpNode("SuperExpression" + tyText(superExpression.ty))
        return nil
    }

    @discardableResult
    public override func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        dumpNode("ImplicitMemberAccess \(implicitMemberAccess.name.value)" + tyText(implicitMemberAccess.ty))
        return nil
    }

    @discardableResult
    public override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = []
        if let signature = closure.signature {
            children.append {
                var text = "Signature"
                if signature.asyncToken != nil { text += " async" }
                if !signature.captureList.isEmpty {
                    text += " [" + signature.captureList.map { item in
                        var itemText = item.name.value
                        if let specifier = item.specifier { itemText = specifier.value + " " + itemText }
                        return itemText
                    }.joined(separator: ", ") + "]"
                }
                if let throwsClause = signature.throwsClause { text += self.throwsText(throwsClause) }
                var signatureChildren: [() -> Void] = self.parameterNodes(signature.parameters)
                if let throwsClause = signature.throwsClause {
                    signatureChildren.append(contentsOf: self.throwsClauseNodes(throwsClause))
                }
                if let returnType = signature.returnType {
                    signatureChildren.append { self.visit(returnType) }
                }
                self.dumpNode(text, children: signatureChildren)
            }
        }
        children.append(contentsOf: statementNodes(closure.body))
        dumpNode("Closure" + tyText(closure.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitClosureType(
        _ closureType: AST.ClosureType, additional: Any? = nil
    ) -> Any? {
        var text = "ClosureType"
        if let throwsClause = closureType.throwsClause { text += throwsText(throwsClause) }
        var children: [() -> Void] = [ { self.visit(closureType.parameterTypes) } ]
        if let throwsClause = closureType.throwsClause {
            children.append(contentsOf: throwsClauseNodes(throwsClause))
        }
        children.append { self.visit(closureType.returnType) }
        dumpNode(text + tyText(closureType.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitOptionalType(_ optionalType: AST.OptionalType, additional: Any? = nil) -> Any? {
        dumpNode("OptionalType ?" + tyText(optionalType.ty), children: [ { self.visit(optionalType.wrappedType) } ])
        return nil
    }

    @discardableResult
    public override func visitVariadicType(_ variadicType: AST.VariadicType, additional: Any? = nil) -> Any? {
        dumpNode("VariadicType ..." + tyText(variadicType.ty), children: [ { self.visit(variadicType.base) } ])
        return nil
    }

    @discardableResult
    public override func visitSomeType(_ someType: AST.SomeType, additional: Any? = nil) -> Any? {
        dumpNode("SomeType some" + tyText(someType.ty), children: [ { self.visit(someType.wrappedType) } ])
        return nil
    }

    @discardableResult
    public override func visitAnyType(_ anyType: AST.AnyType, additional: Any? = nil) -> Any? {
        dumpNode("AnyType any" + tyText(anyType.ty), children: [ { self.visit(anyType.wrappedType) } ])
        return nil
    }

    @discardableResult
    public override func visitProtocolCompositionType(
        _ protocolCompositionType: AST.ProtocolCompositionType, additional: Any? = nil
    ) -> Any? {
        dumpNode(
            "ProtocolCompositionType &" + tyText(protocolCompositionType.ty),
            children: protocolCompositionType.types.map { type in
                { self.visit(type) }
            }
        )
        return nil
    }

    @discardableResult
    public override func visitTupleExpression(
        _ tupleExpression: AST.TupleExpression, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = []
        for element in tupleExpression.elements {
            children.append {
                var text = "Element"
                if let label = element.label { text += " label:\(label.value)" }
                self.dumpNode(text, children: [ { self.visit(element.value) } ])
            }
        }
        dumpNode("TupleExpression" + tyText(tupleExpression.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitIsPattern(_ isPattern: AST.IsPattern, additional: Any? = nil) -> Any? {
        dumpNode("IsPattern is", children: [ { self.visit(isPattern.typeExpression) } ])
        return nil
    }

    @discardableResult
    public override func visitAsPattern(_ asPattern: AST.AsPattern, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [ { self.visit(asPattern.pattern) } ]
        children.append { self.visit(asPattern.typeExpression) }
        dumpNode("AsPattern as", children: children)
        return nil
    }

    @discardableResult
    public override func visitSequentialExpression(
        _ sequentialExpression: AST.SequentialExpression, additional: Any? = nil
    ) -> Any? {
        var text = "SequentialExpression "
        if sequentialExpression.ops.isEmpty {
            text += "(no ops)"
        } else {
            text += sequentialExpression.ops.map(\.value).joined(separator: " ")
        }
        dumpNode(
            text + tyText(sequentialExpression.ty),
            children: sequentialExpression.operands.map { operand in
                { self.visit(operand) }
            }
        )
        return nil
    }

    @discardableResult
    public override func visitBinary(_ binary: AST.Binary, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [ { self.visit(binary.left) } ]
        children.append { self.visit(binary.right) }
        dumpNode("Binary \(binary.operatorToken.value)" + tyText(binary.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitPrefix(_ prefixExpression: AST.Prefix, additional: Any? = nil) -> Any? {
        dumpNode(
            "Prefix \(prefixExpression.operatorToken.value)" + tyText(prefixExpression.ty),
            children: [ { self.visit(prefixExpression.expression) } ]
        )
        return nil
    }

    @discardableResult
    public override func visitPostfix(_ postfixExpression: AST.Postfix, additional: Any? = nil) -> Any? {
        dumpNode(
            "Postfix \(postfixExpression.operatorToken.value)" + tyText(postfixExpression.ty),
            children: [ { self.visit(postfixExpression.expression) } ]
        )
        return nil
    }

    @discardableResult
    public override func visitArrayLiteral(
        _ arrayLiteral: AST.ArrayLiteral, additional: Any? = nil
    ) -> Any? {
        dumpNode(
            "ArrayLiteral" + tyText(arrayLiteral.ty),
            children: arrayLiteral.elements.map { element in
                { self.visit(element) }
            }
        )
        return nil
    }

    @discardableResult
    public override func visitDictionaryLiteral(
        _ dictionaryLiteral: AST.DictionaryLiteral, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = []
        for entry in dictionaryLiteral.entries {
            children.append {
                let entryChildren: [() -> Void] = [
                    { self.dumpNode("Key", children: [ { self.visit(entry.key) } ]) },
                    { self.dumpNode("Value", children: [ { self.visit(entry.value) } ]) },
                ]
                self.dumpNode("Entry", children: entryChildren)
            }
        }
        dumpNode("DictionaryLiteral" + tyText(dictionaryLiteral.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitCastExpression(
        _ castExpression: AST.CastExpression, additional: Any? = nil
    ) -> Any? {
        let kindText: String
        switch castExpression.kind {
        case .As: kindText = "as"
        case .AsQuestion: kindText = "as?"
        case .AsExclamation: kindText = "as!"
        case .Is: kindText = "is"
        }
        var children: [() -> Void] = [ { self.visit(castExpression.left) } ]
        children.append { self.visit(castExpression.right) }
        dumpNode("CastExpression \(kindText)" + tyText(castExpression.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitTryExpression(
        _ tryExpression: AST.TryExpression, additional: Any? = nil
    ) -> Any? {
        let kindText: String
        switch tryExpression.kind {
        case .Try: kindText = "try"
        case .TryQuestion: kindText = "try?"
        case .TryExclamation: kindText = "try!"
        }
        dumpNode(
            "TryExpression \(kindText)" + tyText(tryExpression.ty),
            children: [ { self.visit(tryExpression.expression) } ]
        )
        return nil
    }

    @discardableResult
    public override func visitAwaitExpression(
        _ awaitExpression: AST.AwaitExpression, additional: Any? = nil
    ) -> Any? {
        dumpNode(
            "AwaitExpression await" + tyText(awaitExpression.ty),
            children: [ { self.visit(awaitExpression.expression) } ]
        )
        return nil
    }

    @discardableResult
    public override func visitSubscript(_ subscriptExpr: AST.Subscript, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [ { self.visit(subscriptExpr.base) } ]
        for argument in subscriptExpr.arguments {
            children.append {
                var text = "Argument"
                if let label = argument.label { text += " label:\(label.value)" }
                self.dumpNode(text, children: [ { self.visit(argument.value) } ])
            }
        }
        dumpNode("Subscript" + tyText(subscriptExpr.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitOptionalBinding(
        _ optionalBinding: AST.OptionalBinding, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = []
        if let typeExpression = optionalBinding.typeExpression {
            children.append { self.visit(typeExpression) }
        }
        children.append { self.visit(optionalBinding.value) }
        dumpNode("OptionalBinding \(optionalBinding.name.value)" + tyText(optionalBinding.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitCaseMatch(_ caseMatch: AST.CaseMatch, additional: Any? = nil) -> Any? {
        var children: [() -> Void] = [
            { self.dumpNode("Pattern", children: [ { self.visit(caseMatch.pattern) } ]) }
        ]
        children.append { self.visit(caseMatch.subject) }
        dumpNode("CaseMatch" + tyText(caseMatch.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitBindingPattern(
        _ bindingPattern: AST.BindingPattern, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = []
        if let typeExpression = bindingPattern.typeExpression {
            children.append { self.visit(typeExpression) }
        }
        if let subpattern = bindingPattern.subpattern {
            children.append { self.visit(subpattern) }
        }
        dumpNode("BindingPattern \(bindingPattern.name.value)" + tyText(bindingPattern.ty), children: children)
        return nil
    }

    @discardableResult
    public override func visitWildcardPattern(
        _ wildcardPattern: AST.WildcardPattern, additional: Any? = nil
    ) -> Any? {
        dumpNode("WildcardPattern _" + tyText(wildcardPattern.ty))
        return nil
    }

    @discardableResult
    public override func visitShorthandArgument(
        _ shorthandArgument: AST.ShorthandArgument, additional: Any? = nil
    ) -> Any? {
        dumpNode("ShorthandArgument $\(shorthandArgument.index)" + tyText(shorthandArgument.ty))
        return nil
    }

    @discardableResult
    public override func visitStringInterpolation(
        _ interpolation: AST.StringInterpolation, additional: Any? = nil
    ) -> Any? {
        var children: [() -> Void] = []
        for segment in interpolation.segments {
            switch segment {
            case .literal(let token):
                children.append { self.dumpNode("Literal \"\(self.escapeString(token.value))\"") }
            case .expression(let expression):
                children.append { self.dumpNode("Interpolation", children: [ { self.visit(expression) } ]) }
            }
        }
        dumpNode("StringInterpolation" + tyText(interpolation.ty), children: children)
        return nil
    }
}
