public extension TIR {
    final class MetadataRecord {
        public let id: Id.TIRMetadataId
        public let name: String
        public var superclass: Id.TIRMetadataId?
        public var conformedProtocols: [Id.TIRProtocolId] = []
        public init(id: Id.TIRMetadataId, name: String) {
            self.id = id
            self.name = name
        }
    }

    final class ProtocolRecord {
        public let id: Id.TIRProtocolId
        public let name: String
        public var requirements: [String] = []
        public init(id: Id.TIRProtocolId, name: String) {
            self.id = id
            self.name = name
        }
    }

    final class WitnessEntry {
        public let name: String
        public let function: Id.TIRFunctionId
        public init(name: String, function: Id.TIRFunctionId) {
            self.name = name
            self.function = function
        }
    }

    final class ValueWitnessRecord {
        public var initFunction: Id.TIRFunctionId?
        public var copy: Id.TIRFunctionId?
        public var destroy: Id.TIRFunctionId?
        public init() {}
    }

    final class WitnessRecord {
        public let id: Id.TIRWitnessId
        public let protocolId: Id.TIRProtocolId
        public let concreteType: Id.TIRTypeId
        public var entries: [WitnessEntry] = []
        public var valueWitness: ValueWitnessRecord = ValueWitnessRecord()
        public init(id: Id.TIRWitnessId, protocolId: Id.TIRProtocolId, concreteType: Id.TIRTypeId) {
            self.id = id
            self.protocolId = protocolId
            self.concreteType = concreteType
        }
    }

    final class Registry {
        public var functions: [Id.TIRFunctionId: Function] = [:]
        public var globals: [Id.TIRGlobalId: GlobalVariable] = [:]
        public var types: [Id.TIRTypeId: TIRType.TIRType] = [:]
        public var metadatas: [Id.TIRMetadataId: MetadataRecord] = [:]
        public var protocols: [Id.TIRProtocolId: ProtocolRecord] = [:]
        public var witnesses: [Id.TIRWitnessId: WitnessRecord] = [:]
        public var typeCache: [AnyHashable: TIRType.TIRType] = [:]
        private var witnessByConformance: [WitnessKey: Id.TIRWitnessId] = [:]
        private var existentialCache: [AnyHashable: TIRType.ExistentialType] = [:]
        private var voidTy: TIRType.VoidType?
        private var metadataTy: TIRType.MetadataType?
        public var nextFunctionId: Id.TIRFunctionId {
            .init(UInt64(functions.count))
        }

        public var nextGlobalId: Id.TIRGlobalId {
            .init(UInt64(globals.count))
        }

        public var nextTypeId: Id.TIRTypeId {
            .init(UInt64(types.count))
        }

        public var nextMetadataId: Id.TIRMetadataId {
            .init(UInt64(metadatas.count))
        }

        public var nextProtocolId: Id.TIRProtocolId {
            .init(UInt64(protocols.count))
        }

        public var nextWitnessId: Id.TIRWitnessId {
            .init(UInt64(witnesses.count))
        }

        public init() {}

        public func type(_ id: Id.TIRTypeId) -> TIRType.TIRType? {
            types[id]
        }

        public func metadata(_ id: Id.TIRMetadataId) -> MetadataRecord? {
            metadatas[id]
        }

        public func metadataType() -> TIRType.MetadataType {
            if let ty = metadataTy {
                return ty
            } else {
                let ty = TIRType.MetadataType(id: nextTypeId)
                metadataTy = ty
                types[ty.id] = ty
                return ty
            }
        }

        @discardableResult
        public func addMetadata(name: String) -> MetadataRecord {
            let record = MetadataRecord(id: nextMetadataId, name: name)
            metadatas[record.id] = record
            return record
        }

        @discardableResult
        public func addProtocol(name: String) -> ProtocolRecord {
            let record = ProtocolRecord(id: nextProtocolId, name: name)
            protocols[record.id] = record
            return record
        }

        public func witness(for conformance: (protocolId: Id.TIRProtocolId, concreteType: Id.TIRTypeId)) -> WitnessRecord? {
            guard let id = witnessByConformance[WitnessKey(conformance)] else { return nil }
            return witnesses[id]
        }

        @discardableResult
        public func addWitness(
            protocolId: Id.TIRProtocolId, concreteType: Id.TIRTypeId
        ) -> WitnessRecord {
            let key = WitnessKey((protocolId: protocolId, concreteType: concreteType))
            if let existing = witnessByConformance[key] {
                return witnesses[existing]!
            }
            let record = WitnessRecord(
                id: nextWitnessId, protocolId: protocolId, concreteType: concreteType
            )
            witnesses[record.id] = record
            witnessByConformance[key] = record.id
            return record
        }

        public func existentialType(
            protocols: [Id.TIRProtocolId], name: String
        ) -> TIRType.ExistentialType {
            let key = ExistentialKey(protocols: protocols)
            if let cached = existentialCache[key] {
                return cached
            }
            let ty = TIRType.ExistentialType(
                id: nextTypeId, protocols: protocols, name: name
            )
            types[ty.id] = ty
            existentialCache[key] = ty
            return ty
        }

