import Testing
import TrussCore
import TrussSyntax

func lex(_ source: String) -> [Token] {
    let stream = CharStream(content: source, id: Id.SourceId(id: 0))
    let lexer = Lexer(input: stream)
    return lexer.parse().tokens
}

@Test func lexKeywords() throws {
    let tokens = lex("func return let var")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Func))
    #expect(tokens[0].value == "func")
    #expect(tokens[1].kind == .Keyword(.Return))
    #expect(tokens[1].value == "return")
    #expect(tokens[2].kind == .Keyword(.Let))
    #expect(tokens[2].value == "let")
    #expect(tokens[3].kind == .Keyword(.Var))
    #expect(tokens[3].value == "var")
}

@Test func lexIdentifiers() throws {
    let tokens = lex("foo _bar baz123 func_name")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[0].value == "foo")
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "_bar")
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "baz123")
    #expect(tokens[3].kind == .Identifier)
    #expect(tokens[3].value == "func_name")
}

@Test func lexKeywordAsIdentifier() throws {
    let tokens = lex("let func = 5")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Keyword(.Func))
    #expect(tokens[1].value == "func")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexBacktickKeywordAsIdentifier() throws {
    let tokens = lex("`public`")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[0].value == "public")
}

@Test func lexBacktickRegularIdentifier() throws {
    let tokens = lex("`foo`")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[0].value == "foo")
}

@Test func lexBacktickKeywordInContext() throws {
    let tokens = lex("let `func` = 5")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "func")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexMultipleBacktickKeywords() throws {
    let tokens = lex("`public` `private` `class`")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[0].value == "public")
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "private")
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "class")
}

@Test func lexBacktickPositionTracking() throws {
    let tokens = lex("`public`")
    try #require(tokens.count == 1)
    #expect(tokens[0].pos.col == 1)
    #expect(tokens[0].pos.len == 8)
}

@Test func lexUnclosedBacktick() throws {
    let tokens = lex("`public")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Unknown)
}

@Test func lexEmptyBackticks() throws {
    let tokens = lex("``")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Unknown)
}

@Test func lexSeparators() throws {
    let tokens = lex("()[]{},;:")
    try #require(tokens.count == 9)
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

@Test func lexSharpSeparator() throws {
    let tokens = lex("#")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Separator(.Sharp))
    #expect(tokens[0].value == "#")
}

@Test func lexSingleCharOperators() throws {
    let tokens = lex("$ @ ~ . ? < > & | ^ ! = + - * / %")
    try #require(tokens.count == 17)
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

@Test func lexPercentOperator() throws {
    let tokens = lex("%")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Operator(.Modulus))
}

@Test func lexMultiCharOperators() throws {
    let tokens = lex("<< <= >> >= >>> == != && || ++ -- -> += -= *= /= %= &= |= ^= <<=")
    try #require(tokens.count == 21)
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
    #expect(tokens[11].kind == .Separator(.Arrow))
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

@Test func lexShiftAssignOperators() throws {
    let tokens = lex(">>= >>>=")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(.RightShiftAssign))
    #expect(tokens[0].value == ">>=")
    #expect(tokens[1].kind == .Operator(.RightShiftLogicalAssign))
    #expect(tokens[1].value == ">>>=")
}

@Test func lexQuestionOperators() throws {
    let tokens = lex("?. ?:")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(.QuestionMarkDot))
    #expect(tokens[0].value == "?.")
    #expect(tokens[1].kind == .Operator(.Elvis))
    #expect(tokens[1].value == "?:")
}

@Test func lexRangeOperators() throws {
    let tokens = lex(".. ..< ...")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .Operator(.DotDot))
    #expect(tokens[0].value == "..")
    #expect(tokens[1].kind == .Operator(.DotDotLess))
    #expect(tokens[1].value == "..<")
    #expect(tokens[2].kind == .Operator(.DotDotDot))
    #expect(tokens[2].value == "...")
}

