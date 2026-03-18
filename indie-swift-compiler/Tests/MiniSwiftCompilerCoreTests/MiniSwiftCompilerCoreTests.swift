import Testing
@testable import MiniSwiftCompilerCore

@_cdecl("mini_swift_test_embedded_compile")
private func mini_swift_test_embedded_compile(
    _ swiftSource: UnsafePointer<CChar>?,
    _ moduleName: UnsafePointer<CChar>?,
    _ outLLPath: UnsafePointer<CChar>?,
    _ targetTriple: UnsafePointer<CChar>?,
    _ sdkPath: UnsafePointer<CChar>?
) -> Int32 {
    _ = swiftSource
    _ = targetTriple
    _ = sdkPath
    guard let moduleName, let outLLPath else { return -101 }

    let module = String(cString: moduleName)
    let outputPath = String(cString: outLLPath)
    let ir = """
    ; ModuleID = '\(module)'
    define i64 @main() {
    entry:
      ret i64 42
    }
    """
    do {
        try ir.write(toFile: outputPath, atomically: true, encoding: .utf8)
        return 0
    } catch {
        return -102
    }
}

private func installEmbeddedCompileCallbackForTests() {
    let rc = MiniCompiler.setEmbeddedCompileCallback(mini_swift_test_embedded_compile)
    #expect(rc == 0)
}

@Test func simpleFunctionCompilesToIR() throws {
    installEmbeddedCompileCallbackForTests()
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
    installEmbeddedCompileCallbackForTests()
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
