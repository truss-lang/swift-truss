import Testing
import TrussCore
import TrussSemantics

final class CaptureProbe: AST.Visitor {
    var variables: [AST.Variable] = []
    var selfExpressions: [AST.SelfExpression] = []
    var superExpressions: [AST.SuperExpression] = []
    var implicitMembers: [AST.ImplicitMemberAccess] = []
    var closures: [AST.Closure] = []

    override func visitVariable(_ variable: AST.Variable, additional: Any? = nil) -> Any? {
        variables.append(variable)
        return super.visitVariable(variable, additional: additional)
    }

    override func visitSelfExpression(
        _ selfExpression: AST.SelfExpression, additional: Any? = nil
    ) -> Any? {
        selfExpressions.append(selfExpression)
        return super.visitSelfExpression(selfExpression, additional: additional)
    }

    override func visitSuperExpression(
        _ superExpression: AST.SuperExpression, additional: Any? = nil
    ) -> Any? {
        superExpressions.append(superExpression)
        return super.visitSuperExpression(superExpression, additional: additional)
    }

    override func visitImplicitMemberAccess(
        _ implicitMemberAccess: AST.ImplicitMemberAccess, additional: Any? = nil
    ) -> Any? {
        implicitMembers.append(implicitMemberAccess)
        return super.visitImplicitMemberAccess(implicitMemberAccess, additional: additional)
    }

    override func visitClosure(_ closure: AST.Closure, additional: Any? = nil) -> Any? {
        closures.append(closure)
        return super.visitClosure(closure, additional: additional)
    }
}

func captureProbe(_ source: String) -> (Context, AST.Program, CaptureProbe) {
    let (context, program) = resolve(source)
    let probe = CaptureProbe()
    probe.visitProgram(program)
    return (context, program, probe)
}

func variableSymbol(_ name: String, _ probe: CaptureProbe) throws -> Symbol.VariableSymbol {
    let variable = try #require(probe.variables.first { $0.name.value == name })
    return try #require(variable.symbol as? Symbol.VariableSymbol)
}

func methodSelfSymbol(_ program: AST.Program) throws -> Symbol.SelfSymbol {
    let method = try #require(program.statements.compactMap { containerMethod($0) }.first)
    let scope = try #require(method.symbol?.scope)
    let entries = try #require(scope.values["self"])
    return try #require(entries.last as? Symbol.SelfSymbol)
}

func containerMethod(_ statement: AST.Statement) -> AST.FunctionDecl? {
    if let functionDecl = statement as? AST.FunctionDecl {
        return functionDecl
    }
    if let structDecl = statement as? AST.StructDecl {
        return structDecl.body.compactMap { $0 as? AST.FunctionDecl }.first
    }
    if let extensionDecl = statement as? AST.ExtensionDecl {
        return extensionDecl.body.compactMap { $0 as? AST.FunctionDecl }.first
    }
    return nil
}

func diagnosticMessages(_ context: Context) -> [String] {
    context.diagnositicEngine.diagnostics.map(\.message)
}

let selfContextDiagnostic = "'self' is only available in an instance context"

@Test func closureCapturesOuterLocal() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let x = 1
            let g = { x }
        }
        """
    )
    let x = try variableSymbol("x", probe)
    #expect(x.kind == .Free)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.count == 1)
    #expect(closure.freeVariables.first === x)
}

@Test func outerBodyReferenceStaysLocal() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let x = 1
            x
        }
        """
    )
    #expect(try variableSymbol("x", probe).kind == .Local)
    #expect(probe.closures.isEmpty)
}

@Test func globalReferenceStaysGlobalAndIsNotCaptured() throws {
    let (_, _, probe) = captureProbe(
        """
        var g = 1
        func f() {
            let c = { g }
        }
        """
    )
    #expect(try variableSymbol("g", probe).kind == .Global)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.isEmpty)
}

@Test func memberReferenceStaysPropertyAndCapturesSelf() throws {
    let (_, program, probe) = captureProbe(
        """
        struct S {
            var a: Int
            func m() {
                let g = { a }
            }
        }
        """
    )
    let a = try variableSymbol("a", probe)
    #expect(a.kind == .Property)
    let selfSymbol = try methodSelfSymbol(program)
    #expect(selfSymbol.kind == .Free)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.count == 1)
    #expect(closure.freeVariables.first === selfSymbol)
}

@Test func implicitMemberAccessCapturesSelf() throws {
    let (_, program, probe) = captureProbe(
        """
        struct S {
            var a: Int
            func m() {
                let g = { .a }
            }
        }
        """
    )
    #expect(probe.implicitMembers.first?.symbol?.name == "a")
    let selfSymbol = try methodSelfSymbol(program)
    #expect(selfSymbol.kind == .Free)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.contains { $0 === selfSymbol })
}

