import SwiftBetterDiagnostic
import Testing
import TrussCore
import TrussTIRGen

private let source = """
typealias Int32 = Builtin.Int32

func value() -> Int32 {
    let x: Int32 = 1
    return x
}
"""

private let sourceFile = "test.truss"

@Test
func instructionsCarryRealSourceRanges() throws {
    let (_, module) = runTIRGen(source, filepath: sourceFile)
    let allInstructions = instructions(of: module)
    #expect(!allInstructions.isEmpty)
    for instruction in allInstructions {
        #expect(!isUnknownSourceRange(instruction.sourceRange))
        #expect(instruction.sourceRange.start.buffer.filePath == sourceFile)
        #expect(instruction.sourceRange.start.line > 0)
        #expect(instruction.sourceRange.start.column > 0)
    }
    let value = try #require(function(named: "value", in: module))
    #expect(!isUnknownSourceRange(value.sourceRange))
    #expect(value.sourceRange.start.buffer.filePath == sourceFile)
}

@Test
func instructionSourceRangesPointAtTheirStatements() throws {
    let (_, module) = runTIRGen(source, filepath: sourceFile)
    let value = try #require(function(named: "value", in: module))
    let entry = try #require(value.basicBlocks.first)
    let lines = entry.instructions.map(\.sourceRange.start.line)
    #expect(lines == [4, 4, 5, 5])
}

@Test
func verifierFailuresPointAtRealSourceLocations() throws {
    let (context, module) = runTIRGen(source, filepath: sourceFile)
    let value = try #require(function(named: "value", in: module))
    let entry = try #require(value.basicBlocks.first)
    let terminator = try #require(entry.instructions.last)
    entry.instructions.removeLast()
    entry.instructions.insert(terminator, at: 0)
    let displaced = entry.instructions[1].sourceRange
    #expect(!isUnknownSourceRange(displaced))
    let failures = TIR.Verifier(context: context).verify(module)
    let failure = try #require(failures.first { $0.kind == .Structure })
    #expect(failure.range.start.buffer.filePath == sourceFile)
    #expect(failure.range.start.line == 4)
    #expect(failure.range.start.column > 0)
    #expect(failure.range.start.offset == displaced.start.offset)
}

@Test
func globalInitializerInstructionsCarrySourceRanges() throws {
    let (_, module) = runTIRGen(
        """
        typealias Int32 = Builtin.Int32

        var count: Int32 = 7

        func read() -> Int32 {
            return count
        }
        """,
        filepath: sourceFile
    )
    let global = try #require(module.globals.first)
    #expect(!isUnknownSourceRange(global.sourceRange))
    let initializerId = try #require(global.initializer)
    let initializer = try #require(module.registry.functions[initializerId])
    #expect(!isUnknownSourceRange(initializer.sourceRange))
    let initializerInstructions = initializer.basicBlocks.flatMap(\.instructions)
    #expect(!initializerInstructions.isEmpty)
    for instruction in initializerInstructions {
        #expect(!isUnknownSourceRange(instruction.sourceRange))
        #expect(instruction.sourceRange.start.buffer.filePath == sourceFile)
    }
    let store = try #require(initializerInstructions.compactMap { $0 as? TIR.Store }.first)
    #expect(!isUnknownSourceRange(store.ptr.sourceRange))
    #expect(!isUnknownSourceRange(store.value.sourceRange))
    #expect(store.ptr.sourceRange.start.buffer.filePath == sourceFile)
    #expect(store.value.sourceRange.start.buffer.filePath == sourceFile)
}

private func lineNumber(of needle: String, in source: String) -> Int {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() where line.contains(needle) {
        return index + 1
    }
    return 0
}

@Test
func basicBlocksCarryRealSourceRanges() throws {
    let (_, module) = runTIRGen(source, filepath: sourceFile)
    let value = try #require(function(named: "value", in: module))
    let entry = try #require(value.basicBlocks.first)
    #expect(entry.name == "entry")
    #expect(!isUnknownSourceRange(entry.sourceRange))
    #expect(entry.sourceRange.start.buffer.filePath == sourceFile)
    #expect(entry.sourceRange.start.line == lineNumber(of: "func value()", in: source))
    #expect(entry.sourceRange.start.column > 0)
}

