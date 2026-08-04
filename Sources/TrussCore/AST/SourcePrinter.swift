public final class SourcePrinter: AST.Visitor {
    private final class State {
        var text = ""
        var indent = 0
        func write(_ s: String) {
            text += s
        }

        func indentPrefix() -> String {
            String(repeating: "    ", count: indent)
        }
    }

    private let state = State()

    public func print(_ node: AST.AstNode) -> String {
        visit(node)
        while state.text.hasPrefix("\n") {
            state.text.removeFirst()
        }
        return state.text
    }

    private func beginLine() {
        state.write("\n" + state.indentPrefix())
    }

    private func printStatements(_ statements: [AST.Statement]) {
        for statement in statements {
            beginLine()
            visit(statement)
        }
    }

    private func appendBlock(_ statements: [AST.Statement]) {
        if statements.isEmpty {
            state.write(" {}")
        } else {
            state.write(" {")
            state.indent += 1
            printStatements(statements)
            state.indent -= 1
            beginLine()
            state.write("}")
        }
    }

    private func blockHeader(_ header: String, _ statements: [AST.Statement]) {
        state.write(header)
        appendBlock(statements)
    }

    private func render(_ node: AST.AstNode) -> String {
        let saved = state.text
        state.text = ""
        visit(node)
        let result = state.text
        state.text = saved
        return result
    }

    private func encodeString(_ value: String) -> String {
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

    private func modifiersText(_ modifiers: [AST.Modifier]) -> String {
        modifiers.map { $0.kind.sourceText }.joined(separator: " ")
    }

    private func attributesText(_ attributes: [AST.Attribute]) -> String {
        attributes.map { attribute in
            var parts: [String] = []
            if !attribute.arguments.isEmpty {
                parts.append(
                    "("
                        + attribute.arguments.map { $0.map(\.value).joined(separator: " ") }
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

    private func annotations(_ modifiers: [AST.Modifier], _ attributes: [AST.Attribute]) -> String {
        var text = attributesText(attributes)
        if !modifiers.isEmpty {
            if !text.isEmpty { text += " " }
            text += modifiersText(modifiers)
        }
        if !text.isEmpty { text += " " }
        return text
    }

    private func genericDeclText(_ genericDecl: AST.GenericDecl) -> String {
        "<"
            + genericDecl.generics.map { generic in
                var text = ""
                if generic.eachToken != nil { text += "each " }
                text += generic.name.value
                if let constraint = generic.constraint { text += ": " + render(constraint) }
                return text
            }.joined(separator: ", ") + ">"
    }

    private func parameterText(_ parameter: AST.FunctionDecl.Parameter) -> String {
        var text = ""
        if let label = parameter.label {
            if label.value != parameter.name.value {
                text += label.value + " "
            }
        } else {
            text += "_ "
        }
        text += parameter.name.value
        if let type = parameter.type {
            text += ": " + render(type)
        }
        if let defaultValue = parameter.defaultValue {
            text += " = " + render(defaultValue)
        }
        return text
    }

    private func parametersText(
        _ parameters: [AST.FunctionDecl.Parameter], vararg: Bool = false
    ) -> String {
        var text = "("
        for (index, parameter) in parameters.enumerated() {
            if index > 0 { text += ", " }
            text += parameterText(parameter)
            if vararg && index == parameters.count - 1 { text += "..." }
        }
        text += ")"
        return text
    }

    private func throwsClauseText(_ throwsClause: AST.ThrowsClause) -> String {
        if let types = throwsClause.types {
            return "throws(" + types.map { render($0) }.joined(separator: ", ") + ")"
        }
        return "throws"
    }

    private func whereClauseText(_ requirements: [AST.WhereRequirement]) -> String {
        " where "
            + requirements.map { requirement in
                var text = render(requirement.left)
                switch requirement.constraint {
                case let .conformance(expression): text += ": " + render(expression)
                case let .equality(expression): text += " == " + render(expression)
                }
                return text
            }.joined(separator: ", ")
    }

    @discardableResult
    override public func visitProgram(_ program: AST.Program, additional _: Any? = nil) -> Any? {
        for (index, statement) in program.statements.enumerated() {
            if index > 0 { state.write("\n") }
            beginLine()
            visit(statement)
        }
        return nil
    }

    @discardableResult
    override public func visitGenericDecl(_ genericDecl: AST.GenericDecl, additional _: Any? = nil)
        -> Any?
    {
        state.write(genericDeclText(genericDecl))
        return nil
    }

    @discardableResult
    override public func visitGenericParameter(
        _ genericParameter: AST.GenericParameter, additional _: Any? = nil
    ) -> Any? {
        if genericParameter.eachToken != nil { state.write("each ") }
        state.write(genericParameter.name.value)
        if let constraint = genericParameter.constraint {
            state.write(": ")
            visit(constraint)
        }
        return nil
    }

    @discardableResult
    override public func visitEmptyStatement(
        _ emptyStatement: AST.EmptyStatement, additional _: Any? = nil
    ) -> Any? {
        state.write(emptyStatement.token.value)
        return nil
    }

    @discardableResult
    override public func visitErrorStatement(
        _: AST.ErrorStatement, additional _: Any? = nil
    ) -> Any? {
        state.write("<error>")
        return nil
    }

    @discardableResult
    override public func visitImport(_ importStatement: AST.Import, additional _: Any? = nil) -> Any? {
        state.write("import ")
        for (index, component) in importStatement.path.components.enumerated() {
            if index > 0 { state.write(".") }
            switch component {
            case let .identifier(token), let .self_(token):
                state.write(token.value)
            }
        }
        switch importStatement.selector {
        case let .wholeModule(alias):
            if let alias { state.write(" as " + alias.value) }
        case .wildcard:
            state.write(".*")
        case let .explicit(items):
            let rendered = items.map { item in
                var text: String
                switch item.kind {
                case let .self_(token), let .name(token): text = token.value
                }
                if let alias = item.alias { text += " as " + alias.value }
                return text
            }.joined(separator: ", ")
            state.write(".{" + rendered + "}")
        }
        return nil
    }

    @discardableResult
    override public func visitExternDecl(_ externDecl: AST.ExternDecl, additional _: Any? = nil)
        -> Any?
    {
        state.write(annotations(externDecl.modifiers, externDecl.attributes))
        state.write("extern " + externDecl.convention.value)
        switch externDecl.body {
        case let .Block(statements):
            appendBlock(statements)
        case let .Declaration(decl):
            state.write(" ")
            visit(decl)
        }
        return nil
    }

    @discardableResult
    override public func visitExpressionStatement(
        _ expressionStatement: AST.ExpressionStatement, additional _: Any? = nil
    ) -> Any? {
        visit(expressionStatement.expression)
        return nil
    }

    @discardableResult
    override public func visitTypeAliasDecl(
        _ typeAliasDecl: AST.TypeAliasDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(typeAliasDecl.modifiers, typeAliasDecl.attributes))
        state.write("typealias " + typeAliasDecl.name.value + " = ")
        visit(typeAliasDecl.typeExpression)
        return nil
    }

    @discardableResult
    override public func visitModuleDecl(_ moduleDecl: AST.ModuleDecl, additional _: Any? = nil)
        -> Any?
    {
        state.write(annotations(moduleDecl.modifiers, moduleDecl.attributes))
        state.write("module " + moduleDecl.name.value)
        appendBlock(moduleDecl.body)
        return nil
    }

    @discardableResult
    override public func visitOperatorDecl(
        _ operatorDecl: AST.OperatorDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(operatorDecl.modifiers, operatorDecl.attributes))
        state.write("operator " + operatorDecl.name.value + " ")
        switch operatorDecl.kind {
        case let .Infix(token), let .Prefix(token), let .Postfix(token):
            state.write(token.value)
        }
        return nil
    }

    @discardableResult
    override public func visitPrecedenceGroupDecl(
        _ precedenceGroupDecl: AST.PrecedenceGroupDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(precedenceGroupDecl.modifiers, precedenceGroupDecl.attributes))
        state.write("precedencegroup " + precedenceGroupDecl.name.value + " {")
        state.indent += 1
        for expression in precedenceGroupDecl.higherThan {
            beginLine()
            state.write("higherThan: " + render(expression))
        }
        for expression in precedenceGroupDecl.lowerThan {
            beginLine()
            state.write("lowerThan: " + render(expression))
        }
        if precedenceGroupDecl.associativityToken != nil {
            beginLine()
            state.write("associativity: ")
            switch precedenceGroupDecl.associativity {
            case .Left: state.write("left")
            case .Right: state.write("right")
            case .None: state.write("none")
            }
        }
        if precedenceGroupDecl.assignmentToken != nil {
            beginLine()
            state.write("assignment: " + (precedenceGroupDecl.assignment ? "true" : "false"))
        }
        state.indent -= 1
        beginLine()
        state.write("}")
        return nil
    }

    private func typeDeclHeader(
        _ keyword: String, _ name: Token, _ genericDecl: AST.GenericDecl?,
        _ conformances: [AST.Expression], _ whereClause: [AST.WhereRequirement]?
    ) {
        state.write(keyword + " " + name.value)
        if let genericDecl { state.write(genericDeclText(genericDecl)) }
        if !conformances.isEmpty {
            state.write(": " + conformances.map { render($0) }.joined(separator: ", "))
        }
        if let whereClause { state.write(whereClauseText(whereClause)) }
    }

    @discardableResult
    override public func visitStructDecl(_ structDecl: AST.StructDecl, additional _: Any? = nil)
        -> Any?
    {
        state.write(annotations(structDecl.modifiers, structDecl.attributes))
        typeDeclHeader(
            "struct", structDecl.name, structDecl.genericDecl, structDecl.conformances,
            structDecl.whereClause
        )
        appendBlock(structDecl.body)
        return nil
    }

    @discardableResult
    override public func visitClassDecl(_ classDecl: AST.ClassDecl, additional _: Any? = nil) -> Any? {
        state.write(annotations(classDecl.modifiers, classDecl.attributes))
        typeDeclHeader(
            "class", classDecl.name, classDecl.genericDecl, classDecl.inheritanceClauses,
            classDecl.whereClause
        )
        appendBlock(classDecl.body)
        return nil
    }

    @discardableResult
    override public func visitActorDecl(_ actorDecl: AST.ActorDecl, additional _: Any? = nil) -> Any? {
        state.write(annotations(actorDecl.modifiers, actorDecl.attributes))
        typeDeclHeader(
            "actor", actorDecl.name, actorDecl.genericDecl, actorDecl.conformances,
            actorDecl.whereClause
        )
        appendBlock(actorDecl.body)
        return nil
    }

    @discardableResult
    override public func visitProtocolDecl(_ protocolDecl: AST.ProtocolDecl, additional _: Any? = nil)
        -> Any?
    {
        state.write(annotations(protocolDecl.modifiers, protocolDecl.attributes))
        typeDeclHeader(
            "protocol", protocolDecl.name, protocolDecl.genericDecl, protocolDecl.conformances,
            protocolDecl.whereClause
        )
        appendBlock(protocolDecl.body)
        return nil
    }

    @discardableResult
    override public func visitExtensionDecl(
        _ extensionDecl: AST.ExtensionDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(extensionDecl.modifiers, extensionDecl.attributes))
        state.write("extension ")
        visit(extensionDecl.base)
        if !extensionDecl.conformances.isEmpty {
            state.write(
                ": " + extensionDecl.conformances.map { render($0) }.joined(separator: ", "))
        }
        appendBlock(extensionDecl.body)
        return nil
    }

    @discardableResult
    override public func visitEnumDecl(_ enumDecl: AST.EnumDecl, additional _: Any? = nil) -> Any? {
        state.write(annotations(enumDecl.modifiers, enumDecl.attributes))
        typeDeclHeader(
            "enum", enumDecl.name, enumDecl.genericDecl, enumDecl.conformances, enumDecl.whereClause
        )
        appendBlock(enumDecl.body)
        return nil
    }

    @discardableResult
    override public func visitEnumCaseDecl(
        _ enumCaseDecl: AST.EnumCaseDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(enumCaseDecl.modifiers, enumCaseDecl.attributes))
        state.write("case ")
        for (index, element) in enumCaseDecl.elements.enumerated() {
            if index > 0 { state.write(", ") }
            state.write(element.name.value)
            if !element.associatedValues.isEmpty {
                state.write("(")
                for (valueIndex, associatedValue) in element.associatedValues.enumerated() {
                    if valueIndex > 0 { state.write(", ") }
                    if let label = associatedValue.label { state.write(label.value + ": ") }
                    visit(associatedValue.typeExpression)
                }
                state.write(")")
            }
            if let rawValue = element.rawValue {
                state.write(" = ")
                visit(rawValue)
            }
        }
        return nil
    }

    @discardableResult
    override public func visitInitDecl(_ initDecl: AST.InitDecl, additional _: Any? = nil) -> Any? {
        state.write(annotations(initDecl.modifiers, initDecl.attributes))
        state.write("init")
        if initDecl.optionalToken != nil { state.write("?") }
        if let genericDecl = initDecl.genericDecl { state.write(genericDeclText(genericDecl)) }
        state.write(parametersText(initDecl.parameters))
        if let throwsClause = initDecl.throwsClause { state.write(throwsClauseText(throwsClause)) }
        appendBlock(initDecl.body)
        return nil
    }

    @discardableResult
    override public func visitDeinitDecl(_ deinitDecl: AST.DeinitDecl, additional _: Any? = nil)
        -> Any?
    {
        state.write(annotations(deinitDecl.modifiers, deinitDecl.attributes))
        state.write("deinit")
        appendBlock(deinitDecl.body)
        return nil
    }

    @discardableResult
    override public func visitFunctionDecl(
        _ functionDecl: AST.FunctionDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(functionDecl.modifiers, functionDecl.attributes))
        state.write("func " + functionDecl.name.value)
        if let genericDecl = functionDecl.genericDecl { state.write(genericDeclText(genericDecl)) }
        state.write(
            parametersText(functionDecl.parameters, vararg: functionDecl.varargToken != nil))
        if let throwsClause = functionDecl.throwsClause {
            state.write(throwsClauseText(throwsClause))
        }
        if let returnTypeExpression = functionDecl.returnTypeExpression {
            state.write(" -> ")
            visit(returnTypeExpression)
        }
        switch functionDecl.body {
        case let .Block(statements):
            appendBlock(statements)
        case let .Expression(expression):
            state.write(" = ")
            visit(expression)
        case nil:
            break
        }
        return nil
    }

    @discardableResult
    override public func visitVariableDecl(
        _ variableDecl: AST.VariableDecl, additional: Any? = nil
    ) -> Any? {
        state.write(annotations(variableDecl.modifiers, variableDecl.attributes))
        state.write(variableDecl.token.value)
        if let internalToken = variableDecl.internalToken {
            state.write("(" + internalToken.value + ")")
        }
        state.write(" " + variableDecl.name.value)
        if let typeExpression = variableDecl.typeExpression {
            state.write(": ")
            visit(typeExpression)
        }
        if let initializer = variableDecl.initializer {
            state.write(" = ")
            visit(initializer)
        }
        if !variableDecl.accessors.isEmpty {
            state.write(" {")
            state.indent += 1
            for accessor in variableDecl.accessors {
                beginLine()
                visitAccessor(accessor, additional: additional)
            }
            state.indent -= 1
            beginLine()
            state.write("}")
        }
        return nil
    }

    @discardableResult
    override public func visitReturn(_ ret: AST.Return, additional _: Any? = nil) -> Any? {
        state.write("return")
        if let value = ret.value {
            state.write(" ")
            visit(value)
        }
        return nil
    }

    @discardableResult
    override public func visitThrow(_ throwStatement: AST.Throw, additional _: Any? = nil) -> Any? {
        state.write("throw ")
        visit(throwStatement.expression)
        return nil
    }

    @discardableResult
    override public func visitWhile(_ whileStatement: AST.While, additional _: Any? = nil) -> Any? {
        state.write("while ")
        visit(whileStatement.condition)
        appendBlock(whileStatement.body)
        return nil
    }

    @discardableResult
    override public func visitRepeatWhile(_ repeatWhile: AST.RepeatWhile, additional _: Any? = nil)
        -> Any?
    {
        state.write("repeat")
        appendBlock(repeatWhile.body)
        state.write(" while ")
        visit(repeatWhile.condition)
        return nil
    }

    @discardableResult
    override public func visitGuard(_ guardStatement: AST.Guard, additional _: Any? = nil) -> Any? {
        state.write("guard ")
        visit(guardStatement.condition)
        state.write(" else")
        appendBlock(guardStatement.body)
        return nil
    }

    @discardableResult
    override public func visitFor(_ forStatement: AST.For, additional _: Any? = nil) -> Any? {
        state.write("for")
        if forStatement.asyncToken != nil { state.write(" await") }
        state.write(" ")
        visit(forStatement.pattern)
        state.write(" in ")
        visit(forStatement.sequence)
        appendBlock(forStatement.body)
        return nil
    }

    @discardableResult
    override public func visitDefer(_ deferStatement: AST.Defer, additional _: Any? = nil) -> Any? {
        state.write("defer")
        appendBlock(deferStatement.body)
        return nil
    }

    @discardableResult
    override public func visitAsm(_ asmStatement: AST.Asm, additional _: Any? = nil) -> Any? {
        state.write("asm { ")
        for (index, template) in asmStatement.templates.enumerated() {
            if index > 0 { state.write(" ") }
            visit(template)
        }
        if !asmStatement.bindings.isEmpty {
            state.write(" : ")
            for (index, binding) in asmStatement.bindings.enumerated() {
                if index > 0 { state.write(", ") }
                state.write(binding.name.value + " = " + binding.kind.value + "(")
                state.write(binding.constraint.value + ")")
                if let local = binding.local { state.write(" " + local.value) }
            }
        }
        if !asmStatement.options.isEmpty {
            state.write(" : " + asmStatement.options.map(\.value).joined(separator: " "))
        }
        state.write(" }")
        return nil
    }

    @discardableResult
    override public func visitBreak(_ breakStatement: AST.Break, additional _: Any? = nil) -> Any? {
        state.write("break")
        if let label = breakStatement.label { state.write(" " + label.value) }
        return nil
    }

    @discardableResult
    override public func visitContinue(_ continueStatement: AST.Continue, additional _: Any? = nil)
        -> Any?
    {
        state.write("continue")
        if let label = continueStatement.label { state.write(" " + label.value) }
        return nil
    }

    @discardableResult
    override public func visitGoto(_ gotoStatement: AST.Goto, additional _: Any? = nil) -> Any? {
        state.write("goto " + gotoStatement.label.value)
        return nil
    }

    @discardableResult
    override public func visitLabeledStatement(
        _ labeledStatement: AST.LabeledStatement, additional _: Any? = nil
    ) -> Any? {
        state.write(labeledStatement.label.value + ": ")
        visit(labeledStatement.body)
        return nil
    }

    @discardableResult
    override public func visitAccessor(_ accessor: AST.Accessor, additional _: Any? = nil) -> Any? {
        var text = annotations(accessor.modifiers, accessor.attributes)
        switch accessor.kind {
        case .Get: text += "get"
        case .Set: text += "set"
        case .WillSet: text += "willSet"
        case .DidSet: text += "didSet"
        }
        if let parameterName = accessor.parameterName { text += "(\(parameterName.value))" }
        switch accessor.body {
        case let .Block(statements):
            blockHeader(text, statements)
        case let .Expression(expression):
            state.write(text + " = ")
            visit(expression)
        }
        return nil
    }

    @discardableResult
    override public func visitSubscriptDecl(
        _ subscriptDecl: AST.SubscriptDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(subscriptDecl.modifiers, subscriptDecl.attributes))
        state.write("subscript")
        if let genericDecl = subscriptDecl.genericDecl { state.write(genericDeclText(genericDecl)) }
        state.write(parametersText(subscriptDecl.parameters))
        if let throwsClause = subscriptDecl.throwsClause {
            state.write(throwsClauseText(throwsClause))
        }
        state.write(" -> ")
        visit(subscriptDecl.returnType)
        appendBlock(subscriptDecl.body)
        return nil
    }

    @discardableResult
    override public func visitAssociatedTypeDecl(
        _ associatedTypeDecl: AST.AssociatedTypeDecl, additional _: Any? = nil
    ) -> Any? {
        state.write(annotations(associatedTypeDecl.modifiers, associatedTypeDecl.attributes))
        state.write("associatedtype " + associatedTypeDecl.name.value)
        if let constraint = associatedTypeDecl.constraint {
            state.write(": ")
            visit(constraint)
        }
        if let whereClause = associatedTypeDecl.whereClause {
            state.write(whereClauseText(whereClause))
        }
        return nil
    }

    @discardableResult
    override public func visitErrorExpression(
        _: AST.ErrorExpression, additional _: Any? = nil
    ) -> Any? {
        state.write("<error>")
        return nil
    }

    @discardableResult
    override public func visitParentheticalExpression(
        _ parentheticalExpression: AST.ParentheticalExpression, additional _: Any? = nil
    ) -> Any? {
        state.write("(")
        visit(parentheticalExpression.inner)
        state.write(")")
        return nil
    }

    @discardableResult
    override public func visitVariable(_ variable: AST.Variable, additional _: Any? = nil) -> Any? {
        state.write(variable.name.value)
        return nil
    }

    @discardableResult
    override public func visitGenericApplication(
        _ genericApplication: AST.GenericApplication, additional _: Any? = nil
    ) -> Any? {
        visit(genericApplication.base)
        state.write("<")
        for (index, argument) in genericApplication.genericArguments.enumerated() {
            if index > 0 { state.write(", ") }
            visit(argument)
        }
        state.write(">")
        return nil
    }

    @discardableResult
    override public func visitIntegerLiteral(
        _ integerLiteral: AST.IntegerLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write(integerLiteral.token.value)
        return nil
    }

    @discardableResult
    override public func visitFloatLiteral(
        _ floatLiteral: AST.FloatLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write(floatLiteral.token.value)
        return nil
    }

    @discardableResult
    override public func visitStringLiteral(
        _ stringLiteral: AST.StringLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write("\"" + encodeString(stringLiteral.token.value) + "\"")
        return nil
    }

    @discardableResult
    override public func visitCharLiteral(
        _ charLiteral: AST.CharLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write(charLiteral.token.value)
        return nil
    }

    @discardableResult
    override public func visitBoolLiteral(
        _ boolLiteral: AST.BoolLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write(boolLiteral.token.value)
        return nil
    }

    @discardableResult
    override public func visitNullLiteral(
        _ nullLiteral: AST.NullLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write(nullLiteral.token.value)
        return nil
    }

    @discardableResult
    override public func visitVoidLiteral(
        _: AST.VoidLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write("()")
        return nil
    }

    @discardableResult
    override public func visitIf(_ ifExpression: AST.If, additional: Any? = nil) -> Any? {
        state.write("if ")
        visit(ifExpression.condition)
        appendBlock(ifExpression.then)
        if let elseKind = ifExpression.elseKind {
            switch elseKind {
            case let .Block(statements):
                state.write(" else")
                appendBlock(statements)
            case let .If(elseIfExpression):
                state.write(" else ")
                visitIf(elseIfExpression, additional: additional)
            }
        }
        return nil
    }

    @discardableResult
    override public func visitMatch(_ matchExpression: AST.Match, additional _: Any? = nil) -> Any? {
        state.write("match ")
        visit(matchExpression.subject)
        state.write(" {")
        state.indent += 1
        for matchCase in matchExpression.cases {
            beginLine()
            for (index, pattern) in matchCase.patterns.enumerated() {
                if index > 0 { state.write(", ") }
                visit(pattern)
            }
            state.write(" =>")
            appendBlock(matchCase.body)
        }
        state.indent -= 1
        beginLine()
        state.write("}")
        return nil
    }

    @discardableResult
    override public func visitDo(_ doExpression: AST.Do, additional _: Any? = nil) -> Any? {
        state.write("do")
        appendBlock(doExpression.body)
        for catchClause in doExpression.catches {
            state.write(" catch")
            if let pattern = catchClause.pattern {
                state.write(" ")
                visit(pattern)
            }
            if let whereCondition = catchClause.whereCondition {
                state.write(" where ")
                visit(whereCondition)
            }
            appendBlock(catchClause.body)
        }
        if let finallyBody = doExpression.finallyBody {
            state.write(" finally")
            appendBlock(finallyBody)
        }
        return nil
    }

    @discardableResult
    override public func visitCall(_ call: AST.Call, additional: Any? = nil) -> Any? {
        visit(call.callee)
        state.write("(")
        for (index, argument) in call.arguments.enumerated() {
            if index > 0 { state.write(", ") }
            if let label = argument.label {
                state.write(label.value + ": ")
            }
            visit(argument.value)
        }
        state.write(")")
        for (label, closure) in call.trailingClosures {
            state.write(" ")
            if let label { state.write(label.value + ":") }
            visitClosure(closure, additional: additional)
        }
        return nil
    }

    @discardableResult
    override public func visitMemberAccess(
        _ memberAccess: AST.MemberAccess, additional _: Any? = nil
    ) -> Any? {
        visit(memberAccess.object)
        state.write(memberAccess.token.value)
        state.write(memberAccess.member.value)
        return nil
    }

    @discardableResult
    override public func visitSelfTypeExpression(
        _: AST.SelfTypeExpression, additional _: Any? = nil
    ) -> Any? {
        state.write("Self")
        return nil
    }

    @discardableResult
    override public func visitSelfExpression(
        _: AST.SelfExpression, additional _: Any? = nil
    ) -> Any? {
        state.write("self")
        return nil
    }

    @discardableResult
    override public func visitSuperExpression(
        _: AST.SuperExpression, additional _: Any? = nil
    ) -> Any? {
        state.write("super")
        return nil
    }

    @discardableResult
    override public func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional _: Any? = nil
    ) -> Any? {
        state.write("." + implicitMemberAccess.name.value)
        return nil
    }

    @discardableResult
    override public func visitClosure(_ closure: AST.Closure, additional _: Any? = nil) -> Any? {
        state.write("{")
        if let signature = closure.signature {
            state.write(" ")
            if !signature.captureList.isEmpty {
                let items = signature.captureList.map { item in
                    var text = item.name.value
                    if let specifier = item.specifier { text = specifier.value + " " + text }
                    return text
                }.joined(separator: ", ")
                state.write("[" + items + "] ")
            }
            if !signature.parameters.isEmpty {
                state.write(parametersText(signature.parameters) + " ")
            }
            if signature.asyncToken != nil { state.write("async ") }
            if let throwsClause = signature.throwsClause {
                state.write(throwsClauseText(throwsClause) + " ")
            }
            if let returnType = signature.returnType {
                state.write("-> ")
                visit(returnType)
                state.write(" ")
            }
            state.write("in")
        }
        if closure.body.count == 1, let statement = closure.body.first as? AST.ExpressionStatement {
            state.write(" ")
            visit(statement.expression)
            state.write(" }")
        } else {
            appendBlock(closure.body)
        }
        return nil
    }

    @discardableResult
    override public func visitClosureType(
        _ closureType: AST.ClosureType, additional _: Any? = nil
    ) -> Any? {
        visit(closureType.parameterTypes)
        if let throwsClause = closureType.throwsClause {
            state.write(throwsClauseText(throwsClause))
        }
        state.write(" -> ")
        visit(closureType.returnType)
        return nil
    }

    @discardableResult
    override public func visitOptionalType(_ optionalType: AST.OptionalType, additional _: Any? = nil)
        -> Any?
    {
        visit(optionalType.wrappedType)
        state.write("?")
        return nil
    }

    @discardableResult
    override public func visitVariadicType(_ variadicType: AST.VariadicType, additional _: Any? = nil)
        -> Any?
    {
        visit(variadicType.base)
        state.write("...")
        return nil
    }

    @discardableResult
    override public func visitSomeType(_ someType: AST.SomeType, additional _: Any? = nil) -> Any? {
        state.write("some ")
        visit(someType.wrappedType)
        return nil
    }

    @discardableResult
    override public func visitAnyType(_ anyType: AST.AnyType, additional _: Any? = nil) -> Any? {
        state.write("any ")
        visit(anyType.wrappedType)
        return nil
    }

    @discardableResult
    override public func visitProtocolCompositionType(
        _ protocolCompositionType: AST.ProtocolCompositionType, additional _: Any? = nil
    ) -> Any? {
        for (index, type) in protocolCompositionType.types.enumerated() {
            if index > 0 { state.write(" & ") }
            visit(type)
        }
        return nil
    }

    @discardableResult
    override public func visitTupleExpression(
        _ tupleExpression: AST.TupleExpression, additional _: Any? = nil
    ) -> Any? {
        state.write("(")
        for (index, element) in tupleExpression.elements.enumerated() {
            if index > 0 { state.write(", ") }
            if let label = element.label {
                state.write(label.value + ": ")
            }
            visit(element.value)
        }
        state.write(")")
        return nil
    }

    @discardableResult
    override public func visitIsPattern(_ isPattern: AST.IsPattern, additional _: Any? = nil) -> Any? {
        state.write("is ")
        visit(isPattern.typeExpression)
        return nil
    }

    @discardableResult
    override public func visitAsPattern(_ asPattern: AST.AsPattern, additional _: Any? = nil) -> Any? {
        visit(asPattern.pattern)
        state.write(" as ")
        visit(asPattern.typeExpression)
        return nil
    }

    @discardableResult
    override public func visitSequentialExpression(
        _ sequentialExpression: AST.SequentialExpression, additional _: Any? = nil
    ) -> Any? {
        let ops = sequentialExpression.ops
        let operands = sequentialExpression.operands
        if ops.isEmpty {
            for (index, operand) in operands.enumerated() {
                if index > 0 { state.write(", ") }
                visit(operand)
            }
            return nil
        }
        var opIndex = 0
        var operandIndex = 0
        var lastWasOperand = false
        var lastWasPrefixOp = false
        while opIndex < ops.count || operandIndex < operands.count {
            let opPosition = opIndex < ops.count ? ops[opIndex].pos.pos : Int.max
            let operandPosition =
                operandIndex < operands.count
                    ? operands[operandIndex].sourceRange.start.offset : Int.max
            let emitOp: Bool
            if lastWasOperand {
                emitOp = opIndex < ops.count
            } else {
                emitOp = opIndex < ops.count && opPosition < operandPosition
            }
            if emitOp {
                let token = ops[opIndex]
                opIndex += 1
                if lastWasOperand {
                    state.write(" " + token.value + " ")
                    lastWasPrefixOp = false
                } else {
                    if lastWasPrefixOp { state.write(" ") }
                    state.write(token.value)
                    lastWasPrefixOp = true
                }
                lastWasOperand = false
            } else {
                visit(operands[operandIndex])
                operandIndex += 1
                lastWasOperand = true
                lastWasPrefixOp = false
            }
        }
        return nil
    }

    @discardableResult
    override public func visitBinary(_ binary: AST.Binary, additional _: Any? = nil) -> Any? {
        visit(binary.left)
        state.write(" " + binary.operatorToken.value + " ")
        visit(binary.right)
        return nil
    }

    @discardableResult
    override public func visitPrefix(_ prefixExpression: AST.Prefix, additional _: Any? = nil) -> Any? {
        state.write(prefixExpression.operatorToken.value)
        visit(prefixExpression.expression)
        return nil
    }

    @discardableResult
    override public func visitPostfix(_ postfixExpression: AST.Postfix, additional _: Any? = nil)
        -> Any?
    {
        visit(postfixExpression.expression)
        state.write(postfixExpression.operatorToken.value)
        return nil
    }

    @discardableResult
    override public func visitArrayLiteral(
        _ arrayLiteral: AST.ArrayLiteral, additional _: Any? = nil
    ) -> Any? {
        state.write("[")
        for (index, element) in arrayLiteral.elements.enumerated() {
            if index > 0 { state.write(", ") }
            visit(element)
        }
        state.write("]")
        return nil
    }

    @discardableResult
    override public func visitDictionaryLiteral(
        _ dictionaryLiteral: AST.DictionaryLiteral, additional _: Any? = nil
    ) -> Any? {
        if dictionaryLiteral.entries.isEmpty {
            state.write("[:]")
            return nil
        }
        state.write("[")
        for (index, entry) in dictionaryLiteral.entries.enumerated() {
            if index > 0 { state.write(", ") }
            visit(entry.key)
            state.write(": ")
            visit(entry.value)
        }
        state.write("]")
        return nil
    }

    @discardableResult
    override public func visitCastExpression(
        _ castExpression: AST.CastExpression, additional _: Any? = nil
    ) -> Any? {
        visit(castExpression.left)
        switch castExpression.kind {
        case .As: state.write(" as ")
        case .AsQuestion: state.write(" as? ")
        case .AsExclamation: state.write(" as! ")
        case .Is: state.write(" is ")
        }
        visit(castExpression.right)
        return nil
    }

    @discardableResult
    override public func visitTryExpression(
        _ tryExpression: AST.TryExpression, additional _: Any? = nil
    ) -> Any? {
        switch tryExpression.kind {
        case .Try: state.write("try ")
        case .TryQuestion: state.write("try? ")
        case .TryExclamation: state.write("try! ")
        }
        visit(tryExpression.expression)
        return nil
    }

    @discardableResult
    override public func visitAwaitExpression(
        _ awaitExpression: AST.AwaitExpression, additional _: Any? = nil
    ) -> Any? {
        state.write("await ")
        visit(awaitExpression.expression)
        return nil
    }

    @discardableResult
    override public func visitSubscript(_ subscriptExpr: AST.Subscript, additional _: Any? = nil)
        -> Any?
    {
        visit(subscriptExpr.base)
        state.write("[")
        for (index, argument) in subscriptExpr.arguments.enumerated() {
            if index > 0 { state.write(", ") }
            if let label = argument.label {
                state.write(label.value + ": ")
            }
            visit(argument.value)
        }
        state.write("]")
        return nil
    }

    @discardableResult
    override public func visitOptionalBinding(
        _ optionalBinding: AST.OptionalBinding, additional _: Any? = nil
    ) -> Any? {
        state.write(optionalBinding.token.value + " " + optionalBinding.name.value)
        if let typeExpression = optionalBinding.typeExpression {
            state.write(": ")
            visit(typeExpression)
        }
        state.write(" = ")
        visit(optionalBinding.value)
        return nil
    }

    @discardableResult
    override public func visitCaseMatch(_ caseMatch: AST.CaseMatch, additional _: Any? = nil) -> Any? {
        state.write("case ")
        visit(caseMatch.pattern)
        state.write(" = ")
        visit(caseMatch.subject)
        return nil
    }

    @discardableResult
    override public func visitBindingPattern(
        _ bindingPattern: AST.BindingPattern, additional _: Any? = nil
    ) -> Any? {
        state.write(bindingPattern.token.value + " " + bindingPattern.name.value)
        if let typeExpression = bindingPattern.typeExpression {
            state.write(": ")
            visit(typeExpression)
        }
        if let subpattern = bindingPattern.subpattern {
            state.write(" @ ")
            visit(subpattern)
        }
        return nil
    }

    @discardableResult
    override public func visitWildcardPattern(
        _: AST.WildcardPattern, additional _: Any? = nil
    ) -> Any? {
        state.write("_")
        return nil
    }

    @discardableResult
    override public func visitShorthandArgument(
        _ shorthandArgument: AST.ShorthandArgument, additional _: Any? = nil
    ) -> Any? {
        state.write("$\(shorthandArgument.index)")
        return nil
    }

    @discardableResult
    override public func visitStringInterpolation(
        _ interpolation: AST.StringInterpolation, additional _: Any? = nil
    ) -> Any? {
        state.write("\"")
        for segment in interpolation.segments {
            switch segment {
            case let .literal(token):
                state.write(encodeString(token.value))
            case let .expression(expression):
                state.write("\\(")
                visit(expression)
                state.write(")")
            }
        }
        state.write("\"")
        return nil
    }
}
