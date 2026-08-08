import Testing
import TrussCore
import TrussSemantics

@Test func variableAnnotationType() throws {
    let (context, programs) = runTypeResolver(["struct S {}\nlet x: S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let symbol = try #require(variableDecl.symbol)
    let type = try #require(symbol.type)
    #expect(type is TrussType.StructType)
    let typeId = try #require((programs[0].statements[0] as! AST.StructDecl).symbol?.typeId)
    #expect(type as AnyObject === context.typeTable[typeId] as AnyObject)
}

@Test func noAnnotationLeavesTypeNil() {
    let (_, programs) = runTypeResolver(["func f() {}\nlet x = f()"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type == nil)
}

@Test func noBuiltinTypeIsErrorType() {
    let (context, programs) = runTypeResolver(["let x: Int32"])
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ErrorType)
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int32'"))
}

@Test func moduleMemberTypeAnnotation() throws {
    let (_, programs) = runTypeResolver(["module M {\n    struct A {}\n}\nlet x: M.A"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "A")
}

@Test func nestedTypeAnnotation() throws {
    let (_, programs) = runTypeResolver([
        "struct Outer {\n    struct Inner {}\n}\nlet x: Outer.Inner",
    ])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "Inner")
}

@Test func optionalAnnotation() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nlet x: S?"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let optional = try #require(variableDecl.symbol?.type as? TrussType.OptionalType)
    #expect(optional.wrapped is TrussType.StructType)
}

@Test func tupleAnnotationWithLabels() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nstruct T {}\nlet x: (a: S, T)"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let tuple = try #require(variableDecl.symbol?.type as? TrussType.TupleType)
    #expect(tuple.elements.count == 2)
    #expect(tuple.elements[0].label == "a")
    #expect(tuple.elements[0].type is TrussType.StructType)
    #expect(tuple.elements[1].label == nil)
}

@Test func functionTypeAnnotation() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nlet f: (S) async throws -> S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let function = try #require(variableDecl.symbol?.type as? TrussType.FunctionType)
    #expect(function.parameters.count == 1)
    #expect(function.isAsync)
    #expect(function.isThrowing)
    #expect(function.returnType is TrussType.StructType)
}