@Test func lexRangeOperatorsInCode() throws {
    let tokens = lex("1..<5")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .IntegerLiteral(1))
    #expect(tokens[1].kind == .Operator(.DotDotLess))
    #expect(tokens[2].kind == .IntegerLiteral(5))
}

@Test func lexXorAssignOperator() throws {
    let tokens = lex("^=")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Operator(.BitXorAssign))
    #expect(tokens[0].value == "^=")
}

@Test func lexStringLiteral() throws {
    let tokens = lex("\"hello\"")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "hello")
}

@Test func lexStringLiteralWithEscapes() throws {
    let tokens = lex("\"hello\\nworld\\t\\\\\\\"\"")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "hello\nworld\t\\\"")
}

@Test func lexStringLiteralWithUnicode() throws {
    let tokens = lex("\"\\u{1F600}\"")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "😀")
}

@Test func lexMultilineStringBasic() throws {
    let src = "\"\"\"\nhello\nworld\n\"\"\""
    let tokens = lex(src)
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "hello\nworld\n")
}

@Test func lexMultilineStringWithIndentation() throws {
    let src = "\"\"\"\n    hello\n    world\n    \"\"\""
    let tokens = lex(src)
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "hello\nworld\n")
}

@Test func lexMultilineStringWithEscapes() throws {
    let src = "\"\"\"\nhello\\nworld\n\"\"\""
    let tokens = lex(src)
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "hello\nworld\n")
}

@Test func lexStringLineContinuation() throws {
    let tokens = lex("\"foo\\\nbar\"")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "foobar")
}

@Test func lexStringLineContinuationCRLF() throws {
    let tokens = lex("\"foo\\\u{0D}\u{0A}bar\"")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "foobar")
}

@Test func lexMultilineStringLineContinuation() throws {
    let src = "\"\"\"\nfoo\\\nbar\n\"\"\""
    let tokens = lex(src)
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "foobar\n")
}

@Test func lexCodeLineContinuation() throws {
    let tokens = lex("let x = 1 + \\\n2")
    try #require(tokens.count == 6)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(1))
    #expect(tokens[4].kind == .Operator(.Plus))
    #expect(tokens[5].kind == .IntegerLiteral(2))
}

@Test func lexCodeLineContinuationCRLF() throws {
    let tokens = lex("let x = 1 + \\\u{0D}\u{0A}2")
    try #require(tokens.count == 6)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(1))
    #expect(tokens[4].kind == .Operator(.Plus))
    #expect(tokens[5].kind == .IntegerLiteral(2))
}

@Test func lexCharLiteral() throws {
    let tokens = lex("'a'")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .CharLiteral("a"))
}

@Test func lexCharLiteralWithEscape() throws {
    let tokens = lex("'\\n'")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .CharLiteral("\n"))
}

@Test func lexCharLiteralWithUnicode() throws {
    let tokens = lex("'\\u{41}'")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .CharLiteral("A"))
}

@Test func lexDecimalIntegers() throws {
    let tokens = lex("0 42 1_000_000")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .IntegerLiteral(0))
    #expect(tokens[1].kind == .IntegerLiteral(42))
    #expect(tokens[2].kind == .IntegerLiteral(1_000_000))
}

@Test func lexFloatNumbers() throws {
    let tokens = lex("3.14 0.5 1e10 1.5e-3 2E+5")
    try #require(tokens.count == 5)
    #expect(tokens[0].kind == .FloatLiteral(3.14))
    #expect(tokens[1].kind == .FloatLiteral(0.5))
    #expect(tokens[2].kind == .FloatLiteral(10_000_000_000.0))
    #expect(tokens[3].kind == .FloatLiteral(0.0015))
    #expect(tokens[4].kind == .FloatLiteral(200_000.0))
}

@Test func lexHexIntegers() throws {
    let tokens = lex("0xFF 0x1a_2b 0XABCD")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .IntegerLiteral(255))
    #expect(tokens[1].kind == .IntegerLiteral(6699))
    #expect(tokens[2].kind == .IntegerLiteral(43981))
}

