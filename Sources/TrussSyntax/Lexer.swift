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
    "/", "=", "-", "+", "!", "*", "%", "<", ">", "&", "|", "^", "~", ".",
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
    "=>": .RightArrow,
    "-=": .MinusAssign,
    "/": .Divide,
    "/=": .DivideAssign,
    "<": .Less,
    "<<": .LeftShift,
    "<<=": .LeftShiftAssign,
    "<=": .LessEqual,
    ">": .Greater,
    ">>": .RightShift,
    ">>=": .RightShiftAssign,
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
    "..": .DotDot,
    "..<": .DotDotLess,
    "...": .DotDotDot,
]

public final class Lexer {
    private var input: CharStream
    private var interpolationDepth: Int = 0
    private var emitInterpolationOpen: Bool = false
    private var pendingStringResume: Bool = false
    public init(input: CharStream) {
        self.input = input
    }
    public func parse() -> LexerResult {
        var tokens: [Token] = []
        while !self.input.isEmpty {
            if let token = self.parseAToken() {
                tokens.append(token)
                if self.emitInterpolationOpen {
                    self.emitInterpolationOpen = false
                    let openPos = self.input.currentPosition
                    self.input.incrementPosition()
                    self.input.incrementPosition()
                    tokens.append(
                        Token(
                            value: "(", kind: .Separator(.OpenParen),
                            pos: self.makePosition(openPos), id: self.input.id
                        ))
                }
            }
        }
        return LexerResult(id: input.id, tokens: tokens)
    }
    private func parseAToken() -> Token? {
        if self.pendingStringResume {
            self.pendingStringResume = false
            if self.input.peek == "\"" {
                self.input.incrementPosition()
                return Token(
                    value: "", kind: .StringLiteral,
                    pos: self.makePosition(self.input.currentPosition), id: self.input.id
                )
            }
            return self.resumeStringLiteral()
        }
        self.skipWhitechars()
        guard let c = self.input.peek else {
            return nil
        }
        switch c {
        case "\"":
            if self.input.peek2 == "\"" && self.input.peek3 == "\"" {
                return self.parseMultilineStringLiteral()
            }
            return self.parseStringLiteral()
        case "'":
            return self.parseCharLiteral()
        case _ where c >= "0" && c <= "9":
            return self.parseNumber()
        case "`":
            return self.parseBacktickIdentifier()
        case _ where c.isLetter || c == "_":
            return self.parseIdentifier()
        case "(":
            return self.singleCharToken(.Separator(.OpenParen), "(")
        case ")":
            if self.interpolationDepth > 0 {
                self.interpolationDepth -= 1
                if self.interpolationDepth == 0 {
                    self.pendingStringResume = true
                }
            }
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
        case "#":
            return self.singleCharToken(.Separator(.Sharp), "#")
        case "$":
            return self.singleCharToken(.Operator(.Dollar), "$")
        case "@":
            return self.singleCharToken(.Operator(.At), "@")
        case "?":
            return self.parseQuestion()
        case "-":
            if self.input.peek2 == ">" {
                self.input.incrementPosition()
                self.input.incrementPosition()
                return self.singleCharToken(.Separator(.Arrow), "->")
            } else {
                return self.parseOperator()
            }
        case "~", "!", "%", "&", "*", "+", "<", ">", "=", "^", "|", ".":
            return self.parseOperator()
        case "/":
            let next = self.input.peek2
            if next == "/" {
                self.input.incrementPosition()
                self.input.incrementPosition()
                self.skipLineComment()
                return nil
            } else if next == "*" {
                self.input.incrementPosition()
                self.input.incrementPosition()
                self.skipBlockComment()
                return nil
            } else {
                return self.parseOperator()
            }
        default:
            let begin = self.input.currentPosition
            self.input.incrementPosition()
            return Token(
                value: String(c), kind: .Unknown,
                pos: self.makePosition(begin), id: self.input.id)
        }
    }
    private func singleCharToken(_ kind: TokenKind, _ value: String) -> Token {
        let begin = self.input.currentPosition
        self.input.incrementPosition()
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
            self.input.incrementPosition()
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
        case "nullptr":
            return Token(value: value, kind: .NullptrLiteral, pos: pos, id: self.input.id)
        default:
            break
        }
        if let keyword = keywordLookupMap[value] {
            return Token(value: value, kind: .Keyword(keyword), pos: pos, id: self.input.id)
        }
        return Token(value: value, kind: .Identifier, pos: pos, id: self.input.id)
    }
    private func parseBacktickIdentifier() -> Token {
        let begin = self.input.currentPosition
        self.input.incrementPosition()
        var chars: [Character] = []
        while let c = self.input.peek, c != "`" {
            chars.append(c)
            self.input.incrementPosition()
        }
        if self.input.peek == "`" {
            self.input.incrementPosition()
            let pos = self.makePosition(begin)
            if chars.isEmpty {
                return Token(value: "``", kind: .Unknown, pos: pos, id: self.input.id)
            }
            return Token(value: String(chars), kind: .Identifier, pos: pos, id: self.input.id)
        }
        let pos = self.makePosition(begin)
        return Token(value: "`" + String(chars), kind: .Unknown, pos: pos, id: self.input.id)
    }
    private func parseStringLiteral() -> Token {
        let begin = self.input.currentPosition
        self.input.incrementPosition()
        var raw = ""
        while let c = self.input.peek, c != "\"" {
            if c == "\\" {
                if self.input.peek2 == "(" {
                    let pos = self.makePosition(begin)
                    self.emitInterpolationOpen = true
                    self.interpolationDepth += 1
                    return Token(
                        value: decodeStringEscapes(raw), kind: .StringLiteral, pos: pos,
                        id: self.input.id, isUnterminated: true
                    )
                }
                raw.append(c)
                self.input.incrementPosition()
                if let next = self.input.peek {
                    raw.append(next)
                    self.input.incrementPosition()
                    if next == "u" && self.input.peek == "{" {
                        while let u = self.input.peek, u != "}" {
                            raw.append(u)
                            self.input.incrementPosition()
                        }
                        if self.input.peek == "}" {
                            raw.append("}")
                            self.input.incrementPosition()
                        }
                    }
                }
            } else {
                raw.append(c)
                self.input.incrementPosition()
            }
        }
        if self.input.peek == "\"" {
            self.input.incrementPosition()
        }
        let pos = self.makePosition(begin)
        return Token(
            value: decodeStringEscapes(raw), kind: .StringLiteral, pos: pos,
            id: self.input.id
        )
    }
    private func resumeStringLiteral() -> Token {
        let begin = self.input.currentPosition
        var raw = ""
        while let c = self.input.peek, c != "\"" {
            if c == "\\" {
                if self.input.peek2 == "(" {
                    let pos = self.makePosition(begin)
                    self.emitInterpolationOpen = true
                    self.interpolationDepth += 1
                    return Token(
                        value: decodeStringEscapes(raw), kind: .StringLiteral, pos: pos,
                        id: self.input.id, isUnterminated: true
                    )
                }
                raw.append(c)
                self.input.incrementPosition()
                if let next = self.input.peek {
                    raw.append(next)
                    self.input.incrementPosition()
                    if next == "u" && self.input.peek == "{" {
                        while let u = self.input.peek, u != "}" {
                            raw.append(u)
                            self.input.incrementPosition()
                        }
                        if self.input.peek == "}" {
                            raw.append("}")
                            self.input.incrementPosition()
                        }
                    }
                }
            } else {
                raw.append(c)
                self.input.incrementPosition()
            }
        }
        if self.input.peek == "\"" {
            self.input.incrementPosition()
        }
        let pos = self.makePosition(begin)
        return Token(
            value: decodeStringEscapes(raw), kind: .StringLiteral, pos: pos,
            id: self.input.id
        )
    }
    private func parseMultilineStringLiteral() -> Token {
        let begin = self.input.currentPosition
        self.input.incrementPosition()
        self.input.incrementPosition()
        self.input.incrementPosition()
        if self.input.peek == "\n" {
            self.input.incrementPosition()
        }
        var lines: [String] = []
        var currentLine = ""
        var indentCol = 0
        while let c = self.input.peek {
            if c == "\"" && self.input.peek2 == "\"" && self.input.peek3 == "\"" {
                indentCol = self.input.currentPosition.col
                self.input.incrementPosition()
                self.input.incrementPosition()
                self.input.incrementPosition()
                break
            }
            if c == "\n" {
                lines.append(currentLine)
                currentLine = ""
                self.input.incrementPosition()
            } else {
                currentLine.append(c)
                self.input.incrementPosition()
            }
        }
        lines.append(currentLine)
        var result = ""
        for (i, line) in lines.enumerated() {
            if i > 0 { result.append("\n") }
            result.append(stripIndent(line, indentCol))
        }
        let pos = self.makePosition(begin)
        return Token(
            value: decodeStringEscapes(result), kind: .StringLiteral, pos: pos,
            id: self.input.id
        )
    }
    private func stripIndent(_ line: String, _ col: Int) -> String {
        var i = 0
        var idx = line.startIndex
        while i < col - 1 && idx < line.endIndex {
            let ch = line[idx]
            if ch == " " { i += 1 }
            else if ch == "\t" { i += 1 }
            else { break }
            idx = line.index(after: idx)
        }
        return String(line[idx...])
    }
    private func decodeStringEscapes(_ raw: String) -> String {
        var result = ""
        var i = raw.startIndex
        while i < raw.endIndex {
            let ch = raw[i]
            if ch == "\\" {
                i = raw.index(after: i)
                if i < raw.endIndex {
                    let escaped = raw[i]
                    i = raw.index(after: i)
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "0": result.append("\0")
                    case "u":
                        if i < raw.endIndex && raw[i] == "{" {
                            i = raw.index(after: i)
                            var hex = ""
                            while i < raw.endIndex && raw[i] != "}" {
                                hex.append(raw[i])
                                i = raw.index(after: i)
                            }
                            if i < raw.endIndex { i = raw.index(after: i) }
                            if let scalar = UInt32(hex, radix: 16),
                                let unicode = Unicode.Scalar(scalar)
                            {
                                result.append(Character(unicode))
                            }
                        }
                    default:
                        result.append(escaped)
                    }
                }
            } else {
                result.append(ch)
                i = raw.index(after: i)
            }
        }
        return result
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
                    self.input.incrementPosition()
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
                    self.input.incrementPosition()
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
                    self.input.incrementPosition()
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
            self.input.incrementPosition()
        }
        if self.input.peek == ".", let next = self.input.peek2, next >= "0" && next <= "9" {
            isFloat = true
            if let c = self.input.next() { chars.append(c) }
            while let c = self.input.peek, (c >= "0" && c <= "9") || c == "_" {
                chars.append(c)
                self.input.incrementPosition()
            }
        }
        if let c = self.input.peek, c == "e" || c == "E" {
            isFloat = true
            chars.append(c)
            self.input.incrementPosition()
            if let sign = self.input.peek, sign == "+" || sign == "-" {
                chars.append(sign)
                self.input.incrementPosition()
            }
            while let c = self.input.peek, (c >= "0" && c <= "9") || c == "_" {
                chars.append(c)
                self.input.incrementPosition()
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
        self.input.incrementPosition()
        if let c = self.input.peek {
            if c == "." {
                self.input.incrementPosition()
                return Token(
                    value: "?.", kind: .Operator(.QuestionMarkDot),
                    pos: self.makePosition(begin), id: self.input.id)
            } else if c == ":" {
                self.input.incrementPosition()
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
            if c == "." {
                if !chars.isEmpty {
                    break
                }
                chars.append(c)
                self.input.incrementPosition()
                if self.input.peek == "." {
                    chars.append(self.input.peek!)
                    self.input.incrementPosition()
                    if self.input.peek == "." {
                        chars.append(self.input.peek!)
                        self.input.incrementPosition()
                    } else if self.input.peek == "<" {
                        chars.append(self.input.peek!)
                        self.input.incrementPosition()
                    }
                }
                break
            }
            if c == "/" && !chars.isEmpty {
                let next = self.input.peek2
                if next == "/" || next == "*" {
                    break
                }
            }
            chars.append(c)
            self.input.incrementPosition()
        }
        let value = String(chars)
        let pos = self.makePosition(begin)
        let kind = operatorTable[value]
        return Token(value: value, kind: .Operator(kind), pos: pos, id: self.input.id)
    }
    private func skipLineComment() {
        while let c = self.input.peek, c != "\n" {
            self.input.incrementPosition()
        }
    }
    private func skipBlockComment() {
        var depth = 1
        while depth > 0 {
            guard let c = self.input.peek else { break }
            if c == "/" && self.input.peek2 == "*" {
                self.input.incrementPosition()
                self.input.incrementPosition()
                depth += 1
            } else if c == "*" && self.input.peek2 == "/" {
                self.input.incrementPosition()
                self.input.incrementPosition()
                depth -= 1
            } else {
                self.input.incrementPosition()
            }
        }
    }
    private func skipWhitechars() {
        while let c = self.input.peek, c.isWhitespace {
            self.input.incrementPosition()
        }
    }
}
