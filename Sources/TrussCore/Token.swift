public struct SourceId {
    public let id: UInt64
}

public struct Position {
    public let pos: Int
    public let line: Int
    public let col: Int
    public let len: Int
    public init(pos: Int, line: Int, col: Int, len: Int) {
        self.pos = pos
        self.line = line
        self.col = col
        self.len = len
    }
}

public enum KeywordKind: CaseIterable, Sendable {
    case Func
    case Return
    case Let
    case Var
    // etc.
    public var code: String {
        switch self {
        case .Func: "func"
        case .Return: "return"
        case .Let: "let"
        case .Var: "var"
        default: ""
        }
    }
}

public enum SeparatorKind: Sendable {
    case OpenParen  // (
    case CloseParen  // )
    case OpenBracket  // [
    case CloseBracket  // ]
    case OpenBrace  // (
    case CloseBrace  // )
    case SemiColon  // ;
    case Comma  // ,
    case Colon  // :
}

public enum OperatorKind: Sendable {
    case Dollar  // $
    case At  // @
    case QuestionMark  // ?
    case Dot  // .
    case LeftShift  // <<
    case RightShift  // >>
    case RightShiftLogical  // >>>
    case BitNot  // ~
    case BitAnd  // &
    case BitOr  // |
    case BitXor  // ^

    case Not  // !
    case And  // &&
    case Or  // ||

    case Assign  // =
    case MultiplyAssign  // *=
    case DivideAssign  // /=
    case ModulusAssign  // %=
    case PlusAssign  // +=
    case MinusAssign  // -=
    case LeftShiftArithmeticAssign  // <<=
    case RightShiftArithmeticAssign  // >>=
    case RightShiftLogicalAssign  // >>>=
    case BitAndAssign  // &=
    case BitXorAssign  // ^=
    case BitOrAssign  // |=

    case Arrow  // ->

    case Inc  // ++
    case Dec  // --

    case Plus  // +
    case Minus  // -
    case Multiply  // *
    case Divide  // /
    case Modulus  // %

    case Equal  // ==
    case NotEqual  // !=
    case Greater  // >
    case GreaterEqual  // >=
    case Less  // <
    case LessEqual  // <=

    case QuestionMarkDot  // ?.
    case Elvis  // ?:
}

public enum TokenKind: Equatable {
    case Identifier
    case Keyword(KeywordKind)
    case Separator(SeparatorKind)
    case Operator(OperatorKind)
    case IntegerLiteral(Int128)
    case FloatLiteral(Double)
    case StringLiteral
    case CharLiteral(Character)
    case Unknown
}

public final class Token {
    public let value: String
    public let kind: TokenKind
    public let pos: Position
    public let id: Id.SourceId
    public init(value: String, kind: TokenKind, pos: Position, id: Id.SourceId) {
        self.value = value
        self.kind = kind
        self.pos = pos
        self.id = id
    }
}

public class CharStream: IteratorProtocol {
    private let chars: [Character]
    public let id: Id.SourceId
    public var pos: Int
    public var line: Int
    public var col: Int
    public init(content: String, id: Id.SourceId) {
        self.chars = Array(content)
        self.id = id
        self.pos = 0
        self.line = 1
        self.col = 1
    }
    public var isEmpty: Bool {
        self.pos >= self.chars.count
    }
    public var count: Int {
        chars.count
    }
    public var peek: Character? {
        if pos < chars.count {
            chars[pos]
        } else {
            nil
        }
    }
    public var peek2: Character? {
        if pos + 1 < chars.count {
            chars[pos + 1]
        } else {
            nil
        }
    }
    public func next() -> Character? {
        if pos < chars.count {
            let c = chars[pos]
            pos += 1
            if c == "\n" {
                line += 1
                col = 1
            } else {
                col += 1
            }
            return c
        } else {
            return nil
        }
    }
    public var currentPosition: Position {
        Position(pos: self.pos, line: self.line, col: self.col, len: 1)
    }
    public func incrementPosition() {
        let c = self.peek
        pos += 1
        if c == "\n" {
            line += 1
            col = 1
        } else {
            col += 1
        }
    }
}
