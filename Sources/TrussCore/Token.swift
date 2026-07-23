import TrussDiagnosis

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
    case Open
    case Public
    case Protected
    case PackagePrivate
    case Internal
    case FilePrivate
    case Private
    case Abstract
    case Final
    case Mutating
    case Nonmutating
    case Convenience
    case Required
    case Override
    case Lazy
    case Weak
    case Unowned
    case Indirect
    case Module
    case PrecedenceGroup
    case Operator
    case Infix
    case Prefix
    case Postfix
    case TypeAlias
    case Struct
    case Class
    case Enum
    case Case
    case Actor
    case ProtocolKw
    case AssociatedType
    case Extension
    case Init
    case Deinit
    case Subscript
    case SelfKw
    case SelfTypeKw
    case SuperKw
    case Func
    case Return
    case Let
    case Var
    case Guard
    case Where
    case If
    case Else
    case While
    case For
    case Repeat
    case Break
    case Continue
    case Throw
    case Throws
    case Do
    case Try
    case Catch
    case Finally
    case Defer
    case Match
    case Default
    case As
    case Is
    case In
    case Async
    case Await
    case AnyKw
    case SomeKw
    public var code: String {
        switch self {
        case .Open: "open"
        case .Public: "public"
        case .Protected: "protected"
        case .PackagePrivate: "packageprivate"
        case .Internal: "internal"
        case .FilePrivate: "fileprivate"
        case .Private: "private"
        case .Abstract: "abstract"
        case .Final: "final"
        case .Mutating: "mutating"
        case .Nonmutating: "nonmutating"
        case .Convenience: "convenience"
        case .Required: "required"
        case .Override: "override"
        case .Lazy: "lazy"
        case .Weak: "weak"
        case .Unowned: "unowned"
        case .Indirect: "indirect"
        case .Module: "module"
        case .PrecedenceGroup: "precedencegroup"
        case .Operator: "operator"
        case .Infix: "infix"
        case .Prefix: "prefix"
        case .Postfix: "postfix"
        case .TypeAlias: "typealias"
        case .Struct: "struct"
        case .Class: "class"
        case .Enum: "enum"
        case .Case: "case"
        case .Actor: "actor"
        case .ProtocolKw: "protocol"
        case .AssociatedType: "associatedtype"
        case .Extension: "extension"
        case .Init: "init"
        case .Deinit: "deinit"
        case .Subscript: "subscript"
        case .SelfKw: "self"
        case .SelfTypeKw: "Self"
        case .SuperKw: "super"
        case .Func: "func"
        case .Return: "return"
        case .Let: "let"
        case .Var: "var"
        case .Guard: "guard"
        case .Where: "where"
        case .If: "if"
        case .Else: "else"
        case .While: "while"
        case .For: "for"
        case .Repeat: "repeat"
        case .Break: "break"
        case .Continue: "continue"
        case .Throw: "throw"
        case .Throws: "throws"
        case .Do: "do"
        case .Try: "try"
        case .Catch: "catch"
        case .Finally: "finally"
        case .Defer: "defer"
        case .Match: "match"
        case .Default: "default"
        case .As: "as"
        case .Is: "is"
        case .In: "in"
        case .Async: "async"
        case .Await: "await"
        case .AnyKw: "any"
        case .SomeKw: "some"
        }
    }
}

public enum SeparatorKind: Sendable {
    case OpenParen  // (
    case CloseParen  // )
    case OpenBracket  // [
    case CloseBracket  // ]
    case OpenBrace  // {
    case CloseBrace  // }
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
    case LeftShiftAssign  // <<=
    case RightShiftAssign  // >>=
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
    case Operator(OperatorKind?)
    case IntegerLiteral(Int128)
    case FloatLiteral(Double)
    case StringLiteral
    case CharLiteral(Character)
    case BooleanLiteral(Bool)
    case NullLiteral
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

extension Token {
    public func sourceRange(in buffer: SourceBuffer) -> SourceRange {
        let start = SourceLocation(
            buffer: buffer, offset: pos.pos, line: pos.line, column: pos.col)
        let end = SourceLocation(
            buffer: buffer, offset: pos.pos + pos.len, line: pos.line,
            column: pos.col + pos.len)
        return SourceRange(start: start, end: end)
    }
}

extension SourceRange {
    public init(from startToken: Token, to endToken: Token, in buffer: SourceBuffer) {
        self.init(
            start: SourceLocation(
                buffer: buffer, offset: startToken.pos.pos, line: startToken.pos.line,
                column: startToken.pos.col),
            end: SourceLocation(
                buffer: buffer, offset: endToken.pos.pos + endToken.pos.len,
                line: endToken.pos.line, column: endToken.pos.col + endToken.pos.len))
    }
}
