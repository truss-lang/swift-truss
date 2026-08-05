import SwiftAbstract

extension AST {
    @abstractClass
    open class Rewriter: Visitor {
        @abstractInit
        public override init()

        @discardableResult
        public func rewrite<T: AST.AstNode>(_ node: T) -> T {
            (node.accept(self) as? T) ?? node
        }

        @discardableResult
        public func rewriteAll<T: AST.AstNode>(_ nodes: [T]) -> [T] {
            nodes.compactMap { $0.accept(self) as? T }
        }

        private func unchanged<T: AnyObject>(_ old: [T], _ new: [T]) -> Bool {
            old.count == new.count && zip(old, new).allSatisfy { $0 === $1 }
        }

        public func copySemanticFields(from old: AST.AstNode, to new: AST.AstNode) {
            if let oldExpression = old as? AST.Expression, let newExpression = new as? AST.Expression {
                newExpression.ty = oldExpression.ty
            }
            switch (old, new) {
            case let (oldProgram as AST.Program, newProgram as AST.Program):
                newProgram.packageSymbol = oldProgram.packageSymbol
            case let (oldModule as AST.ModuleDecl, newModule as AST.ModuleDecl):
                newModule.symbol = oldModule.symbol
            case let (oldAlias as AST.TypeAliasDecl, newAlias as AST.TypeAliasDecl):
                newAlias.symbol = oldAlias.symbol
            case let (oldStruct as AST.StructDecl, newStruct as AST.StructDecl):
                newStruct.symbol = oldStruct.symbol
            case let (oldClass as AST.ClassDecl, newClass as AST.ClassDecl):
                newClass.symbol = oldClass.symbol
            case let (oldActor as AST.ActorDecl, newActor as AST.ActorDecl):
                newActor.symbol = oldActor.symbol
            case let (oldProtocol as AST.ProtocolDecl, newProtocol as AST.ProtocolDecl):
                newProtocol.symbol = oldProtocol.symbol
            case let (oldEnum as AST.EnumDecl, newEnum as AST.EnumDecl):
                newEnum.symbol = oldEnum.symbol
            case let (oldExtension as AST.ExtensionDecl, newExtension as AST.ExtensionDecl):
                newExtension.virtualScope = oldExtension.virtualScope
            case let (oldCase as AST.EnumCaseDecl, newCase as AST.EnumCaseDecl):
                newCase.symbols = oldCase.symbols
            case let (oldInit as AST.InitDecl, newInit as AST.InitDecl):
                newInit.symbol = oldInit.symbol
            case let (oldSubscriptDecl as AST.SubscriptDecl, newSubscriptDecl as AST.SubscriptDecl):
                newSubscriptDecl.symbol = oldSubscriptDecl.symbol
            case let (oldFunction as AST.FunctionDecl, newFunction as AST.FunctionDecl):
                newFunction.symbol = oldFunction.symbol
            case let (oldVariableDecl as AST.VariableDecl, newVariableDecl as AST.VariableDecl):
                newVariableDecl.symbol = oldVariableDecl.symbol
            case let (oldAssociated as AST.AssociatedTypeDecl, newAssociated as AST.AssociatedTypeDecl):
                newAssociated.symbol = oldAssociated.symbol
            case let (oldVariable as AST.Variable, newVariable as AST.Variable):
                newVariable.symbol = oldVariable.symbol
                newVariable.overloads = oldVariable.overloads
            case let (oldCall as AST.Call, newCall as AST.Call):
                newCall.overloads = oldCall.overloads
            case let (oldMember as AST.MemberAccess, newMember as AST.MemberAccess):
                newMember.symbol = oldMember.symbol
                newMember.overloads = oldMember.overloads
            case let (oldSelf as AST.SelfExpression, newSelf as AST.SelfExpression):
                newSelf.symbol = oldSelf.symbol
            case let (oldSuper as AST.SuperExpression, newSuper as AST.SuperExpression):
                newSuper.symbol = oldSuper.symbol
            case let (oldImplicit as AST.ImplicitMemberAccess, newImplicit as AST.ImplicitMemberAccess):
                newImplicit.symbol = oldImplicit.symbol
                newImplicit.overloads = oldImplicit.overloads
            case let (oldClosure as AST.Closure, newClosure as AST.Closure):
                newClosure.scope = oldClosure.scope
            default:
                break
            }
        }

        private func rewriteWhereRequirement(
            _ requirement: AST.WhereRequirement
        ) -> AST.WhereRequirement {
            let left = rewrite(requirement.left)
            var changed = left !== requirement.left
            let constraint: AST.WhereRequirement.Constraint
            switch requirement.constraint {
            case let .conformance(expression):
                let rewritten = rewrite(expression)
                constraint = .conformance(rewritten)
                if rewritten !== expression { changed = true }
            case let .equality(expression):
                let rewritten = rewrite(expression)
                constraint = .equality(rewritten)
                if rewritten !== expression { changed = true }
            }
            return changed
                ? AST.WhereRequirement(left, constraint)
                : requirement
        }

        private func rewriteWhereRequirements(
            _ requirements: [AST.WhereRequirement]?
        ) -> [AST.WhereRequirement]? {
            guard let requirements else { return nil }
            return requirements.map { rewriteWhereRequirement($0) }
        }

        private func rewriteThrowsClause(
            _ throwsClause: AST.ThrowsClause?
        ) -> AST.ThrowsClause? {
            guard let throwsClause else { return nil }
            let types: [Expression]? = if let oldTypes = throwsClause.types {
                rewriteAll(oldTypes)
            } else {
                nil
            }
            let typesChanged: Bool = if let oldTypes = throwsClause.types, let types {
                !unchanged(oldTypes, types)
            } else {
                (throwsClause.types != nil) != (types != nil)
            }
            if !typesChanged { return throwsClause }
            return AST.ThrowsClause(
                throwsClause.token, types, sourceRange: throwsClause.sourceRange
            )
        }

        private func rewriteParameter(
            _ parameter: AST.FunctionDecl.Parameter
        ) -> AST.FunctionDecl.Parameter {
            var changed = false
            let type: Expression?
            if let oldType = parameter.type {
                let newType = rewrite(oldType)
                type = newType
                if newType !== oldType { changed = true }
            } else {
                type = nil
            }
            let defaultValue: Expression?
            if let oldDefault = parameter.defaultValue {
                let newDefault = rewrite(oldDefault)
                defaultValue = newDefault
                if newDefault !== oldDefault { changed = true }
            } else {
                defaultValue = nil
            }
            if !changed { return parameter }
            return AST.FunctionDecl.Parameter(
                label: parameter.label, name: parameter.name, type: type,
                defaultValue: defaultValue, sourceRange: parameter.sourceRange
            )
        }

        private func rewriteParameters(
            _ parameters: [AST.FunctionDecl.Parameter]
        ) -> [AST.FunctionDecl.Parameter] {
            parameters.map { rewriteParameter($0) }
        }

        private func rewriteFunctionBody(
            _ body: AST.FunctionDecl.Body
        ) -> AST.FunctionDecl.Body {
            switch body {
            case let .Block(statements):
                let rewritten = rewriteAll(statements)
                if unchanged(statements, rewritten) { return body }
                return .Block(rewritten)
            case let .Expression(expression):
                let rewritten = rewrite(expression)
                if rewritten === expression { return body }
                return .Expression(rewritten)
            }
        }

        private func rewriteExternBody(_ body: AST.ExternDecl.Body) -> AST.ExternDecl.Body {
            switch body {
            case let .Block(statements):
                let rewritten = rewriteAll(statements)
                if unchanged(statements, rewritten) { return body }
                return .Block(rewritten)
            case let .Declaration(decl):
                let rewritten = rewrite(decl)
                if rewritten === decl { return body }
                return .Declaration(rewritten)
            }
        }

