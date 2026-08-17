import SwiftAbstract

public enum TIR {
    public final class Module {
        public let registry: Registry
        public var globals: [GlobalVariable] = []
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
            return f
        }

        public func addGlobal(
            name: String, type: Id.TIRTypeId, isExtern: Bool
        ) -> GlobalVariable {
            let g = GlobalVariable(name: name, type: type, isExtern: isExtern)
            globals.append(g)
            return g
        }
    }

    public final class GlobalVariable {
        public let name: String
        public let type: Id.TIRTypeId
        public let isExtern: Bool
        public var initializer: [Instruction] = []
        public init(name: String, type: Id.TIRTypeId, isExtern: Bool) {
            self.name = name
            self.type = type
            self.isExtern = isExtern
        }
    }

    @abstractClass
    public class Value {
        public let ty: Id.TIRTypeId
        public let name: String
        @abstractInit
        public init(ty: Id.TIRTypeId, name: String) {
            self.ty = ty
            self.name = name
        }
    }

    public final class Function: Value {
        public weak var module: Module?
        public let id: Id.TIRFunctionId
        public let parameters: [Parameter]
        public let returnType: Id.TIRTypeId
        public let isVariadic: Bool
        public let isExtern: Bool
        public let callingConvention: String?
        public var basicBlocks: [BasicBlock] = []
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
            self.parameters = parameters
            self.returnType = returnType
            self.isVariadic = isVariadic
            self.isExtern = isExtern
            self.callingConvention = callingConvention
            super.init(ty: ty, name: name)
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
    public class Instruction: Value {
        @abstractInit
        public override init(ty: Id.TIRTypeId, name: String) {
            super.init(ty: ty, name: name)
        }

        @abstract
        public func accept(_ visitor: Visitor, additional: Any? = nil) -> Any?
    }
}
