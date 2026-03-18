import Foundation

public final class MiniSwiftCompilerBridge {
    public init() {}

    /// Swiftソース文字列をLLVM IR文字列に変換します（対応構文はMiniCompiler.swift参照）。
    public func compileToIR(source: String, moduleName: String) throws -> String {
        let output = try MiniCompiler().compileSource(source, moduleName: moduleName)
        return output.llvmIR
    }

    /// swift-frontendを利用してLLVM IRを生成します（Swift互換性優先）。
    public func compileToIRUsingSwiftFrontend(
        source: String,
        moduleName: String,
        swiftFrontendPath: String
    ) throws -> String {
        let output = try MiniCompiler().compileSourceUsingSwiftFrontend(
            source,
            moduleName: moduleName,
            swiftFrontendPath: swiftFrontendPath
        )
        return output.llvmIR
    }
}
