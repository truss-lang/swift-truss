import Testing
import TrussTIRGen

@Suite struct TIRGenTests {
    @Test func basicFunction() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(a: S) -> S {
                return a
            }
            """
        )
        try #require(tir.contains("function $t4main_1f_1a10$t4main_1S_10$t4main_1S"))
        try #require(tir.contains("entry:"))
        try #require(tir.contains("AllocStack"))
        try #require(tir.contains("Load"))
        try #require(tir.contains("Return"))
    }

    @Test func matchStatement() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A
                case B
            }
            func f(e: E) {
                match e {
                .A => { return }
                .B => { return }
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Unreachable"))
    }

    @Test func matchCaseMemberSubjectLowersToSwitchEnum() throws {
        let tir = dumpTIR(
            """
            enum En {
                case SomeCase
                case OtherCase
            }
            func has_cname() {
                match En.SomeCase {
                .SomeCase => {
                }
                .OtherCase => {
                }
                }
            }
            """
        )
        try #require(tir.contains("EnumValue"))
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Unreachable"))
    }

    @Test func matchImplicitReturnInFunction() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A
                case B
            }
            func f(e: E) -> E {
                match e {
                .A => { e }
                .B => { e }
                }
            }
            """
        )
        let fBlock = tir.components(separatedBy: "function ").last ?? ""
        let returns = fBlock.components(separatedBy: "\n")
            .filter { $0.range(of: #"Return %\d+"#, options: .regularExpression) != nil }
        try #require(returns.count == 2)
    }

    @Test func matchImplicitReturnInGetter() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A
                case B
            }
            struct S {
                var e: E
                var mirrored: E {
                    get {
                        match e {
                        .A => { e }
                        .B => { e }
                        }
                    }
                }
            }
            """
        )
        let getterBlock = tir.components(separatedBy: "function ")
            .first(where: { $0.contains("mirroredGetter_") }) ?? ""
        let returns = getterBlock.components(separatedBy: "\n")
            .filter { $0.range(of: #"Return %\d+"#, options: .regularExpression) != nil }
        try #require(returns.count == 2)
    }

    @Test func matchImplicitReturnInClosure() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A
                case B
            }
            func f(e: E) -> () -> E {
                { () -> E in
                    match e {
                    .A => { e }
                    .B => { e }
                    }
                }
            }
            """
        )
        let closureBlock = tir.components(separatedBy: "function ")
            .first(where: { $0.hasPrefix("$t4main_1f_1e10$t4main_1E_12FR$t4main_1E_closure_0") }) ?? ""
        let returns = closureBlock.components(separatedBy: "\n")
            .filter { $0.range(of: #"Return %\d+"#, options: .regularExpression) != nil }
        try #require(returns.count == 2)
    }

    @Test func matchExpressionLowersToPhi() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A
                case B
            }
            struct S {
                init() {}
            }
            func f(e: E) -> S {
                let x = match e {
                .A => S(),
                .B => S()
                }
                return x
            }
            """
        )
        try #require(tir.contains("Phi"))
        try #require(tir
            .range(of: #"Phi \[%[0-9]+, bb[0-9]+\], \[%[0-9]+, bb[0-9]+\]"#, options: .regularExpression) != nil)
    }

    @Test func ifExpressionLowersToPhi() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(c: Builtin.Bool) -> S {
                let y = if c {
                    S()
                } else {
                    S()
                }
                return y
            }
            """,
            installBuiltin: true
        )
        try #require(tir.contains("Phi"))
        try #require(tir
            .range(of: #"Phi \[%[0-9]+, bb[0-9]+\], \[%[0-9]+, bb[0-9]+\]"#, options: .regularExpression) != nil)
    }

    @Test func implicitReturnIfLowersToPhiReturn() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(c: Builtin.Bool) -> S {
                if c {
                    S()
                } else {
                    S()
                }
            }
            """,
            installBuiltin: true
        )
        let fBlock = tir.components(separatedBy: "function ").last ?? ""
        try #require(fBlock.range(
            of: #"Phi \[%[0-9]+, bb[0-9]+\], \[%[0-9]+, bb[0-9]+\]"#,
            options: .regularExpression
        ) != nil)
        try #require(fBlock.range(of: #"Return %[0-9]+"#, options: .regularExpression) != nil)
    }

    @Test func doExpressionLowersToPhi() throws {
        let tir = dumpTIR(
            """
            struct E {}
            struct S {
                init() {}
            }
            func f() -> S {
                let x = do {
                    S()
                } catch E {
                    S()
                }
                return x
            }
            """
        )
        try #require(tir.range(
            of: #"Phi \[%[0-9]+, (?:bb[0-9]+|entry)\], \[%[0-9]+, (?:bb[0-9]+|entry)\]"#,
            options: .regularExpression
        ) != nil)
    }

    @Test func implicitReturnDoLowersToPhiReturn() throws {
        let tir = dumpTIR(
            """
            struct E {}
            struct S {
                init() {}
            }
            func f() -> S {
                do {
                    S()
                } catch {
                    S()
                }
            }
            """
        )
        let fBlock = tir.components(separatedBy: "function ").last ?? ""
        try #require(fBlock.range(
            of: #"Phi \[%[0-9]+, (?:bb[0-9]+|entry)\], \[%[0-9]+, (?:bb[0-9]+|entry)\]"#,
            options: .regularExpression
        ) != nil)
        try #require(fBlock.range(of: #"Return %[0-9]+"#, options: .regularExpression) != nil)
    }

    @Test func closureCapture() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f() {
                var x: S = S()
                let c = { () -> Void in
                    let y = x
                    return
                }
                c()
            }
            """
        )
        try #require(tir.contains("$t4main_1f_4Void_closure_0"))
        try #require(tir.contains("AllocCell"))
        try #require(tir.contains("Closure"))
    }

    @Test func errorHandling() throws {
        let tir = dumpTIR(
            """
            struct E {}
            func g() throws(E) {}
            func f() {
                do {
                    try g()
                } catch {
                    return
                }
            }
            """
        )
        try #require(tir.contains("TryApply"))
        try #require(tir.contains("error:"))
    }
}

