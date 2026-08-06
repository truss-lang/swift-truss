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
              value f (function) #3 (a:, b: =)
                value a (variable) #1
                value b (variable) #2
              value f (function) #5 (xs: ...)
                value xs (variable) #4
              value g (function) #9 (x:, y:)
                value x (variable) #6
                value y (variable) #7
                value z (variable) #8

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
                value a (case) #11
                value b (case) #12
              type Q (protocol) #3 ty:ProtocolType(Q)#1
                type U (associated-type) #4
              type S (struct) #1 ty:StructType(S)#0
                value init (function) #8 (x:)
                  value x (variable) #7
                value subscript (function) #10 (i:)
                  value i (variable) #9
                value x (variable) #6
              type T (typealias) #2

            """
    )
}
