import Foundation

public struct EmbeddedCompilerAppRequest: Sendable, Equatable {
  public let source: String
  public let moduleName: String

  public init(source: String, moduleName: String = "EmbeddedAppModule") {
    self.source = source
    self.moduleName = moduleName
  }
}

public struct EmbeddedCompilerAppResult: Sendable, Equatable {
  public let moduleName: String
  public let llvmIR: String
  public let diagnostics: [String]
  public let executionOutput: String

  public init(moduleName: String, llvmIR: String, diagnostics: [String], executionOutput: String) {
    self.moduleName = moduleName
    self.llvmIR = llvmIR
    self.diagnostics = diagnostics
    self.executionOutput = executionOutput
  }
}

public enum EmbeddedCompilerAppRuntimeError: Error, CustomStringConvertible {
  case missingExecutionHandler

  public var description: String {
    switch self {
    case .missingExecutionHandler:
      "No application execution handler has been configured for the embedded compiler runtime."
    }
  }
}

public final class EmbeddedCompilerAppRuntime {
  public typealias ExecutionHandler =
    @Sendable (EmbeddedCompilerAppRequest, CompileOutput) throws -> String

  nonisolated(unsafe) private static var executionHandler: ExecutionHandler?

  public static func setExecutionHandler(_ handler: ExecutionHandler?) {
    executionHandler = handler
  }

  public let adapter: MiniCompilerIOSAdapter

  public init(adapter: MiniCompilerIOSAdapter = MiniCompilerIOSAdapter()) {
    self.adapter = adapter
  }

  public func compile(_ request: EmbeddedCompilerAppRequest) throws -> CompileOutput {
    try adapter.compile(
      MiniCompilerCompileRequest(source: request.source, moduleName: request.moduleName))
  }

  public func compileAndExecute(_ request: EmbeddedCompilerAppRequest) throws
    -> EmbeddedCompilerAppResult
  {
    let compileOutput = try compile(request)
    guard let handler = Self.executionHandler else {
      throw EmbeddedCompilerAppRuntimeError.missingExecutionHandler
    }
    let executionOutput = try handler(request, compileOutput)
    return EmbeddedCompilerAppResult(
      moduleName: request.moduleName,
      llvmIR: compileOutput.llvmIR,
      diagnostics: compileOutput.diagnostics,
      executionOutput: executionOutput
    )
  }
}
