import Foundation

public struct MiniCompilerAppExecutionResult: Sendable, Equatable {
  public let llvmIR: String
  public let diagnostics: [String]
  public let executionOutput: String

  public init(llvmIR: String, diagnostics: [String], executionOutput: String) {
    self.llvmIR = llvmIR
    self.diagnostics = diagnostics
    self.executionOutput = executionOutput
  }
}

public enum MiniCompilerRuntimeLessExecutor {
  public static func run(source: String) -> String {
    let outputs = printedStrings(in: source)
    if outputs.isEmpty {
      return "No runtime-less output (print literal) was derived from the source."
    }
    return outputs.joined(separator: "\n")
  }

  private static func printedStrings(in source: String) -> [String] {
    let pattern = #"print\("((?:\\.|[^"\\])*)"\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

    let nsSource = source as NSString
    let matches = regex.matches(
      in: source,
      range: NSRange(location: 0, length: nsSource.length)
    )

    return matches.compactMap { match in
      guard match.numberOfRanges > 1 else { return nil }
      let range = match.range(at: 1)
      guard range.location != NSNotFound else { return nil }
      let raw = nsSource.substring(with: range)
      return raw
        .replacingOccurrences(of: #"\n"#, with: "\n")
        .replacingOccurrences(of: #"\t"#, with: "\t")
        .replacingOccurrences(of: #"\""#, with: "\"")
        .replacingOccurrences(of: #"\\"#, with: #"\"#)
    }
  }
}

public struct MiniCompilerAppService {
  public let adapter: MiniCompilerIOSAdapter

  public init(adapter: MiniCompilerIOSAdapter = MiniCompilerIOSAdapter()) {
    self.adapter = adapter
  }

  public func compileAndRunRuntimeLess(
    source: String,
    moduleName: String = "EmbeddedCompilerApp"
  ) throws -> MiniCompilerAppExecutionResult {
    let compileOutput = try adapter.compile(
      MiniCompilerCompileRequest(source: source, moduleName: moduleName)
    )

    return MiniCompilerAppExecutionResult(
      llvmIR: compileOutput.llvmIR,
      diagnostics: compileOutput.diagnostics,
      executionOutput: MiniCompilerRuntimeLessExecutor.run(source: source)
    )
  }
}
