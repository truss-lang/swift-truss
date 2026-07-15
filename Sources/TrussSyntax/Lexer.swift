import TrussCore

nonisolated(unsafe) var keywordMap: [KeywordKind: String]? = nil

func getKeywordMap() -> [KeywordKind: String] {
    if keywordMap == nil {
        keywordMap = [:]
        for keyword in KeywordKind.allCases {
            (keywordMap!)[keyword] = keyword.code
        }
    }
    return keywordMap!
}

nonisolated(unsafe) var keywordLookupMap: [String: KeywordKind]? = nil

func getKeywordLookupMap() -> [String: KeywordKind] {
    if keywordLookupMap == nil {
        keywordLookupMap = [:]
        for keyword in KeywordKind.allCases {
            let code = keyword.code
            if !code.isEmpty {
                (keywordLookupMap!)[code] = keyword
            }
        }
    }
    return keywordLookupMap!
}

public struct LexerResult {
    public let id: Id.SourceId
    public let tokens: [Token]
}

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
        case "~":
            return self.singleCharToken(.Operator(.BitNot), "~")
        case ".":
            return self.singleCharToken(.Operator(.Dot), ".")
        case "?":
            return self.parseQuestion()
        case "<":
            return self.parseLess()
        case ">":
            return self.parseGreater()
        case "&":
            return self.parseAmpersand()
        case "|":
            return self.parsePipe()
        case "^":
            return self.parseCaret()
        case "!":
            return self.parseExclaim()
        case "=":
            return self.parseEqual()
        case "+":
            return self.parsePlus()
        case "-":
            return self.parseMinus()
        case "*":
            return self.parseStar()
        case "/":
            return self.parseSlash()
        case "%":
            return self.parsePercent()
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
        if let keyword = getKeywordLookupMap()[value] {
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
        if let c = self.input.next() { chars.append(c) }
        while let c = self.input.peek, c != "'" {
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
        if self.input.peek == "'" {
            chars.append("'")
            _ = self.input.next()
        }
        let value = String(chars)
        let pos = self.makePosition(begin)
        return Token(value: value, kind: .CharLiteral, pos: pos, id: self.input.id)
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
                let value = String(chars)
                let pos = self.makePosition(begin)
                return Token(value: value, kind: .IntegerLiteral, pos: pos, id: self.input.id)
            } else if next == "b" || next == "B" {
                if let c = self.input.next() { chars.append(c) }
                if let c = self.input.next() { chars.append(c) }
                while let c = self.input.peek, c == "0" || c == "1" || c == "_" {
                    chars.append(c)
                    _ = self.input.next()
                }
                let value = String(chars)
                let pos = self.makePosition(begin)
                return Token(value: value, kind: .IntegerLiteral, pos: pos, id: self.input.id)
            } else if next == "o" || next == "O" {
                if let c = self.input.next() { chars.append(c) }
                if let c = self.input.next() { chars.append(c) }
                while let c = self.input.peek, (c >= "0" && c <= "7") || c == "_" {
                    chars.append(c)
                    _ = self.input.next()
                }
                let value = String(chars)
                let pos = self.makePosition(begin)
                return Token(value: value, kind: .IntegerLiteral, pos: pos, id: self.input.id)
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
        let kind: TokenKind = isFloat ? .FloatLiteral : .IntegerLiteral
        return Token(value: value, kind: kind, pos: pos, id: self.input.id)
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
    private func parseLess() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == "<" {
                _ = self.input.next()
                if self.input.peek == "=" {
                    _ = self.input.next()
                    return Token(
                        value: "<<=", kind: .Operator(.LeftShiftArithmeticAssign),
                        pos: self.makePosition(begin), id: self.input.id)
                }
                return Token(
                    value: "<<", kind: .Operator(.LeftShift),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == "=" {
                _ = self.input.next()
                return Token(
                    value: "<=", kind: .Operator(.LessEqual),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: "<", kind: .Operator(.Less),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseGreater() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == ">" {
                _ = self.input.next()
                if let c2 = self.input.peek {
                    if c2 == ">" {
                        _ = self.input.next()
                        if self.input.peek == "=" {
                            _ = self.input.next()
                            return Token(
                                value: ">>>=", kind: .Operator(.RightShiftLogicalAssign),
                                pos: self.makePosition(begin), id: self.input.id)
                        }
                        return Token(
                            value: ">>>", kind: .Operator(.RightShiftLogical),
                            pos: self.makePosition(begin), id: self.input.id)
                    } else if c2 == "=" {
                        _ = self.input.next()
                        return Token(
                            value: ">>=", kind: .Operator(.RightShiftArithmeticAssign),
                            pos: self.makePosition(begin), id: self.input.id)
                    }
                }
                return Token(
                    value: ">>", kind: .Operator(.RightShift),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == "=" {
                _ = self.input.next()
                return Token(
                    value: ">=", kind: .Operator(.GreaterEqual),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: ">", kind: .Operator(.Greater),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseAmpersand() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == "&" {
                _ = self.input.next()
                return Token(
                    value: "&&", kind: .Operator(.And),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == "=" {
                _ = self.input.next()
                return Token(
                    value: "&=", kind: .Operator(.BitAndAssign),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: "&", kind: .Operator(.BitAnd),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parsePipe() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == "|" {
                _ = self.input.next()
                return Token(
                    value: "||", kind: .Operator(.Or),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == "=" {
                _ = self.input.next()
                return Token(
                    value: "|=", kind: .Operator(.BitOrAssign),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: "|", kind: .Operator(.BitOr),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseCaret() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if self.input.peek == "=" {
            _ = self.input.next()
            return Token(
                value: "^=", kind: .Operator(.BitXorAssign),
                pos: self.makePosition(begin), id: self.input.id)
        }
        return Token(
            value: "^", kind: .Operator(.BitXor),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseExclaim() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if self.input.peek == "=" {
            _ = self.input.next()
            return Token(
                value: "!=", kind: .Operator(.NotEqual),
                pos: self.makePosition(begin), id: self.input.id)
        }
        return Token(
            value: "!", kind: .Operator(.Not),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseEqual() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if self.input.peek == "=" {
            _ = self.input.next()
            return Token(
                value: "==", kind: .Operator(.Equal),
                pos: self.makePosition(begin), id: self.input.id)
        }
        return Token(
            value: "=", kind: .Operator(.Assign),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parsePlus() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == "+" {
                _ = self.input.next()
                return Token(
                    value: "++", kind: .Operator(.Inc),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == "=" {
                _ = self.input.next()
                return Token(
                    value: "+=", kind: .Operator(.PlusAssign),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: "+", kind: .Operator(.Plus),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseMinus() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == "-" {
                _ = self.input.next()
                return Token(
                    value: "--", kind: .Operator(.Dec),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == ">" {
                _ = self.input.next()
                return Token(
                    value: "->", kind: .Operator(.Arrow),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == "=" {
                _ = self.input.next()
                return Token(
                    value: "-=", kind: .Operator(.MinusAssign),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: "-", kind: .Operator(.Minus),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseStar() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if self.input.peek == "=" {
            _ = self.input.next()
            return Token(
                value: "*=", kind: .Operator(.MultiplyAssign),
                pos: self.makePosition(begin), id: self.input.id)
        }
        return Token(
            value: "*", kind: .Operator(.Multiply),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parseSlash() -> Token? {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if let c = self.input.peek {
            if c == "/" {
                _ = self.input.next()
                self.skipLineComment()
                return nil
            } else if c == "*" {
                _ = self.input.next()
                self.skipBlockComment()
                return nil
            } else if c == "=" {
                _ = self.input.next()
                return Token(
                    value: "/=", kind: .Operator(.DivideAssign),
                    pos: self.makePosition(begin), id: self.input.id)
            }
        }
        return Token(
            value: "/", kind: .Operator(.Divide),
            pos: self.makePosition(begin), id: self.input.id)
    }
    private func parsePercent() -> Token {
        let begin = self.input.currentPosition
        _ = self.input.next()
        if self.input.peek == "=" {
            _ = self.input.next()
            return Token(
                value: "%=", kind: .Operator(.ModulusAssign),
                pos: self.makePosition(begin), id: self.input.id)
        }
        return Token(
            value: "%", kind: .Operator(.Modulus),
            pos: self.makePosition(begin), id: self.input.id)
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