        private func rewriteElseKind(_ elseKind: AST.If.ElseKind?) -> AST.If.ElseKind? {
            guard let elseKind else { return nil }
            switch elseKind {
            case let .Block(statements):
                let rewritten = rewriteAll(statements)
                if unchanged(statements, rewritten) { return elseKind }
                return .Block(rewritten)
            case let .If(elseIf):
                let rewritten = rewrite(elseIf)
                if rewritten === elseIf { return elseKind }
                return .If(rewritten)
            }
        }

        private func rewriteMatchCase(_ matchCase: AST.Match.Case) -> AST.Match.Case {
            var changed = false
            let patterns = rewriteAll(matchCase.patterns)
            if !unchanged(matchCase.patterns, patterns) { changed = true }
            let body = rewriteAll(matchCase.body)
            if !unchanged(matchCase.body, body) { changed = true }
            if !changed { return matchCase }
            return AST.Match.Case(patterns, body, sourceRange: matchCase.sourceRange)
        }

        private func rewriteCatchClause(
            _ catchClause: AST.Do.CatchClause
        ) -> AST.Do.CatchClause {
            var changed = false
            let pattern: Expression?
            if let oldPattern = catchClause.pattern {
                let newPattern = rewrite(oldPattern)
                pattern = newPattern
                if newPattern !== oldPattern { changed = true }
            } else {
                pattern = nil
            }
            let whereCondition: Expression?
            if let oldCondition = catchClause.whereCondition {
                let newCondition = rewrite(oldCondition)
                whereCondition = newCondition
                if newCondition !== oldCondition { changed = true }
            } else {
                whereCondition = nil
            }
            let body = rewriteAll(catchClause.body)
            if !unchanged(catchClause.body, body) { changed = true }
            if !changed { return catchClause }
            return AST.Do.CatchClause(
                pattern, catchClause.whereToken, whereCondition, body,
                sourceRange: catchClause.sourceRange
            )
        }

        private func rewriteLabeledArgument(
            _ argument: AST.LabeledArgument
        ) -> AST.LabeledArgument {
            let value = rewrite(argument.value)
            if value === argument.value { return argument }
            return AST.LabeledArgument(
                label: argument.label, value: value, sourceRange: argument.sourceRange
            )
        }

        private func rewriteClosureSignature(
            _ signature: AST.ClosureSignature?
        ) -> AST.ClosureSignature? {
            guard let signature else { return nil }
            var changed = false
            let parameters = rewriteParameters(signature.parameters)
            if !parametersUnchanged(signature.parameters, parameters) { changed = true }
            let throwsClause = rewriteThrowsClause(signature.throwsClause)
            if !throwsClauseUnchanged(signature.throwsClause, throwsClause) { changed = true }
            let returnType: Expression?
            if let oldReturnType = signature.returnType {
                let newReturnType = rewrite(oldReturnType)
                returnType = newReturnType
                if newReturnType !== oldReturnType { changed = true }
            } else {
                returnType = nil
            }
            if !changed { return signature }
            return AST.ClosureSignature(
                signature.captureList, parameters, throwsClause, returnType,
                signature.asyncToken, signature.inToken
            )
        }

        private func rewriteAssociatedValue(
            _ associatedValue: AST.EnumCaseDecl.AssociatedValue
        ) -> AST.EnumCaseDecl.AssociatedValue {
            let typeExpression = rewrite(associatedValue.typeExpression)
            if typeExpression === associatedValue.typeExpression { return associatedValue }
            return AST.EnumCaseDecl.AssociatedValue(
                label: associatedValue.label, typeExpression: typeExpression,
                sourceRange: associatedValue.sourceRange
            )
        }

        private func rewriteEnumCaseElement(
            _ element: AST.EnumCaseDecl.Element
        ) -> AST.EnumCaseDecl.Element {
            var changed = false
            let associatedValues = element.associatedValues.map { value
                -> AST.EnumCaseDecl.AssociatedValue in
                let typeExpression = rewrite(value.typeExpression)
                if typeExpression !== value.typeExpression { changed = true }
                return AST.EnumCaseDecl.AssociatedValue(
                    label: value.label, typeExpression: typeExpression,
                    sourceRange: value.sourceRange
                )
            }
            let rawValue: Expression?
            if let oldRawValue = element.rawValue {
                let newRawValue = rewrite(oldRawValue)
                rawValue = newRawValue
                if newRawValue !== oldRawValue { changed = true }
            } else {
                rawValue = nil
            }
            if !changed { return element }
            return AST.EnumCaseDecl.Element(
                name: element.name, associatedValues: associatedValues, rawValue: rawValue,
                sourceRange: element.sourceRange
            )
        }

        private func rewriteDictionaryEntry(
            _ entry: AST.DictionaryLiteral.Entry
        ) -> AST.DictionaryLiteral.Entry {
            let key = rewrite(entry.key)
            let value = rewrite(entry.value)
            if key === entry.key, value === entry.value { return entry }
            return AST.DictionaryLiteral.Entry(
                key: key, value: value, sourceRange: entry.sourceRange
            )
        }

        private func rewriteStringSegment(_ segment: AST.StringSegment) -> AST.StringSegment {
            switch segment {
            case .literal:
                return segment
            case let .expression(expression):
                let rewritten = rewrite(expression)
                if rewritten === expression { return segment }
                return .expression(rewritten)
            }
        }

        @discardableResult
        open override func visitProgram(
            _ program: AST.Program, additional: Any? = nil
        ) -> Any? {
            let statements = rewriteAll(program.statements)
            if unchanged(program.statements, statements) { return program }
            let newProgram = AST.Program(
                program.id, program.packageName, statements, sourceRange: program.sourceRange
            )
            copySemanticFields(from: program, to: newProgram)
            return newProgram
        }

        @discardableResult
        open override func visitGenericDecl(
            _ genericDecl: GenericDecl, additional: Any? = nil
        ) -> Any? {
            let generics = rewriteAll(genericDecl.generics)
            if unchanged(genericDecl.generics, generics) { return genericDecl }
            return GenericDecl(
                genericDecl.begin, generics, genericDecl.end, sourceRange: genericDecl.sourceRange
            )
        }

        @discardableResult
        open override func visitGenericParameter(
            _ genericParameter: GenericParameter, additional: Any? = nil
        ) -> Any? {
            guard let constraint = genericParameter.constraint else {
                return genericParameter
            }
            let newConstraint = rewrite(constraint)
            if newConstraint === constraint { return genericParameter }
            return GenericParameter(
                genericParameter.eachToken, genericParameter.name, newConstraint,
                sourceRange: genericParameter.sourceRange
            )
        }

        @discardableResult
        open override func visitEmptyStatement(
            _ emptyStatement: AST.EmptyStatement, additional: Any? = nil
        ) -> Any? {
            emptyStatement
        }

        @discardableResult
        open override func visitErrorStatement(
            _ errorStatement: AST.ErrorStatement, additional: Any? = nil
        ) -> Any? {
            errorStatement
        }

        @discardableResult
        open override func visitImport(
            _ importStatement: AST.Import, additional: Any? = nil
        ) -> Any? {
            importStatement
        }

        @discardableResult
        open override func visitExternDecl(
            _ externDecl: AST.ExternDecl, additional: Any? = nil
        ) -> Any? {
            let body = rewriteExternBody(externDecl.body)
            if bodyMatches(externDecl.body, body) { return externDecl }
            let newExternDecl = AST.ExternDecl(
                externDecl.modifiers, externDecl.attributes, externDecl.token,
                externDecl.convention, body, sourceRange: externDecl.sourceRange
            )
            copySemanticFields(from: externDecl, to: newExternDecl)
            return newExternDecl
        }

        private func bodyMatches(_ old: AST.ExternDecl.Body, _ new: AST.ExternDecl.Body) -> Bool {
            switch (old, new) {
            case let (.Block(oldStatements), .Block(newStatements)):
                unchanged(oldStatements, newStatements)
            case let (.Declaration(oldDecl), .Declaration(newDecl)):
                oldDecl === newDecl
            default:
                false
            }
        }

        @discardableResult
        open override func visitExpressionStatement(
            _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
        ) -> Any? {
            let expression = rewrite(expressionStatement.expression)
            if expression === expressionStatement.expression { return expressionStatement }
            return AST.ExpressionStatement(expression)
        }

