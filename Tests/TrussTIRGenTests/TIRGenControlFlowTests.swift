import Testing

@Suite struct ControlFlowTests {
    @Test func whileLoopBranchesOnCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                while x {
                    break
                }
            }
            """
        )
        try #require(tir.contains("CondBranch"))
        try #require(tir.contains("Branch"))
    }

    @Test func continueBranchesBackToCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                while x {
                    continue
                }
            }
            """
        )
        let lines = tir.split(separator: "\n").map(String.init)
        let condBranchIndex = try #require(lines.firstIndex { $0.contains("CondBranch") })
        let condBlock = try #require(
            lines[..<condBranchIndex].reversed().first { $0.hasSuffix(":") }
        ).replacingOccurrences(of: ":", with: "")
        try #require(lines.contains("  Branch \(condBlock)"))
    }

    @Test func ifElseBranchesOnCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                if x {
                } else {
                }
            }
            """
        )
        try #require(tir.contains("CondBranch"))
        try #require(tir.contains("true: "))
        try #require(tir.contains("false: "))
    }

    @Test func guardReturnsOnFailure() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                guard x else {
                    return
                }
            }
            """
        )
        let condBranchLines = tir.split(separator: "\n").filter { $0.contains("CondBranch") }
        try #require(condBranchLines.count == 1)
        let trueTarget = condBranchLines[0].split(separator: ",")[1].split(separator: ":")[1]
            .trimmingCharacters(in: .whitespaces)
        let falseTarget = condBranchLines[0].split(separator: ",")[2].split(separator: ":")[1]
            .trimmingCharacters(in: .whitespaces)
        try #require(tir.contains("\(falseTarget):\n  Return"))
        try #require(tir.contains("\(trueTarget):"))
    }

    @Test func repeatWhileReevaluatesCondition() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                repeat {
                } while x
            }
            """
        )
        try #require(tir.contains("CondBranch"))
        try #require(tir.contains("true: "))
    }

    @Test func deferRunsBeforeReturn() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                defer {
                    let y = x
                }
                return
            }
            """
        )
        let returnIndex = try #require(tir.range(of: "\n  Return"))
        let storeIndex = try #require(tir.range(of: "Store "))
        try #require(storeIndex.lowerBound < returnIndex.lowerBound)
    }

    @Test func doFinallyRunsBeforeJoin() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                do {
                } finally {
                    let y = x
                }
            }
            """
        )
        try #require(tir.contains("Unreachable"))
        try #require(tir.contains("Load "))
        try #require(tir.contains("Store "))
    }

    @Test func gotoBranchesToLabel() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f(x: S) {
                goto label
            label:
                let y = x
            }
            """
        )
        try #require(tir.contains("Branch "))
        try #require(!tir.contains("Trap"))
    }

    @Test func asmLowersToInlineAsm() throws {
        let tir = dumpTIR(
            """
            struct S {
                init() {}
            }
            func f() {
                let s = S()
                asm { "mov {dst}, 42" : dst = out(reg) s }
            }
            """
        )
        try #require(tir.contains("InlineAsm \"mov {dst}, 42\""))
        try #require(tir.contains("constraints: [reg]"))
        try #require(!tir.contains("Trap"))
    }

    @Test func forLoopLowersToTrap() throws {
        let tir = dumpTIR(
            """
            struct S {}
            func f() {
                for x in [] {
                }
            }
            """
        )
        try #require(tir.contains("ArrayValue []"))
        try #require(tir.contains("Trap"))
    }
}
