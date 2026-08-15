import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class Dumper {
        private var registry: TIR.Registry?

        public init() {}

        public func dump(_ module: TIR.Module) -> String {
            registry = module.registry
            var lines: [String] = []
            let types = collectTypes(module)
            if !types.isEmpty {
                lines.append("types:")
                for type in types {
                    lines.append("  " + type.name + nominalDefinition(type))
                }
                lines.append("")
            }
            for global in module.globals {
                let externMark = global.isExtern ? " extern" : ""
                lines.append("global\(externMark) \(global.name) : \(typeText(global.type))")
                for instruction in global.initializer {
                    lines.append("  " + instructionText(instruction))
                }
            }
            if !module.globals.isEmpty, !module.functions.isEmpty {
                lines.append("")
            }
            lines.append(contentsOf: module.functions.map { dump($0) })
            return lines.joined(separator: "\n")
        }

        private func collectTypes(_ module: TIR.Module) -> [TIRType.NominalType] {
            var seen = Set<String>()
            var result: [TIRType.NominalType] = []
            func visit(_ type: TIRType.TIRType) {
                switch type {
                case let nominal as TIRType.NominalType:
                    if seen.insert(nominal.name).inserted {
                        result.append(nominal)
                    }
                case let optional as TIRType.OptionalType:
                    visit(optional.wrapped)
                case let tuple as TIRType.TupleType:
                    for element in tuple.elements {
                        visit(element.type)
                    }
                case let function as TIRType.FunctionType:
                    for parameter in function.parameters {
                        visit(parameter.type)
                    }
                    for throwsType in function.throwsTypes {
                        visit(throwsType)
                    }
                    visit(function.returnType)
                case let address as TIRType.AddressType:
                    visit(address.pointee)
                case let metatype as TIRType.MetatypeType:
                    visit(metatype.instance)
                case let existential as TIRType.ExistentialType:
                    for protocolType in existential.protocolTypes {
                        visit(protocolType)
                    }
                case let pointer as TIRType.PointerType:
                    visit(pointer.pointee)
                default:
                    break
                }
            }
            func visit(_ typeId: Int) {
                if let type = registry?.types[typeId] {
                    visit(type)
                }
            }
            for global in module.globals {
                visit(global.type)
                for instruction in global.initializer {
                    if let value = instruction.result {
                        visit(value.type)
                    }
                }
            }
            for function in module.functions {
                visit(function.returnType)
                for throwsType in function.throwsTypes {
                    visit(throwsType)
                }
                for argument in function.arguments {
                    visit(argument.type)
                }
                for block in function.blocks {
                    for argument in block.arguments {
                        visit(argument.type)
                    }
                    for instruction in block.instructions {
                        if let value = instruction.result {
                            visit(value.type)
                        }
                    }
                }
            }
            return result.sorted { $0.name < $1.name }
        }

        public func dump(_ function: TIR.Function) -> String {
            var lines: [String] = []
            var attributes = ""
            if function.isExtern {
                attributes += " extern"
            }
            if let convention = function.callingConvention {
                attributes += " \"" + convention + "\""
            }
            lines.append("function \(function.name)\(attributes) " + functionSignatureText(function))
            if let genericSignature = function.genericSignature {
                lines.append("  " + signatureText(genericSignature))
            }
            for block in function.blocks {
                lines.append(block.name + ":")
                for argument in block.arguments {
                    lines.append(
                        "  " + argument.name + " = argument " + typeText(argument.type)
                    )
                }
                for instruction in block.instructions {
                    lines.append("  " + instructionText(instruction))
                }
            }
            return lines.joined(separator: "\n")
        }

        private func functionSignatureText(_ function: TIR.Function) -> String {
            let args = function.arguments.map { "\($0.name) \(innerTypeText($0.type))" }.joined(separator: ", ")
            let variadic = if function.isVariadic {
                if args.isEmpty {
                    "..."
                } else {
                    ", ..."
                }
            } else {
                ""
            }
            return "(\(args)\(variadic)) -> " + functionReturnTypeText(function.returnType)
        }

        private func functionReturnTypeText(_ type: Int) -> String {
            guard let resolved = registry?.types[type] else { return "?" }
            return functionReturnTypeText(resolved)
        }

        private func functionReturnTypeText(_ type: TIRType.TIRType) -> String {
            if type is TIRType.VoidType {
                return "()"
            }
            return innerTypeText(type)
        }

        private func signatureText(_ signature: TIRType.GenericSignature) -> String {
            var text = "generic <"
            text += signature.parameters.joined(separator: ", ") + ">"
            if !signature.requirements.isEmpty {
                text += " where "
                text += signature.requirements.map(requirementText).joined(separator: ", ")
            }
            return text
        }

        private func requirementText(_ requirement: TIRType.Requirement) -> String {
            switch requirement.kind {
            case let .Conformance(protocolType):
                typeText(requirement.subject) + " : " + typeText(protocolType)
            case let .Equality(type):
                typeText(requirement.subject) + " == " + typeText(type)
            }
        }

        private func instructionText(_ instruction: Instruction) -> String {
            let text = instructionBodyText(instruction)
            if let value = instruction.result {
                return text + " : " + typeText(value.type)
            }
            return text
        }

        private func instructionBodyText(_ instruction: Instruction) -> String {
            let result = instruction.result.map { $0.name + " = " } ?? ""
            switch instruction {
            case let instruction as AllocStack:
                return result + "AllocStack " + typeText(instruction.allocatedType)
            case let instruction as AllocCell:
                return result + "AllocCell " + typeText(instruction.allocatedType)
            case let instruction as AllocRef:
                return result + "AllocRef " + typeText(instruction.referenceType)
            case let instruction as DeallocStack:
                return "DeallocStack " + instruction.address.name
            case let instruction as DeallocCell:
                return "DeallocCell " + instruction.address.name
            case let instruction as DeallocRef:
                return "DeallocRef " + instruction.reference.name
            case let instruction as Load:
                return result + "Load " + instruction.address.name
            case let instruction as Store:
                return "Store " + instruction.value.name + " to " + instruction.address.name
            case let instruction as ProjectCell:
                return result + "ProjectCell " + instruction.address.name
            case let instruction as RefElementAddr:
                return result + "RefElementAddr " + instruction.reference.name + ", #"
                    + String(instruction.fieldIndex) + " " + instruction.fieldName
            case let instruction as StructElementAddr:
                return result + "StructElementAddr " + instruction.structAddress.name + ", #"
                    + String(instruction.fieldIndex) + " " + instruction.fieldName
            case let instruction as TupleElementAddr:
                return result + "TupleElementAddr " + instruction.tupleAddress.name + ", #"
                    + String(instruction.index)
            case let instruction as AddressToPointer:
                return result + "AddressToPointer " + instruction.address.name
            case let instruction as GlobalAddr:
                return result + "GlobalAddr " + instruction.global.name
            case let instruction as CopyValue:
                return result + "CopyValue " + instruction.value.name
            case let instruction as DestroyValue:
                return "DestroyValue " + instruction.value.name
            case let instruction as RetainValue:
                return "RetainValue " + instruction.value.name
            case let instruction as ReleaseValue:
                return "ReleaseValue " + instruction.value.name
            case let instruction as BorrowValue:
                return result + "BorrowValue " + instruction.value.name
            case let instruction as EndBorrow:
                return "EndBorrow " + instruction.value.name
            case let instruction as MoveValue:
                return result + "MoveValue " + instruction.value.name
            case let instruction as FunctionRef:
                return result + "FunctionRef "
                    + (registry?.functions[instruction.functionId]?.name ?? "?")
            case let instruction as Closure:
                return result + "Closure "
                    + (registry?.functions[instruction.functionId]?.name ?? "?")
                    + "(captures: "
                    + instruction.captures.map(\.name).joined(separator: ", ") + ")"
            case let instruction as ClassMethod:
                return result + "ClassMethod " + instruction.reference.name + ", "
                    + instruction.methodName
            case let instruction as SuperMethod:
                return result + "SuperMethod " + instruction.reference.name + ", "
                    + instruction.methodName
            case let instruction as WitnessMethod:
                return result + "WitnessMethod " + instruction.protocolName + "."
                    + instruction.methodName
            case let instruction as Apply:
                return result + "Apply " + applyText(instruction.callee, instruction.arguments)
                    + substitutionText(instruction.substitutions)
            case let instruction as TryApply:
                return result + "TryApply " + applyText(instruction.callee, instruction.arguments)
                    + " success: " + instruction.successBlock.name + ", error: "
                    + instruction.errorBlock.name
            case let instruction as PartialApply:
                return result + "PartialApply " + applyText(instruction.callee, instruction.arguments)
            case let instruction as Upcast:
                return result + "Upcast " + instruction.value.name + " to "
                    + typeText(instruction.targetType)
            case let instruction as UncheckedRefCast:
                return result + "UncheckedRefCast " + instruction.value.name + " to "
                    + typeText(instruction.targetType)
            case let instruction as InitExistential:
                return result + "InitExistential " + instruction.value.name + " to "
                    + typeText(instruction.existentialType)
            case let instruction as OpenExistential:
                return result + "OpenExistential " + instruction.value.name
            case let instruction as Branch:
                return "Branch " + instruction.target.name
            case let instruction as CondBranch:
                return "CondBranch " + instruction.condition.name + ", true: "
                    + instruction.trueBlock.name + ", false: " + instruction.falseBlock.name
            case let instruction as SwitchEnum:
                var text = "SwitchEnum " + instruction.value.name
                for entry in instruction.cases {
                    text += ", case " + entry.caseName + ": " + entry.block.name
                }
                if let defaultBlock = instruction.defaultBlock {
                    text += ", default: " + defaultBlock.name
                }
                return text
            case let instruction as SwitchValue:
                var text = "SwitchValue " + instruction.value.name
                for entry in instruction.cases {
                    text += ", case " + entry.literal.name + ": " + entry.block.name
                }
                if let defaultBlock = instruction.defaultBlock {
                    text += ", default: " + defaultBlock.name
                }
                return text
            case let instruction as Return:
                if let value = instruction.value {
                    return "Return " + value.name
                }
                return "Return"
            case let instruction as Throw:
                return "Throw " + instruction.value.name
            case is Unreachable:
                return "Unreachable"
            case is Trap:
                return "Trap"
            case let instruction as InlineAsm:
                var text = "InlineAsm \"" + instruction.template + "\""
                if !instruction.constraints.isEmpty {
                    text += " constraints: [" + instruction.constraints.joined(separator: ", ") + "]"
                }
                if !instruction.operands.isEmpty {
                    text += " operands: [" + instruction.operands.map(\.name).joined(separator: ", ") + "]"
                }
                if !instruction.options.isEmpty {
                    text += " options: [" + instruction.options.joined(separator: ", ") + "]"
                }
                return text
            case let instruction as Phi:
                var text = result + "Phi"
                for (index, incoming) in instruction.incomings.enumerated() {
                    if index > 0 { text += "," }
                    text += " [" + incoming.value.name + ", " + incoming.block.name + "]"
                }
                return text
            case let instruction as IntegerLiteral:
                return result + "IntegerLiteral " + String(instruction.value)
            case let instruction as FloatLiteral:
                return result + "FloatLiteral " + String(instruction.value)
            case let instruction as StringLiteral:
                return result + "StringLiteral \"" + instruction.value + "\""
            case let instruction as CharLiteral:
                return result + "CharLiteral \"" + String(instruction.value) + "\""
            case let instruction as BoolLiteral:
                return result + "BoolLiteral " + String(instruction.value)
            case is NullLiteral:
                return result + "NullLiteral"
            case is NullptrLiteral:
                return result + "NullptrLiteral"
            case is VoidLiteral:
                return result + "VoidLiteral"
            case let instruction as ArrayValue:
                return result + "ArrayValue [" + instruction.elements.map(\.name).joined(separator: ", ")
                    + "]"
            case let instruction as DictionaryValue:
                return result + "DictionaryValue ["
                    + instruction.entries.map { $0.key.name + ": " + $0.value.name }
                    .joined(separator: ", ") + "]"
            case let instruction as StructValue:
                return result + "StructValue " + typeText(instruction.structType) + " ["
                    + instruction.fields.map { $0.name + ": " + $0.value.name }
                    .joined(separator: ", ") + "]"
            case let instruction as TupleValue:
                return result + "TupleValue (" + instruction.elements.map(\.name)
                    .joined(separator: ", ") + ")"
            case let instruction as EnumValue:
                var text = result + "EnumValue " + typeText(instruction.enumType) + ", case "
                    + instruction.caseName
                if let payload = instruction.payload {
                    text += ", payload: " + payload.name
                }
                return text
            case let instruction as InitEnumDataAddr:
                return result + "InitEnumDataAddr " + instruction.enumAddress.name + ", case "
                    + instruction.caseName
            case let instruction as UncheckedEnumData:
                return result + "UncheckedEnumData " + instruction.enumValue.name + ", case "
                    + instruction.caseName
            case let instruction as ExistentialMetatype:
                return result + "ExistentialMetatype " + instruction.value.name
            case let instruction as GenericMetatype:
                return result + "GenericMetatype " + instruction.value.name
            case let instruction as OpenArchetype:
                return result + "OpenArchetype " + instruction.value.name + " : "
                    + typeText(instruction.archetype)
            default:
                return result + "Unknown"
            }
        }

        private func applyText(_ callee: Value, _ arguments: [Value]) -> String {
            callee.name + "(" + arguments.map(\.name).joined(separator: ", ") + ")"
        }

        private func substitutionText(_ substitutions: [Substitution]) -> String {
            if substitutions.isEmpty { return "" }
            return " <" + substitutions.map { typeText($0.concreteType) }.joined(separator: ", ")
                + ">"
        }

        public func typeText(_ typeId: Int) -> String {
            guard let type = registry?.types[typeId] else { return "?" }
            return typeText(type)
        }

        public func typeText(_ type: TIRType.TIRType) -> String {
            switch type {
            case is TIRType.VoidType:
                return "()"
            case let primitive as TIRType.PrimitiveType:
                return primitiveKindText(primitive.kind) + String(primitive.bitWidth)
            case let nominal as TIRType.NominalType:
                return nominal.name
            case let tuple as TIRType.TupleType:
                return "$(" + tuple.elements.map { element in
                    if let label = element.label {
                        return label + ": " + innerTypeText(element.type)
                    }
                    return innerTypeText(element.type)
                }.joined(separator: ", ") + ")"
            case let optional as TIRType.OptionalType:
                return typeText(optional.wrapped) + "?"
            case let function as TIRType.FunctionType:
                let parameters = function.parameters.map { parameter in
                    if let label = parameter.label {
                        return label + ": " + innerTypeText(parameter.type)
                    }
                    return innerTypeText(parameter.type)
                }.joined(separator: ", ")
                let variadic = if function.isVariadic {
                    if parameters.isEmpty {
                        "..."
                    } else {
                        ", ..."
                    }
                } else {
                    ""
                }
                var text = "$(\(parameters)\(variadic))"
                if function.isAsync { text += " async" }
                if function.isThrowing {
                    text += " throws"
                    if !function.throwsTypes.isEmpty {
                        text += "(" + function.throwsTypes.map(innerTypeText).joined(separator: ", ")
                            + ")"
                    }
                }
                text += " -> " + functionReturnTypeText(function.returnType)
                return text
            case let address as TIRType.AddressType:
                return "$*" + innerTypeText(address.pointee)
            case let metatype as TIRType.MetatypeType:
                return typeText(metatype.instance) + ".Type"
            case let existential as TIRType.ExistentialType:
                return "$any " + existential.protocolTypes.map(innerTypeText).joined(separator: " & ")
            case let archetype as TIRType.ArchetypeType:
                return "$<" + archetype.name + ">"
            case let pointer as TIRType.PointerType:
                return "$ptr " + innerTypeText(pointer.pointee)
            default:
                return "$?"
            }
        }

        private func innerTypeText(_ typeId: Int) -> String {
            let text = typeText(typeId)
            if text.hasPrefix("$") {
                return String(text.dropFirst())
            }
            return text
        }

        private func innerTypeText(_ type: TIRType.TIRType) -> String {
            let text = typeText(type)
            if text.hasPrefix("$") {
                return String(text.dropFirst())
            }
            return text
        }

        private func primitiveKindText(_ kind: TIRType.PrimitiveKind) -> String {
            switch kind {
            case .Signed: "i"
            case .Unsigned: "u"
            case .Float: "f"
            case .Bool: "b"
            case .Char: "c"
            }
        }

        private func nominalDefinition(_ nominal: TIRType.NominalType) -> String {
            let members: [String] = switch nominal {
            case let structType as TIRType.StructType:
                structType.fields.map { "\($0.name): " + fieldTypeText($0.type) }
            case let referenceType as TIRType.ReferenceType:
                referenceType.fields.map { "\($0.name): " + fieldTypeText($0.type) }
            case let enumType as TIRType.EnumType:
                enumType.cases.map(caseText)
            default:
                []
            }
            if members.isEmpty {
                return ""
            }
            return " { " + members.joined(separator: ", ") + " }"
        }

        private func fieldTypeText(_ typeId: Int) -> String {
            guard let type = registry?.types[typeId] else { return "?" }
            return typeText(type)
        }

        private func caseText(_ entry: (name: String, associatedTypeIds: [Int])) -> String {
            if entry.associatedTypeIds.isEmpty {
                return "." + entry.name
            }
            return "." + entry.name + "("
                + entry.associatedTypeIds.map(fieldTypeText).joined(separator: ", ") + ")"
        }
    }
}
