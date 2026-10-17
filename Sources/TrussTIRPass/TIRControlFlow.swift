import TrussCore

struct TIRControlFlow {
    let function: TIR.Function
    private(set) var successors: [ObjectIdentifier: [TIR.BasicBlock]] = [:]
    private(set) var predecessors: [ObjectIdentifier: [TIR.BasicBlock]] = [:]

    init(function: TIR.Function) {
        self.function = function
        for block in function.basicBlocks {
            let edges = Self.edges(from: block)
            successors[ObjectIdentifier(block)] = edges
            for edge in edges {
                predecessors[ObjectIdentifier(edge), default: []].append(block)
            }
        }
    }

    static func edges(from block: TIR.BasicBlock) -> [TIR.BasicBlock] {
        guard let terminator = block.instructions.last else {
            return []
        }
        switch terminator {
        case let i as TIR.Branch:
            return [i.target]
        case let i as TIR.ConditionalBranch:
            return [i.trueBranch, i.falseBranch]
        case let i as TIR.SwitchEnum:
            return i.cases.map(\.block) + (i.defaultBlock.map { [$0] } ?? [])
        case let i as TIR.TryCall:
            return [i.successBlock, i.errorBlock]
        default:
            return []
        }
    }

    func successors(of block: TIR.BasicBlock) -> [TIR.BasicBlock] {
        successors[ObjectIdentifier(block)] ?? []
    }

    func reachableBlocks(from start: TIR.BasicBlock?) -> Set<ObjectIdentifier> {
        guard let start, function.basicBlocks.contains(where: { $0 === start }) else {
            return []
        }
        var visited: Set<ObjectIdentifier> = [ObjectIdentifier(start)]
        var worklist = [start]
        while let block = worklist.popLast() {
            for next in successors(of: block) where visited.insert(ObjectIdentifier(next)).inserted {
                worklist.append(next)
            }
        }
        return visited
    }

    var entryBlock: TIR.BasicBlock? {
        function.basicBlocks.first
    }

    var reachable: Set<ObjectIdentifier> {
        reachableBlocks(from: entryBlock)
    }
}

struct TIRLiveness {
    private let liveInSets: [ObjectIdentifier: Set<ObjectIdentifier>]
    private let liveOutSets: [ObjectIdentifier: Set<ObjectIdentifier>]
    private let lastUseIndices: [ObjectIdentifier: [ObjectIdentifier: Int]]

    init(function: TIR.Function, controlFlow: TIRControlFlow) {
        let blocks = function.basicBlocks
        var uses: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        var defs: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        var lastUse: [ObjectIdentifier: [ObjectIdentifier: Int]] = [:]
        for block in blocks {
            let key = ObjectIdentifier(block)
            var defined: Set<ObjectIdentifier> = []
            var exposed: Set<ObjectIdentifier> = []
            var last: [ObjectIdentifier: Int] = [:]
            for (index, instruction) in block.instructions.enumerated() {
                for value in TIRFacts.uses(of: instruction) {
                    let valueKey = ObjectIdentifier(value)
                    last[valueKey] = index
                    if !defined.contains(valueKey) {
                        exposed.insert(valueKey)
                    }
                }
                for value in TIRFacts.defs(of: instruction) {
                    defined.insert(ObjectIdentifier(value))
                }
            }
            uses[key] = exposed
            defs[key] = defined
            lastUse[key] = last
        }
        var liveIn: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        var liveOut: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        for block in blocks {
            let key = ObjectIdentifier(block)
            liveIn[key] = uses[key] ?? []
            liveOut[key] = []
        }
        var changed = true
        while changed {
            changed = false
            for block in blocks.reversed() {
                let key = ObjectIdentifier(block)
                var outgoing: Set<ObjectIdentifier> = []
                for successor in controlFlow.successors(of: block) {
                    outgoing.formUnion(liveIn[ObjectIdentifier(successor)] ?? [])
                }
                var incoming = uses[key] ?? []
                for value in outgoing where !(defs[key] ?? []).contains(value) {
                    incoming.insert(value)
                }
                if outgoing != liveOut[key] {
                    liveOut[key] = outgoing
                    changed = true
                }
                if incoming != liveIn[key] {
                    liveIn[key] = incoming
                    changed = true
                }
            }
        }
        liveInSets = liveIn
        liveOutSets = liveOut
        lastUseIndices = lastUse
    }

    func liveIn(_ block: TIR.BasicBlock) -> Set<ObjectIdentifier> {
        liveInSets[ObjectIdentifier(block)] ?? []
    }

    func liveOut(_ block: TIR.BasicBlock) -> Set<ObjectIdentifier> {
        liveOutSets[ObjectIdentifier(block)] ?? []
    }

    func isLiveIn(_ block: TIR.BasicBlock, _ value: TIR.Value) -> Bool {
        liveIn(block).contains(ObjectIdentifier(value))
    }

    func isLiveOut(_ block: TIR.BasicBlock, _ value: TIR.Value) -> Bool {
        liveOut(block).contains(ObjectIdentifier(value))
    }

    func lastUseIndex(of value: TIR.Value, in block: TIR.BasicBlock) -> Int? {
        lastUseIndices[ObjectIdentifier(block)]?[ObjectIdentifier(value)]
    }
}
