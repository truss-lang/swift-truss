import CustomDump
import SwiftBetterDiagnostic
import TrussCore
import TrussSemantics
import TrussSyntax

extension SourceLocation: @retroactive CustomDumpStringConvertible {
    public var customDumpDescription: String {
        return "SourceLocation(\n  offset: \(offset),\n  line: \(line),\n  column: \(column)\n)"
    }
}

@main
struct truss {
    static func main() {
        let source = """
            func f() {
                var a = 1 {
                    get {
                        1
                    }
                    set(v) {
                    }
                }
                a
                f2()
                M.f3()
            }
            module M {
                func f3() {
                }
            }
            protocol P {}
            protocol P2: P {}
            struct S: P2 {
                public func m() {
                    let t: Result = .None
                }
            }
            precedencegroup Precedence {
                associativity: left
                associativity: right
            }
            struct S3<E, each T> {
            }
            extension Array<
            T> {
                func f() {
                }
            }
            typealias SS = (S) -> S
            """
        let context = Context()
        let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
        context.register(source: src)
        let lexerResult = Lexer(input: CharStream(content: source, id: Id.SourceId(id: 0)))
            .parse()
        let tokens = Preprocessor(context: context).process(
            lexerResult.tokens, config: PreprocessorConfig())
        let program = Parser(
            context: context, packageName: "main",
            LexerResult(id: lexerResult.id, tokens: tokens)).parse()
        Enter(context: context).visitProgram(program)
        NameResolver(context: context).visitProgram(program)
        customDump(program)
        if context.diagnositicEngine.hasErrors {
            print(
                TerminalRenderer(beforeLines: 1, afterLines: 1)
                    .render(context.diagnositicEngine.diagnostics)
            )
        }
    }
}
