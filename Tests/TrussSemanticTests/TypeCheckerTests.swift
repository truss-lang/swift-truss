import Testing
import TrussCore
import TrussSemantics

private let pointerPrelude = """
struct Int {}
struct Bool {}

precedencegroup Add { associativity: left }
infix operator +: Add
infix operator -: Add
precedencegroup Cmp { associativity: none }
infix operator ==: Cmp
infix operator !=: Cmp
infix operator <: Cmp
infix operator <=: Cmp
infix operator >: Cmp
infix operator >=: Cmp
precedencegroup Assignment { assignment: true }
infix operator =: Assignment
"""

@Test
func variableAnnotationType() throws {
    let (context, programs) = runTypeChecker(["struct S {}\nlet x: S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let symbol = try #require(variableDecl.symbol)
    let type = try #require(symbol.type)
    #expect(type is TrussType.StructType)
    let typeId = try #require((programs[0].statements[0] as! AST.StructDecl).symbol?.typeId)
    #expect(type as AnyObject === context.typeTable[typeId] as AnyObject)
}

@Test
func noAnnotationLeavesTypeNil() {
    let (_, programs) = runTypeChecker(["let x"])
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type == nil)
}

@Test
func noBuiltinTypeIsErrorType() {
    let (context, programs) = runTypeChecker(["let x: Int32"])
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ErrorType)
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int32'"))
}

@Test
func moduleMemberTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(["module M {\n    struct A {}\n}\nlet x: M.A"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "A")
}

@Test
func nestedTypeAnnotation() throws {
    let (_, programs) = runTypeChecker([
        "struct Outer {\n    struct Inner {}\n}\nlet x: Outer.Inner",
    ])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "Inner")
}

@Test
func builtinTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(["let x: Builtin.Int64"], installBuiltin: true)
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int64")
}

@Test
func builtinUnqualifiedNameStillErrors() throws {
    let (context, programs) = runTypeChecker(["let x: Int64"], installBuiltin: true)
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ErrorType)
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int64'"))
}

@Test
func structWrappingBuiltinStorage() throws {
    let (_, programs) = runTypeChecker(
        ["struct Int {\n    var value: Builtin.Int64\n}"], installBuiltin: true
    )
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let member = try #require(structDecl.body.first as? AST.VariableDecl)
    let type = try #require(member.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int64")
}

@Test
func optionalAnnotation() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet x: S?"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let optional = try #require(variableDecl.symbol?.type as? TrussType.GenericInstantiation)
    #expect(optional.base.name == "Optional")
    #expect(optional.arguments.first is TrussType.StructType)
}

@Test
func tupleAnnotationWithLabels() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nstruct T {}\nlet x: (a: S, T)"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let tuple = try #require(variableDecl.symbol?.type as? TrussType.TupleType)
    #expect(tuple.elements.count == 2)
    #expect(tuple.elements[0].label == "a")
    #expect(tuple.elements[0].type is TrussType.StructType)
    #expect(tuple.elements[1].label == nil)
}

@Test
func closureTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f: (S) async throws -> S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let closure = try #require(variableDecl.symbol?.type as? TrussType.ClosureType)
    #expect(closure.parameters.count == 1)
    #expect(closure.isAsync)
    #expect(closure.isThrowing)
    #expect(closure.returnType is TrussType.StructType)
}

@Test
func functionTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f: func(x: S) async throws -> S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let function = try #require(variableDecl.symbol?.type as? TrussType.FunctionType)
    #expect(function.parameters.count == 1)
    #expect(function.parameters[0].label == "x")
    #expect(function.isAsync)
    #expect(function.isThrowing)
    #expect(function.returnType is TrussType.StructType)
    #expect(!(variableDecl.symbol?.type is TrussType.ClosureType))
}

@Test
func declaredFunctionType() throws {
    let (_, programs) = runTypeChecker([
        """
        struct S {}
        func f(a: S, b: S?) -> S {
        }
        """,
    ])
    let functionDecl = programs[0].statements[1] as! AST.FunctionDecl
    let symbol = try #require(functionDecl.symbol)
    let functionType = try #require(symbol.functionType)
    #expect(functionType.parameters.count == 2)
    #expect(functionType.parameters[0].label == "a")
    #expect(functionType.parameters[0].type is TrussType.StructType)
    let optional = try #require(
        functionType.parameters[1].type as? TrussType.GenericInstantiation
    )
    #expect(optional.base.name == "Optional")
    #expect(optional.arguments.first is TrussType.StructType)
    #expect(functionType.returnType is TrussType.StructType)
    let paramSymbol = try #require(symbol.scope.values["a"]?.first as? Symbol.VariableSymbol)
    #expect(paramSymbol.type is TrussType.StructType)
}

@Test
func noReturnAnnotationDefaultsVoid() throws {
    let (_, programs) = runTypeChecker(["func f() {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.returnType is TrussType.VoidType)
}

@Test
func unresolvableReturnAnnotationIsErrorType() throws {
    let (context, programs) = runTypeChecker(["func f() -> Int32 {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.returnType is TrussType.ErrorType)
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int32'"))
}

@Test
func initFunctionTypeReturnsNominal() throws {
    let (_, programs) = runTypeChecker(["struct S {\n    init(x: S) {\n    }\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let initDecl = try #require(structDecl.body.first as? AST.InitDecl)
    let functionType = try #require(initDecl.symbol?.functionType)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.returnType is TrussType.StructType)
}

@Test
func throwsClauseRecordsThrownTypes() throws {
    let (_, programs) = runTypeChecker([
        "struct E1 {}\nstruct E2 {}\nfunc f() throws(E1, E2) {}",
    ])
    let functionDecl = programs[0].statements[2] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.isThrowing)
    #expect(functionType.throwsTypes.count == 2)
    #expect((functionType.throwsTypes[0] as! TrussType.StructType).name == "E1")
    #expect((functionType.throwsTypes[1] as! TrussType.StructType).name == "E2")
}

@Test
func plainThrowsHasNoThrownTypes() throws {
    let (_, programs) = runTypeChecker(["func f() throws {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.isThrowing)
    #expect(functionType.throwsTypes.isEmpty)
}

@Test
func nonThrowingFunctionHasEmptyThrows() throws {
    let (_, programs) = runTypeChecker(["func f() {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(!functionType.isThrowing)
    #expect(functionType.throwsTypes.isEmpty)
}

@Test
func subscriptFunctionTypeReturnsElement() throws {
    let (_, programs) = runTypeChecker(["struct S {\n    subscript(i: S) -> S {\n    }\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let subscriptDecl = try #require(structDecl.body.first as? AST.SubscriptDecl)
    let functionType = try #require(subscriptDecl.symbol?.getter.functionType)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.returnType is TrussType.StructType)
}

@Test
func typealiasTargetType() throws {
    let (context, programs) = runTypeChecker(["struct S {}\ntypealias T = S"])
    let typeAliasDecl = programs[0].statements[1] as! AST.TypeAliasDecl
    let symbol = try #require(typeAliasDecl.symbol)
    let target = try #require(symbol.targetType)
    let typeId = try #require((programs[0].statements[0] as! AST.StructDecl).symbol?.typeId)
    #expect(target as AnyObject === context.typeTable[typeId] as AnyObject)
}

@Test
func typealiasChainDereferences() throws {
    let (_, programs) = runTypeChecker(["struct S {}\ntypealias T = S\ntypealias U = T\nlet x: U"])
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "S")
}

@Test
func typealiasCycleIsErrorType() {
    let (context, programs) = runTypeChecker(["typealias A = B\ntypealias B = A\nlet x: A"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ErrorType)
    let aSymbol = (programs[0].statements[0] as! AST.TypeAliasDecl).symbol
    let bSymbol = (programs[0].statements[1] as! AST.TypeAliasDecl).symbol
    #expect(aSymbol?.targetType is TrussType.ErrorType)
    #expect(bSymbol?.targetType is TrussType.ErrorType)
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("circular reference to typealias 'A'"))
}

@Test
func closureLiteralFunctionType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet cl = { (x: S) -> S in x }"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let closure = try #require(variableDecl.initializer as? AST.Closure)
    let closureType = try #require(closure.ty as? TrussType.ClosureType)
    #expect(closureType.parameters.count == 1)
    #expect(closureType.parameters[0].type is TrussType.StructType)
    #expect(closureType.returnType is TrussType.StructType)
}

@Test
func variadicParameterType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nfunc f(xs: S...) {}"])
    let functionDecl = programs[0].statements[1] as! AST.FunctionDecl
    let symbol = try #require(functionDecl.symbol)
    let variadic = try #require(
        symbol.functionType?.parameters.first?.type as? TrussType.VariadicType
    )
    #expect(variadic.base is TrussType.StructType)
}

@Test
func compositionAnnotation() throws {
    let (_, programs) = runTypeChecker(["protocol P {}\nprotocol Q {}\nlet x: P & Q"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let composition = try #require(variableDecl.symbol?.type as? TrussType.CompositionType)
    #expect(composition.members.count == 2)
    #expect(composition.members[0] is TrussType.ProtocolType)
}

@Test
func enumAssociatedValueType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nenum E {\n    case a(x: S)\n}"])
    let enumDecl = programs[0].statements[1] as! AST.EnumDecl
    let caseDecl = try #require(enumDecl.body.first as? AST.EnumCaseDecl)
    let typeExpression = caseDecl.elements[0].associatedValues[0].typeExpression
    #expect(typeExpression.ty is TrussType.StructType)
}

@Test
func castExpressionTypeIsTarget() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet x = y as S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let cast = try #require(variableDecl.initializer as? AST.Cast)
    #expect(cast.right.ty is TrussType.StructType)
    #expect(cast.ty is TrussType.StructType)
}

@Test
func callReturnTypeResolved() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nfunc f() -> S {}\nlet x: S = f()"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(call.ty is TrussType.StructType)
}

@Test
func variableReferencePropagates() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet x: S\nlet y = x"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let variable = try #require(variableDecl.initializer as? AST.Variable)
    #expect(variable.ty is TrussType.StructType)
}

@Test
func voidNeverAnnotations() throws {
    let (_, programs) = runTypeChecker(["let x: Void\nlet y: Never"])
    let voidDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(voidDecl.symbol?.type is TrussType.VoidType)
    let neverDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(neverDecl.symbol?.type is TrussType.NeverType)
}

@Test
func matchingAssignmentPasses() {
    let (
        context,
        programs
    ) =
        runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: S = s"])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test
func mismatchedAssignmentReportsError() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            ["struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet x: S = t"]
        )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test
func optionalPromotion() {
    let (
        context,
        _
    ) = runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: S? = s"])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func subclassAssignment() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            [
                "class Base { init() {} }\nclass Derived: Base { init() {} }\nfunc makeDerived() -> Derived { Derived() }\nlet d = makeDerived()\nlet b: Base = d",
            ]
        )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func neverConvertsToAnyType() {
    let (
        context,
        _
    ) =
        runTypeChecker(["struct S { init() {} }\nfunc makeNever() -> Never { }\nlet n = makeNever()\nlet x: S = n"])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func conformancePromotion() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: P = s"]
        )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func conformanceMismatchReportsError() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            ["protocol P {}\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet x: P = t"]
        )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'P', found 'T'"))
}

@Test
func overloadResolutionByExpectedReturn() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { S() }\nfunc f() -> T { T() }\nlet x: S = f()",
            ]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(AST.Expression.resolvedFunctionSymbol(of: call.callee)?.name == "f")
}

