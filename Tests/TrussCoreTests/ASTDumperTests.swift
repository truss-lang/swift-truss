import Testing
import TrussCore

@Test func dumpSimpleFunction() {
    #expect(
        dumpProgram(
            """
            func f(x: Int) -> Int {
                return x + 1
            }
            """
        )
            == """
            Program "main"
            `-FunctionDecl f
              |-Parameter x label:x
              | `-Variable Int
              |-Variable Int
              `-Return
                `-SequentialExpression +
                  |-Variable x
                  `-IntegerLiteral 1
            """
    )
}

@Test func dumpForWithWhereClause() {
    #expect(
        dumpProgram(
            """
            func f(xs: [Int]) {
                for i in xs where i > 0 {
                    g(i)
                }
            }
            """
        )
            == """
            Program "main"
            `-FunctionDecl f
              |-Parameter xs label:xs
              | `-ArrayLiteral
              |   `-Variable Int
              `-For
                |-Pattern
                | `-Variable i
                |-Sequence
                | `-Variable xs
                |-Where
                | `-SequentialExpression >
                |   |-Variable i
                |   `-IntegerLiteral 0
                `-ExpressionStatement
                  `-Call
                    |-Variable g
                    `-Argument
                      `-Variable i
            """
    )
}

@Test func dumpFunctionDeclSemantics() {
    #expect(
        dumpProgram("func f() {}", semantic: true)
            == """
            Program "main"
            `-FunctionDecl f sym:f#1
            """
    )
}

@Test func dumpVariableReferenceSemantics() {
    #expect(
        dumpProgram("func f() {\n    let a = 1\n    a\n}", semantic: true)
            == """
            Program "main"
            `-FunctionDecl f sym:f#2
              |-VariableDecl a sym:a#1
              | `-Initializer
              |   `-IntegerLiteral 1
              `-ExpressionStatement
                `-Variable a sym:a#1
            """
    )
}

@Test func dumpLiterals() {
    #expect(
        dumpProgram(
            """
            func f() {
                let a = 42
                let b = 3.14
                let c = "hi"
                let d = 'x'
                let e = true
                let g = null
            }
            """
        )
            == """
            Program "main"
            `-FunctionDecl f
              |-VariableDecl a
              | `-Initializer
              |   `-IntegerLiteral 42
              |-VariableDecl b
              | `-Initializer
              |   `-FloatLiteral 3.14
              |-VariableDecl c
              | `-Initializer
              |   `-StringLiteral "hi"
              |-VariableDecl d
              | `-Initializer
              |   `-CharLiteral 'x'
              |-VariableDecl e
              | `-Initializer
              |   `-BoolLiteral true
              `-VariableDecl g
                `-Initializer
                  `-NullLiteral
            """
    )
}

@Test func dumpPrefixOperators() {
    #expect(
        dumpProgram("func f() {\n    let x = -a + -b\n}")
            == """
            Program "main"
            `-FunctionDecl f
              `-VariableDecl x
                `-Initializer
                  `-SequentialExpression - + -
                    |-Variable a
                    `-Variable b
            """
    )
}

@Test func dumpIfElse() {
    #expect(
        dumpProgram(
            """
            func f(c: Bool) {
                if c {
                    g()
                } else {
                    h()
                }
            }
            """
        )
            == """
            Program "main"
            `-FunctionDecl f
              |-Parameter c label:c
              | `-Variable Bool
              `-ExpressionStatement
                `-If
                  |-Condition
                  | `-Variable c
                  |-ExpressionStatement
                  | `-Call
                  |   `-Variable g
                  `-Else
                    `-ExpressionStatement
                      `-Call
                        `-Variable h
            """
    )
}

@Test func dumpModuleAndStruct() {
    #expect(
        dumpProgram(
            """
            module M {
                func f() {
                }
            }
            struct S: P2 {
                public func m() {
                }
            }
            """
        )
            == """
            Program "main"
            |-ModuleDecl M
            | `-FunctionDecl f
            `-StructDecl S
              |-Conformance
              | `-Variable P2
              `-FunctionDecl m [public]
            """
    )
}

