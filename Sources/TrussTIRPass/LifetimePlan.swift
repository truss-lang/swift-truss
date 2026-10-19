import SwiftBetterDiagnostic
import TrussCore

enum LifetimeAction {
    case Retain(TIR.Value)
    case Release(TIR.Value)
    case Destroy(TIR.Value)
    case SlotDischarge(slot: TIR.Value, destroying: Bool)
    case FieldDischarge(base: TIR.Value, structTypeId: Id.TIRTypeId, startIndex: Int)
    case DeallocStack(TIR.Value)
}

struct LifetimeInsertions {
    var acquires: [LifetimeAction] = []
    var consumes: [LifetimeAction] = []
    var deallocs: [LifetimeAction] = []

    var ordered: [LifetimeAction] {
        acquires + consumes + deallocs
    }
}

struct EdgeDischarge {
    let slot: TIR.Value
    let block: TIR.BasicBlock
    let successor: TIR.BasicBlock
}

struct PresplitDischarge {
    let block: TIR.BasicBlock
    let slot: TIR.Value
}

final class LifetimePlan {
    let function: TIR.Function
    let registry: TIR.Registry
    private let presplit: [PresplitDischarge]
    private let controlFlow: TIRControlFlow
    private let liveness: TIRLiveness
    private var before: [ObjectIdentifier: LifetimeInsertions] = [:]
    private var after: [ObjectIdentifier: LifetimeInsertions] = [:]
    private var carrierOrder: [ObjectIdentifier] = []
    private var carrierSet: Set<ObjectIdentifier> = []
    private var carrierStarts: [ObjectIdentifier: TIR.BasicBlock] = [:]
    private var carrierSnapshots: [ObjectIdentifier: CarrierState] = [:]
    private var transferBlocks: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
    private var slotOrder: [ObjectIdentifier] = []
    private var slotRoots: [ObjectIdentifier: ObjectIdentifier?] = [:]
    private var slotValues: [ObjectIdentifier: TIR.Value] = [:]
    private var globalKeys: [Id.TIRGlobalId: ObjectIdentifier] = [:]
    private var globalAliases: [ObjectIdentifier: ObjectIdentifier] = [:]
    private var globalSlots: Set<ObjectIdentifier> = []
    private var heapSlots: Set<ObjectIdentifier> = []
    private var storedSlotOrder: [ObjectIdentifier] = []
    private var storedStackSlots: [ObjectIdentifier: TIR.Value] = [:]
    private var tokenSnapshots: [ObjectIdentifier: [ObjectIdentifier: Int?]] = [:]
    private var blockOfInstruction: [ObjectIdentifier: TIR.BasicBlock] = [:]
    private var blockEntries: [ObjectIdentifier: [ObjectIdentifier: Int?]] = [:]
    private var blockExits: [ObjectIdentifier: [ObjectIdentifier: Int?]] = [:]
    private var dischargeAnchors: [ObjectIdentifier: [(slot: TIR.Value, after: Bool)]] = [:]
    private var deliveredAnchors: [ObjectIdentifier: [(slot: TIR.Value, after: Bool)]] = [:]

    init(
        function: TIR.Function, registry: TIR.Registry,
        presplitDischarges: [PresplitDischarge] = []
    ) {
        self.function = function
        self.registry = registry
        presplit = presplitDischarges
        controlFlow = TIRControlFlow(function: function)
        liveness = TIRLiveness(function: function, controlFlow: controlFlow)
        analyze()
    }

    func insertions(before instruction: TIR.Instruction) -> [LifetimeAction] {
        before[ObjectIdentifier(instruction)]?.ordered ?? []
    }

    func insertions(after instruction: TIR.Instruction) -> [LifetimeAction] {
        after[ObjectIdentifier(instruction)]?.ordered ?? []
    }

    func pendingEdgeDischarges() -> [EdgeDischarge] {
        var discharges: [EdgeDischarge] = []
        for key in storedSlotOrder {
            guard let slot = storedStackSlots[key] else {
                continue
            }
            for block in function.basicBlocks {
                guard blockExits[ObjectIdentifier(block)]?[key] ?? nil == 1 else {
                    continue
                }
                for successor in controlFlow.successors(of: block) {
                    guard blockEntries[ObjectIdentifier(successor)]?[key] ?? nil != 1 else {
                        continue
                    }
                    discharges.append(
                        EdgeDischarge(slot: slot, block: block, successor: successor)
                    )
                }
            }
        }
        return discharges
    }

    private var entryBlock: TIR.BasicBlock? {
        controlFlow.entryBlock
    }

    private func analyze() {
        guard let entry = entryBlock else {
            return
        }
        indexInstructions()
        computeSlots()
        collectStoredSlots()
        placePresplitDischarges()
        dischargeAnchors = deliveredAnchors
        computeTokenFlow()
        placeStoredSlotDischarges()
        dischargeAnchors = deliveredAnchors
        computeTokenFlow()
        seedCarriers()
        computeCarrierFlow()
        placeBlockParameterTransfers()
        placeStores()
        placeCallTransfers()
        placeDeinitializerDischarges()
        placeResultTransfers()
        placeStackAllocations()
        placeConsumes(entry: entry)
    }