@Test
func overloadNoMatchReportsError() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nstruct U { init() {} }\nfunc f(x: S) {}\nfunc f(x: T) {}\nfunc makeU() -> U { U() }\nfunc main() { f(makeU()) }",
            ]
        )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("no exact matches in call to 'f'") }))
}

@Test
func overloadAmbiguousReportsError() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { S() }\nfunc f() -> T { T() }\nlet g = f()",
            ]
        )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("ambiguous use of 'f'") }))
}

@Test
func genericFunctionTypeIsForall() throws {
    let (_, programs) = runTypeChecker(["struct S { init() {} }\nfunc id<T>(x: T) -> T { x }"])
    let functionDecl = programs[0].statements[1] as! AST.FunctionDecl
    let forall = try #require(functionDecl.symbol?.forallType)
    #expect(forall.parameters.count == 1)
    #expect(forall.parameters[0].name == "T")
    #expect(forall.body is TrussType.FunctionType)
}

@Test
func genericFunctionImplicitInstantiation() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id(x: s)",
            ]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test
func genericFunctionExplicitInstantiation() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id<S>(x: s)",
            ]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test
func genericStructMember() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct Box<T> { init(v: T) {} var value: T }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet b = Box(v: s)\nlet v = b.value",
            ]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[5] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test
func closureParameterFromExpectedType() throws {
    let (context, programs) = runTypeChecker(["struct S { init() {} }\nlet f: (S) -> S = { x in x }"])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let closureType = try #require(variableDecl.symbol?.type as? TrussType.ClosureType)
    #expect(closureType.parameters.count == 1)
    #expect(closureType.parameters[0].type is TrussType.StructType)
    #expect(closureType.returnType is TrussType.StructType)
    let closure = try #require(variableDecl.initializer as? AST.Closure)
    #expect(closure.ty is TrussType.ClosureType)
}

@Test
func closureWithoutContextReportsError() {
    let (context, _) = runTypeChecker(["struct S { init() {} }\nlet f = { x in x }"])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("requires an explicit type annotation") }))
}

@Test
func memberAccessOnInstance() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(["struct S { init() {} var x: S }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet y = s.x"])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test
func optionalChainingMemberAccess() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            ["struct S { init() {} var x: S }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet z: S? = s\nlet w = z?.x"]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let optional = try #require(variableDecl.symbol?.type as? TrussType.GenericInstantiation)
    #expect(optional.base.name == "Optional")
    #expect(optional.arguments.first is TrussType.StructType)
}

@Test
func ifElseJoinProducesBranchType() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            ["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = if true { s } else { s }"]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test
func ifElseMismatchedBranchesReportError() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc makeS() -> S { S() }\nfunc makeT() -> T { T() }\nlet s = makeS()\nlet t = makeT()\nlet x = if true { s } else { t }",
            ]
        )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func ifWithoutElseIsVoid() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = if true { s }"])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.VoidType)
}

@Test
func literalAdaptsToAnyAnnotation() {
    let (context, _) = runTypeChecker(["struct S { init() {} }\nlet x: S = 1"])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func functionReturnTypeChecked() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nfunc f() -> S { return t }",
            ]
        )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test
func voidFunctionCannotReturnValue() {
    let (
        context,
        _
    ) =
        runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nfunc f() { return s }"])
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func someTypeProducesVariableWithConstraint() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: some P = s"]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let variable = try #require(variableDecl.symbol?.type as? TrussType.TypeVariableType)
    #expect(variable.binding is TrussType.StructType)
}

@Test
func someTypeOnFunctionReturn() {
    let (
        context,
        _
    ) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nfunc f() -> some P { makeS() }"]
        )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func anyTypeDereferencesToProtocol() throws {
    let (
        context,
        programs
    ) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: any P = s"]
        )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = try #require(programs[0].statements[4] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.ProtocolType)
}

@Test
func someTypeDereferencesToProtocolOnAnnotation() throws {
    let (_, programs) = runTypeChecker(["protocol P {}\nlet x: any P"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ProtocolType)
}

@Test
func tupleElementsCheckedAgainstExpected() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }\nfunc makeS() -> S { S() }\nfunc makeT() -> T { T() }\nlet s = makeS()\nlet t = makeT()\nlet x: (S, S) = (s, t)",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test
func closureReturnTypeChecked() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet f: () -> S = { () in t }",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test
func missingMemberReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = s.unknown"]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("type 'S' has no member 'unknown'"))
}

@Test
func undefinedVariableReportsError() {
    let (context, _) = runTypeChecker(["let x = unknown"])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find 'unknown' in this scope"))
}

@Test
func sequentialExpressionReportsUnknownOperator() {
    let (context, _) = runTypeChecker(["func main() { 1 + 2 }"])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("operator '+' has no function declaration"))
}

@Test
func wrongTypeArgumentCountReportsError() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id<S, S>(s)",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("wrong number of type arguments: expected 1, got 2"))
}