@Suite struct GlobalVarTests {
    @Test func globalVariableLowered() throws {
        let tir = dumpTIR(
            """
            struct S {}
            var g: S
            func f() -> S {
                return g
            }
            """
        )
        try #require(tir.contains("global "))
        try #require(tir.contains("GlobalAddr"))
        try #require(tir.contains("Load"))
    }

    @Test func propertyInitializerInInit() throws {
        let tir = dumpTIR(
            """
            struct T {}
            struct S {
                var x: T = T()
                init() {}
            }
            """
        )
        try #require(tir.contains("StructElementAddr"))
        try #require(tir.contains("Store"))
    }

    @Test func memberFunctionDoesNotReinitializeProperties() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            class C {
                var x: S = S()
                init() {}
                func f() {
                }
            }
            """
        )
        let fBlock = tir.components(separatedBy: "function ")
            .first(where: { $0.contains("1C_1f_") }) ?? ""
        try #require(!fBlock.contains("RefElementAddr"))
        try #require(fBlock.contains("Return"))
    }

    @Test func accessorGetterCalled() throws {
        let tir = dumpTIR(
            """
            struct T {}
            struct S {
                var x: T {
                    get { return y }
                }
                var y: T = T()
            }
            func f(s: S) -> T {
                return s.x
            }
            """
        )
        try #require(tir.contains("xGetter"))
        try #require(tir.contains("Apply"))
    }

    @Test func nestedModuleFunctionMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            module A.B {
                func f(a: S) -> S {
                    return a
                }
            }
            """
        )
        try #require(tir.contains("function $t4main1A1B_1f_1a10$t4main_1S_10$t4main_1S"))
        try #require(!tir.contains("function $t4main_1f_1a10$t4main_1S_10$t4main_1S"))
    }

    @Test func nestedModuleGlobalMangled() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            module A.B {
                var g: S = S()
            }
            """
        )
        try #require(tir.contains("global $t4main1A1B_1g"))
        try #require(tir.contains("GlobalAddr $t4main1A1B_1g"))
    }

    @Test func nestedModuleAccessorMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            module A.B {
                struct T {
                    var x: S {
                        get { return y }
                    }
                    var y: S = S()
                    init() {}
                }
            }
            """
        )
        try #require(tir.contains("function $t4main1A1B_1T_1xGetter_10$t4main_1S"))
    }

    @Test func nestedModuleDoesNotCollideWithTopLevel() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(a: S) -> S {
                return a
            }
            module A.B {
                func f(a: S) -> S {
                    return a
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1f_1a10$t4main_1S_10$t4main_1S"))
        try #require(tir.contains("function $t4main1A1B_1f_1a10$t4main_1S_10$t4main_1S"))
    }

    @Test func cnameOverridesMangledName() throws {
        let tir = dumpTIR(
            """
            #[cname("my_name")]
            func f() {}
            """
        )
        try #require(tir.contains("function my_name"))
    }

    @Test func cnameWithWrongArgumentCountReportsError() {
        let (context, program) = runPipeline(
            """
            #[cname("a", "b")]
            func f() {}
            """
        )
        _ = TIRGen(context: context).generate(program)
        #expect(
            context.diagnositicEngine.diagnostics.contains {
                $0.message.contains("cname attribute expects exactly one argument")
            }
        )
    }

    @Test func globalVarCnameOverridesMangledName() throws {
        let tir = dumpTIR(
            """
            struct T {
                init() {}
            }
            #[cname("g_name")]
            var g: T = T()
            func f() -> T {
                return g
            }
            """
        )
        try #require(tir.contains("global g_name"))
        try #require(tir.contains("GlobalAddr g_name"))
    }

    @Test func staticVarLoweredWithMangledName() throws {
        let tir = dumpTIR(
            """
            struct T {
                init() {}
            }
            struct S {
                static var s: T = T()
            }
            func f() -> T {
                return S.s
            }
            """
        )
        try #require(tir.contains("global $t4main_1S_1s"))
        try #require(tir.contains("GlobalAddr $t4main_1S_1s"))
    }

    @Test func staticVarCnameOverridesMangledName() throws {
        let tir = dumpTIR(
            """
            precedencegroup Assignment { assignment: true }
            infix operator =: Assignment
            struct T {
                init() {}
            }
            struct S {
                #[cname("s_name")]
                static var s: T = T()
            }
            func f() {
                S.s = T()
                let x = S.s
            }
            """
        )
        try #require(tir.contains("global s_name"))
        try #require(tir.contains("GlobalAddr s_name"))
        try #require(tir.contains("Store "))
        try #require(tir.contains("Load "))
    }

    @Test func variableCnameWithWrongArgumentCountReportsError() {
        let (context, program) = runPipeline(
            """
            struct T {
                init() {}
            }
            #[cname("a", "b")]
            var g: T = T()
            """
        )
        _ = TIRGen(context: context).generate(program)
        #expect(
            context.diagnositicEngine.diagnostics.contains {
                $0.message.contains("cname attribute expects exactly one argument")
            }
        )
    }

    @Test func externFunctionUsesPlainName() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                func foo(a: Int32) -> Int32
            }
            """
        )
        try #require(tir.contains("function foo "))
    }

    @Test func externFunctionUsesCnameWhenPresent() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                #[cname("bar")]
                func foo(a: Int32) -> Int32
            }
            """
        )
        try #require(tir.contains("function bar "))
        try #require(!tir.contains("function foo "))
    }

    @Test func externFunctionWithBodyIsLowered() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                func foo(a: Int32) -> Int32 {
                    return a
                }
            }
            """
        )
        try #require(tir.contains("function foo "))
        try #require(tir.contains("Return "))
    }

    @Test func externFunctionCallUsesExternName() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                func foo(a: Int32) -> Int32
            }
            func callFoo() {
                let x = foo(1)
            }
            """
        )
        try #require(tir.contains("function foo "))
        try #require(tir.contains("FunctionRef"))
        try #require(tir.contains("Apply "))
    }

    @Test func externVariableUsesPlainName() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                var g: Int32
            }
            """
        )
        try #require(tir.contains("global extern g"))
        try #require(!tir.contains("global $t4main_1g"))
    }

    @Test func externDeclarationIsExternWithConvention() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                func foo(a: Builtin.Int32) -> Builtin.Int32
            }
            """,
            installBuiltin: true
        )
        try #require(tir.contains("function foo extern \"C\""))
    }

    @Test func externFunctionWithBodyKeepsConventionWithoutExtern() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                func foo(a: Builtin.Int32) -> Builtin.Int32 {
                    return a
                }
            }
            """,
            installBuiltin: true
        )
        try #require(tir.contains("function foo \"C\""))
        try #require(!tir.contains("function foo extern"))
        try #require(tir.contains("Return "))
    }

    @Test func ordinaryFunctionHasNoExternOrConvention() throws {
        let tir = dumpTIR(
            """
            func foo(a: Builtin.Int32) -> Builtin.Int32 {
                return a
            }
            """,
            installBuiltin: true
        )
        try #require(!tir.contains(" extern"))
        try #require(!tir.contains(" \"C\""))
    }

    @Test func externVariableWithInitializerIsDefinition() throws {
        let tir = dumpTIR(
            """
            extern "C" {
                var g: Builtin.Int32 = 5
            }
            """,
            installBuiltin: true
        )
        try #require(tir.contains("global g : i32"))
        try #require(!tir.contains("global extern g"))
    }

    @Test func structDeinitCalledOnScopeExit() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
                deinit {
                }
            }
            func f() {
                let x = S()
            }
            """
        )
        try #require(tir.contains("function $t4main_1S_6deinit_4Void"))
        try #require(tir.contains("ReleaseValue") == false)
        let fBody = tir.components(separatedBy: "function $t4main_1f_4Void").last ?? ""
        try #require(fBody.contains("FunctionRef $t4main_1S_6deinit_4Void"))
        try #require(fBody.contains("Apply "))
    }

    @Test func structWithoutDeinitIsNotCalled() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let x = S()
            }
            """
        )
        try #require(!tir.contains("$t4main_1S_6deinit"))
    }

    @Test func classVariableReleasedOnScopeExit() throws {
        let tir = dumpTIR(
            """
            class C {
                init() {}
            }
            func f() {
                let x = C()
            }
            """
        )
        let fBody = tir.components(separatedBy: "function $t4main_1f_4Void").last ?? ""
        try #require(fBody.contains("ReleaseValue"))
    }

    @Test func refCopyRetainsAndReleasesBoth() throws {
        let tir = dumpTIR(
            """
            class C {
                init() {}
            }
            func f() {
                let a = C()
                let b = a
            }
            """
        )
        let fBody = tir.components(separatedBy: "function $t4main_1f_4Void").last ?? ""
        try #require(fBody.contains("RetainValue"))
        try #require(fBody.contains("ReleaseValue"))
        let retains = fBody.components(separatedBy: "\n").filter {
            $0.range(of: #"RetainValue"#, options: .regularExpression) != nil
        }.count
        let releases = fBody.components(separatedBy: "\n").filter {
            $0.range(of: #"ReleaseValue"#, options: .regularExpression) != nil
        }.count
        try #require(retains == 1)
        try #require(releases == 2)
    }

    @Test func refArgumentRetainedOnCall() throws {
        let tir = dumpTIR(
            """
            class C {
                init() {}
            }
            func g(c: C) {
            }
            func f() {
                let x = C()
                g(x)
            }
            """
        )
        let fBody = tir.components(separatedBy: "function $t4main_1f_4Void").last ?? ""
        try #require(fBody.contains("RetainValue"))
        try #require(fBody.contains("Apply "))
    }

    @Test func breakReleasesLoopScopeVariables() throws {
        let tir = dumpTIR(
            """
            class C {
                init() {}
            }
            func f() {
                while true {
                    let x = C()
                    break
                }
            }
            """
        )
        let fBody = tir.components(separatedBy: "function $t4main_1f_4Void").last ?? ""
        try #require(fBody.contains("ReleaseValue"))
        try #require(fBody.contains("Branch "))
    }

    @Test func guardFailureReleasesVariables() throws {
        let tir = dumpTIR(
            """
            class C {
                init() {}
            }
            func f() -> Bool {
                let x = C()
                guard true else {
                    return false
                }
                return true
            }
            """
        )
        try #require(tir.contains("ReleaseValue"))
    }

    @Test func closureCaptureRetainsRef() throws {
        let tir = dumpTIR(
            """
            class C {
                init() {}
            }
            func f() {
                let x = C()
                let g = {
                    x
                }
            }
            """
        )
        try #require(tir.contains("RetainValue"))
        try #require(tir.contains("AllocCell"))
    }

    @Test func optionalOverloadMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            struct T {}
            func f(a: S?) {}
            func f(a: T?) {}
            """
        )
        try #require(tir.contains("function $t4main_1f_1a11O$t4main_1S_4Void"))
        try #require(tir.contains("function $t4main_1f_1a11O$t4main_1T_4Void"))
    }

    @Test func genericInstantiationOverloadMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            struct T {}
            struct Box<U> {}
            func f(a: Box<S>) {}
            func f(a: Box<T>) {}
            """
        )
        try #require(tir.contains("function $t4main_1f_1a23G$t4main_3Box$t4main_1S_4Void"))
        try #require(tir.contains("function $t4main_1f_1a23G$t4main_3Box$t4main_1T_4Void"))
    }

    @Test func functionTypeParameterOverloadMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            struct T {}
            func f(cb: (S) -> Void) {}
            func f(cb: (T) -> Void) {}
            """
        )
        try #require(tir.contains("function $t4main_1f_2cb16F$t4main_1SRVoid_4Void"))
        try #require(tir.contains("function $t4main_1f_2cb16F$t4main_1TRVoid_4Void"))
    }

    @Test func tupleParameterOverloadMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            struct T {}
            func f(t: (S, T)) {}
            func f(t: (T, S)) {}
            """
        )
        try #require(tir.contains("function $t4main_1f_1t21T$t4main_1S$t4main_1T_4Void"))
        try #require(tir.contains("function $t4main_1f_1t21T$t4main_1T$t4main_1S_4Void"))
    }

    @Test func crossModuleSameNameTypeMangled() throws {
        let tir = dumpTIR(
            """
            module A { struct S {} }
            module B { struct S {} }
            func f(a: A.S) {}
            func f(a: B.S) {}
            """
        )
        try #require(tir.contains("function $t4main_1f_1a12$t4main1A_1S_4Void"))
        try #require(tir.contains("function $t4main_1f_1a12$t4main1B_1S_4Void"))
    }

    @Test func nestedTypeMangled() throws {
        let tir = dumpTIR(
            """
            struct Outer { struct Inner {} }
            struct Inner {}
            func f(a: Outer.Inner) {}
            func f(a: Inner) {}
            """
        )
        try #require(tir.contains("function $t4main_1f_1a21$t4main_5Outer_5Inner_4Void"))
        try #require(tir.contains("function $t4main_1f_1a14$t4main_5Inner_4Void"))
    }

    @Test func asyncThrowsFunctionTypeOverloadMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(cb: (S) -> Void) {}
            func f(cb: (S) async -> Void) {}
            func f(cb: (S) throws -> Void) {}
            """
        )
        try #require(tir.contains("function $t4main_1f_2cb16F$t4main_1SRVoid_4Void"))
        try #require(tir.contains("function $t4main_1f_2cb17F$t4main_1SRVoidA_4Void"))
        try #require(tir.contains("function $t4main_1f_2cb17F$t4main_1SRVoidT_4Void"))
    }
}

