import Testing
@testable import MiniSwiftCompilerCore

@Test func simpleFunctionCompilesToIR() throws {
    let source = """
    func main() -> Int {
        return 40 + 2
    }
    """

    let output = try MiniCompiler().compileSource(source, moduleName: "Demo")
    #expect(output.llvmIR.contains("define"))
    #expect(output.llvmIR.contains("main"))
    #expect(output.llvmIR.contains("ret"))
}

@Test func letBindingCompilesToIR() throws {
    let source = """
    func main() -> Int {
        let x = 40
        return x + 2
    }
    """

    let output = try MiniCompiler().compileSource(source, moduleName: "Demo")
    #expect(output.llvmIR.contains("define"))
    #expect(output.llvmIR.contains("Demo"))
    #expect(output.llvmIR.contains("ret"))
}