@Test
func tryExpressionPassesThrough() throws {
    let (context, programs) = runTypeChecker(
        ["struct S { init() {} }\nfunc f() throws -> S { S() }\nfunc main() { let x = try f() }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let functionDecl = try #require(programs[0].statements[2] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test
func shorthandArgumentTypeFromExpected() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc main() { let f: (S) -> S = { $0 } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func selfKeywordTypeIsEnclosing() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func f() -> S { Self } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func keyPathExpressionInferred() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S }\nfunc main() { let kp = \\S.x }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func keyPathWithoutRootReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S }\nfunc main() { let kp = \\.x }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func voidLiteralType() throws {
    let (_, programs) = runTypeChecker(["func main() { let x = () }"])
    let functionDecl = try #require(programs[0].statements[0] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.VoidType)
}

@Test
func genericApplicationValueType() throws {
    let (context, programs) = runTypeChecker(
        ["struct Box<T> { init() {} }\nstruct S { init() {} }\nfunc main() { let b = Box<S> }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let functionDecl = try #require(programs[0].statements[2] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.GenericInstantiation)
}

@Test
func genericFunctionConstraintViolationReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nfunc f<T: P>(x: T) {}\nfunc main() { f(x: S()) }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func genericFunctionConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S: P { init() {} }\nfunc f<T: P>(x: T) {}\nfunc main() { f(x: S()) }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericTypeArgumentConstraintViolationReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S {}\nstruct Box<T: P> { init() {} }\nlet b: Box<S>"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func genericTypeArgumentConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S: P {}\nstruct Box<T: P> { init() {} }\nlet b: Box<S>"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericTypeWhereClauseConstraintChecked() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S {}\nstruct Box<T> where T: P { init() {} }\nlet b: Box<S>"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func genericParameterBodyMemberAccess() {
    let (context, _) = runTypeChecker(
        [
            "protocol P { func pm() }\nstruct S: P { init() {} func pm() {} }",
            "func f<T: P>(x: T) { x.pm() }\nfunc main() { f(x: S()) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericParameterConformsToDeclaredProtocol() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nprotocol Q {}\nfunc f<T: P>(x: T) { let y: P = x }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericParameterViolatesOtherProtocol() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nprotocol Q {}\nfunc f<T: P>(x: T) { let y: Q = x }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func genericTypeEqualityConstraintChecked() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nstruct T {}\nstruct W<A, B> where A == B { init() {} }\nlet w: W<S, T>"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func genericTypeEqualityConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nstruct W<A, B> where A == B { init() {} }\nlet w: W<S, S>"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericParameterCompositionConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P, Q { init() {} }",
            "func f<T: P & Q>(x: T) {}\nfunc main() { f(x: S()) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericParameterCompositionConstraintViolated() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P { init() {} }",
            "func f<T: P & Q>(x: T) {}\nfunc main() { f(x: S()) }",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func multipleGenericParameterConstraints() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P { init() {} }\nstruct T: Q { init() {} }",
            "func f<A: P, B: Q>(x: A, y: B) {}\nfunc main() { f(x: S(), y: T()) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericConstraintViolationKeepsNonGenericOverload() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nstruct S { init() {} }\nstruct T: P { init() {} }",
            "func f<A: P>(x: A) -> A { x }\nfunc f(x: S) -> S { x }",
            "func main() { let a = f(x: S()); let b = f(x: T()) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func nestedGenericInstantiationConstraintChecked() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nstruct S: P { init() {} }\nstruct T { init() {} }",
            "struct Box<A: P> { init() {} }",
            "let good: Box<Box<S>>\nlet bad: Box<Box<T>>",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func genericBodyReturnsParameter() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nstruct S: P { init() {} }",
            "func f<T: P>(x: T) -> T { x }",
            "func main() { let a = f(x: S()) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func forwardModuleFunctionCallMatches() {
    let (context, _) = runTypeChecker(
        ["func f() { M.g() }\nmodule M { func g() {} }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func matchEnumCaseMatches() {
    let (context, _) = runTypeChecker(
        ["enum E { case a; case b }\nfunc f(e: E) { match e { .a => { 1 } .b => { 2 } } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func matchPatternResolvesCaseSymbol() throws {
    let (_, programs) = runTypeChecker(
        ["enum E { case a; case b }\nfunc f(e: E) { match e { .a => { 1 } .b => { 2 } } }"]
    )
    let functionDecl = try #require(programs[0].statements[1] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let statement = try #require(statements[0] as? AST.ExpressionStatement)
    let matchExpression = try #require(statement.expression as? AST.Match)
    let pattern = try #require(matchExpression.cases[0].patterns[0] as? AST.ImplicitMemberAccess)
    let symbol = try #require(pattern.symbol)
    #expect(symbol is Symbol.CaseSymbol)
    #expect(symbol.name == "a")
}

@Test
func matchUnknownCaseReportsError() { let (context, _) = runTypeChecker(
    ["enum E { case a }\nfunc f(e: E) { match e { .c => 1 } }"]
)
#expect(context.diagnosticEngine.hasErrors)
}

@Test
func matchAssociatedValueBindsPatternType() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nenum R { case ok(S) }\nfunc f(r: R) { match r { .ok(let x) => x } }"]
    )
    let functionDecl = try #require(programs[0].statements[2] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let expressionStatement = try #require(statements[0] as? AST.ExpressionStatement)
    let matchExpression = try #require(expressionStatement.expression as? AST.Match)
    let call = try #require(matchExpression.cases[0].patterns[0] as? AST.Call)
    let binding = try #require(call.arguments[0].value as? AST.BindingPattern)
    let bodyStatement = try #require(matchExpression.cases[0].body[0] as? AST.ExpressionStatement)
    let variable = try #require(bodyStatement.expression as? AST.Variable)
    let symbol = try #require(variable.symbol as? Symbol.VariableSymbol)
    #expect(symbol.type is TrussType.StructType)
}

@Test
func matchAssociatedValueCountMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum R { case ok(S) }\nfunc f(r: R) { match r { .ok() => 1 } }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func matchNonEnumSubjectReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { match s { .a => 1 } }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func matchImplicitMemberExpressionReportsError() {
    let (context, _) = runTypeChecker(
        ["enum E { case a, b }\nfunc f(e: E) -> E { match e { .a => .b } }"]
    )
    let errors = context.diagnosticEngine.diagnostics.filter { $0.severity == .error }
    #expect(
        errors.contains {
            $0.message == "cannot infer type of implicit member access '.b'"
        }
    )
}

@Test
func ifCaseEnumMatches() {
    let (context, _) = runTypeChecker(
        ["enum E { case a }\nfunc f(e: E) { if case .a = e {} }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func ifCaseNonEnumSubjectReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { if case .a = s {} }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func caseBindingTypeAnnotationChecked() {
    let (context, _) = runTypeChecker(
        [
            "enum E { case a }\nstruct S { init() {} }\nstruct T { init() {} }",
            "func f(e: E, t: T) { if case let x: T = e { x } }",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func forCasePatternChecked() {
    let (context, _) = runTypeChecker(
        ["enum E { case a }\nfunc f(es: E) { for case .a in es {} }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func enumRawValueMatchesRawType() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E: S { case a = s }\nlet s = S()"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func enumRawValueMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nenum E: S { case a = t }\nlet t = T()"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func throwMatchesThrowsTypes() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) { throw E1() }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func throwMismatchReportsError() {
    let (context, _) = runTypeChecker(
        [
            "struct E1 { init() {} }\nstruct E2 { init() {} }",
            "func f() throws(E1) { throw E2() }",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func throwInNonThrowingFunctionReportsError() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() { throw E1() }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func doCatchPatternAndWhereChecked() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) { do { throw E1() } catch let e where true { () } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func optionalChainingOnNonOptionalReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S }\nlet s = S()\nlet w = s?.x"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func setterAccessorDoesNotCheckReturnType() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S { get { S() } set { () } } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func genericInitDeclaredAsForall() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct Box<T> { init() {} }\nlet b = Box<S>()"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func nonGenericOverloadPreferredOverGeneric() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nfunc f<T>(x: T) -> T { x }\nfunc f(x: S) -> S { x }\nfunc main() { let a = f(x: S()) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func nestedTypeGenericApplication() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nlet b: Outer.Inner<S>"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func throwingCallWithoutTryReportsError() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) {}\nfunc main() { f() }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func throwingCallWithTryPasses() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) {}\nfunc main() { try f() }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func forInBindingPatternResolvedInBody() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { for let x in s { x } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func forBodyLocalScope() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { for x in s { let y = x; y } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func localLetWithoutInitializerReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f() { let x: S }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func localVarWithoutInitializerAllowed() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f() { var x: S }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func topLevelLetWithoutInitializerAllowed() {
    let (context, _) = runTypeChecker(["struct S { init() {} }\nlet x: S"])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func multiGenericOverloadConstraintSelection() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P { init() {} }\nstruct T: Q { init() {} }",
            "func f<A: P>(x: A) -> A { x }\nfunc f<B: Q>(x: B) -> B { x }",
            "func main() { let t = T(); let r = f(x: t) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func missingProtocolWitnessReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P { func pm() }\nstruct S: P { init() {} }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func implementedProtocolWitnessPasses() {
    let (context, _) = runTypeChecker(
        ["protocol P { func pm() }\nstruct S: P { init() {} func pm() {} }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func inheritedProtocolWitnessChecked() {
    let (context, _) = runTypeChecker(
        ["protocol P1 { func pm() }\nprotocol P2: P1 {}\nstruct S: P2 { init() {} }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func superclassProvidesWitness() {
    let (context, _) = runTypeChecker(
        [
            "protocol P { func pm() }\nclass B: P { init() {} func pm() {} }",
            "class C: B, P { init() {} }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func missingAssociatedTypeWitnessReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nprotocol P { associatedtype T }\nstruct C: P { init() {} }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func associatedTypeWitnessViaTypealias() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nprotocol P { associatedtype T }\nstruct C: P { init() {} typealias T = S }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func instanceMethodCallResolved() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func pm() -> S { self } }\nfunc f(s: S) { let a = s.pm() }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func instanceMethodCallWithArguments() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func pm(a: S, b: S) -> S { a } }\nfunc f(s: S) { let r = s.pm(a: s, b: s) }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func instanceMethodCallThroughOptionalChain() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func pm() -> S { self } }\nfunc f(z: S?) { let a = z?.pm() }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func instanceMethodOverloadResolution() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }",
            "struct R { init() {} func f(x: S) -> S { x } func f(x: T) -> T { x } }",
            "func g(r: R, s: S) { let a = r.f(x: s) }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func rawValueWithoutRawTypeReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nenum E: P { case a = s }\nlet s = S()"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func rawValueWithTypeInComposition() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nenum E: P & S { case a = s }\nlet s = S()"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func rawValueWithProtocolOnlyCompositionReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P1 {}\nprotocol P2 {}\nstruct S { init() {} }\nenum E: P1 & P2 { case a = s }\nlet s = S()"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func mixedCompositionWithGenericMember() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nstruct W<T> { init() {} }\nlet x: W<S> & P"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func nestedEnumWithoutRawTypeDoesNotLeakOuter() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum A: S { enum B { case x = s } case y = s }\nlet s = S()"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func nestedEnumWithOwnRawTypes() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum A: S { enum B: S { case x = s } case y = s }\nlet s = S()"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func valueBitAndNotFoldedAsComposition() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(a: S, b: S) { let c = a & b }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func valueBitAndWithDeclaredOperator() {
    let (context, _) = runTypeChecker(
        [
            "precedencegroup G {}\ninfix operator &: G",
            "struct S { init() {} }\nfunc &(lhs: S, rhs: S) -> S { lhs }",
            "func f(a: S, b: S) { let c = a & b }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func tryQuestionWrapsResultInOptional() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nstruct E1 { init() {} }\nfunc f() throws(E1) -> S { S() }\nlet x = try? f()"]
    )
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as? TrussType.GenericInstantiation)?.base.name == "Optional")
}

@Test
func tryExclamationKeepsPlainType() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nstruct E1 { init() {} }\nfunc f() throws(E1) -> S { S() }\nlet x = try! f()"]
    )
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.StructType)
}

@Test
func nestedTypeGenericInitCall() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nfunc main() { let b = Outer.Inner<S>() }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func nestedTypeGenericInitWithMultipleArguments() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }\nstruct Outer { struct Inner<A, B> { init() {} } }\nfunc main() { let b = Outer.Inner<S, T>() }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func nestedTypeAsGenericArgument() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct W<T> { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nlet x: W<Outer.Inner<S>>",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func nestedTypeGenericArgumentOnValuePosition() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct W<T> { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nlet x = W<Outer.Inner<S>>",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func castInstanceToProtocolConforms() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S: P { init() {} }\nfunc main() { let s = S(); let x = s as P }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func castInstanceToUnrelatedTypeReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nfunc main() { let s = S(); let x = s as T }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func castInstanceToCompositionConforms() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nprotocol Q {}\nstruct S: P, Q { init() {} }\nfunc main() { let s = S(); let x = s as P & Q }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func bitCastAcceptsUnrelatedTypes() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nlet s = S()\nlet x = s as!! T"]
    )
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let cast = try #require(variableDecl.initializer as? AST.Cast)
    #expect(cast.kind == .AsBitCast)
    #expect(cast.ty is TrussType.StructType)
}

@Test
func forceUnwrapOptional() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nfunc f(z: S?) -> T { let x = z!; return T() }"]
    )
    let functionDecl = programs[0].statements[2] as! AST.FunctionDecl
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    let forceUnwrap = try #require(variableDecl.initializer as? AST.ForceUnwrap)
    #expect(forceUnwrap.ty is TrussType.StructType)
}

@Test
func forceUnwrapNonOptionalReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { let x = s! }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func catchMatchesSecondThrowsType() {
    let (context, _) = runTypeChecker(
        ["struct E1 {}\nstruct E2 {}\nfunc f() throws(E1, E2) {}\nfunc g() { do { try f() } catch E2 { } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func catchMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["struct E1 {}\nstruct E2 {}\nstruct T {}\nfunc f() throws(E1, E2) {}\nfunc g() { do { try f() } catch T { } }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func catchMatchesFirstThrowsType() {
    let (context, _) = runTypeChecker(
        ["struct E1 {}\nstruct E2 {}\nfunc f() throws(E1, E2) {}\nfunc g() { do { try f() } catch E1 { } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func matchVariableCalleeCasePattern() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E { case foo(S) }\nfunc f(e: E) { match e { foo(let x) => { x } } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func matchBareCaseNamePattern() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E { case foo(S) }\nfunc f(e: E) { match e { foo(let x) => { x } } }"]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func matchBareCaseNameArgumentCountChecked() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E { case foo(S) }\nfunc f(e: E) { match e { foo() => { S() } } }"]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func assignmentDoesNotRequireOperatorFunction() {
    let (context, _) = runTypeChecker(
        [
            "precedencegroup Assignment { assignment: true }\ninfix operator =: Assignment\nstruct TT { init() {} }\nstruct TS { var x: TT = TT() var y: TT = TT() init() {} }\nfunc f(s: TS) -> TT { s.y = TT() return s.x }",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func assignmentMismatchReportsExpectedFound() {
    let (context, _) = runTypeChecker(
        [
            "precedencegroup Assignment { assignment: true }\ninfix operator =: Assignment\nstruct TT { init() {} }\nstruct UU { init() {} }\nstruct TS { var y: TT = TT() init() {} }\nfunc f(s: TS, u: UU) { s.y = u }",
        ]
    )
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'TT', found 'UU'"))
}

@Test
func implicitReturnTypeChecked() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { T() }"]
    )
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("expected 'S'") })
}

@Test
func pointerTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(
        ["struct Int {} \nlet p: Int*"]
    )
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type as? TrussType.PointerType)
    #expect(type.pointee is TrussType.StructType)
    #expect(!type.isNonnull)
}

@Test
func nonnullPointerTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(
        ["struct Int {} \nlet p: Int*!"]
    )
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type as? TrussType.PointerType)
    #expect(type.pointee is TrussType.StructType)
    #expect(type.isNonnull)
}

@Test
func nullptrRejectsNonnullPointer() {
    let (context, _) = runTypeChecker(
        [
            "struct Int {} \n"
                + "func f() {\n    var n: Int*! = nullptr\n}",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("nullptr cannot be used with non-null pointer type") })
    #expect(!messages.contains { $0.hasPrefix("expected 'Int*!'") })
}

@Test
func nullptrRequiresPointerType() {
    let (context, _) = runTypeChecker(
        [
            "struct Int {} \n"
                + "func f() {\n    var x: Int = nullptr\n}",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("nullptr requires a pointer type") })
}

@Test
func nonnullPointerAcceptsNullableAssignment() {
    let (context, _) = runTypeChecker(
        [
            "struct Int {} \n"
                + "func f() {\n    var v: Int\n"
                + "    var p: Int*! = &v\n"
                + "    var q: Int* = p\n}",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func placementNewRequiresVoidPointer() {
    let (context, _) = runFullChecks(
        [
            "struct P {}\nstruct S {\n    init() {}\n}\n"
                + "func f(p: P*) {\n    S() in p\n}",
        ]
    )
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("expected 'Void*'") })
}

@Test
func placementNewAcceptsVoidPointer() {
    let (context, _) = runFullChecks(
        [
            "struct S {\n    init() {}\n}\n"
                + "func f(p: Void*) {\n    S() in p\n}",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func pointerDereferenceAndMember() {
    let (context, _) = runTypeChecker(
        [
            pointerPrelude
                + "struct Point {\n    var x: Int\n    var y: Int\n}\n"
                + "func f() {\n    var pt: Point\n    var pp: Point* = &pt\n"
                + "    var a = (*pp).x\n    var b = *pp\n    var i = pp[0]\n"
                + "    if pp != nullptr {\n        var c = (*pp).y\n    }\n"
                + "    var nn: Point*! = pp!\n}",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func dereferenceNonPointerReportsError() {
    let (context, _) = runTypeChecker(
        [
            "struct Int {} \n"
                + "func f() {\n    var v: Int\n    var x = *v\n}",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("cannot dereference non-pointer type") })
}

@Test
func pointerArithmeticAndComparison() {
    let (context, _) = runTypeChecker(
        [
            pointerPrelude
                + "func f() {\n    var v: Int\n    var p: Int* = &v\n"
                + "    var s = p + 1\n    var d = (p + 2) - p\n"
                + "    var eq = p == p\n    var lt = p < p\n}",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func pointerArithmeticRequiresDeclaredOperator() {
    let (context, _) = runTypeChecker(
        [
            "struct Int {} \n"
                + "func f() {\n    var v: Int\n    var p: Int* = &v\n    var x = p + p\n}",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("unknown operator '+'") })
}

@Test
func useBeforeDefinitionInInitInfersType() throws {
    let (_, programs) = runTypeChecker([
        "struct Int32 { init() {} }\n"
            + "struct S {\n    var x: Int32\n"
            + "    init() {\n        let y = b\n        let b: Int32 = Int32()\n    }\n}",
    ])
    let structDecl = try #require(programs[0].statements[1] as? AST.StructDecl)
    let initDecl = try #require(structDecl.body[1] as? AST.InitDecl)
    let yDecl = try #require(initDecl.body[0] as? AST.VariableDecl)
    let yType = try #require(yDecl.symbol?.type)
    #expect(yType is TrussType.StructType)
    let bDecl = try #require(initDecl.body[1] as? AST.VariableDecl)
    let bType = try #require(bDecl.symbol?.type)
    #expect(bType as AnyObject === yType as AnyObject)
}

@Test
func useBeforeDefinitionWithoutAnnotationInFunctionInfersType() throws {
    let (_, programs) = runTypeChecker([
        "struct Int32 { init() {} }\n"
            + "func f() {\n    let y = b\n    let b = Int32()\n}",
    ])
    let functionDecl = try #require(programs[0].statements[1] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let yDecl = try #require(statements[0] as? AST.VariableDecl)
    let yType = try #require(yDecl.symbol?.type)
    #expect(!(yType is TrussType.ErrorType))
    let bDecl = try #require(statements[1] as? AST.VariableDecl)
    let bType = try #require(bDecl.symbol?.type)
    #expect(bType as AnyObject === yType as AnyObject)
}

@Test
func declarationBeforeUseStillInfersType() throws {
    let (_, programs) = runTypeChecker([
        "struct Int32 { init() {} }\n"
            + "func f() {\n    let b: Int32 = Int32()\n    let y = b\n}",
    ])
    let functionDecl = try #require(programs[0].statements[1] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let yDecl = try #require(statements[1] as? AST.VariableDecl)
    let yType = try #require(yDecl.symbol?.type)
    #expect(yType is TrussType.StructType)
}

@Test
func typeUseBeforeDeclarationInfersType() throws {
    let (_, programs) = runTypeChecker(["let tt = TT()\nstruct TT { init() {} }"])
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let ttType = try #require(variableDecl.symbol?.type)
    #expect(ttType is TrussType.GenericInstantiation)
    let structDecl = try #require(programs[0].statements[1] as? AST.StructDecl)
    let initDecl = try #require(structDecl.body[0] as? AST.InitDecl)
    let initType = try #require(initDecl.symbol?.functionType)
    #expect(initType.parameters.isEmpty)
}

@Test
func functionCallBeforeDeclarationInfersType() throws {
    let (_, programs) = runTypeChecker([
        "let g = makeG()\nstruct Int32 { init() {} }\nfunc makeG() -> Int32 { Int32() }",
    ])
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.StructType)
}

@Test
func integerLiteralInfersToInt32() throws {
    let (context, programs) = runTypeChecker(["let v = 42"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int32")
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func floatLiteralInfersToFloat64() throws {
    let (context, programs) = runTypeChecker(["let v = 3.14"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Float64")
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func boolLiteralInfersToBool() throws {
    let (context, programs) = runTypeChecker(["let v = true"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Bool")
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func integerLiteralMatchesInt64Annotation() throws {
    let (context, programs) = runTypeChecker(["let v: Builtin.Int64 = 42"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int64")
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func ifConditionRequiresBool() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nfunc f(x: S) {\n    if x {\n    }\n}"],
        installBuiltin: true
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("expected 'Builtin.Bool'") })
}

@Test
func ifBoolLiteralConditionPasses() {
    let (context, _) = runTypeChecker(["func f() {\n    if true {\n    }\n}"], installBuiltin: true)
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func ifBoolVariableConditionPasses() {
    let (context, _) = runTypeChecker(
        ["func f(b: Builtin.Bool) {\n    if b {\n    }\n}"],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func whileConditionRequiresBool() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nfunc f(x: S) {\n    while x {\n    }\n}"],
        installBuiltin: true
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("expected 'Builtin.Bool'") })
}

@Test
func caseMatchInfersToBool() throws {
    let (context, programs) = runTypeChecker(
        ["enum E { case C }\nfunc f(e: E) {\n    let b = case .C = e\n}"],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let functionDecl = try #require(programs[0].statements[1] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Bool")
}

@Test
func caseMatchAsIfConditionPasses() {
    let (context, _) = runTypeChecker(
        ["enum E { case C }\nfunc f(e: E) {\n    if case .C = e {\n    }\n}"],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func optionalBindingExpressionInfersToBool() throws {
    let (context, programs) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(a: S?) {\n    let b = (let x = a)\n}"],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let functionDecl = try #require(programs[0].statements[1] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Bool")
    let xSymbol = try #require(functionDecl.symbol?.scope.values["x"]?.first as? Symbol.VariableSymbol)
    #expect(xSymbol.type == nil)
}

@Test
func optionalBindingConditionBindsVariable() throws {
    let (context, programs) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(a: S?) {\n    if (let x = a) {\n    }\n}"],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let functionDecl = try #require(programs[0].statements[1] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let expressionStatement = try #require(statements[0] as? AST.ExpressionStatement)
    let ifExpression = try #require(expressionStatement.expression as? AST.If)
    let xSymbol = try #require(ifExpression.scope?.values["x"]?.first as? Symbol.VariableSymbol)
    let xType = try #require(xSymbol.type)
    #expect(xType is TrussType.StructType)
}

@Test
func optionalBindingExpressionAsIfConditionPasses() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(a: S?) {\n    if (let x = a) {\n    }\n}"],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func builtinCallResolvesWithReturnType() throws {
    let (context, programs) = runTypeChecker(
        ["let x = Builtin.builtin_add_int32(1, 2)"], installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int32")
}

@Test
func builtinCallArgumentTypeMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["let x = Builtin.builtin_add_int32(1, 2.0)"], installBuiltin: true
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("no exact matches in call to 'builtin_add_int32'"))
}

@Test
func builtinCallArgumentCountMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["let x = Builtin.builtin_add_int32(1)"], installBuiltin: true
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func builtinCallNegIsUnary() throws {
    let (context, programs) = runTypeChecker(
        ["let x = Builtin.builtin_neg_float64(1.5)"], installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Float64")
}

@Test
func builtinCompareCallReturnsBool() throws {
    let (context, programs) = runTypeChecker(
        [
            "let a: Builtin.UInt64 = 1\n"
                + "let b: Builtin.UInt64 = 2\n"
                + "let x = Builtin.builtin_eq_int32(1, 2)\n"
                + "let y = Builtin.builtin_lt_uint64(a, b)\n"
                + "let z = Builtin.builtin_ge_float64(1.0, 2.0)\n",
        ],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
    for index in 2 ..< 5 {
        let variableDecl = try #require(programs[0].statements[index] as? AST.VariableDecl)
        let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
        #expect(type.name == "Bool")
    }
}

@Test
func builtinNotAndBitnotCalls() throws {
    let (context, programs) = runTypeChecker(
        [
            "let x = Builtin.builtin_not_bool(true)\n"
                + "let y = Builtin.builtin_bitnot_int32(5)\n",
        ],
        installBuiltin: true
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let first = try #require(programs[0].statements[0] as? AST.VariableDecl)
    #expect((first.symbol?.type as? TrussType.BuiltinType)?.name == "Bool")
    let second = try #require(programs[0].statements[1] as? AST.VariableDecl)
    #expect((second.symbol?.type as? TrussType.BuiltinType)?.name == "Int32")
}

@Test
func builtinCompareTypeMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["let x = Builtin.builtin_eq_int32(1, 2.0)"], installBuiltin: true
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("no exact matches in call to 'builtin_eq_int32'"))
}

@Test
func instanceSubscriptGetAndSet() throws {
    let source = """
    precedencegroup Assignment { assignment: true }
    infix operator =: Assignment
    struct Buffer {
        var x: Builtin.Int32
        subscript(i: Builtin.Int32) -> Builtin.Int32 {
            get {
                return x
            }
            set {
                x = newValue
            }
        }
    }
    func use() {
        var b: Buffer
        let v = b[0]
        b[0] = 42
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.isEmpty, "unexpected diagnostics: \(errors)")
}

@Test
func readOnlySubscriptAssignmentDiagnosed() throws {
    let source = """
    precedencegroup Assignment { assignment: true }
    infix operator =: Assignment
    struct Buffer {
        var x: Builtin.Int32
        subscript(i: Builtin.Int32) -> Builtin.Int32 {
            get {
                return x
            }
        }
    }
    func use() {
        var b: Buffer
        b[0] = 42
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.contains { $0.contains("cannot assign to subscript") }, "got: \(errors)")
}

@Test
func subscriptWithSetterDeclOnly() throws {
    let source = """
    precedencegroup Assignment { assignment: true }
    infix operator =: Assignment
    struct Buffer {
        var x: Builtin.Int32
        subscript(i: Builtin.Int32) -> Builtin.Int32 {
            get {
                return x
            }
            set {
                x = newValue
            }
        }
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.isEmpty, "unexpected diagnostics: \(errors)")
}

@Test
func subscriptOverloadResolutionByArgumentType() throws {
    let source = """
    precedencegroup Assignment { assignment: true }
    infix operator =: Assignment
    struct Buffer {
        var x: Builtin.Int32
        subscript(i: Builtin.Int32) -> Builtin.Int32 {
            get {
                return x
            }
            set {
                x = newValue
            }
        }
        subscript(s: Builtin.Int64) -> Builtin.Int64 {
            get {
                return 0
            }
            set {
                x = 0
            }
        }
    }
    func use() {
        var b: Buffer
        let a = b[1]
        let c = b[1]
        b[2] = 3
    }
    """
    let (context, programs) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.isEmpty, "unexpected diagnostics: \(errors)")
}

@Test
func compoundAssignmentOnSubscript() throws {
    let source = """
    precedencegroup Assignment { assignment: true }
    precedencegroup Additive { higherThan: Assignment }
    infix operator =: Assignment
    infix operator +=: Additive
    func +=(lhs: Builtin.Int32, rhs: Builtin.Int32) -> Builtin.Int32 {
        return Builtin.builtin_add_int32(lhs, rhs)
    }
    struct Buffer {
        var x: Builtin.Int32
        subscript(i: Builtin.Int32) -> Builtin.Int32 {
            get {
                return x
            }
            set {
                x = newValue
            }
        }
    }
    func use() {
        var b: Buffer
        b[1] += 2
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.isEmpty, "unexpected diagnostics: \(errors)")
}

@Test
func keyPathSubscriptComponentResolution() throws {
    let source = """
    struct Box {
        var value: Builtin.Int32
    }
    struct Holder {
        var box: Box
        subscript(i: Builtin.Int32) -> Builtin.Int32 {
            get {
                return box.value
            }
        }
    }
    func use() {
        var h: Holder
        let k = \\h[0]
        let k2 = \\h.box
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.isEmpty, "unexpected diagnostics: \(errors)")
}

@Test
func sizeofExpressionType() throws {
    let source = """
    func f() -> Builtin.UInt64 {
        return sizeof(Builtin.Int32)
    }
    """
    let (context, programs) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.isEmpty, "unexpected diagnostics: \(errors)")
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let ret = try #require(functionDecl.body as? AST.FunctionDecl.Body)
    if case let .Block(statements) = ret {
        let returnStmt = try #require(statements[0] as? AST.Return)
        let sizeofExpr = try #require(returnStmt.value as? AST.SizeofExpression)
        #expect(sizeofExpr.ty is TrussType.BuiltinType)
        #expect((sizeofExpr.ty as! TrussType.BuiltinType).name == "UInt64")
    }
}

@Test
func sizeofProtocolTypeDiagnosed() throws {
    let source = """
    protocol P {}
    func f() -> Builtin.UInt64 {
        return sizeof(P)
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.contains { $0.contains("cannot determine size of protocol type") }, "got: \(errors)")
}

@Test
func sizeofGenericParameterAllowed() throws {
    let source = """
    func sizeOf<T>(x: T) -> Builtin.UInt64 {
        return sizeof(T)
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(errors.isEmpty, "unexpected diagnostics: \(errors)")
}

@Test
func compositionSameNameConflictDiagnosed() throws {
    let source = """
    struct Int {}
    struct Bool {}
    protocol P {
        func foo(x: Int)
    }
    protocol Q {
        func foo(x: Bool)
    }
    struct S: P, Q {
        func foo(x: Int) {}
        func foo(x: Bool) {}
    }
    func main() {
        let v: any P & Q = S()
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(
        errors.contains { $0.contains("requirement 'foo' has conflicting signatures") },
        "got: \(errors)"
    )
}

@Test
func compositionSameNameIdenticalSignatureNoDiagnosis() throws {
    let source = """
    protocol P {
        func foo()
    }
    protocol Q {
        func foo()
    }
    struct S: P, Q {
        init() {}
        func foo() {}
    }
    func main() {
        let v: any P & Q = S()
    }
    """
    let (context, _) = runTypeChecker([source], installBuiltin: true)
    let errors = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(
        !errors.contains { $0.contains("conflicting signatures") },
        "got: \(errors)"
    )
}

private func memberFunction(
    _ name: String, in type: Symbol.NominalTypeSymbol?
) throws -> Symbol.FunctionSymbol {
    try #require(type?.scope.values[name]?.first as? Symbol.FunctionSymbol)
}

private func selfSymbol(of function: Symbol.FunctionSymbol?) throws -> Symbol.SelfSymbol {
    let function = try #require(function)
    return try #require(function.scope.values["self"]?.first as? Symbol.SelfSymbol)
}

private func collectSelfExpressions(_ program: AST.Program) -> [AST.SelfExpression] {
    let probe = SymbolProbe()
    probe.visitProgram(program)
    return probe.selfExpressions
}

@Test
func instanceMethodSelfSymbolType() throws {
    let (context, programs) = runTypeChecker(["struct S { func m() { self } }"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let selfSymbol = try selfSymbol(of: memberFunction("m", in: structDecl.symbol))
    let selfType = try #require(selfSymbol.type)
    let typeId = try #require(structDecl.symbol?.typeId)
    #expect(selfType as AnyObject === context.typeTable[typeId] as AnyObject)
    let selfExpression = try #require(collectSelfExpressions(programs[0]).first)
    #expect(selfExpression.ty === selfType)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func genericInstanceMethodSelfSymbolType() throws {
    let (context, programs) = runTypeChecker(["struct S<T> { func m() { self } }"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let selfSymbol = try selfSymbol(of: memberFunction("m", in: structDecl.symbol))
    let selfType = try #require(selfSymbol.type as? TrussType.GenericInstantiation)
    #expect(selfType.base.name == "S")
    #expect(selfType.arguments.count == 1)
    let parameter = try #require(selfType.arguments.first as? TrussType.GenericParamType)
    #expect(parameter.name == "T")
    let selfExpression = try #require(collectSelfExpressions(programs[0]).first)
    #expect(selfExpression.ty === selfType)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func initSelfSymbolType() throws {
    let (context, programs) = runTypeChecker(["struct S { init() {} }"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let initializer = try #require(structDecl.symbol?.initializers.first)
    let selfSymbol = try selfSymbol(of: initializer)
    let selfType = try #require(selfSymbol.type)
    let typeId = try #require(structDecl.symbol?.typeId)
    #expect(selfType as AnyObject === context.typeTable[typeId] as AnyObject)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func deinitSelfSymbolType() throws {
    let (context, programs) = runTypeChecker(["class C { deinit {} }"])
    let classDecl = programs[0].statements[0] as! AST.ClassDecl
    let selfSymbol = try selfSymbol(of: classDecl.symbol?.deinitializer)
    let selfType = try #require(selfSymbol.type)
    let typeId = try #require(classDecl.symbol?.typeId)
    #expect(selfType as AnyObject === context.typeTable[typeId] as AnyObject)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func subscriptSelfSymbolType() throws {
    let source = """
    struct Int {}
    struct S {
        subscript(i: Int) -> Int {
            get { i }
            set { }
        }
    }
    """
    let (context, programs) = runTypeChecker([source])
    let structDecl = programs[0].statements[1] as! AST.StructDecl
    let subscriptSymbol = try #require(
        structDecl.symbol?.scope.values["subscript"]?.first as? Symbol.SubscriptSymbol
    )
    let typeId = try #require(structDecl.symbol?.typeId)
    let expected = context.typeTable[typeId]
    let getterSelfType = try #require(try selfSymbol(of: subscriptSymbol.getter).type)
    #expect(getterSelfType as AnyObject === expected as AnyObject)
    let setterSelfType = try #require(try selfSymbol(of: subscriptSymbol.setter).type)
    #expect(setterSelfType as AnyObject === expected as AnyObject)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func propertyAccessorSelfSymbolType() throws {
    let source = """
    struct Int {}
    struct S {
        var p: Int {
            get { 0 }
            set { }
        }
    }
    """
    let (context, programs) = runTypeChecker([source])
    let structDecl = programs[0].statements[1] as! AST.StructDecl
    let variableDecl = try #require(structDecl.body.first as? AST.VariableDecl)
    let typeId = try #require(structDecl.symbol?.typeId)
    let expected = context.typeTable[typeId]
    try #require(variableDecl.accessors.count == 2)
    for accessor in variableDecl.accessors {
        let selfType = try #require(try selfSymbol(of: accessor.symbol).type)
        #expect(selfType as AnyObject === expected as AnyObject)
    }
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func propertyAccessorFunctionTypes() throws {
    let source = """
    struct Int {}
    struct S {
        var p: Int {
            get { 0 }
            set { }
        }
        static var q: Int {
            get { 0 }
        }
    }
    """
    let (context, programs) = runTypeChecker([source])
    let structDecl = programs[0].statements[1] as! AST.StructDecl
    let typeId = try #require(structDecl.symbol?.typeId)
    let expectedSelf = context.typeTable[typeId]
    let property = try #require((structDecl.body[0] as! AST.VariableDecl).symbol)
    let getter = try #require(property.accessors[.Get]?.functionType)
    #expect(getter.selfType as AnyObject === expectedSelf as AnyObject)
    #expect(getter.parameters.isEmpty)
    #expect(getter.returnType is TrussType.StructType)
    let setter = try #require(property.accessors[.Set]?.functionType)
    #expect(setter.selfType as AnyObject === expectedSelf as AnyObject)
    #expect(setter.parameters.count == 1)
    #expect(setter.parameters[0].label == nil)
    #expect(setter.parameters[0].type is TrussType.StructType)
    #expect(setter.returnType is TrussType.VoidType)
    let staticProperty = try #require((structDecl.body[1] as! AST.VariableDecl).symbol)
    let staticGetter = try #require(staticProperty.accessors[.Get]?.functionType)
    #expect(staticGetter.selfType == nil)
    #expect(staticGetter.returnType is TrussType.StructType)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func observerImplicitParameterTypes() throws {
    let source = """
    struct Int {}
    struct S {
        var p: Int = 0 {
            willSet { }
            didSet { }
        }
    }
    """
    let (context, programs) = runTypeChecker([source])
    let structDecl = programs[0].statements[1] as! AST.StructDecl
    let variableDecl = structDecl.body[0] as! AST.VariableDecl
    let newValue = try #require(
        variableDecl.accessors[0].scope?.values["newValue"]?.first as? Symbol.VariableSymbol
    )
    let oldValue = try #require(
        variableDecl.accessors[1].scope?.values["oldValue"]?.first as? Symbol.VariableSymbol
    )
    #expect(newValue.type is TrussType.StructType)
    #expect(oldValue.type is TrussType.StructType)
    let willSet = try #require(variableDecl.symbol?.accessors[.WillSet]?.functionType)
    #expect(willSet.parameters.count == 1)
    #expect(willSet.parameters[0].type is TrussType.StructType)
    #expect(willSet.returnType is TrussType.VoidType)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func staticMethodSelfHasNoCascadeDiagnostic() throws {
    let (context, programs) = runTypeChecker(["struct S { static func f() { self } }"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let method = try memberFunction("f", in: structDecl.symbol)
    #expect(method.scope.values["self"] == nil)
    let selfExpression = try #require(collectSelfExpressions(programs[0]).first)
    #expect(selfExpression.symbol == nil)
    #expect(selfExpression.ty == nil)
    #expect(
        context.diagnosticEngine.diagnostics.map(\.message)
            == ["'self' is only available in an instance context"]
    )
}

@Test
func typeChecksForBodyRewrittenByOperatorPass() {
    let (context, programs) = runTypeChecker(["""
    precedencegroup AssignmentPrecedence {
        associativity: right
        assignment: true
    }
    infix operator = : AssignmentPrecedence
    func f() {
        var i = 0
        for j in 0 {
            i = 1
        }
    }
    """])
    #expect(programs.count == 1)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func typeChecksRewrittenLoopAndClosureBodies() {
    let (context, programs) = runTypeChecker(["""
    precedencegroup AssignmentPrecedence {
        associativity: right
        assignment: true
    }
    infix operator = : AssignmentPrecedence
    struct Holder {
        var stored = 1
        var computed: Builtin.Int32 {
            get { return self.stored }
            set { self.stored = 1 }
        }
        subscript(index: Builtin.Int32) -> Builtin.Int32 {
            get { return self.stored }
            set { self.stored = 1 }
        }
    }
    func f() {
        var i = 0
        while true {
            i = 1
        }
        loop {
            i = 1
        }
        repeat {
            i = 1
        } while true
        if true {
            i = 1
        }
        let g: () -> Builtin.Int32 = {
            var k = 0
            while true {
                k = 1
            }
            return k
        }
        var h = Holder()
        h.computed = 2
        g()
    }
    """], installBuiltin: true)
    #expect(programs.count == 1)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func operatorReferenceInValuePosition() throws {
    let source =
        "precedencegroup Additive {}\ninfix operator +: Additive\n"
            + "struct S {}\nfunc +(lhs: S, rhs: S) -> S { lhs }\n"
            + "func applyClosure(f: (lhs: S, rhs: S) -> S) {}\n"
            + "func applyFunction(f: func(lhs: S, rhs: S) -> S) {}\n"
            + "func main() {\nvar s: S\n"
            + "let c: (lhs: S, rhs: S) -> S = (+)\n"
            + "let f: func(lhs: S, rhs: S) -> S = (+)\n"
            + "applyClosure(+)\napplyFunction(+)\n}\n"
    let (context, programs) = runTypeChecker([source])
    #expect(programs.count == 1)
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func closureTypeSyntaxEvaluatesToClosureType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f: (x: S) -> S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.ClosureType)
    #expect(!(type is TrussType.FunctionType))
    let closureType = try #require(type as? TrussType.ClosureType)
    #expect(closureType.parameters.count == 1)
    #expect(closureType.parameters[0].label == "x")
}

@Test
func functionTypeSyntaxEvaluatesToFunctionType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f: func(x: S) -> S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.FunctionType)
    #expect(!(type is TrussType.ClosureType))
    let functionType = try #require(type as? TrussType.FunctionType)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.selfType == nil)
}

@Test
func declaredFunctionValueHasFunctionType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nfunc f(x: S) -> S { x }\nlet g = f"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.FunctionType)
    #expect(!(type is TrussType.ClosureType))
}

@Test
func closureLiteralWithoutContextInfersClosureType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f = { (x: S) -> S in x }"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.ClosureType)
    #expect(!(type is TrussType.FunctionType))
}

@Test
func closureLiteralCheckedAgainstFunctionTypeKeepsFunctionType() throws {
    let (context, programs) = runTypeChecker(["struct S {}\nlet f: func(x: S) -> S = { x in x }"])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.FunctionType)
    let closure = try #require(variableDecl.initializer as? AST.Closure)
    #expect(closure.ty is TrussType.FunctionType)
}

@Test
func variadicClosureTypeSyntaxUsesIsVariadic() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f: (xs: S...) -> Void"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let closureType = try #require(variableDecl.symbol?.type as? TrussType.ClosureType)
    #expect(closureType.isVariadic)
    #expect(closureType.parameters.count == 1)
    #expect(closureType.parameters[0].type is TrussType.StructType)
    #expect(!(closureType.parameters[0].type is TrussType.VariadicType))
}

@Test
func variadicFunctionTypeSyntaxUsesIsVariadic() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f: func(xs: S...) -> Void"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let functionType = try #require(variableDecl.symbol?.type as? TrussType.FunctionType)
    #expect(functionType.isVariadic)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.parameters[0].type is TrussType.StructType)
    #expect(!(functionType.parameters[0].type is TrussType.VariadicType))
}

@Test
func variadicSurvivesGenericSubstitution() throws {
    let source = "struct S {}\nstruct Box<T> { var f: func(xs: T...) -> Void }\n"
        + "func main() {\n    var b: Box<S>\n    let g = b.f\n}"
    let (_, programs) = runTypeChecker([source])
    let functionDecl = programs[0].statements[2] as! AST.FunctionDecl
    let body = try #require(functionDecl.body)
    let statements: [AST.Statement] = if case let .Block(block) = body {
        block
    } else {
        []
    }
    let variableDecl = try #require(statements[1] as? AST.VariableDecl)
    let functionType = try #require(variableDecl.symbol?.type as? TrussType.FunctionType)
    #expect(functionType.isVariadic)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.parameters[0].type is TrussType.StructType)
}

@Test
func functionTypeSyntaxAcceptsDeclaredFunctionValue() throws {
    let (context, programs) = runTypeChecker([
        "struct S {}\nfunc f(x: S) -> S { x }\nlet g: func(x: S) -> S = f",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.FunctionType)
}

@Test
func functionTypeAnnotationAcceptsVariadicDeclaredFunction() throws {
    let (context, _) = runTypeChecker([
        "struct S {}\nfunc f(xs: S...) -> Void {}\nlet g: func(xs: S...) -> Void = f",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func functionToClosureConversionInAssignmentArgumentAndReturn() {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    func apply(f: (Int) -> Int) {}
    func make() -> (Int) -> Int { return id }
    func main() {
        let copy: (Int) -> Int = id
        apply(f: id)
        let made = make()
        let value = copy(Int())
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func closureToFunctionConversionIsRejected() {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    let c: (Int) -> Int = id
    let bad: func(x: Int) -> Int = c
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'func(x: Int) -> Int', found '(Int) -> Int'"))
}

@Test
func nonCapturingClosureLiteralAsFunctionTypeIsAccepted() throws {
    let source = """
    struct Int { init() {} }
    let f: func(x: Int) -> Int = { (x: Int) -> Int in x }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.FunctionType)
    let closure = try #require(variableDecl.initializer as? AST.Closure)
    #expect(closure.ty is TrussType.FunctionType)
}

@Test
func capturingClosureLiteralAsFunctionTypeIsRejected() {
    let source = """
    struct Int { init() {} }
    func main() {
        var outer: Int
        let f: func(x: Int) -> Int = { (x: Int) -> Int in outer }
    }
    """
    let (context, _) = runTypeChecker([source])
    let diagnostics = context.diagnosticEngine.diagnostics
    #expect(diagnostics.contains { diagnostic in
        diagnostic.message
            == "closure captures outer and cannot be converted to function type "
            + "'func(x: Int) -> Int'"
            && diagnostic.notes.contains {
                $0.message == "consider using the closure type '(x: Int) -> Int' instead"
            }
    })
}

@Test
func contextualClosureArgumentCheckedAgainstFunctionType() throws {
    let source = """
    struct Int { init() {} }
    func consume(f: func(x: Int) -> Int) {}
    func main() {
        consume(f: { (x: Int) -> Int in x })
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = programs[0].statements[2] as! AST.FunctionDecl
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let statement = try #require(statements.first as? AST.ExpressionStatement)
    let call = try #require(statement.expression as? AST.Call)
    let closure = try #require(call.arguments.first?.value as? AST.Closure)
    #expect(closure.ty is TrussType.FunctionType)
}

@Test
func mixedFunctionAndClosureJoinConvergesToClosureType() throws {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    let f: func(x: Int) -> Int = id
    let g: (Int) -> Int = { (x: Int) -> Int in x }
    let h = if true { f } else { g }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.ClosureType)
    #expect(!(type is TrussType.FunctionType))
}

@Test
func directCallOfClosureValueChecksArgumentCount() {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    let f: (Int) -> Int = id
    let r = f(Int(), Int())
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 1 argument, found 2"))
}

@Test
func directCallOfClosureValueChecksArgumentType() {
    let source = """
    struct Int { init() {} }
    struct Other { init() {} }
    func id(x: Int) -> Int { x }
    let f: (Int) -> Int = id
    var o: Other
    let r = f(o)
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'Int', found 'Other'"))
}

@Test
func directCallOfClosureValueChecksArgumentLabels() {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    let f: (Int) -> Int = id
    let r = f(y: Int())
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("unexpected argument label 'y'"))
}

@Test
func directCallOfFunctionValueUsesReturnType() throws {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    let f: (Int) -> Int = id
    let r = f(Int())
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.StructType)
}

@Test
func directCallOfThrowingClosureValueRequiresTry() {
    let source = """
    struct Int { init() {} }
    func boom() throws {}
    let t: () throws -> Void = boom
    func main() {
        t()
    }
    """
    let (context, _) = runTypeChecker([source])
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("call to throwing function must be tried"))
}

@Test
func directCallOfThrowingClosureValueInsideTryIsAllowed() {
    let source = """
    struct Int { init() {} }
    func boom() throws {}
    let t: () throws -> Void = boom
    func main() {
        try t()
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func functionTypeTextUsesFuncPrefixWithSelfType() {
    let source = """
    struct Int { init() {} }
    struct S {
        func m(x: Int) -> Int { x }
        func n() {
            let bad: () -> Void = self.m
        }
    }
    """
    let (context, _) = runTypeChecker([source])
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected '() -> Void', found 'S.func(x: Int) -> Int'"))
}

@Test
func closureTypeTextUsesClosureSyntaxWithoutFuncPrefix() {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    let c: (Int) -> Int = id
    let bad: func(x: Int) -> Int = c
    """
    let (context, _) = runTypeChecker([source])
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("found '(Int) -> Int'") })
}

@Test
func closureTypeTextRendersVariadicParameter() {
    let source = """
    struct Int { init() {} }
    struct Other { init() {} }
    let f: (x: Int...) -> Int = Other()
    """
    let (context, _) = runTypeChecker([source])
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected '(x: Int...) -> Int', found 'Other<>'"))
}

@Test
func valueCallChecksNonCapturingClosureLiteralAgainstFunctionParameter() throws {
    let source = """
    struct Int { init() {} }
    func consume(f: func(x: Int) -> Int) -> Int { return 1 }
    let g: func(f: func(x: Int) -> Int) -> Int = consume
    func main() -> Int {
        return g(f: { (x: Int) -> Int in x })
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let closure = try #require(closureLiteralArgument(in: programs[0]))
    #expect(closure.ty is TrussType.FunctionType)
}

@Test
func valueCallRejectsCapturingClosureLiteralAgainstFunctionParameter() {
    let source = """
    struct Int { init() {} }
    func consume(f: func(x: Int) -> Int) -> Int { return 1 }
    let g: func(f: func(x: Int) -> Int) -> Int = consume
    func main() -> Int {
        var outer: Int
        return g(f: { (x: Int) -> Int in outer })
    }
    """
    let (context, _) = runTypeChecker([source])
    let diagnostics = context.diagnosticEngine.diagnostics
    #expect(diagnostics.contains { diagnostic in
        diagnostic.message
            == "closure captures outer and cannot be converted to function type "
            + "'func(x: Int) -> Int'"
            && diagnostic.notes.contains {
                $0.message == "consider using the closure type '(x: Int) -> Int' instead"
            }
    })
}

@Test
func valueCallChecksLabeledClosureLiteralAgainstNilLabelParameter() throws {
    let source = """
    struct Int { init() {} }
    func consume(f: (Int) -> Int) -> Int { return 1 }
    let g: func(f: (Int) -> Int) -> Int = consume
    func main() -> Int {
        return g(f: { (a x: Int) -> Int in x })
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let closure = try #require(closureLiteralArgument(in: programs[0]))
    #expect(closure.ty is TrussType.ClosureType)
}

@Test
func closureArgumentIsTypedByTheSelectedCandidateOnly() throws {
    let source = """
    struct A { init() {} }
    struct B { init() {} }
    func consume(f: (a: A) -> A) {}
    func consume(f: (b: B) -> B) {}
    func main() {
        consume(f: { (b x: B) -> B in x })
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = try #require(
        programs[0].statements.compactMap { $0 as? AST.FunctionDecl }
            .first { $0.name.value == "main" }
    )
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let call = try #require(statements.first as? AST.ExpressionStatement)
    let expression = try #require(call.expression as? AST.Call)
    let closure = try #require(expression.arguments.first?.value as? AST.Closure)
    let closureType = try #require(closure.ty as? TrussType.ClosureType)
    #expect(closureType.parameters.first?.type is TrussType.StructType)
    let parameterType = try #require(closureType.parameters.first?.type as? TrussType.StructType)
    #expect(parameterType.name == "B")
    let signatureParameter = try #require(closure.signature?.parameters.first)
    let symbolType = try #require(signatureParameter.symbol?.type as? TrussType.StructType)
    #expect(symbolType.name == "B")
    #expect(
        AST.Expression.resolvedFunctionSymbol(of: expression.callee)?
            .functionType?.parameters.first?.type is TrussType.ClosureType
    )
}

@Test
func fixedArityFunctionIsRejectedByVariadicClosureType() {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    let bad: (Int...) -> Int = id
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(!messages.isEmpty)
}

@Test
func variadicFunctionConvertsToVariadicClosureType() {
    let source = """
    struct Int { init() {} }
    func f(xs: Int...) -> Int { return Int() }
    let g: (Int...) -> Int = f
    """
    let (context, _) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func variadicClosureTypeDoesNotAcceptFixedArityClosureValue() {
    let source = """
    struct Int { init() {} }
    func f(xs: Int...) -> Int { return Int() }
    func apply(f: (Int) -> Int) -> Int { return Int() }
    let variadicClosure: (Int...) -> Int = f
    let bad = apply(f: variadicClosure)
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func captureSuggestionKeepsCallableEffects() {
    let source = """
    struct Int { init() {} }
    func main() {
        var outer: Int
        let f: func(x: Int) throws -> Int = { (x: Int) -> Int in outer }
    }
    """
    let (context, _) = runTypeChecker([source])
    let diagnostics = context.diagnosticEngine.diagnostics
    #expect(diagnostics.contains { diagnostic in
        diagnostic.notes.contains {
            $0.message == "consider using the closure type '(x: Int) throws -> Int' instead"
        }
    })
}

private func closureLiteralArgument(in program: AST.Program) -> AST.Closure? {
    for statement in program.statements {
        guard let functionDecl = statement as? AST.FunctionDecl,
              case let .Block(body) = functionDecl.body
        else {
            continue
        }
        for statement in body {
            let call: AST.Call? =
                if let expressionStatement = statement as? AST.ExpressionStatement {
                    expressionStatement.expression as? AST.Call
                } else if let returnStatement = statement as? AST.Return {
                    returnStatement.value as? AST.Call
                } else {
                    nil
                }
            if let closure = call?.arguments.first?.value as? AST.Closure {
                return closure
            }
        }
    }
    return nil
}

@Test
func declaredCallAcceptsLabeledLiteralForNilLabelParameter() {
    let source = """
    struct Int { init() {} }
    func consume(f: (Int) -> Int) {}
    func main() {
        consume(f: { (x: Int) -> Int in x })
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func declaredCallRejectsMismatchedLabeledLiteral() {
    let source = """
    struct Int { init() {} }
    func consume(f: (x: Int) -> Int) {}
    func main() {
        consume(f: { (y: Int) -> Int in y })
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func selectedCandidateControlsConvertedArgumentTyping() throws {
    let source = """
    struct Int { init() {} }
    func id(x: Int) -> Int { x }
    func consume(f: (x: Int) -> Int) -> Int { return 1 }
    func consume(f: (Int) -> Int) -> Void {}
    func main() {
        let r: Int = consume(f: id)
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = try #require(
        programs[0].statements.compactMap { $0 as? AST.FunctionDecl }
            .first { $0.name.value == "main" }
    )
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements.first as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    let argument = try #require(call.arguments.first?.value)
    let argumentType = try #require(argument.ty as? TrussType.ClosureType)
    #expect(argumentType.parameters.first?.label == "x")
    let callee = try #require(
        AST.Expression.resolvedFunctionSymbol(of: call.callee)?.functionType
    )
    #expect(callee.returnType is TrussType.StructType)
}

@Test
func declaredCallRequiresArgumentLabels() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, b: Int) -> Int { a }\nlet r = f(1, 2)",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("no exact matches in call to 'f'"))
}

@Test
func declaredCallRequiresPartialLabels() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, b: Int) -> Int { a }\nlet r = f(a: Int(), 2)",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("no exact matches in call to 'f'"))
}

@Test
func underscoreParameterBindsUnlabeledArgument() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, _ b: Int) -> Int { a }\n"
                + "let r = f(a: Int(), Int())",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func labeledParameterRejectsUnlabeledArgument() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, _ b: Int) -> Int { a }\n"
                + "let r = f(Int(), Int())",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func initializerCallRequiresArgumentLabels() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nstruct S { init(a: Int, b: Int) {} }\nlet s = S(Int(), Int())",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("no exact matches in call to 'init'"))
}

@Test
func methodCallRequiresArgumentLabels() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\n"
                + "struct S {\n    init() {}\n    func add(a: Int, b: Int) -> Int { a }\n}\n"
                + "func use() {\n    let s = S()\n    let r = s.add(Int(), Int())\n}",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("no exact matches in call to 'add'"))
}

@Test
func functionValueCallRequiresArgumentLabels() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, b: Int) -> Int { a }\n"
                + "let h = f\nlet r = h(Int(), Int())",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("missing argument label 'a' in call to 'h'"))
}

@Test
func functionValueCallAcceptsLabels() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, b: Int) -> Int { a }\n"
                + "let h = f\nlet r = h(a: Int(), b: Int())",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func labelledClosureTypeValueCallRequiresArgumentLabels() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, b: Int) -> Int { a }\n"
                + "let g: (a: Int, b: Int) -> Int = f\nlet r = g(Int(), Int())",
        ]
    )
    #expect(context.diagnosticEngine.hasErrors)
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages.contains("missing argument label 'a' in call to 'g'"))
}

@Test
func subscriptArgumentsStayPositional() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\n"
                + "struct S {\n    init() {}\n    subscript(i: Int) -> Int { i }\n}\n"
                + "func use() {\n    let s = S()\n    let r = s[Int()]\n}",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func trailingClosureIgnoresParameterLabel() {
    let (context, _) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(body: () -> Void) {}\nfunc use() {\n    f { }\n}",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func operatorReferenceArgumentBindsPositionally() {
    let source = """
    precedencegroup Additive {}
    infix operator +: Additive
    struct S {}
    func +(lhs: S, rhs: S) -> S { lhs }
    func applyClosure(f: (lhs: S, rhs: S) -> S) {}
    func main() {
    var s: S
    applyClosure(+)
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func memberOperatorCallAcceptsPositionalArgument() {
    let (context, _) = runTypeChecker(
        [
            "struct S { func +(rhs: S) -> S { self } }\nfunc main() {\nvar s: S\nlet a: S = s.+(s)\n}",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func outOfOrderLabelledArgumentsRecordMapping() throws {
    let (context, programs) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, b: Int) -> Int { a }\n"
                + "let r = f(b: Int(), a: Int())",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = try #require(programs[0].statements[2] as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(call.argumentMapping == [1, 0])
}

@Test
func inOrderLabelledArgumentsRecordIdentityMapping() throws {
    let (context, programs) = runTypeChecker(
        [
            "struct Int { init() {} }\nfunc f(a: Int, b: Int) -> Int { a }\n"
                + "let r = f(a: Int(), b: Int())",
        ]
    )
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = try #require(programs[0].statements[2] as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(call.argumentMapping == [0, 1])
}

private let genericClosurePrelude = """
precedencegroup AssignmentPrecedence { assignment: true }
infix operator =: AssignmentPrecedence
struct Int { init() {} }
struct Box<T> {
    let v: T
    init(v: T) {
        self.v = v
    }
}
func id(x: Int) -> Int { x }
"""

private func resolvedTestType(_ type: TrussType.TrussType?) -> TrussType.TrussType? {
    guard let type else {
        return nil
    }
    guard let variable = type as? TrussType.TypeVariableType, let binding = variable.binding else {
        return type
    }
    return resolvedTestType(binding)
}

private func genericInstantiationArgument(of call: AST.Call) -> TrussType.TrussType? {
    guard let instantiation = resolvedTestType(call.ty) as? TrussType.GenericInstantiation else {
        return nil
    }
    guard let argument = instantiation.arguments.first else {
        return nil
    }
    return resolvedTestType(argument)
}

@Test
func explicitClosureGenericArgumentBindsClosureType() throws {
    let source = genericClosurePrelude + """
    func main() {
        let c: Box<(Int) -> Int> = Box<(Int) -> Int>(v: id)
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = try #require(
        programs[0].statements.compactMap { $0 as? AST.FunctionDecl }
            .first { $0.name.value == "main" }
    )
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements.first as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    let argument = try #require(genericInstantiationArgument(of: call))
    #expect(argument is TrussType.ClosureType)
    #expect(call.arguments.first?.value.ty is TrussType.ClosureType)
}

@Test
func explicitFunctionTypeGenericArgumentBindsFunctionType() throws {
    let source = """
    struct Box<T> {
        let v: T
        init(v: T) {}
    }
    func f() {}
    func main() {
        let c: Box<func() -> Void> = Box<func() -> Void>(v: f)
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = try #require(
        programs[0].statements.compactMap { $0 as? AST.FunctionDecl }
            .first { $0.name.value == "main" }
    )
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements.first as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    let argument = try #require(genericInstantiationArgument(of: call))
    #expect(argument is TrussType.FunctionType)
}

@Test
func explicitClosureGenericArgumentRejectsWrongType() {
    let source = genericClosurePrelude + """
    func main() {
        let c: Box<(Int) -> Int> = Box<(Int) -> Int>(v: Int())
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func explicitClosureGenericArgumentRejectsMismatchedArity() {
    let source = genericClosurePrelude + """
    func main() {
        let c: Box<(Int, Int) -> Int> = Box<(Int, Int) -> Int>(v: id)
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(context.diagnosticEngine.hasErrors)
}

@Test
func explicitClosureGenericArgumentOnGenericFunction() throws {
    let source = genericClosurePrelude + """
    func apply<T>(v: T) -> T { v }
    func main() {
        let c: (Int) -> Int = apply<(Int) -> Int>(v: id)
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = try #require(
        programs[0].statements.compactMap { $0 as? AST.FunctionDecl }
            .first { $0.name.value == "main" }
    )
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements.first as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(resolvedTestType(call.ty) is TrussType.ClosureType)
    #expect(call.arguments.first?.value.ty is TrussType.ClosureType)
}

@Test
func inferredGenericConstructionKeepsFunctionArgumentType() throws {
    let source = genericClosurePrelude + """
    func main() {
        let c = Box(v: id)
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = try #require(
        programs[0].statements.compactMap { $0 as? AST.FunctionDecl }
            .first { $0.name.value == "main" }
    )
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements.first as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    let argument = try #require(genericInstantiationArgument(of: call))
    #expect(argument is TrussType.FunctionType)
}

@Test
func inferredGenericConstructionInfersLiteralType() throws {
    let source = genericClosurePrelude + """
    func main() {
        let c = Box(v: 1)
    }
    """
    let (context, programs) = runTypeChecker([source], installBuiltin: true)
    #expect(!context.diagnosticEngine.hasErrors)
    let mainDecl = try #require(
        programs[0].statements.compactMap { $0 as? AST.FunctionDecl }
            .first { $0.name.value == "main" }
    )
    let body = try #require(mainDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements.first as? AST.VariableDecl)
    let call = try #require(variableDecl.initializer as? AST.Call)
    let argument = try #require(genericInstantiationArgument(of: call))
    #expect(argument is TrussType.BuiltinType)
}

private let genericPairPrelude = """
precedencegroup AssignmentPrecedence { assignment: true }
infix operator =: AssignmentPrecedence
struct Int { init() {} }
struct Pair<A, B> {
    init(a: A, b: B) {}
}
func id(x: Int) -> Int { x }
"""

private func genericInstantiationArguments(of call: AST.Call) -> [TrussType.TrussType]? {
    guard let instantiation = resolvedTestType(call.ty) as? TrussType.GenericInstantiation else {
        return nil
    }
    return instantiation.arguments.map { resolvedTestType($0) ?? $0 }
}

private func firstStatementCall(_ programs: [AST.Program]) -> AST.Call? {
    guard let mainDecl = programs[0].statements.compactMap({ $0 as? AST.FunctionDecl })
        .first(where: { $0.name.value == "main" }),
        let body = mainDecl.body,
        case let .Block(statements) = body,
        let variableDecl = statements.first as? AST.VariableDecl
    else {
        return nil
    }
    return variableDecl.initializer as? AST.Call
}

@Test
func explicitClosureGenericArgumentBindsSecondParameter() throws {
    let source = genericPairPrelude + """
    func main() {
        let p: Pair<Int, (Int) -> Int> = Pair<Int, (Int) -> Int>(a: Int(), b: id)
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let call = try #require(firstStatementCall(programs))
    let arguments = try #require(genericInstantiationArguments(of: call))
    #expect(arguments.count == 2)
    #expect(arguments[0] is TrussType.StructType)
    #expect(arguments[1] is TrussType.ClosureType)
}

@Test
func explicitClosureGenericArgumentBindsFirstParameter() throws {
    let source = genericPairPrelude + """
    func main() {
        let p: Pair<(Int) -> Int, Int> = Pair<(Int) -> Int, Int>(a: id, b: Int())
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let call = try #require(firstStatementCall(programs))
    let arguments = try #require(genericInstantiationArguments(of: call))
    #expect(arguments.count == 2)
    #expect(arguments[0] is TrussType.ClosureType)
    #expect(arguments[1] is TrussType.StructType)
}

private let genericStoredPropertyPairPrelude = """
precedencegroup AssignmentPrecedence { assignment: true }
infix operator =: AssignmentPrecedence
struct Int { init() {} }
struct Pair<A, B> {
    let a: A
    let b: B
    init(a: A, b: B) {
        self.a = a
        self.b = b
    }
}
func id(x: Int) -> Int { x }
"""

@Test
func storedPropertyGenericStructTypeChecks() {
    let source = genericStoredPropertyPairPrelude + """
    func use() {
        let x: Int = Int()
    }
    """
    let (context, _) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
}

@Test
func storedPropertyGenericStructBindsForwardSlots() throws {
    let source = genericStoredPropertyPairPrelude + """
    func main() {
        let p: Pair<Int, (Int) -> Int> = Pair<Int, (Int) -> Int>(a: Int(), b: id)
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let call = try #require(firstStatementCall(programs))
    let arguments = try #require(genericInstantiationArguments(of: call))
    #expect(arguments.count == 2)
    #expect(arguments[0] is TrussType.StructType)
    #expect(arguments[1] is TrussType.ClosureType)
}

@Test
func storedPropertyGenericStructBindsReversedSlots() throws {
    let source = genericStoredPropertyPairPrelude + """
    func main() {
        let p: Pair<(Int) -> Int, Int> = Pair<(Int) -> Int, Int>(a: id, b: Int())
    }
    """
    let (context, programs) = runTypeChecker([source])
    #expect(!context.diagnosticEngine.hasErrors)
    let call = try #require(firstStatementCall(programs))
    let arguments = try #require(genericInstantiationArguments(of: call))
    #expect(arguments.count == 2)
    #expect(arguments[0] is TrussType.ClosureType)
    #expect(arguments[1] is TrussType.StructType)
}

@Test
func parentheticalFunctionReferenceConvertsToClosureType() throws {
    let (context, programs) = runTypeChecker([
        "struct S { init() {} }\nfunc id(_ x: S) -> S { x }\nlet f: (S) -> S = (id)",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let parenthetical = try #require(variableDecl.initializer as? AST.Parenthetical)
    #expect(parenthetical.ty is TrussType.ClosureType)
    let inner = try #require(parenthetical.inner as? AST.Variable)
    #expect(inner.ty is TrussType.ClosureType)
}

@Test
func nestedParentheticalFunctionReferenceConvertsToClosureType() throws {
    let (context, programs) = runTypeChecker([
        "struct S { init() {} }\nfunc id(_ x: S) -> S { x }\nlet f: (S) -> S = ((id))",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let outer = try #require(variableDecl.initializer as? AST.Parenthetical)
    let inner = try #require(outer.inner as? AST.Parenthetical)
    let leaf = try #require(inner.inner as? AST.Variable)
    #expect(outer.ty is TrussType.ClosureType)
    #expect(inner.ty is TrussType.ClosureType)
    #expect(leaf.ty is TrussType.ClosureType)
}

@Test
func parenthesizedFunctionReferenceArgumentConvertsToClosureType() throws {
    let (context, programs) = runTypeChecker([
        "struct S { init() {} }\nfunc id(_ x: S) -> S { x }\n"
            + "func apply(_ f: (S) -> S) -> S { f }\nlet r = apply((id))",
    ])
    #expect(!context.diagnosticEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let call = try #require(variableDecl.initializer as? AST.Call)
    let argument = try #require(call.arguments.first?.value as? AST.Parenthetical)
    #expect(argument.ty is TrussType.ClosureType)
    let leaf = try #require(argument.inner as? AST.Variable)
    #expect(leaf.ty is TrussType.ClosureType)
}