    private func indexInstructions() {
        for block in function.basicBlocks {
            for instruction in block.instructions {
                blockOfInstruction[ObjectIdentifier(instruction)] = block
            }
        }
    }

    private func placePresplitDischarges() {
        for discharge in presplit {
            guard let anchor = discharge.block.instructions.last else {
                continue
            }
            deliveredAnchors[ObjectIdentifier(anchor), default: []].append((discharge.slot, false))
            insert(self.discharge(slot: discharge.slot), at: anchor, after: false, bucket: .Consume)
        }
    }

    private func collectStoredSlots() {
        for block in function.basicBlocks {
            for instruction in block.instructions {
                guard let store = instruction as? TIR.Store,
                      let key = slotKey(store.ptr), slotRoots[key] ?? nil != nil
                else {
                    continue
                }
                if storedStackSlots[key] == nil {
                    storedSlotOrder.append(key)
                }
                storedStackSlots[key] = store.ptr
            }
        }
    }

    private lazy var valueByIdentity: [ObjectIdentifier: TIR.Value] = {
        var values: [ObjectIdentifier: TIR.Value] = [:]
        for parameter in function.parameters {
            values[ObjectIdentifier(parameter)] = parameter
        }
        for block in function.basicBlocks {
            for argument in block.parameters {
                values[ObjectIdentifier(argument)] = argument
            }
            for instruction in block.instructions {
                for value in TIRFacts.defs(of: instruction) + TIRFacts.uses(of: instruction) {
                    values[ObjectIdentifier(value)] = value
                }
            }
        }
        return values
    }()

    private func slotKey(_ value: TIR.Value) -> ObjectIdentifier? {
        let key = ObjectIdentifier(value)
        if let alias = globalAliases[key] {
            return alias
        }
        return slotRoots.index(forKey: key) != nil ? key : nil
    }

    private func isTrackedSlot(_ value: TIR.Value) -> Bool {
        slotKey(value) != nil
    }

    private func isSlotType(_ id: Id.TIRTypeId) -> Bool {
        guard let pointee = pointee(of: id) else {
            return false
        }
        return TIRFacts.isReferenceValue(pointee, registry: registry)
    }

    private func pointee(of id: Id.TIRTypeId) -> Id.TIRTypeId? {
        switch registry.types[id] {
        case let address as TIRType.AddressType:
            address.pointee
        case let pointer as TIRType.PointerType:
            pointer.pointee
        default:
            nil
        }
    }

    private func computeSlots() {
        var producers: [ObjectIdentifier: TIR.Instruction] = [:]
        for block in function.basicBlocks {
            for instruction in block.instructions {
                for result in TIRFacts.defs(of: instruction) {
                    producers[ObjectIdentifier(result)] = instruction
                }
            }
        }
        for block in function.basicBlocks {
            for instruction in block.instructions {
                let candidate: TIR.Value? = switch instruction {
                case let allocation as TIR.AllocStack:
                    allocation.result
                case let address as TIR.StructElementAddr:
                    address.result
                case let address as TIR.TupleElementAddr:
                    address.result
                case let address as TIR.ClassElementAddr:
                    address.result
                case let cell as TIR.ProjectCell:
                    cell.result
                default:
                    nil
                }
                guard let candidate, isSlotType(candidate.ty) else {
                    continue
                }
                let key = ObjectIdentifier(candidate)
                let root = slotRoot(of: candidate, producers: producers)
                slotRoots[key] = root
                slotValues[key] = candidate
                slotOrder.append(key)
                if root == nil {
                    heapSlots.insert(key)
                }
            }
        }
        for block in function.basicBlocks {
            for instruction in block.instructions {
                for operand in TIRFacts.uses(of: instruction) {
                    guard let address = operand as? TIR.GlobalAddr, isSlotType(address.ty) else {
                        continue
                    }
                    registerGlobalSlot(address)
                }
            }
        }
    }

    private func registerGlobalSlot(_ address: TIR.GlobalAddr) {
        let key = ObjectIdentifier(address)
        if let canonical = globalKeys[address.globalId] {
            globalAliases[key] = canonical
            return
        }
        globalKeys[address.globalId] = key
        globalAliases[key] = key
        globalSlots.insert(key)
        heapSlots.insert(key)
    }

    private func slotRoot(
        of value: TIR.Value, producers: [ObjectIdentifier: TIR.Instruction]
    ) -> ObjectIdentifier? {
        guard let producer = producers[ObjectIdentifier(value)] else {
            return nil
        }
        switch producer {
        case is TIR.AllocStack:
            return ObjectIdentifier(value)
        case let address as TIR.StructElementAddr:
            return slotRoot(of: address.base, producers: producers)
        case let address as TIR.TupleElementAddr:
            return slotRoot(of: address.base, producers: producers)
        default:
            return nil
        }
    }

