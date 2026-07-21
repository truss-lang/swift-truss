import SwiftAbstract

extension AST {
    @abstractClass
    open class Visitor {
        @abstractInit
        public init() {}
        open func visit(_ node: AST.AstNode, additional: Any? = nil) -> Any? {
            node.accept(self, additional: additional)
        }
        open func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
            var last: Any? = nil
            for statement in program.statements {
                last = visit(statement, additional: additional)
            }
            return last
        }
        open func visitEmptyStatement(
            _ emptyStatement: AST.EmptyStatement, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitErrorStatement(
            _ errorStatement: AST.ErrorStatement, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitExpressionStatement(
            _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
        ) -> Any? {
            visit(expressionStatement.expression, additional: additional)
        }
        open func visitReturn(
            _ ret: AST.Return, additional: Any? = nil
        ) -> Any? {
            if let value = ret.value {
                visit(value, additional: additional)
            } else {
                nil
            }
        }
        open func visitFunctionDecl(
            _ functionDecl: AST.FunctionDecl, additional: Any? = nil
        ) -> Any? {
            if let returnTypeExpression = functionDecl.returnTypeExpression {
                let _ = visit(returnTypeExpression, additional: additional)
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
        open func visitVariableDecl(
            _ variableDecl: AST.VariableDecl, additional: Any? = nil
        ) -> Any? {
            if let typeExpression = variableDecl.typeExpression {
                let _ = visit(typeExpression, additional: additional)
            }
            if let initializer = variableDecl.initializer {
                let _ = visit(initializer, additional: additional)
            }
            return nil
        }
        open func visitErrorExpression(
            _ errorExpression: AST.ErrorExpression, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
            return nil
        }
        open func visitGenericApplication(
            _ genericApplication: AST.GenericApplication, additional: Any? = nil
        ) -> Any? {
            let _ = visit(genericApplication.base, additional: additional)
            for genericArgument in genericApplication.genericArguments {
                let _ = visit(genericArgument, additional: additional)
            }
            return nil
        }
        open func visitIntegerLiteral(
            _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitFloatLiteral(
            _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitStringLiteral(
            _ stringLiteral: AST.StringLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitCharLiteral(
            _ charLiteral: AST.CharLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitBoolLiteral(
            _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitNullLiteral(
            _ nullLiteral: AST.NullLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        open func visitCall(
            _ call: AST.Call, additional: Any? = nil
        ) -> Any? {
            let _ = visit(call.callee, additional: additional)
            for argument in call.arguments {
                let _ = visit(argument, additional: additional)
            }
            return nil
        }
        open func visitMemberAccess(
            _ memberAccess: AST.MemberAccess, additional: Any? = nil
        ) -> Any? {
            return visit(memberAccess.object, additional: additional)
        }
        open func visitInfix(
            _ infixExpression: AST.Infix, additional: Any? = nil
        ) -> Any? {
            var last: Any? = nil
            for operand in infixExpression.operands {
                last = visit(operand, additional: additional)
            }
            return last
        }
        open func visitBinary(
            _ binary: AST.Binary, additional: Any? = nil
        ) -> Any? {
            let _ = visit(binary.left, additional: additional)
            return visit(binary.right, additional: additional)
        }
        open func visitPrefix(
            _ prefixExpression: AST.Prefix, additional: Any? = nil
        ) -> Any? {
            return visit(prefixExpression.expression, additional: additional)
        }
        open func visitPostfix(
            _ postfixExpression: AST.Postfix, additional: Any? = nil
        ) -> Any? {
            return visit(postfixExpression.expression, additional: additional)
        }
    }
}
