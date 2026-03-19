import Foundation
import Testing

@testable import MiniSwiftCompilerCore

@Test func helloWorldDemoExecutorExtractsPrintedString() {
  let output = EmbeddedCompilerDemoExecutor.runHelloWorldDemo(source: "print(\"Hello, world!\")")
  #expect(output == "Hello, world!")
}

@Test func helloWorldDemoCompilesAndProducesExecutionOutput() throws {
  installEmbeddedPipelineCallbacksForTests()
  let result = try EmbeddedCompilerDemoIDE().compileAndRunHelloWorldDemo(
    source: "print(\"Hello from demo\")",
    moduleName: "DemoIDE"
  )

  #expect(result.llvmIR.contains("define"))
  #expect(result.executionOutput == "Hello from demo")
}