        public func voidType() -> TIRType.VoidType {
            if let ty = voidTy {
                return ty
            } else {
                let ty = TIRType.VoidType(id: nextTypeId)
                voidTy = ty
                types[ty.id] = ty
                return ty
            }
        }

        public func primitiveType(kind: TIRType.PrimitiveKind, bitWidth: Int) -> TIRType.PrimitiveType {
            let key = PrimitiveKey(kind: kind, bitWidth: bitWidth)
            if let cached = typeCache[key] {
                return cached as! TIRType.PrimitiveType
            } else {
                let ty = TIRType.PrimitiveType(
                    id: nextTypeId,
                    kind: kind,
                    bitWidth: bitWidth
                )
                types[ty.id] = ty
                typeCache[key] = ty
                return ty
            }
        }

        public func integerType(isSigned: Bool, bitWidth: Int) -> TIRType.PrimitiveType {
            let kind: TIRType.PrimitiveKind = if isSigned { .Signed } else { .Unsigned }
            return primitiveType(kind: kind, bitWidth: bitWidth)
        }

        public func pointerType(pointee: Id.TIRTypeId) -> TIRType.PointerType {
            let key = PointerKey(pointee: pointee)
            if let cached = typeCache[key] {
                return cached as! TIRType.PointerType
            } else {
                let ty = TIRType.PointerType(
                    id: nextTypeId,
                    pointee: pointee
                )
                types[ty.id] = ty
                typeCache[key] = ty
                return ty
            }
        }

        public func functionType(
            parameters: [Id.TIRTypeId], returnType: Id.TIRTypeId, isVariadic: Bool
        ) -> TIRType.FunctionType {
            let key = FunctionTypeKey(
                parameters: parameters,
                returnType: returnType,
                isVariadic: isVariadic
            )
            if let cached = typeCache[key] {
                return cached as! TIRType.FunctionType
            } else {
                let ty = TIRType.FunctionType(
                    id: nextTypeId,
                    parameters: parameters,
                    returnType: returnType,
                    isVariadic: isVariadic
                )
                types[ty.id] = ty
                typeCache[key] = ty
                return ty
            }
        }

        public func structType(name: String) -> TIRType.StructType {
            if let cached = typeCache[name] {
                return cached as! TIRType.StructType
            } else {
                let ty = TIRType.StructType(
                    id: nextTypeId,
                    name: name
                )
                types[ty.id] = ty
                typeCache[name] = ty
                return ty
            }
        }

        public func enumType(name: String) -> TIRType.EnumType {
            if let cached = typeCache[name] {
                return cached as! TIRType.EnumType
            } else {
                let ty = TIRType.EnumType(
                    id: nextTypeId,
                    name: name
                )
                types[ty.id] = ty
                typeCache[name] = ty
                return ty
            }
        }

        public func classType(name: String) -> TIRType.ClassType {
            if let cached = typeCache[name] {
                return cached as! TIRType.ClassType
            } else {
                let ty = TIRType.ClassType(
                    id: nextTypeId,
                    name: name
                )
                types[ty.id] = ty
                typeCache[name] = ty
                return ty
            }
        }

        public func tupleType(elements: [TIRType.TupleType.Element]) -> TIRType.TupleType {
            let key = TupleKey(elements: elements)
            if let cached = typeCache[key] {
                return cached as! TIRType.TupleType
            } else {
                let ty = TIRType.TupleType(
                    id: nextTypeId,
                    elements: elements
                )
                types[ty.id] = ty
                typeCache[key] = ty
                return ty
            }
        }

        public func elementPointerType(base: Id.TIRTypeId, at index: Int) -> Id.TIRTypeId {
            guard let baseTy = types[base] else {
                return base
            }
            let aggregate: TIRType.TIRType = if let pointerType = baseTy as? TIRType.PointerType {
                types[pointerType.pointee] ?? baseTy
            } else {
                baseTy
            }
            let elementType: Id.TIRTypeId =
                switch aggregate {
                case let structType as TIRType.StructType:
                    structType.fields[index].type
                case let classType as TIRType.ClassType:
                    classType.fields[index].type
                case let tupleType as TIRType.TupleType:
                    tupleType.elements[index].type
                default:
                    base
                }
            return pointerType(pointee: elementType).id
        }

        private struct PrimitiveKey: Hashable, Equatable {
            let kind: TIRType.PrimitiveKind
            let bitWidth: Int
        }

        private struct PointerKey: Hashable, Equatable {
            let pointee: Id.TIRTypeId
        }

        private struct FunctionTypeKey: Hashable, Equatable {
            let parameters: [Id.TIRTypeId]
            let returnType: Id.TIRTypeId
            let isVariadic: Bool
        }

        private struct TupleKey: Hashable, Equatable {
            let elements: [TIRType.TupleType.Element]
        }

        private struct WitnessKey: Hashable, Equatable {
            let protocolId: Id.TIRProtocolId
            let concreteType: Id.TIRTypeId
            init(_ conformance: (protocolId: Id.TIRProtocolId, concreteType: Id.TIRTypeId)) {
                protocolId = conformance.protocolId
                concreteType = conformance.concreteType
            }
        }

        private struct ExistentialKey: Hashable, Equatable {
            let protocols: [Id.TIRProtocolId]
        }
    }
}