@Suite struct AccessorTests {
    @Test func accessorFunctionsMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            struct T {
                var x: S {
                    get { return y }
                    set { let v = newValue }
                }
                var y: S = S()
                init() {}
            }
            """
        )
        try #require(tir.contains("function $t4main_1T_1xGetter_10$t4main_1S"))
        try #require(tir.contains("function $t4main_1T_1xSetter_4Void"))
    }

    @Test func observerFunctionsMangled() throws {
        let tir = dumpTIR(
            """
            struct S {}
            struct T {
                var x: S = S() {
                    willSet(new) { let a = new }
                    didSet(old) { let b = old }
                }
                init() {}
            }
            """
        )
        try #require(tir.contains("function $t4main_1T_1xWillSet_4Void"))
        try #require(tir.contains("function $t4main_1T_1xDidSet_4Void"))
    }

    @Test func assignmentCallsSetter() throws {
        let tir = dumpTIR(
            """
            precedencegroup Assignment { assignment: true }
            infix operator =: Assignment
            struct S {
                init() {}
            }
            struct T {
                var x: S {
                    get { return y }
                    set { let v = newValue }
                }
                var y: S = S()
                init() {}
            }
            func f(t: T) {
                var u = t
                u.x = S()
            }
            """
        )
        try #require(tir.contains("FunctionRef $t4main_1T_1xSetter_4Void"))
        try #require(tir.contains("Apply "))
    }

    @Test func assignmentCallsObserversAroundStore() throws {
        let tir = dumpTIR(
            """
            precedencegroup Assignment { assignment: true }
            infix operator =: Assignment
            struct S {
                init() {}
            }
            struct T {
                var x: S = S() {
                    willSet(new) { let a = new }
                    didSet(old) { let b = old }
                }
                init() {}
            }
            func f(t: T) {
                var u = t
                u.x = S()
            }
            """
        )
        let fBlock = tir.components(separatedBy: "function ").last
            ?? ""
        let willSet = try #require(fBlock.range(of: "FunctionRef $t4main_1T_1xWillSet_4Void"))
        let store = try #require(fBlock.range(of: "Store ", options: .backwards))
        let didSet = try #require(fBlock.range(of: "FunctionRef $t4main_1T_1xDidSet_4Void"))
        try #require(willSet.lowerBound < store.lowerBound)
        try #require(store.lowerBound < didSet.lowerBound)
    }

    @Test func assignmentStoresToStoredProperty() throws {
        let tir = dumpTIR(
            """
            precedencegroup Assignment { assignment: true }
            infix operator =: Assignment
            struct S {
                init() {}
            }
            struct T {
                var x: S = S()
                init() {}
            }
            func f(t: T) {
                var u = t
                u.x = S()
            }
            """
        )
        try #require(tir.contains("StructElementAddr"))
        try #require(tir.contains("Store "))
        try #require(!tir.contains("xSetter_"))
    }

    @Test func assignmentStoresToLocalVariable() throws {
        let tir = dumpTIR(
            """
            precedencegroup Assignment { assignment: true }
            infix operator =: Assignment
            struct S {
                init() {}
            }
            func f(s: S) {
                var x: S = s
                x = s
            }
            """
        )
        let fBlock = tir.components(separatedBy: "function ").last
            ?? ""
        try #require(fBlock.contains("Store "))
        try #require(fBlock.contains("Load "))
    }
}

@Test func implicitSelfPropertyReadInGetter() throws {
    let tir = dumpTIR(
        """
        struct TT {
            init() {}
        }
        struct TS {
            var y: TT = TT()
            init() {}
            var x: TT {
                get { return y }
            }
        }
        """
    )
    let getterBlock = tir.components(separatedBy: "function ")
        .first(where: { $0.contains("1xGetter_") }) ?? ""
    try #require(getterBlock.contains("StructElementAddr"))
    try #require(getterBlock.contains("Load "))
}

@Test func implicitSelfPropertyWriteInSetter() throws {
    let tir = dumpTIR(
        """
        precedencegroup Assignment { assignment: true }
        infix operator =: Assignment
        struct TT {
            init() {}
        }
        struct TS {
            var x: TT {
                get { return y }
                set { y = newValue }
            }
            var y: TT = TT()
            init() {}
        }
        """
    )
    let setterBlock = tir.components(separatedBy: "function ")
        .first(where: { $0.contains("1xSetter_") }) ?? ""
    try #require(setterBlock.contains("StructElementAddr"))
    try #require(setterBlock.contains("Store "))
}

@Test func dumpShowsFunctionSignature() throws {
    let tir = dumpTIR(
        """
        struct S {}
        func f(a: S) -> S {
            return a
        }
        """
    )
    try #require(tir.contains("function $t4main_1f_1a10$t4main_1S_10$t4main_1S (%0 t4main_1S) -> t4main_1S"))
}

@Suite struct ControlFlowTests {
    @Test func whileLoopBranchesOnCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                while x {
                    break
                }
            }
            """
        )
        try #require(tir.contains("CondBranch"))
        try #require(tir.contains("Branch"))
    }

    @Test func continueBranchesBackToCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                while x {
                    continue
                }
            }
            """
        )
        let lines = tir.split(separator: "\n").map(String.init)
        let condBranchIndex = try #require(lines.firstIndex { $0.contains("CondBranch") })
        let condBlock = try #require(
            lines[..<condBranchIndex].reversed().first { $0.hasSuffix(":") }
        ).replacingOccurrences(of: ":", with: "")
        try #require(lines.contains("  Branch \(condBlock)"))
    }

    @Test func ifElseBranchesOnCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                if x {
                } else {
                }
            }
            """
        )
        try #require(tir.contains("CondBranch"))
        try #require(tir.contains("true: "))
        try #require(tir.contains("false: "))
    }

    @Test func guardReturnsOnFailure() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                guard x else {
                    return
                }
            }
            """
        )
        let condBranchLines = tir.split(separator: "\n").filter { $0.contains("CondBranch") }
        try #require(condBranchLines.count == 1)
        let trueTarget = condBranchLines[0].split(separator: ",")[1].split(separator: ":")[1]
            .trimmingCharacters(in: .whitespaces)
        let falseTarget = condBranchLines[0].split(separator: ",")[2].split(separator: ":")[1]
            .trimmingCharacters(in: .whitespaces)
        try #require(tir.contains("\(falseTarget):\n  Return"))
        try #require(tir.contains("\(trueTarget):"))
    }

    @Test func repeatWhileReevaluatesCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                repeat {
                } while x
            }
            """
        )
        try #require(tir.contains("CondBranch"))
        try #require(tir.contains("true: "))
    }

    @Test func deferRunsBeforeReturn() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                defer {
                    let y = x
                }
                return
            }
            """
        )
        let returnIndex = try #require(tir.range(of: "\n  Return"))
        let storeIndex = try #require(tir.range(of: "Store "))
        try #require(storeIndex.lowerBound < returnIndex.lowerBound)
    }

    @Test func doFinallyRunsBeforeJoin() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                do {
                } finally {
                    let y = x
                }
            }
            """
        )
        try #require(tir.contains("Unreachable"))
        try #require(tir.contains("Load "))
        try #require(tir.contains("Store "))
    }

    @Test func gotoBranchesToLabel() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                goto label
            label:
                let y = x
            }
            """
        )
        try #require(tir.contains("Branch "))
        try #require(!tir.contains("Trap"))
    }

    @Test func asmLowersToInlineAsm() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let s = S()
                asm { "mov {dst}, 42" : dst = out(reg) s }
            }
            """
        )
        try #require(tir.contains("InlineAsm \"mov {dst}, 42\""))
        try #require(tir.contains("constraints: [reg]"))
        try #require(!tir.contains("Trap"))
    }

    @Test func forLoopLowersToTrap() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f() {
                for x in [] {
                }
            }
            """
        )
        try #require(tir.contains("ArrayValue []"))
        try #require(tir.contains("Trap"))
    }
}

@Suite struct MissingLoweringTests {
    @Test func ifLetBindingBindsVariable() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S?) {
                if let y = x {
                    let z = y
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Load "))
    }

    @Test func matchCaseBindingBindsVariable() throws {
        let tir = dumpTIR(
            """
            enum E {
                case A(S)
            }
            struct S {
                init() {}
            }
            func f(e: E) {
                match e {
                .A(let x) => {
                    let z = x
                }
                }
            }
            """
        )
        try #require(tir.contains("UncheckedEnumData"))
        try #require(tir.contains("Load "))
    }

    @Test func guardLetBindingBindsVariable() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S?) {
                guard let y = x else { return }
                let z = y
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Load "))
        try #require(tir.contains("Return"))
    }

    @Test func addressOfLowersToAddressToPointer() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S) -> S {
                let p = &x
                return *p
            }
            """
        )
        try #require(tir.contains("AddressToPointer "))
        try #require(tir.contains("Load "))
    }

    @Test func nullPointerLiteralLowersToNullLiteral() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let p: S* = nullptr
            }
            """
        )
        try #require(tir.contains("NullptrLiteral"))
    }

    @Test func labeledBreakTargetsOuterLoop() throws {
        let plain = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                while true {
                    while true {
                        break
                    }
                }
            }
            """
        )
        let labeled = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                outer: while true {
                    while true {
                        break outer
                    }
                }
            }
            """
        )
        try #require(labeled != plain)
        try #require(labeled.contains("Branch "))
    }

    @Test func closureBindingUsesClosureScope() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(x: S?) {
                let g = {
                    if let y = x {
                        let z = y
                    }
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("Load "))
    }
}

@Test func caseMatchLowersToBoolPhi() throws {
    let tir = dumpTIR(
        """
        enum E {
            case C
        }
        func f(e: E) {
            let b = case .C = e
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("BoolLiteral true"))
    try #require(tir.contains("BoolLiteral false"))
    try #require(tir.contains("Phi"))
}