@Test func dumpClosure() {
    #expect(
        dumpProgram(
            """
            func f() {
                let fn = { [weak self] (x: Int) -> Int in x }
            }
            """
        )
            == """
            Program "main"
            `-FunctionDecl f
              `-VariableDecl fn
                `-Initializer
                  `-Closure
                    |-Signature [weak self]
                    | |-Parameter x label:x
                    | | `-Variable Int
                    | `-Variable Int
                    `-ExpressionStatement
                      `-Variable x
            """
    )
}

@Test func dumpStringInterpolation() {
    #expect(
        dumpProgram(
            """
            func f() {
                let s = "a\\(x + 1)b"
            }
            """
        )
            == """
            Program "main"
            `-FunctionDecl f
              `-VariableDecl s
                `-Initializer
                  `-StringInterpolation
                    |-Literal "a"
                    |-Interpolation
                    | `-SequentialExpression +
                    |   |-Variable x
                    |   `-IntegerLiteral 1
                    `-Literal "b"
            """
    )
}

@Test func dumpPrecedenceGroup() {
    #expect(
        dumpProgram(
            """
            precedencegroup P {
                associativity: left
                higherThan: A
            }
            """
        )
            == """
            Program "main"
            `-PrecedenceGroupDecl P [left]
              `-HigherThan
                `-Variable A
            """
    )
}

@Test func dumpAsm() {
    #expect(
        dumpProgram(
            """
            func f() {
                asm { "nop" : dst = out(reg) result : result preserves_flags }
            }
            """
        )
            == """
            Program "main"
            `-FunctionDecl f
              `-Asm
                |-StringLiteral "nop"
                |-Binding dst = out(reg) result
                `-Options result, preserves_flags
            """
    )
}

@Test func dumpPostfixOperator() {
    #expect(
        dumpProgram("func f() {\n    let x = a!\n}")
            == """
            Program "main"
            `-FunctionDecl f
              `-VariableDecl x
                `-Initializer
                  `-SequentialExpression !
                    `-Variable a
            """
    )
}

@Test func dumpTypeDeclSemantics() {
    #expect(
        dumpProgram(
            """
            protocol P1 {}
            class Base {}
            struct S: P1 {}
            class C: Base, P1 {}
            enum E: P1 {}
            actor A {}
            """,
            semantic: true
        )
            == """
            Program "main"
            |-ProtocolDecl P1 sym:P1#1
            |-ClassDecl Base sym:Base#2
            |-StructDecl S sym:S#3
            | `-Conformance
            |   `-Variable P1 sym:P1#1
            |-ClassDecl C sym:C#4 super:Base#2
            | |-Conformance
            | | `-Variable Base sym:Base#2
            | `-Conformance
            |   `-Variable P1 sym:P1#1
            |-EnumDecl E sym:E#5
            | `-Conformance
            |   `-Variable P1 sym:P1#1
            `-ActorDecl A sym:A#6
            """
    )
}

@Test func dumpOverloadsSemantics() {
    #expect(
        dumpProgram(
            """
            func f(a: Int, b: Int = 0) {}
            func f(xs: Int...) {}
            func g() {
                f(a: 1)
            }
            """,
            semantic: true
        )
            == """
            Program "main"
            |-FunctionDecl f sym:f#3
            | |-Parameter a label:a
            | | `-Variable Int ty:ErrorType
            | `-Parameter b label:b
            |   |-Variable Int ty:ErrorType
            |   `-Default
            |     `-IntegerLiteral 0
            |-FunctionDecl f sym:f#5
            | `-Parameter xs label:xs
            |   `-VariadicType ... ty:ErrorType
            |     `-Variable Int ty:ErrorType
            `-FunctionDecl g sym:g#6
              `-ExpressionStatement
                `-Call ty:VoidType overloads:2 [f(a:, b: =), f(xs: ...)]
                  |-Variable f overloads:2 [f(a:, b: =), f(xs: ...)]
                  `-Argument label:a
                    `-IntegerLiteral 1
            """
    )
}