    private func computeTokenFlow() {
        guard let entry = entryBlock else {
            return
        }
        let entryKey = ObjectIdentifier(entry)
        let initial = Dictionary(
            uniqueKeysWithValues: (Array(slotRoots.keys) + Array(globalSlots)).map { ($0, 0 as Int?) }
        )
        let reachable = controlFlow.reachableBlocks(from: entry)
        var entries: [ObjectIdentifier: [ObjectIdentifier: Int?]] = [:]
        var exits: [ObjectIdentifier: [ObjectIdentifier: Int?]] = [:]
        var snapshots: [ObjectIdentifier: [[ObjectIdentifier: Int?]]] = [:]
        var changed = true
        while changed {
            changed = false
            for block in function.basicBlocks {
                let key = ObjectIdentifier(block)
                let state: [ObjectIdentifier: Int?]
                if key == entryKey || !reachable.contains(key) {
                    state = initial
                } else if let propagated = entries[key] {
                    state = propagated
                } else {
                    continue
                }
                var outgoing = state
                var blockSnapshots: [[ObjectIdentifier: Int?]] = []
                for instruction in block.instructions {
                    outgoing = applyClearings(of: instruction, after: false, state: outgoing)
                    blockSnapshots.append(outgoing)
                    outgoing = applyTokenTransfer(instruction, state: outgoing)
                    outgoing = applyClearings(of: instruction, after: true, state: outgoing)
                }
                snapshots[key] = blockSnapshots
                if exits[key] != outgoing {
                    exits[key] = outgoing
                    changed = true
                }
                guard reachable.contains(key) else {
                    continue
                }
                for successor in controlFlow.successors(of: block) where successor !== entry {
                    let next = entries[ObjectIdentifier(successor)].map { joinTokens($0, outgoing) } ?? outgoing
                    if entries[ObjectIdentifier(successor)] != next {
                        entries[ObjectIdentifier(successor)] = next
                        changed = true
                    }
                }
            }
        }
        for block in function.basicBlocks {
            guard let blockSnapshots = snapshots[ObjectIdentifier(block)] else {
                continue
            }
            for (index, instruction) in block.instructions.enumerated() where index < blockSnapshots.count {
                tokenSnapshots[ObjectIdentifier(instruction), default: [:]] = blockSnapshots[index]
            }
        }
        blockEntries = entries
        blockExits = exits
    }

    private func joinTokens(
        _ lhs: [ObjectIdentifier: Int?], _ rhs: [ObjectIdentifier: Int?]
    ) -> [ObjectIdentifier: Int?] {
        var joined: [ObjectIdentifier: Int?] = [:]
        for key in Set(lhs.keys).union(rhs.keys) {
            let left = lhs[key] ?? nil
            let right = rhs[key] ?? nil
            joined[key] = left != nil && left == right ? left : nil
        }
        return joined
    }

    private func applyClearings(
        of instruction: TIR.Instruction, after: Bool, state: [ObjectIdentifier: Int?]
    ) -> [ObjectIdentifier: Int?] {
        guard let anchors = dischargeAnchors[ObjectIdentifier(instruction)] else {
            return state
        }
        var cleared = state
        for anchor in anchors where anchor.after == after {
            guard let key = slotKey(anchor.slot), cleared.index(forKey: key) != nil else {
                continue
            }
            cleared[key] = 0
        }
        return cleared
    }

    private func applyTokenTransfer(
        _ instruction: TIR.Instruction, state: [ObjectIdentifier: Int?]
    ) -> [ObjectIdentifier: Int?] {
        if let store = instruction as? TIR.Store, let key = slotKey(store.ptr) {
            var transferred = state
            transferred[key] = 1
            return transferred
        }
        guard let load = instruction as? TIR.Load, let key = slotKey(load.ptr) else {
            return state
        }
        guard state.index(forKey: key) != nil else {
            return state
        }
        var transferred = state
        transferred[key] = 0
        return transferred
    }

    private func tokensBefore(_ instruction: TIR.Instruction, of slot: TIR.Value) -> Int? {
        guard let key = slotKey(slot) else {
            return nil
        }
        return tokenSnapshots[ObjectIdentifier(instruction)]?[key] ?? nil
    }

    private func tokensAt(_ anchor: TIR.Instruction, after: Bool, of slot: TIR.Value) -> Int? {
        guard let key = slotKey(slot), var state = tokenSnapshots[ObjectIdentifier(anchor)] else {
            return nil
        }
        if after {
            state = applyTokenTransfer(anchor, state: state)
            state = applyClearings(of: anchor, after: true, state: state)
        }
        return state[key] ?? nil
    }

