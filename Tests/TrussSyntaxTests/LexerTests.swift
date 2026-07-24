import Testing
import TrussCore
import TrussSyntax

func lex(_ source: String) -> [Token] {
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexer = Lexer(input: stream)
    return lexer.parse().tokens
}

@Test func lexKeywords() {
    let tokens = lex("func return let var")
    #expect(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Func))
    #expect(tokens[0].value == "func")
    #expect(tokens[1].kind == .Keyword(.Return))
    #expect(tokens[1].value == "return")
    #expect(tokens[2].kind == .Keyword(.Let))
    #expect(tokens[2].value == "let")
    #expect(tokens[3].kind == .Keyword(.Var))
    #expect(tokens[3].value == "var")
}

@Test func lexIdentifiers() {
    let tokens = lex("foo _bar baz123 func_name")
    #expect(tokens.count == 4)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[0].value == "foo")
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "_bar")
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "baz123")
    #expect(tokens[3].kind == .Identifier)
    #expect(tokens[3].value == "func_name")
}

@Test func lexKeywordAsIdentifier() {
    let tokens = lex("let func = 5")
    #expect(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Keyword(.Func))
    #expect(tokens[1].value == "func")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexSeparators() {
    let tokens = lex("()[]{},;:")
    #expect(tokens.count == 9)
    #expect(tokens[0].kind == .Separator(.OpenParen))
    #expect(tokens[1].kind == .Separator(.CloseParen))
    #expect(tokens[2].kind == .Separator(.OpenBracket))
    #expect(tokens[3].kind == .Separator(.CloseBracket))
    #expect(tokens[4].kind == .Separator(.OpenBrace))
    #expect(tokens[5].kind == .Separator(.CloseBrace))
    #expect(tokens[6].kind == .Separator(.Comma))
    #expect(tokens[7].kind == .Separator(.SemiColon))
    #expect(tokens[8].kind == .Separator(.Colon))
}

@Test func lexSharpSeparator() {
    let tokens = lex("#")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .Separator(.Sharp))
    #expect(tokens[0].value == "#")
}

@Test func lexSingleCharOperators() {
    let tokens = lex("$ @ ~ . ? < > & | ^ ! = + - * / %")
    #expect(tokens.count == 17)
    #expect(tokens[0].kind == .Operator(.Dollar))
    #expect(tokens[1].kind == .Operator(.At))
    #expect(tokens[2].kind == .Operator(.BitNot))
    #expect(tokens[3].kind == .Operator(.Dot))
    #expect(tokens[4].kind == .Operator(.QuestionMark))
    #expect(tokens[5].kind == .Operator(.Less))
    #expect(tokens[6].kind == .Operator(.Greater))
    #expect(tokens[7].kind == .Operator(.BitAnd))
    #expect(tokens[8].kind == .Operator(.BitOr))
    #expect(tokens[9].kind == .Operator(.BitXor))
    #expect(tokens[10].kind == .Operator(.Not))
    #expect(tokens[11].kind == .Operator(.Assign))
    #expect(tokens[12].kind == .Operator(.Plus))
    #expect(tokens[13].kind == .Operator(.Minus))
    #expect(tokens[14].kind == .Operator(.Multiply))
    #expect(tokens[15].kind == .Operator(.Divide))
    #expect(tokens[16].kind == .Operator(.Modulus))
}

@Test func lexPercentOperator() {
    let tokens = lex("%")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .Operator(.Modulus))
}