        @discardableResult
        open override func visitTypeAliasDecl(
            _ typeAliasDecl: AST.TypeAliasDecl, additional: Any? = nil
        ) -> Any? {
            let typeExpression = rewrite(typeAliasDecl.typeExpression)
            if typeExpression === typeAliasDecl.typeExpression { return typeAliasDecl }
            let newTypeAliasDecl = AST.TypeAliasDecl(
                typeAliasDecl.modifiers, typeAliasDecl.attributes, typeAliasDecl.token,
                typeAliasDecl.name, typeExpression, sourceRange: typeAliasDecl.sourceRange
            )
            copySemanticFields(from: typeAliasDecl, to: newTypeAliasDecl)
            return newTypeAliasDecl
        }

        @discardableResult
        open override func visitModuleDecl(
            _ moduleDecl: AST.ModuleDecl, additional: Any? = nil
        ) -> Any? {
            let body = rewriteAll(moduleDecl.body)
            if unchanged(moduleDecl.body, body) { return moduleDecl }
            let newModuleDecl = AST.ModuleDecl(
                moduleDecl.modifiers, moduleDecl.attributes, moduleDecl.token, moduleDecl.name,
                body, sourceRange: moduleDecl.sourceRange
            )
            copySemanticFields(from: moduleDecl, to: newModuleDecl)
            return newModuleDecl
        }

        @discardableResult
        open override func visitOperatorDecl(
            _ operatorDecl: AST.OperatorDecl, additional: Any? = nil
        ) -> Any? {
            operatorDecl
        }

        @discardableResult
        open override func visitPrecedenceGroupDecl(
            _ precedenceGroupDecl: AST.PrecedenceGroupDecl, additional: Any? = nil
        ) -> Any? {
            let higherThan = rewriteAll(precedenceGroupDecl.higherThan)
            let lowerThan = rewriteAll(precedenceGroupDecl.lowerThan)
            if unchanged(precedenceGroupDecl.higherThan, higherThan),
               unchanged(precedenceGroupDecl.lowerThan, lowerThan)
            {
                return precedenceGroupDecl
            }
            return AST.PrecedenceGroupDecl(
                precedenceGroupDecl.modifiers, precedenceGroupDecl.attributes,
                precedenceGroupDecl.token, precedenceGroupDecl.name,
                precedenceGroupDecl.higherThanTokens, higherThan,
                precedenceGroupDecl.lowerThanTokens, lowerThan,
                precedenceGroupDecl.associativityToken, precedenceGroupDecl.associativity,
                precedenceGroupDecl.assignmentToken, precedenceGroupDecl.assignment,
                sourceRange: precedenceGroupDecl.sourceRange
            )
        }

        @discardableResult
        open override func visitStructDecl(
            _ structDecl: AST.StructDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = structDecl.genericDecl.map { rewrite($0) }
            let conformances = rewriteAll(structDecl.conformances)
            let whereClause = rewriteWhereRequirements(structDecl.whereClause)
            let body = rewriteAll(structDecl.body)
            if genericDecl === structDecl.genericDecl,
               unchanged(structDecl.conformances, conformances),
               whereClauseUnchanged(structDecl.whereClause, whereClause),
               unchanged(structDecl.body, body)
            {
                return structDecl
            }
            let newStructDecl = AST.StructDecl(
                structDecl.modifiers, structDecl.attributes, structDecl.token, structDecl.name,
                genericDecl, conformances, whereClause, body, sourceRange: structDecl.sourceRange
            )
            copySemanticFields(from: structDecl, to: newStructDecl)
            return newStructDecl
        }

        private func whereClauseUnchanged(
            _ old: [AST.WhereRequirement]?, _ new: [AST.WhereRequirement]?
        ) -> Bool {
            switch (old, new) {
            case let (oldRequirements?, newRequirements?):
                zip(oldRequirements, newRequirements).allSatisfy {
                    $0.left === $1.left && whereConstraintUnchanged($0.constraint, $1.constraint)
                } && oldRequirements.count == newRequirements.count
            case (nil, nil):
                true
            default:
                false
            }
        }

        private func whereConstraintUnchanged(
            _ old: AST.WhereRequirement.Constraint, _ new: AST.WhereRequirement.Constraint
        ) -> Bool {
            switch (old, new) {
            case let (.conformance(oldExpression), .conformance(newExpression)),
                 let (.equality(oldExpression), .equality(newExpression)):
                oldExpression === newExpression
            default:
                false
            }
        }

        @discardableResult
        open override func visitClassDecl(
            _ classDecl: AST.ClassDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = classDecl.genericDecl.map { rewrite($0) }
            let inheritanceClauses = rewriteAll(classDecl.inheritanceClauses)
            let whereClause = rewriteWhereRequirements(classDecl.whereClause)
            let body = rewriteAll(classDecl.body)
            if genericDecl === classDecl.genericDecl,
               unchanged(classDecl.inheritanceClauses, inheritanceClauses),
               whereClauseUnchanged(classDecl.whereClause, whereClause),
               unchanged(classDecl.body, body)
            {
                return classDecl
            }
            let newClassDecl = AST.ClassDecl(
                classDecl.modifiers, classDecl.attributes, classDecl.token, classDecl.name,
                genericDecl, inheritanceClauses, whereClause, body,
                sourceRange: classDecl.sourceRange
            )
            copySemanticFields(from: classDecl, to: newClassDecl)
            return newClassDecl
        }

        @discardableResult
        open override func visitActorDecl(
            _ actorDecl: AST.ActorDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = actorDecl.genericDecl.map { rewrite($0) }
            let conformances = rewriteAll(actorDecl.conformances)
            let whereClause = rewriteWhereRequirements(actorDecl.whereClause)
            let body = rewriteAll(actorDecl.body)
            if genericDecl === actorDecl.genericDecl,
               unchanged(actorDecl.conformances, conformances),
               whereClauseUnchanged(actorDecl.whereClause, whereClause),
               unchanged(actorDecl.body, body)
            {
                return actorDecl
            }
            let newActorDecl = AST.ActorDecl(
                actorDecl.modifiers, actorDecl.attributes, actorDecl.token, actorDecl.name,
                genericDecl, conformances, whereClause, body, sourceRange: actorDecl.sourceRange
            )
            copySemanticFields(from: actorDecl, to: newActorDecl)
            return newActorDecl
        }

        @discardableResult
        open override func visitProtocolDecl(
            _ protocolDecl: AST.ProtocolDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = protocolDecl.genericDecl.map { rewrite($0) }
            let conformances = rewriteAll(protocolDecl.conformances)
            let whereClause = rewriteWhereRequirements(protocolDecl.whereClause)
            let body = rewriteAll(protocolDecl.body)
            if genericDecl === protocolDecl.genericDecl,
               unchanged(protocolDecl.conformances, conformances),
               whereClauseUnchanged(protocolDecl.whereClause, whereClause),
               unchanged(protocolDecl.body, body)
            {
                return protocolDecl
            }
            let newProtocolDecl = AST.ProtocolDecl(
                protocolDecl.modifiers, protocolDecl.attributes, protocolDecl.token,
                protocolDecl.name, genericDecl, conformances, whereClause, body,
                sourceRange: protocolDecl.sourceRange
            )
            copySemanticFields(from: protocolDecl, to: newProtocolDecl)
            return newProtocolDecl
        }

        @discardableResult
        open override func visitExtensionDecl(
            _ extensionDecl: AST.ExtensionDecl, additional: Any? = nil
        ) -> Any? {
            let base = rewrite(extensionDecl.base)
            let conformances = rewriteAll(extensionDecl.conformances)
            let body = rewriteAll(extensionDecl.body)
            if base === extensionDecl.base,
               unchanged(extensionDecl.conformances, conformances),
               unchanged(extensionDecl.body, body)
            {
                return extensionDecl
            }
            let newExtensionDecl = AST.ExtensionDecl(
                extensionDecl.modifiers, extensionDecl.attributes, extensionDecl.token, base,
                conformances, body, sourceRange: extensionDecl.sourceRange
            )
            copySemanticFields(from: extensionDecl, to: newExtensionDecl)
            return newExtensionDecl
        }

