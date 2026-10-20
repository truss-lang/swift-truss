public extension TIR {
    final class Dumper: Visitor {
        private var registry: TIR.Registry?

        public override init() {}

        public func dump(_ module: TIR.Module) -> String {
            registry = module.registry
            var sections: [String] = []
            let nominalTypes = module.registry.types.values.compactMap { $0 as? TIRType.NominalType }
                .sorted { $0.name < $1.name }
            if !nominalTypes.isEmpty {
                sections.append(
                    nominalTypes.map { "type " + $0.displayText + " = " + nominalBody($0) }
                        .joined(separator: "\n")
                )
            }
            let metadataLines = metadataSection(module)
            if !metadataLines.isEmpty {
                sections.append(metadataLines.joined(separator: "\n"))
            }
            if !module.globals.isEmpty {
                sections.append(module.globals.map { globalText($0) }.joined(separator: "\n"))
            }
            if !module.functions.isEmpty {
                sections.append(module.functions.map { dump($0) }.joined(separator: "\n\n"))
            }
            return sections.joined(separator: "\n\n")
        }

        public func dump(_ function: TIR.Function) -> String {
            var header = function.isExtern ? "tir.extern" : "tir"
            header += " @" + function.name + "(" + parameterList(function) + ")"
            header += " -> " + ownershipKeyword(resultOwnership(function)) + " " + typeText(function.returnType)
            if let convention = function.callingConvention {
                header += " cc " + convention
            }
            if function.isExtern {
                return header
            }
            var lines = [header + " {"]
            for block in function.basicBlocks {
                lines.append(blockHeader(block))
                for instruction in block.instructions {
                    lines.append("  " + instructionText(instruction))
                }
            }
            lines.append("}")
            return lines.joined(separator: "\n")
        }

        private func parameterList(_ function: TIR.Function) -> String {
            var parts = function.parameters.enumerated().map { index, parameter in
                ownershipKeyword(parameterOwnership(function, index)) + " %" + parameter.name + ": "
                    + typeText(parameter.ty)
            }
            if function.isVariadic {
                parts.append("...")
            }
            return parts.joined(separator: ", ")
        }

        private func functionType(_ function: TIR.Function) -> TIRType.FunctionType? {
            registry?.types[function.ty] as? TIRType.FunctionType
        }

        private func parameterOwnership(_ function: TIR.Function, _ index: Int) -> Ownership {
            guard let ownership = functionType(function)?.parameterOwnership,
                  ownership.indices.contains(index)
            else {
                return .Owned
            }
            return ownership[index]
        }

        private func resultOwnership(_ function: TIR.Function) -> Ownership {
            functionType(function)?.resultOwnership ?? .Owned
        }

        private func ownershipKeyword(_ ownership: Ownership) -> String {
            switch ownership {
            case .Owned:
                "owned"
            case .Guaranteed:
                "guaranteed"
            }
        }

        private func blockHeader(_ block: BasicBlock) -> String {
            guard !block.parameters.isEmpty else {
                return "^" + block.name + ":"
            }
            let parameters = block.parameters.enumerated().map { index, parameter in
                "%" + blockArgumentName(parameter, index: index) + ": " + typeText(parameter.ty)
            }
            return "^" + block.name + "(" + parameters.joined(separator: ", ") + "):"
        }

        private func blockArgumentName(_ argument: BlockArgument, index: Int) -> String {
            argument.name.isEmpty ? "arg" + String(index) : argument.name
        }

        private func metadataSection(_ module: TIR.Module) -> [String] {
            var lines: [String] = []
            for metadata in module.registry.metadatas.values.sorted(by: {
                ($0.name, $0.id.id) < ($1.name, $1.id.id)
            }) {
                var attributes: [String] = []
                if let superclass = metadata.superclass {
                    attributes.append("super @" + metadataName(superclass))
                }
                if !metadata.conformedProtocols.isEmpty {
                    let protocols = metadata.conformedProtocols.map { protocolName($0) }
                    attributes.append("conforms " + protocols.joined(separator: ", "))
                }
                if !attributes.isEmpty {
                    lines.append("metadata @" + metadata.name + " : " + attributes.joined(separator: ", "))
                }
                if !metadata.vtable.isEmpty {
                    let entries = metadata.vtable.enumerated().map { index, entry in
                        String(index) + ": " + vtableEntryText(entry, module: module)
                    }
                    lines.append("vtable @" + metadata.name + " { " + entries.joined(separator: ", ") + " }")
                }
            }
            return lines
        }

        private func vtableEntryText(_ entry: TIR.VTableEntry, module: TIR.Module) -> String {
            let functionName = module.registry.functions[entry.function].map { "@" + $0.name } ?? "@<?>"
            return entry.name + signatureText(entry.signature) + " " + functionName
        }

        private func signatureText(_ typeId: Id.TIRTypeId) -> String {
            guard let ty = registry?.types[typeId] else {
                return "(" + typeText(typeId) + ")"
            }
            switch ty {
            case let functionType as TIRType.FunctionType:
                return signatureText(
                    parameters: functionType.parameters,
                    returnType: functionType.returnType,
                    isVariadic: functionType.isVariadic
                )
            case let closureType as TIRType.ClosureType:
                return signatureText(
                    parameters: closureType.parameters,
                    returnType: closureType.returnType,
                    isVariadic: closureType.isVariadic
                )
            default:
                return "(" + typeText(typeId) + ")"
            }
        }

        private func signatureText(
            parameters: [Id.TIRTypeId], returnType: Id.TIRTypeId, isVariadic: Bool
        ) -> String {
            var parts = parameters.map { typeText($0) }
            if isVariadic {
                parts.append("...")
            }
            return "(" + parts.joined(separator: ",") + ")->" + typeText(returnType)
        }

        private func globalText(_ global: TIR.GlobalVariable) -> String {
            var text = (global.isExtern ? "extern " : "") + "global @" + global.name
            text += " : " + typeText(global.type)
            if let initializer = global.initializer {
                text += " init " + (registry?.functions[initializer].map { "@" + $0.name } ?? "@<?>")
            }
            return text
        }

        private func nominalBody(_ type: TIRType.NominalType) -> String {
            switch type {
            case let structType as TIRType.StructType:
                return "struct " + braced(fieldsText(structType.fields))
            case let classType as TIRType.ClassType:
                return "class " + braced(fieldsText(classType.fields))
            case let enumType as TIRType.EnumType:
                let cases = enumType.cases.map { caseInfo in
                    let payload = caseInfo.associatedTypes.map { typeText($0) }.joined(separator: ",")
                    return "." + caseInfo.name + (payload.isEmpty ? "" : "(" + payload + ")")
                }
                return "enum " + braced(cases.joined(separator: ", "))
            default:
                return "nominal {}"
            }
        }

        private func braced(_ body: String) -> String {
            body.isEmpty ? "{}" : "{ " + body + " }"
        }

        private func fieldsText(_ fields: [(name: String, type: Id.TIRTypeId)]) -> String {
            fields.map { $0.name + ": " + typeText($0.type) }.joined(separator: ", ")
        }

        private func typeText(_ typeId: Id.TIRTypeId) -> String {
            guard let type = registry?.types[typeId] else {
                return "<?type " + String(typeId.id) + ">"
            }
            switch type {
            case _ as TIRType.VoidType:
                return "void"
            case let primitive as TIRType.PrimitiveType:
                switch primitive.kind {
                case .Signed:
                    return "i" + String(primitive.bitWidth)
                case .Unsigned:
                    return "u" + String(primitive.bitWidth)
                case .Float:
                    return "f" + String(primitive.bitWidth)
                case .Bool:
                    return "bool"
                case .Char:
                    return "char"
                }
            case let pointer as TIRType.PointerType:
                return "*" + pointeeText(pointer.pointee)
            case let address as TIRType.AddressType:
                return "addr " + pointeeText(address.pointee)
            case _ as TIRType.MetadataType:
                return "meta"
            case let nominal as TIRType.NominalType:
                return nominalKeyword(nominal) + " " + nominal.displayText
            case let tuple as TIRType.TupleType:
                let elements = tuple.elements.map { element in
                    (element.label.map { $0 + ": " } ?? "") + typeText(element.type)
                }
                return "(" + elements.joined(separator: ",") + ")"
            case let function as TIRType.FunctionType:
                var parameters = function.parameters.map { typeText($0) }
                if function.isVariadic {
                    parameters.append("...")
                }
                return "fn(" + parameters.joined(separator: ",") + ")->" + typeText(function.returnType)
            case let closure as TIRType.ClosureType:
                var parameters = closure.parameters.map { typeText($0) }
                if closure.isVariadic {
                    parameters.append("...")
                }
                return "closure(" + parameters.joined(separator: ",") + ")->" + typeText(closure.returnType)
            case let existential as TIRType.ExistentialType:
                return "any " + existential.name
            default:
                return "<?type " + String(typeId.id) + ">"
            }
        }

        private func pointeeText(_ pointee: Id.TIRTypeId) -> String {
            if let nominal = registry?.types[pointee] as? TIRType.NominalType {
                return nominal.displayText
            }
            return typeText(pointee)
        }

        private func nominalKeyword(_ type: TIRType.NominalType) -> String {
            switch type {
            case _ as TIRType.StructType:
                "struct"
            case _ as TIRType.ClassType:
                "class"
            case _ as TIRType.EnumType:
                "enum"
            default:
                "nominal"
            }
        }

        private func metadataName(_ id: Id.TIRMetadataId) -> String {
            registry?.metadatas[id]?.name ?? "#" + String(id.id)
        }

        private func protocolName(_ id: Id.TIRProtocolId) -> String {
            registry?.protocols[id]?.name ?? "#" + String(id.id)
        }

        private func witnessText(_ id: Id.TIRWitnessId) -> String {
            guard let witness = registry?.witnesses[id] else {
                return "<witness #" + String(id.id) + ">"
            }
            let concrete = (registry?.types[witness.concreteType] as? TIRType.NominalType)?.displayText
                ?? typeText(witness.concreteType)
            return "%" + concrete + ":" + protocolName(witness.protocolId) + "#" + String(id.id)
        }

        private func enumCaseRef(_ ty: Id.TIRTypeId, _ tag: Int) -> String {
            guard let type = registry?.types[ty] as? TIRType.EnumType,
                  tag >= 0, tag < type.cases.count
            else {
                return "#" + String(tag)
            }
            return "." + type.cases[tag].name
        }

        private func fieldText(_ base: Value, _ index: Int) -> String {
            let pointee: Id.TIRTypeId? = switch registry?.types[base.ty] {
            case let pointer as TIRType.PointerType:
                pointer.pointee
            case let address as TIRType.AddressType:
                address.pointee
            default:
                nil
            }
            guard let pointee, let nominal = registry?.types[pointee]
            else {
                return "#" + String(index)
            }
            let name: String? = if let structType = nominal as? TIRType.StructType {
                structType.fields.indices.contains(index) ? structType.fields[index].name : nil
            } else if let classType = nominal as? TIRType.ClassType {
                classType.fields.indices.contains(index) ? classType.fields[index].name : nil
            } else {
                nil
            }
            guard let name else {
                return "#" + String(index)
            }
            return "#" + String(index) + " " + name
        }

        private func definition(_ result: Value, _ body: String) -> String {
            "%" + result.name + " = " + body + " : " + typeText(result.ty)
        }

        private func blockRef(_ block: BasicBlock, _ arguments: [Value]) -> String {
            var text = "^" + block.name
            if !arguments.isEmpty {
                text += "(" + arguments.map { valueText($0) }.joined(separator: ", ") + ")"
            }
            return text
        }

        private func calleeReturnTypeText(_ callee: Value) -> String {
            guard let ty = registry?.types[callee.ty] else {
                return "void"
            }
            switch ty {
            case let functionType as TIRType.FunctionType:
                return typeText(functionType.returnType)
            case let closureType as TIRType.ClosureType:
                return typeText(closureType.returnType)
            default:
                return "void"
            }
        }

        private func quoted(_ text: String) -> String {
            var result = "\""
            for character in text {
                switch character {
                case "\\": result += "\\\\"
                case "\"": result += "\\\""
                case "\n": result += "\\n"
                case "\r": result += "\\r"
                case "\t": result += "\\t"
                default: result.append(character)
                }
            }
            return result + "\""
        }

        private func charQuoted(_ character: Character) -> String {
            switch character {
            case "\\": "'\\\\'"
            case "'": "'\\''"
            default: "'" + String(character) + "'"
            }
        }

        private func valueText(_ value: Value) -> String {
            switch value {
            case let literal as IntegerLiteral:
                String(literal.value)
            case let literal as FloatLiteral:
                String(literal.value)
            case let literal as CharLiteral:
                charQuoted(literal.value)
            case let literal as BoolLiteral:
                literal.value ? "true" : "false"
            case let literal as StringLiteral:
                quoted(literal.value)
            case _ as NullptrLiteral:
                "null"
            case _ as VoidLiteral:
                "void"
            case let function as FunctionRef:
                registry?.functions[function.functionId].map { "@" + $0.name } ?? "@<?>"
            case let globalAddr as GlobalAddr:
                registry?.globals[globalAddr.globalId].map { "@" + $0.name } ?? "@<?>"
            default:
                value.name.isEmpty ? "%<?>" : "%" + value.name
            }
        }

        private func instructionText(_ instruction: Instruction) -> String {
            switch instruction {
            case let ret as Return:
                return ret.value.map { "ret " + valueText($0) } ?? "ret"
            case let branch as Branch:
                return "br " + blockRef(branch.target, branch.arguments)
            case let cond as ConditionalBranch:
                return "condbr " + valueText(cond.condition)
                    + " ? " + blockRef(cond.trueBranch, cond.trueArguments)
                    + " : " + blockRef(cond.falseBranch, cond.falseArguments)
            case _ as Unreachable:
                return "halt"
            case let phi as Phi:
                let incomings = phi.incomings.map { "^" + $0.block.name + ": " + valueText($0.value) }
                return definition(phi.result, "phi { " + incomings.joined(separator: ", ") + " }")
            case let switchEnum as SwitchEnum:
                var entries = switchEnum.cases.map { caseInfo in
                    enumCaseRef(switchEnum.value.ty, caseInfo.tag) + ": "
                        + blockRef(caseInfo.block, caseInfo.arguments)
                }
                if let defaultBlock = switchEnum.defaultBlock {
                    entries.append("default: " + blockRef(defaultBlock, []))
                }
                return "switch " + valueText(switchEnum.value) + " { " + entries.joined(separator: ", ") + " }"
            case let extract as ExtractPayload:
                return definition(
                    extract.result,
                    "extractpayload " + valueText(extract.value) + ", " +
                        enumCaseRef(extract.value.ty, extract.caseIndex)
                )
            case let arith as UnaryArith:
                return definition(arith.result, arith.op.rawValue + " " + valueText(arith.operand))
            case let arith as BinaryArith:
                return definition(
                    arith.result,
                    arith.op.rawValue + " " + valueText(arith.lhs) + ", " + valueText(arith.rhs)
                )
            case let alloc as AllocStack:
                return definition(alloc.result, "allocstack " + typeText(alloc.allocatedType))
            case let dealloc as DeallocStack:
                return "deallocstack " + valueText(dealloc.value)
            case let alloc as AllocHeap:
                return definition(alloc.result, "allocheap " + typeText(alloc.allocatedType))
            case let dealloc as DeallocHeap:
                return "deallocheap " + valueText(dealloc.value)
            case let alloc as AllocCell:
                return definition(alloc.result, "alloccell " + typeText(alloc.allocatedType))
            case let dealloc as DeallocCell:
                return "dealloccell " + valueText(dealloc.value)
            case let load as Load:
                return definition(load.result, "load " + valueText(load.ptr))
            case let store as Store:
                return "store " + valueText(store.value) + " -> " + valueText(store.ptr)
            case let sizeOf as SizeOf:
                return definition(sizeOf.result, "sizeof " + typeText(sizeOf.sizedType))
            case let structAddr as StructElementAddr:
                return definition(
                    structAddr.result,
                    "structelementaddr " + valueText(structAddr.base) + ", "
                        + fieldText(structAddr.base, structAddr.index)
                )
            case let tupleAddr as TupleElementAddr:
                return definition(
                    tupleAddr.result,
                    "tupleelementaddr " + valueText(tupleAddr.base) + ", #" + String(tupleAddr.index)
                )
            case let classAddr as ClassElementAddr:
                return definition(
                    classAddr.result,
                    "classelementaddr " + valueText(classAddr.base) + ", "
                        + fieldText(classAddr.base, classAddr.index)
                )
            case let project as ProjectCell:
                return definition(project.result, "projectcell " + valueText(project.cell))
            case let conversion as AddressToPointer:
                return definition(conversion.result, "addrtoptr " + valueText(conversion.address))
            case let conversion as PointerToAddress:
                return definition(conversion.result, "ptrtoaddr " + valueText(conversion.pointer))
            case let structValue as StructValue:
                return definition(
                    structValue.result,
                    "structvalue (" + structValue.fields.map { valueText($0) }.joined(separator: ", ") + ")"
                )
            case let tupleValue as TupleValue:
                return definition(
                    tupleValue.result,
                    "tuplevalue (" + tupleValue.elements.map { valueText($0) }.joined(separator: ", ") + ")"
                )
            case let enumValue as EnumValue:
                var body = "enumvalue " + enumCaseRef(enumValue.result.ty, enumValue.caseIndex)
                if let payload = enumValue.payload {
                    body += "(" + valueText(payload) + ")"
                }
                return definition(enumValue.result, body)
            case let call as Call:
                let body = "call " + valueText(call.callee) + "("
                    + call.arguments.map { valueText($0) }.joined(separator: ", ") + ")"
                if let result = call.result {
                    return definition(result, body)
                }
                return body + " : " + calleeReturnTypeText(call.callee)
            case let tryCall as TryCall:
                var body = "trycall " + valueText(tryCall.callee) + "("
                    + tryCall.arguments.map { valueText($0) }.joined(separator: ", ") + ")"
                body += " -> " + blockRef(tryCall.successBlock, [])
                body += ", error " + blockRef(tryCall.errorBlock, [])
                if let errorCell = tryCall.errorCell {
                    body += ", cell " + valueText(errorCell)
                }
                if let result = tryCall.result {
                    return definition(result, body)
                }
                return body + " : " + calleeReturnTypeText(tryCall.callee)
            case let closure as Closure:
                return definition(
                    closure.result,
                    "closure " + valueText(closure.function) + "("
                        + closure.captures.map { valueText($0) }.joined(separator: ", ") + ")"
                )
            case let upcast as Upcast:
                return definition(upcast.result, "upcast " + valueText(upcast.value))
            case let cast as UncheckedRefCast:
                return definition(cast.result, "uncheckedrefcast " + valueText(cast.value))
            case let numericCast as NumericCast:
                return definition(
                    numericCast.result,
                    "numericcast " + numericCast.op.rawValue + " " + valueText(numericCast.value)
                )
            case let bitCast as BitCast:
                return definition(bitCast.result, "bitcast " + valueText(bitCast.value))
            case let typeMetadata as TypeMetadata:
                return definition(typeMetadata.result, "typemetadata " + valueText(typeMetadata.value))
            case let typeMetadataConstant as TypeMetadataConstant:
                return definition(
                    typeMetadataConstant.result,
                    "typemetadataconstant " + typeText(typeMetadataConstant.type)
                        + " @" + metadataName(typeMetadataConstant.metadata)
                )
            case let isInstance as IsInstance:
                return definition(
                    isInstance.result,
                    "isinstance " + valueText(isInstance.metadata) + ", " + valueText(isInstance.target)
                )
            case let superclass as Superclass:
                return definition(superclass.result, "superclass " + valueText(superclass.metadata))
            case let trap as Trap:
                return trap.message.map { "trap " + quoted($0) } ?? "trap"
            case let retain as Retain:
                return "retain " + valueText(retain.value)
            case let release as Release:
                return "release " + valueText(release.value)
            case let copy as Copy:
                return definition(copy.result, "copy " + valueText(copy.value))
            case let destroy as Destroy:
                return "destroy " + valueText(destroy.value)
            case let asm as InlineAsm:
                var text = "asm " + quoted(asm.template) + ", " + quoted(asm.constraints.joined(separator: ","))
                text += "(" + asm.operands.map { valueText($0) }.joined(separator: ", ") + ")"
                if !asm.options.isEmpty {
                    text += " options " + asm.options.joined(separator: ", ")
                }
                return text
            case let build as BuildExistential:
                let witnesses = build.witnesses.map { witnessText($0) }.joined(separator: ", ")
                return definition(
                    build.result,
                    "buildexistential " + valueText(build.value) + ", witnesses [" + witnesses + "]"
                )
            case let open as OpenExistential:
                return definition(open.result, "openexistential " + valueText(open.container))
            case let witnessMethod as WitnessMethod:
                return definition(
                    witnessMethod.result,
                    "witnessmethod " + witnessText(witnessMethod.witness) + "." + String(witnessMethod.index)
                )
            case let opaqueWitness as OpaqueWitnessMethod:
                return definition(
                    opaqueWitness.result,
                    "opaquewitnessmethod " + valueText(opaqueWitness.container) + " %"
                        + protocolName(opaqueWitness.protocolId) + "#" + String(opaqueWitness.protocolId.id)
                        + "." + String(opaqueWitness.index)
                )
            case let virtualMethod as VirtualMethod:
                return definition(
                    virtualMethod.result,
                    "virtualmethod @" + metadataName(virtualMethod.metadata) + "#"
                        + String(virtualMethod.metadata.id) + "." + String(virtualMethod.index)
                        + "(" + valueText(virtualMethod.selfValue) + ")"
                )
            case let existentialCopy as ExistentialCopy:
                return definition(existentialCopy.result, "existentialcopy " + valueText(existentialCopy.container))
            case let existentialDestroy as ExistentialDestroy:
                return "existentialdestroy " + valueText(existentialDestroy.container)
            default:
                fatalError("unhandled TIR instruction in dumper: \(type(of: instruction))")
            }
        }
    }
}
