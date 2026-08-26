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
    "!!": .NotNot,
    "!=": .NotEqual,
    "!==": .NotIdentical,
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
    "===": .Identical,
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
    private var stringMode: StringMode = .SingleLine
    private var multilineState: MultilineState?

    private enum StringMode {
        case SingleLine
        case MultiLine
        case RawSingleLine
        case RawMultiLine
    }

    private struct MultilineState {
        var mode: StringMode
        var lines: [String] = []
        var lineStarts: [Bool] = []
        var currentLine: String = ""
        var currentIsLineStart: Bool = true
        init(mode: StringMode) {
            self.mode = mode
        }
    }

    public init(input: CharStream) {
        self.input = input
    }

    public func parse() -> LexerResult {
        var tokens: [Token] = []
        while !input.isEmpty {
            if let token = parseAToken() {
                tokens.append(token)
                if emitInterpolationOpen {
                    emitInterpolationOpen = false
                    let openPos = input.currentPosition
                    input.incrementPosition()
                    input.incrementPosition()
                    tokens.append(
                        Token(
                            value: "(", kind: .Separator(.OpenParen),
                            pos: makePosition(openPos), id: input.id
                        )
                    )
                }
            }
        }
        return LexerResult(id: input.id, tokens: tokens)
    }

    private func parseAToken() -> Token? {
        if pendingStringResume {
            pendingStringResume = false
            switch stringMode {
            case .SingleLine:
                if input.peek == "\"" {
                    input.incrementPosition()
                    return Token(
                        value: "", kind: .StringLiteral,
                        pos: makePosition(input.currentPosition), id: input.id
                    )
                }
                return resumeStringLiteral()
            case .RawSingleLine:
                if input.peek == "\"", input.peek2 == "#" {
                    input.incrementPosition()
                    input.incrementPosition()
                    return Token(
                        value: "", kind: .StringLiteral,
                        pos: makePosition(input.currentPosition), id: input.id, isRaw: true
                    )
                }
                return resumeRawStringLiteral()
            case .MultiLine, .RawMultiLine:
                return resumeMultilineString()
            }
        }
        skipWhitechars()
        guard let c = input.peek else {
            return nil
        }
        switch c {
        case "\"":
            if input.peek2 == "\"", input.peek3 == "\"" {
                return parseMultilineStringLiteral()
            }
            return parseStringLiteral()
        case "'":
            return parseCharLiteral()
        case _ where c >= "0" && c <= "9":
            return parseNumber()
        case "`":
            return parseBacktickIdentifier()
        case _ where c.isLetter || c == "_":
            return parseIdentifier()
        case "(":
            if interpolationDepth > 0 {
                interpolationDepth += 1
            }
            return singleCharToken(.Separator(.OpenParen), "(")
        case ")":
            if interpolationDepth > 0 {
                interpolationDepth -= 1
                if interpolationDepth == 0 {
                    pendingStringResume = true
                }
            }
            return singleCharToken(.Separator(.CloseParen), ")")
        case "[":
            return singleCharToken(.Separator(.OpenBracket), "[")
        case "]":
            return singleCharToken(.Separator(.CloseBracket), "]")
        case "{":
            return singleCharToken(.Separator(.OpenBrace), "{")
        case "}":
            return singleCharToken(.Separator(.CloseBrace), "}")
        case ";":
            return singleCharToken(.Separator(.SemiColon), ";")
        case ",":
            return singleCharToken(.Separator(.Comma), ",")
        case ":":
            return singleCharToken(.Separator(.Colon), ":")
        case "#":
            if input.peek2 == "\"" {
                if input.peek3 == "\"", input.peek4 == "\"" {
                    return parseRawMultilineStringLiteral()
                }
                return parseRawStringLiteral()
            }
            return singleCharToken(.Separator(.Sharp), "#")
        case "$":
            return singleCharToken(.Operator(.Dollar), "$")
        case "@":
            return singleCharToken(.Operator(.At), "@")
        case "?":
            return parseQuestion()
        case "-":
            if input.peek2 == ">" {
                let begin = input.currentPosition
                input.incrementPosition()
                input.incrementPosition()
                return Token(
                    value: "->", kind: .Separator(.Arrow),
                    pos: makePosition(begin), id: input.id
                )
            } else {
                return parseOperator()
            }
        case "=":
            if input.peek2 == ">" {
                let begin = input.currentPosition
                input.incrementPosition()
                input.incrementPosition()
                return Token(
                    value: "=>", kind: .Separator(.RightArrow),
                    pos: makePosition(begin), id: input.id
                )
            } else {
                return parseOperator()
            }
        case "~", "!", "%", "&", "*", "+", "<", ">", "^", "|", ".":
            return parseOperator()
        case "/":
            let next = input.peek2
            if next == "/" {
                input.incrementPosition()
                input.incrementPosition()
                skipLineComment()
                return nil
            } else if next == "*" {
                input.incrementPosition()
                input.incrementPosition()
                skipBlockComment()
                return nil
            } else {
                return parseOperator()
            }
        case "\\":
            if input.peek2 == "\n" || input.peek2 == "\r\n" {
                input.incrementPosition()
                input.incrementPosition()
                return nil
            }
            if interpolationDepth > 0, input.peek2 == "(" {
                emitInterpolationOpen = true
                interpolationDepth += 1
                let pos = makePosition(input.currentPosition)
                return Token(
                    value: "", kind: .StringLiteral, pos: pos, id: input.id,
                    isUnterminated: true
                )
            }
            let begin = input.currentPosition
            input.incrementPosition()
            return Token(
                value: "\\", kind: .Operator(.Backslash),
                pos: makePosition(begin), id: input.id
            )
        default:
            let begin = input.currentPosition
            input.incrementPosition()
            return Token(
                value: String(c), kind: .Unknown,
                pos: makePosition(begin), id: input.id
            )
        }
    }

    private func singleCharToken(_ kind: TokenKind, _ value: String) -> Token {
        let begin = input.currentPosition
        input.incrementPosition()
        return Token(value: value, kind: kind, pos: makePosition(begin), id: input.id)
    }

    private func makePosition(_ begin: Position) -> Position {
        Position(
            pos: begin.pos,
            line: begin.line,
            col: begin.col,
            len: input.pos - begin.pos
        )
    }

    private func parseIdentifier() -> Token {
        let begin = input.currentPosition
        var chars: [Character] = []
        while let c = input.peek, c.isLetter || c.isNumber || c == "_" {
            chars.append(c)
            input.incrementPosition()
        }
        let value = String(chars)
        let pos = makePosition(begin)
        switch value {
        case "true":
            return Token(value: value, kind: .BooleanLiteral(true), pos: pos, id: input.id)
        case "false":
            return Token(value: value, kind: .BooleanLiteral(false), pos: pos, id: input.id)
        case "null":
            return Token(value: value, kind: .NullLiteral, pos: pos, id: input.id)
        case "nullptr":
            return Token(value: value, kind: .NullptrLiteral, pos: pos, id: input.id)
        default:
            break
        }
        if let keyword = keywordLookupMap[value] {
            return Token(value: value, kind: .Keyword(keyword), pos: pos, id: input.id)
        }
        return Token(value: value, kind: .Identifier, pos: pos, id: input.id)
    }

    private func parseBacktickIdentifier() -> Token {
        let begin = input.currentPosition
        input.incrementPosition()
        var chars: [Character] = []
        while let c = input.peek, c != "`" {
            chars.append(c)
            input.incrementPosition()
        }
        if input.peek == "`" {
            input.incrementPosition()
            let pos = makePosition(begin)
            if chars.isEmpty {
                return Token(value: "``", kind: .Unknown, pos: pos, id: input.id)
            }
            return Token(value: String(chars), kind: .Identifier, pos: pos, id: input.id)
        }
        let pos = makePosition(begin)
        return Token(value: "`" + String(chars), kind: .Unknown, pos: pos, id: input.id)
    }

    private func parseStringLiteral() -> Token {
        let begin = input.currentPosition
        if interpolationDepth == 0 {
            stringMode = .SingleLine
        }
        input.incrementPosition()
        return scanSingleLineBody(begin: begin)
    }

    private func scanSingleLineBody(begin: Position) -> Token {
        var raw = ""
        while let c = input.peek, c != "\"" {
            if c == "\\" {
                if input.peek2 == "(" {
                    let pos = makePosition(begin)
                    emitInterpolationOpen = true
                    interpolationDepth += 1
                    return Token(
                        value: decodeStringEscapes(raw), kind: .StringLiteral, pos: pos,
                        id: input.id, isUnterminated: true
                    )
                }
                raw.append(c)
                input.incrementPosition()
                if let next = input.peek {
                    raw.append(next)
                    input.incrementPosition()
                    if next == "u", input.peek == "{" {
                        while let u = input.peek, u != "}" {
                            raw.append(u)
                            input.incrementPosition()
                        }
                        if input.peek == "}" {
                            raw.append("}")
                            input.incrementPosition()
                        }
                    }
                }
            } else {
                raw.append(c)
                input.incrementPosition()
            }
        }
        if input.peek == "\"" {
            input.incrementPosition()
        }
        let pos = makePosition(begin)
        return Token(
            value: decodeStringEscapes(raw), kind: .StringLiteral, pos: pos,
            id: input.id
        )
    }

    private func resumeStringLiteral() -> Token {
        scanSingleLineBody(begin: input.currentPosition)
    }

    private func parseRawStringLiteral() -> Token {
        let begin = input.currentPosition
        if interpolationDepth == 0 {
            stringMode = .RawSingleLine
        }
        input.incrementPosition()
        input.incrementPosition()
        return scanRawSingleLineBody(begin: begin)
    }

    private func resumeRawStringLiteral() -> Token {
        scanRawSingleLineBody(begin: input.currentPosition)
    }

    private func scanRawSingleLineBody(begin: Position) -> Token {
        var raw = ""
        while let c = input.peek, !(c == "\"" && input.peek2 == "#") {
            if c == "\\", input.peek2 == "#", input.peek3 == "(" {
                input.incrementPosition()
                emitInterpolationOpen = true
                interpolationDepth += 1
                let pos = makePosition(begin)
                return Token(
                    value: raw, kind: .StringLiteral, pos: pos, id: input.id,
                    isUnterminated: true, isRaw: true
                )
            }
            raw.append(c)
            input.incrementPosition()
        }
        if input.peek == "\"", input.peek2 == "#" {
            input.incrementPosition()
            input.incrementPosition()
        }
        let pos = makePosition(begin)
        return Token(value: raw, kind: .StringLiteral, pos: pos, id: input.id, isRaw: true)
    }

    private func parseMultilineStringLiteral() -> Token {
        let begin = input.currentPosition
        if interpolationDepth == 0 {
            stringMode = .MultiLine
        }
        input.incrementPosition()
        input.incrementPosition()
        input.incrementPosition()
        multilineState = MultilineState(mode: .MultiLine)
        if input.peek == "\n" {
            input.incrementPosition()
        }
        return scanMultilineBody(begin: begin)
    }

    private func parseRawMultilineStringLiteral() -> Token {
        let begin = input.currentPosition
        if interpolationDepth == 0 {
            stringMode = .RawMultiLine
        }
        input.incrementPosition()
        input.incrementPosition()
        input.incrementPosition()
        input.incrementPosition()
        multilineState = MultilineState(mode: .RawMultiLine)
        if input.peek == "\n" {
            input.incrementPosition()
        }
        return scanMultilineBody(begin: begin)
    }

    private func resumeMultilineString() -> Token {
        if multilineState == nil {
            multilineState = MultilineState(
                mode: stringMode == .RawMultiLine ? .RawMultiLine : .MultiLine
            )
            multilineState!.currentIsLineStart = false
        }
        return scanMultilineBody(begin: input.currentPosition)
    }

    private func scanMultilineBody(begin: Position) -> Token {
        let isRaw = multilineState!.mode == .RawMultiLine
        while let c = input.peek {
            if c == "\"" {
                if input.peek2 == "\"", input.peek3 == "\"" {
                    if isRaw {
                        if input.peek4 == "#" {
                            let indentCol = input.currentPosition.col
                            input.incrementPosition()
                            input.incrementPosition()
                            input.incrementPosition()
                            input.incrementPosition()
                            return finishMultilineSegment(begin: begin, indentCol: indentCol)
                        }
                    } else {
                        let indentCol = input.currentPosition.col
                        input.incrementPosition()
                        input.incrementPosition()
                        input.incrementPosition()
                        return finishMultilineSegment(begin: begin, indentCol: indentCol)
                    }
                }
            }
            if c == "\\" {
                if isRaw {
                    if input.peek2 == "#", input.peek3 == "(" {
                        return emitMultilineSegment(begin: begin)
                    }
                } else if input.peek2 == "(" {
                    return emitMultilineSegment(begin: begin)
                }
            }
            if c == "\n" {
                multilineState!.lines.append(multilineState!.currentLine)
                multilineState!.lineStarts.append(multilineState!.currentIsLineStart)
                multilineState!.currentLine = ""
                multilineState!.currentIsLineStart = true
                input.incrementPosition()
                continue
            }
            multilineState!.currentLine.append(c)
            input.incrementPosition()
        }
        return finishMultilineSegment(begin: begin, indentCol: 0)
    }

    private func emitMultilineSegment(begin: Position) -> Token {
        let state = multilineState!
        let isRaw = state.mode == .RawMultiLine
        if isRaw {
            input.incrementPosition()
        }
        emitInterpolationOpen = true
        interpolationDepth += 1
        let pos = makePosition(begin)
        let content = assembleMultilineSegment(
            lines: state.lines, lineStarts: state.lineStarts,
            currentLine: state.currentLine, currentIsLineStart: state.currentIsLineStart,
            indentCol: nil
        )
        multilineState = MultilineState(mode: state.mode)
        multilineState!.currentIsLineStart = false
        let value = isRaw ? content : decodeStringEscapes(content)
        return Token(
            value: value, kind: .StringLiteral, pos: pos, id: input.id,
            isUnterminated: true, isRaw: isRaw
        )
    }

    private func finishMultilineSegment(begin: Position, indentCol: Int) -> Token {
        let state = multilineState!
        let isRaw = state.mode == .RawMultiLine
        let content = assembleMultilineSegment(
            lines: state.lines, lineStarts: state.lineStarts,
            currentLine: state.currentLine, currentIsLineStart: state.currentIsLineStart,
            indentCol: indentCol
        )
        multilineState = nil
        let pos = makePosition(begin)
        let value = isRaw ? content : decodeStringEscapes(content)
        return Token(value: value, kind: .StringLiteral, pos: pos, id: input.id, isRaw: isRaw)
    }

    private func assembleMultilineSegment(
        lines: [String], lineStarts: [Bool], currentLine: String,
        currentIsLineStart: Bool, indentCol: Int?
    ) -> String {
        var allLines = lines
        var allStarts = lineStarts
        allLines.append(currentLine)
        allStarts.append(currentIsLineStart)
        let col: Int
        if let indentCol {
            col = indentCol
        } else {
            var minIndent = Int.max
            for (i, line) in allLines.enumerated() where allStarts[i] && !line.isEmpty {
                var count = 0
                for ch in line {
                    if ch == " " || ch == "\t" {
                        count += 1
                    } else {
                        break
                    }
                }
                if count < minIndent {
                    minIndent = count
                }
            }
            col = minIndent == Int.max ? 0 : minIndent + 1
        }
        var result = ""
        for (i, line) in allLines.enumerated() {
            if i > 0 {
                result.append("\n")
            }
            if allStarts[i] {
                result.append(stripIndent(line, col))
            } else {
                result.append(line)
            }
        }
        return result
    }

    private func stripIndent(_ line: String, _ col: Int) -> String {
        var i = 0
        var idx = line.startIndex
        while i < col - 1, idx < line.endIndex {
            let ch = line[idx]
            if ch == " " { i += 1 } else if ch == "\t" { i += 1 } else { break }
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
                    case "\n":
                        break
                    case "\r\n":
                        break
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "0": result.append("\0")
                    case "u":
                        if i < raw.endIndex, raw[i] == "{" {
                            i = raw.index(after: i)
                            var hex = ""
                            while i < raw.endIndex, raw[i] != "}" {
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
        let begin = input.currentPosition
        var chars: [Character] = []
        chars.append(input.next()!)
        var charValue: Character = "\0"
        if let c = input.peek {
            if c == "\\" {
                chars.append(input.next()!)
                if let escaped = input.peek {
                    chars.append(input.next()!)
                    switch escaped {
                    case "n": charValue = "\n"
                    case "t": charValue = "\t"
                    case "r": charValue = "\r"
                    case "\\": charValue = "\\"
                    case "'": charValue = "'"
                    case "\"": charValue = "\""
                    case "0": charValue = "\0"
                    case "u":
                        if input.peek == "{" {
                            chars.append(input.next()!)
                            var hex = ""
                            while let h = input.peek, h != "}" {
                                hex.append(h)
                                chars.append(input.next()!)
                            }
                            if input.peek == "}" {
                                chars.append(input.next()!)
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
                chars.append(input.next()!)
            }
        }
        if input.peek == "'" {
            chars.append(input.next()!)
        }
        let pos = makePosition(begin)
        return Token(
            value: String(chars), kind: .CharLiteral(charValue), pos: pos, id: input.id
        )
    }

    private func parseNumber() -> Token {
        let begin = input.currentPosition
        var chars: [Character] = []
        var isFloat = false
        if input.peek == "0", let next = input.peek2 {
            if next == "x" || next == "X" {
                if let c = input.next() { chars.append(c) }
                if let c = input.next() { chars.append(c) }
                while let c = input.peek, c.isHexDigit || c == "_" {
                    chars.append(c)
                    input.incrementPosition()
                }
                let digits = String(chars.dropFirst(2)).filter { $0 != "_" }
                let intValue = Int128(digits, radix: 16) ?? 0
                let pos = makePosition(begin)
                return Token(
                    value: String(chars), kind: .IntegerLiteral(intValue), pos: pos,
                    id: input.id
                )
            } else if next == "b" || next == "B" {
                if let c = input.next() { chars.append(c) }
                if let c = input.next() { chars.append(c) }
                while let c = input.peek, c == "0" || c == "1" || c == "_" {
                    chars.append(c)
                    input.incrementPosition()
                }
                let digits = String(chars.dropFirst(2)).filter { $0 != "_" }
                let intValue = Int128(digits, radix: 2) ?? 0
                let pos = makePosition(begin)
                return Token(
                    value: String(chars), kind: .IntegerLiteral(intValue), pos: pos,
                    id: input.id
                )
            } else if next == "o" || next == "O" {
                if let c = input.next() { chars.append(c) }
                if let c = input.next() { chars.append(c) }
                while let c = input.peek, (c >= "0" && c <= "7") || c == "_" {
                    chars.append(c)
                    input.incrementPosition()
                }
                let digits = String(chars.dropFirst(2)).filter { $0 != "_" }
                let intValue = Int128(digits, radix: 8) ?? 0
                let pos = makePosition(begin)
                return Token(
                    value: String(chars), kind: .IntegerLiteral(intValue), pos: pos,
                    id: input.id
                )
            }
        }
        while let c = input.peek, (c >= "0" && c <= "9") || c == "_" {
            chars.append(c)
            input.incrementPosition()
        }
        if input.peek == ".", let next = input.peek2, next >= "0" && next <= "9" {
            isFloat = true
            if let c = input.next() { chars.append(c) }
            while let c = input.peek, (c >= "0" && c <= "9") || c == "_" {
                chars.append(c)
                input.incrementPosition()
            }
        }
        if let c = input.peek, c == "e" || c == "E" {
            isFloat = true
            chars.append(c)
            input.incrementPosition()
            if let sign = input.peek, sign == "+" || sign == "-" {
                chars.append(sign)
                input.incrementPosition()
            }
            while let c = input.peek, (c >= "0" && c <= "9") || c == "_" {
                chars.append(c)
                input.incrementPosition()
            }
        }
        let value = String(chars)
        let pos = makePosition(begin)
        if isFloat {
            return Token(
                value: value, kind: .FloatLiteral(Double(value) ?? 0), pos: pos, id: input.id
            )
        } else {
            let digits = value.filter { $0 != "_" }
            let intValue = Int128(digits) ?? 0
            return Token(
                value: value, kind: .IntegerLiteral(intValue), pos: pos, id: input.id
            )
        }
    }

    private func parseQuestion() -> Token {
        let begin = input.currentPosition
        input.incrementPosition()
        if let c = input.peek {
            if c == "." {
                input.incrementPosition()
                return Token(
                    value: "?.", kind: .Operator(.QuestionMarkDot),
                    pos: makePosition(begin), id: input.id
                )
            } else if c == ":" {
                input.incrementPosition()
                return Token(
                    value: "?:", kind: .Operator(.Elvis),
                    pos: makePosition(begin), id: input.id
                )
            }
        }
        return Token(
            value: "?", kind: .Operator(.QuestionMark),
            pos: makePosition(begin), id: input.id
        )
    }

    private func parseOperator() -> Token {
        let begin = input.currentPosition
        var chars: [Character] = []
        while let c = input.peek, operatorChars.contains(c) {
            if c == "." {
                if !chars.isEmpty {
                    break
                }
                chars.append(c)
                input.incrementPosition()
                if input.peek == "." {
                    chars.append(input.peek!)
                    input.incrementPosition()
                    if input.peek == "." {
                        chars.append(input.peek!)
                        input.incrementPosition()
                    } else if input.peek == "<" {
                        chars.append(input.peek!)
                        input.incrementPosition()
                    }
                }
                break
            }
            if c == "/", !chars.isEmpty {
                let next = input.peek2
                if next == "/" || next == "*" {
                    break
                }
            }
            chars.append(c)
            input.incrementPosition()
            if chars == ["*"] || chars == ["&"], let next = input.peek, next != "=",
               next != "&"
            {
                break
            }
        }
        let value = String(chars)
        let pos = makePosition(begin)
        return Token(value: value, kind: .Operator(operatorTable[value]), pos: pos, id: input.id)
    }

    private func skipLineComment() {
        while let c = input.peek, c != "\n" {
            input.incrementPosition()
        }
    }

    private func skipBlockComment() {
        var depth = 1
        while depth > 0 {
            guard let c = input.peek else { break }
            if c == "/", input.peek2 == "*" {
                input.incrementPosition()
                input.incrementPosition()
                depth += 1
            } else if c == "*", input.peek2 == "/" {
                input.incrementPosition()
                input.incrementPosition()
                depth -= 1
            } else {
                input.incrementPosition()
            }
        }
    }

    private func skipWhitechars() {
        while let c = input.peek, c.isWhitespace {
            input.incrementPosition()
        }
    }
}