        @discardableResult
        open override func visitEnumDecl(
            _ enumDecl: AST.EnumDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = enumDecl.genericDecl.map { rewrite($0) }
            let conformances = rewriteAll(enumDecl.conformances)
            let whereClause = rewriteWhereRequirements(enumDecl.whereClause)
            let body = rewriteAll(enumDecl.body)
            if genericDecl === enumDecl.genericDecl,
               unchanged(enumDecl.conformances, conformances),
               whereClauseUnchanged(enumDecl.whereClause, whereClause),
               unchanged(enumDecl.body, body)
            {
                return enumDecl
            }
            let newEnumDecl = AST.EnumDecl(
                enumDecl.modifiers, enumDecl.attributes, enumDecl.token, enumDecl.name,
                genericDecl, conformances, whereClause, body, sourceRange: enumDecl.sourceRange
            )
            copySemanticFields(from: enumDecl, to: newEnumDecl)
            return newEnumDecl
        }

        @discardableResult
        open override func visitEnumCaseDecl(
            _ enumCaseDecl: AST.EnumCaseDecl, additional: Any? = nil
        ) -> Any? {
            var changed = false
            let elements = enumCaseDecl.elements.map { element
                -> AST.EnumCaseDecl.Element in
                let rewritten = rewriteEnumCaseElement(element)
                if !enumElementUnchanged(element, rewritten) { changed = true }
                return rewritten
            }
            if !changed { return enumCaseDecl }
            let newEnumCaseDecl = AST.EnumCaseDecl(
                enumCaseDecl.modifiers, enumCaseDecl.attributes, enumCaseDecl.token, elements,
                sourceRange: enumCaseDecl.sourceRange
            )
            copySemanticFields(from: enumCaseDecl, to: newEnumCaseDecl)
            return newEnumCaseDecl
        }

        private func enumElementUnchanged(
            _ old: AST.EnumCaseDecl.Element, _ new: AST.EnumCaseDecl.Element
        ) -> Bool {
            guard old.associatedValues.count == new.associatedValues.count else { return false }
            for (oldValue, newValue) in zip(old.associatedValues, new.associatedValues)
                where oldValue.typeExpression !== newValue.typeExpression
            {
                return false
            }
            switch (old.rawValue, new.rawValue) {
            case let (oldRaw?, newRaw?):
                return oldRaw === newRaw
            case (nil, nil):
                return true
            default:
                return false
            }
        }

        @discardableResult
        open override func visitInitDecl(
            _ initDecl: AST.InitDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = initDecl.genericDecl.map { rewrite($0) }
            let parameters = rewriteParameters(initDecl.parameters)
            let throwsClause = rewriteThrowsClause(initDecl.throwsClause)
            let body = rewriteAll(initDecl.body)
            if genericDecl === initDecl.genericDecl,
               parametersUnchanged(initDecl.parameters, parameters),
               throwsClauseUnchanged(initDecl.throwsClause, throwsClause),
               unchanged(initDecl.body, body)
            {
                return initDecl
            }
            let newInitDecl = AST.InitDecl(
                initDecl.modifiers, initDecl.attributes, initDecl.token, initDecl.optionalToken,
                genericDecl, parameters, throwsClause, body, sourceRange: initDecl.sourceRange
            )
            copySemanticFields(from: initDecl, to: newInitDecl)
            return newInitDecl
        }

        private func parametersUnchanged(
            _ old: [AST.FunctionDecl.Parameter], _ new: [AST.FunctionDecl.Parameter]
        ) -> Bool {
            guard old.count == new.count else { return false }
            for (oldParameter, newParameter) in zip(old, new) {
                if oldParameter.type !== newParameter.type
                    || oldParameter.defaultValue !== newParameter.defaultValue
                {
                    return false
                }
            }
            return true
        }

        private func throwsClauseUnchanged(
            _ old: AST.ThrowsClause?, _ new: AST.ThrowsClause?
        ) -> Bool {
            switch (old, new) {
            case let (oldClause?, newClause?):
                unchanged(oldClause.types ?? [], newClause.types ?? [])
                    && (oldClause.types == nil) == (newClause.types == nil)
            case (nil, nil):
                true
            default:
                false
            }
        }

        @discardableResult
        open override func visitDeinitDecl(
            _ deinitDecl: AST.DeinitDecl, additional: Any? = nil
        ) -> Any? {
            let body = rewriteAll(deinitDecl.body)
            if unchanged(deinitDecl.body, body) { return deinitDecl }
            return AST.DeinitDecl(
                deinitDecl.modifiers, deinitDecl.attributes, deinitDecl.token, body,
                sourceRange: deinitDecl.sourceRange
            )
        }

        @discardableResult
        open override func visitFunctionDecl(
            _ functionDecl: AST.FunctionDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = functionDecl.genericDecl.map { rewrite($0) }
            let parameters = rewriteParameters(functionDecl.parameters)
            let throwsClause = rewriteThrowsClause(functionDecl.throwsClause)
            let returnTypeExpression = functionDecl.returnTypeExpression.map { rewrite($0) }
            let body = functionDecl.body.map { rewriteFunctionBody($0) }
            if genericDecl === functionDecl.genericDecl,
               parametersUnchanged(functionDecl.parameters, parameters),
               throwsClauseUnchanged(functionDecl.throwsClause, throwsClause),
               returnTypeExpression === functionDecl.returnTypeExpression,
               bodyUnchanged(functionDecl.body, body)
            {
                return functionDecl
            }
            let newFunctionDecl = AST.FunctionDecl(
                functionDecl.modifiers, functionDecl.attributes, functionDecl.token,
                functionDecl.name, genericDecl, parameters, functionDecl.varargToken,
                throwsClause, returnTypeExpression, body, sourceRange: functionDecl.sourceRange
            )
            copySemanticFields(from: functionDecl, to: newFunctionDecl)
            return newFunctionDecl
        }

        private func bodyUnchanged(
            _ old: AST.FunctionDecl.Body?, _ new: AST.FunctionDecl.Body?
        ) -> Bool {
            switch (old, new) {
            case let (oldBody?, newBody?):
                functionBodyUnchanged(oldBody, newBody)
            case (nil, nil):
                true
            default:
                false
            }
        }

        private func functionBodyUnchanged(
            _ old: AST.FunctionDecl.Body, _ new: AST.FunctionDecl.Body
        ) -> Bool {
            switch (old, new) {
            case let (.Block(oldStatements), .Block(newStatements)):
                unchanged(oldStatements, newStatements)
            case let (.Expression(oldExpression), .Expression(newExpression)):
                oldExpression === newExpression
            default:
                false
            }
        }

        @discardableResult
        open override func visitVariableDecl(
            _ variableDecl: AST.VariableDecl, additional: Any? = nil
        ) -> Any? {
            let typeExpression = variableDecl.typeExpression.map { rewrite($0) }
            let initializer = variableDecl.initializer.map { rewrite($0) }
            var accessorsChanged = false
            let accessors = variableDecl.accessors.map { accessor -> AST.Accessor in
                let rewritten = rewrite(accessor)
                if rewritten !== accessor { accessorsChanged = true }
                return rewritten
            }
            if typeExpression === variableDecl.typeExpression,
               initializer === variableDecl.initializer, !accessorsChanged
            {
                return variableDecl
            }
            let newVariableDecl = AST.VariableDecl(
                variableDecl.modifiers, variableDecl.attributes, variableDecl.token,
                variableDecl.internalToken, variableDecl.name, typeExpression, initializer,
                accessors, sourceRange: variableDecl.sourceRange
            )
            copySemanticFields(from: variableDecl, to: newVariableDecl)
            return newVariableDecl
        }