    private func seedCarriers() {
        guard let entry = entryBlock else {
            return
        }
        for parameter in function.parameters
            where TIRFacts.isReferenceValue(parameter.ty, registry: registry)
        {
            registerCarrier(parameter, startBlock: entry)
        }
        for block in function.basicBlocks {
            for parameter in block.parameters
                where TIRFacts.isReferenceValue(parameter.ty, registry: registry)
            {
                registerCarrier(parameter, startBlock: block)
            }
            for instruction in block.instructions {
                if let load = instruction as? TIR.Load, isOwningLoad(load) {
                    registerCarrier(load.result, startBlock: block)
                }
                if let result = ownedResult(of: instruction),
                   TIRFacts.isReferenceValue(result.ty, registry: registry)
                {
                    registerCarrier(result, startBlock: block)
                }
                if let result = producedCarrier(of: instruction),
                   TIRFacts.isReferenceValue(result.ty, registry: registry)
                {
                    registerCarrier(result, startBlock: block)
                }
            }
        }
    }

    private func producedCarrier(of instruction: TIR.Instruction) -> TIR.Value? {
        switch instruction {
        case let cast as TIR.Upcast:
            cast.result
        case let cast as TIR.UncheckedRefCast:
            cast.result
        case let cast as TIR.BitCast:
            cast.result
        case let copy as TIR.Copy:
            copy.result
        default:
            nil
        }
    }

    private func ownedResult(of instruction: TIR.Instruction) -> TIR.Value? {
        switch instruction {
        case let call as TIR.Call:
            guard let result = call.result, hasOwnedResult(call.callee) else {
                return nil
            }
            return result
        case let call as TIR.TryCall:
            guard let result = call.result, hasOwnedResult(call.callee) else {
                return nil
            }
            return result
        case let allocation as TIR.AllocHeap:
            return allocation.result
        case let allocation as TIR.AllocCell:
            return allocation.result
        default:
            return nil
        }
    }

    private func hasOwnedResult(_ callee: TIR.Value) -> Bool {
        guard let signature = registry.types[callee.ty] as? TIRType.FunctionType else {
            return false
        }
        return signature.resultOwnership == .Owned
    }

    private func registerCarrier(_ value: TIR.Value, startBlock: TIR.BasicBlock) {
        let key = ObjectIdentifier(value)
        guard carrierSet.insert(key).inserted else {
            return
        }
        carrierOrder.append(key)
        carrierStarts[key] = startBlock
    }

    private func isOwningLoad(_ load: TIR.Load) -> Bool {
        guard let key = slotKey(load.ptr), !heapSlots.contains(key) else {
            return false
        }
        return tokensBefore(load, of: load.ptr) == 1
    }

    private func computeCarrierFlow() {
        guard let entry = entryBlock else {
            return
        }
        let entryKey = ObjectIdentifier(entry)
        var initial = CarrierState(
            availability: Dictionary(uniqueKeysWithValues: carrierOrder.map { ($0, 0 as Int?) })
        )
        for (index, parameter) in function.parameters.enumerated()
            where carrierSet.contains(ObjectIdentifier(parameter))
        {
            initial.set(parameter, to: parameterOwnership(at: index) == .Owned ? 1 : 0)
        }
        let reachable = controlFlow.reachableBlocks(from: entry)
        var entries: [ObjectIdentifier: CarrierState] = [:]
        var exits: [ObjectIdentifier: CarrierState] = [:]
        var snapshots: [ObjectIdentifier: [CarrierState]] = [:]
        for _ in 0 ..< carrierFlowLimit {
            var changed = false
            for block in function.basicBlocks {
                let key = ObjectIdentifier(block)
                let state: CarrierState
                if key == entryKey || !reachable.contains(key) {
                    state = initial
                } else if let propagated = entries[key] {
                    state = propagated
                } else {
                    continue
                }
                var outgoing = state
                var blockSnapshots: [CarrierState] = []
                for instruction in block.instructions {
                    blockSnapshots.append(outgoing)
                    outgoing = applyCarrierTransfer(instruction, state: outgoing)
                }
                if snapshots[key] != blockSnapshots {
                    snapshots[key] = blockSnapshots
                    changed = true
                }
                if exits[key] != outgoing {
                    exits[key] = outgoing
                    changed = true
                }
                guard reachable.contains(key) else {
                    continue
                }
                let beforeTerminator = blockSnapshots.last ?? state
                for successor in controlFlow.successors(of: block) where successor !== entry {
                    let edge = applyEdgeCarrierTransfers(
                        terminator: block.instructions.last, before: beforeTerminator,
                        target: successor, state: outgoing
                    )
                    let next = entries[ObjectIdentifier(successor)].map {
                        joinCarriers($0, edge)
                    } ?? edge
                    if entries[ObjectIdentifier(successor)] != next {
                        entries[ObjectIdentifier(successor)] = next
                        changed = true
                    }
                }
            }
            if !changed {
                break
            }
        }
        for block in function.basicBlocks {
            guard let blockSnapshots = snapshots[ObjectIdentifier(block)] else {
                continue
            }
            for (index, instruction) in block.instructions.enumerated()
                where index < blockSnapshots.count
            {
                carrierSnapshots[ObjectIdentifier(instruction)] = blockSnapshots[index]
            }
        }
    }

