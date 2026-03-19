import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public typealias EmbeddedCompileCallback =
  @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
  ) -> Int32
public typealias EmbeddedSILEmitCallback =
  @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
  ) -> Int32
public typealias EmbeddedSILMandatoryOptimizeCallback =
  @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
  ) -> Int32
public typealias EmbeddedSILPerformanceOptimizeCallback =
  @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
  ) -> Int32
public typealias EmbeddedIRGenFromSILCallback =
  @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
  ) -> Int32

private typealias AdapterSetCompileCallbackFn = @convention(c) (EmbeddedCompileCallback?) -> Int32
private typealias AdapterSetEmitSILCallbackFn = @convention(c) (EmbeddedSILEmitCallback?) -> Int32
private typealias AdapterSetEmitIRFromSILCallbackFn =
  @convention(c) (EmbeddedIRGenFromSILCallback?) -> Int32
private typealias SILMandatoryOptimizerSetCallbackFn =
  @convention(c) (EmbeddedSILMandatoryOptimizeCallback?) -> Int32
private typealias SILPerformanceOptimizerSetCallbackFn =
  @convention(c) (EmbeddedSILPerformanceOptimizeCallback?) -> Int32

public enum MiniCompilerError: Error, CustomStringConvertible {
  case sourceReadFailed(String)
  case unsupportedSyntax(String)
  case missingMain
  case embeddedPipelineNotFound

  public var description: String {
    switch self {
    case .sourceReadFailed(let path):
      "ソースファイルの読み込みに失敗しました: \(path)"
    case .unsupportedSyntax(let message):
      "未対応の構文です: \(message)"
    case .missingMain:
      "main() 相当のトップレベル式が見つかりませんでした"
    case .embeddedPipelineNotFound:
      "embedded parser/ast/sema/silgen/sil/optimizer/irgen 実体が未リンクです"
    }
  }
}

public struct CompileOutput {
  public let llvmIR: String
  public let diagnostics: [String]

  public init(llvmIR: String, diagnostics: [String]) {
    self.llvmIR = llvmIR
    self.diagnostics = diagnostics
  }
}

public struct MiniCompiler {
  public init() {}

  public static func defaultArchitecture() throws -> CompilerArchitecture {
    try CompilerArchitectureLoader.loadDefaultArchitecture()
  }

  public static func hasExpectedEmbeddedPipeline() throws -> Bool {
    try defaultArchitecture().isExpectedEmbeddedOrder
  }

  @discardableResult
  public static func setEmbeddedSILEmitCallback(_ callback: EmbeddedSILEmitCallback?) -> Int32 {
    SwiftFrontendAdapterBridge.runtimeSILEmitCallback = callback
    guard let symbol = dlsym(nil, "swift_irgen_adapter_set_emit_sil_callback") else {
      return callback == nil ? -10 : 0
    }
    let fn = unsafeBitCast(symbol, to: AdapterSetEmitSILCallbackFn.self)
    return fn(callback)
  }

  @discardableResult
  public static func setEmbeddedSILMandatoryOptimizerCallback(
    _ callback: EmbeddedSILMandatoryOptimizeCallback?
  ) -> Int32 {
    SILOptimizerAdapterBridge.runtimeMandatoryOptimizeCallback = callback
    guard let symbol = dlsym(nil, "swift_sil_optimizer_adapter_set_mandatory_callback") else {
      return callback == nil ? -10 : 0
    }
    let fn = unsafeBitCast(symbol, to: SILMandatoryOptimizerSetCallbackFn.self)
    return fn(callback)
  }

  @discardableResult
  public static func setEmbeddedSILPerformanceOptimizerCallback(
    _ callback: EmbeddedSILPerformanceOptimizeCallback?
  ) -> Int32 {
    SILOptimizerAdapterBridge.runtimePerformanceOptimizeCallback = callback
    guard let symbol = dlsym(nil, "swift_sil_optimizer_adapter_set_performance_callback") else {
      return callback == nil ? -10 : 0
    }
    let fn = unsafeBitCast(symbol, to: SILPerformanceOptimizerSetCallbackFn.self)
    return fn(callback)
  }