        @discardableResult
        open override func visitReturn(
            _ ret: AST.Return, additional: Any? = nil
        ) -> Any? {
            guard let value = ret.value else { return ret }
            let newValue = rewrite(value)
            if newValue === value { return ret }
            return AST.Return(ret.token, newValue, sourceRange: ret.sourceRange)
        }

        @discardableResult
        open override func visitThrow(
            _ throwStatement: AST.Throw, additional: Any? = nil
        ) -> Any? {
            let expression = rewrite(throwStatement.expression)
            if expression === throwStatement.expression { return throwStatement }
            return AST.Throw(throwStatement.token, expression, sourceRange: throwStatement.sourceRange)
        }

        @discardableResult
        open override func visitWhile(
            _ whileStatement: AST.While, additional: Any? = nil
        ) -> Any? {
            let condition = rewrite(whileStatement.condition)
            let body = rewriteAll(whileStatement.body)
            if condition === whileStatement.condition, unchanged(whileStatement.body, body) {
                return whileStatement
            }
            return AST.While(
                whileStatement.token, condition, whileStatement.beginToken, body,
                whileStatement.endToken, sourceRange: whileStatement.sourceRange
            )
        }

        @discardableResult
        open override func visitRepeatWhile(
            _ repeatWhile: AST.RepeatWhile, additional: Any? = nil
        ) -> Any? {
            let body = rewriteAll(repeatWhile.body)
            let condition = rewrite(repeatWhile.condition)
            if unchanged(repeatWhile.body, body), condition === repeatWhile.condition {
                return repeatWhile
            }
            return AST.RepeatWhile(
                repeatWhile.token, repeatWhile.beginToken, body, repeatWhile.endToken,
                repeatWhile.whileToken, condition, sourceRange: repeatWhile.sourceRange
            )
        }

        @discardableResult
        open override func visitGuard(
            _ guardStatement: AST.Guard, additional: Any? = nil
        ) -> Any? {
            let condition = rewrite(guardStatement.condition)
            let body = rewriteAll(guardStatement.body)
            if condition === guardStatement.condition, unchanged(guardStatement.body, body) {
                return guardStatement
            }
            return AST.Guard(
                guardStatement.token, condition, guardStatement.beginToken, body,
                guardStatement.endToken, sourceRange: guardStatement.sourceRange
            )
        }

        @discardableResult
        open override func visitFor(
            _ forStatement: AST.For, additional: Any? = nil
        ) -> Any? {
            let pattern = rewrite(forStatement.pattern)
            let sequence = rewrite(forStatement.sequence)
            let body = rewriteAll(forStatement.body)
            if pattern === forStatement.pattern, sequence === forStatement.sequence,
               unchanged(forStatement.body, body)
            {
                return forStatement
            }
            return AST.For(
                forStatement.token, forStatement.asyncToken, pattern, forStatement.inToken,
                sequence, forStatement.beginToken, body, forStatement.endToken,
                sourceRange: forStatement.sourceRange
            )
        }

        @discardableResult
        open override func visitDefer(
            _ deferStatement: AST.Defer, additional: Any? = nil
        ) -> Any? {
            let body = rewriteAll(deferStatement.body)
            if unchanged(deferStatement.body, body) { return deferStatement }
            return AST.Defer(
                deferStatement.token, deferStatement.beginToken, body, deferStatement.endToken,
                sourceRange: deferStatement.sourceRange
            )
        }

        @discardableResult
        open override func visitAsm(
            _ asmStatement: AST.Asm, additional: Any? = nil
        ) -> Any? {
            let templates = rewriteAll(asmStatement.templates)
            if unchanged(asmStatement.templates, templates) { return asmStatement }
            return AST.Asm(
                asmStatement.token, asmStatement.beginToken, templates, asmStatement.bindings,
                asmStatement.options, asmStatement.endToken, sourceRange: asmStatement.sourceRange
            )
        }

        @discardableResult
        open override func visitBreak(
            _ breakStatement: AST.Break, additional: Any? = nil
        ) -> Any? {
            breakStatement
        }

        @discardableResult
        open override func visitContinue(
            _ continueStatement: AST.Continue, additional: Any? = nil
        ) -> Any? {
            continueStatement
        }

        @discardableResult
        open override func visitGoto(
            _ gotoStatement: AST.Goto, additional: Any? = nil
        ) -> Any? {
            gotoStatement
        }

        @discardableResult
        open override func visitLabeledStatement(
            _ labeledStatement: AST.LabeledStatement, additional: Any? = nil
        ) -> Any? {
            let body = rewrite(labeledStatement.body)
            if body === labeledStatement.body { return labeledStatement }
            return AST.LabeledStatement(
                labeledStatement.label, body, sourceRange: labeledStatement.sourceRange
            )
        }

        @discardableResult
        open override func visitAccessor(
            _ accessor: AST.Accessor, additional: Any? = nil
        ) -> Any? {
            let body = rewriteFunctionBody(accessor.body)
            if functionBodyUnchanged(accessor.body, body) { return accessor }
            return AST.Accessor(
                accessor.modifiers, accessor.attributes, accessor.token, accessor.parameterName,
                body, kind: accessor.kind, sourceRange: accessor.sourceRange
            )
        }

        @discardableResult
        open override func visitErrorExpression(
            _ errorExpression: AST.ErrorExpression, additional: Any? = nil
        ) -> Any? {
            errorExpression
        }

        @discardableResult
        open override func visitParentheticalExpression(
            _ parentheticalExpression: AST.ParentheticalExpression, additional: Any? = nil
        ) -> Any? {
            let inner = rewrite(parentheticalExpression.inner)
            if inner === parentheticalExpression.inner { return parentheticalExpression }
            let newParentheticalExpression = AST.ParentheticalExpression(
                inner, sourceRange: parentheticalExpression.sourceRange
            )
            copySemanticFields(from: parentheticalExpression, to: newParentheticalExpression)
            return newParentheticalExpression
        }

        @discardableResult
        open override func visitVariable(
            _ variable: AST.Variable, additional: Any? = nil
        ) -> Any? {
            variable
        }

        @discardableResult
        open override func visitGenericApplication(
            _ genericApplication: AST.GenericApplication, additional: Any? = nil
        ) -> Any? {
            let base = rewrite(genericApplication.base)
            let genericArguments = rewriteAll(genericApplication.genericArguments)
            if base === genericApplication.base,
               unchanged(genericApplication.genericArguments, genericArguments)
            {
                return genericApplication
            }
            let newGenericApplication = AST.GenericApplication(
                base, genericArguments, sourceRange: genericApplication.sourceRange
            )
            copySemanticFields(from: genericApplication, to: newGenericApplication)
            return newGenericApplication
        }

        @discardableResult
        open override func visitIntegerLiteral(
            _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
        ) -> Any? {
            integerLiteral
        }

        @discardableResult
        open override func visitFloatLiteral(
            _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
        ) -> Any? {
            floatLiteral
        }

        @discardableResult
        open override func visitStringLiteral(
            _ stringLiteral: AST.StringLiteral, additional: Any? = nil
        ) -> Any? {
            stringLiteral
        }

        @discardableResult
        open override func visitCharLiteral(
            _ charLiteral: AST.CharLiteral, additional: Any? = nil
        ) -> Any? {
            charLiteral
        }

        @discardableResult
        open override func visitBoolLiteral(
            _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
        ) -> Any? {
            boolLiteral
        }

        @discardableResult
        open override func visitNullLiteral(
            _ nullLiteral: AST.NullLiteral, additional: Any? = nil
        ) -> Any? {
            nullLiteral
        }

        @discardableResult
        open override func visitVoidLiteral(
            _ voidLiteral: AST.VoidLiteral, additional: Any? = nil
        ) -> Any? {
            voidLiteral
        }

        @discardableResult
        open override func visitIf(
            _ ifExpression: AST.If, additional: Any? = nil
        ) -> Any? {
            let condition = rewrite(ifExpression.condition)
            let then = rewriteAll(ifExpression.then)
            let elseKind = rewriteElseKind(ifExpression.elseKind)
            if condition === ifExpression.condition, unchanged(ifExpression.then, then),
               elseKindUnchanged(ifExpression.elseKind, elseKind)
            {
                return ifExpression
            }
            let newIf = AST.If(
                ifExpression.token, condition, then, elseKind,
                sourceRange: ifExpression.sourceRange
            )
            copySemanticFields(from: ifExpression, to: newIf)
            return newIf
        }