@Test func optionalBindingExpressionLowersToBoolPhi() throws {
    let tir = dumpTIR(
        """
        struct S {
            init() {}
        }
        func f(a: S?) {
            let b = (let x = a)
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("SwitchEnum"))
    try #require(tir.contains("BoolLiteral true"))
    try #require(tir.contains("BoolLiteral false"))
    try #require(tir.contains("Phi"))
}

@Test func logicalAndShortCircuits() throws {
    let tir = dumpTIR(
        """
        precedencegroup LogicalAnd { associativity: left }
        infix operator &&: LogicalAnd
        func &&(lhs: Builtin.Bool, rhs: Builtin.Bool) -> Builtin.Bool {
            lhs
        }
        func f(a: Builtin.Bool, b: Builtin.Bool) -> Builtin.Bool {
            return a && b
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("CondBranch"))
    try #require(tir.contains("BoolLiteral false"))
    try #require(tir.contains("Phi"))
    try #require(!tir.contains("Apply "))
}

@Suite struct TypeLoweringTests {
    @Test func enumMatchWithPayload() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            enum E {
                case A
                case B(S)
            }
            func f(e: E) {
                match e {
                .B(let s) => { let x = s }
                _ => { return }
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("UncheckedEnumData"))
        try #require(tir.contains("TupleElementAddr"))
    }

    @Test func enumCaseValue() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            enum E {
                case A
            }
            func f() -> E {
                return E.A
            }
            """
        )
        try #require(tir.contains("EnumValue"))
        try #require(tir.contains("case A"))
    }

    @Test func forceUnwrapUncheckedEnumData() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(o: S?) -> S {
                return o!
            }
            """
        )
        try #require(tir.contains("UncheckedEnumData"))
        try #require(tir.contains("case some"))
    }

    @Test func ifLetSwitchOnOptional() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(o: S?) {
                if let x = o {
                    let y = x
                }
            }
            """
        )
        try #require(tir.contains("SwitchEnum"))
        try #require(tir.contains("case some"))
        try #require(tir.contains("case none"))
    }

    @Test func upcastToProtocol() throws {
        let tir = dumpTIR(
            """
            protocol P {}
            struct S: P {
                init() {}
            }
            func f(s: S) -> P {
                return s as P
            }
            """
        )
        try #require(tir.contains("Upcast"))
    }

    @Test func classStoredPropertyUsesRefElementAddr() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            class C {
                var x: S = S()
                init() {}
            }
            func f(c: C) -> S {
                return c.x
            }
            """
        )
        try #require(tir.contains("RefElementAddr"))
        try #require(tir.contains("#0 x"))
        try #require(tir.contains("Store "))
    }

    @Test func deinitFunctionLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            class C {
                var x: S = S()
                init() {}
                deinit {
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1C_6deinit_4Void"))
    }

    @Test func deinitBindsSelfAndAccessesMembers() throws {
        let tir = dumpTIR(
            """
            precedencegroup Assignment { assignment: true }
            infix operator =: Assignment
            struct S {
                init() {}
            }
            class C {
                var x: S = S()
                init() {}
                deinit {
                    x = S()
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1C_6deinit_4Void"))
        try #require(tir.contains("RefElementAddr"))
        try #require(tir.contains("Store "))
    }

    @Test func deinitPerClassMangledSeparately() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            class C {
                init() {}
                deinit {
                }
            }
            class D {
                init() {}
                deinit {
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1C_6deinit_4Void"))
        try #require(tir.contains("function $t4main_1D_6deinit_4Void"))
    }

    @Test func subscriptDeclLoweredToFunction() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            struct T {
                init() {}
                subscript(i: S) -> S {
                    return i
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1T_9subscript_1i10$t4main_1S_10$t4main_1S"))
    }

    @Test func initCallLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() -> S {
                return S()
            }
            """
        )
        try #require(tir.contains("function $t4main_1S_4init_4Void"))
        try #require(tir.contains("FunctionRef $t4main_1S_4init_4Void"))
        try #require(tir.contains("Apply "))
    }
}

