import Foundation
import Testing

@testable import MiniSwiftCompilerCore

@Suite(.serialized)
struct EmbeddedCompilerAppRuntimeTestsSuite {}

@Test func appRuntimeRequiresExecutionHandler() throws {
  EmbeddedCompilerAppRuntime.setExecutionHandler(nil)
  installEmbeddedPipelineCallbacksForTests()

  #expect(throws: EmbeddedCompilerAppRuntimeError.self) {
    try EmbeddedCompilerAppRuntime().compileAndExecute(
      EmbeddedCompilerAppRequest(source: "print(\"hello\")", moduleName: "NoHandler")
    )
  }
}

@Test func appRuntimeCompilesAndExecutesThroughRegisteredHandler() throws {
  installEmbeddedPipelineCallbacksForTests()
  EmbeddedCompilerAppRuntime.setExecutionHandler { request, _ in
    request.source.contains("print") ? "executed" : "no-op"
  }

  let result = try EmbeddedCompilerAppRuntime().compileAndExecute(
    EmbeddedCompilerAppRequest(source: "print(\"hello\")", moduleName: "AppRuntime")
  )

  #expect(result.llvmIR.contains("define"))
  #expect(result.executionOutput == "executed")
}