    private func applyEdgeCarrierTransfers(
        terminator: TIR.Instruction?, before: CarrierState,
        target: TIR.BasicBlock, state: CarrierState
    ) -> CarrierState {
        guard let terminator else {
            return state
        }
        var edge = state
        for arguments in edgeArguments(of: terminator, to: target) {
            for (index, argument) in arguments.enumerated() {
                guard TIRFacts.isReferenceValue(argument.ty, registry: registry) else {
                    continue
                }
                if before.value(of: argument) == 1 {
                    edge.set(argument, to: 0)
                }
                guard index < target.parameters.count else {
                    continue
                }
                let parameter = target.parameters[index]
                guard TIRFacts.isReferenceValue(parameter.ty, registry: registry) else {
                    continue
                }
                edge.set(parameter, to: 1)
            }
        }
        return edge
    }

    private func joinCarriers(_ lhs: CarrierState, _ rhs: CarrierState) -> CarrierState {
        var joined: [ObjectIdentifier: Int?] = [:]
        for key in Set(lhs.availability.keys).union(rhs.availability.keys) {
            let left = lhs.availability[key] ?? nil
            let right = rhs.availability[key] ?? nil
            joined[key] = left != nil && left == right ? left : nil
        }
        return CarrierState(availability: joined)
    }

    private func applyCarrierTransfer(_ instruction: TIR.Instruction, state: CarrierState) -> CarrierState {
        var next = state
        switch instruction {
        case let store as TIR.Store
            where TIRFacts.isReferenceValue(store.value.ty, registry: registry):
            next.set(store.value, to: 0)
        case let cast as TIR.Upcast:
            next.move(from: cast.value, to: cast.result)
        case let cast as TIR.UncheckedRefCast:
            next.move(from: cast.value, to: cast.result)
        case let cast as TIR.BitCast:
            next.move(from: cast.value, to: cast.result)
        case let copy as TIR.Copy:
            next.set(copy.result, to: 1)
        case let load as TIR.Load where isOwningLoad(load):
            next.set(load.result, to: 1)
        case let call as TIR.Call:
            next = applyingOwnedArguments(callee: call.callee, arguments: call.arguments, to: next)
            if let result = call.result, hasOwnedResult(call.callee) {
                next.set(result, to: 1)
            }
        case let call as TIR.TryCall:
            next = applyingOwnedArguments(callee: call.callee, arguments: call.arguments, to: next)
            if let result = call.result, hasOwnedResult(call.callee) {
                next.set(result, to: 1)
            }
        case let allocation as TIR.AllocHeap:
            next.set(allocation.result, to: 1)
        case let allocation as TIR.AllocCell:
            next.set(allocation.result, to: 1)
        default:
            break
        }
        return next
    }

    private func applyingOwnedArguments(
        callee: TIR.Value, arguments: [TIR.Value], to state: CarrierState
    ) -> CarrierState {
        guard let signature = registry.types[callee.ty] as? TIRType.FunctionType else {
            return state
        }
        var next = state
        for (index, argument) in arguments.enumerated() {
            guard index < signature.parameterOwnership.count,
                  signature.parameterOwnership[index] == .Owned,
                  TIRFacts.isReferenceValue(argument.ty, registry: registry)
            else {
                continue
            }
            next.set(argument, to: 0)
        }
        return next
    }

    private func availability(before instruction: TIR.Instruction, of value: TIR.Value) -> Int? {
        guard let state = carrierSnapshots[ObjectIdentifier(instruction)] else {
            return nil
        }
        return state.value(of: value)
    }

    private func availability(
        at anchor: TIR.Instruction, after: Bool, of key: ObjectIdentifier
    ) -> Int? {
        guard var state = carrierSnapshots[ObjectIdentifier(anchor)] else {
            return nil
        }
        if after {
            state = applyCarrierTransfer(anchor, state: state)
        }
        return state.availability[key] ?? nil
    }

    private var carrierFlowLimit: Int {
        64
    }

    private func placeBlockParameterTransfers() {
        for block in function.basicBlocks {
            for (index, parameter) in block.parameters.enumerated() {
                guard TIRFacts.isReferenceValue(parameter.ty, registry: registry) else {
                    continue
                }
                for predecessor in controlFlow.predecessors[ObjectIdentifier(block)] ?? [] {
                    guard let terminator = predecessor.instructions.last else {
                        continue
                    }
                    for arguments in edgeArguments(of: terminator, to: block) {
                        guard arguments.indices.contains(index) else {
                            continue
                        }
                        let argument = arguments[index]
                        guard TIRFacts.isReferenceValue(argument.ty, registry: registry) else {
                            continue
                        }
                        guard availability(before: terminator, of: argument) != 1 else {
                            continue
                        }
                        insert(.Retain(argument), before: terminator)
                    }
                }
            }
        }
    }

