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

@Test func noBuiltinTypeLeavesNil() {
    let (_, programs) = runTypeResolver(["let x: Int32"])
    let variableDecl = programs[0].statements[0] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type == nil)
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

@Test func unresolvableReturnAnnotationIsNil() throws {
    let (_, programs) = runTypeResolver(["func f() -> Int32 {}"])
    let functionDecl = programs[0].statements[0] as! AST.FunctionDecl
    let functionType = try #require(functionDecl.symbol?.functionType)
    #expect(functionType.returnType == nil)
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

@Test func typealiasCycleResolvesToNil() throws {
    let (_, programs) = runTypeResolver(["typealias A = B\ntypealias B = A\nlet x: A"])
    let variableDecl = programs[0].statements[2] as! AST.VariableDecl
    #expect(variableDecl.symbol?.type == nil)
    let aSymbol = (programs[0].statements[0] as! AST.TypeAliasDecl).symbol
    let bSymbol = (programs[0].statements[1] as! AST.TypeAliasDecl).symbol
    #expect(aSymbol?.targetType == nil)
    #expect(bSymbol?.targetType == nil)
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
