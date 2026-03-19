import Foundation

@MainActor
final class EmbeddedCompilerIDEViewModel: ObservableObject {
  @Published var sourceCode: String = """
  print("Hello, world!")
  """
  @Published var llvmIR: String = ""
  @Published var executionOutput: String = ""
  @Published var diagnostics: [String] = []
  @Published var statusMessage: String = "Ready"

  private let appService = MiniCompilerAppService()

  func compileAndRun() {
    do {
      let result = try appService.compileAndRunRuntimeLess(source: sourceCode)
      llvmIR = result.llvmIR
      executionOutput = result.executionOutput
      diagnostics = result.diagnostics
      statusMessage = "Compiled and executed runtime-less source."
    } catch {
      llvmIR = ""
      executionOutput = ""
      diagnostics = [error.localizedDescription]
      statusMessage = "Compilation failed."
    }
  }
}
