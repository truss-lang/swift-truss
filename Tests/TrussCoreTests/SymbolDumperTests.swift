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
                var a #1
                var b #2
              function f #5 (xs: ...)
                var xs #4
              function g #9 (x:, y:)
                var x #6
                var y #7
                var z #8

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
                case a #11
                case b #12
              type Q (protocol) #3 ty:ProtocolType(Q)#1
                type U (associated-type) #4
              type S (struct) #1 ty:StructType(S)#0
                function init #8 (x:)
                  var x #7
                function subscript #10 (i:)
                  var i #9
                var x #6
              type T (typealias) #2

            """
    )
}