@Test func initCallPassesSelfArgument() throws {
    let tir = dumpTIR(
        """
        struct S {
            init() {}
        }
        func f() -> S {
            return S()
        }
        """
    )
    try #require(tir.contains("4init_4Void : $("))
    let fBlock = tir.components(separatedBy: "function ").last
        ?? ""
    try #require(fBlock.range(of: #"Apply %\d+\(%\d+\)"#, options: .regularExpression) != nil)
}

@Test func implicitReturnInFunctionBody() throws {
    let tir = dumpTIR(
        """
        struct S {
            init() {}
        }
        func f() -> S {
            S()
        }
        """
    )
    let fBlock = tir.components(separatedBy: "function ").last
        ?? ""
    try #require(fBlock.range(of: #"Return %\d+"#, options: .regularExpression) != nil)
}

@Test func implicitReturnInGetter() throws {
    let tir = dumpTIR(
        """
        struct S {
            init() {}
        }
        struct T {
            var x: S {
                get { S() }
            }
            init() {}
        }
        """
    )
    let getterBlock = tir.components(separatedBy: "function ")
        .first(where: { $0.contains("1xGetter_") }) ?? ""
    try #require(getterBlock.range(of: #"Return %\d+"#, options: .regularExpression) != nil)
}

@Test func implicitReturnInClosure() throws {
    let tir = dumpTIR(
        """
        struct S {}
        func f() {
            let g = { (s: S) -> S in
                s
            }
        }
        """
    )
    let closureBlock = tir.components(separatedBy: "function ")
        .first(where: { $0.hasPrefix("$t4main_1f_4Void_closure_0") }) ?? ""
    try #require(closureBlock.range(of: #"Return %\d+"#, options: .regularExpression) != nil)
}

