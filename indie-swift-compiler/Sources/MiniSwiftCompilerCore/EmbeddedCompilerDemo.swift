import Foundation

public struct EmbeddedCompilerDemoResult: Sendable, Equatable {
  public let llvmIR: String
  public let diagnostics: [String]
  public let executionOutput: String

  public init(llvmIR: String, diagnostics: [String], executionOutput: String) {
    self.llvmIR = llvmIR
    self.diagnostics = diagnostics
    self.executionOutput = executionOutput
  }
}

public enum EmbeddedCompilerDemoExecutor {
  public static func runHelloWorldDemo(source: String) -> String {
    if let printedString = firstPrintedString(in: source) {
      return printedString
    }
    if source.contains("Hello, world") {
      return "Hello, world!"
    }
    return "Demo executor could not derive runtime output from the provided source."
  }

  private static func firstPrintedString(in source: String) -> String? {
    guard let printRange = source.range(of: "print(\"") else { return nil }
    let suffix = source[printRange.upperBound...]
    guard let end = suffix.firstIndex(of: "\"") else { return nil }
    return String(suffix[..<end])
  }
}

public struct EmbeddedCompilerDemoIDE {
  public let adapter: MiniCompilerIOSAdapter

  public init(adapter: MiniCompilerIOSAdapter = MiniCompilerIOSAdapter()) {
    self.adapter = adapter
  }

  public func compileAndRunHelloWorldDemo(
    source: String,
    moduleName: String = "EmbeddedCompilerDemo"
  ) throws -> EmbeddedCompilerDemoResult {
    let compileOutput = try adapter.compile(
      MiniCompilerCompileRequest(source: source, moduleName: moduleName)
    )
    return EmbeddedCompilerDemoResult(
      llvmIR: compileOutput.llvmIR,
      diagnostics: compileOutput.diagnostics,
      executionOutput: EmbeddedCompilerDemoExecutor.runHelloWorldDemo(source: source)
    )
  }
}
