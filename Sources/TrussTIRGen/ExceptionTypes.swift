import TrussCore

final class ExceptionTypes {
    let registry: TIR.Registry

    init(registry: TIR.Registry) {
        self.registry = registry
    }

    func errorBoxType() -> Id.TIRTypeId {
        registry.errorBoxType().id
    }

    func errUnionType(name: String, okReturnType: Id.TIRTypeId) -> Id.TIRTypeId {
        let union = registry.enumType(name: name)
        union.cases = [
            (name: "ok", associatedTypes: [okReturnType]),
            (name: "err", associatedTypes: [errorBoxType()]),
        ]
        return union.id
    }

    func metadataGlobalName(typeId: Id.TIRTypeId) -> String {
        "meta." + String(typeId.id)
    }
}
