import Foundation

public extension TIR {
    final class Dumper: Visitor {
        private var registry: TIR.Registry?

        public override init() {}

        public func dump(_ module: TIR.Module) -> String {
            registry = module.registry
            var lines: [String] = []
            let nominalTypes = module.registry.types.values.compactMap { $0 as? TIRType.NominalType }
                .sorted { $0.name < $1.name }
            for type in nominalTypes {
                lines.append("%" + type.name + " = type " + nominalBody(type))
            }
            if !nominalTypes.isEmpty {
                lines.append("")
            }
            for global in module.globals {
                let externMark = global.isExtern ? "external " : ""
                lines.append("@\(global.name) = \(externMark)global \(typeText(global.type))")
                if !global.initializer.isEmpty {
                    lines.append(contentsOf: global.initializer.map { "  " + instructionText($0) })
                }
            }
            let functions = module.functions
            if !module.globals.isEmpty, !functions.isEmpty {
                lines.append("")
            }
            lines.append(contentsOf: functions.map { dump($0) })
            return lines.joined(separator: "\n")
        }

        public func dump(_ function: TIR.Function) -> String {
            var lines: [String] = []
            let signature = functionSignature(function)
            if function.isExtern {
                lines.append("declare " + signature)
                return lines.joined(separator: "\n")
            }
            var attributes = ""
            if let convention = function.callingConvention {
                attributes += " \"\(convention)\""
            }
            lines.append("define " + signature + attributes + " {")
            for block in function.basicBlocks {
                if block.parameters.isEmpty {
                    lines.append(block.name + ":")
                } else {
                    let parameters = block.parameters.map {
                        "%" + $0.name + ": " + typeText($0.ty)
                    }
                    lines.append(block.name + "(" + parameters.joined(separator: ", ") + "):")
                }
                for instruction in block.instructions {
                    lines.append("  " + instructionText(instruction))
                }
            }
            lines.append("}")
            return lines.joined(separator: "\n")
        }

        private func functionSignature(_ function: TIR.Function) -> String {
            let returnText = typeText(function.returnType)
            let parameterText = function.parameters.map { parameter in
                typeText(parameter.ty) + " %" + parameter.name
            }
            var result = returnText + " @" + function.name + "(" + parameterText.joined(separator: ", ") + ")"
            if function.isVariadic {
                result += ", ..."
            }
            return result
        }

        private func nominalBody(_ type: TIRType.NominalType) -> String {
            switch type {
            case let structType as TIRType.StructType:
                return "{ " + structType.fields.map { $0.name + ": " + typeText($0.type) }
                    .joined(separator: ", ") + " }"
            case let classType as TIRType.ClassType:
                return "{ ptr" + (classType.fields.isEmpty ? "" : ", ") + classType.fields
                    .map { $0.name + ": " + typeText($0.type) }
                    .joined(separator: ", ") + " }"
            case let enumType as TIRType.EnumType:
                let cases = enumType.cases.map { caseInfo in
                    "." + caseInfo
                        .name +
                        (caseInfo.associatedTypes.isEmpty ? "" : "(" + caseInfo.associatedTypes.map { typeText($0) }
                            .joined(separator: ", ") + ")")
                }
                return "{ i32" + (cases.isEmpty ? "" : ", ") + cases.joined(separator: " | ") + " }"
            default:
                return "opaque"
            }
        }

        private func typeText(_ typeId: Id.TIRTypeId) -> String {
            guard let type = registry?.types[typeId] else { return "?" }
            switch type {
            case _ as TIRType.VoidType:
                return "void"
            case let primitive as TIRType.PrimitiveType:
                switch primitive.kind {
                case .Float:
                    return "f\(primitive.bitWidth)"
                case .Signed, .Unsigned, .Bool, .Char:
                    return "i\(primitive.bitWidth)"
                }
            case _ as TIRType.PointerType:
                return "ptr"
            case _ as TIRType.MetadataType:
                return "metadata"
            case let nominal as TIRType.NominalType:
                return "%" + nominal.name
            case let tuple as TIRType.TupleType:
                return "{ " + tuple.elements.map { typeText($0.type) }.joined(separator: ", ") + " }"
            case let function as TIRType.FunctionType:
                return "(" + function.parameters.map { typeText($0) }
                    .joined(separator: ", ") + ") -> " + typeText(function.returnType)
            case let existential as TIRType.ExistentialType:
                return "%" + existential.name
            default:
                return "?"
            }
        }

        private func enumCaseName(_ ty: Id.TIRTypeId, _ tag: Int) -> String {
            guard let type = registry?.types[ty] as? TIRType.EnumType,
                  tag >= 0, tag < type.cases.count
            else {
                return String(tag)
            }
            return type.cases[tag].name
        }

