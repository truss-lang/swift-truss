import SwiftBetterDiagnostic
import TrussCore
import TrussSemantics
import TrussSyntax

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
            #define EMPTY()
            #define DEFER1(A) A
            #define DEFER2(A) A EMPTY()
            #define A() 123
            func tf() {
                DEFER1(A)()
                DEFER2(A)()
            }
            """
        let context = Context()
        let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
        context.register(source: src)
        let lexerResult = [
            Lexer(input: CharStream(content: source, id: Id.SourceId(id: 0)))
                .parse()
        ].map {
            Preprocessor(context: context).process($0, config: PreprocessorConfig())
        }[0]
        let program = Parser(context: context, packageName: "main", lexerResult).parse()
        Enter(context: context).visitProgram(program)
        NameResolver(context: context).visitProgram(program)
        print("=== AST Dump ===")
        print(ASTDumper().dump(program))
        print("=== Source Print ===")
        print(SourcePrinter().print(program))
        if context.diagnositicEngine.hasErrors {
            print(
                TerminalRenderer(beforeLines: 1, afterLines: 1)
                    .render(context.diagnositicEngine.diagnostics)
            )
        }
    }
}
