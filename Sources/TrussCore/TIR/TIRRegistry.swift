public extension TIR {
    final class MetadataRecord {
        public let id: Id.TIRMetadataId
        public let name: String
        public var superclass: Id.TIRMetadataId?
        public init(id: Id.TIRMetadataId, name: String) {
            self.id = id
            self.name = name
        }
    }

    final class Registry {
        public var functions: [Id.TIRFunctionId: Function] = [:]
        public var globals: [Id.TIRGlobalId: GlobalVariable] = [:]
        public var types: [Id.TIRTypeId: TIRType.TIRType] = [:]
        public var metadatas: [Id.TIRMetadataId: MetadataRecord] = [:]
        public var typeCache: [AnyHashable: TIRType.TIRType] = [:]
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
    }
}
