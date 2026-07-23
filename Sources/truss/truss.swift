import CustomDump
import SwiftBetterDiagnosis
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
                var a = 1
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
            }
            """
        let lexerResult = Lexer(input: CharStream(content: source, id: Id.SourceId(id: 0)))
            .parse()
        let context = Context()
        let src = Source(id: Id.SourceId(id: 0), filepath: "<test>", content: source)
        context.register(source: src)
        let program = Parser(context: context, packageName: "main", lexerResult).parse()
        Enter(context: context).visitProgram(program)
        NameResolver(context: context).visitProgram(program)
        customDump(program)
        print(TerminalRenderer().render(context.diagnositicEngine.diagnostics))
    }
}