@Test func lexBinaryIntegers() throws {
    let tokens = lex("0b1010 0b1111_0000")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .IntegerLiteral(10))
    #expect(tokens[1].kind == .IntegerLiteral(240))
}

@Test func lexOctalIntegers() throws {
    let tokens = lex("0o777 0o123")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .IntegerLiteral(511))
    #expect(tokens[1].kind == .IntegerLiteral(83))
}

@Test func lexLineComment() throws {
    let tokens = lex("let x // this is a comment\n = 5")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "x")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexBlockComment() throws {
    let tokens = lex("let x /* comment */ = 5")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "x")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexNestedBlockComment() throws {
    let tokens = lex("let /* outer /* inner */ outer */ x = 5")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Keyword(.Let))
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[1].value == "x")
    #expect(tokens[2].kind == .Operator(.Assign))
    #expect(tokens[3].kind == .IntegerLiteral(5))
}

@Test func lexUnknownCharacter() throws {
    let tokens = lex("`")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Unknown)
    #expect(tokens[0].value == "`")
}

@Test func lexMixedTokens() throws {
    let tokens = lex("func main() { let x = 42 }")
    try #require(tokens.count == 10)
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

@Test func lexPositionTracking() throws {
    let tokens = lex("let x\n= 5")
    try #require(tokens.count == 4)
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

@Test func lexCustomOperator() throws {
    let tokens = lex("+++")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Operator(nil))
    #expect(tokens[0].value == "+++")
}

@Test func lexCustomOperatorMixed() throws {
    let tokens = lex("<>> ===")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(nil))
    #expect(tokens[0].value == "<>>")
    #expect(tokens[1].kind == .Operator(nil))
    #expect(tokens[1].value == "===")
}

@Test func lexCustomOperatorThenComment() throws {
    let tokens = lex("a /=//comment\n b")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[0].value == "a")
    #expect(tokens[1].kind == .Operator(.DivideAssign))
    #expect(tokens[1].value == "/=")
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "b")
}

@Test func lexKnownOperatorNotSplit() throws {
    let tokens = lex("<<= >>=")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .Operator(.LeftShiftAssign))
    #expect(tokens[0].value == "<<=")
    #expect(tokens[1].kind == .Operator(.RightShiftAssign))
    #expect(tokens[1].value == ">>=")
}

@Test func lexBooleanLiterals() throws {
    let tokens = lex("true false")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .BooleanLiteral(true))
    #expect(tokens[0].value == "true")
    #expect(tokens[1].kind == .BooleanLiteral(false))
    #expect(tokens[1].value == "false")
}

@Test func lexNullLiteral() throws {
    let tokens = lex("null")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .NullLiteral)
    #expect(tokens[0].value == "null")
}

@Test func lexLiteralsMixed() throws {
    let tokens = lex("true null false 42 3.14")
    try #require(tokens.count == 5)
    #expect(tokens[0].kind == .BooleanLiteral(true))
    #expect(tokens[1].kind == .NullLiteral)
    #expect(tokens[2].kind == .BooleanLiteral(false))
    #expect(tokens[3].kind == .IntegerLiteral(42))
    #expect(tokens[4].kind == .FloatLiteral(3.14))
}

// MARK: - Edge Cases

@Test func lexUnterminatedStringLiteral() throws {
    let tokens = lex("\"abc")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "abc")
    #expect(!tokens[0].isUnterminated)
}

@Test func lexUnterminatedMultilineString() throws {
    let tokens = lex("\"\"\"\nabc\n")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "abc\n")
}

@Test func lexEmptyMultilineString() throws {
    let tokens = lex("\"\"\"\"\"\"")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
}

@Test func lexSharpAlone() throws {
    let tokens = lex("#")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .Separator(.Sharp))
    #expect(tokens[0].value == "#")
}

