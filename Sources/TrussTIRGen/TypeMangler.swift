import TrussCore

final class TypeMangler {
    private let context: Context

    init(context: Context) {
        self.context = context
    }

    func nominalPath(_ type: TrussType.NominalType, modulePath: [Symbol.ModuleSymbol]) -> String {
        var result = "$t"
        let packageName = type.symbol.flatMap(\.packageId).flatMap { context.id2Symbol[$0]?.name }
            ?? "main"
        result += mangleIdentifier(packageName)
        for moduleSymbol in modulePath {
            result += mangleIdentifier(moduleSymbol.name)
        }
        var chain: [String] = []
        var current: Id.SymbolId? = type.symbol?.memberOf
        while let member = current, let owner = context.id2Symbol[member] {
            chain.append(owner.name)
            current = owner.memberOf
        }
        for name in chain.reversed() {
            result += "_"
            result += mangleIdentifier(name)
        }
        result += "_"
        result += mangleIdentifier(type.name)
        return result
    }

    func typeName(_ type: TrussType.TrussType, modulePath: [Symbol.ModuleSymbol]) -> String {
        switch type {
        case is TrussType.VoidType:
            return "Void"
        case is TrussType.NeverType:
            return "Never"
        case is TrussType.ErrorType:
            return "E"
        case let builtin as TrussType.BuiltinType:
            return "B" + builtin.name
        case let nominal as TrussType.NominalType:
            return nominalPath(nominal, modulePath: modulePath)
        case let optional as TrussType.GenericInstantiation
            where optional.base.name == "Optional":
            if let wrapped = optional.arguments.first {
                return "O" + typeName(wrapped, modulePath: modulePath)
            }
            return "O"
        case let pointer as TrussType.PointerType:
            return "P" + (pointer.isNonnull ? "n" : "u") + typeName(pointer.pointee, modulePath: modulePath)
        case let tuple as TrussType.TupleType:
            var result = "T"
            for element in tuple.elements {
                result += typeName(element.type, modulePath: modulePath)
            }
            return result
        case let function as TrussType.FunctionType:
            var result = "F"
            for parameter in function.parameters {
                result += typeName(parameter.type, modulePath: modulePath)
            }
            result += "R"
            result += typeName(function.returnType, modulePath: modulePath)
            if function.isAsync {
                result += "A"
            }
            if function.isThrowing {
                result += "T"
            }
            if !function.throwsTypes.isEmpty {
                result += "E"
                for throwsType in function.throwsTypes {
                    result += typeName(throwsType, modulePath: modulePath)
                }
            }
            return result
        case let composition as TrussType.CompositionType:
            var result = "C"
            for member in composition.members {
                result += typeName(member, modulePath: modulePath)
            }
            return result
        case let variadic as TrussType.VariadicType:
            return "V" + typeName(variadic.base, modulePath: modulePath)
        case let instantiation as TrussType.GenericInstantiation:
            var result = "G"
            result += typeName(instantiation.base, modulePath: modulePath)
            for argument in instantiation.arguments {
                result += typeName(argument, modulePath: modulePath)
            }
            return result
        case let forall as TrussType.ForallType:
            return "A" + typeName(forall.body, modulePath: modulePath)
        case let genericParam as TrussType.GenericParamType:
            return "p" + genericParam.name
        case let variable as TrussType.TypeVariableType:
            if let binding = variable.binding {
                return typeName(binding, modulePath: modulePath)
            } else {
                return "v\(variable.id.id)"
            }
        default:
            return "x"
        }
    }

    func mangleFunctionName(
        _ symbol: Symbol.FunctionSymbol, baseName: String, returnType: TrussType.TrussType,
        modulePath: [Symbol.ModuleSymbol]
    ) -> String {
        var result = "$t"
        let packageName = symbol.packageId.flatMap { context.id2Symbol[$0]?.name } ?? "main"
        result += mangleIdentifier(packageName)
        for moduleSymbol in modulePath {
            result += mangleIdentifier(moduleSymbol.name)
        }
        if let memberOf = symbol.memberOf, let owner = context.id2Symbol[memberOf] {
            result += "_"
            result += mangleIdentifier(owner.name)
        }
        result += "_"
        result += mangleIdentifier(baseName)
        if let functionType = symbol.functionType {
            let labels = symbol.signature.labels
            for (index, parameter) in functionType.parameters.enumerated() {
                let label = index < labels.count ? labels[index] : nil
                result += "_"
                result += mangleIdentifier(label ?? "_")
                result += mangleIdentifier(typeName(parameter.type, modulePath: modulePath))
            }
        }
        result += "_"
        result += mangleIdentifier(typeName(returnType, modulePath: modulePath))
        return result
    }

    func mangleGlobalName(_ symbol: Symbol.VariableSymbol, modulePath: [Symbol.ModuleSymbol]) -> String {
        let packageName = symbol.packageId.flatMap { context.id2Symbol[$0]?.name } ?? "main"
        var result = "$t" + mangleIdentifier(packageName)
        for moduleSymbol in modulePath {
            result += mangleIdentifier(moduleSymbol.name)
        }
        if let memberOf = symbol.memberOf, let owner = context.id2Symbol[memberOf] {
            result += "_"
            result += mangleIdentifier(owner.name)
        }
        result += "_"
        result += mangleIdentifier(symbol.name)
        return result
    }

    func mangleAccessorName(
        _ symbol: Symbol.VariableSymbol, suffix: String, returnType: TrussType.TrussType,
        modulePath: [Symbol.ModuleSymbol]
    ) -> String {
        var result = "$t"
        let packageName = symbol.packageId.flatMap { context.id2Symbol[$0]?.name } ?? "main"
        result += mangleIdentifier(packageName)
        for moduleSymbol in modulePath {
            result += mangleIdentifier(moduleSymbol.name)
        }
        if let memberOf = symbol.memberOf, let owner = context.id2Symbol[memberOf] {
            result += "_"
            result += mangleIdentifier(owner.name)
        }
        result += "_"
        result += mangleIdentifier(symbol.name)
        result += suffix
        result += "_"
        result += mangleIdentifier(typeName(returnType, modulePath: modulePath))
        return result
    }

    func mangleDeinitName(_ owner: Symbol.NominalTypeSymbol, modulePath: [Symbol.ModuleSymbol]) -> String {
        var result = "$t"
        result += mangleIdentifier("main")
        for moduleSymbol in modulePath {
            result += mangleIdentifier(moduleSymbol.name)
        }
        result += "_"
        result += mangleIdentifier(owner.name)
        result += "_"
        result += mangleIdentifier("deinit")
        result += "_"
        result += mangleIdentifier("Void")
        return result
    }

    func mangleIdentifier(_ name: String) -> String {
        "\(name.count)\(name)"
    }
}
