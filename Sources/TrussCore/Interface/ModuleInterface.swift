import Foundation

public struct ModuleInterface: Equatable, Hashable {
    public var name: String
    public var root: InterfaceScope
    public init(name: String, root: InterfaceScope) {
        self.name = name
        self.root = root
    }
}

public struct InterfaceScope: Equatable, Hashable {
    public var modules: [InterfaceModule]
    public var types: [InterfaceType]
    public var values: [InterfaceValue]
    public init(modules: [InterfaceModule] = [], types: [InterfaceType] = [], values: [InterfaceValue] = []) {
        self.modules = modules
        self.types = types
        self.values = values
    }
}

public struct InterfaceModule: Equatable, Hashable {
    public var name: String
    public var scope: InterfaceScope
    public init(name: String, scope: InterfaceScope) {
        self.name = name
        self.scope = scope
    }
}

public enum InterfaceType: Equatable, Hashable {
    case Nominal(InterfaceNominal)
    case TypeAlias(InterfaceTypealias)
    case AssociatedType(InterfaceSimple)
    case Builtin(InterfaceSimple)
    case GenericParam(InterfaceSimple)
}

public enum InterfaceNominalKind: UInt8, Equatable, Hashable {
    case StructType = 0
    case ClassType = 1
    case EnumType = 2
    case ProtocolType = 3
    case ActorType = 4
}

public enum InterfaceTypeRefCode: UInt8 {
    case Void = 0
    case Never = 1
    case Error = 2
    case Builtin = 3
    case Nominal = 4
    case Pointer = 5
    case Tuple = 6
    case Function = 7
    case Composition = 8
    case Variadic = 9
    case GenericParam = 10
    case Forall = 11
    case TypeVariable = 12
}

public enum InterfaceTypeDeclCode: UInt8 {
    case Nominal = 0
    case TypeAlias = 1
    case AssociatedType = 2
    case Builtin = 3
    case GenericParam = 4
}

public enum InterfaceValueDeclCode: UInt8 {
    case Function = 0
    case Variable = 1
}

public struct InterfaceNominal: Equatable, Hashable {
    public var kind: InterfaceNominalKind
    public var name: String
    public var conformances: [String]
    public var superclass: String?
    public var cases: [InterfaceCase]
    public var scope: InterfaceScope
    public init(
        kind: InterfaceNominalKind,
        name: String,
        conformances: [String] = [],
        superclass: String? = nil,
        cases: [InterfaceCase] = [],
        scope: InterfaceScope = InterfaceScope()
    ) {
        self.kind = kind
        self.name = name
        self.conformances = conformances
        self.superclass = superclass
        self.cases = cases
        self.scope = scope
    }
}

public struct InterfaceCase: Equatable, Hashable {
    public var name: String
    public var associatedTypes: [InterfaceTypeRef]
    public init(name: String, associatedTypes: [InterfaceTypeRef] = []) {
        self.name = name
        self.associatedTypes = associatedTypes
    }
}

public struct InterfaceTypealias: Equatable, Hashable {
    public var name: String
    public var target: InterfaceTypeRef?
    public init(name: String, target: InterfaceTypeRef? = nil) {
        self.name = name
        self.target = target
    }
}

public struct InterfaceSimple: Equatable, Hashable {
    public var name: String
    public init(name: String) { self.name = name }
}

public enum InterfaceValue: Equatable, Hashable {
    case Function(InterfaceFunction)
    case Variable(InterfaceVariable)
}

public struct InterfaceFunction: Equatable, Hashable {
    public var name: String
    public var labels: [String?]
    public var hasDefaults: [Bool]
    public var isVararg: [Bool]
    public var isVariadic: Bool
    public var isStatic: Bool
    public var functionType: InterfaceTypeRef?
    public init(
        name: String,
        labels: [String?],
        hasDefaults: [Bool],
        isVararg: [Bool],
        isVariadic: Bool,
        isStatic: Bool = false,
        functionType: InterfaceTypeRef? = nil
    ) {
        self.name = name
        self.labels = labels
        self.hasDefaults = hasDefaults
        self.isVararg = isVararg
        self.isVariadic = isVariadic
        self.isStatic = isStatic
        self.functionType = functionType
    }
}

public struct InterfaceVariable: Equatable, Hashable {
    public var name: String
    public var isMutable: Bool
    public var type: InterfaceTypeRef?
    public init(name: String, isMutable: Bool = true, type: InterfaceTypeRef? = nil) {
        self.name = name
        self.isMutable = isMutable
        self.type = type
    }
}

public struct InterfaceTupleElement: Equatable, Hashable {
    public var label: String?
    public var type: InterfaceTypeRef
    public init(label: String?, type: InterfaceTypeRef) {
        self.label = label
        self.type = type
    }
}

public struct InterfaceFunctionType: Equatable, Hashable {
    public var parameters: [InterfaceTupleElement]
    public var isVariadic: Bool
    public var isAsync: Bool
    public var isThrowing: Bool
    public var throwsTypes: [InterfaceTypeRef]
    public var returnType: InterfaceTypeRef
    public init(
        parameters: [InterfaceTupleElement],
        isVariadic: Bool = false,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        throwsTypes: [InterfaceTypeRef] = [],
        returnType: InterfaceTypeRef
    ) {
        self.parameters = parameters
        self.isVariadic = isVariadic
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.throwsTypes = throwsTypes
        self.returnType = returnType
    }
}

public indirect enum InterfaceTypeRef: Equatable, Hashable {
    case Void
    case Never
    case Error
    case Builtin(String)
    case Nominal(String, [InterfaceTypeRef])
    case Pointer(InterfaceTypeRef, Bool)
    case Tuple([InterfaceTupleElement])
    case Function(InterfaceFunctionType)
    case Composition([InterfaceTypeRef])
    case Variadic(InterfaceTypeRef)
    case GenericParam(String)
    case Forall([String], InterfaceTypeRef)
    case TypeVariable(Int)
}

public struct TrussPackageDocument {
    public let interface: ModuleInterface
    public init(interface: ModuleInterface) { self.interface = interface }
}