  @discardableResult
  public static func setEmbeddedIRGenFromSILCallback(_ callback: EmbeddedIRGenFromSILCallback?)
    -> Int32
  {
    IRGenAdapterBridge.runtimeIRGenCallback = callback
    guard let symbol = dlsym(nil, "swift_irgen_adapter_set_emit_ir_from_sil_callback") else {
      return callback == nil ? -10 : 0
    }
    let fn = unsafeBitCast(symbol, to: AdapterSetEmitIRFromSILCallbackFn.self)
    return fn(callback)
  }

  @discardableResult
  public static func setEmbeddedCompileCallback(_ callback: EmbeddedCompileCallback?) -> Int32 {
    SwiftFrontendAdapterBridge.runtimeCallback = callback
    guard let symbol = dlsym(nil, "swift_irgen_adapter_set_compile_callback") else {
      return callback == nil ? -10 : 0
    }
    let fn = unsafeBitCast(symbol, to: AdapterSetCompileCallbackFn.self)
    return fn(callback)
  }

  public enum BackendMode {
    /// 抽出・内蔵した parser/AST/Sema/SILGen/SIL/IRGen パイプラインを利用する。
    case directEmbedded
  }

  public func compileSource(_ source: String, moduleName: String = "Main") throws -> CompileOutput {
    try compileSource(source, moduleName: moduleName, mode: .directEmbedded)
  }

  public func compileSource(
    _ source: String,
    moduleName: String = "Main",
    mode: BackendMode
  ) throws -> CompileOutput {
    switch mode {
    case .directEmbedded:
      return try EmbeddedCompilerPipelineBridge().emitIR(
        source: source,
        moduleName: moduleName
      )
    }
  }

  public func compileSourceUsingEmbeddedPipeline(
    _ source: String,
    moduleName: String = "Main"
  ) throws -> CompileOutput {
    try compileSource(source, moduleName: moduleName, mode: .directEmbedded)
  }

  public func compileSource(_ source: String, moduleName: String = "Main", modeRaw: String) throws
    -> CompileOutput
  {
    _ = modeRaw
    return try compileSource(source, moduleName: moduleName, mode: .directEmbedded)
  }

  public func compileFile(at path: String, moduleName: String = "Main") throws -> CompileOutput {
    try compileFile(at: path, moduleName: moduleName, mode: .directEmbedded)
  }

  public func compileFile(
    at path: String,
    moduleName: String = "Main",
    mode: BackendMode
  ) throws -> CompileOutput {
    guard let data = FileManager.default.contents(atPath: path),
      let source = String(data: data, encoding: .utf8)
    else {
      throw MiniCompilerError.sourceReadFailed(path)
    }

    return try compileSource(source, moduleName: moduleName, mode: mode)
  }
}

private struct EmbeddedCompilerPipelineBridge {
  func emitIR(source: String, moduleName: String) throws -> CompileOutput {
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    if let stagedResult = try emitIRUsingFullPipeline(
      source: source,
      moduleName: moduleName,
      temporaryDirectory: tmpDir
    ) {
      return stagedResult
    }

    guard
      let linkedResult = try SwiftFrontendAdapterBridge().emitIRUsingSingleStageAdapter(
        source: source,
        moduleName: moduleName,
        temporaryDirectory: tmpDir
      )
    else {
      throw MiniCompilerError.embeddedPipelineNotFound
    }
    return linkedResult
  }

  private func emitIRUsingFullPipeline(
    source: String,
    moduleName: String,
    temporaryDirectory: URL
  ) throws -> CompileOutput? {
    let rawSILPath = temporaryDirectory.appendingPathComponent("raw.sil")
    let mandatorySILPath = temporaryDirectory.appendingPathComponent("mandatory.sil")
    let optimizedSILPath = temporaryDirectory.appendingPathComponent("optimized.sil")
    let outputPath = temporaryDirectory.appendingPathComponent("output.ll")

    guard
      try SwiftFrontendAdapterBridge().emitSILUsingLinkedAdapter(
        source: source,
        moduleName: moduleName,
        outputPath: rawSILPath
      )
    else {
      return nil
    }

    guard
      try SILOptimizerAdapterBridge().runMandatoryOptimizerUsingLinkedAdapter(
        inputPath: rawSILPath,
        moduleName: moduleName,
        outputPath: mandatorySILPath
      )
    else {
      return nil
    }

    guard
      try SILOptimizerAdapterBridge().runPerformanceOptimizerUsingLinkedAdapter(
        inputPath: mandatorySILPath,
        moduleName: moduleName,
        outputPath: optimizedSILPath
      )
    else {
      return nil
    }

    guard
      try IRGenAdapterBridge().emitIRUsingLinkedAdapter(
        inputPath: optimizedSILPath,
        moduleName: moduleName,
        outputPath: outputPath
      )
    else {
      return nil
    }

    let ir = try String(contentsOf: outputPath, encoding: .utf8)
    return CompileOutput(llvmIR: ir, diagnostics: [])
  }
}