@Test func builtinTypeLowersToPrimitive() throws {
    let tir = dumpTIR(
        """
        func f() {
            var v: Builtin.Int64 = 1
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("i64"))
}

@Test func builtinBoolLowersToPrimitive() throws {
    let tir = dumpTIR(
        """
        func f() {
            var b: Builtin.Bool = true
        }
        """,
        installBuiltin: true
    )
    try #require(tir.contains("b1"))
}

@Suite struct ValueLoweringTests {
    @Test func binaryOperatorAppliesFunction() throws {
        let tir = dumpTIR(
            """
            precedencegroup P {}
            infix operator +: P
            struct S {
                init() {}
            }
            func +(lhs: S, rhs: S) -> S { lhs }
            func f(a: S, b: S) -> S {
                return a + b
            }
            """
        )
        try #require(tir.contains("function $t4main_1+_3lhs10$t4main_1S_3rhs10$t4main_1S_10$t4main_1S"))
        try #require(tir.contains("FunctionRef $t4main_1+_3lhs10$t4main_1S_3rhs10$t4main_1S_10$t4main_1S"))
        try #require(tir.contains("Apply "))
    }

    @Test func prefixOperatorAppliesFunction() throws {
        let tir = dumpTIR(
            """
            precedencegroup P {}
            prefix operator -
            struct S {
                init() {}
            }
            func -(prefixValue: S) -> S { prefixValue }
            func f(s: S) -> S {
                return -s
            }
            """
        )
        try #require(tir.contains("function $t4main_1-_11prefixValue10$t4main_1S_10$t4main_1S"))
        try #require(tir.contains("Apply "))
    }

    @Test func tupleValueLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() -> S {
                let t = (S(), S())
                return S()
            }
            """
        )
        try #require(tir.contains("TupleValue"))
    }

    @Test func arrayAndDictionaryLiterals() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let a = [S(), S()]
                let d = ["k": S()]
            }
            """
        )
        try #require(tir.contains("ArrayValue"))
        try #require(tir.contains("DictionaryValue"))
        try #require(tir.contains("StringLiteral \"k\""))
    }

    @Test func stringInterpolationLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f(s: S) {
                let t = "value \\(s) tail"
            }
            """
        )
        try #require(tir.contains("StringLiteral \"value  tail\""))
        try #require(tir.contains("Load "))
    }

    @Test func closureShorthandArgument() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let c = { (a: S, b: S) -> S in
                    return $0
                }
            }
            """
        )
        try #require(tir.contains("function $t4main_1f_4Void_closure_0"))
        try #require(tir.contains("Closure $t4main_1f_4Void_closure_0"))
        try #require(tir.contains("Return "))
    }

    @Test func globalInitializerLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            var g: S = S()
            func f() -> S {
                return g
            }
            """
        )
        try #require(tir.contains("global $t4main_1g"))
        try #require(tir.contains("GlobalAddr $t4main_1g"))
        try #require(tir.contains("FunctionRef $t4main_1S_4init_4Void"))
        try #require(tir.contains("Store "))
    }

    @Test func staticMethodCallLowered() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
                static func make() -> S {
                    return S()
                }
            }
            func f() -> S {
                return S.make()
            }
            """
        )
        try #require(tir.contains("function $t4main_1S_4make_10$t4main_1S"))
        try #require(tir.contains("FunctionRef $t4main_1S_4make_10$t4main_1S"))
        try #require(tir.contains("Apply "))
    }
}

@Suite struct TypeRegistryTests {
    @Test func storedPropertyFieldIndexFollowsDeclarationOrder() throws {
        let tir = dumpTIR(
            """
            struct T {}
            struct S {
                var x: T = T()
                var y: T = T()
                init() {}
            }
            func f() -> T {
                let s = S()
                return s.y
            }
            """
        )
        let fBlock = tir.components(separatedBy: "function ").last ?? ""
        try #require(fBlock.range(
            of: #"StructElementAddr %\d+, #1 y"#, options: .regularExpression
        ) != nil)
    }

    @Test func mutuallyRecursiveStructsLowerWithoutCycle() throws {
        let tir = dumpTIR(
            """
            struct A {
                var b: B
            }
            struct B {
                var a: A
            }
            func f(a: A) -> A {
                return a
            }
            func g(b: B) -> B {
                return b
            }
            """
        )
        try #require(tir.contains("types:"))
        try #require(tir.contains("b: "))
        try #require(tir.contains("a: "))
    }

    @Test func recursiveClassFieldLowered() throws {
        let tir = dumpTIR(
            """
            class C {
                var next: C?
            }
            func f(c: C) -> C {
                return c
            }
            """
        )
        try #require(tir.contains("next: "))
    }

    @Test func computedAndStaticPropertiesExcludedFromFields() throws {
        let tir = dumpTIR(
            """
            struct T {}
            struct S {
                var stored: T = T()
                static var shared: T = T()
                var computed: T {
                    get { return stored }
                }
                init() {}
            }
            """
        )
        let typeLine = tir.components(separatedBy: "\n").first(where: { $0.contains("$t4main_1S") })
            ?? ""
        try #require(typeLine.contains("stored: "))
        try #require(!typeLine.contains("shared"))
        try #require(!typeLine.contains("computed"))
    }

    @Test func enumCasesDumpedWithAssociatedTypes() throws {
        let tir = dumpTIR(
            """
            struct T {}
            enum E {
                case A
                case B(T)
            }
            func f(e: E) -> E {
                return e
            }
            """
        )
        try #require(tir.contains(".A"))
        try #require(tir.range(
            of: #"\.B\(\$t4main_1T"#, options: .regularExpression
        ) != nil)
    }
}
