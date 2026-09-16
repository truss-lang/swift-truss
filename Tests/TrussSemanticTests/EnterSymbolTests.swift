import Testing
import TrussCore

@Test func crossFileExtensionCycle() {
    let (context, programs) = runEnter([
        "struct A {} extension B { func useA() {} }",
        "struct B {} extension A { func useB() {} }",
    ])
    let packageScope = programs[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = packageScope.types["B"] as! Symbol.NominalTypeSymbol
    #expect(a.scope.values["useB"] != nil)
    #expect(b.scope.values["useA"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func pendingNestedExtensionConvergence() throws {
    let (context, program) = runEnter([
        "struct A {} extension A.B { class C {} } extension A { class B {} }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = a.scope.types["B"] as? Symbol.NominalTypeSymbol
    try #require(b != nil)
    let c = b!.scope.types["C"] as? Symbol.NominalTypeSymbol
    #expect(c != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func deepNestingAcrossFiles() throws {
    let (context, programs) = runEnter([
        "class A {}",
        "extension A { class B { let c: C } }",
        "extension A.B { class C {} }",
    ])
    let packageScope = programs[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = a.scope.types["B"] as? Symbol.NominalTypeSymbol
    try #require(b != nil)
    #expect(b!.scope.values["c"] != nil)
    let c = b!.scope.types["C"] as? Symbol.NominalTypeSymbol
    #expect(c != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionMemberLandsInBaseScope() {
    let (context, program) = runEnter(["struct S {} extension S { func f() {} }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    #expect(s.scope.values["f"] != nil)
    #expect(packageScope.values["f"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func memberFunctionAndLocals() throws {
    let (context, program) = runEnter(["struct S { func m() { var x = 1 } }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let m = s.scope.values["m"]?.first as? Symbol.FunctionSymbol
    try #require(m != nil)
    #expect(m!.scope.values["x"] != nil)
    #expect(packageScope.values["m"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func typeRedeclarationConflict() {
    let (context, _) = runEnter(["struct A {} struct A {}"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of type 'A'"))
}

@Test func typeRedeclarationAcrossFiles() {
    let (context, _) = runEnter(["struct A {}", "class A {}"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of type 'A'"))
}

@Test func extensionMemberKindConflictAtMerge() {
    let (context, _) = runEnter([
        "struct A {} extension A { var v: Int } extension A { var v: Int }",
    ])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of 'v'"))
}

@Test func functionVariableKindConflict() {
    let (context, _) = runEnter(["func f() {} var f: Int"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of 'f'"))
}

@Test func overloadedFunctionsAllowed() {
    let (context, program) = runEnter(["func f() {} func f(x: Int) {}"])
    let packageScope = program[0].packageSymbol!.scope
    let symbols = packageScope.values["f"]
    #expect(symbols?.count == 2)
    #expect(symbols?.allSatisfy { $0 is Symbol.FunctionSymbol } == true)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionBaseNotFound() {
    let (context, _) = runEnter(["extension NotFound { func f() {} }"])
    #expect(context.diagnositicEngine.hasErrors)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("extension of type 'NotFound' has no matching declaration"))
}

@Test func caseSymbols() {
    let (context, program) = runEnter(["enum E { case a, b(Int32) }"])
    let packageScope = program[0].packageSymbol!.scope
    let e = packageScope.types["E"] as! Symbol.NominalTypeSymbol
    #expect(e.scope.values["a"]?.first is Symbol.CaseSymbol)
    #expect(e.scope.values["b"]?.first is Symbol.CaseSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func genericParamsOnTypeAndFunction() {
    let (context, program) = runEnter([
        "struct S3<E, each T> {} func f<G>() {}",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s3 = packageScope.types["S3"] as! Symbol.NominalTypeSymbol
    #expect(s3.scope.types["E"] is Symbol.GenericParamSymbol)
    #expect(s3.scope.types["T"] is Symbol.GenericParamSymbol)
    let f = packageScope.values["f"]?.first as? Symbol.FunctionSymbol
    #expect(f?.scope.types["G"] is Symbol.GenericParamSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func initAndSubscriptSymbols() {
    let (context, program) = runEnter([
        "struct S { init() {} subscript(i: Int) -> Int { 0 } }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    #expect(s.scope.values["init"]?.first is Symbol.FunctionSymbol)
    #expect(s.scope.values["subscript"]?.first is Symbol.SubscriptSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func associatedTypeSymbol() {
    let (context, program) = runEnter(["protocol P { associatedtype T }"])
    let packageScope = program[0].packageSymbol!.scope
    let p = packageScope.types["P"] as! Symbol.NominalTypeSymbol
    #expect(p.scope.types["T"] is Symbol.AssociatedTypeSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func typealiasSymbol() {
    let (context, program) = runEnter(["typealias SS = (S) -> S struct S {}"])
    let packageScope = program[0].packageSymbol!.scope
    #expect(packageScope.types["SS"] is Symbol.TypeAliasSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func nestedTypeInExtension() throws {
    let (context, program) = runEnter([
        "struct A {} extension A { class B { class D {} } }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let b = a.scope.types["B"] as? Symbol.NominalTypeSymbol
    try #require(b != nil)
    #expect(b!.scope.types["D"] is Symbol.NominalTypeSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionInsideModuleResolvesInModuleScope() throws {
    let (context, program) = runEnter([
        "module M { struct T {} extension T { func f() {} } }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let m = packageScope.modules["M"]
    let t = m?.scope.types["T"] as? Symbol.NominalTypeSymbol
    try #require(t != nil)
    #expect(t!.scope.values["f"] != nil)
    #expect(packageScope.values["f"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func overloadedFunctionsAcrossExtensions() {
    let (context, program) = runEnter([
        "struct A {} extension A { func f() {} } extension A { func f(x: Int) {} }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let symbols = a.scope.values["f"]
    #expect(symbols?.count == 2)
    #expect(symbols?.allSatisfy { $0 is Symbol.FunctionSymbol } == true)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func deinitLocalsIsolatedFromTypeScope() {
    let (context, program) = runEnter(["class C { deinit { let x = 1 } }"])
    let packageScope = program[0].packageSymbol!.scope
    let c = packageScope.types["C"] as! Symbol.NominalTypeSymbol
    #expect(c.scope.values["x"] == nil)
    let classDecl = program[0].statements[0] as! AST.ClassDecl
    let deinitDecl = classDecl.body[0] as! AST.DeinitDecl
    #expect(deinitDecl.scope?.values["x"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func deinitLocalDoesNotConflictWithMember() {
    let (context, _) = runEnter(["class C { var x: Int deinit { let x = 1 } }"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func accessorLocalsAndImplicitParameterScoped() {
    let (context, program) = runEnter([
        "struct S { var x: Int { get { let t = 1; return t } set { x = newValue } } }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    #expect(s.scope.values["t"] == nil)
    #expect(s.scope.values["newValue"] == nil)
    let structDecl = program[0].statements[0] as! AST.StructDecl
    let varDecl = structDecl.body[0] as! AST.VariableDecl
    let setter = varDecl.accessors[1]
    #expect(setter.scope?.values["newValue"] != nil)
    let getter = varDecl.accessors[0]
    #expect(getter.scope?.values["t"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionWithModulePrefixBaseMerged() throws {
    let (context, program) = runEnter([
        "module M { struct T {} } extension M.T { func f() {} }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let t = packageScope.modules["M"]?.scope.types["T"] as? Symbol.NominalTypeSymbol
    try #require(t != nil)
    #expect(t!.scope.values["f"] != nil)
    #expect(packageScope.values["f"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func deinitInTypeBodyIsAllowed() {
    let (context, program) = runEnter(["class C { deinit {} }"])
    let packageScope = program[0].packageSymbol!.scope
    let c = packageScope.types["C"] as! Symbol.ClassSymbol
    #expect(c.deinitializer != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func deinitInExtensionIsError() {
    let (context, _) = runEnter(["class C {} extension C { deinit {} }"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("deinitializer is not allowed in an extension"))
}

@Test func extensionInitLandsInBaseInitializers() {
    let (context, program) = runEnter(["struct S {} extension S { init() {} }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.StructSymbol
    #expect(s.initializers.count == 1)
    #expect(s.scope.values["init"] != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func closureParameterGetsSymbol() throws {
    let (context, program) = runEnter(["struct S {}\nlet cl = { (x: S) -> S in x }"])
    let variableDecl = program[0].statements[1] as! AST.VariableDecl
    let closure = variableDecl.initializer as! AST.Closure
    let signature = try #require(closure.signature)
    let symbol = try #require(signature.parameters[0].symbol)
    #expect(symbol === closure.scope?.values["x"]?.first as? Symbol.VariableSymbol)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func instanceMethodSelfSymbol() throws {
    let (context, program) = runEnter(["struct S { func m() {} }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let m = try #require(s.scope.values["m"]?.first as? Symbol.FunctionSymbol)
    let selfSymbol = try #require(m.scope.values["self"]?.first as? Symbol.SelfSymbol)
    #expect(selfSymbol.name == "self")
    #expect(selfSymbol.kind == .Local)
    #expect(selfSymbol.type == nil)
    #expect(selfSymbol.memberOf == s.id)
    #expect(selfSymbol.sourceToken != nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func initDeinitSubscriptAndAccessorSelfSymbols() throws {
    let (context, program) = runEnter([
        """
        struct S {
            var a: Int { get { 0 } set { } }
            init() {}
            subscript(i: Int) -> Int { get { 0 } set { } }
        }
        class C { deinit {} }
        """,
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let c = packageScope.types["C"] as! Symbol.ClassSymbol

    let initSymbol = try #require(s.scope.values["init"]?.first as? Symbol.FunctionSymbol)
    let initSelf = try #require(initSymbol.scope.values["self"]?.first as? Symbol.SelfSymbol)
    #expect(initSelf.memberOf == s.id)

    let deinitSelf = try #require(c.deinitializer?.scope.values["self"]?.first as? Symbol.SelfSymbol)
    #expect(deinitSelf.memberOf == c.id)

    let subscriptSymbol = try #require(s.scope.values["subscript"]?.first as? Symbol.SubscriptSymbol)
    let getterSelf = try #require(
        subscriptSymbol.getter.scope.values["self"]?.first as? Symbol.SelfSymbol
    )
    let setter = try #require(subscriptSymbol.setter)
    let setterSelf = try #require(setter.scope.values["self"]?.first as? Symbol.SelfSymbol)
    #expect(getterSelf.id != setterSelf.id)
    #expect(getterSelf.memberOf == s.id)
    #expect(setterSelf.memberOf == s.id)

    let structDecl = program[0].statements[0] as! AST.StructDecl
    let variableDecl = structDecl.body[0] as! AST.VariableDecl
    let accessorSelfs = try variableDecl.accessors.map { accessor in
        try #require(accessor.scope?.values["self"]?.first as? Symbol.SelfSymbol)
    }
    #expect(accessorSelfs.count == 2)
    #expect(accessorSelfs[0].id != accessorSelfs[1].id)
    #expect(accessorSelfs.allSatisfy { $0.memberOf == s.id })
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionMethodSelfSymbolGetsMemberOf() throws {
    let (context, program) = runEnter(["struct S {} extension S { func f() {} }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let f = try #require(s.scope.values["f"]?.first as? Symbol.FunctionSymbol)
    let selfSymbol = try #require(f.scope.values["self"]?.first as? Symbol.SelfSymbol)
    #expect(f.kind == .Method)
    #expect(f.memberOf == s.id)
    #expect(selfSymbol.memberOf == s.id)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionStoredPropertyKind() throws {
    let (context, program) = runEnter(["struct S {} extension S { var v: Int }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let v = try #require(s.scope.values["v"]?.first as? Symbol.VariableSymbol)
    #expect(v.kind == .Property)
    #expect(v.memberOf == s.id)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionStaticPropertyKind() throws {
    let (context, program) = runEnter(["struct S {} extension S { static var s: Int }"])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let v = try #require(s.scope.values["s"]?.first as? Symbol.VariableSymbol)
    #expect(v.kind == .StaticProperty)
    #expect(v.memberOf == s.id)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func topLevelVariableStaysGlobal() throws {
    let (context, program) = runEnter(["var g: Int"])
    let packageScope = program[0].packageSymbol!.scope
    let g = try #require(packageScope.values["g"]?.first as? Symbol.VariableSymbol)
    #expect(g.kind == .Global)
    #expect(g.memberOf == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionStaticFunctionAndInitializerKindsPreserved() throws {
    let (context, program) = runEnter([
        "struct S {} extension S { static func sf() {} init() {} }",
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol
    let staticFunction = try #require(s.scope.values["sf"]?.first as? Symbol.FunctionSymbol)
    #expect(staticFunction.kind == .StaticMethod)
    #expect(staticFunction.scope.values["self"] == nil)
    let initSymbol = try #require(s.scope.values["init"]?.first as? Symbol.FunctionSymbol)
    #expect(initSymbol.kind == .Initializer)
    let initSelf = try #require(initSymbol.scope.values["self"]?.first as? Symbol.SelfSymbol)
    #expect(initSelf.memberOf == s.id)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionSubscriptAndAccessorSelfSymbolsGetMemberOf() throws {
    let (context, program) = runEnter([
        """
        struct S {}
        extension S {
            var a: Int { get { 0 } set { } }
            subscript(i: Int) -> Int { get { 0 } set { } }
        }
        """,
    ])
    let packageScope = program[0].packageSymbol!.scope
    let s = packageScope.types["S"] as! Symbol.NominalTypeSymbol

    let subscriptSymbol = try #require(s.scope.values["subscript"]?.first as? Symbol.SubscriptSymbol)
    #expect(subscriptSymbol.memberOf == s.id)
    #expect(subscriptSymbol.getter.kind == .Method)
    #expect(subscriptSymbol.getter.memberOf == s.id)
    let getterSelf = try #require(
        subscriptSymbol.getter.scope.values["self"]?.first as? Symbol.SelfSymbol
    )
    #expect(getterSelf.memberOf == s.id)
    let setter = try #require(subscriptSymbol.setter)
    #expect(setter.memberOf == s.id)
    let setterSelf = try #require(setter.scope.values["self"]?.first as? Symbol.SelfSymbol)
    #expect(setterSelf.memberOf == s.id)

    let extensionDecl = program[0].statements[1] as! AST.ExtensionDecl
    let variableDecl = extensionDecl.body[0] as! AST.VariableDecl
    let accessorSelfs = try variableDecl.accessors.map { accessor in
        try #require(accessor.scope?.values["self"]?.first as? Symbol.SelfSymbol)
    }
    #expect(accessorSelfs.count == 2)
    #expect(accessorSelfs.allSatisfy { $0.memberOf == s.id })
    #expect(variableDecl.accessors.allSatisfy { $0.symbol?.memberOf == s.id })
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionMemberOfNotBackfilledWhenBaseUnresolved() throws {
    let (context, program) = runEnter(["extension NotFound { func f() {} }"])
    let virtualScope = (program[0].statements[0] as! AST.ExtensionDecl).virtualScope
    let f = try #require(virtualScope?.values["f"]?.first as? Symbol.FunctionSymbol)
    #expect(f.memberOf == nil)
    #expect(f.kind == .Function)
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("extension of type 'NotFound' has no matching declaration"))
}

@Test func noSelfSymbolForNonInstanceCallables() throws {
    let (context, program) = runEnter([
        """
        protocol P { func f(); var v: Int }
        abstract class A { abstract func g() {} }
        struct T { static func h() {} static var sv: Int { get { 0 } } }
        func free() {}
        class C { func m() { func nested() {} } }
        """,
    ])
    let packageScope = program[0].packageSymbol!.scope

    let p = packageScope.types["P"] as! Symbol.NominalTypeSymbol
    let requirement = try #require(p.scope.values["f"]?.first as? Symbol.FunctionSymbol)
    #expect(requirement.scope.values["self"] == nil)

    let a = packageScope.types["A"] as! Symbol.NominalTypeSymbol
    let abstractFunction = try #require(a.scope.values["g"]?.first as? Symbol.FunctionSymbol)
    #expect(abstractFunction.scope.values["self"] == nil)

    let t = packageScope.types["T"] as! Symbol.NominalTypeSymbol
    let staticFunction = try #require(t.scope.values["h"]?.first as? Symbol.FunctionSymbol)
    #expect(staticFunction.scope.values["self"] == nil)
    let structDecl = program[0].statements[2] as! AST.StructDecl
    let staticVariableDecl = structDecl.body[1] as! AST.VariableDecl
    #expect(!staticVariableDecl.accessors.isEmpty)
    #expect(staticVariableDecl.accessors.allSatisfy { $0.scope?.values["self"] == nil })

    let free = try #require(packageScope.values["free"]?.first as? Symbol.FunctionSymbol)
    #expect(free.scope.values["self"] == nil)

    let c = packageScope.types["C"] as! Symbol.NominalTypeSymbol
    let m = try #require(c.scope.values["m"]?.first as? Symbol.FunctionSymbol)
    #expect(m.scope.values["self"]?.first is Symbol.SelfSymbol)
    let nested = try #require(m.scope.values["nested"]?.first as? Symbol.FunctionSymbol)
    #expect(nested.scope.values["self"] == nil)
}

@Test func closureBodyHasNoSelfAndLocalKinds() throws {
    let (context, program) = runEnter(["let cl = { var y = 1 }"])
    let variableDecl = program[0].statements[0] as! AST.VariableDecl
    let closure = variableDecl.initializer as! AST.Closure
    let scope = try #require(closure.scope)
    let y = try #require(scope.values["y"]?.first as? Symbol.VariableSymbol)
    #expect(y.kind == .Local)
    #expect(scope.values["self"] == nil)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func accessorBodyLocalKinds() throws {
    let (context, program) = runEnter([
        "struct S { var x: Int { get { let t = 1; return t } set { let u = 2 } } }",
    ])
    let structDecl = program[0].statements[0] as! AST.StructDecl
    let variableDecl = structDecl.body[0] as! AST.VariableDecl
    let getterLocal = try #require(
        variableDecl.accessors[0].scope?.values["t"]?.first as? Symbol.VariableSymbol
    )
    let setterLocal = try #require(
        variableDecl.accessors[1].scope?.values["u"]?.first as? Symbol.VariableSymbol
    )
    let implicitParameter = try #require(
        variableDecl.accessors[1].scope?.values["newValue"]?.first as? Symbol.VariableSymbol
    )
    #expect(getterLocal.kind == .Local)
    #expect(setterLocal.kind == .Local)
    #expect(implicitParameter.kind == .Local)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func variableSymbolStoresAccessorSymbols() throws {
    let (context, program) = runEnter([
        """
        struct S {
            var x: Int { get { 0 } set { } }
            var y: Int = 0 { willSet { } didSet { } }
        }
        """,
    ])
    let structDecl = program[0].statements[0] as! AST.StructDecl
    let computed = structDecl.body[0] as! AST.VariableDecl
    let observed = structDecl.body[1] as! AST.VariableDecl
    let computedSymbol = try #require(computed.symbol)
    let observedSymbol = try #require(observed.symbol)
    #expect(Set(computedSymbol.accessors.keys) == [.Get, .Set])
    #expect(Set(observedSymbol.accessors.keys) == [.WillSet, .DidSet])
    for variableDecl in [computed, observed] {
        let symbol = try #require(variableDecl.symbol)
        #expect(variableDecl.accessors.allSatisfy { symbol.accessors[$0.kind] === $0.symbol })
    }
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func extensionPropertyAccessorSymbolsAdoptedByBaseType() throws {
    let (context, program) = runEnter([
        """
        struct S {}
        extension S { var x: Int { get { 0 } set { } } }
        """,
    ])
    let s = try #require(program[0].packageSymbol!.scope.types["S"] as? Symbol.NominalTypeSymbol)
    let x = try #require(s.scope.values["x"]?.first as? Symbol.VariableSymbol)
    let getter = try #require(x.accessors[.Get])
    let setter = try #require(x.accessors[.Set])
    #expect(getter.memberOf == s.id)
    #expect(setter.memberOf == s.id)
    #expect(getter.scope.values["self"]?.first?.memberOf == s.id)
    #expect(setter.scope.values["self"]?.first?.memberOf == s.id)
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func repeatedLocalNamesInSameFunctionScope() {
    let (context, _) = runEnter(["func f() { var x = 1; var x = 2 }"])
    #expect(!context.diagnositicEngine.hasErrors)
}

@Test func repeatedGlobalNamesConflict() {
    let (context, _) = runEnter(["var g = 1; var g = 2"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of 'g'"))
}

@Test func repeatedPropertyNamesConflict() {
    let (context, _) = runEnter(["struct S { var p: Int; var p: Int }"])
    let messages = context.diagnositicEngine.diagnostics.map(\.message)
    #expect(messages.contains("invalid redeclaration of 'p'"))
}