    private func edgeArguments(
        of terminator: TIR.Instruction, to target: TIR.BasicBlock
    ) -> [[TIR.Value]] {
        switch terminator {
        case let branch as TIR.Branch:
            return branch.target === target ? [branch.arguments] : []
        case let conditional as TIR.ConditionalBranch:
            var result: [[TIR.Value]] = []
            if conditional.trueBranch === target {
                result.append(conditional.trueArguments)
            }
            if conditional.falseBranch === target {
                result.append(conditional.falseArguments)
            }
            return result
        case let switchEnum as TIR.SwitchEnum:
            var result: [[TIR.Value]] = switchEnum.cases
                .filter { $0.block === target }
                .map(\.arguments)
            if let defaultBlock = switchEnum.defaultBlock, defaultBlock === target {
                result.append([])
            }
            return result
        default:
            return []
        }
    }

    private func placeStores() {
        for block in function.basicBlocks {
            for instruction in block.instructions {
                guard let store = instruction as? TIR.Store, let key = slotKey(store.ptr) else {
                    continue
                }
                if heapSlots.contains(key) || tokensBefore(store, of: store.ptr) != 0 {
                    insert(discharge(slot: store.ptr), before: store)
                }
                guard TIRFacts.isReferenceValue(store.value.ty, registry: registry) else {
                    continue
                }
                guard availability(before: store, of: store.value) != 1 else {
                    continue
                }
                insert(.Retain(store.value), before: store)
            }
        }
    }

    private func placeCallTransfers() {
        for block in function.basicBlocks {
            for instruction in block.instructions {
                let callee: TIR.Value
                let arguments: [TIR.Value]
                switch instruction {
                case let call as TIR.Call:
                    callee = call.callee
                    arguments = call.arguments
                case let call as TIR.TryCall:
                    callee = call.callee
                    arguments = call.arguments
                default:
                    continue
                }
                guard let signature = registry.types[callee.ty] as? TIRType.FunctionType else {
                    continue
                }
                for (index, argument) in arguments.enumerated() {
                    guard index < signature.parameterOwnership.count,
                          signature.parameterOwnership[index] == .Owned,
                          TIRFacts.isReferenceValue(argument.ty, registry: registry)
                    else {
                        continue
                    }
                    guard availability(before: instruction, of: argument) != 1 else {
                        continue
                    }
                    insert(.Retain(argument), before: instruction)
                }
            }
        }
    }

    private func discharge(slot: TIR.Value, destroying: Bool? = nil) -> LifetimeAction {
        let needsTeardown = destroying
            ?? pointee(of: slot.ty).map { TIRFacts.needsTeardown($0, registry: registry) }
            ?? false
        return .SlotDischarge(slot: slot, destroying: needsTeardown)
    }

    private func placeStoredSlotDischarges() {
        for key in storedSlotOrder {
            guard let slot = storedStackSlots[key],
                  let rootKey = slotRoots[key] ?? nil, let rootValue = slotValues[rootKey],
                  let rootBlock = definitionBlock(of: rootValue) ?? entryBlock
            else {
                continue
            }
            let action = discharge(slot: slot)
            placePositions(of: rootedValues(of: rootValue), from: rootBlock) { anchor, isAfter in
                guard self.tokensAt(anchor, after: isAfter, of: slot) == 1 else {
                    return
                }
                self.deliveredAnchors[ObjectIdentifier(anchor), default: []].append((slot, isAfter))
                self.insert(action, at: anchor, after: isAfter, bucket: .Consume)
            }
        }
    }

    private func rootedValues(of root: TIR.Value) -> [TIR.Value] {
        var values: [TIR.Value] = [root]
        let rootKey = ObjectIdentifier(root)
        for key in slotOrder {
            guard slotRoots[key] ?? nil == rootKey, let value = slotValues[key] else {
                continue
            }
            if value !== root {
                values.append(value)
            }
        }
        return values
    }

    private func placeDeinitializerDischarges() {
        guard let selfParameter = function.parameters.first,
              let pointeeId = pointee(of: selfParameter.ty),
              let classType = registry.types[pointeeId] as? TIRType.ClassType,
              let record = TIRFacts.metadata(of: classType, registry: registry),
              let entry = record.vtable.first,
              entry.function == function.id,
              !TIRFacts.isNoOpDeinitializer(record, registry: registry),
              TIRFacts.hasReferenceFields(classType.id, registry: registry)
        else {
            return
        }
        let startIndex = TIRFacts.inheritedFieldCount(of: classType, registry: registry)
        let action = LifetimeAction.FieldDischarge(
            base: selfParameter, structTypeId: classType.id, startIndex: startIndex
        )
        if let baseCall = baseDeinitializerCall(of: classType) {
            insert(action, before: baseCall)
            return
        }
        for block in function.basicBlocks {
            for instruction in block.instructions where isDeinitializerExit(instruction) {
                insert(action, before: instruction)
            }
        }
    }