@Test
func controlFlowBlocksCarryTheirStatementRanges() throws {
    let flowSource = """
    typealias Int32 = Builtin.Int32

    func choose(c: Builtin.Bool) -> Int32 {
        if c {
            return 1
        } else {
            return 2
        }
        return 0
    }

    func spin(c: Builtin.Bool) {
        while c {
            break
        }
    }

    func again(c: Builtin.Bool) {
        repeat {
            break
        } while c
    }

    func forever() {
        loop {
            break
        }
    }

    func guarded(c: Builtin.Bool) -> Int32 {
        guard c else {
            return 0
        }
        return 1
    }

    func deferred(n: Int32) -> Int32 {
        defer {
            let copy = n
        }
        return n
    }

    func jumped() {
        goto done
    done:
        return
    }

    var counter: Int32 = 7
    """
    let (_, module) = runTIRGen(flowSource, filepath: sourceFile)

    let choose = try #require(function(named: "choose", in: module))
    let chooseLines = [
        lineNumber(of: "func choose", in: flowSource),
        lineNumber(of: "if c {", in: flowSource),
        lineNumber(of: "if c {", in: flowSource),
        lineNumber(of: "if c {", in: flowSource),
        lineNumber(of: "return 0", in: flowSource),
    ]
    #expect(choose.basicBlocks.map(\.sourceRange.start.line) == chooseLines)

    let spin = try #require(function(named: "spin", in: module))
    let whileLine = lineNumber(of: "while c {", in: flowSource)
    #expect(spin.basicBlocks.dropFirst().allSatisfy { $0.sourceRange.start.line == whileLine })

    let again = try #require(function(named: "again", in: module))
    let repeatLine = lineNumber(of: "repeat {", in: flowSource)
    #expect(again.basicBlocks.dropFirst().allSatisfy { $0.sourceRange.start.line == repeatLine })

    let forever = try #require(function(named: "forever", in: module))
    let loopLine = lineNumber(of: "loop {", in: flowSource)
    #expect(forever.basicBlocks.dropFirst().allSatisfy { $0.sourceRange.start.line == loopLine })

    let guarded = try #require(function(named: "guarded", in: module))
    let guardLine = lineNumber(of: "guard c else", in: flowSource)
    #expect(guarded.basicBlocks.dropFirst().allSatisfy { $0.sourceRange.start.line == guardLine })

    let deferred = try #require(function(named: "deferred", in: module))
    let deferLine = lineNumber(of: "defer {", in: flowSource)
    #expect(deferred.basicBlocks.dropFirst().allSatisfy { $0.sourceRange.start.line == deferLine })

    let jumped = try #require(function(named: "jumped", in: module))
    let labelBlock = try #require(jumped.basicBlocks.first { $0.name == "label_done" })
    #expect(labelBlock.sourceRange.start.line == lineNumber(of: "done:", in: flowSource))

    let counter = try #require(module.globals.first { $0.name.contains("counter") })
    let initializerId = try #require(counter.initializer)
    let initializer = try #require(module.registry.functions[initializerId])
    let initializerEntry = try #require(initializer.basicBlocks.first)
    #expect(
        initializerEntry.sourceRange.start.line == lineNumber(of: "var counter", in: flowSource)
    )

    for function in module.functions {
        for block in function.basicBlocks {
            #expect(!isUnknownSourceRange(block.sourceRange))
            #expect(block.sourceRange.start.buffer.filePath == sourceFile)
            #expect(block.sourceRange.start.line > 0)
        }
    }
}

@Test
func methodAndAccessorBlocksCarryTheirDeclarationRanges() throws {
    let classSource = """
    typealias Int32 = Builtin.Int32

    class Counter {
        var value: Int32 {
            get {
                return 1
            }
            set {
            }
        }
        init() {
            return
        }
        func bump() -> Int32 {
            return self.value
        }
    }

    struct Point {
        var x: Int32
        var y: Int32
        init() {}
        func sum() -> Int32 {
            return self.x
        }
    }

    func drive() -> Int32 {
        let counter = Counter()
        return counter.bump()
    }
    """
    let (_, module) = runTIRGen(classSource, filepath: sourceFile)

    let expectedLines: [String: Int] = [
        "valueGetter": lineNumber(of: "get {", in: classSource),
        "valueSetter": lineNumber(of: "set {", in: classSource),
        "Counter_4init": lineNumber(of: "init() {", in: classSource),
        "bump": lineNumber(of: "func bump", in: classSource),
        "Point_3sum": lineNumber(of: "func sum", in: classSource),
        "drive": lineNumber(of: "func drive", in: classSource),
    ]
    for (name, expected) in expectedLines {
        let fn = try #require(function(named: name, in: module))
        let entry = try #require(fn.basicBlocks.first)
        #expect(entry.sourceRange.start.line == expected)
    }

    for function in module.functions {
        for block in function.basicBlocks {
            #expect(!isUnknownSourceRange(block.sourceRange))
            #expect(block.sourceRange.start.buffer.filePath == sourceFile)
            #expect(block.sourceRange.start.line > 0)
        }
    }
}

