import TrussCore

let keywordMap: [KeywordKind: String] = {
    var map: [KeywordKind: String] = [:]
    for keyword in KeywordKind.allCases {
        map[keyword] = keyword.code
    }
    return map
}()

let keywordLookupMap: [String: KeywordKind] = {
    var map: [String: KeywordKind] = [:]
    for keyword in KeywordKind.allCases {
        let code = keyword.code
        if !code.isEmpty {
            map[code] = keyword
        }
    }
    return map
}()

let operatorChars: Set<Character> = [
    "/", "=", "-", "+", "!", "*", "%", "<", ">", "&", "|", "^", "~", "."
]

let operatorTable: [String: OperatorKind] = [
    ".": .Dot,
    "~": .BitNot,
    "!": .Not,
    "!=": .NotEqual,
    "%": .Modulus,
    "%=": .ModulusAssign,
    "&": .BitAnd,
    "&&": .And,
    "&=": .BitAndAssign,
    "*": .Multiply,
    "*=": .MultiplyAssign,
    "+": .Plus,
    "++": .Inc,
    "+=": .PlusAssign,
    "-": .Minus,
    "--": .Dec,
    "->": .Arrow,
    "-=": .MinusAssign,
    "/": .Divide,
    "/=": .DivideAssign,
    "<": .Less,
    "<<": .LeftShift,
    "<<=": .LeftShiftArithmeticAssign,
    "<=": .LessEqual,
    ">": .Greater,
    ">>": .RightShift,
    ">>=": .RightShiftArithmeticAssign,
    ">>>": .RightShiftLogical,
    ">>>=": .RightShiftLogicalAssign,
    ">=": .GreaterEqual,
    "=": .Assign,
    "==": .Equal,
    "^": .BitXor,
    "^=": .BitXorAssign,
    "|": .BitOr,
    "||": .Or,
    "|=": .BitOrAssign,
]

