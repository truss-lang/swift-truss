import Testing
import TrussCore

private func installedBuiltin() -> Symbol.PackageSymbol {
    let context = Context()
    return Builtin.install(context: context)
}

@Test func builtinInstallsArithFunctions() {
    let package = installedBuiltin()
    for name in ["builtin_add_int32", "builtin_sub_uint64", "builtin_div_float32", "builtin_neg_int8"] {
        let symbols = package.scope.values[name] ?? []
        #expect(symbols.count == 1)
        let function = symbols.first as? Symbol.FunctionSymbol
        #expect(function != nil)
        #expect(function?.isBuiltin == true)
    }
}

@Test func builtinArithFunctionSignature() {
    let package = installedBuiltin()
    let add = (package.scope.values["builtin_add_int32"] ?? []).first as? Symbol.FunctionSymbol
    let functionType = add?.functionType
    #expect(functionType?.parameters.count == 2)
    #expect((functionType?.parameters[0].type as? TrussType.BuiltinType)?.name == "Int32")
    #expect((functionType?.parameters[1].type as? TrussType.BuiltinType)?.name == "Int32")
    #expect((functionType?.returnType as? TrussType.BuiltinType)?.name == "Int32")
}

@Test func builtinNegFunctionIsUnary() {
    let package = installedBuiltin()
    let neg = (package.scope.values["builtin_neg_float64"] ?? []).first as? Symbol.FunctionSymbol
    let functionType = neg?.functionType
    #expect(functionType?.parameters.count == 1)
    #expect((functionType?.returnType as? TrussType.BuiltinType)?.name == "Float64")
}

@Test func builtinFunctionInfoParsesNames() {
    #expect(Builtin.builtinFunctionInfo(named: "builtin_add_int32")?.opName == "add")
    #expect(Builtin.builtinFunctionInfo(named: "builtin_add_int32")?.typeName == "int32")
    #expect(Builtin.builtinFunctionInfo(named: "builtin_neg_float32")?.opName == "neg")
    #expect(Builtin.builtinFunctionInfo(named: "builtin_neg_float32")?.typeName == "float32")
    #expect(Builtin.builtinFunctionInfo(named: "ordinaryFunction") == nil)
    #expect(Builtin.builtinFunctionInfo(named: "builtin_shift_int32") == nil)
}

@Test func builtinCompareFunctionsRegisterWithBoolReturn() {
    let package = installedBuiltin()
    for name in ["builtin_eq_int32", "builtin_ne_float64", "builtin_lt_uint64", "builtin_ge_int8"] {
        let function = (package.scope.values[name] ?? []).first as? Symbol.FunctionSymbol
        #expect(function?.isBuiltin == true)
        #expect((function?.functionType?.returnType as? TrussType.BuiltinType)?.name == "Bool")
        #expect(function?.functionType?.parameters.count == 2)
    }
}

@Test func builtinCompareTypeFiltering() {
    let package = installedBuiltin()
    #expect((package.scope.values["builtin_eq_bool"] ?? []).first != nil)
    #expect((package.scope.values["builtin_ne_char"] ?? []).first != nil)
    #expect(package.scope.values["builtin_lt_bool"] == nil)
    #expect(package.scope.values["builtin_ge_char"] == nil)
}

@Test func builtinNotAndBitnotRegister() {
    let package = installedBuiltin()
    let not = (package.scope.values["builtin_not_bool"] ?? []).first as? Symbol.FunctionSymbol
    #expect(not?.isBuiltin == true)
    #expect(not?.functionType?.parameters.count == 1)
    #expect((not?.functionType?.parameters[0].type as? TrussType.BuiltinType)?.name == "Bool")
    let bitnot = (package.scope.values["builtin_bitnot_int32"] ?? []).first as? Symbol.FunctionSymbol
    #expect(bitnot?.isBuiltin == true)
    #expect(bitnot?.functionType?.parameters.count == 1)
    #expect((bitnot?.functionType?.returnType as? TrussType.BuiltinType)?.name == "Int32")
    #expect(package.scope.values["builtin_not_int32"] == nil)
    #expect(package.scope.values["builtin_bitnot_float32"] == nil)
}

@Test func builtinFunctionInfoParsesNewOps() {
    #expect(Builtin.builtinFunctionInfo(named: "builtin_eq_int32")?.opName == "eq")
    #expect(Builtin.builtinFunctionInfo(named: "builtin_lt_float64")?.opName == "lt")
    #expect(Builtin.builtinFunctionInfo(named: "builtin_not_bool")?.opName == "not")
    #expect(Builtin.builtinFunctionInfo(named: "builtin_bitnot_uint8")?.opName == "bitnot")
}
