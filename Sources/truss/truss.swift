import CustomDump
import TrussCore
import TrussSemantics
import TrussSyntax

@main
struct truss {
    static func main() {
        let source = """
            func f() {
                var a = 1
                a
                f2()
            }
            func f2() {
            }
            module M {
                func f3() {
                }
            }
            """
        let lexerResult = Lexer(input: CharStream(content: source, id: Id.SourceId(id: 0)))
            .parse()
        // lexerResult.tokens.forEach { customDump($0) }
        let context = Context()
        let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
        context.register(source: src)
        let program = Parser(context: context, packageName: "main", lexerResult).parse()
        Enter(context: context).visitProgram(program)
        NameResolver(context: context).visitProgram(program)
        customDump(program)

    }
}