@Test func dumpTypeMemberSemantics() {
    #expect(
        dumpProgram(
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
            """,
            semantic: true
        )
            == """
            Program "main"
            |-StructDecl S sym:S#1
            | |-VariableDecl x sym:x#6
            | | `-Type
            | |   `-Variable Int ty:ErrorType
            | |-InitDecl sym:init#8
            | | `-Parameter x label:x
            | |   `-Variable Int ty:ErrorType
            | `-SubscriptDecl sym:subscript#10
            |   |-Parameter i label:i
            |   | `-Variable Int ty:ErrorType
            |   |-ReturnType
            |   | `-Variable Int ty:ErrorType
            |   `-Return
            |     `-Variable x ty:ErrorType sym:x#6
            |-TypeAliasDecl T sym:T#2
            | `-Variable S ty:StructType(S)#0 sym:S#1
            |-ProtocolDecl Q sym:Q#3
            | `-AssociatedTypeDecl U sym:U#4
            `-EnumDecl E sym:E#5
              `-EnumCaseDecl
                |-Element a sym:a#11
                `-Element b sym:b#12
                  `-AssociatedValue x:
                    `-Variable Int ty:ErrorType
            """
    )
}

@Test func dumpTypeCheckerStructuralAnnotations() {
    #expect(
        dumpProgram(
            """
            struct S {}
            struct Box<T> {}
            typealias A = S
            let a: S
            let b: S?
            let g: Box<S>
            let h: Box<S?>
            let i: Box<A>
            let p: P & Q
            protocol P {}
            protocol Q {}
            """,
            semantic: true
        )
            == """
            Program "main"
            |-StructDecl S sym:S#1
            |-StructDecl Box sym:Box#2
            | `-GenericDecl
            |   `-GenericParameter T
            |-TypeAliasDecl A sym:A#4
            | `-Variable S ty:StructType(S)#0 sym:S#1
            |-VariableDecl a sym:a#7
            | `-Type
            |   `-Variable S ty:StructType(S)#0 sym:S#1
            |-VariableDecl b sym:b#8
            | `-Type
            |   `-OptionalType ? ty:Optional(StructType(S)#0)
            |     `-Variable S ty:StructType(S)#0 sym:S#1
            |-VariableDecl g sym:g#9
            | `-Type
            |   `-GenericApplication ty:Generic(StructType(Box)#1<StructType(S)#0>)
            |     |-Variable Box ty:StructType(Box)#1 sym:Box#2
            |     `-Argument
            |       `-Variable S ty:StructType(S)#0 sym:S#1
            |-VariableDecl h sym:h#10
            | `-Type
            |   `-GenericApplication ty:Generic(StructType(Box)#1<Optional(StructType(S)#0)>)
            |     |-Variable Box ty:StructType(Box)#1 sym:Box#2
            |     `-Argument
            |       `-OptionalType ? ty:Optional(StructType(S)#0)
            |         `-Variable S ty:StructType(S)#0 sym:S#1
            |-VariableDecl i sym:i#11
            | `-Type
            |   `-GenericApplication ty:Generic(StructType(Box)#1<StructType(S)#0>)
            |     |-Variable Box ty:StructType(Box)#1 sym:Box#2
            |     `-Argument
            |       `-Variable A ty:StructType(S)#0 sym:A#4
            |-VariableDecl p sym:p#12
            | `-Type
            |   `-SequentialExpression & ty:Composition(ProtocolType(P)#2 & ProtocolType(Q)#3)
            |     |-Variable P ty:ProtocolType(P)#2 sym:P#5
            |     `-Variable Q ty:ProtocolType(Q)#3 sym:Q#6
            |-ProtocolDecl P sym:P#5
            `-ProtocolDecl Q sym:Q#6
            """
    )
}