    private func isDeinitializerExit(_ instruction: TIR.Instruction) -> Bool {
        instruction is TIR.Return || instruction is TIR.Unreachable || instruction is TIR.Trap
    }

    private func baseDeinitializerCall(of classType: TIRType.ClassType) -> TIR.Instruction? {
        guard let record = TIRFacts.metadata(of: classType, registry: registry),
              let superclassId = record.superclass,
              let superclassRecord = registry.metadatas[superclassId],
              let baseEntry = superclassRecord.vtable.first
        else {
            return nil
        }
        for block in function.basicBlocks {
            for instruction in block.instructions {
                guard let call = instruction as? TIR.Call,
                      let reference = call.callee as? TIR.FunctionRef,
                      reference.functionId == baseEntry.function
                else {
                    continue
                }
                return call
            }
        }
        return nil
    }

    private func placeResultTransfers() {
        guard resultOwnership() == .Owned else {
            return
        }
        for block in function.basicBlocks {
            for instruction in block.instructions {
                guard let ret = instruction as? TIR.Return,
                      let value = ret.value,
                      TIRFacts.isReferenceValue(value.ty, registry: registry)
                else {
                    continue
                }
                let key = ObjectIdentifier(value)
                transferBlocks[key, default: []].insert(ObjectIdentifier(block))
                guard availability(before: instruction, of: value) != 1 else {
                    continue
                }
                insert(.Retain(value), before: instruction)
            }
        }
    }

    private func placeStackAllocations() {
        for block in function.basicBlocks {
            for instruction in block.instructions {
                guard let allocation = instruction as? TIR.AllocStack else {
                    continue
                }
                let rooted = rootedValues(of: allocation.result)
                placePositions(of: rooted, from: block) { anchor, isAfter in
                    guard self.tokensAreEmpty(rooted, at: anchor, after: isAfter) else {
                        return
                    }
                    self.insert(
                        .DeallocStack(allocation.result), at: anchor, after: isAfter, bucket: .Dealloc
                    )
                }
            }
        }
    }

    private func tokensAreEmpty(_ values: [TIR.Value], at anchor: TIR.Instruction, after: Bool) -> Bool {
        for value in values where isTrackedSlot(value) {
            guard tokensAt(anchor, after: after, of: value) == 0 else {
                return false
            }
        }
        return true
    }

    private func placeConsumes(entry: TIR.BasicBlock) {
        for key in carrierOrder {
            guard let value = valueByIdentity[key] else {
                continue
            }
            let action = value is TIR.Parameter ? LifetimeAction.Release(value) : consume(for: value)
            placePositions(
                of: value, from: carrierStarts[key] ?? entry, excluding: transferBlocks[key] ?? []
            ) { anchor, isAfter in
                guard self.availability(at: anchor, after: isAfter, of: key) != 0 else {
                    return
                }
                guard !self.transfersOnAnEdge(anchor, value) else {
                    return
                }
                self.insert(action, at: anchor, after: isAfter, bucket: .Consume)
            }
        }
    }

    private func transfersOnAnEdge(_ anchor: TIR.Instruction, _ value: TIR.Value) -> Bool {
        guard let block = blockOfInstruction[ObjectIdentifier(anchor)] else {
            return false
        }
        for successor in controlFlow.successors(of: block) {
            for arguments in edgeArguments(of: anchor, to: successor)
                where arguments.contains(where: { $0 === value })
            {
                return true
            }
        }
        return false
    }

    private func consume(for value: TIR.Value) -> LifetimeAction {
        if TIRFacts.needsTeardown(value.ty, registry: registry) {
            return .Destroy(value)
        }
        return .Release(value)
    }

    private func definitionBlock(of value: TIR.Value) -> TIR.BasicBlock? {
        for block in function.basicBlocks where block.instructions.contains(where: { instruction in
            TIRFacts.defs(of: instruction).contains(where: { $0 === value })
        }) {
            return block
        }
        return nil
    }

    private func placePositions(
        of value: TIR.Value, from start: TIR.BasicBlock,
        excluding excluded: Set<ObjectIdentifier> = [],
        action: (TIR.Instruction, Bool) -> Void
    ) {
        placePositions(of: [value], from: start, excluding: excluded, action: action)
    }

