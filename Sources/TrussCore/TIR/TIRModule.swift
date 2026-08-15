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
        public var functions: [Int: Function] = [:]
        public var types: [Int: TIRType.TIRType] = [:]
        public init() {}
        public var nextFunctionId: Int {
            functions.count
        }

        public var nextTypeId: Int {
            types.count
        }
    }

    public final class GlobalVariable {
        public var symbol: Symbol.VariableSymbol?
        public var name: String
        public var type: TIRType.TIRType
        public var isExtern: Bool
        public var initializer: [Instruction] = []
        public init(name: String, type: TIRType.TIRType, isExtern: Bool = false) {
            self.name = name
            self.type = type
            self.isExtern = isExtern
        }
    }

    public final class Function {
        public let id: Int
        public var symbol: Symbol.FunctionSymbol?
        public var name: String
        public var genericSignature: TIRType.GenericSignature?
        public var arguments: [Argument] = []
        public var returnType: TIRType.TIRType
        public var isVariadic: Bool
        public var isAsync: Bool
        public var isThrowing: Bool
        public var throwsTypes: [TIRType.TIRType]
        public var isExtern: Bool
        public var callingConvention: String?
        public let entryBlock: BasicBlock
        public var blocks: [BasicBlock]
        public init(
            id: Int, name: String, returnType: TIRType.TIRType, isVariadic: Bool = false,
            isAsync: Bool = false, isThrowing: Bool = false, throwsTypes: [TIRType.TIRType] = [],
            isExtern: Bool = false, callingConvention: String? = nil
        ) {
            self.id = id
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
        public override init(name: String, type: TIRType.TIRType, ownership: TIRType.Ownership) {
            super.init(name: name, type: type, ownership: ownership)
        }
    }

    public class Value {
        public let name: String
        public let type: TIRType.TIRType
        public let ownership: TIRType.Ownership
        public weak var definingInstruction: Instruction?
        public init(name: String, type: TIRType.TIRType, ownership: TIRType.Ownership) {
            self.name = name
            self.type = type
            self.ownership = ownership
        }
    }
}
