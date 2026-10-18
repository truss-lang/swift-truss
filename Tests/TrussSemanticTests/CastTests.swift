import SwiftBetterDiagnostic
import Testing
import TrussCore

@Test
func downcastWithAsIsRejected() {
    let (context, _) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func f(a: Animal) -> Dog {
            let d: Dog = a as Dog
            return d
        }
        """],
        installBuiltin: true
    )
    let diagnostics = context.diagnosticEngine.diagnostics
    let messages = diagnostics.map(\.message)
    #expect(messages == ["cannot downcast from 'Animal' to 'Dog' with 'as'"])
    let notes = diagnostics.flatMap(\.notes)
    #expect(notes.map(\.message) == ["use 'as!' or 'as?'"])
    #expect(notes.map(\.severity) == [.note])
}

@Test
func isTestAllowsDowncast() {
    let (context, _) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func f(a: Animal) -> Builtin.Bool {
            return a is Dog
        }
        """],
        installBuiltin: true
    )
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("expected 'Dog'") }))
}

@Test
func asPatternBindsVariable() {
    let (context, _) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func f(a: Animal) -> Builtin.Int32 {
            let result = match a {
            d as Dog => { let r: Dog = d; 1 }
            _ => { 0 }
            }
            return result
        }
        """],
        installBuiltin: true
    )
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(!messages.contains(where: { $0.contains("cannot find 'd'") }))
    #expect(!messages.contains(where: { $0.contains("expected 'Dog'") }))
}

@Test
func numericConversionsWithAsAreAllowed() {
    let (context, _) = runFullChecks(
        ["""
        func toInt64(i: Builtin.Int32) -> Builtin.Int64 { return i as Builtin.Int64 }
        func toInt8(i: Builtin.Int32) -> Builtin.Int8 { return i as Builtin.Int8 }
        func toFloat64(i: Builtin.Int32) -> Builtin.Float64 { return i as Builtin.Float64 }
        func widenFloat(f: Builtin.Float32) -> Builtin.Float64 { return f as Builtin.Float64 }
        func fromBool(b: Builtin.Bool) -> Builtin.Int32 { return b as Builtin.Int32 }
        func fromChar(c: Builtin.Char) -> Builtin.Int32 { return c as Builtin.Int32 }
        func fromUInt8(u: Builtin.UInt8) -> Builtin.UInt64 { return u as Builtin.UInt64 }
        func same(i: Builtin.Int32) -> Builtin.Int32 { return i as Builtin.Int32 }
        func optional(i: Builtin.Int32) -> Builtin.Int32? { return i as Builtin.Int32? }
        """],
        installBuiltin: true
    )
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func coercionsWithAsAreAllowed() {
    let (context, _) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        protocol P {}
        struct S: P {}
        func up(d: Dog) -> Animal {
            return d as Animal
        }
        func toProtocol(s: S) -> P {
            return s as P
        }
        """],
        installBuiltin: true
    )
    #expect(context.diagnosticEngine.diagnostics.isEmpty)
}

@Test
func unrelatedStructsWithAsStillMismatch() {
    let (context, _) = runFullChecks(
        ["""
        struct S {}
        struct T {}
        func f(s: S) -> T {
            return s as T
        }
        """],
        installBuiltin: true
    )
    let messages = context.diagnosticEngine.diagnostics.map(\.message)
    #expect(messages == ["expected 'T', found 'S'"])
}

@Test
func staticUpcastWithAsIsRecorded() {
    let (_, programs) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func up(d: Dog) -> Animal {
            return d as Animal
        }
        """],
        installBuiltin: true
    )
    let dump = AST.Dumper().dump(programs[0])
    #expect(dump.contains("asStatic=upcast"))
}

@Test
func staticNumericWithAsIsRecorded() {
    let (_, programs) = runFullChecks(
        ["""
        func widen(i: Builtin.Int32) -> Builtin.Int64 {
            return i as Builtin.Int64
        }
        """],
        installBuiltin: true
    )
    let dump = AST.Dumper().dump(programs[0])
    #expect(dump.contains("asStatic=numeric"))
}

@Test
func staticUpcastWithForcedAsIsRecorded() {
    let (_, programs) = runFullChecks(
        ["""
        class Animal {}
        class Dog: Animal {}
        func up(d: Dog) -> Animal {
            return d as! Animal
        }
        """],
        installBuiltin: true
    )
    let dump = AST.Dumper().dump(programs[0])
    #expect(dump.contains("asStatic=upcast"))
}

@Test
func protocolCoercionWithAsHasNoStaticResult() {
    let (_, programs) = runFullChecks(
        ["""
        protocol P {}
        struct S: P {}
        func box(s: S) -> P {
            return s as P
        }
        """],
        installBuiltin: true
    )
    let dump = AST.Dumper().dump(programs[0])
    #expect(!dump.contains("asStatic="))
}
