import Foundation
import Testing

@testable import MiniSwiftCompilerCore

@Test func runtimeLessExecutorCollectsMultiplePrintOutputs() {
  let source = """
  print("Hello")
  print("Swift")
  """
  let output = MiniCompilerRuntimeLessExecutor.run(source: source)
  #expect(output == "Hello\nSwift")
}

@Test func appServiceCompilesAndProducesRuntimeLessOutput() throws {
  installEmbeddedPipelineCallbacksForTests()
  let result = try MiniCompilerAppService().compileAndRunRuntimeLess(
    source: "print(\"Hello from app service\")",
    moduleName: "AppService"
  )

  #expect(result.llvmIR.contains("define"))
  #expect(result.executionOutput == "Hello from app service")
}