@Test func declaredFunctionType() throws {
    let (_, programs) = runTypeResolver([
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
    let (_, programs) = runTypeResolver(["func f() {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.returnType is TrussType.VoidType)
}

@Test func unresolvableReturnAnnotationIsErrorType() throws {
    let (context, programs) = runTypeResolver(["func f() -> Int32 {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.returnType is TrussType.ErrorType)
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("cannot find type 'Int32'"))
}

@Test func initFunctionTypeReturnsVoid() throws {
    let (_, programs) = runTypeResolver(["struct S {\n    init(x: S) {\n    }\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let initDecl = try #require(structDecl.body.first as? AST.InitDecl)
    let functionType = try #require(initDecl.symbol?.functionType)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.returnType is TrussType.VoidType)
}

@Test func subscriptFunctionTypeReturnsElement() throws {
    let (_, programs) = runTypeResolver(["struct S {\n    subscript(i: S) -> S {\n    }\n}"])
    let structDecl = programs[0].statements[0] as! AST.StructDecl
    let subscriptDecl = try #require(structDecl.body.first as? AST.SubscriptDecl)
    let functionType = try #require(subscriptDecl.symbol?.functionType)
    #expect(functionType.parameters.count == 1)
    #expect(functionType.returnType is TrussType.StructType)
}

@Test func typealiasTargetType() throws {
    let (context, programs) = runTypeResolver(["struct S {}\ntypealias T = S"])
    let typeAliasDecl = programs[0].statements[1] as! AST.TypeAliasDecl
    let symbol = try #require(typeAliasDecl.symbol)
    let target = try #require(symbol.targetType)
    let typeId = try #require((programs[0].statements[0] as! AST.StructDecl).symbol?.typeId)
    #expect(target as AnyObject === context.typeTable[typeId] as AnyObject)
}

@Test func typealiasChainDereferences() throws {
    let (_, programs) = runTypeResolver(["struct S {}\ntypealias T = S\ntypealias U = T\nlet x: U"])
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    let type = try #require(variableDecl.symbol?.type)
    #expect((type as! TrussType.StructType).name == "S")
}

@Test func typealiasCycleIsErrorType() {
    let (context, programs) = runTypeResolver(["typealias A = B\ntypealias B = A\nlet x: A"])
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
    let (_, programs) = runTypeResolver(["struct S {}\nlet cl = { (x: S) -> S in x }"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let closure = try #require(variableDecl.initializer as? AST.Closure)
    let function = try #require(closure.ty as? TrussType.FunctionType)
    #expect(function.parameters.count == 1)
    #expect(function.parameters[0].type is TrussType.StructType)
    #expect(function.returnType is TrussType.StructType)
}

@Test func variadicParameterType() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nfunc f(xs: S...) {}"])
    let functionDecl = programs[0].statements[1] as! AST.FunctionDecl
    let symbol = try #require(functionDecl.symbol)
    let variadic = try #require(
        symbol.functionType?.parameters.first?.type as? TrussType.VariadicType)
    #expect(variadic.base is TrussType.StructType)
}

@Test func compositionAnnotation() throws {
    let (_, programs) = runTypeResolver(["protocol P {}\nprotocol Q {}\nlet x: P & Q"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let composition = try #require(variableDecl.symbol?.type as? TrussType.CompositionType)
    #expect(composition.members.count == 2)
    #expect(composition.members[0] is TrussType.ProtocolType)
}

@Test func enumAssociatedValueType() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nenum E {\n    case a(x: S)\n}"])
    let enumDecl = programs[0].statements[1] as! AST.EnumDecl
    let caseDecl = try #require(enumDecl.body.first as? AST.EnumCaseDecl)
    let typeExpression = caseDecl.elements[0].associatedValues[0].typeExpression
    #expect(typeExpression.ty is TrussType.StructType)
}

@Test func castRightTypeOnly() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nlet x = y as S"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let cast = try #require(variableDecl.initializer as? AST.CastExpression)
    #expect(cast.right.ty is TrussType.StructType)
    #expect(cast.ty == nil)
}

@Test func callTypeNotResolved() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nfunc f() -> S {}\nlet x: S = f()"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(call.ty == nil)
}

@Test func variableReferenceNotPropagated() throws {
    let (_, programs) = runTypeResolver(["struct S {}\nlet x: S\nlet y = x"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    let variable = try #require(variableDecl.initializer as? AST.Variable)
    #expect(variable.ty == nil)
}

@Test func voidNeverAnnotations() throws {
    let (_, programs) = runTypeResolver(["let x: Void\nlet y: Never"])
    let voidDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(voidDecl.symbol?.type is TrussType.VoidType)
    let neverDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(neverDecl.symbol?.type is TrussType.NeverType)
}

@Test func matchingAssignmentPasses() {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: S = s"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func mismatchedAssignmentReportsError() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet x: S = t"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test func optionalPromotion() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: S? = s"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func subclassAssignment() {
    let (context, _) = runTypeResolver(["class Base { init() {} }\nclass Derived: Base { init() {} }\nfunc makeDerived() -> Derived { Derived() }\nlet d = makeDerived()\nlet b: Base = d"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func neverConvertsToAnyType() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nfunc makeNever() -> Never { }\nlet n = makeNever()\nlet x: S = n"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func conformancePromotion() {
    let (context, _) = runTypeResolver(["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: P = s"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func conformanceMismatchReportsError() {
    let (context, _) = runTypeResolver(["protocol P {}\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nlet x: P = t"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'P', found 'T'"))
}

@Test func overloadResolutionByExpectedReturn() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { S() }\nfunc f() -> T { T() }\nlet x: S = f()"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let call = try #require(variableDecl.initializer as? AST.Call)
    #expect(call.symbol?.name == "f")
}

@Test func overloadNoMatchReportsError() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nstruct T { init() {} }\nfunc f(x: S) {}\nfunc f(x: T) {}\nfunc makeT() -> T { T() }\nf(makeT())"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("no exact matches in call to 'f'") }))
}

@Test func overloadAmbiguousReportsError() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nstruct T { init() {} }\nfunc f() -> S { S() }\nfunc f() -> T { T() }\nlet g = f()"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("ambiguous use of 'f'") }))
}

@Test func genericFunctionTypeIsForall() throws {
    let (_, programs) = runTypeResolver(["struct S { init() {} }\nfunc id<T>(x: T) -> T { x }"])
    let functionDecl = programs[0].statements[1] as! AST.FunctionDecl
    let forall = try #require(functionDecl.symbol?.forallType)
    #expect(forall.parameters.count == 1)
    #expect(forall.parameters[0].name == "T")
    #expect(forall.body is TrussType.FunctionType)
}

@Test func genericFunctionImplicitInstantiation() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id(s)"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func genericFunctionExplicitInstantiation() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nfunc id<T>(x: T) -> T { x }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet a = id<S>(s)"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func genericStructMember() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nstruct Box<T> { init(v: T) {} var value: T }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet b = Box(v: s)\nlet v = b.value"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[5] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func closureParameterFromExpectedType() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nlet f: (S) -> S = { x in x }"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    let function = try #require(variableDecl.symbol?.type as? TrussType.FunctionType)
    #expect(function.parameters.count == 1)
    #expect(function.parameters[0].type is TrussType.StructType)
    #expect(function.returnType is TrussType.StructType)
}

@Test func closureWithoutContextReportsError() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nlet f = { x in x }"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains(where: { $0.contains("requires an explicit type annotation") }))
}

@Test func memberAccessOnInstance() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} var x: S }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet y = s.x"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func optionalChainingMemberAccess() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} var x: S }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet z: S? = s\nlet w = z?.x"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let optional = try #require(variableDecl.symbol?.type as? TrussType.OptionalType)
    #expect(optional.wrapped is TrussType.StructType)
}

@Test func ifElseJoinProducesBranchType() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = if true { s } else { s }"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.StructType)
}

@Test func ifElseMismatchedBranchesReportError() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nstruct T { init() {} }\nfunc makeS() -> S { S() }\nfunc makeT() -> T { T() }\nlet s = makeS()\nlet t = makeT()\nlet x = if true { s } else { t }"])
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func ifWithoutElseIsVoid() throws {
    let (context, programs) = runTypeResolver(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x = if true { s }"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[3] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.VoidType)
}

@Test func literalAdaptsToAnyAnnotation() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nlet x: S = 1"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func functionReturnTypeChecked() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nstruct T { init() {} }\nfunc makeT() -> T { T() }\nlet t = makeT()\nfunc f() -> S { return t }"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("expected 'S', found 'T'"))
}

@Test func voidFunctionCannotReturnValue() {
    let (context, _) = runTypeResolver(["struct S { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nfunc f() { return s }"])
    #expect(context.diagnositicEngine.hasErrors)
}

@Test func someTypeProducesVariableWithConstraint() throws {
    let (context, programs) = runTypeResolver(["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: some P = s"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = programs[0].statements[4] as! AST.VariableDecl
    let variable = try #require(variableDecl.symbol?.type as? TrussType.TypeVariableType)
    #expect(variable.binding is TrussType.StructType)
}

@Test func someTypeOnFunctionReturn() {
    let (context, _) = runTypeResolver(["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nfunc f() -> some P { makeS() }"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func anyTypeDereferencesToProtocol() throws {
    let (context, programs) = runTypeResolver(["protocol P {}\nstruct S: P { init() {} }\nfunc makeS() -> S { S() }\nlet s = makeS()\nlet x: any P = s"])
    #expect(!context.diagnositicEngine.hasErrors)
    let variableDecl = try #require(programs[0].statements[4] as? AST.VariableDecl)
    #expect(variableDecl.symbol?.type is TrussType.ProtocolType)
}

@Test func someTypeDereferencesToProtocolOnAnnotation() throws {
    let (_, programs) = runTypeResolver(["protocol P {}\nlet x: any P"])
    let variableDecl = programs[0].statements[1] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type is TrussType.ProtocolType)
}
