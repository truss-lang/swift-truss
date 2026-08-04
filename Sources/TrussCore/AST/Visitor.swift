import SwiftAbstract

extension AST {
    @abstractClass
    open class Visitor {
        @abstractInit
        public init()

        @discardableResult
        open func visit(_ node: AST.AstNode, additional: Any? = nil) -> Any? {
            node.accept(self, additional: additional)
        }

        @discardableResult
        open func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
            var last: Any?
            for statement in program.statements {
                last = visit(statement, additional: additional)
            }
            return last
        }

        @discardableResult
        open func visitGenericDecl(_ genericDecl: GenericDecl, additional: Any? = nil) -> Any? {
            for generic in genericDecl.generics {
                visitGenericParameter(generic, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitGenericParameter(
            _ genericParameter: GenericParameter, additional: Any? = nil
        ) -> Any? {
            if let constraint = genericParameter.constraint {
                visit(constraint, additional: additional)
            }
            return nil
        }

        private func visitWhereClauseRequirements(
            _ requirements: [AST.WhereRequirement], additional: Any?
        ) {
            for requirement in requirements {
                visit(requirement.left, additional: additional)
                switch requirement.constraint {
                case let .conformance(e), let .equality(e):
                    visit(e, additional: additional)
                }
            }
        }

        @discardableResult
        open func visitEmptyStatement(
            _: AST.EmptyStatement, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitErrorStatement(
            _: AST.ErrorStatement, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitImport(
            _: AST.Import, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitExternDecl(
            _ externDecl: AST.ExternDecl, additional: Any? = nil
        ) -> Any? {
            switch externDecl.body {
            case let .Block(statements):
                for statement in statements {
                    visit(statement, additional: additional)
                }
                return nil
            case let .Declaration(decl):
                return visit(decl, additional: additional)
            }
        }

        @discardableResult
        open func visitExpressionStatement(
            _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
        ) -> Any? {
            visit(expressionStatement.expression, additional: additional)
        }

        @discardableResult
        open func visitTypeAliasDecl(
            _ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil
        ) -> Any? {
            visit(typeAliasDecl.typeExpression, additional: additional)
        }

        @discardableResult
        open func visitModuleDecl(
            _ moduleDecl: AST.ModuleDecl, additional: Any? = nil
        ) -> Any? {
            for statement in moduleDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitOperatorDecl(
            _: AST.OperatorDecl, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        /* This method does nothing, because we don't want to visit
         * this node most of the time. It will be individually processed
         * by the `TrussOperators` module.
         */
        @discardableResult
        open func visitPrecedenceGroupDecl(
            _: AST.PrecedenceGroupDecl, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitStructDecl(
            _ structDecl: AST.StructDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = structDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for conformance in structDecl.conformances {
                visit(conformance, additional: additional)
            }
            if let whereClause = structDecl.whereClause {
                visitWhereClauseRequirements(whereClause, additional: additional)
            }
            for statement in structDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitClassDecl(
            _ classDecl: AST.ClassDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = classDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for inheritanceClause in classDecl.inheritanceClauses {
                visit(inheritanceClause, additional: additional)
            }
            if let whereClause = classDecl.whereClause {
                visitWhereClauseRequirements(whereClause, additional: additional)
            }
            for statement in classDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitActorDecl(
            _ actorDecl: AST.ActorDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = actorDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for conformance in actorDecl.conformances {
                visit(conformance, additional: additional)
            }
            if let whereClause = actorDecl.whereClause {
                visitWhereClauseRequirements(whereClause, additional: additional)
            }
            for statement in actorDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitProtocolDecl(
            _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = protocolDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for conformance in protocolDecl.conformances {
                visit(conformance, additional: additional)
            }
            if let whereClause = protocolDecl.whereClause {
                visitWhereClauseRequirements(whereClause, additional: additional)
            }
            for statement in protocolDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitExtensionDecl(
            _ extensionDecl: AST.ExtensionDecl, additional: Any? = nil
        ) -> Any? {
            visit(extensionDecl.base, additional: additional)
            for conformance in extensionDecl.conformances {
                visit(conformance, additional: additional)
            }
            for statement in extensionDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitEnumDecl(
            _ enumDecl: AST.EnumDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = enumDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for conformance in enumDecl.conformances {
                visit(conformance, additional: additional)
            }
            if let whereClause = enumDecl.whereClause {
                visitWhereClauseRequirements(whereClause, additional: additional)
            }
            for statement in enumDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitEnumCaseDecl(
            _ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil
        ) -> Any? {
            for element in enumCaseDecl.elements {
                for associatedValue in element.associatedValues {
                    visit(associatedValue.typeExpression, additional: additional)
                }
                if let rawValue = element.rawValue {
                    visit(rawValue, additional: additional)
                }
            }
            return nil
        }

        @discardableResult
        open func visitInitDecl(
            _ initDecl: AST.InitDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = initDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for parameter in initDecl.parameters {
                if let type = parameter.type {
                    visit(type, additional: additional)
                }
                if let defaultValue = parameter.defaultValue {
                    visit(defaultValue, additional: additional)
                }
            }
            if let types = initDecl.throwsClause?.types {
                for type in types {
                    visit(type, additional: additional)
                }
            }
            for statement in initDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitDeinitDecl(
            _ deinitDecl: AST.DeinitDecl, additional: Any? = nil
        ) -> Any? {
            for statement in deinitDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitFunctionDecl(
            _ functionDecl: AST.FunctionDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = functionDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for parameter in functionDecl.parameters {
                if let type = parameter.type {
                    visit(type, additional: additional)
                }
                if let defaultValue = parameter.defaultValue {
                    visit(defaultValue, additional: additional)
                }
            }
            if let types = functionDecl.throwsClause?.types {
                for type in types {
                    visit(type, additional: additional)
                }
            }
            if let returnTypeExpression = functionDecl.returnTypeExpression {
                visit(returnTypeExpression, additional: additional)
            }
            switch functionDecl.body {
            case let .Block(statements):
                var last: Any? = nil
                for statement in statements {
                    last = visit(statement, additional: additional)
                }
                return last
            case let .Expression(expression):
                return visit(expression, additional: additional)
            default:
                return nil
            }
        }

        @discardableResult
        open func visitVariableDecl(
            _ variableDecl: AST.VariableDecl, additional: Any? = nil
        ) -> Any? {
            if let typeExpression = variableDecl.typeExpression {
                visit(typeExpression, additional: additional)
            }
            if let initializer = variableDecl.initializer {
                visit(initializer, additional: additional)
            }
            for accessor in variableDecl.accessors {
                visitAccessor(accessor, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitReturn(
            _ ret: AST.Return, additional: Any? = nil
        ) -> Any? {
            if let value = ret.value {
                visit(value, additional: additional)
            } else {
                nil
            }
        }

        @discardableResult
        open func visitThrow(
            _ throwStatement: AST.Throw, additional: Any? = nil
        ) -> Any? {
            visit(throwStatement.expression, additional: additional)
        }

        @discardableResult
        open func visitWhile(_ whileStatement: AST.While, additional: Any? = nil) -> Any? {
            visit(whileStatement.condition, additional: additional)
            for statement in whileStatement.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitRepeatWhile(_ repeatWhile: AST.RepeatWhile, additional: Any? = nil) -> Any? {
            for statement in repeatWhile.body {
                visit(statement, additional: additional)
            }
            return visit(repeatWhile.condition, additional: additional)
        }

        @discardableResult
        open func visitGuard(_ guardStatement: AST.Guard, additional: Any? = nil) -> Any? {
            visit(guardStatement.condition, additional: additional)
            for statement in guardStatement.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitFor(_ forStatement: AST.For, additional: Any? = nil) -> Any? {
            visit(forStatement.pattern, additional: additional)
            visit(forStatement.sequence, additional: additional)
            for statement in forStatement.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitDefer(_ deferStatement: AST.Defer, additional: Any? = nil) -> Any? {
            for statement in deferStatement.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitAsm(_: AST.Asm, additional _: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitBreak(_: AST.Break, additional _: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitContinue(_: AST.Continue, additional _: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitGoto(_: AST.Goto, additional _: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitLabeledStatement(
            _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
        ) -> Any? {
            visit(labeledStatement.body, additional: additional)
        }

        @discardableResult
        open func visitAccessor(_ accessor: AST.Accessor, additional: Any? = nil) -> Any? {
            switch accessor.body {
            case let .Block(statements):
                var last: Any? = nil
                for statement in statements {
                    last = visit(statement, additional: additional)
                }
                return last
            case let .Expression(expression):
                return visit(expression, additional: additional)
            }
        }

        @discardableResult
        open func visitErrorExpression(
            _: AST.ErrorExpression, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitParentheticalExpression(
            _ parentheticalExpression: AST.ParentheticalExpression, additional: Any? = nil
        ) -> Any? {
            visit(parentheticalExpression.inner, additional: additional)
        }

        @discardableResult
        open func visitVariable(_: AST.Variable, additional _: Any? = nil) -> Any? {
            nil
        }

        @discardableResult
        open func visitGenericApplication(
            _ genericApplication: AST.GenericApplication, additional: Any? = nil
        ) -> Any? {
            visit(genericApplication.base, additional: additional)
            for genericArgument in genericApplication.genericArguments {
                visit(genericArgument, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitIntegerLiteral(
            _: AST.IntegerLiteral, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitFloatLiteral(
            _: AST.FloatLiteral, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitStringLiteral(
            _: AST.StringLiteral, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitCharLiteral(
            _: AST.CharLiteral, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitBoolLiteral(
            _: AST.BoolLiteral, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitNullLiteral(
            _: AST.NullLiteral, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitVoidLiteral(
            _: AST.VoidLiteral, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitIf(
            _ ifExpression: AST.If, additional: Any? = nil
        ) -> Any? {
            visit(ifExpression.condition, additional: additional)
            for statement in ifExpression.then {
                visit(statement, additional: additional)
            }
            if let elseKind = ifExpression.elseKind {
                switch elseKind {
                case let .Block(statements):
                    for statement in statements {
                        visit(statement, additional: additional)
                    }
                case let .If(elseIfExpression):
                    visitIf(elseIfExpression, additional: additional)
                }
            }
            return nil
        }

        @discardableResult
        open func visitMatch(_ matchExpression: AST.Match, additional: Any? = nil) -> Any? {
            visit(matchExpression.subject, additional: additional)
            for matchCase in matchExpression.cases {
                for pattern in matchCase.patterns {
                    visit(pattern, additional: additional)
                }
                for statement in matchCase.body {
                    visit(statement, additional: additional)
                }
            }
            return nil
        }

        @discardableResult
        open func visitDo(_ doExpression: AST.Do, additional: Any? = nil) -> Any? {
            for statement in doExpression.body {
                visit(statement, additional: additional)
            }
            for catchClause in doExpression.catches {
                if let pattern = catchClause.pattern {
                    visit(pattern, additional: additional)
                }
                if let whereCondition = catchClause.whereCondition {
                    visit(whereCondition, additional: additional)
                }
                for statement in catchClause.body {
                    visit(statement, additional: additional)
                }
            }
            if let finallyBody = doExpression.finallyBody {
                for statement in finallyBody {
                    visit(statement, additional: additional)
                }
            }
            return nil
        }

        @discardableResult
        open func visitCall(
            _ call: AST.Call, additional: Any? = nil
        ) -> Any? {
            visit(call.callee, additional: additional)
            for argument in call.arguments {
                visit(argument.value, additional: additional)
            }
            for (_, closure) in call.trailingClosures {
                visitClosure(closure, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitMemberAccess(
            _ memberAccess: AST.MemberAccess, additional: Any? = nil
        ) -> Any? {
            visit(memberAccess.object, additional: additional)
        }

        @discardableResult
        open func visitSelfTypeExpression(
            _: AST.SelfTypeExpression, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitSelfExpression(
            _: AST.SelfExpression, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitSuperExpression(
            _: AST.SuperExpression, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitImplicitMemberAccess(
            _: AST.ImplicitMemberAccess, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
            if let sig = closure.signature {
                if let returnType = sig.returnType {
                    visit(returnType, additional: additional)
                }
                if let types = sig.throwsClause?.types {
                    for type in types {
                        visit(type, additional: additional)
                    }
                }
            }
            for statement in closure.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitClosureType(
            _ closureType: AST.ClosureType, additional: Any? = nil
        ) -> Any? {
            visit(closureType.parameterTypes, additional: additional)
            if let types = closureType.throwsClause?.types {
                for type in types {
                    visit(type, additional: additional)
                }
            }
            return visit(closureType.returnType, additional: additional)
        }

        @discardableResult
        open func visitOptionalType(_ optionalType: AST.OptionalType, additional: Any? = nil)
            -> Any?
        {
            visit(optionalType.wrappedType, additional: additional)
        }

        @discardableResult
        open func visitVariadicType(
            _ variadicType: AST.VariadicType, additional: Any? = nil
        ) -> Any? {
            visit(variadicType.base, additional: additional)
        }

        @discardableResult
        open func visitSomeType(_ someType: AST.SomeType, additional: Any? = nil) -> Any? {
            visit(someType.wrappedType, additional: additional)
        }

        @discardableResult
        open func visitAnyType(_ anyType: AST.AnyType, additional: Any? = nil) -> Any? {
            visit(anyType.wrappedType, additional: additional)
        }

        @discardableResult
        open func visitProtocolCompositionType(
            _ protocolCompositionType: AST.ProtocolCompositionType, additional: Any? = nil
        ) -> Any? {
            for type in protocolCompositionType.types {
                visit(type, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitTupleExpression(
            _ tupleExpression: AST.TupleExpression, additional: Any? = nil
        ) -> Any? {
            for element in tupleExpression.elements {
                visit(element.value, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitIsPattern(
            _ isPattern: AST.IsPattern, additional: Any? = nil
        ) -> Any? {
            visit(isPattern.typeExpression, additional: additional)
        }

        @discardableResult
        open func visitAsPattern(
            _ asPattern: AST.AsPattern, additional: Any? = nil
        ) -> Any? {
            visit(asPattern.pattern, additional: additional)
            return visit(asPattern.typeExpression, additional: additional)
        }

        @discardableResult
        open func visitSequentialExpression(
            _ sequentialExpression: AST.SequentialExpression, additional: Any? = nil
        ) -> Any? {
            var last: Any?
            for operand in sequentialExpression.operands {
                last = visit(operand, additional: additional)
            }
            return last
        }

        @discardableResult
        open func visitBinary(
            _ binary: AST.Binary, additional: Any? = nil
        ) -> Any? {
            visit(binary.left, additional: additional)
            return visit(binary.right, additional: additional)
        }

        @discardableResult
        open func visitPrefix(
            _ prefixExpression: AST.Prefix, additional: Any? = nil
        ) -> Any? {
            visit(prefixExpression.expression, additional: additional)
        }

        @discardableResult
        open func visitPostfix(
            _ postfixExpression: AST.Postfix, additional: Any? = nil
        ) -> Any? {
            visit(postfixExpression.expression, additional: additional)
        }

        @discardableResult
        open func visitArrayLiteral(
            _ arrayLiteral: AST.ArrayLiteral, additional: Any? = nil
        ) -> Any? {
            for element in arrayLiteral.elements {
                visit(element, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitDictionaryLiteral(
            _ dictionaryLiteral: AST.DictionaryLiteral, additional: Any? = nil
        ) -> Any? {
            for entry in dictionaryLiteral.entries {
                visit(entry.key, additional: additional)
                visit(entry.value, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitCastExpression(
            _ castExpression: AST.CastExpression, additional: Any? = nil
        ) -> Any? {
            visit(castExpression.left, additional: additional)
            visit(castExpression.right, additional: additional)
            return nil
        }

        @discardableResult
        open func visitTryExpression(
            _ tryExpression: AST.TryExpression, additional: Any? = nil
        ) -> Any? {
            visit(tryExpression.expression, additional: additional)
        }

        @discardableResult
        open func visitAwaitExpression(
            _ awaitExpression: AST.AwaitExpression, additional: Any? = nil
        ) -> Any? {
            visit(awaitExpression.expression, additional: additional)
        }

        @discardableResult
        open func visitSubscript(
            _ subscriptExpr: AST.Subscript, additional: Any? = nil
        ) -> Any? {
            visit(subscriptExpr.base, additional: additional)
            for argument in subscriptExpr.arguments {
                visit(argument.value, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitOptionalBinding(
            _ optionalBinding: AST.OptionalBinding, additional: Any? = nil
        ) -> Any? {
            if let typeExpression = optionalBinding.typeExpression {
                visit(typeExpression, additional: additional)
            }
            return visit(optionalBinding.value, additional: additional)
        }

        @discardableResult
        open func visitCaseMatch(
            _ caseMatch: AST.CaseMatch, additional: Any? = nil
        ) -> Any? {
            visit(caseMatch.pattern, additional: additional)
            return visit(caseMatch.subject, additional: additional)
        }

        @discardableResult
        open func visitBindingPattern(
            _ bindingPattern: AST.BindingPattern, additional: Any? = nil
        ) -> Any? {
            if let typeExpression = bindingPattern.typeExpression {
                visit(typeExpression, additional: additional)
            }
            if let subpattern = bindingPattern.subpattern {
                return visit(subpattern, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitWildcardPattern(
            _: AST.WildcardPattern, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitShorthandArgument(
            _: AST.ShorthandArgument, additional _: Any? = nil
        ) -> Any? {
            nil
        }

        @discardableResult
        open func visitKeyPathExpression(
            _ keyPathExpression: AST.KeyPathExpression, additional: Any? = nil
        ) -> Any? {
            if let root = keyPathExpression.root {
                visit(root, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitStringInterpolation(
            _ interpolation: AST.StringInterpolation, additional: Any? = nil
        ) -> Any? {
            for segment in interpolation.segments {
                switch segment {
                case .literal: break
                case let .expression(expr):
                    visit(expr, additional: additional)
                }
            }
            return nil
        }

        @discardableResult
        open func visitSubscriptDecl(
            _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
        ) -> Any? {
            if let genericDecl = subscriptDecl.genericDecl {
                visitGenericDecl(genericDecl, additional: additional)
            }
            for parameter in subscriptDecl.parameters {
                if let type = parameter.type {
                    visit(type, additional: additional)
                }
                if let defaultValue = parameter.defaultValue {
                    visit(defaultValue, additional: additional)
                }
            }
            if let types = subscriptDecl.throwsClause?.types {
                for type in types {
                    visit(type, additional: additional)
                }
            }
            visit(subscriptDecl.returnType, additional: additional)
            for statement in subscriptDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitAssociatedTypeDecl(
            _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
        ) -> Any? {
            if let constraint = associatedTypeDecl.constraint {
                visit(constraint, additional: additional)
            }
            if let whereClause = associatedTypeDecl.whereClause {
                for requirement in whereClause {
                    visit(requirement.left, additional: additional)
                    switch requirement.constraint {
                    case let .conformance(e), let .equality(e):
                        visit(e, additional: additional)
                    }
                }
            }
            return nil
        }
    }
}