private struct SwiftFrontendAdapterBridge {
  typealias AdapterCompileEntryFn =
    @convention(c) (
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?
    ) -> Int32
  typealias EmitSILEntryFn =
    @convention(c) (
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?
    ) -> Int32
  nonisolated(unsafe) static var runtimeCallback: EmbeddedCompileCallback?
  nonisolated(unsafe) static var runtimeSILEmitCallback: EmbeddedSILEmitCallback?

  func emitSILUsingLinkedAdapter(
    source: String,
    moduleName: String,
    outputPath: URL
  ) throws -> Bool {
    applyEmbeddedSDKDefaults()
    let rc: Int32
    if let callback = Self.runtimeSILEmitCallback {
      rc = source.withCString { src in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            callback(src, mod, out, nil, nil)
          }
        }
      }
    } else if let entryFn = resolveSILEntryFunction() {
      rc = source.withCString { src in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            entryFn(src, mod, out)
          }
        }
      }
    } else {
      return false
    }

    guard rc == 0 else {
      throw MiniCompilerError.unsupportedSyntax("swift frontend SIL生成失敗: rc=\(rc)")
    }
    return true
  }

  func emitIRUsingSingleStageAdapter(
    source: String,
    moduleName: String,
    temporaryDirectory: URL
  ) throws -> CompileOutput? {
    let outputPath = temporaryDirectory.appendingPathComponent("output.ll")
    applyEmbeddedSDKDefaults()
    let rc: Int32
    if let callback = Self.runtimeCallback {
      rc = source.withCString { src in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            callback(src, mod, out, nil, nil)
          }
        }
      }
    } else if let entryFn = resolveLinkedAdapterEntryFunction() {
      rc = source.withCString { src in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            entryFn(src, mod, out)
          }
        }
      }
    } else {
      return nil
    }

    guard rc == 0 else {
      throw MiniCompilerError.unsupportedSyntax("swift frontend adapter 実行失敗: rc=\(rc)")
    }

    let ir = try String(contentsOf: outputPath, encoding: .utf8)
    return CompileOutput(llvmIR: ir, diagnostics: [])
  }

  private func resolveLinkedAdapterEntryFunction() -> AdapterCompileEntryFn? {
    guard let symbol = dlsym(nil, "swift_irgen_adapter_compile") else {
      return nil
    }
    return unsafeBitCast(symbol, to: AdapterCompileEntryFn.self)
  }

  private func resolveSILEntryFunction() -> EmitSILEntryFn? {
    guard let symbol = dlsym(nil, "swift_irgen_adapter_emit_sil") else {
      return nil
    }
    return unsafeBitCast(symbol, to: EmitSILEntryFn.self)
  }

  func applyEmbeddedSDKDefaults() {
    if let target = ProcessInfo.processInfo.environment["SWIFT_TARGET_TRIPLE"], !target.isEmpty {
      _ = setenv("SWIFT_TARGET_TRIPLE", target, 1)
    }

    if let sdkPath = ProcessInfo.processInfo.environment["SWIFT_SDK_PATH"], !sdkPath.isEmpty {
      _ = setenv("SWIFT_SDK_PATH", sdkPath, 1)
      return
    }

    if let docsSDK = resolveDocumentsSDKPath() {
      _ = setenv("SWIFT_SDK_PATH", docsSDK, 1)
      return
    }
  }

  private func resolveDocumentsSDKPath() -> String? {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      return nil
    }
    let sdk = docs.appendingPathComponent("sdk", isDirectory: true)
    guard FileManager.default.fileExists(atPath: sdk.path) else {
      return nil
    }
    return sdk.path
  }
}

