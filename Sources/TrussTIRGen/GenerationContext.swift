import SwiftBetterDiagnostic
import TrussCore

struct VirtualMethodSlot {
    let metadata: Id.TIRMetadataId
    let index: Int
}

final class GenerationContext {
    let context: Context
    let registry: TIR.Registry
    let mangler: Mangler
    let typeLower: TypeLower
    var modules: [TIR.Module] = []
    var currentModule: TIR.Module?
    var builder: TIR.Builder?
    var functionsBySymbol: [Id.SymbolId: TIR.Function] = [:]
    var globalsBySymbol: [Id.SymbolId: TIR.GlobalVariable] = [:]
    var env: [Id.SymbolId: TIR.Value] = [:]
    var modulePathStack: [Symbol.ModuleSymbol] = []
    var externContextStack: [String] = []
    var collectTypeStack: [Symbol.NominalTypeSymbol] = []
    var staticVariableSymbols: Set<Id.SymbolId> = []
    var deinitFunctions: [ObjectIdentifier: TIR.Function] = [:]
    var deinitOwners: [ObjectIdentifier: Symbol.NominalTypeSymbol] = [:]
    var sharedNoOpDeinitializers: [ObjectIdentifier: TIR.Function] = [:]
    var sharedNoOpDeinitializerByClass: [ObjectIdentifier: TIR.Function] = [:]
    var sharedNoOpDeinitializerIds: Set<Id.TIRFunctionId> = []
    var fieldDeinitializers: [ObjectIdentifier: TIR.Function] = [:]
    var classModules: [ObjectIdentifier: TIR.Module] = [:]
    var storedProperties: [Id.ASTTypeId: [StoredProperty]] = [:]
    var defaultInitializers: [ObjectIdentifier: TIR.Function] = [:]
    var existentialBoxes: [Id.SymbolId: ExistentialBox] = [:]
    var virtualMethodSlots: [Id.SymbolId: VirtualMethodSlot] = [:]

    struct ExistentialBox {
        let witnesses: [Id.TIRProtocolId: Id.TIRWitnessId]
        let concreteType: Id.TIRTypeId
        let containerType: Id.TIRTypeId
    }

    init(context: Context) {
        self.context = context
        registry = .init()
        mangler = .init(context: context)
        typeLower = .init(context: context, mangler: mangler, registry: registry)
        builder = .init(registry: registry)
    }

    func makeModule() -> TIR.Module {
        let module = TIR.Module(registry: registry)
        modules.append(module)
        currentModule = module
        return module
    }

    func sharedNoOpDeinitializer(sourceRange: SourceRange) -> TIR.Function? {
        guard let module = currentModule else {
            return nil
        }
        let key = ObjectIdentifier(module)
        if let existing = sharedNoOpDeinitializers[key] {
            return existing
        }
        let function = module.addFunction(
            name: TIR.noOpDeinitializerName, parameters: [], returnType: registry.voidType().id,
            isVariadic: false, isExtern: false, callingConvention: nil
        )
        function.sourceRange = sourceRange
        let entry = function.addBasicBlock(name: "entry")
        entry.sourceRange = sourceRange
        let returnInstruction = TIR.Return(value: nil)
        returnInstruction.sourceRange = sourceRange
        entry.instructions.append(returnInstruction)
        sharedNoOpDeinitializers[key] = function
        sharedNoOpDeinitializerIds.insert(function.id)
        return function
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

let fieldDeinitializerName = "$t_field_deinit_"

func ownedConventions(count: Int) -> [TIR.Ownership] {
    Array(repeating: TIR.Ownership.Owned, count: count)
}

func parameterConventions(selfKind: Symbol.FunctionSymbol.Kind?, count: Int) -> [TIR.Ownership] {
    (0 ..< count).map { index in
        if index == 0, let selfKind, selfKind != .Initializer {
            return TIR.Ownership.Guaranteed
        }
        return TIR.Ownership.Owned
    }
}

let deinitializerSlotName = "deinit"
