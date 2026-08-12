import SwiftAbstract
import SwiftBetterDiagnostic

public extension TIR {
    final class Dumper {
        public init() {}

        public func dump(_ module: TIR.Module) -> String {
            module.functions.map { dump($0) }.joined(separator: "\n")
        }

        public func dump(_ function: TIR.Function) -> String {
            var lines: [String] = []
            lines.append("function \(function.name)")
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

        private func signatureText(_ signature: TIRType.GenericSignature) -> String {
            var text = "generic <"
            text += signature.parameters.map(\.name).joined(separator: ", ") + ">"
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
                return result + "FunctionRef " + instruction.function.name
            case let instruction as Closure:
                return result + "Closure " + instruction.function.name + "(captures: "
                    + instruction.captures.map(\.name).joined(separator: ", ") + ")"
            case let instruction as ClassMethod:
                return result + "ClassMethod " + instruction.reference.name + ", "
                    + instruction.methodSymbol.name
            case let instruction as SuperMethod:
                return result + "SuperMethod " + instruction.reference.name + ", "
                    + instruction.methodSymbol.name
            case let instruction as WitnessMethod:
                return result + "WitnessMethod " + instruction.protocolSymbol.name + "."
                    + instruction.methodSymbol.name
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
            case let instruction as IntegerLiteral:
                return result + "IntegerLiteral " + String(instruction.value) + " : "
                    + typeText(instruction.literalType)
            case let instruction as FloatLiteral:
                return result + "FloatLiteral " + String(instruction.value) + " : "
                    + typeText(instruction.literalType)
            case let instruction as StringLiteral:
                return result + "StringLiteral \"" + instruction.value + "\""
            case let instruction as CharLiteral:
                return result + "CharLiteral \"" + String(instruction.value) + "\""
            case let instruction as BoolLiteral:
                return result + "BoolLiteral " + String(instruction.value)
            case let instruction as NullLiteral:
                return result + "NullLiteral : " + typeText(instruction.literalType)
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

        public func typeText(_ type: TIRType.TIRType) -> String {
            switch type {
            case let nominal as TIRType.NominalType:
                return "$" + nominal.name + "#" + String(nominal.id.id)
            case let tuple as TIRType.TupleType:
                return "$(" + tuple.elements.map { element in
                    if let label = element.label {
                        return label + ": " + typeText(element.type)
                    }
                    return typeText(element.type)
                }.joined(separator: ", ") + ")"
            case let optional as TIRType.OptionalType:
                return typeText(optional.wrapped) + "?"
            case let function as TIRType.FunctionType:
                var text = "$(" + function.parameters.map { parameter in
                    if let label = parameter.label {
                        return label + ": " + typeText(parameter.type)
                    }
                    return typeText(parameter.type)
                }.joined(separator: ", ") + ")"
                if function.isAsync { text += " async" }
                if function.isThrowing {
                    text += " throws"
                    if !function.throwsTypes.isEmpty {
                        text += "(" + function.throwsTypes.map(typeText).joined(separator: ", ")
                            + ")"
                    }
                }
                text += " -> " + typeText(function.returnType)
                return text
            case let address as TIRType.AddressType:
                return "$*" + typeText(address.pointee)
            case let metatype as TIRType.MetatypeType:
                return typeText(metatype.instance) + ".Type"
            case let existential as TIRType.ExistentialType:
                return "$any " + existential.protocolTypes.map(typeText).joined(separator: " & ")
            case let archetype as TIRType.ArchetypeType:
                return "$<" + archetype.name + ">"
            case let pointer as TIRType.PointerType:
                return "$ptr " + typeText(pointer.pointee)
            default:
                return "$?"
            }
        }
    }
}
