import Testing
import TrussCore

@Test
func dumpSimpleFunction() {
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

@Test
func dumpForWithWhereClause() {
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

@Test
func dumpFunctionDeclSemantics() {
    #expect(
        dumpProgram("func f() {}", semantic: true)
            == """
            Program "main"
            `-FunctionDecl f sym:f#1
            """
    )
}

@Test
func dumpVariableReferenceSemantics() {
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

@Test
func dumpLiterals() {
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

@Test
func dumpPrefixOperators() {
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

@Test
func dumpIfElse() {
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

@Test
func dumpModuleAndStruct() {
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

@Test
func dumpClosure() {
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

@Test
func dumpStringInterpolation() {
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

@Test
func dumpPrecedenceGroup() {
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

@Test
func dumpAsm() {
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

@Test
func dumpPostfixOperator() {
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

@Test
func dumpTypeDeclSemantics() {
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
            |   `-Variable P1 ty:ProtocolType(P1)#0 sym:P1#1
            `-ActorDecl A sym:A#6
            """
    )
}

@Test
func dumpOverloadsSemantics() {
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
                `-Call ty:VoidType
                  |-Variable f ty:func(a: ErrorType, b: ErrorType) -> VoidType sym:f#3 overloads:2 [f(a:, b: =), f(xs: ...)] willBeCalled
                  `-Argument label:a
                    `-IntegerLiteral 1
            """
    )
}

@Test
func dumpTypeMemberSemantics() {
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
            | |-InitDecl sym:init#9
            | | `-Parameter x label:x
            | |   `-Variable Int ty:ErrorType
            | `-SubscriptDecl sym:subscript#13
            |   |-Parameter i label:i
            |   | `-Variable Int ty:ErrorType
            |   |-ReturnType
            |   | `-Variable Int ty:ErrorType
            |   `-Accessor get
            |     `-Return
            |       `-Variable x ty:ErrorType sym:x#6
            |-TypeAliasDecl T sym:T#2
            | `-Variable S ty:StructType(S)#0 sym:S#1
            |-ProtocolDecl Q sym:Q#3
            | `-AssociatedTypeDecl U sym:U#4
            `-EnumDecl E sym:E#5
              `-EnumCaseDecl
                |-Element a sym:a#14
                `-Element b sym:b#15
                  `-AssociatedValue x:
                    `-Variable Int ty:ErrorType
            """
    )
}

@Test
func dumpTypeCheckerStructuralAnnotations() {
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
            |   `-ProtocolCompositionType & ty:Composition(ProtocolType(P)#2 & ProtocolType(Q)#3)
            |     |-Variable P ty:ProtocolType(P)#2 sym:P#5
            |     `-Variable Q ty:ProtocolType(Q)#3 sym:Q#6
            |-ProtocolDecl P sym:P#5
            `-ProtocolDecl Q sym:Q#6
            """
    )
}

@Test
func dumpPointerSemantics() {
    #expect(
        dumpProgram(
            "struct Int {}\nfunc f() {\n    var v: Int\n    var p: Int* = &v\n    var x = *p\n}",
            semantic: true
        ) == """
        Program "main"
        |-StructDecl Int sym:Int#1
        `-FunctionDecl f sym:f#5
          |-VariableDecl v sym:v#2
          | `-Type
          |   `-Variable Int ty:StructType(Int)#0 sym:Int#1
          |-VariableDecl p sym:p#3
          | |-Type
          | | `-PointerType * ty:Pointer(StructType(Int)#0)
          | |   `-Variable Int ty:StructType(Int)#0 sym:Int#1
          | `-Initializer
          |   `-AddressOf & ty:Pointer(StructType(Int)#0!)
          |     `-Variable v ty:StructType(Int)#0 sym:v#2 lvalue
          `-VariableDecl x sym:x#4
            `-Initializer
              `-Dereference * ty:StructType(Int)#0
                `-Variable p ty:Pointer(StructType(Int)#0) sym:p#3
        """
    )
}

@Test
func dumpAssignmentLeftValueSemantics() {
    #expect(
        dumpProgram(
            """
            func f() {
                var a = 1
                a = 2
            }
            """,
            semantic: true
        ) == """
        Program "main"
        `-FunctionDecl f sym:f#2
          |-VariableDecl a sym:a#1
          | `-Initializer
          |   `-IntegerLiteral 1
          `-ExpressionStatement
            `-Binary =
              |-Variable a sym:a#1 lvalue
              `-IntegerLiteral 2
        """
    )
}

@Test
func dumpMemberAssignmentLeftValueSemantics() {
    #expect(
        dumpProgram(
            """
            struct S {
                var x = 1
                func f() {
                    self.x = 2
                }
            }
            """,
            semantic: true
        ) == """
        Program "main"
        `-StructDecl S sym:S#1
          |-VariableDecl x sym:x#2
          | `-Initializer
          |   `-IntegerLiteral 1
          `-FunctionDecl f sym:f#4
            `-ExpressionStatement
              `-Binary = ty:ErrorType
                |-MemberAccess x ty:ErrorType sym:x#2 lvalue
                | `-SelfExpression ty:StructType(S)#0 sym:self#3 lvalue
                `-IntegerLiteral 2
        """
    )
}

@Test
func dumpSubscriptAssignmentLeftValueSemantics() {
    #expect(
        dumpProgram(
            """
            struct S {
                var x = 1
                init() {
                    x = 0
                }
                subscript(i: Int) -> Int {
                    get { x }
                    set { x = newValue }
                }
            }
            func f() {
                var s = S()
                s[0] = 2
            }
            """,
            semantic: true
        ) == """
        Program "main"
        |-StructDecl S sym:S#1
        | |-VariableDecl x sym:x#2
        | | `-Initializer
        | |   `-IntegerLiteral 1
        | |-InitDecl sym:init#4
        | | `-ExpressionStatement
        | |   `-Binary =
        | |     |-Variable x sym:x#2 lvalue
        | |     `-IntegerLiteral 0
        | `-SubscriptDecl sym:subscript#11
        |   |-Parameter i label:i
        |   | `-Variable Int ty:ErrorType
        |   |-ReturnType
        |   | `-Variable Int ty:ErrorType
        |   |-Accessor get
        |   | `-ExpressionStatement
        |   |   `-Variable x sym:x#2
        |   `-Accessor set
        |     `-ExpressionStatement
        |       `-Binary =
        |         |-Variable x sym:x#2 lvalue
        |         `-Variable newValue ty:ErrorType sym:newValue#6
        `-FunctionDecl f sym:f#13
          |-VariableDecl s sym:s#12
          | `-Initializer
          |   `-Call ty:Generic(StructType(S)#0<>)
          |     `-Variable S ty:StructType(S)#0.func() -> StructType(S)#0 sym:init#4 willBeCalled
          `-ExpressionStatement
            `-Binary = ty:VoidType
              |-Subscript ty:VoidType lvalue
              | |-Variable s ty:Generic(StructType(S)#0<>) sym:s#12
              | `-Argument
              |   `-IntegerLiteral 0
              `-IntegerLiteral 2
        """
    )
}

@Test
func dumpCallCalleeWillBeCalledSemantics() {
    #expect(
        dumpProgram(
            """
            func g() {}
            func f() {
                g()
            }
            """,
            semantic: true
        ) == """
        Program "main"
        |-FunctionDecl g sym:g#1
        `-FunctionDecl f sym:f#2
          `-ExpressionStatement
            `-Call ty:VoidType
              `-Variable g ty:func() -> VoidType sym:g#1 overloads:1 [g()] willBeCalled
        """
    )
}

@Test
func dumpFunctionTypeSyntax() {
    #expect(
        dumpProgram("let f: func(x: Int) -> Void")
            == """
            Program "main"
            `-VariableDecl f
              `-Type
                `-FunctionType
                  |-Parameter label:x
                  | `-Variable Int
                  `-Variable Void
            """
    )
}

@Test
func dumpClosureTypeSyntax() {
    #expect(
        dumpProgram("let f: (x: Int) -> Void")
            == """
            Program "main"
            `-VariableDecl f
              `-Type
                `-ClosureType
                  |-Parameter label:x
                  | `-Variable Int
                  `-Variable Void
            """
    )
}

@Test
func dumpFunctionAndClosureTypeText() {
    #expect(
        dumpProgram(
            """
            struct S {}
            let f: func(x: S) -> S
            let c: (x: S) -> S
            """,
            semantic: true
        ) == """
        Program "main"
        |-StructDecl S sym:S#1
        |-VariableDecl f sym:f#2
        | `-Type
        |   `-FunctionType ty:func(x: StructType(S)#0) -> StructType(S)#0
        |     |-Parameter label:x
        |     | `-Variable S ty:StructType(S)#0 sym:S#1
        |     `-Variable S ty:StructType(S)#0 sym:S#1
        `-VariableDecl c sym:c#3
          `-Type
            `-ClosureType ty:(x: StructType(S)#0) -> StructType(S)#0
              |-Parameter label:x
              | `-Variable S ty:StructType(S)#0 sym:S#1
              `-Variable S ty:StructType(S)#0 sym:S#1
        """
    )
}

@Test
func dumpVariadicFunctionAndClosureTypeText() {
    let dump = dumpProgram(
        """
        struct S {}
        let f: func(x: S...) -> S
        let c: (x: S...) -> S
        """,
        semantic: true
    )
    #expect(dump.contains("FunctionType ty:func(x: StructType(S)#0...) -> StructType(S)#0"))
    #expect(dump.contains("ClosureType ty:(x: StructType(S)#0...) -> StructType(S)#0"))
}

private let foldedOperatorPrelude = """
precedencegroup ExponentiationPrecedence {
    higherThan: MultiplicationPrecedence
    associativity: right
}
precedencegroup MultiplicationPrecedence {
    higherThan: AdditionPrecedence
    associativity: left
}
precedencegroup AdditionPrecedence {
    higherThan: AssignmentPrecedence
    associativity: left
}
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator ^ : ExponentiationPrecedence
infix operator * : MultiplicationPrecedence
infix operator + : AdditionPrecedence
infix operator - : AdditionPrecedence
infix operator = : AssignmentPrecedence
prefix operator -
postfix operator ++
typealias Int = Builtin.Int32
func ^ (lhs: Int, rhs: Int) -> Int { return lhs }
func * (lhs: Int, rhs: Int) -> Int { return lhs }
func + (lhs: Int, rhs: Int) -> Int { return lhs }
func - (lhs: Int, rhs: Int) -> Int { return lhs }
func = (lhs: Int, rhs: Int) -> Int { return lhs }
func - (prefixValue: Int) -> Int { return prefixValue }
func ++ (postfixValue: Int) -> Int { return postfixValue }
func id(_ value: Int) -> Int { return value }
"""

private func foldedFunctionSource(_ body: String) -> String {
    foldedOperatorPrelude + "\nfunc f(a: Int, b: Int, c: Int) {\n" + body + "\n}\n"
}

private func foldedSource(_ source: String) -> String {
    SourcePrinter().print(parseProgram(source, semantic: true))
}

private func foldedDump(_ source: String) -> String {
    AST.Dumper().dump(parseProgram(source, semantic: true))
}

private func assertFoldedRoundTrip(_ source: String) {
    let printed = foldedSource(source)
    let reparsed = foldedDump(printed)
    #expect(
        reparsed == foldedDump(source),
        "folded round-trip failed for:\n\(source)\nprinted:\n\(printed)"
    )
    #expect(foldedSource(printed) == printed, "folded printing is not idempotent:\n\(printed)")
}

@Test
func foldedSourceKeepsLowerPrecedenceLeftOperandParenthesized() {
    let source = foldedFunctionSource("    let x = (1 + 2) * 3")
    let printed = foldedSource(source)
    #expect(printed.contains("let x = (1 + 2) * 3"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceKeepsLowerPrecedenceRightOperandParenthesized() {
    let source = foldedFunctionSource("    let x = 1 - (2 - 3)\n    let y = 1 - 2 - 3")
    let printed = foldedSource(source)
    #expect(printed.contains("let x = 1 - (2 - 3)"))
    #expect(printed.contains("let y = 1 - 2 - 3"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceKeepsRightAssociativeOperandParenthesized() {
    let source = foldedFunctionSource("    let x = a ^ b ^ c\n    let y = (a ^ b) ^ c")
    let printed = foldedSource(source)
    #expect(printed.contains("let x = a ^ b ^ c"))
    #expect(printed.contains("let y = (a ^ b) ^ c"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceKeepsAssignmentOperandParenthesized() {
    let source = foldedFunctionSource("    a = b = c")
    #expect(foldedSource(source).contains("a = b = c"))
    assertFoldedRoundTrip(source)

    let leftNested = foldedFunctionSource("    (a = b) = c")
    #expect(foldedSource(leftNested).contains("(a = b) = c"))
    assertFoldedRoundTrip(leftNested)
}

@Test
func foldedSourceKeepsPrefixAndPostfixOperandsGrouped() {
    let source = foldedFunctionSource(
        "    let x = -(a + b)\n    let y = -a * b\n    let z = (a + b)++\n    let w = a++ * b"
    )
    let printed = foldedSource(source)
    #expect(printed.contains("let x = -(a + b)"))
    #expect(printed.contains("let y = -a * b"))
    #expect(printed.contains("let z = (a + b)++"))
    #expect(printed.contains("let w = a++ * b"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceSeparatesAdjacentPrefixAndPostfixOperators() {
    let source = foldedFunctionSource("    let x = - -a\n    let y = a! !")
    let printed = foldedSource(source)
    #expect(printed.contains("let x = - -a"))
    #expect(printed.contains("let y = a! !"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceKeepsParenthesizedFunctionReference() {
    let source = foldedFunctionSource("    let x: (Int) -> Int = (id)\n    return")
    let printed = foldedSource(source)
    #expect(printed.contains("let x: (Int) -> Int = (id)"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceKeepsGroupedOperandsInsideClosureBody() {
    let source = foldedFunctionSource("    let x = { (y: Int) -> Int in (y + 1) * 2 }")
    let printed = foldedSource(source)
    #expect(printed.contains("in (y + 1) * 2"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceKeepsGroupedOperandsInMemberAccessAndSubscript() {
    let source = """
    precedencegroup AdditionPrecedence {
        higherThan: AssignmentPrecedence
        associativity: left
    }
    precedencegroup AssignmentPrecedence {
        associativity: right
        assignment: true
    }
    infix operator + : AdditionPrecedence
    infix operator = : AssignmentPrecedence
    typealias Int = Builtin.Int32
    struct S {
        let x: Int
        subscript(i: Int) -> Int {
            return i
        }
    }
    func + (lhs: S, rhs: S) -> S { return lhs }
    func f(a: S, b: S) {
        let m = (a + b).x
        let s = (a + b)[1]
    }
    """
    let printed = foldedSource(source)
    #expect(printed.contains("let m = (a + b).x"))
    #expect(printed.contains("let s = (a + b)[1]"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceParenthesizesOperatorReferences() {
    let source = foldedFunctionSource(
        "    let g: (Int, Int) -> Int = (+)\n"
            + "    let h: (Int, Int) -> Int = (-)\n"
            + "    let i: (Int) -> Int = (++)\n"
            + "    let r = (+)(a, b)"
    )
    let printed = foldedSource(source)
    #expect(printed.contains("let g: (Int, Int) -> Int = (+)"))
    #expect(printed.contains("let h: (Int, Int) -> Int = (-)"))
    #expect(printed.contains("let i: (Int) -> Int = (++)"))
    #expect(printed.contains("let r = (+)(a, b)"))
    #expect(!printed.contains("= +"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourceKeepsMemberOperatorReferenceUnparenthesized() {
    let source = """
    precedencegroup AdditionPrecedence {
        higherThan: AssignmentPrecedence
        associativity: left
    }
    precedencegroup AssignmentPrecedence {
        associativity: right
        assignment: true
    }
    infix operator + : AdditionPrecedence
    infix operator = : AssignmentPrecedence
    typealias Int = Builtin.Int32
    struct S {
        let v: Int
        func +(rhs: S) -> S { return rhs }
    }
    func f(s: S) {
        let m = s.+
    }
    """
    let printed = foldedSource(source)
    #expect(printed.contains("let m = s.+"))
    #expect(!printed.contains("s.(+)"))
    assertFoldedRoundTrip(source)
}

private let closureCallPrelude = """
typealias Int32 = Builtin.Int32
func take(body: () -> Void) { return }
func take1(body: (Int32) -> Void) { return }
func take2(a: Int32, body: () -> Void) { return }
"""

private func closureFunctionSource(_ body: String) -> String {
    closureCallPrelude + "\nfunc f() {\n" + body + "\n}\n"
}

private func braceCount(_ text: String, _ brace: Character) -> Int {
    text.filter { $0 == brace }.count
}

@Test
func foldedSourcePrintsBalancedTrailingClosures() {
    let source = closureFunctionSource(
        "    take { }\n"
            + "    take {\n        let x = 1\n        return\n    }\n"
            + "    take1 { (y: Int32) in return }\n"
            + "    take2(a: 1) { }"
    )
    let printed = foldedSource(source)
    #expect(printed.contains("take() { }"))
    #expect(printed.contains("take2(a: 1) { }"))
    #expect(printed.contains("take1() { (y: Int32) in"))
    #expect(printed.contains("let x = 1"))
    #expect(!printed.contains("{ {"))
    #expect(braceCount(printed, "{") == braceCount(printed, "}"))
    assertFoldedRoundTrip(source)
}

@Test
func foldedSourcePrintsBalancedStandaloneClosures() {
    let source = closureFunctionSource(
        "    let g: () -> Void = { }\n"
            + "    let h: () -> Int32 = { 1 }\n"
            + "    let i: () -> Int32 = {\n        let x = 1\n        x\n    }\n"
            + "    let j: (Int32) -> Int32 = { (z: Int32) in z }\n"
            + "    let y = 1\n"
            + "    let k: () -> Int32 = { [y] in y }\n"
            + "    let m: (Int32) -> Void = { (z: Int32) in }"
    )
    let printed = foldedSource(source)
    #expect(printed.contains("let g: () -> Void = { }"))
    #expect(printed.contains("let h: () -> Int32 = { 1 }"))
    #expect(printed.contains("let j: (Int32) -> Int32 = { (z: Int32) in z }"))
    #expect(printed.contains("let k: () -> Int32 = { [y] in y }"))
    #expect(printed.contains("let m: (Int32) -> Void = { (z: Int32) in }"))
    #expect(!printed.contains("{ {"))
    #expect(braceCount(printed, "{") == braceCount(printed, "}"))
    assertFoldedRoundTrip(source)
}
