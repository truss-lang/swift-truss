import SwiftBetterDiagnostic
import TrussCore

public struct TIRPassFailure {
    public let functionName: String
    public let slotName: String
    public let fromBlockName: String
    public let toBlockName: String
    public let sourceRange: SourceRange

    public var message: String {
        "cannot discharge live slot '\(slotName)' of function '\(functionName)'"
            + " on the edge from '\(fromBlockName)' to '\(toBlockName)'"
    }

    public init(
        functionName: String, slotName: String, fromBlockName: String, toBlockName: String,
        sourceRange: SourceRange
    ) {
        self.functionName = functionName
        self.slotName = slotName
        self.fromBlockName = fromBlockName
        self.toBlockName = toBlockName
        self.sourceRange = sourceRange
    }
}

public struct TIRPassResult {
    public let module: TIR.Module
    public let failures: [TIRPassFailure]

    public init(module: TIR.Module, failures: [TIRPassFailure]) {
        self.module = module
        self.failures = failures
    }
}

public final class TIRPass {
    public init() {}

    @discardableResult
    public func run(on module: TIR.Module) -> TIRPassResult {
        let splitter = EdgeDischargeSplitter(registry: module.registry)
        let discharges = splitter.split(module: module)
        let lowered = LifetimeRewriter(
            registry: module.registry, presplitDischarges: discharges
        ).rewrite(module: module)
        return TIRPassResult(module: lowered, failures: splitter.failures)
    }
}