private struct SILOptimizerAdapterBridge {
  typealias MandatoryOptimizeEntryFn =
    @convention(c) (
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?
    ) -> Int32
  typealias PerformanceOptimizeEntryFn =
    @convention(c) (
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?
    ) -> Int32
  nonisolated(unsafe) static var runtimeMandatoryOptimizeCallback:
    EmbeddedSILMandatoryOptimizeCallback?
  nonisolated(unsafe) static var runtimePerformanceOptimizeCallback:
    EmbeddedSILPerformanceOptimizeCallback?

  func runMandatoryOptimizerUsingLinkedAdapter(
    inputPath: URL,
    moduleName: String,
    outputPath: URL
  ) throws -> Bool {
    let rc: Int32
    if let callback = Self.runtimeMandatoryOptimizeCallback {
      rc = inputPath.path.withCString { input in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            callback(input, mod, out)
          }
        }
      }
    } else if let entryFn = resolveMandatoryEntryFunction() {
      rc = inputPath.path.withCString { input in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            entryFn(input, mod, out)
          }
        }
      }
    } else {
      return false
    }

    guard rc == 0 else {
      throw MiniCompilerError.unsupportedSyntax("SIL mandatory optimizer 実行失敗: rc=\(rc)")
    }
    return true
  }

  func runPerformanceOptimizerUsingLinkedAdapter(
    inputPath: URL,
    moduleName: String,
    outputPath: URL
  ) throws -> Bool {
    let rc: Int32
    if let callback = Self.runtimePerformanceOptimizeCallback {
      rc = inputPath.path.withCString { input in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            callback(input, mod, out)
          }
        }
      }
    } else if let entryFn = resolvePerformanceEntryFunction() {
      rc = inputPath.path.withCString { input in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            entryFn(input, mod, out)
          }
        }
      }
    } else {
      return false
    }

    guard rc == 0 else {
      throw MiniCompilerError.unsupportedSyntax("SIL performance optimizer 実行失敗: rc=\(rc)")
    }
    return true
  }

  private func resolveMandatoryEntryFunction() -> MandatoryOptimizeEntryFn? {
    guard let symbol = dlsym(nil, "swift_sil_optimizer_adapter_run_mandatory") else {
      return nil
    }
    return unsafeBitCast(symbol, to: MandatoryOptimizeEntryFn.self)
  }

  private func resolvePerformanceEntryFunction() -> PerformanceOptimizeEntryFn? {
    guard let symbol = dlsym(nil, "swift_sil_optimizer_adapter_run_performance") else {
      return nil
    }
    return unsafeBitCast(symbol, to: PerformanceOptimizeEntryFn.self)
  }
}

private struct IRGenAdapterBridge {
  typealias EmitIRFromSILEntryFn =
    @convention(c) (
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?,
      UnsafePointer<CChar>?
    ) -> Int32
  nonisolated(unsafe) static var runtimeIRGenCallback: EmbeddedIRGenFromSILCallback?

  func emitIRUsingLinkedAdapter(
    inputPath: URL,
    moduleName: String,
    outputPath: URL
  ) throws -> Bool {
    let rc: Int32
    if let callback = Self.runtimeIRGenCallback {
      rc = inputPath.path.withCString { input in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            callback(input, mod, out, nil, nil)
          }
        }
      }
    } else if let entryFn = resolveLinkedAdapterEntryFunction() {
      rc = inputPath.path.withCString { input in
        moduleName.withCString { mod in
          outputPath.path.withCString { out in
            entryFn(input, mod, out)
          }
        }
      }
    } else {
      return false
    }

    guard rc == 0 else {
      throw MiniCompilerError.unsupportedSyntax("IRGen 実行失敗: rc=\(rc)")
    }
    return true
  }

  private func resolveLinkedAdapterEntryFunction() -> EmitIRFromSILEntryFn? {
    guard let symbol = dlsym(nil, "swift_irgen_adapter_emit_ir_from_sil") else {
      return nil
    }
    return unsafeBitCast(symbol, to: EmitIRFromSILEntryFn.self)
  }
}
