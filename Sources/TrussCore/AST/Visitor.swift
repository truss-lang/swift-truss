import SwiftAbstract

extension AST {
    @abstractClass
    public class Visitor {
        @abstractInit
        public init() {}
        public func visit(_ node: AST.AstNode, additional: Any? = nil) -> Any? {
            node.accept(self, additional: additional)
        }
        public func visitProgram(_ program: AST.Program, additional: Any? = nil) -> Any? {
            var last: Any? = nil
            for statement in program.statements {
                last = visit(statement, additional: additional)
            }
            return last
        }
        public func visitEmptyStatement(
            _ emptyStatement: AST.EmptyStatement, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitErrorStatement(
            _ errorStatement: AST.ErrorStatement, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitExpressionStatement(
            _ expressionStatement: AST.ExpressionStatement, additional: Any? = nil
        ) -> Any? {
            visit(expressionStatement.expression, additional: additional)
        }
        public func visitReturn(
            _ ret: AST.Return, additional: Any? = nil
        ) -> Any? {
            if let value = ret.value {
                visit(value, additional: additional)
            } else {
                nil
            }
        }
        public func visitFunctionDecl(
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
        public func visitVariableDecl(
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
        public func visitErrorExpression(
            _ errorExpression: AST.ErrorExpression, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
            return nil
        }
        public func visitGenericApplication(
            _ genericApplication: AST.GenericApplication, additional: Any? = nil
        ) -> Any? {
            let _ = visit(genericApplication.base, additional: additional)
            for genericArgument in genericApplication.genericArguments {
                let _ = visit(genericArgument, additional: additional)
            }
            return nil
        }
        public func visitIntegerLiteral(
            _ integerLiteral: AST.IntegerLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitFloatLiteral(
            _ floatLiteral: AST.FloatLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitStringLiteral(
            _ stringLiteral: AST.StringLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitCharLiteral(
            _ charLiteral: AST.CharLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitBoolLiteral(
            _ boolLiteral: AST.BoolLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitNullLiteral(
            _ nullLiteral: AST.NullLiteral, additional: Any? = nil
        ) -> Any? {
            return nil
        }
        public func visitCall(
            _ call: AST.Call, additional: Any? = nil
        ) -> Any? {
            let _ = visit(call.callee, additional: additional)
            for argument in call.arguments {
                let _ = visit(argument, additional: additional)
            }
            return nil
        }
        public func visitMemberAccess(
            _ memberAccess: AST.MemberAccess, additional: Any? = nil
        ) -> Any? {
            return visit(memberAccess.object, additional: additional)
        }
        public func visitInfix(
            _ infixExpression: AST.Infix, additional: Any? = nil
        ) -> Any? {
            var last: Any? = nil
            for operand in infixExpression.operands {
                last = visit(operand, additional: additional)
            }
            return last
        }
        public func visitBinary(
            _ binary: AST.Binary, additional: Any? = nil
        ) -> Any? {
            let _ = visit(binary.left, additional: additional)
            return visit(binary.right, additional: additional)
        }
        public func visitPrefix(
            _ prefixExpression: AST.Prefix, additional: Any? = nil
        ) -> Any? {
            return visit(prefixExpression.expression, additional: additional)
        }
        public func visitPostfix(
            _ postfixExpression: AST.Postfix, additional: Any? = nil
        ) -> Any? {
            return visit(postfixExpression.expression, additional: additional)
        }
    }
}
