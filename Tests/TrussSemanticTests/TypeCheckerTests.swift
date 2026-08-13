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

#[builtin]
func + <T>(lhs: T*, rhs: Int) -> T*
#[builtin]
func + <T>(lhs: Int, rhs: T*) -> T*
#[builtin]
func - <T>(lhs: T*, rhs: Int) -> T*
#[builtin]
func - <T>(lhs: T*, rhs: T*) -> Int
#[builtin]
func == <T>(lhs: T*, rhs: T*) -> Bool
#[builtin]
func != <T>(lhs: T*, rhs: T*) -> Bool
#[builtin]
func < <T>(lhs: T*, rhs: T*) -> Bool
#[builtin]
func <= <T>(lhs: T*, rhs: T*) -> Bool
#[builtin]
func > <T>(lhs: T*, rhs: T*) -> Bool
#[builtin]
func >= <T>(lhs: T*, rhs: T*) -> Bool

"""

@Test func variableAnnotationType() throws {
    let (context, programs) = runTypeChecker(["struct S {}\nlet x: S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let symbol = try #require(variableDecl.symbol)
    let type = try #require(symbol.type)
    #expect(type is TrussType.StructType)
    let typeId = try #require((programs[0].statements[0] as! AST.StructDecl).symbol?.typeId)
    #expect(type as AnyObject === context.typeTable[typeId] as AnyObject)
}

@Test func noAnnotationLeavesTypeNil() {
    let (_, programs) = runTypeChecker(["let x"])
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type == nil)
}

@Test func noBuiltinTypeIsErrorType() {
    let (context, programs) = runTypeChecker(["let x: Int32"])
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ErrorType)
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int32'"))
}

@Test func moduleMemberTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(["module M {\n    struct A {}\n}\nlet x: M.A"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "A")
}

@Test func nestedTypeAnnotation() throws {
    let (_, programs) = runTypeChecker([
        "struct Outer {\n    struct Inner {}\n}\nlet x: Outer.Inner",
    ])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "Inner")
}

@Test func builtinTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(["let x: Builtin.Int64"], installBuiltin: true)
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int64")
}

@Test func builtinUnqualifiedNameStillErrors() throws {
    let (context, programs) = runTypeChecker(["let x: Int64"], installBuiltin: true)
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ErrorType)
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int64'"))
}

@Test func structWrappingBuiltinStorage() throws {
    let (_, programs) = runTypeChecker(
        ["struct Int {\n    var value: Builtin.Int64\n}"], installBuiltin: true
    )
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let member = try #require(structDecl.body.first as? AST.VariableDecl)
    let type = try #require(member.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int64")
}

@Test func optionalAnnotation() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet x: S?"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let optional = try #require(variableDecl.symbol?.type as? TrussType.OptionalType)
    #expect(optional.wrapped is TrussType.StructType)
}

@Test func tupleAnnotationWithLabels() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nstruct T {}\nlet x: (a: S, T)"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let tuple = try #require(variableDecl.symbol?.type as? TrussType.TupleType)
    #expect(tuple.elements.count == 2)
    #expect(tuple.elements[0].label == "a")
    #expect(tuple.elements[0].type is TrussType.StructType)
    #expect(tuple.elements[1].label == nil)
}

@Test func functionTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet f: (S) async throws -> S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let function = try #require(variableDecl.symbol?.type as? TrussType.FunctionType)
    #expect(function.parameters.count == 1)
    #expect(function.isAsync)
    #expect(function.isThrowing)
    #expect(function.returnType is TrussType.StructType)
}

@Test func declaredFunctionType() throws {
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
    let optional = try #require(functionType.parameters[1].type as? TrussType.OptionalType)
    #expect(optional.wrapped is TrussType.StructType)
    #expect(functionType.returnType is TrussType.StructType)
    let paramSymbol = try #require(symbol.scope.values["a"]?.first as? Symbol.VariableSymbol)
    #expect(paramSymbol.type is TrussType.StructType)
}

@Test func noReturnAnnotationDefaultsVoid() throws {
    let (_, programs) = runTypeChecker(["func f() {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.returnType is TrussType.VoidType)
}

@Test func unresolvableReturnAnnotationIsErrorType() throws {
    let (context, programs) = runTypeChecker(["func f() -> Int32 {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.returnType is TrussType.ErrorType)
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int32'"))
}

@Test func initFunctionTypeReturnsVoid() throws {
    let (_, programs) = runTypeChecker(["struct S {\n    init(x: S) {\n    }\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let initDecl = try #require(structDecl.body.first as? AST.InitDecl)
    let functionType = try #require(initDecl.symbol?.functionType)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.returnType is TrussType.VoidType)
}

@Test func throwsClauseRecordsThrownTypes() throws {
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

@Test func plainThrowsHasNoThrownTypes() throws {
    let (_, programs) = runTypeChecker(["func f() throws {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.isThrowing)
    #expect(functionType.throwsTypes.isEmpty)
}

@Test func nonThrowingFunctionHasEmptyThrows() throws {
    let (_, programs) = runTypeChecker(["func f() {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(!functionType.isThrowing)
    #expect(functionType.throwsTypes.isEmpty)
}

@Test func subscriptFunctionTypeReturnsElement() throws {
    let (_, programs) = runTypeChecker(["struct S {\n    subscript(i: S) -> S {\n    }\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let subscriptDecl = try #require(structDecl.body.first as? AST.SubscriptDecl)
    let functionType = try #require(subscriptDecl.symbol?.functionType)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.returnType is TrussType.StructType)
}

@Test func typealiasTargetType() throws {
    let (context, programs) = runTypeChecker(["struct S {}\ntypealias T = S"])
    let typeAliasDecl = programs[0].statements[1] as! AST.TypeAliasDecl
    let symbol = try #require(typeAliasDecl.symbol)
    let target = try #require(symbol.targetType)
    let typeId = try #require((programs[0].statements[0] as! AST.StructDecl).symbol?.typeId)
    #expect(target as AnyObject === context.typeTable[typeId] as AnyObject)
}

@Test func typealiasChainDereferences() throws {
    let (_, programs) = runTypeChecker(["struct S {}\ntypealias T = S\ntypealias U = T\nlet x: U"])
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "S")
}

@Test func typealiasCycleIsErrorType() {
    let (context, programs) = runTypeChecker(["typealias A = B\ntypealias B = A\nlet x: A"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ErrorType)
    let aSymbol = (programs[0].statements[0] as! AST.TypeAliasDecl).symbol
    let bSymbol = (programs[0].statements[1] as! AST.TypeAliasDecl).symbol
    #expect(aSymbol?.targetType is TrussType.ErrorType)
    #expect(bSymbol?.targetType is TrussType.ErrorType)
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("circular reference to typealias 'A'"))
}

@Test func closureLiteralFunctionType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet cl = { (x: S) -> S in x }"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let closure = try #require(variableDecl.initializer as? AST.Closure)
    let function = try #require(closure.ty as? TrussType.FunctionType)
    #expect(function.parameters.count == 1)
    #expect(function.parameters[0].type is TrussType.StructType)
    #expect(function.returnType is TrussType.StructType)
}

@Test func variadicParameterType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nfunc f(xs: S...) {}"])
    let functionDecl = programs[0].statements[1] as! AST.FunctionDecl
    let symbol = try #require(functionDecl.symbol)
    let variadic = try #require(
        symbol.functionType?.parameters.first?.type as? TrussType.VariadicType
    )
    #expect(variadic.base is TrussType.StructType)
}

@Test func compositionAnnotation() throws {
    let (_, programs) = runTypeChecker(["protocol P {}\nprotocol Q {}\nlet x: P & Q"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let composition = try #require(variableDecl.symbol?.type as? TrussType.CompositionType)
    #expect(composition.members.count == 2)
    #expect(composition.members[0] is TrussType.ProtocolType)
}

@Test func enumAssociatedValueType() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nenum E {\n    case a(x: S)\n}"])
    let enumDecl = programs[0].statements[1] as! AST.EnumDecl
    let caseDecl = try #require(enumDecl.body.first as? AST.EnumCaseDecl)
    let typeExpression = caseDecl.elements[0].associatedValues[0].typeExpression
    #expect(typeExpression.ty is TrussType.StructType)
}

@Test func castExpressionTypeIsTarget() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet x = y as S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let cast = try #require(variableDecl.initializer as? AST.Cast)
    #expect(cast.right.ty is TrussType.StructType)
    #expect(cast.ty is TrussType.StructType)
}

@Test func callReturnTypeResolved() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nfunc f() -> S {}\nlet x: S = f()"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(call.ty is TrussType.StructType)
}

@Test func variableReferencePropagates() throws {
    let (_, programs) = runTypeChecker(["struct S {}\nlet x: S\nlet y = x"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let variable = try #require(variableDecl.initializer as? AST.Variable)
    #expect(variable.ty is TrussType.StructType)
}

@Test func voidNeverAnnotations() throws {
    let (_, programs) = runTypeChecker(["let x: Void\nlet y: Never"])
    let voidDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(voidDecl.symbol?.type is TrussType.VoidType)
    let neverDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(neverDecl.symbol?.type is TrussType.NeverType)
}

@Test func matchingAssignmentPasses() {
    let (context,
         programs) =
        runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: S = s"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func mismatchedAssignmentReportsError() {
    let (context,
         _) =
        runTypeChecker(
            ["struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet x: S = t"]
        )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test func optionalPromotion() {
    let (context,
         _) = runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: S? = s"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func subclassAssignment() {
    let (context,
         _) =
        runTypeChecker(
            [
                "class Base { init() {} }\nclass Derived: Base { init() {} }\nfunc makeDerived() -> Derived { Derived() }\nlet d = makeDerived()\nlet b: Base = d",
            ]
        )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func neverConvertsToAnyType() {
    let (context,
         _) =
        runTypeChecker(["struct S { init() {} }\nfunc makeNever() -> Never { }\nlet n = makeNever()\nlet x: S = n"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func conformancePromotion() {
    let (context,
         _) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: P = s"]
        )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func conformanceMismatchReportsError() {
    let (context,
         _) =
        runTypeChecker(
            ["protocol P {}\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet x: P = t"]
        )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'P', found 'T'"))
}

@Test func overloadResolutionByExpectedReturn() throws {
    let (context,
         programs) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { S() }\nfunc f() -> T { T() }\nlet x: S = f()",
            ]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(call.symbol?.name == "f")
}

@Test func overloadNoMatchReportsError() {
    let (context,
         _) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nstruct U { init() {} }\nfunc f(x: S) {}\nfunc f(x: T) {}\nfunc makeU() -> U { U() }\nfunc main() { f(makeU()) }",
            ]
        )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("no exact matches in call to 'f'") }))
}

@Test func overloadAmbiguousReportsError() {
    let (context,
         _) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { S() }\nfunc f() -> T { T() }\nlet g = f()",
            ]
        )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("ambiguous use of 'f'") }))
}

@Test func genericFunctionTypeIsForall() throws {
    let (_, programs) = runTypeChecker(["struct S { init() {} }\nfunc id<T>(x: T) -> T { x }"])
    let functionDecl = programs[0].statements[1] as! AST.FunctionDecl
    let forall = try #require(functionDecl.symbol?.forallType)
    #expect(forall.parameters.count == 1)
    #expect(forall.parameters[0].name == "T")
    #expect(forall.body is TrussType.FunctionType)
}

@Test func genericFunctionImplicitInstantiation() throws {
    let (context,
         programs) =
        runTypeChecker(
            [
                "struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id(s)",
            ]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func genericFunctionExplicitInstantiation() throws {
    let (context,
         programs) =
        runTypeChecker(
            [
                "struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id<S>(s)",
            ]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func genericStructMember() throws {
    let (context,
         programs) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct Box<T> { init(v: T) {} var value: T }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet b = Box(v: s)\nlet v = b.value",
            ]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[5] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func closureParameterFromExpectedType() throws {
    let (context, programs) = runTypeChecker(["struct S { init() {} }\nlet f: (S) -> S = { x in x }"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let function = try #require(variableDecl.symbol?.type as? TrussType.FunctionType)
    #expect(function.parameters.count == 1)
    #expect(function.parameters[0].type is TrussType.StructType)
    #expect(function.returnType is TrussType.StructType)
}

@Test func closureWithoutContextReportsError() {
    let (context, _) = runTypeChecker(["struct S { init() {} }\nlet f = { x in x }"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("requires an explicit type annotation") }))
}

@Test func memberAccessOnInstance() throws {
    let (context,
         programs) =
        runTypeChecker(["struct S { init() {} var x: S }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet y = s.x"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func optionalChainingMemberAccess() throws {
    let (context,
         programs) =
        runTypeChecker(
            ["struct S { init() {} var x: S }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet z: S? = s\nlet w = z?.x"]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let optional = try #require(variableDecl.symbol?.type as? TrussType.OptionalType)
    #expect(optional.wrapped is TrussType.StructType)
}

@Test func ifElseJoinProducesBranchType() throws {
    let (context,
         programs) =
        runTypeChecker(
            ["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = if true { s } else { s }"]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func ifElseMismatchedBranchesReportError() {
    let (context,
         _) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc makeS() -> S { S() }\nfunc makeT() -> T { T() }\nlet s = makeS()\nlet t = makeT()\nlet x = if true { s } else { t }",
            ]
        )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func ifWithoutElseIsVoid() throws {
    let (context,
         programs) =
        runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = if true { s }"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.VoidType)
}

@Test func literalAdaptsToAnyAnnotation() {
    let (context, _) = runTypeChecker(["struct S { init() {} }\nlet x: S = 1"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func functionReturnTypeChecked() {
    let (context,
         _) =
        runTypeChecker(
            [
                "struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nfunc f() -> S { return t }",
            ]
        )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test func voidFunctionCannotReturnValue() {
    let (context,
         _) =
        runTypeChecker(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nfunc f() { return s }"])
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func someTypeProducesVariableWithConstraint() throws {
    let (context,
         programs) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: some P = s"]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let variable = try #require(variableDecl.symbol?.type as? TrussType.TypeVariableType)
    #expect(variable.binding is TrussType.StructType)
}

@Test func someTypeOnFunctionReturn() {
    let (context,
         _) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nfunc f() -> some P { makeS() }"]
        )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func anyTypeDereferencesToProtocol() throws {
    let (context,
         programs) =
        runTypeChecker(
            ["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: any P = s"]
        )
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = try #require(programs[0].statements[4] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.ProtocolType)
}

@Test func someTypeDereferencesToProtocolOnAnnotation() throws {
    let (_, programs) = runTypeChecker(["protocol P {}\nlet x: any P"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ProtocolType)
}

@Test func tupleElementsCheckedAgainstExpected() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }\nfunc makeS() -> S { S() }\nfunc makeT() -> T { T() }\nlet s = makeS()\nlet t = makeT()\nlet x: (S, S) = (s, t)",
        ]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test func closureReturnTypeChecked() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet f: () -> S = { () in t }",
        ]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test func missingMemberReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = s.unknown"]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("type 'S' has no member 'unknown'"))
}

@Test func undefinedVariableReportsError() {
    let (context, _) = runTypeChecker(["let x = unknown"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find 'unknown' in this scope"))
}

@Test func sequentialExpressionReportsUnknownOperator() {
    let (context, _) = runTypeChecker(["func main() { 1 + 2 }"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("operator '+' has no function declaration"))
}

@Test func wrongTypeArgumentCountReportsError() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id<S, S>(s)",
        ]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("wrong number of type arguments: expected 1, got 2"))
}

@Test func tryExpressionPassesThrough() throws {
    let (context, programs) = runTypeChecker(
        ["struct S { init() {} }\nfunc f() throws -> S { S() }\nfunc main() { let x = try f() }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
    let functionDecl = try #require(programs[0].statements[2] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func shorthandArgumentTypeFromExpected() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc main() { let f: (S) -> S = { $0 } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func selfKeywordTypeIsEnclosing() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func f() -> S { Self } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathExpressionInferred() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S }\nfunc main() { let kp = \\S.x }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func keyPathWithoutRootReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S }\nfunc main() { let kp = \\.x }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func voidLiteralType() throws {
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

@Test func genericApplicationValueType() throws {
    let (context, programs) = runTypeChecker(
        ["struct Box<T> { init() {} }\nstruct S { init() {} }\nfunc main() { let b = Box<S> }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
    let functionDecl = try #require(programs[0].statements[2] as? AST.FunctionDecl)
    let body = try #require(functionDecl.body)
    guard case let .Block(statements) = body else {
        Issue.record("expected block body")
        return
    }
    let variableDecl = try #require(statements[0] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.GenericInstantiation)
}

@Test func genericFunctionConstraintViolationReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nfunc f<T: P>(x: T) {}\nfunc main() { f(x: S()) }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func genericFunctionConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S: P { init() {} }\nfunc f<T: P>(x: T) {}\nfunc main() { f(x: S()) }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericTypeArgumentConstraintViolationReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S {}\nstruct Box<T: P> { init() {} }\nlet b: Box<S>"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func genericTypeArgumentConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S: P {}\nstruct Box<T: P> { init() {} }\nlet b: Box<S>"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericTypeWhereClauseConstraintChecked() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S {}\nstruct Box<T> where T: P { init() {} }\nlet b: Box<S>"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func genericParameterBodyMemberAccess() {
    let (context, _) = runTypeChecker(
        [
            "protocol P { func pm() }\nstruct S: P { init() {} func pm() {} }",
            "func f<T: P>(x: T) { x.pm() }\nfunc main() { f(x: S()) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericParameterConformsToDeclaredProtocol() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nprotocol Q {}\nfunc f<T: P>(x: T) { let y: P = x }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericParameterViolatesOtherProtocol() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nprotocol Q {}\nfunc f<T: P>(x: T) { let y: Q = x }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func genericTypeEqualityConstraintChecked() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nstruct T {}\nstruct W<A, B> where A == B { init() {} }\nlet w: W<S, T>"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func genericTypeEqualityConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nstruct W<A, B> where A == B { init() {} }\nlet w: W<S, S>"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericParameterCompositionConstraintSatisfied() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P, Q { init() {} }",
            "func f<T: P & Q>(x: T) {}\nfunc main() { f(x: S()) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericParameterCompositionConstraintViolated() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P { init() {} }",
            "func f<T: P & Q>(x: T) {}\nfunc main() { f(x: S()) }",
        ]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func multipleGenericParameterConstraints() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P { init() {} }\nstruct T: Q { init() {} }",
            "func f<A: P, B: Q>(x: A, y: B) {}\nfunc main() { f(x: S(), y: T()) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericConstraintViolationKeepsNonGenericOverload() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nstruct S { init() {} }\nstruct T: P { init() {} }",
            "func f<A: P>(x: A) -> A { x }\nfunc f(x: S) -> S { x }",
            "func main() { let a = f(x: S()); let b = f(x: T()) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedGenericInstantiationConstraintChecked() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nstruct S: P { init() {} }\nstruct T { init() {} }",
            "struct Box<A: P> { init() {} }",
            "let good: Box<Box<S>>\nlet bad: Box<Box<T>>",
        ]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func genericBodyReturnsParameter() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nstruct S: P { init() {} }",
            "func f<T: P>(x: T) -> T { x }",
            "func main() { let a = f(x: S()) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func forwardModuleFunctionCallMatches() {
    let (context, _) = runTypeChecker(
        ["func f() { M.g() }\nmodule M { func g() {} }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func matchEnumCaseMatches() {
    let (context, _) = runTypeChecker(
        ["enum E { case a; case b }\nfunc f(e: E) { match e { .a => { 1 } .b => { 2 } } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func matchPatternResolvesCaseSymbol() throws {
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

@Test func matchUnknownCaseReportsError() { let (context, _) = runTypeChecker(
    ["enum E { case a }\nfunc f(e: E) { match e { .c => 1 } }"]
)
#expect(context.diagnositicEngine.hasErrors)
}

@Test func matchAssociatedValueBindsPatternType() throws {
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

@Test func matchAssociatedValueCountMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum R { case ok(S) }\nfunc f(r: R) { match r { .ok() => 1 } }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func matchNonEnumSubjectReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { match s { .a => 1 } }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func matchImplicitMemberExpressionReportsError() {
    let (context, _) = runTypeChecker(
        ["enum E { case a, b }\nfunc f(e: E) -> E { match e { .a => .b } }"]
    )
    let errors = context.diagnositicEngine.diagnostics.filter { $0.severity == .error }
    #expect(
        errors.contains {
            $0.message == "cannot infer type of implicit member access '.b'"
        }
    )
}

@Test func ifCaseEnumMatches() {
    let (context, _) = runTypeChecker(
        ["enum E { case a }\nfunc f(e: E) { if case .a = e {} }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func ifCaseNonEnumSubjectReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { if case .a = s {} }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func caseBindingTypeAnnotationChecked() {
    let (context, _) = runTypeChecker(
        [
            "enum E { case a }\nstruct S { init() {} }\nstruct T { init() {} }",
            "func f(e: E, t: T) { if case let x: T = e { x } }",
        ]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func forCasePatternChecked() {
    let (context, _) = runTypeChecker(
        ["enum E { case a }\nfunc f(es: E) { for case .a in es {} }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func enumRawValueMatchesRawType() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E: S { case a = s }\nlet s = S()"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func enumRawValueMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nenum E: S { case a = t }\nlet t = T()"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func throwMatchesThrowsTypes() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) { throw E1() }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func throwMismatchReportsError() {
    let (context, _) = runTypeChecker(
        [
            "struct E1 { init() {} }\nstruct E2 { init() {} }",
            "func f() throws(E1) { throw E2() }",
        ]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func throwInNonThrowingFunctionReportsError() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() { throw E1() }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func doCatchPatternAndWhereChecked() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) { do { throw E1() } catch let e where true { () } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func optionalChainingOnNonOptionalReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S }\nlet s = S()\nlet w = s?.x"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func setterAccessorDoesNotCheckReturnType() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} var x: S { get { S() } set { () } } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericInitDeclaredAsForall() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct Box<T> { init() {} }\nlet b = Box<S>()"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nonGenericOverloadPreferredOverGeneric() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nfunc f<T>(x: T) -> T { x }\nfunc f(x: S) -> S { x }\nfunc main() { let a = f(x: S()) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedTypeGenericApplication() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nlet b: Outer.Inner<S>"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func throwingCallWithoutTryReportsError() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) {}\nfunc main() { f() }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func throwingCallWithTryPasses() {
    let (context, _) = runTypeChecker(
        ["struct E1 { init() {} }\nfunc f() throws(E1) {}\nfunc main() { try f() }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func forInBindingPatternResolvedInBody() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { for let x in s { x } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func forBodyLocalScope() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { for x in s { let y = x; y } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func localLetWithoutInitializerReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f() { let x: S }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func localVarWithoutInitializerAllowed() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f() { var x: S }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func topLevelLetWithoutInitializerAllowed() {
    let (context, _) = runTypeChecker(["struct S { init() {} }\nlet x: S"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func multiGenericOverloadConstraintSelection() {
    let (context, _) = runTypeChecker(
        [
            "protocol P {}\nprotocol Q {}",
            "struct S: P { init() {} }\nstruct T: Q { init() {} }",
            "func f<A: P>(x: A) -> A { x }\nfunc f<B: Q>(x: B) -> B { x }",
            "func main() { let t = T(); let r = f(x: t) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func missingProtocolWitnessReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P { func pm() }\nstruct S: P { init() {} }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func implementedProtocolWitnessPasses() {
    let (context, _) = runTypeChecker(
        ["protocol P { func pm() }\nstruct S: P { init() {} func pm() {} }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func inheritedProtocolWitnessChecked() {
    let (context, _) = runTypeChecker(
        ["protocol P1 { func pm() }\nprotocol P2: P1 {}\nstruct S: P2 { init() {} }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func superclassProvidesWitness() {
    let (context, _) = runTypeChecker(
        [
            "protocol P { func pm() }\nclass B: P { init() {} func pm() {} }",
            "class C: B, P { init() {} }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func missingAssociatedTypeWitnessReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nprotocol P { associatedtype T }\nstruct C: P { init() {} }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func associatedTypeWitnessViaTypealias() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nprotocol P { associatedtype T }\nstruct C: P { init() {} typealias T = S }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func instanceMethodCallResolved() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func pm() -> S { self } }\nfunc f(s: S) { let a = s.pm() }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func instanceMethodCallWithArguments() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func pm(a: S, b: S) -> S { a } }\nfunc f(s: S) { let r = s.pm(a: s, b: s) }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func instanceMethodCallThroughOptionalChain() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} func pm() -> S { self } }\nfunc f(z: S?) { let a = z?.pm() }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func instanceMethodOverloadResolution() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }",
            "struct R { init() {} func f(x: S) -> S { x } func f(x: T) -> T { x } }",
            "func g(r: R, s: S) { let a = r.f(x: s) }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func rawValueWithoutRawTypeReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nenum E: P { case a = s }\nlet s = S()"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func rawValueWithTypeInComposition() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nenum E: P & S { case a = s }\nlet s = S()"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func rawValueWithProtocolOnlyCompositionReportsError() {
    let (context, _) = runTypeChecker(
        ["protocol P1 {}\nprotocol P2 {}\nstruct S { init() {} }\nenum E: P1 & P2 { case a = s }\nlet s = S()"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func mixedCompositionWithGenericMember() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S { init() {} }\nstruct W<T> { init() {} }\nlet x: W<S> & P"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedEnumWithoutRawTypeDoesNotLeakOuter() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum A: S { enum B { case x = s } case y = s }\nlet s = S()"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func nestedEnumWithOwnRawTypes() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum A: S { enum B: S { case x = s } case y = s }\nlet s = S()"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func valueBitAndNotFoldedAsComposition() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(a: S, b: S) { let c = a & b }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func valueBitAndWithDeclaredOperator() {
    let (context, _) = runTypeChecker(
        [
            "precedencegroup G {}\ninfix operator &: G",
            "struct S { init() {} }\nfunc &(lhs: S, rhs: S) -> S { lhs }",
            "func f(a: S, b: S) { let c = a & b }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func tryQuestionWrapsResultInOptional() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nstruct E1 { init() {} }\nfunc f() throws(E1) -> S { S() }\nlet x = try? f()"]
    )
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.OptionalType)
}

@Test func tryExclamationKeepsPlainType() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nstruct E1 { init() {} }\nfunc f() throws(E1) -> S { S() }\nlet x = try! f()"]
    )
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.StructType)
}

@Test func nestedTypeGenericInitCall() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nfunc main() { let b = Outer.Inner<S>() }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedTypeGenericInitWithMultipleArguments() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct T { init() {} }\nstruct Outer { struct Inner<A, B> { init() {} } }\nfunc main() { let b = Outer.Inner<S, T>() }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedTypeAsGenericArgument() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct W<T> { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nlet x: W<Outer.Inner<S>>",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedTypeGenericArgumentOnValuePosition() {
    let (context, _) = runTypeChecker(
        [
            "struct S { init() {} }\nstruct W<T> { init() {} }\nstruct Outer { struct Inner<T> { init() {} } }\nlet x = W<Outer.Inner<S>>",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func castInstanceToProtocolConforms() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nstruct S: P { init() {} }\nfunc main() { let s = S(); let x = s as P }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func castInstanceToUnrelatedTypeReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nfunc main() { let s = S(); let x = s as T }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func castInstanceToCompositionConforms() {
    let (context, _) = runTypeChecker(
        ["protocol P {}\nprotocol Q {}\nstruct S: P, Q { init() {} }\nfunc main() { let s = S(); let x = s as P & Q }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func bitCastAcceptsUnrelatedTypes() throws {
    let (_, programs) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nlet s = S()\nlet x = s as!! T"]
    )
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let cast = try #require(variableDecl.initializer as? AST.Cast)
    #expect(cast.kind == .AsBitCast)
    #expect(cast.ty is TrussType.StructType)
}

@Test func forceUnwrapOptional() throws {
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

@Test func forceUnwrapNonOptionalReportsError() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nfunc f(s: S) { let x = s! }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func catchMatchesSecondThrowsType() {
    let (context, _) = runTypeChecker(
        ["struct E1 {}\nstruct E2 {}\nfunc f() throws(E1, E2) {}\nfunc g() { do { try f() } catch E2 { } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func catchMismatchReportsError() {
    let (context, _) = runTypeChecker(
        ["struct E1 {}\nstruct E2 {}\nstruct T {}\nfunc f() throws(E1, E2) {}\nfunc g() { do { try f() } catch T { } }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func catchMatchesFirstThrowsType() {
    let (context, _) = runTypeChecker(
        ["struct E1 {}\nstruct E2 {}\nfunc f() throws(E1, E2) {}\nfunc g() { do { try f() } catch E1 { } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func matchVariableCalleeCasePattern() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E { case foo(S) }\nfunc f(e: E) { match e { foo(let x) => { x } } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func matchBareCaseNamePattern() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E { case foo(S) }\nfunc f(e: E) { match e { foo(let x) => { x } } }"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func matchBareCaseNameArgumentCountChecked() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nenum E { case foo(S) }\nfunc f(e: E) { match e { foo() => { S() } } }"]
    )
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func assignmentDoesNotRequireOperatorFunction() {
    let (context, _) = runTypeChecker(
        [
            "precedencegroup Assignment { assignment: true }\ninfix operator =: Assignment\nstruct TT { init() {} }\nstruct TS { var x: TT = TT() var y: TT = TT() init() {} }\nfunc f(s: TS) -> TT { s.y = TT() return s.x }",
        ]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func assignmentMismatchReportsExpectedFound() {
    let (context, _) = runTypeChecker(
        [
            "precedencegroup Assignment { assignment: true }\ninfix operator =: Assignment\nstruct TT { init() {} }\nstruct UU { init() {} }\nstruct TS { var y: TT = TT() init() {} }\nfunc f(s: TS, u: UU) { s.y = u }",
        ]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'TT', found 'UU'"))
}

@Test func implicitReturnTypeChecked() {
    let (context, _) = runTypeChecker(
        ["struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { T() }"]
    )
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("expected 'S'") })
}

@Test func pointerTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(
        ["struct Int {} \nlet p: Int*"]
    )
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type as? TrussType.PointerType)
    #expect(type.pointee is TrussType.StructType)
    #expect(!type.isNonnull)
}

@Test func nonnullPointerTypeAnnotation() throws {
    let (_, programs) = runTypeChecker(
        ["struct Int {} \nlet p: Int*!"]
    )
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type as? TrussType.PointerType)
    #expect(type.pointee is TrussType.StructType)
    #expect(type.isNonnull)
}

@Test func nullptrRejectsNonnullPointer() {
    let (context, _) = runTypeChecker(
        ["struct Int {} \n"
            + "func f() {\n    var n: Int*! = nullptr\n}"]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("nullptr cannot be used with non-null pointer type") })
    #expect(!messages.contains { $0.hasPrefix("expected 'Int*!'") })
}

@Test func nullptrRequiresPointerType() {
    let (context, _) = runTypeChecker(
        ["struct Int {} \n"
            + "func f() {\n    var x: Int = nullptr\n}"]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("nullptr requires a pointer type") })
}

@Test func nonnullPointerAcceptsNullableAssignment() {
    let (context, _) = runTypeChecker(
        ["struct Int {} \n"
            + "func f() {\n    var v: Int\n"
            + "    var p: Int*! = &v\n"
            + "    var q: Int* = p\n}"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func pointerDereferenceAndMember() {
    let (context, _) = runTypeChecker(
        [pointerPrelude
            + "struct Point {\n    var x: Int\n    var y: Int\n}\n"
            + "func f() {\n    var pt: Point\n    var pp: Point* = &pt\n"
            + "    var a = (*pp).x\n    var b = *pp\n    var i = pp[0]\n"
            + "    if pp != nullptr {\n        var c = (*pp).y\n    }\n"
            + "    var nn: Point*! = pp!\n}"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func dereferenceNonPointerReportsError() {
    let (context, _) = runTypeChecker(
        ["struct Int {} \n"
            + "func f() {\n    var v: Int\n    var x = *v\n}"]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("cannot dereference non-pointer type") })
}

@Test func pointerArithmeticAndComparison() {
    let (context, _) = runTypeChecker(
        [pointerPrelude
            + "func f() {\n    var v: Int\n    var p: Int* = &v\n"
            + "    var s = p + 1\n    var d = (p + 2) - p\n"
            + "    var eq = p == p\n    var lt = p < p\n}"]
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func pointerArithmeticRequiresDeclaredOperator() {
    let (context, _) = runTypeChecker(
        ["struct Int {} \n"
            + "func f() {\n    var v: Int\n    var p: Int* = &v\n    var x = p + p\n}"]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("unknown operator '+'") })
}

@Test func addressOfNonLValueReportsError() {
    let (context, _) = runTypeChecker(
        ["struct Int {} \n"
            + "func f() {\n    var x = &42\n}"]
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("cannot take address of non-lvalue") })
}

@Test func useBeforeDefinitionInInitInfersType() throws {
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

@Test func useBeforeDefinitionWithoutAnnotationInFunctionInfersType() throws {
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

@Test func declarationBeforeUseStillInfersType() throws {
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

@Test func typeUseBeforeDeclarationInfersType() throws {
    let (_, programs) = runTypeChecker(["let tt = TT()\nstruct TT { init() {} }"])
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let ttType = try #require(variableDecl.symbol?.type)
    #expect(ttType is TrussType.GenericInstantiation)
    let structDecl = try #require(programs[0].statements[1] as? AST.StructDecl)
    let initDecl = try #require(structDecl.body[0] as? AST.InitDecl)
    let initType = try #require(initDecl.symbol?.functionType)
    #expect(initType.parameters.isEmpty)
}

@Test func functionCallBeforeDeclarationInfersType() throws {
    let (_, programs) = runTypeChecker([
        "let g = makeG()\nstruct Int32 { init() {} }\nfunc makeG() -> Int32 { Int32() }",
    ])
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type)
    #expect(type is TrussType.StructType)
}

@Test func integerLiteralInfersToInt64() throws {
    let (context, programs) = runTypeChecker(["let v = 42"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int64")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func floatLiteralInfersToFloat64() throws {
    let (context, programs) = runTypeChecker(["let v = 3.14"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Float64")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func boolLiteralInfersToBool() throws {
    let (context, programs) = runTypeChecker(["let v = true"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Bool")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func integerLiteralMatchesInt64Annotation() throws {
    let (context, programs) = runTypeChecker(["let v: Builtin.Int64 = 42"], installBuiltin: true)
    let variableDecl = try #require(programs[0].statements[0] as? AST.VariableDecl)
    let type = try #require(variableDecl.symbol?.type as? TrussType.BuiltinType)
    #expect(type.name == "Int64")
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func ifConditionRequiresBool() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nfunc f(x: S) {\n    if x {\n    }\n}"],
        installBuiltin: true
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("expected 'Builtin.Bool'") })
}

@Test func ifBoolLiteralConditionPasses() {
    let (context, _) = runTypeChecker(["func f() {\n    if true {\n    }\n}"], installBuiltin: true)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func ifBoolVariableConditionPasses() {
    let (context, _) = runTypeChecker(
        ["func f(b: Builtin.Bool) {\n    if b {\n    }\n}"],
        installBuiltin: true
    )
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func whileConditionRequiresBool() {
    let (context, _) = runTypeChecker(
        ["struct S {}\nfunc f(x: S) {\n    while x {\n    }\n}"],
        installBuiltin: true
    )
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains { $0.contains("expected 'Builtin.Bool'") })
}
