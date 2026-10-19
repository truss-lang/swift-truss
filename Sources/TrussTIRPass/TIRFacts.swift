import SwiftBetterDiagnostic
import TrussCore

enum TIRFacts {
    static let noOpDeinitializerName = "$t_noop_deinit"

    static func isTerminator(_ instruction: TIR.Instruction) -> Bool {
        instruction is TIR.Return || instruction is TIR.Branch || instruction is TIR.ConditionalBranch
            || instruction is TIR.SwitchEnum || instruction is TIR.Unreachable
            || instruction is TIR.Trap || instruction is TIR.TryCall
    }

    static func uses(of instruction: TIR.Instruction) -> [TIR.Value] {
        switch instruction {
        case let i as TIR.Return:
            i.value.map { [$0] } ?? []
        case let i as TIR.Branch:
            i.arguments
        case let i as TIR.ConditionalBranch:
            [i.condition] + i.trueArguments + i.falseArguments
        case let i as TIR.SwitchEnum:
            [i.value] + i.cases.flatMap(\.arguments)
        case let i as TIR.Phi:
            i.incomings.map(\.value)
        case let i as TIR.ExtractPayload:
            [i.value]
        case let i as TIR.UnaryArith:
            [i.operand]
        case let i as TIR.BinaryArith:
            [i.lhs, i.rhs]
        case let i as TIR.DeallocStack:
            [i.value]
        case let i as TIR.DeallocHeap:
            [i.value]
        case let i as TIR.DeallocCell:
            [i.value]
        case let i as TIR.Load:
            [i.ptr]
        case let i as TIR.Store:
            [i.value, i.ptr]
        case let i as TIR.StructElementAddr:
            [i.base]
        case let i as TIR.TupleElementAddr:
            [i.base]
        case let i as TIR.ClassElementAddr:
            [i.base]
        case let i as TIR.ProjectCell:
            [i.cell]
        case let i as TIR.StructValue:
            i.fields
        case let i as TIR.TupleValue:
            i.elements
        case let i as TIR.EnumValue:
            i.payload.map { [$0] } ?? []
        case let i as TIR.Call:
            [i.callee] + i.arguments
        case let i as TIR.TryCall:
            [i.callee] + i.arguments + (i.errorCell.map { [$0] } ?? [])
        case let i as TIR.Closure:
            [i.function] + i.captures
        case let i as TIR.VirtualMethod:
            [i.selfValue]
        case let i as TIR.Upcast:
            [i.value]
        case let i as TIR.UncheckedRefCast:
            [i.value]
        case let i as TIR.NumericCast:
            [i.value]
        case let i as TIR.BitCast:
            [i.value]
        case let i as TIR.TypeMetadata:
            [i.value]
        case let i as TIR.IsInstance:
            [i.metadata, i.target]
        case let i as TIR.Superclass:
            [i.metadata]
        case let i as TIR.Retain:
            [i.value]
        case let i as TIR.Release:
            [i.value]
        case let i as TIR.Copy:
            [i.value]
        case let i as TIR.Destroy:
            [i.value]
        case let i as TIR.InlineAsm:
            i.operands
        case let i as TIR.BuildExistential:
            [i.value]
        case let i as TIR.OpenExistential:
            [i.container]
        case let i as TIR.OpaqueWitnessMethod:
            [i.container]
        case let i as TIR.ExistentialCopy:
            [i.container]
        case let i as TIR.ExistentialDestroy:
            [i.container]
        default:
            []
        }
    }

    static func defs(of instruction: TIR.Instruction) -> [TIR.Value] {
        switch instruction {
        case let i as TIR.Phi:
            [i.result]
        case let i as TIR.ExtractPayload:
            [i.result]
        case let i as TIR.UnaryArith:
            [i.result]
        case let i as TIR.BinaryArith:
            [i.result]
        case let i as TIR.AllocStack:
            [i.result]
        case let i as TIR.AllocHeap:
            [i.result]
        case let i as TIR.AllocCell:
            [i.result]
        case let i as TIR.Load:
            [i.result]
        case let i as TIR.StructElementAddr:
            [i.result]
        case let i as TIR.TupleElementAddr:
            [i.result]
        case let i as TIR.ClassElementAddr:
            [i.result]
        case let i as TIR.ProjectCell:
            [i.result]
        case let i as TIR.AddressToPointer:
            [i.result]
        case let i as TIR.PointerToAddress:
            [i.result]
        case let i as TIR.StructValue:
            [i.result]
        case let i as TIR.TupleValue:
            [i.result]
        case let i as TIR.EnumValue:
            [i.result]
        case let i as TIR.Call:
            i.result.map { [$0] } ?? []
        case let i as TIR.TryCall:
            i.result.map { [$0] } ?? []
        case let i as TIR.Closure:
            [i.result]
        case let i as TIR.VirtualMethod:
            [i.result]
        case let i as TIR.Upcast:
            [i.result]
        case let i as TIR.UncheckedRefCast:
            [i.result]
        case let i as TIR.NumericCast:
            [i.result]
        case let i as TIR.BitCast:
            [i.result]
        case let i as TIR.SizeOf:
            [i.result]
        case let i as TIR.TypeMetadata:
            [i.result]
        case let i as TIR.TypeMetadataConstant:
            [i.result]
        case let i as TIR.IsInstance:
            [i.result]
        case let i as TIR.Superclass:
            [i.result]
        case let i as TIR.Copy:
            [i.result]
        case let i as TIR.BuildExistential:
            [i.result]
        case let i as TIR.OpenExistential:
            [i.result]
        case let i as TIR.WitnessMethod:
            [i.result]
        case let i as TIR.OpaqueWitnessMethod:
            [i.result]
        case let i as TIR.ExistentialCopy:
            [i.result]
        default:
            []
        }
    }

