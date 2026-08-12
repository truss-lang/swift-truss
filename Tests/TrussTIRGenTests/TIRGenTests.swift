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
        try #require(tir.contains("function $t4main_1f_1a1S_1S"))
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
            .first(where: { $0.hasPrefix("closure-0") }) ?? ""
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
        try #require(tir.contains("closure-0"))
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
        try #require(tir.contains("function $t4main1A1B_1f_1a1S_1S"))
        try #require(!tir.contains("function $t4main_1f_1a1S_1S"))
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
        try #require(tir.contains("function $t4main1A1B_1T_1xGetter_1S"))
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
        try #require(tir.contains("function $t4main_1f_1a1S_1S"))
        try #require(tir.contains("function $t4main1A1B_1f_1a1S_1S"))
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
}