@Test func lexMultiCharOperators() {
    let tokens = lex("<< <= >> >= >>> == != && || ++ -- -> += -= *= /= %= &= |= ^= <<=")
    #expect(tokens.count == 21)
    #expect(tokens[0].kind == .Operator(.LeftShift))
    #expect(tokens[0].value == "<<")
    #expect(tokens[1].kind == .Operator(.LessEqual))
    #expect(tokens[1].value == "<=")
    #expect(tokens[2].kind == .Operator(.RightShift))
    #expect(tokens[2].value == ">>")
    #expect(tokens[3].kind == .Operator(.GreaterEqual))
    #expect(tokens[3].value == ">=")
    #expect(tokens[4].kind == .Operator(.RightShiftLogical))
    #expect(tokens[4].value == ">>>")
    #expect(tokens[5].kind == .Operator(.Equal))
    #expect(tokens[5].value == "==")
    #expect(tokens[6].kind == .Operator(.NotEqual))
    #expect(tokens[6].value == "!=")
    #expect(tokens[7].kind == .Operator(.And))
    #expect(tokens[7].value == "&&")
    #expect(tokens[8].kind == .Operator(.Or))
    #expect(tokens[8].value == "||")
    #expect(tokens[9].kind == .Operator(.Inc))
    #expect(tokens[9].value == "++")
    #expect(tokens[10].kind == .Operator(.Dec))
    #expect(tokens[10].value == "--")
    #expect(tokens[11].kind == .Operator(.Arrow))
    #expect(tokens[11].value == "->")
    #expect(tokens[12].kind == .Operator(.PlusAssign))
    #expect(tokens[12].value == "+=")
    #expect(tokens[13].kind == .Operator(.MinusAssign))
    #expect(tokens[13].value == "-=")
    #expect(tokens[14].kind == .Operator(.MultiplyAssign))
    #expect(tokens[14].value == "*=")
    #expect(tokens[15].kind == .Operator(.DivideAssign))
    #expect(tokens[15].value == "/=")
    #expect(tokens[16].kind == .Operator(.ModulusAssign))
    #expect(tokens[16].value == "%=")
    #expect(tokens[17].kind == .Operator(.BitAndAssign))
    #expect(tokens[17].value == "&=")
    #expect(tokens[18].kind == .Operator(.BitOrAssign))
    #expect(tokens[18].value == "|=")
    #expect(tokens[19].kind == .Operator(.BitXorAssign))
    #expect(tokens[19].value == "^=")
    #expect(tokens[20].kind == .Operator(.LeftShiftAssign))
    #expect(tokens[20].value == "<<=")
}

@Test func lexShiftAssignOperators() {
    let tokens = lex(">>= >>>=")
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(.RightShiftAssign))
    #expect(tokens[0].value == ">>=")
    #expect(tokens[1].kind == .Operator(.RightShiftLogicalAssign))
    #expect(tokens[1].value == ">>>=")
}

@Test func lexQuestionOperators() {
    let tokens = lex("?. ?:")
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(.QuestionMarkDot))
    #expect(tokens[0].value == "?.")
    #expect(tokens[1].kind == .Operator(.Elvis))
    #expect(tokens[1].value == "?:")
}

@Test func lexXorAssignOperator() {
    let tokens = lex("^=")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .Operator(.BitXorAssign))
    #expect(tokens[0].value == "^=")
}

@Test func lexStringLiteral() {
    let tokens = lex("\"hello\"")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "\"hello\"")
}

@Test func lexStringLiteralWithEscapes() {
    let tokens = lex("\"hello\\nworld\\t\\\\\\\"\"")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "\"hello\\nworld\\t\\\\\\\"\"")
}

@Test func lexStringLiteralWithUnicode() {
    let tokens = lex("\"\\u{1F600}\"")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "\"\\u{1F600}\"")
}

@Test func lexCharLiteral() {
    let tokens = lex("'a'")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .CharLiteral("a"))
}

@Test func lexCharLiteralWithEscape() {
    let tokens = lex("'\\n'")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .CharLiteral("\n"))
}

@Test func lexCharLiteralWithUnicode() {
    let tokens = lex("'\\u{41}'")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .CharLiteral("A"))
}

@Test func lexDecimalIntegers() {
    let tokens = lex("0 42 1_000_000")
    #expect(tokens.count == 3)
    #expect(tokens[0].kind == .IntegerLiteral(0))
    #expect(tokens[1].kind == .IntegerLiteral(42))
    #expect(tokens[2].kind == .IntegerLiteral(1_000_000))
}

@Test func lexFloatNumbers() {
    let tokens = lex("3.14 0.5 1e10 1.5e-3 2E+5")
    #expect(tokens.count == 5)
    #expect(tokens[0].kind == .FloatLiteral(3.14))
    #expect(tokens[1].kind == .FloatLiteral(0.5))
    #expect(tokens[2].kind == .FloatLiteral(10000000000.0))
    #expect(tokens[3].kind == .FloatLiteral(0.0015))
    #expect(tokens[4].kind == .FloatLiteral(200000.0))
}

@Test func lexHexIntegers() {
    let tokens = lex("0xFF 0x1a_2b 0XABCD")
    #expect(tokens.count == 3)
    #expect(tokens[0].kind == .IntegerLiteral(255))
    #expect(tokens[1].kind == .IntegerLiteral(6699))
    #expect(tokens[2].kind == .IntegerLiteral(43981))
}