@Test func lexSharpFollowedByBracket() throws {
    let tokens = lex("#[")
    try #require(tokens.count == 2)
    #expect(tokens[0].kind == .Separator(.Sharp))
    #expect(tokens[1].kind == .Separator(.OpenBracket))
}

@Test func lexStringWithInterpolationTokenSplit() throws {
    let tokens = lex("\"a\\(b)\"")
    try #require(tokens.count == 5)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "a")
    #expect(tokens[0].isUnterminated)
    #expect(tokens[1].kind == .Separator(.OpenParen))
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "b")
    #expect(tokens[3].kind == .Separator(.CloseParen))
    #expect(tokens[4].kind == .StringLiteral)
    #expect(tokens[4].value == "")
}

@Test func lexStringWithNestedInterpolationTokenSplit() throws {
    let tokens = lex("\"\\(foo(\\(bar)))\"")
    try #require(tokens.count == 11)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "")
    #expect(tokens[0].isUnterminated)
    #expect(tokens[1].kind == .Separator(.OpenParen))
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "foo")
    #expect(tokens[3].kind == .Separator(.OpenParen))
    #expect(tokens[4].kind == .StringLiteral)
    #expect(tokens[4].value == "")
    #expect(tokens[4].isUnterminated)
    #expect(tokens[5].kind == .Separator(.OpenParen))
    #expect(tokens[6].kind == .Identifier)
    #expect(tokens[6].value == "bar")
    #expect(tokens[7].kind == .Separator(.CloseParen))
    #expect(tokens[8].kind == .Separator(.CloseParen))
    #expect(tokens[9].kind == .Separator(.CloseParen))
    #expect(tokens[10].kind == .StringLiteral)
    #expect(tokens[10].value == "")
    #expect(!tokens[10].isUnterminated)
}

@Test func lexStringWithCallInsideInterpolation() throws {
    let tokens = lex("\"a\\(f(x))b\"")
    try #require(tokens.count == 8)
    #expect(tokens[0].value == "a")
    #expect(tokens[0].isUnterminated)
    #expect(tokens[1].kind == .Separator(.OpenParen))
    #expect(tokens[2].value == "f")
    #expect(tokens[3].kind == .Separator(.OpenParen))
    #expect(tokens[4].value == "x")
    #expect(tokens[5].kind == .Separator(.CloseParen))
    #expect(tokens[6].kind == .Separator(.CloseParen))
    #expect(tokens[7].kind == .StringLiteral)
    #expect(tokens[7].value == "b")
}

