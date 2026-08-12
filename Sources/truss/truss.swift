import Foundation
import TrussDriver

@main
struct truss {
    static func main() {
        let source = """
        precedencegroup Assignment { assignment: true }
        precedencegroup LogicalAnd { higherThan: Assignment }
        precedencegroup Comparison { higherThan: LogicalAnd }
        precedencegroup Addition { higherThan: Comparison associativity: left }
        precedencegroup Multiplication { higherThan: Addition associativity: left }
        infix operator =: Assignment
        infix operator &&: LogicalAnd
        infix operator >=: Comparison
        infix operator +: Addition
        infix operator -: Addition
        infix operator *: Multiplication
        infix operator /: Multiplication
        func f() {
            // f2()
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
                // let t: Result = .None
            }
        }
        struct S3<E, each T> {
        }
        struct SS<T> {
            init() {

            }
        }
        typealias SSS = (SS<S>) -> S
        typealias TA = (S)
        #define EMPTY()
        #define DEFER1(A) A
        #define DEFER2(A) A EMPTY()
        #define A() 123
        #define EXPAND(x) x
        class TT {
            init() {}
        }
        class TS {
            var x: TT {
                get { y }
            }
            var t: TT = TT()
            var y: TT = TT() {
                willSet {

                }
            }
        }
        func f(s: TS) -> TT {
            s.y = TT()
            return s.x
        }
        func tf() {
            DEFER1(A)()
            // DEFER2(A)()
            EXPAND(DEFER2(A)())
            // 1 + 2 && 3*4 - 5/6 >= 7
            let ss = SS<S>()
            hasCName()
        }
        enum En {
            case SomeCase
            case OtherCase
        }
        #[cname("has_cname")]
        func hasCName() {
            match 1 {
                2 => {
                    let a = 1
                }
                3 => {
                    let b = 2
                }
            }
            match En.SomeCase {
                .SomeCase => {

                }
                .OtherCase => {

                }
            }
        }
        """
        let result = Driver(
            config: DriverConfig(
                dumpAST: true, dumpSymbols: true, dumpTIR: true, dumpSource: true,
                dumpOnError: true
            )
        ).runString(source)
        if !result.stdout.isEmpty {
            print(result.stdout, terminator: "")
        }
        if result.hasErrors {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
    }
}
