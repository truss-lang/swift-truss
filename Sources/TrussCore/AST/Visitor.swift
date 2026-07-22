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
            var last: Any? = nil
            for statement in program.statements {
                last = visit(statement, additional: additional)
            }
            return last
        }

        @discardableResult
        open func visitEmptyStatement(
            _ emptyStatement: AST.EmptyStatement, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitErrorStatement(
            _ errorStatement: AST.ErrorStatement, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitExpressionStatement(
            _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
        ) -> Any? {
            visit(expressionStatement.expression, additional: additional)
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
        open func visitModuleDecl(
            _ moduleDecl: AST.ModuleDecl, additional: Any? = nil
        ) -> Any? {
            for statement in moduleDecl.body {
                visit(statement, additional: additional)
            }
            return nil
        }

        /* This method will do nothing, because we don't want to
         * visit this node most of the time. It will be individually
         * processed by the `TrussOperators` module.
         */
        @discardableResult
        open func visitPrecedenceGroupDecl(
            _ precedenceGroupDecl: AST.PrecedenceGroupDecl, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitFunctionDecl(
            _ functionDecl: AST.FunctionDecl, additional: Any? = nil
        ) -> Any? {
            if let returnTypeExpression = functionDecl.returnTypeExpression {
                visit(returnTypeExpression, additional: additional)
            }
            switch functionDecl.body {
            case .Block(let statements):
                var last: Any? = nil
                for statement in statements {
                    last = visit(statement, additional: additional)
                }
                return last
            case .Expression(let expression):
                return visit(expression, additional: additional)
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
            return nil
        }

        @discardableResult
        open func visitErrorExpression(
            _ errorExpression: AST.ErrorExpression, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
            return nil
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
            _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitFloatLiteral(
            _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitStringLiteral(
            _ stringLiteral: AST.StringLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitCharLiteral(
            _ charLiteral: AST.CharLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitBoolLiteral(
            _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitNullLiteral(
            _ nullLiteral: AST.NullLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }

        @discardableResult
        open func visitCall(
            _ call: AST.Call, additional: Any? = nil
        ) -> Any? {
            visit(call.callee, additional: additional)
            for argument in call.arguments {
                visit(argument, additional: additional)
            }
            return nil
        }

        @discardableResult
        open func visitMemberAccess(
            _ memberAccess: AST.MemberAccess, additional: Any? = nil
        ) -> Any? {
            return visit(memberAccess.object, additional: additional)
        }

        @discardableResult
        open func visitSequentialExpression(
            _ sequentialExpression: AST.SequentialExpression, additional: Any? = nil
        ) -> Any? {
            var last: Any? = nil
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
            return visit(prefixExpression.expression, additional: additional)
        }

        @discardableResult
        open func visitPostfix(
            _ postfixExpression: AST.Postfix, additional: Any? = nil
        ) -> Any? {
            return visit(postfixExpression.expression, additional: additional)
        }
    }
}
