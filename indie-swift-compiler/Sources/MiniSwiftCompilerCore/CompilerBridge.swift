import Foundation

public final class MiniSwiftCompilerBridge {
  public init() {}

  /// Swiftソース文字列をLLVM IR文字列に変換します（対応構文はMiniCompiler.swift参照）。
  public func compileToIR(source: String, moduleName: String) throws -> String {
    let output = try MiniCompiler().compileSource(source, moduleName: moduleName)
    return output.llvmIR
  }

  /// 抽出・内蔵したコンパイラパイプラインを使って LLVM IR を生成します。
  public func compileToIRUsingEmbeddedPipeline(
    source: String,
    moduleName: String
  ) throws -> String {
    let output = try MiniCompiler().compileSourceUsingEmbeddedPipeline(
      source,
      moduleName: moduleName
    )
    return output.llvmIR
  }

  public func compilerStageOrder() throws -> [String] {
    try MiniCompiler.defaultArchitecture().stageNames
  }
}

extension MiniSwiftCompilerBridge {
  public func compile(request: MiniCompilerCompileRequest) throws -> CompileOutput {
    try MiniCompiler().compileSource(request.source, moduleName: request.moduleName)
  }

  public func defaultToolchainLayout() -> MiniCompilerToolchainLayout {
    .default
  }
}
