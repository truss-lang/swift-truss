import CustomDump
import TrussCore

@main
struct truss {
    static func main() {
        customDump(AST.Return(nil))
    }
}
