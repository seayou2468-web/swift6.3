import Testing
@testable import MiniSwiftCompilerCore

@Test func simpleFunctionCompilesToIR() throws {
    let source = """
    func main() -> Int {
        return 40 + 2
    }
    """

    let output = try MiniCompiler().compileSource(source, moduleName: "Demo")
    #expect(output.llvmIR.contains("define i64 @main()"))
    #expect(output.llvmIR.contains("add i64 40, 2"))
    #expect(output.llvmIR.contains("ret i64 %"))
}

@Test func letBindingCompilesToIR() throws {
    let source = """
    func main() -> Int {
        let x = 40
        return x + 2
    }
    """

    let output = try MiniCompiler().compileSource(source, moduleName: "Demo")
    #expect(output.llvmIR.contains("alloca i64"))
    #expect(output.llvmIR.contains("load i64"))
    #expect(output.llvmIR.contains("add i64"))
}