@Test func lexRawStringBasic() throws {
    let tokens = lex("#\"hello\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "hello")
}

@Test func lexRawStringEmpty() throws {
    let tokens = lex("#\"\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "")
}

@Test func lexRawStringContentWithQuote() throws {
    let tokens = lex("#\"a\"b\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "a\"b")
}

@Test func lexRawStringBackslashLiteral() throws {
    let tokens = lex("#\"a\\nb\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "a\\nb")
}

@Test func lexRawStringHashInsideContent() throws {
    let tokens = lex("#\"a#\"b\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "a#\"b")
}

@Test func lexRawStringInterpolationTokenSplit() throws {
    let tokens = lex("#\"a\\#(b)c\"#")
    try #require(tokens.count == 5)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "a")
    #expect(tokens[0].isRaw)
    #expect(tokens[0].isUnterminated)
    #expect(tokens[1].kind == .Separator(.OpenParen))
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "b")
    #expect(tokens[3].kind == .Separator(.CloseParen))
    #expect(tokens[4].kind == .StringLiteral)
    #expect(tokens[4].value == "c")
    #expect(tokens[4].isRaw)
    #expect(!tokens[4].isUnterminated)
}

@Test func lexRawStringEmptyTrailingInterpolation() throws {
    let tokens = lex("#\"a\\#(b)\"#")
    try #require(tokens.count == 5)
    #expect(tokens[4].kind == .StringLiteral)
    #expect(tokens[4].value == "")
    #expect(tokens[4].isRaw)
    #expect(!tokens[4].isUnterminated)
}

@Test func lexRawStringBackslashHashNotInterpolation() throws {
    let tokens = lex("#\"a\\#x\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "a\\#x")
}

@Test func lexRawMultilineStringBasic() throws {
    let tokens = lex("#\"\"\"\nhello\nworld\n\"\"\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "hello\nworld\n")
}

@Test func lexRawMultilineStringWithIndentation() throws {
    let tokens = lex("#\"\"\"\n    hello\n    world\n    \"\"\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "hello\nworld\n")
}

@Test func lexRawMultilineStringBackslashLiteral() throws {
    let tokens = lex("#\"\"\"\nhello\\nworld\n\"\"\"#")
    try #require(tokens.count == 1)
    #expect(tokens[0].isRaw)
    #expect(tokens[0].value == "hello\\nworld\n")
}

@Test func lexMultilineStringInterpolationTokenSplit() throws {
    let tokens = lex("\"\"\"\nhello \\(x) world\n\"\"\"")
    try #require(tokens.count == 5)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "hello ")
    #expect(tokens[0].isUnterminated)
    #expect(tokens[1].kind == .Separator(.OpenParen))
    #expect(tokens[2].kind == .Identifier)
    #expect(tokens[2].value == "x")
    #expect(tokens[3].kind == .Separator(.CloseParen))
    #expect(tokens[4].kind == .StringLiteral)
    #expect(tokens[4].value == " world\n")
    #expect(!tokens[4].isUnterminated)
}

@Test func lexMultilineStringInterpolationWithIndentation() throws {
    let tokens = lex("\"\"\"\n    hello \\(x)\n    world\n    \"\"\"")
    try #require(tokens.count == 5)
    #expect(tokens[0].value == "hello ")
    #expect(tokens[0].isUnterminated)
    #expect(tokens[4].value == "\nworld\n")
    #expect(!tokens[4].isUnterminated)
}

@Test func lexRawMultilineStringInterpolation() throws {
    let tokens = lex("#\"\"\"\nhello \\#(x)\nworld\n\"\"\"#")
    try #require(tokens.count == 5)
    #expect(tokens[0].kind == .StringLiteral)
    #expect(tokens[0].value == "hello ")
    #expect(tokens[0].isRaw)
    #expect(tokens[0].isUnterminated)
    #expect(tokens[4].kind == .StringLiteral)
    #expect(tokens[4].value == "\nworld\n")
    #expect(tokens[4].isRaw)
    #expect(!tokens[4].isUnterminated)
}

@Test func lexSharpDirectiveUnaffected() throws {
    let tokens = lex("#if X")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .Separator(.Sharp))
    #expect(tokens[1].kind == .Keyword(.If))
    #expect(tokens[2].kind == .Identifier)
}

@Test func lexSharpPasteUnaffected() throws {
    let tokens = lex("A ## B")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Identifier)
    #expect(tokens[1].kind == .Separator(.Sharp))
    #expect(tokens[2].kind == .Separator(.Sharp))
    #expect(tokens[3].kind == .Identifier)
}

@Test func lexBackslashOperator() throws {
    let tokens = lex("\\Person.name")
    try #require(tokens.count == 4)
    #expect(tokens[0].kind == .Operator(.Backslash))
    #expect(tokens[0].value == "\\")
    #expect(tokens[1].kind == .Identifier)
    #expect(tokens[2].kind == .Operator(.Dot))
    #expect(tokens[3].kind == .Identifier)
}

@Test func lexBackslashLineContinuationStillWorks() throws {
    let tokens = lex("1 + \\\n2")
    try #require(tokens.count == 3)
    #expect(tokens[0].kind == .IntegerLiteral(1))
    #expect(tokens[1].kind == .Operator(.Plus))
    #expect(tokens[2].kind == .IntegerLiteral(2))
}