@Test func extensionMemberReferenceCapturesSelf() throws {
    let (_, program, probe) = captureProbe(
        """
        struct S {
            var a: Int
        }
        extension S {
            func m() {
                let g = { a }
            }
        }
        """
    )
    let selfSymbol = try methodSelfSymbol(program)
    #expect(selfSymbol.kind == .Free)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.contains { $0 === selfSymbol })
}

@Test func nestedFunctionCapturesOuterLocal() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let x = 1
            func inner() { x }
        }
        """
    )
    #expect(try variableSymbol("x", probe).kind == .Free)
}

@Test func nestedClosuresShareTransitiveCapture() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let x = 1
            let g = { { x } }
        }
        """
    )
    try #require(probe.closures.count == 2)
    let x = try variableSymbol("x", probe)
    #expect(probe.closures[0].freeVariables.contains { $0 === x })
    #expect(probe.closures[1].freeVariables.contains { $0 === x })
}

@Test func innerClosureLocalIsNotCapturedByOuterClosure() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let g = {
                let y = 1
                let h = { y }
            }
        }
        """
    )
    try #require(probe.closures.count == 2)
    let y = try variableSymbol("y", probe)
    #expect(probe.closures[0].freeVariables.isEmpty)
    #expect(probe.closures[1].freeVariables.contains { $0 === y })
}

@Test func repeatedCaptureIsDeduplicated() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let x = 1
            let g = {
                x
                x
            }
        }
        """
    )
    let x = try variableSymbol("x", probe)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.count == 1)
    #expect(closure.freeVariables.first === x)
}

@Test func capturesAreSortedBySymbolId() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let a = 1
            let b = 2
            let g = {
                b
                a
            }
        }
        """
    )
    let a = try variableSymbol("a", probe)
    let b = try variableSymbol("b", probe)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.map(\.id.id) == [a.id.id, b.id.id])
}

@Test func closureCapturesSelf() throws {
    let (_, _, probe) = captureProbe(
        """
        struct S {
            var a: Int
            func m() {
                let g = { self.a }
            }
        }
        """
    )
    let selfSymbol = try #require(probe.selfExpressions.first?.symbol)
    #expect(selfSymbol.kind == .Free)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.count == 1)
    #expect(closure.freeVariables.first === selfSymbol)
}

@Test func selfExpressionStaysLocalWithoutClosure() throws {
    let (_, _, probe) = captureProbe(
        """
        struct S {
            var a: Int
            func m() { self }
        }
        """
    )
    let selfSymbol = try #require(probe.selfExpressions.first?.symbol)
    #expect(selfSymbol.kind == .Local)
    #expect(probe.closures.isEmpty)
}

@Test func captureListMarksVariableFree() throws {
    let (_, _, probe) = captureProbe(
        """
        func f() {
            let x = 1
            let g = { [x] in 1 }
        }
        """
    )
    let x = try variableSymbol("x", probe)
    #expect(x.kind == .Free)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.contains { $0 === x })
}

@Test func captureListWeakSelfMarksSelfFree() throws {
    let (_, _, probe) = captureProbe(
        """
        struct S {
            var a: Int
            func m() {
                let g = { [weak self] in 1 }
            }
        }
        """
    )
    let selfSymbol = try #require(probe.selfExpressions.first?.symbol)
    #expect(selfSymbol.kind == .Free)
    let closure = try #require(probe.closures.first)
    #expect(closure.freeVariables.contains { $0 === selfSymbol })
}

@Test func subscriptParameterReferenceStaysLocal() throws {
    let (_, _, probe) = captureProbe(
        """
        struct S {
            subscript(i: Int) -> Int { i }
        }
        """
    )
    #expect(try variableSymbol("i", probe).kind == .Local)
}

@Test func staticSelfIsDiagnosed() throws {
    let (context, _, probe) = captureProbe(
        """
        struct S {
            static func f() { self }
        }
        """
    )
    #expect(probe.selfExpressions.first?.symbol == nil)
    #expect(diagnosticMessages(context) == [selfContextDiagnostic])
}

@Test func topLevelSelfIsDiagnosed() throws {
    let (context, _, probe) = captureProbe("func f() { self }")
    #expect(probe.selfExpressions.first?.symbol == nil)
    #expect(diagnosticMessages(context) == [selfContextDiagnostic])
}

@Test func instanceContextsAreNotDiagnosed() throws {
    let (context, _, probe) = captureProbe(
        """
        struct S {
            var a: Int
            var b: Int {
                get { self }
                set { self }
            }
            func m() { self }
            init() { self }
            subscript(i: Int) -> Int { self }
        }
        """
    )
    try #require(probe.selfExpressions.count == 5)
    #expect(probe.selfExpressions.allSatisfy { $0.symbol?.kind == .Local })
    #expect(diagnosticMessages(context).isEmpty)
}

@Test func superWithoutInstanceContextStaysSilent() throws {
    let (context, _, probe) = captureProbe("func f() { super }")
    #expect(probe.superExpressions.first?.symbol == nil)
    #expect(diagnosticMessages(context).isEmpty)
}
