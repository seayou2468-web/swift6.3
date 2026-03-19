import Foundation
import MiniSwiftCompilerCore

@MainActor
final class EmbeddedCompilerIDEViewModel: ObservableObject {
  @Published var sourceCode: String = """
  let greeting = "Hello, Swift!"
  print(greeting)
  print(40 + 2)
  """
  @Published var llvmIR: String = ""
  @Published var executionOutput: String = ""
  @Published var diagnostics: [String] = []
  @Published var statusMessage: String = "Ready"

  private let runtime = EmbeddedCompilerAppRuntime()

  init() {
    RuntimeFreeExecutionBackend.install()
  }

  func compileAndRun() {
    do {
      let result = try runtime.compileAndExecute(
        EmbeddedCompilerAppRequest(source: sourceCode, moduleName: "EmbeddedCompilerIDE")
      )
      llvmIR = result.llvmIR
      executionOutput = result.executionOutput
      diagnostics = result.diagnostics
      statusMessage = "Compiled and executed application source."
    } catch {
      llvmIR = ""
      executionOutput = ""
      diagnostics = [error.localizedDescription]
      statusMessage = "Compilation failed."
    }
  }
}
