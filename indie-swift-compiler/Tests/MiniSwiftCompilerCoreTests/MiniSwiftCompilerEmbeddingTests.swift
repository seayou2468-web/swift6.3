import Foundation
import Testing

@testable import MiniSwiftCompilerCore

@Suite(.serialized)
struct EmbeddedPipelineEmbeddingTests {}

@Test func embeddedRuntimeEnvironmentConfigurationPopulatesVariables() {
  var environment: [String: String] = [:]
  let layout = MiniCompilerToolchainLayout(
    llvmXCFrameworkName: "LLVM.xcframework",
    clangXCFrameworkName: "Clang.xcframework",
    swiftResourceDirectory: "/tmp/swift-resources",
    swiftSDKPath: "/tmp/swift-sdk",
    swiftTargetTriple: "arm64-apple-ios15.0"
  )

  MiniCompilerEmbeddedRuntime.configureProcessEnvironment(for: layout, environment: &environment)

  #expect(environment["SWIFT_RESOURCE_DIR"] == "/tmp/swift-resources")
  #expect(environment["SWIFT_SDK_PATH"] == "/tmp/swift-sdk")
  #expect(environment["SWIFT_TARGET_TRIPLE"] == "arm64-apple-ios15.0")
}

@Test func iosAdapterUsesEmbeddedPipelineAndToolchainLayout() throws {
  let adapter = MiniCompilerIOSAdapter(
    toolchainLayout: MiniCompilerToolchainLayout(
      swiftResourceDirectory: "/tmp/swift-resources",
      swiftSDKPath: "/tmp/swift-sdk",
      swiftTargetTriple: "arm64-apple-ios15.0"
    )
  )

  installEmbeddedPipelineCallbacksForTests()
  let output = try adapter.compile(
    MiniCompilerCompileRequest(source: "func main() -> Int { 42 }", moduleName: "IOSDemo")
  )

  #expect(output.llvmIR.contains("define"))
  #expect(recordedStages(for: "IOSDemo").contains("irgen"))
}