@Test func lexBinaryIntegers() {
    let tokens = lex("0b1010 0b1111_0000")
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .IntegerLiteral(10))
    #expect(tokens[1].kind == .IntegerLiteral(240))
}

@Test func lexOctalIntegers() {
    let tokens = lex("0o777 0o123")
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .IntegerLiteral(511))
    #expect(tokens[1].kind == .IntegerLiteral(83))
}

@Test func lexLineComment() {
    let tokens = lex("let x // this is a comment\n = 5")
    #expect(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "x")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexBlockComment() {
    let tokens = lex("let x /* comment */ = 5")
    #expect(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "x")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexNestedBlockComment() {
    let tokens = lex("let /* outer /* inner */ outer */ x = 5")
    #expect(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "x")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexUnknownCharacter() {
    let tokens = lex("`")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .Unknown)
    #expect(tokens[0].value == "`")
}

@Test func lexMixedTokens() {
    let tokens = lex("func main() { let x = 42 }")
    #expect(tokens.count == 10)
    #expect(tokens[0].kind == .Keyword(.Func))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "main")
    #expect(tokens[2].kind == .Separator(.OpenParen))
    #expect(tokens[3].kind == .Separator(.CloseParen))
    #expect(tokens[4].kind == .Separator(.OpenBrace))
    #expect(tokens[5].kind == .Keyword(.Let))
    #expect(tokens[6].kind == .Identifier)
    #expect(tokens[6].value == "x")
    #expect(tokens[7].kind == .Operator(.Assign))
    #expect(tokens[8].kind == .IntegerLiteral(42))
    #expect(tokens[9].kind == .Separator(.CloseBrace))
}

@Test func lexPositionTracking() {
    let tokens = lex("let x\n= 5")
    #expect(tokens.count == 4)
    #expect(tokens[0].pos.line == 1)
    #expect(tokens[0].pos.col == 1)
    #expect(tokens[0].pos.len == 3)
    #expect(tokens[1].pos.line == 1)
    #expect(tokens[1].pos.col == 5)
    #expect(tokens[1].pos.len == 1)
    #expect(tokens[2].pos.line == 2)
    #expect(tokens[2].pos.col == 1)
    #expect(tokens[2].pos.len == 1)
    #expect(tokens[3].pos.line == 2)
    #expect(tokens[3].pos.col == 3)
    #expect(tokens[3].pos.len == 1)
}

@Test func lexCustomOperator() {
    let tokens = lex("+++")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .Operator(nil))
    #expect(tokens[0].value == "+++")
}

@Test func lexCustomOperatorMixed() {
    let tokens = lex("<>> ===")
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(nil))
    #expect(tokens[0].value == "<>>")
    #expect(tokens[1].kind == .Operator(nil))
    #expect(tokens[1].value == "===")
}

@Test func lexCustomOperatorThenComment() {
    let tokens = lex("a /=//comment\n b")
    #expect(tokens.count == 3)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[0].value == "a")
    #expect(tokens[1].kind == .Operator(.DivideAssign))
    #expect(tokens[1].value == "/=")
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "b")
}

@Test func lexKnownOperatorNotSplit() {
    let tokens = lex("<<= >>=")
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(.LeftShiftAssign))
    #expect(tokens[0].value == "<<=")
    #expect(tokens[1].kind == .Operator(.RightShiftAssign))
    #expect(tokens[1].value == ">>=")
}

@Test func lexBooleanLiterals() {
    let tokens = lex("true false")
    #expect(tokens.count == 2)
    #expect(tokens[0].kind == .BooleanLiteral(true))
    #expect(tokens[0].value == "true")
    #expect(tokens[1].kind == .BooleanLiteral(false))
    #expect(tokens[1].value == "false")
}

@Test func lexNullLiteral() {
    let tokens = lex("null")
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .NullLiteral)
    #expect(tokens[0].value == "null")
}

@Test func lexLiteralsMixed() {
    let tokens = lex("true null false 42 3.14")
    #expect(tokens.count == 5)
    #expect(tokens[0].kind == .BooleanLiteral(true))
    #expect(tokens[1].kind == .NullLiteral)
    #expect(tokens[2].kind == .BooleanLiteral(false))
    #expect(tokens[3].kind == .IntegerLiteral(42))
    #expect(tokens[4].kind == .FloatLiteral(3.14))
}
