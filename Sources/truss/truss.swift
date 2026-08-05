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
            higherThan: PD1
            higherThan: PD2
            lowerThan: PD2
            assignment: true
        }
        struct S3<E, each T> {
        }
        typealias SS = (S) -> S
        #define EMPTY()
        #define DEFER1(A) A
        #define DEFER2(A) A EMPTY()
        #define A() 123
        #define EXPAND(x) x
        func tf() {
            DEFER1(A)()
            DEFER2(A)()
            EXPAND(DEFER2(A)())
            a = 1 + 2 && 3 * 4 - 5 / 6 >= 7
        }
        """
        let context = Context()
        let src = Source(id: context.nextSourceId, filepath: "<test>", content: source)
        context.register(source: src)
        let lexerResult = [
            Lexer(input: CharStream(content: source, id: Id.SourceId(id: 0)))
                .parse(),
        ].map {
            Preprocessor(context: context).process($0, config: PreprocessorConfig())
        }[0]
        let program = Parser(context: context, packageName: "main", lexerResult).parse()
        DeclCollector(context: context).visitProgram(program)
        Enter(context: context).visitProgram(program)
        let merger = MergePass(context: context)
        merger.visitProgram(program)
        merger.resolvePending()
        NameResolver(context: context).visitProgram(program)
        print("=== AST Dump ===")
        print(AST.Dumper().dump(program))
        print("=== Symbol Dump ===")
        print(SymbolDumper().dump(program))
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