public final class Lexer {
    private var input: CharStream
    public init(input: CharStream) {
        self.input = input
    }
    public func parse() -> LexerResult {
        var tokens: [Token] = []
        while !self.input.isEmpty {
            if let token = self.parseAToken() {
                tokens.append(token)
            }
        }
        return LexerResult(id: input.id, tokens: tokens)
    }
    private func parseAToken() -> Token? {
        self.skipWhitechars()
        guard let c = self.input.peek else {
            return nil
        }
        switch c {
        case "\"":
            return self.parseStringLiteral()
        case "'":
            return self.parseCharLiteral()
        case _ where c >= "0" && c <= "9":
            return self.parseNumber()
        case _ where c.isLetter || c == "_":
            return self.parseIdentifier()
        case "(":
            return self.singleCharToken(.Separator(.OpenParen), "(")
        case ")":
            return self.singleCharToken(.Separator(.CloseParen), ")")
        case "[":
            return self.singleCharToken(.Separator(.OpenBracket), "[")
        case "]":
            return self.singleCharToken(.Separator(.CloseBracket), "]")
        case "{":
            return self.singleCharToken(.Separator(.OpenBrace), "{")
        case "}":
            return self.singleCharToken(.Separator(.CloseBrace), "}")
        case ";":
            return self.singleCharToken(.Separator(.SemiColon), ";")
        case ",":
            return self.singleCharToken(.Separator(.Comma), ",")
        case ":":
            return self.singleCharToken(.Separator(.Colon), ":")
        case "$":
            return self.singleCharToken(.Operator(.Dollar), "$")
        case "@":
            return self.singleCharToken(.Operator(.At), "@")
        case "?":
            return self.parseQuestion()
        case "~", "!", "%", "&", "*", "+", "-", "<", ">", "=", "^", "|", ".":
            return self.parseOperator()
        case "/":
            let next = self.input.peek2
            if next == "/" {
                _ = self.input.next()
                _ = self.input.next()
                self.skipLineComment()
                return nil
            } else if next == "*" {
                _ = self.input.next()
                _ = self.input.next()
                self.skipBlockComment()
                return nil
            } else {
                return self.parseOperator()
            }
        default:
            let begin = self.input.currentPosition
            _ = self.input.next()
            return Token(
                value: String(c), kind: .Unknown,
                pos: self.makePosition(begin), id: self.input.id)
        }
    }
    private func singleCharToken(_ kind: TokenKind, _ value: String) -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        return Token(value: value, kind: kind, pos: self.makePosition(begin), id: self.input.id)
    }
    private func makePosition(_ begin: Position) -> Position {
        return Position(
            pos: begin.pos,
            line: begin.line,
            col: begin.col,
            len: self.input.pos - begin.pos
        )
    }
    private func parseIdentifier() -> Token {
        let begin = self.input.currentPosition
        var chars: [Character] = []
        while let c = self.input.peek, c.isLetter || c.isNumber || c == "_" {
            chars.append(c)
            _ = self.input.next()
        }
        let value = String(chars)
        let pos = self.makePosition(begin)
        switch value {
        case "true":
            return Token(value: value, kind: .BooleanLiteral(true), pos: pos, id: self.input.id)
        case "false":
            return Token(value: value, kind: .BooleanLiteral(false), pos: pos, id: self.input.id)
        case "null":
            return Token(value: value, kind: .NullLiteral, pos: pos, id: self.input.id)
        default:
            break
        }
        if let keyword = keywordLookupMap[value] {
            return Token(value: value, kind: .Keyword(keyword), pos: pos, id: self.input.id)
        }
        return Token(value: value, kind: .Identifier, pos: pos, id: self.input.id)
    }
    private func parseStringLiteral() -> Token {
        let begin = self.input.currentPosition
        var chars: [Character] = []
        if let c = self.input.next() { chars.append(c) }
        while let c = self.input.peek, c != "\"" {
            if c == "\\" {
                chars.append(c)
                _ = self.input.next()
                if let escaped = self.input.peek {
                    chars.append(escaped)
                    _ = self.input.next()
                    if escaped == "u" && self.input.peek == "{" {
                        while let u = self.input.peek, u != "}" {
                            chars.append(u)
                            _ = self.input.next()
                        }
                        if self.input.peek == "}" {
                            chars.append("}")
                            _ = self.input.next()
                        }
                    }
                }
            } else {
                chars.append(c)
                _ = self.input.next()
            }
        }
        if self.input.peek == "\"" {
            chars.append("\"")
            _ = self.input.next()
        }
        let value = String(chars)
        let pos = self.makePosition(begin)
        return Token(value: value, kind: .StringLiteral, pos: pos, id: self.input.id)
    }
    private func parseCharLiteral() -> Token {
        let begin = self.input.currentPosition
        var chars: [Character] = []
        chars.append(self.input.next()!)
        var charValue: Character = "\0"
        if let c = self.input.peek {
            if c == "\\" {
                chars.append(self.input.next()!)
                if let escaped = self.input.peek {
                    chars.append(self.input.next()!)
                    switch escaped {
                    case "n": charValue = "\n"
                    case "t": charValue = "\t"
                    case "r": charValue = "\r"
                    case "\\": charValue = "\\"
                    case "'": charValue = "'"
                    case "\"": charValue = "\""
                    case "0": charValue = "\0"
                    case "u":
                        if self.input.peek == "{" {
                            chars.append(self.input.next()!)
                            var hex = ""
                            while let h = self.input.peek, h != "}" {
                                hex.append(h)
                                chars.append(self.input.next()!)
                            }
                            if self.input.peek == "}" {
                                chars.append(self.input.next()!)
                            }
                            if let scalar = UInt32(hex, radix: 16),
                                let unicode = Unicode.Scalar(scalar)
                            {
                                charValue = Character(unicode)
                            }
                        }
                    default:
                        charValue = escaped
                    }
                }
            } else {
                charValue = c
                chars.append(self.input.next()!)
            }
        }
        if self.input.peek == "'" {
            chars.append(self.input.next()!)
        }
        let pos = self.makePosition(begin)
        return Token(
            value: String(chars), kind: .CharLiteral(charValue), pos: pos, id: self.input.id)
    }
    private func parseNumber() -> Token {
        let begin = self.input.currentPosition
        var chars: [Character] = []
        var isFloat = false
        if self.input.peek == "0", let next = self.input.peek2 {
            if next == "x" || next == "X" {
                if let c = self.input.next() { chars.append(c) }
                if let c = self.input.next() { chars.append(c) }
                while let c = self.input.peek, c.isHexDigit || c == "_" {
                    chars.append(c)
                    _ = self.input.next()
                }
                let digits = String(chars.dropFirst(2)).filter { $0 != "_" }
                let intValue = Int128(digits, radix: 16) ?? 0
                let pos = self.makePosition(begin)
                return Token(
                    value: String(chars), kind: .IntegerLiteral(intValue), pos: pos,
                    id: self.input.id)
            } else if next == "b" || next == "B" {
                if let c = self.input.next() { chars.append(c) }
                if let c = self.input.next() { chars.append(c) }
                while let c = self.input.peek, c == "0" || c == "1" || c == "_" {
                    chars.append(c)
                    _ = self.input.next()
                }
                let digits = String(chars.dropFirst(2)).filter { $0 != "_" }
                let intValue = Int128(digits, radix: 2) ?? 0
                let pos = self.makePosition(begin)
                return Token(
                    value: String(chars), kind: .IntegerLiteral(intValue), pos: pos,
                    id: self.input.id)
            } else if next == "o" || next == "O" {
                if let c = self.input.next() { chars.append(c) }
                if let c = self.input.next() { chars.append(c) }
                while let c = self.input.peek, (c >= "0" && c <= "7") || c == "_" {
                    chars.append(c)
                    _ = self.input.next()
                }
                let digits = String(chars.dropFirst(2)).filter { $0 != "_" }
                let intValue = Int128(digits, radix: 8) ?? 0
                let pos = self.makePosition(begin)
                return Token(
                    value: String(chars), kind: .IntegerLiteral(intValue), pos: pos,
                    id: self.input.id)
            }
        }
        while let c = self.input.peek, (c >= "0" && c <= "9") || c == "_" {
            chars.append(c)
            _ = self.input.next()
        }
        if self.input.peek == ".", let next = self.input.peek2, next >= "0" && next <= "9" {
            isFloat = true
            if let c = self.input.next() { chars.append(c) }
            while let c = self.input.peek, (c >= "0" && c <= "9") || c == "_" {
                chars.append(c)
                _ = self.input.next()
            }
        }
        if let c = self.input.peek, c == "e" || c == "E" {
            isFloat = true
            chars.append(c)
            _ = self.input.next()
            if let sign = self.input.peek, sign == "+" || sign == "-" {
                chars.append(sign)
                _ = self.input.next()
            }
            while let c = self.input.peek, (c >= "0" && c <= "9") || c == "_" {
                chars.append(c)
                _ = self.input.next()
            }
        }
        let value = String(chars)
        let pos = self.makePosition(begin)
        if isFloat {
            return Token(
                value: value, kind: .FloatLiteral(Double(value) ?? 0), pos: pos, id: self.input.id)
        } else {
            let digits = value.filter { $0 != "_" }
            let intValue = Int128(digits) ?? 0
            return Token(
                value: value, kind: .IntegerLiteral(intValue), pos: pos, id: self.input.id)
        }
    }
    private func parseQuestion() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == "." {
                _ = self.input.next()
                return Token(
                    value: "?.", kind: .Operator(.QuestionMarkDot),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == ":" {
                _ = self.input.next()
                return Token(
                    value: "?:", kind: .Operator(.Elvis),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: "?", kind: .Operator(.QuestionMark),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseOperator() -> Token {
        let begin = self.input.currentPosition
        var chars: [Character] = []
        while let c = self.input.peek, operatorChars.contains(c) {
            if c == "/" && !chars.isEmpty {
                let next = self.input.peek2
                if next == "/" || next == "*" {
                    break
                }
            }
            chars.append(c)
            _ = self.input.next()
        }
        let value = String(chars)
        let pos = self.makePosition(begin)
        let kind = operatorTable[value]
        return Token(value: value, kind: .Operator(kind), pos: pos, id: self.input.id)
    }
    private func skipLineComment() {
        while let c = self.input.peek, c != "\n" {
            _ = self.input.next()
        }
    }
    private func skipBlockComment() {
        var depth = 1
        while depth > 0 {
            guard let c = self.input.peek else { break }
            if c == "/" && self.input.peek2 == "*" {
                _ = self.input.next()
                _ = self.input.next()
                depth += 1
            } else if c == "*" && self.input.peek2 == "/" {
                _ = self.input.next()
                _ = self.input.next()
                depth -= 1
            } else {
                _ = self.input.next()
            }
        }
    }
    private func skipWhitechars() {
        while let c = self.input.peek, c.isWhitespace {
            _ = self.input.next()
        }
    }
}