@Test
func staticAsClassificationDrivesCastLowering() throws {
    let (_, module) = runTIRGen(
        """
        typealias Int32 = Builtin.Int32
        typealias Int64 = Builtin.Int64
        class Animal { init() {} }
        class Dog: Animal { init() {} }
        func upcastNow(d: Dog) -> Animal { return d as Animal }
        func widenNow(i: Int32) -> Int64 { return i as Int64 }
        func forcedUpNow(d: Dog) -> Animal { return d as! Animal }
        func forcedDownNow(a: Animal) -> Dog { return a as! Dog }
        """,
        filepath: sourceFile
    )
    let upcast = try #require(function(named: "upcastNow", in: module))
    #expect(upcast.basicBlocks.flatMap(\.instructions).contains { $0 is TIR.Upcast })

    let widen = try #require(function(named: "widenNow", in: module))
    #expect(widen.basicBlocks.flatMap(\.instructions).contains { $0 is TIR.NumericCast })

    let forcedUp = try #require(function(named: "forcedUpNow", in: module))
    #expect(forcedUp.basicBlocks.flatMap(\.instructions).contains { $0 is TIR.Upcast })

    let forcedDown = try #require(function(named: "forcedDownNow", in: module))
    let downInstructions = forcedDown.basicBlocks.flatMap(\.instructions)
    #expect(downInstructions.contains { $0 is TIR.IsInstance })
    #expect(!downInstructions.contains { $0 is TIR.Upcast })
}

private let pointerSource = """
precedencegroup AssignmentPrecedence {
    associativity: right
    assignment: true
}
infix operator = : AssignmentPrecedence
typealias Int32 = Builtin.Int32

func write() -> Int32 {
    var x: Int32 = 1
    let p: Int32* = &x
    *p = 2
    return x
}
"""

@Test
func slotsAreAddressedAndLanguagePointersAreConverted() throws {
    let (context, module) = runTIRGen(pointerSource, filepath: sourceFile)
    #expect(!context.diagnosticEngine.hasErrors)
    let all = instructions(of: module)
    let toPointer = all.compactMap { $0 as? TIR.AddressToPointer }
    let toAddress = all.compactMap { $0 as? TIR.PointerToAddress }
    #expect(toPointer.count == 1)
    #expect(toAddress.count == 1)
    let allocation = try #require(all.compactMap { $0 as? TIR.AllocStack }.first)
    #expect(module.registry.type(allocation.result.ty) is TIRType.AddressType)
    #expect(toPointer.first?.result.ty == module.registry.pointerType(pointee: allocation.allocatedType).id)
    #expect(TIR.Verifier(context: context).verify(module).isEmpty)
}

@Test
func subscriptAssignmentCallsSetter() throws {
    let source = """
    precedencegroup Assignment { assignment: true }
    infix operator =: Assignment
    struct Buffer {
        var x: Builtin.Int32
        subscript(i: Builtin.Int32) -> Builtin.Int32 {
            get { return x }
            set { }
        }
    }
    func use() {
        var b: Buffer
        b[0] = 42
    }
    """
    let (_, module) = runTIRGen(source)
    let use = try #require(function(named: "use", in: module))
    let calls = use.basicBlocks.flatMap(\.instructions).compactMap { $0 as? TIR.Call }
    let setterCall = try #require(
        calls.first { ($0.callee as? TIR.FunctionRef)?.name.contains("subscriptSetter") == true }
    )
    #expect(setterCall.arguments.count == 3)
}

@Test
func implicitEnumCaseValueLowersToEnumValue() {
    let source = """
    enum E { case a; case b }
    func f() -> E { return .a }
    func h() -> E {
        let e: E = .b
        return e
    }
    """
    let (context, module) = runTIRGen(source)
    #expect(!context.diagnosticEngine.hasErrors)
    let values = instructions(of: module).compactMap { $0 as? TIR.EnumValue }
    #expect(values.map(\.caseIndex) == [0, 1])
}

@Test
func staticMethodReferenceLowersToClosure() {
    let source = """
    struct S {
        static func make() -> S { return S() }
        static func make(x: S) -> S { return x }
        init() {}
    }
    func f() {
        let a: () -> S = S.make
        let b: (S) -> S = S.make
    }
    """
    let (context, module) = runTIRGen(source)
    #expect(!context.diagnosticEngine.hasErrors)
    let closures = instructions(of: module).compactMap { $0 as? TIR.Closure }
    #expect(closures.count == 2)
    for closure in closures {
        #expect(module.registry.type(closure.result.ty) is TIRType.ClosureType)
    }
}
