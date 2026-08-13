import Testing

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
        try #require(tir.contains("function $t4main_1T_1xGetter_9$t4main1S"))
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
    try #require(tir.contains("function $t4main_1f_1a9$t4main1S_9$t4main1S (%0 t4main1S#0) -> t4main1S#0"))
}
