import SwiftAbstract
import SwiftBetterDiagnostic

public enum TIR {
    @abstractClass
    public class Instruction {
        public let sourceRange: SourceRange
        public weak var parentBlock: BasicBlock?
        public var result: Value?
        @abstractInit
        public init(_ sourceRange: SourceRange) {
            self.sourceRange = sourceRange
        }

        @abstract
        public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any?
    }

    public final class Module {
        public var globals: [GlobalVariable] = []
        public var functions: [Function] = []
        public var registry: Registry?
        public init() {}
    }

    public final class Registry {
        public enum TypeKey: Hashable {
            case primitive(TIRType.PrimitiveKind, Int)
            case void
            case tuple([TupleElementKey])
            case optional(Int)
            case function([FunctionParameterKey], isVariadic: Bool, isAsync: Bool, isThrowing: Bool, [Int], Int)
            case address(Int)
            case metatype(Int)
            case existential([Int])
            case pointer(Int)
            case archetype(String)
            case nominal(String)
        }

        public struct TupleElementKey: Hashable {
            public let label: String?
            public let type: Int
            public init(label: String?, type: Int) {
                self.label = label
                self.type = type
            }
        }

        public struct FunctionParameterKey: Hashable {
            public let label: String?
            public let type: Int
            public init(label: String?, type: Int) {
                self.label = label
                self.type = type
            }
        }

        public var functions: [Int: Function] = [:]
        public var types: [Int: TIRType.TIRType] = [:]
        private var typeKeys: [TypeKey: Int] = [:]
        private var nextFunctionIdCounter = 0
        private var nextTypeIdCounter = 0
        public init() {}

        public var nextFunctionId: Int {
            nextFunctionIdCounter
        }

        public var nextTypeId: Int {
            nextTypeIdCounter
        }

        @discardableResult
        public func registerType(_ type: TIRType.TIRType) -> Int {
            let key = typeKey(for: type)
            if let existing = typeKeys[key] {
                type.id = existing
                return existing
            }
            let id = nextTypeIdCounter
            nextTypeIdCounter += 1
            type.id = id
            types[id] = type
            typeKeys[key] = id
            return id
        }

        @discardableResult
        public func registerFunction(_ function: Function) -> Int {
            let id = nextFunctionIdCounter
            nextFunctionIdCounter += 1
            function.id = id
            functions[id] = function
            return id
        }

        public func type(_ id: Int) -> TIRType.TIRType? {
            types[id]
        }

        private func typeKey(for type: TIRType.TIRType) -> TypeKey {
            switch type {
            case let primitive as TIRType.PrimitiveType:
                .primitive(primitive.kind, primitive.bitWidth)
            case is TIRType.VoidType:
                .void
            case let tuple as TIRType.TupleType:
                .tuple(tuple.elements.map { TupleElementKey(label: $0.label, type: $0.type) })
            case let optional as TIRType.OptionalType:
                .optional(optional.wrapped)
            case let function as TIRType.FunctionType:
                .function(
                    function.parameters.map { FunctionParameterKey(label: $0.label, type: $0.type) },
                    isVariadic: function.isVariadic, isAsync: function.isAsync, isThrowing: function.isThrowing,
                    function.throwsTypes, function.returnType
                )
            case let address as TIRType.AddressType:
                .address(address.pointee)
            case let metatype as TIRType.MetatypeType:
                .metatype(metatype.instance)
            case let existential as TIRType.ExistentialType:
                .existential(existential.protocolTypes)
            case let pointer as TIRType.PointerType:
                .pointer(pointer.pointee)
            case let archetype as TIRType.ArchetypeType:
                .archetype(archetype.name)
            case let nominal as TIRType.NominalType:
                .nominal(nominal.name)
            default:
                fatalError("unreachable")
            }
        }
    }

    public final class GlobalVariable {
        public var name: String
        public var type: Int
        public var isExtern: Bool
        public var initializer: [Instruction] = []
        public init(name: String, type: Int, isExtern: Bool = false) {
            self.name = name
            self.type = type
            self.isExtern = isExtern
        }
    }

    public final class Function {
        public var id: Int = -1
        public var name: String
        public var genericSignature: TIRType.GenericSignature?
        public var arguments: [Argument] = []
        public var returnType: Int
        public var isVariadic: Bool
        public var isAsync: Bool
        public var isThrowing: Bool
        public var throwsTypes: [Int]
        public var isExtern: Bool
        public var callingConvention: String?
        public let entryBlock: BasicBlock
        public var blocks: [BasicBlock]
        public init(
            name: String, returnType: Int, isVariadic: Bool = false,
            isAsync: Bool = false, isThrowing: Bool = false, throwsTypes: [Int] = [],
            isExtern: Bool = false, callingConvention: String? = nil
        ) {
            self.name = name
            self.returnType = returnType
            self.isVariadic = isVariadic
            self.isAsync = isAsync
            self.isThrowing = isThrowing
            self.throwsTypes = throwsTypes
            self.isExtern = isExtern
            self.callingConvention = callingConvention
            let entry = BasicBlock(name: "entry")
            entryBlock = entry
            blocks = [entry]
        }
    }

    public final class BasicBlock {
        public var name: String
        public var arguments: [Argument] = []
        public var instructions: [Instruction] = []
        public init(name: String) {
            self.name = name
        }
    }

    public final class Argument: Value {
        public override init(name: String, type: Int, ownership: TIRType.Ownership) {
            super.init(name: name, type: type, ownership: ownership)
        }
    }

    public class Value {
        public let name: String
        public let type: Int
        public let ownership: TIRType.Ownership
        public weak var definingInstruction: Instruction?
        public init(name: String, type: Int, ownership: TIRType.Ownership) {
            self.name = name
            self.type = type
            self.ownership = ownership
        }
    }
}
