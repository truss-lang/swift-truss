import Testing
import TrussCore

@Test func dumpSymbolsTypeDeclarations() {
    #expect(
        dumpSymbols(
            """
            protocol P1 {}
            class Base {}
            struct S: P1 {}
            class C: Base, P1 {}
            enum E: P1 {}
            actor A {}
            """
        )
            == """
            main (package) #0
              type A (actor) #6 ty:ActorType(A)#5
              type Base (class) #2 ty:ClassType(Base)#1
              type C (class) #4 ty:ClassType(C)#3 conforms:P1#1 super:Base#2
              type E (enum) #5 ty:EnumType(E)#4 conforms:P1#1
              type P1 (protocol) #1 ty:ProtocolType(P1)#0
              type S (struct) #3 ty:StructType(S)#2 conforms:P1#1

            """
    )
}

@Test func dumpSymbolsFunctions() {
    #expect(
        dumpSymbols(
            """
            func f(a: Int, b: Int = 0) {}
            func f(xs: Int...) {}
            func g(x: Int, y: Int) {
                let z = 1
            }
            """
        )
            == """
            main (package) #0
              function f #3 (a:, b: =)
                var a (Local) #1
                var b (Local) #2
              function f #5 (xs: ...)
                var xs (Local) #4
              function g #9 (x:, y:)
                var x (Local) #6
                var y (Local) #7
                var z (Local) #8

            """
    )
}

@Test func dumpSymbolsTypeMembers() {
    #expect(
        dumpSymbols(
            """
            struct S {
                var x: Int
                init(x: Int) {
                }
                subscript(i: Int) -> Int {
                    return x
                }
            }
            typealias T = S
            protocol Q {
                associatedtype U
            }
            enum E {
                case a, b(x: Int)
            }
            """
        )
            == """
            main (package) #0
              type E (enum) #5 ty:EnumType(E)#2
                case a #14
                case b #15
              type Q (protocol) #3 ty:ProtocolType(Q)#1
                type U (associated-type) #4
              type S (struct) #1 ty:StructType(S)#0
                function init #9 (x:)
                  self (Local) #7
                  var x (Local) #8
                value subscript #13
                  function getter #11 (i:)
                    var i (Local) #10
                    self (Local) #12
                var x (Property) #6
              type T (typealias) #2

            """
    )
}

@Test func dumpSymbolsSubscriptAccessors() {
    #expect(
        dumpSymbols(
            """
            struct S {
                var x: Int
                subscript(i: Int) -> Int {
                    get {
                        return x
                    }
                    set {
                        x = newValue
                    }
                }
            }
            """
        )
            == """
            main (package) #0
              type S (struct) #1 ty:StructType(S)#0
                value subscript #9
                  function getter #5 (i:)
                    var i (Local) #3
                    self (Local) #6
                  function setter #7 (i:, _:)
                    var newValue (Local) #4
                    self (Local) #8
                var x (Property) #2

            """
    )
}

@Test func dumpSymbolsVariableKinds() {
    #expect(
        dumpSymbols(
            """
            struct S {
                var a: Int
                static var s: Int
                func f() {
                    var x = 1
                }
            }
            var g = 1
            """
        )
            == """
            main (package) #0
              type S (struct) #1 ty:StructType(S)#0
                var a (Property) #2
                function f #6 ()
                  self (Local) #4
                  var x (Local) #5
                var s (StaticProperty) #3
              var g (Global) #7

            """
    )
}

@Test func dumpSymbolsSelfSymbol() {
    #expect(
        dumpSymbols(
            """
            struct S {
                var a: Int {
                    get { return 1 }
                    set { }
                }
                func m() {}
                init() {}
                subscript(i: Int) -> Int { return i }
            }
            class C {
                deinit {}
            }
            """
        )
            == """
            main (package) #0
              type C (class) #2 ty:ClassType(C)#1
                function deinit #18 ()
                  self (Local) #17
              type S (struct) #1 ty:StructType(S)#0
                var a (Property) #4
                function init #12 ()
                  self (Local) #11
                function m #10 ()
                  self (Local) #9
                value subscript #16
                  function getter #14 (i:)
                    var i (Local) #13
                    self (Local) #15

            """
    )
}

@Test func dumpSymbolsNoSelfSymbol() {
    #expect(
        dumpSymbols(
            """
            protocol P {
                func f()
                var v: Int
            }
            abstract class A {
                abstract func g()
            }
            struct T {
                static func h() {}
            }
            let cl = { var y = 1 }
            """
        )
            == """
            main (package) #0
              type A (class) #2 ty:ClassType(A)#1
                function g #6 ()
              type P (protocol) #1 ty:ProtocolType(P)#0
                function f #4 ()
                var v (Property) #5
              type T (struct) #3 ty:StructType(T)#2
                function h #7 ()
              var cl (Global) #9

            """
    )
}
