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
            `-FunctionDecl f sym:f
            """
    )
}

@Test func dumpVariableReferenceSemantics() {
    #expect(
        dumpProgram("func f() {\n    let a = 1\n    a\n}", semantic: true)
            == """
            Program "main"
            `-FunctionDecl f sym:f
              |-VariableDecl a sym:a
              | `-Initializer
              |   `-IntegerLiteral 1
              `-ExpressionStatement
                `-Variable a sym:a
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