        private func valueText(_ value: Value) -> String {
            switch value {
            case let literal as IntegerLiteral:
                String(literal.value)
            case let literal as FloatLiteral:
                String(literal.value)
            case let literal as CharLiteral:
                "'" + String(literal.value) + "'"
            case let literal as BoolLiteral:
                literal.value ? "true" : "false"
            case let literal as StringLiteral:
                "\"" + literal.value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"") + "\""
            case _ as NullptrLiteral:
                "null"
            case _ as VoidLiteral:
                "void"
            case let function as FunctionRef:
                registry?.functions[function.functionId].map { "@" + $0.name } ?? "?"
            case let globalAddr as GlobalAddr:
                registry?.globals[globalAddr.globalId].map { "@" + $0.name } ?? "?"
            default:
                "%" + value.name
            }
        }

        private func blockLabel(_ block: BasicBlock) -> String {
            "label %" + block.name
        }

        private func instructionText(_ instruction: Instruction) -> String {
            let valuePrefix = instruction.name.isEmpty ? "" : "%" + instruction.name + " = "
            var body: String
            switch instruction {
            case let ret as Return:
                if let value = ret.value {
                    body = "ret \(typeText(value.ty)) \(valueText(value))"
                } else {
                    body = "ret void"
                }
            case let branch as Branch:
                body = "br " + blockLabel(branch.target)
                if !branch.arguments.isEmpty {
                    body += "(" + branch.arguments.map { valueText($0) }.joined(separator: ", ") + ")"
                }
            case let cond as ConditionalBranch:
                var trueTarget = blockLabel(cond.trueBranch)
                if !cond.trueArguments.isEmpty {
                    trueTarget += "(" + cond.trueArguments.map { valueText($0) }.joined(separator: ", ") + ")"
                }
                var falseTarget = blockLabel(cond.falseBranch)
                if !cond.falseArguments.isEmpty {
                    falseTarget += "(" + cond.falseArguments.map { valueText($0) }.joined(separator: ", ") + ")"
                }
                body = "br \(typeText(cond.condition.ty)) \(valueText(cond.condition)), "
                    + trueTarget + ", " + falseTarget
            case _ as Unreachable:
                body = "unreachable"
            case let phi as Phi:
                let incomings = phi.incomings.map { incoming in
                    "[" + valueText(incoming.value) + ", %" + incoming.block.name + "]"
                }
                body = "phi \(typeText(phi.result.ty)) " + incomings.joined(separator: ", ")
            case let switchEnum as SwitchEnum:
                var text = "switch \(typeText(switchEnum.value.ty)) \(valueText(switchEnum.value))"
                if let defaultBlock = switchEnum.defaultBlock {
                    text += ", " + blockLabel(defaultBlock)
                }
                text += " [ "
                text += switchEnum.cases.map { caseInfo in
                    var label = blockLabel(caseInfo.block)
                    if !caseInfo.arguments.isEmpty {
                        label += "(" + caseInfo.arguments.map { valueText($0) }.joined(separator: ", ") + ")"
                    }
                    return "case \(enumCaseName(switchEnum.value.ty, caseInfo.tag)), " + label
                }.joined(separator: ", ")
                text += " ]"
                body = text
            case let extract as ExtractPayload:
                body = "extractpayload \(typeText(extract.value.ty)) \(valueText(extract.value))"
            case let arith as UnaryArith:
                body = "\(arith.op.rawValue) \(typeText(arith.result.ty)) \(valueText(arith.operand))"
            case let arith as BinaryArith:
                body =
                    "\(arith.op.rawValue) \(typeText(arith.result.ty)) \(valueText(arith.lhs)), \(valueText(arith.rhs))"
            case let alloc as AllocStack:
                body = "alloca \(typeText(alloc.allocatedType))"
            case let dealloc as DeallocStack:
                body = "deallocstack \(valueText(dealloc.value))"
            case let alloc as AllocHeap:
                body = "allocheap \(typeText(alloc.allocatedType))"
            case let dealloc as DeallocHeap:
                body = "deallocheap \(valueText(dealloc.value))"
            case let alloc as AllocCell:
                body = "alloccell \(typeText(alloc.allocatedType))"
            case let dealloc as DeallocCell:
                body = "dealloccell \(valueText(dealloc.value))"
            case let load as Load:
                body = "load \(typeText(load.result.ty)), ptr \(valueText(load.ptr))"
            case let store as Store:
                body = "store \(typeText(store.value.ty)) \(valueText(store.value)), ptr \(valueText(store.ptr))"
            case let sizeOf as SizeOf:
                body = "sizeof \(typeText(sizeOf.sizedType))"
            case let structAddr as StructElementAddr:
                body =
                    "structelementaddr \(typeText(structAddr.base.ty)) \(valueText(structAddr.base)), \(structAddr.index)"
            case let tupleAddr as TupleElementAddr:
                body =
                    "tupleelementaddr \(typeText(tupleAddr.base.ty)) \(valueText(tupleAddr.base)), \(tupleAddr.index)"
            case let refAddr as ClassElementAddr:
                body = "refelementaddr \(typeText(refAddr.base.ty)) \(valueText(refAddr.base)), \(refAddr.index)"
            case let project as ProjectCell:
                body = "projectcell \(valueText(project.cell))"
            case let structValue as StructValue:
                body = "structvalue \(typeText(structValue.result.ty)) (" + structValue.fields.map { valueText($0) }
                    .joined(separator: ", ") + ")"
            case let tupleValue as TupleValue:
                body = "tuplevalue \(typeText(tupleValue.result.ty)) (" + tupleValue.elements.map { valueText($0) }
                    .joined(separator: ", ") + ")"
            case let enumValue as EnumValue:
                var text =
                    "enumvalue \(typeText(enumValue.result.ty)) case \(enumCaseName(enumValue.result.ty, enumValue.caseIndex))"
                if let payload = enumValue.payload {
                    text += ", \(valueText(payload))"
                }
                body = text
            case let call as Call:
                body = "call \(typeText(call.result?.ty ?? registry!.voidType().id)) \(valueText(call.callee))(" + call
                    .arguments.map { valueText($0) }
                    .joined(separator: ", ") + ")"
            case let tryCall as TryCall:
                var text =
                    "trycall \(typeText(tryCall.result?.ty ?? registry!.voidType().id)) \(valueText(tryCall.callee))(" +
                    tryCall.arguments
                    .map { valueText($0) }
                    .joined(separator: ", ") + ") to " + blockLabel(tryCall.successBlock) + ", error " +
                    blockLabel(tryCall.errorBlock)
                if let errorCell = tryCall.errorCell {
                    text += ", errorcell \(valueText(errorCell))"
                }
                body = text
            case let closure as Closure:
                body = "closure @\(closure.function.name)(" + closure.captures.map { valueText($0) }
                    .joined(separator: ", ") + ")"
            case let upcast as Upcast:
                body = "upcast \(valueText(upcast.value)) to \(typeText(upcast.targetType))"
            case let cast as UncheckedRefCast:
                body = "uncheckedrefcast \(valueText(cast.value)) to \(typeText(cast.targetType))"
            case let typeMetadata as TypeMetadata:
                body = "typemetadata \(valueText(typeMetadata.value))"
            case let typeMetadataConstant as TypeMetadataConstant:
                body = "typemetadataconstant \(typeText(typeMetadataConstant.type))"
            case let isInstance as IsInstance:
                body = "isinstance \(valueText(isInstance.metadata)), \(valueText(isInstance.target))"
            case let superclass as Superclass:
                body = "superclass \(valueText(superclass.metadata))"
            case let trap as Trap:
                if let message = trap.message {
                    body = "trap \"" + message + "\""
                } else {
                    body = "trap"
                }
            case let retain as Retain:
                body = "retain \(valueText(retain.value))"
            case let release as Release:
                body = "release \(valueText(release.value))"
            case let copy as Copy:
                body = "copy \(valueText(copy.value))"
            case let destroy as Destroy:
                body = "destroy \(valueText(destroy.value))"
            case let asm as InlineAsm:
                body = "asm \"" + asm.template + "\", \"" + asm.constraints.joined(separator: ",") + "\"(" + asm
                    .operands.map { valueText($0) }.joined(separator: ", ") + ")"
            case let build as BuildExistential:
                body = "buildexistential \(valueText(build.value)) witness \(build.witness.id) to \(typeText(build.result.ty))"
            case let open as OpenExistential:
                body = "openexistential \(valueText(open.container)) as \(typeText(open.result.ty))"
            case let witnessMethod as WitnessMethod:
                let args = ([witnessMethod.selfValue] + witnessMethod.arguments)
                    .map { valueText($0) }.joined(separator: ", ")
                body = "witnessmethod \(typeText(witnessMethod.selfValue.ty))#\(witnessMethod.witness.id).\(witnessMethod.index)(" + args + ")"
            case let existentialCopy as ExistentialCopy:
                body = "existentialcopy \(valueText(existentialCopy.container))"
            case let existentialDestroy as ExistentialDestroy:
                body = "existentialdestroy \(valueText(existentialDestroy.container))"
            default:
                body = "unknown"
            }
            return valuePrefix + body
        }
    }
}
