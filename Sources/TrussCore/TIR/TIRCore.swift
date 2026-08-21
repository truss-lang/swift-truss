import SwiftAbstract
import SwiftBetterDiagnostic

public enum TIR {
    public static var unknownSourceRange: SourceRange {
        SourceRange(
            location: SourceLocation(
                buffer: StringSourceBuffer(filePath: "<unknown>", content: ""),
                offset: 0, line: 0, column: 0
            )
        )
    }

    public final class Module {
        public let registry: Registry
        public var globals: [GlobalVariable] = []
        public var functions: [Function] = []
        public init(registry: Registry) {
            self.registry = registry
        }

        public func addFunction(
            name: String,
            parameters: [Parameter],
            returnType: Id.TIRTypeId,
            isVariadic: Bool,
            isExtern: Bool,
            callingConvention: String?
        ) -> Function {
            let ty = registry.functionType(
                parameters: parameters.map(\.ty),
                returnType: returnType,
                isVariadic: isVariadic
            )
            let f = Function(
                module: self,
                id: registry.nextFunctionId,
                name: name,
                ty: ty.id,
                parameters: parameters,
                returnType: returnType,
                isVariadic: isVariadic,
                isExtern: isExtern,
                callingConvention: callingConvention
            )
            registry.functions[f.id] = f
            functions.append(f)
            return f
        }

        public func addGlobal(
            name: String, type: Id.TIRTypeId, isExtern: Bool
        ) -> GlobalVariable {
            let g = GlobalVariable(
                id: registry.nextGlobalId, name: name, type: type, isExtern: isExtern
            )
            registry.globals[g.id] = g
            globals.append(g)
            return g
        }
    }

    public final class GlobalVariable {
        public let id: Id.TIRGlobalId
        public let name: String
        public let type: Id.TIRTypeId
        public let isExtern: Bool
        public var initializer: [Instruction] = []
        public var sourceRange: SourceRange = TIR.unknownSourceRange
        public init(id: Id.TIRGlobalId, name: String, type: Id.TIRTypeId, isExtern: Bool) {
            self.id = id
            self.name = name
            self.type = type
            self.isExtern = isExtern
        }
    }

    @abstractClass
    public class Value {
        public let ty: Id.TIRTypeId
        public let name: String
        public var sourceRange: SourceRange = TIR.unknownSourceRange
        @abstractInit
        public init(ty: Id.TIRTypeId, name: String) {
            self.ty = ty
            self.name = name
        }

        @abstract
        public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any?
    }

    public final class InstructionResult: Value {
        public override init(ty: Id.TIRTypeId, name: String) {
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            nil
        }
    }

    public final class Function {
        public weak var module: Module?
        public let id: Id.TIRFunctionId
        public let name: String
        public let ty: Id.TIRTypeId
        public let parameters: [Parameter]
        public let returnType: Id.TIRTypeId
        public let isVariadic: Bool
        public let isExtern: Bool
        public let callingConvention: String?
        public var basicBlocks: [BasicBlock] = []
        public var sourceRange: SourceRange = TIR.unknownSourceRange
        public init(
            module: Module,
            id: Id.TIRFunctionId,
            name: String,
            ty: Id.TIRTypeId,
            parameters: [Parameter],
            returnType: Id.TIRTypeId,
            isVariadic: Bool,
            isExtern: Bool,
            callingConvention: String?
        ) {
            self.module = module
            self.id = id
            self.name = name
            self.ty = ty
            self.parameters = parameters
            self.returnType = returnType
            self.isVariadic = isVariadic
            self.isExtern = isExtern
            self.callingConvention = callingConvention
        }

        public func addBasicBlock(name: String? = nil) -> BasicBlock {
            let bb = BasicBlock(function: self, name: name ?? String(basicBlocks.count))
            basicBlocks.append(bb)
            return bb
        }
    }

    public final class Parameter: Value {
        public override init(ty: Id.TIRTypeId, name: String) {
            super.init(ty: ty, name: name)
        }

        public override func accept(_ visitor: Visitor, additional: Any? = nil) -> Any? {
            visitor.visitParameter(self, additional: additional)
        }
    }

    public final class BasicBlock {
        public weak var function: Function?
        public let name: String
        public var instructions: [Instruction] = []
        public init(function: Function, name: String) {
            self.function = function
            self.name = name
        }
    }

    @abstractClass
    public class Instruction {
        public let name: String
        public var sourceRange: SourceRange = TIR.unknownSourceRange
        @abstractInit
        public init(name: String) {
            self.name = name
        }

        @abstract
        public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any?
    }
}