        private func elseKindUnchanged(
            _ old: AST.If.ElseKind?, _ new: AST.If.ElseKind?
        ) -> Bool {
            switch (old, new) {
            case let (oldKind?, newKind?):
                switch (oldKind, newKind) {
                case let (.Block(oldStatements), .Block(newStatements)):
                    unchanged(oldStatements, newStatements)
                case let (.If(oldIf), .If(newIf)):
                    oldIf === newIf
                default:
                    false
                }
            case (nil, nil):
                true
            default:
                false
            }
        }

        @discardableResult
        open override func visitMatch(
            _ matchExpression: AST.Match, additional: Any? = nil
        ) -> Any? {
            let subject = rewrite(matchExpression.subject)
            var casesChanged = false
            let cases = matchExpression.cases.map { matchCase -> AST.Match.Case in
                let rewritten = rewriteMatchCase(matchCase)
                if !matchCaseUnchanged(matchCase, rewritten) { casesChanged = true }
                return rewritten
            }
            if subject === matchExpression.subject, !casesChanged { return matchExpression }
            let newMatch = AST.Match(
                matchExpression.token, subject, cases, sourceRange: matchExpression.sourceRange
            )
            copySemanticFields(from: matchExpression, to: newMatch)
            return newMatch
        }

        private func matchCaseUnchanged(
            _ old: AST.Match.Case, _ new: AST.Match.Case
        ) -> Bool {
            unchanged(old.patterns, new.patterns) && unchanged(old.body, new.body)
        }

        @discardableResult
        open override func visitDo(
            _ doExpression: AST.Do, additional: Any? = nil
        ) -> Any? {
            let body = rewriteAll(doExpression.body)
            var catchesChanged = false
            let catches = doExpression.catches.map { catchClause -> AST.Do.CatchClause in
                let rewritten = rewriteCatchClause(catchClause)
                if !catchClauseUnchanged(catchClause, rewritten) { catchesChanged = true }
                return rewritten
            }
            let finallyBody: [Statement]? = if let oldFinallyBody = doExpression.finallyBody {
                rewriteAll(oldFinallyBody)
            } else {
                nil
            }
            let finallyChanged: Bool = if let oldFinallyBody = doExpression.finallyBody, let finallyBody {
                !unchanged(oldFinallyBody, finallyBody)
            } else {
                (doExpression.finallyBody != nil) != (finallyBody != nil)
            }
            if unchanged(doExpression.body, body), !catchesChanged, !finallyChanged {
                return doExpression
            }
            let newDo = AST.Do(
                doExpression.token, body, catches, finallyBody,
                sourceRange: doExpression.sourceRange
            )
            copySemanticFields(from: doExpression, to: newDo)
            return newDo
        }

        private func catchClauseUnchanged(
            _ old: AST.Do.CatchClause, _ new: AST.Do.CatchClause
        ) -> Bool {
            switch (old.pattern, new.pattern) {
            case let (oldPattern?, newPattern?):
                if oldPattern !== newPattern { return false }
            case (nil, nil):
                break
            default:
                return false
            }
            switch (old.whereCondition, new.whereCondition) {
            case let (oldCondition?, newCondition?):
                if oldCondition !== newCondition { return false }
            case (nil, nil):
                break
            default:
                return false
            }
            return unchanged(old.body, new.body)
        }

        @discardableResult
        open override func visitCall(
            _ call: AST.Call, additional: Any? = nil
        ) -> Any? {
            let callee = rewrite(call.callee)
            var argumentsChanged = false
            let arguments = call.arguments.map { argument -> AST.LabeledArgument in
                let value = rewrite(argument.value)
                if value !== argument.value { argumentsChanged = true }
                return AST.LabeledArgument(
                    label: argument.label, value: value, sourceRange: argument.sourceRange
                )
            }
            var trailingClosuresChanged = false
            let trailingClosures = call.trailingClosures.map { pair -> (Token?, AST.Closure) in
                let closure = rewrite(pair.1)
                if closure !== pair.1 { trailingClosuresChanged = true }
                return (pair.0, closure)
            }
            if callee === call.callee, !argumentsChanged, !trailingClosuresChanged {
                return call
            }
            let newCall = AST.Call(
                callee: callee, arguments: arguments, trailingClosures: trailingClosures,
                sourceRange: call.sourceRange
            )
            copySemanticFields(from: call, to: newCall)
            return newCall
        }

        @discardableResult
        open override func visitMemberAccess(
            _ memberAccess: AST.MemberAccess, additional: Any? = nil
        ) -> Any? {
            let object = rewrite(memberAccess.object)
            if object === memberAccess.object { return memberAccess }
            let newMemberAccess = AST.MemberAccess(
                object, memberAccess.token, memberAccess.member,
                isOptional: memberAccess.isOptional, sourceRange: memberAccess.sourceRange
            )
            copySemanticFields(from: memberAccess, to: newMemberAccess)
            return newMemberAccess
        }

        @discardableResult
        open override func visitSelfTypeExpression(
            _ selfTypeExpression: AST.SelfTypeExpression, additional: Any? = nil
        ) -> Any? {
            selfTypeExpression
        }

        @discardableResult
        open override func visitSelfExpression(
            _ selfExpression: AST.SelfExpression, additional: Any? = nil
        ) -> Any? {
            selfExpression
        }

        @discardableResult
        open override func visitSuperExpression(
            _ superExpression: AST.SuperExpression, additional: Any? = nil
        ) -> Any? {
            superExpression
        }

        @discardableResult
        open override func visitImplicitMemberAccess(
            _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
        ) -> Any? {
            implicitMemberAccess
        }

        @discardableResult
        open override func visitClosure(
            _ closure: AST.Closure, additional: Any? = nil
        ) -> Any? {
            let signature = rewriteClosureSignature(closure.signature)
            let body = rewriteAll(closure.body)
            if signatureMatches(closure.signature, signature), unchanged(closure.body, body) {
                return closure
            }
            let newClosure = AST.Closure(signature, body, sourceRange: closure.sourceRange)
            copySemanticFields(from: closure, to: newClosure)
            return newClosure
        }

        private func signatureMatches(
            _ old: AST.ClosureSignature?, _ new: AST.ClosureSignature?
        ) -> Bool {
            guard let old, let new else {
                return (old == nil) == (new == nil)
            }
            return parametersUnchanged(old.parameters, new.parameters)
                && throwsClauseUnchanged(old.throwsClause, new.throwsClause)
                && old.returnType === new.returnType
        }

        @discardableResult
        open override func visitClosureType(
            _ closureType: AST.ClosureType, additional: Any? = nil
        ) -> Any? {
            let parameterTypes = rewrite(closureType.parameterTypes)
            let throwsClause = rewriteThrowsClause(closureType.throwsClause)
            let returnType = rewrite(closureType.returnType)
            if parameterTypes === closureType.parameterTypes,
               throwsClauseUnchanged(closureType.throwsClause, throwsClause),
               returnType === closureType.returnType
            {
                return closureType
            }
            let newClosureType = AST.ClosureType(
                parameterTypes, throwsClause, returnType, sourceRange: closureType.sourceRange
            )
            copySemanticFields(from: closureType, to: newClosureType)
            return newClosureType
        }

        @discardableResult
        open override func visitOptionalType(
            _ optionalType: AST.OptionalType, additional: Any? = nil
        ) -> Any? {
            let wrappedType = rewrite(optionalType.wrappedType)
            if wrappedType === optionalType.wrappedType { return optionalType }
            let newOptionalType = AST.OptionalType(
                wrappedType, optionalType.token, sourceRange: optionalType.sourceRange
            )
            copySemanticFields(from: optionalType, to: newOptionalType)
            return newOptionalType
        }