    static func isReferenceValue(_ id: Id.TIRTypeId, registry: TIR.Registry) -> Bool {
        isReferenceType(id, registry: registry, visited: [])
    }

    private static func isReferenceType(
        _ id: Id.TIRTypeId, registry: TIR.Registry, visited: Set<Id.TIRTypeId>
    ) -> Bool {
        guard !visited.contains(id), let ty = registry.types[id] else {
            return false
        }
        switch ty {
        case is TIRType.ClassType:
            return true
        case let pointer as TIRType.PointerType:
            return registry.types[pointer.pointee] is TIRType.ClassType
        case let structType as TIRType.StructType:
            let nested = visited.union([id])
            return structType.fields.contains { isReferenceType($0.type, registry: registry, visited: nested) }
        default:
            return false
        }
    }

    static func classType(of id: Id.TIRTypeId, registry: TIR.Registry) -> TIRType.ClassType? {
        guard let ty = registry.types[id] else {
            return nil
        }
        if let classType = ty as? TIRType.ClassType {
            return classType
        }
        if let pointee = pointee(of: id, registry: registry) {
            return registry.types[pointee] as? TIRType.ClassType
        }
        return nil
    }

    static func structType(of id: Id.TIRTypeId, registry: TIR.Registry) -> TIRType.StructType? {
        guard let ty = registry.types[id] else {
            return nil
        }
        if let structType = ty as? TIRType.StructType {
            return structType
        }
        if let pointee = pointee(of: id, registry: registry) {
            return registry.types[pointee] as? TIRType.StructType
        }
        return nil
    }

    private static func pointee(of id: Id.TIRTypeId, registry: TIR.Registry) -> Id.TIRTypeId? {
        switch registry.types[id] {
        case let address as TIRType.AddressType:
            address.pointee
        case let pointer as TIRType.PointerType:
            pointer.pointee
        default:
            nil
        }
    }

    static func needsTeardown(_ id: Id.TIRTypeId, registry: TIR.Registry) -> Bool {
        if let classType = classType(of: id, registry: registry) {
            return classNeedsTeardown(classType, registry: registry, visited: [])
        }
        if let structType = structType(of: id, registry: registry) {
            return structNeedsTeardown(structType, registry: registry)
        }
        return false
    }

    static func structNeedsTeardown(
        _ structType: TIRType.StructType, registry: TIR.Registry
    ) -> Bool {
        structType.fields.contains { isReferenceValue($0.type, registry: registry) }
    }

    private static func classNeedsTeardown(
        _ classType: TIRType.ClassType, registry: TIR.Registry, visited: Set<Id.TIRTypeId>
    ) -> Bool {
        guard !visited.contains(classType.id) else {
            return false
        }
        var nested = visited
        nested.insert(classType.id)
        if classType.fields.contains(where: {
            isReferenceType($0.type, registry: registry, visited: nested)
        }) {
            return true
        }
        guard let record = metadata(of: classType, registry: registry) else {
            return false
        }
        if !isNoOpDeinitializer(record, registry: registry) {
            return true
        }
        guard let superclassId = record.superclass,
              let superclassRecord = registry.metadatas[superclassId],
              let superclassType = superclassRecord.flatMapClassType(registry: registry)
        else {
            return false
        }
        return classNeedsTeardown(superclassType, registry: registry, visited: nested)
    }

    static func metadata(
        of classType: TIRType.ClassType, registry: TIR.Registry
    ) -> TIR.MetadataRecord? {
        registry.metadatas.values.first { $0.name == classType.displayText }
    }

    static func isNoOpDeinitializer(_ record: TIR.MetadataRecord, registry: TIR.Registry) -> Bool {
        guard let entry = record.vtable.first else {
            return true
        }
        return registry.functions[entry.function]?.name == noOpDeinitializerName
    }

    static func inheritedFieldCount(
        of classType: TIRType.ClassType, registry: TIR.Registry
    ) -> Int {
        guard let record = metadata(of: classType, registry: registry),
              let superclassId = record.superclass,
              let superclassRecord = registry.metadatas[superclassId],
              let superclassType = superclassRecord.flatMapClassType(registry: registry)
        else {
            return 0
        }
        return superclassType.fields.count
    }

    static func referenceFieldIndices(
        _ structType: TIRType.StructType, registry: TIR.Registry
    ) -> [Int] {
        structType.fields.enumerated().compactMap { index, field in
            isReferenceValue(field.type, registry: registry) ? index : nil
        }
    }

    static func hasReferenceFields(_ id: Id.TIRTypeId, registry: TIR.Registry) -> Bool {
        guard let type = registry.types[id] else {
            return false
        }
        if let structType = type as? TIRType.StructType {
            return !referenceFieldIndices(structType, registry: registry).isEmpty
        }
        if let classType = type as? TIRType.ClassType {
            return classType.fields.contains { isReferenceValue($0.type, registry: registry) }
        }
        return false
    }
}

private extension TIR.MetadataRecord {
    func flatMapClassType(registry: TIR.Registry) -> TIRType.ClassType? {
        registry.types.values.compactMap { $0 as? TIRType.ClassType }.first { $0.displayText == name }
    }
}