    private func placePositions(
        of values: [TIR.Value], from start: TIR.BasicBlock,
        excluding excluded: Set<ObjectIdentifier> = [],
        action: (TIR.Instruction, Bool) -> Void
    ) {
        let region = controlFlow.reachableBlocks(from: start)
        guard !region.isEmpty else {
            return
        }
        let dominated = dominatedBlocks(from: start, region: region)
        let candidates = function.basicBlocks.filter { block in
            let key = ObjectIdentifier(block)
            return region.contains(key) && dominated.contains(key)
                && !excluded.contains(key)
                && values.allSatisfy { !liveness.isLiveOut(block, $0) }
        }
        let candidateKeys = Set(candidates.map(ObjectIdentifier.init))
        let maximal = candidates.filter { block in
            !controlFlow.successors(of: block).contains { candidateKeys.contains(ObjectIdentifier($0)) }
        }
        for block in maximal {
            guard let anchor = insertionAnchor(of: block) else {
                continue
            }
            action(anchor.instruction, anchor.after)
        }
    }

    private func insertionAnchor(of block: TIR.BasicBlock) -> (instruction: TIR.Instruction, after: Bool)? {
        guard let last = block.instructions.last else {
            return nil
        }
        guard TIRFacts.isTerminator(last) else {
            return (last, true)
        }
        return (last, false)
    }

    private func dominatedBlocks(
        from start: TIR.BasicBlock, region: Set<ObjectIdentifier>
    ) -> Set<ObjectIdentifier> {
        guard let entry = entryBlock else {
            return []
        }
        let entryRegion = controlFlow.reachableBlocks(from: entry)
        let startKey = ObjectIdentifier(start)
        guard entryRegion.contains(startKey) else {
            let dominators = computeDominators(root: start, region: region)
            return dominators[startKey] ?? []
        }
        let dominators = computeDominators(root: entry, region: entryRegion)
        return Set(dominators.filter { $0.value.contains(startKey) }.keys)
    }

    private func computeDominators(
        root: TIR.BasicBlock, region: Set<ObjectIdentifier>
    ) -> [ObjectIdentifier: Set<ObjectIdentifier>] {
        let rootKey = ObjectIdentifier(root)
        var dominators: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        for key in region {
            dominators[key] = key == rootKey ? [rootKey] : region
        }
        var changed = true
        while changed {
            changed = false
            for block in function.basicBlocks {
                let key = ObjectIdentifier(block)
                guard region.contains(key), key != rootKey else {
                    continue
                }
                var incoming: Set<ObjectIdentifier>?
                for predecessor in controlFlow.predecessors[key] ?? []
                    where region.contains(ObjectIdentifier(predecessor))
                {
                    let predecessorDominators = dominators[ObjectIdentifier(predecessor)] ?? region
                    incoming = incoming.map { $0.intersection(predecessorDominators) }
                        ?? predecessorDominators
                }
                var updated = incoming ?? []
                updated.insert(key)
                if updated != dominators[key] {
                    dominators[key] = updated
                    changed = true
                }
            }
        }
        return dominators
    }

    private func parameterOwnership(at index: Int) -> TIR.Ownership {
        guard let functionType = registry.types[function.ty] as? TIRType.FunctionType,
              functionType.parameterOwnership.indices.contains(index)
        else {
            return .Owned
        }
        return functionType.parameterOwnership[index]
    }

    private func resultOwnership() -> TIR.Ownership {
        (registry.types[function.ty] as? TIRType.FunctionType)?.resultOwnership ?? .Owned
    }

    private struct CarrierState: Equatable {
        var availability: [ObjectIdentifier: Int?]

        func value(of value: TIR.Value) -> Int? {
            availability[ObjectIdentifier(value)] ?? nil
        }

        mutating func set(_ value: TIR.Value, to state: Int?) {
            let key = ObjectIdentifier(value)
            guard availability.index(forKey: key) != nil else {
                return
            }
            availability[key] = state
        }

        mutating func move(from source: TIR.Value, to result: TIR.Value) {
            let state = value(of: source)
            set(source, to: 0)
            set(result, to: state ?? 0)
        }
    }

    private enum Bucket {
        case Acquire
        case Consume
        case Dealloc
    }

    private func insert(_ action: LifetimeAction, before anchor: TIR.Instruction) {
        insert(action, at: anchor, after: false, bucket: bucket(of: action))
    }

    private func bucket(of action: LifetimeAction) -> Bucket {
        switch action {
        case .Retain:
            .Acquire
        case .Release, .Destroy, .SlotDischarge, .FieldDischarge:
            .Consume
        case .DeallocStack:
            .Dealloc
        }
    }

    private func insert(
        _ action: LifetimeAction, at anchor: TIR.Instruction, after: Bool, bucket: Bucket
    ) {
        let key = ObjectIdentifier(anchor)
        let trailing = after && !TIRFacts.isTerminator(anchor)
        var insertions = trailing
            ? (self.after[key] ?? LifetimeInsertions())
            : (before[key] ?? LifetimeInsertions())
        switch bucket {
        case .Acquire:
            insertions.acquires.append(action)
        case .Consume:
            insertions.consumes.append(action)
        case .Dealloc:
            insertions.deallocs.append(action)
        }
        if trailing {
            self.after[key] = insertions
        } else {
            before[key] = insertions
        }
    }
}