        @discardableResult
        open override func visitVariadicType(
            _ variadicType: AST.VariadicType, additional: Any? = nil
        ) -> Any? {
            let base = rewrite(variadicType.base)
            if base === variadicType.base { return variadicType }
            let newVariadicType = AST.VariadicType(
                base, variadicType.token, sourceRange: variadicType.sourceRange
            )
            copySemanticFields(from: variadicType, to: newVariadicType)
            return newVariadicType
        }

        @discardableResult
        open override func visitSomeType(
            _ someType: AST.SomeType, additional: Any? = nil
        ) -> Any? {
            let wrappedType = rewrite(someType.wrappedType)
            if wrappedType === someType.wrappedType { return someType }
            let newSomeType = AST.SomeType(
                someType.token, wrappedType, sourceRange: someType.sourceRange
            )
            copySemanticFields(from: someType, to: newSomeType)
            return newSomeType
        }

        @discardableResult
        open override func visitAnyType(
            _ anyType: AST.AnyType, additional: Any? = nil
        ) -> Any? {
            let wrappedType = rewrite(anyType.wrappedType)
            if wrappedType === anyType.wrappedType { return anyType }
            let newAnyType = AST.AnyType(
                anyType.token, wrappedType, sourceRange: anyType.sourceRange
            )
            copySemanticFields(from: anyType, to: newAnyType)
            return newAnyType
        }

        @discardableResult
        open override func visitProtocolCompositionType(
            _ protocolCompositionType: AST.ProtocolCompositionType, additional: Any? = nil
        ) -> Any? {
            let types = rewriteAll(protocolCompositionType.types)
            if unchanged(protocolCompositionType.types, types) { return protocolCompositionType }
            let newProtocolCompositionType = AST.ProtocolCompositionType(
                types, sourceRange: protocolCompositionType.sourceRange
            )
            copySemanticFields(from: protocolCompositionType, to: newProtocolCompositionType)
            return newProtocolCompositionType
        }

        @discardableResult
        open override func visitTupleExpression(
            _ tupleExpression: AST.TupleExpression, additional: Any? = nil
        ) -> Any? {
            var elementsChanged = false
            let elements = tupleExpression.elements.map { element -> AST.LabeledArgument in
                let value = rewrite(element.value)
                if value !== element.value { elementsChanged = true }
                return AST.LabeledArgument(
                    label: element.label, value: value, sourceRange: element.sourceRange
                )
            }
            if !elementsChanged { return tupleExpression }
            let newTupleExpression = AST.TupleExpression(
                elements, sourceRange: tupleExpression.sourceRange
            )
            copySemanticFields(from: tupleExpression, to: newTupleExpression)
            return newTupleExpression
        }

        @discardableResult
        open override func visitIsPattern(
            _ isPattern: AST.IsPattern, additional: Any? = nil
        ) -> Any? {
            let typeExpression = rewrite(isPattern.typeExpression)
            if typeExpression === isPattern.typeExpression { return isPattern }
            let newIsPattern = AST.IsPattern(
                isPattern.token, typeExpression, sourceRange: isPattern.sourceRange
            )
            copySemanticFields(from: isPattern, to: newIsPattern)
            return newIsPattern
        }

        @discardableResult
        open override func visitAsPattern(
            _ asPattern: AST.AsPattern, additional: Any? = nil
        ) -> Any? {
            let pattern = rewrite(asPattern.pattern)
            let typeExpression = rewrite(asPattern.typeExpression)
            if pattern === asPattern.pattern, typeExpression === asPattern.typeExpression {
                return asPattern
            }
            let newAsPattern = AST.AsPattern(
                pattern, asPattern.token, typeExpression, sourceRange: asPattern.sourceRange
            )
            copySemanticFields(from: asPattern, to: newAsPattern)
            return newAsPattern
        }

        @discardableResult
        open override func visitSequentialExpression(
            _ sequentialExpression: AST.SequentialExpression, additional: Any? = nil
        ) -> Any? {
            let operands = rewriteAll(sequentialExpression.operands)
            if unchanged(sequentialExpression.operands, operands) {
                return sequentialExpression
            }
            let newSequentialExpression = AST.SequentialExpression(
                sequentialExpression.ops, operands, sourceRange: sequentialExpression.sourceRange
            )
            copySemanticFields(from: sequentialExpression, to: newSequentialExpression)
            return newSequentialExpression
        }

        @discardableResult
        open override func visitBinary(
            _ binary: AST.Binary, additional: Any? = nil
        ) -> Any? {
            let left = rewrite(binary.left)
            let right = rewrite(binary.right)
            if left === binary.left, right === binary.right { return binary }
            let newBinary = AST.Binary(
                left, right, binary.operatorToken, sourceRange: binary.sourceRange
            )
            copySemanticFields(from: binary, to: newBinary)
            return newBinary
        }

        @discardableResult
        open override func visitPrefix(
            _ prefixExpression: AST.Prefix, additional: Any? = nil
        ) -> Any? {
            let expression = rewrite(prefixExpression.expression)
            if expression === prefixExpression.expression { return prefixExpression }
            let newPrefix = AST.Prefix(
                prefixExpression.operatorToken, expression,
                sourceRange: prefixExpression.sourceRange
            )
            copySemanticFields(from: prefixExpression, to: newPrefix)
            return newPrefix
        }

        @discardableResult
        open override func visitPostfix(
            _ postfixExpression: AST.Postfix, additional: Any? = nil
        ) -> Any? {
            let expression = rewrite(postfixExpression.expression)
            if expression === postfixExpression.expression { return postfixExpression }
            let newPostfix = AST.Postfix(
                expression, postfixExpression.operatorToken,
                sourceRange: postfixExpression.sourceRange
            )
            copySemanticFields(from: postfixExpression, to: newPostfix)
            return newPostfix
        }

        @discardableResult
        open override func visitArrayLiteral(
            _ arrayLiteral: AST.ArrayLiteral, additional: Any? = nil
        ) -> Any? {
            let elements = rewriteAll(arrayLiteral.elements)
            if unchanged(arrayLiteral.elements, elements) { return arrayLiteral }
            let newArrayLiteral = AST.ArrayLiteral(
                elements, sourceRange: arrayLiteral.sourceRange
            )
            copySemanticFields(from: arrayLiteral, to: newArrayLiteral)
            return newArrayLiteral
        }

        @discardableResult
        open override func visitDictionaryLiteral(
            _ dictionaryLiteral: AST.DictionaryLiteral, additional: Any? = nil
        ) -> Any? {
            var entriesChanged = false
            let entries = dictionaryLiteral.entries.map { entry -> AST.DictionaryLiteral.Entry in
                let rewritten = rewriteDictionaryEntry(entry)
                if !dictionaryEntryUnchanged(entry, rewritten) { entriesChanged = true }
                return rewritten
            }
            if !entriesChanged { return dictionaryLiteral }
            let newDictionaryLiteral = AST.DictionaryLiteral(
                entries, sourceRange: dictionaryLiteral.sourceRange
            )
            copySemanticFields(from: dictionaryLiteral, to: newDictionaryLiteral)
            return newDictionaryLiteral
        }

        private func dictionaryEntryUnchanged(
            _ old: AST.DictionaryLiteral.Entry, _ new: AST.DictionaryLiteral.Entry
        ) -> Bool {
            old.key === new.key && old.value === new.value
        }

        @discardableResult
        open override func visitCastExpression(
            _ castExpression: AST.CastExpression, additional: Any? = nil
        ) -> Any? {
            let left = rewrite(castExpression.left)
            let right = rewrite(castExpression.right)
            if left === castExpression.left, right === castExpression.right {
                return castExpression
            }
            let newCastExpression = AST.CastExpression(
                left, castExpression.token, right, castExpression.kind,
                sourceRange: castExpression.sourceRange
            )
            copySemanticFields(from: castExpression, to: newCastExpression)
            return newCastExpression
        }

        @discardableResult
        open override func visitTryExpression(
            _ tryExpression: AST.TryExpression, additional: Any? = nil
        ) -> Any? {
            let expression = rewrite(tryExpression.expression)
            if expression === tryExpression.expression { return tryExpression }
            let newTryExpression = AST.TryExpression(
                tryExpression.token, tryExpression.kind, expression,
                sourceRange: tryExpression.sourceRange
            )
            copySemanticFields(from: tryExpression, to: newTryExpression)
            return newTryExpression
        }

        @discardableResult
        open override func visitAwaitExpression(
            _ awaitExpression: AST.AwaitExpression, additional: Any? = nil
        ) -> Any? {
            let expression = rewrite(awaitExpression.expression)
            if expression === awaitExpression.expression { return awaitExpression }
            let newAwaitExpression = AST.AwaitExpression(
                awaitExpression.token, expression, sourceRange: awaitExpression.sourceRange
            )
            copySemanticFields(from: awaitExpression, to: newAwaitExpression)
            return newAwaitExpression
        }

        @discardableResult
        open override func visitSubscript(
            _ subscriptExpr: AST.Subscript, additional: Any? = nil
        ) -> Any? {
            let base = rewrite(subscriptExpr.base)
            var argumentsChanged = false
            let arguments = subscriptExpr.arguments.map { argument -> AST.LabeledArgument in
                let value = rewrite(argument.value)
                if value !== argument.value { argumentsChanged = true }
                return AST.LabeledArgument(
                    label: argument.label, value: value, sourceRange: argument.sourceRange
                )
            }
            if base === subscriptExpr.base, !argumentsChanged { return subscriptExpr }
            let newSubscript = AST.Subscript(
                base: base, arguments: arguments, sourceRange: subscriptExpr.sourceRange
            )
            copySemanticFields(from: subscriptExpr, to: newSubscript)
            return newSubscript
        }

        @discardableResult
        open override func visitOptionalBinding(
            _ optionalBinding: AST.OptionalBinding, additional: Any? = nil
        ) -> Any? {
            let typeExpression = optionalBinding.typeExpression.map { rewrite($0) }
            let value = rewrite(optionalBinding.value)
            if typeExpression === optionalBinding.typeExpression, value === optionalBinding.value {
                return optionalBinding
            }
            let newOptionalBinding = AST.OptionalBinding(
                optionalBinding.token, optionalBinding.name, typeExpression, value,
                sourceRange: optionalBinding.sourceRange
            )
            copySemanticFields(from: optionalBinding, to: newOptionalBinding)
            return newOptionalBinding
        }

        @discardableResult
        open override func visitCaseMatch(
            _ caseMatch: AST.CaseMatch, additional: Any? = nil
        ) -> Any? {
            let pattern = rewrite(caseMatch.pattern)
            let subject = rewrite(caseMatch.subject)
            if pattern === caseMatch.pattern, subject === caseMatch.subject {
                return caseMatch
            }
            let newCaseMatch = AST.CaseMatch(
                caseMatch.token, pattern, subject, sourceRange: caseMatch.sourceRange
            )
            copySemanticFields(from: caseMatch, to: newCaseMatch)
            return newCaseMatch
        }

        @discardableResult
        open override func visitBindingPattern(
            _ bindingPattern: AST.BindingPattern, additional: Any? = nil
        ) -> Any? {
            let typeExpression = bindingPattern.typeExpression.map { rewrite($0) }
            let subpattern = bindingPattern.subpattern.map { rewrite($0) }
            if typeExpression === bindingPattern.typeExpression,
               subpattern === bindingPattern.subpattern
            {
                return bindingPattern
            }
            let newBindingPattern = AST.BindingPattern(
                bindingPattern.token, bindingPattern.name, typeExpression, subpattern,
                sourceRange: bindingPattern.sourceRange
            )
            copySemanticFields(from: bindingPattern, to: newBindingPattern)
            return newBindingPattern
        }

        @discardableResult
        open override func visitWildcardPattern(
            _ wildcardPattern: AST.WildcardPattern, additional: Any? = nil
        ) -> Any? {
            wildcardPattern
        }

        @discardableResult
        open override func visitShorthandArgument(
            _ shorthandArgument: AST.ShorthandArgument, additional: Any? = nil
        ) -> Any? {
            shorthandArgument
        }

        @discardableResult
        open override func visitKeyPathExpression(
            _ keyPathExpression: AST.KeyPathExpression, additional: Any? = nil
        ) -> Any? {
            guard let root = keyPathExpression.root else { return keyPathExpression }
            let newRoot = rewrite(root)
            if newRoot === root { return keyPathExpression }
            let newKeyPathExpression = AST.KeyPathExpression(
                keyPathExpression.backslashToken, newRoot, keyPathExpression.rootPostfix,
                keyPathExpression.components, sourceRange: keyPathExpression.sourceRange
            )
            copySemanticFields(from: keyPathExpression, to: newKeyPathExpression)
            return newKeyPathExpression
        }

        @discardableResult
        open override func visitStringInterpolation(
            _ interpolation: AST.StringInterpolation, additional: Any? = nil
        ) -> Any? {
            var segmentsChanged = false
            let segments = interpolation.segments.map { segment -> AST.StringSegment in
                let rewritten = rewriteStringSegment(segment)
                if !stringSegmentUnchanged(segment, rewritten) { segmentsChanged = true }
                return rewritten
            }
            if !segmentsChanged { return interpolation }
            let newInterpolation = AST.StringInterpolation(
                segments, sourceRange: interpolation.sourceRange
            )
            copySemanticFields(from: interpolation, to: newInterpolation)
            return newInterpolation
        }

        private func stringSegmentUnchanged(
            _ old: AST.StringSegment, _ new: AST.StringSegment
        ) -> Bool {
            switch (old, new) {
            case (.literal, .literal):
                true
            case let (.expression(oldExpression), .expression(newExpression)):
                oldExpression === newExpression
            default:
                false
            }
        }

        @discardableResult
        open override func visitSubscriptDecl(
            _ subscriptDecl: AST.SubscriptDecl, additional: Any? = nil
        ) -> Any? {
            let genericDecl = subscriptDecl.genericDecl.map { rewrite($0) }
            let parameters = rewriteParameters(subscriptDecl.parameters)
            let throwsClause = rewriteThrowsClause(subscriptDecl.throwsClause)
            let returnType = rewrite(subscriptDecl.returnType)
            let body = rewriteAll(subscriptDecl.body)
            if genericDecl === subscriptDecl.genericDecl,
               parametersUnchanged(subscriptDecl.parameters, parameters),
               throwsClauseUnchanged(subscriptDecl.throwsClause, throwsClause),
               returnType === subscriptDecl.returnType, unchanged(subscriptDecl.body, body)
            {
                return subscriptDecl
            }
            let newSubscriptDecl = AST.SubscriptDecl(
                subscriptDecl.modifiers, subscriptDecl.attributes, subscriptDecl.token,
                genericDecl, parameters, throwsClause, returnType, body,
                sourceRange: subscriptDecl.sourceRange
            )
            copySemanticFields(from: subscriptDecl, to: newSubscriptDecl)
            return newSubscriptDecl
        }

        @discardableResult
        open override func visitAssociatedTypeDecl(
            _ associatedTypeDecl: AST.AssociatedTypeDecl, additional: Any? = nil
        ) -> Any? {
            let constraint = associatedTypeDecl.constraint.map { rewrite($0) }
            let whereClause = rewriteWhereRequirements(associatedTypeDecl.whereClause)
            if constraint === associatedTypeDecl.constraint,
               whereClauseUnchanged(associatedTypeDecl.whereClause, whereClause)
            {
                return associatedTypeDecl
            }
            let newAssociatedTypeDecl = AST.AssociatedTypeDecl(
                associatedTypeDecl.modifiers, associatedTypeDecl.attributes,
                associatedTypeDecl.token, associatedTypeDecl.name, constraint, whereClause,
                sourceRange: associatedTypeDecl.sourceRange
            )
            copySemanticFields(from: associatedTypeDecl, to: newAssociatedTypeDecl)
            return newAssociatedTypeDecl
        }
    }
}
