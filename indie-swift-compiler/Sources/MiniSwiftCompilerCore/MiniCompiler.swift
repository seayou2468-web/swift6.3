import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public typealias EmbeddedCompileCallback = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
) -> Int32

private typealias AdapterSetCompileCallbackFn = @convention(c) (EmbeddedCompileCallback?) -> Int32

public enum MiniCompilerError: Error, CustomStringConvertible {
    case sourceReadFailed(String)
    case unsupportedSyntax(String)
    case missingMain
    case swiftFrontendNotFound

    public var description: String {
        switch self {
        case .sourceReadFailed(let path):
            "ソースファイルの読み込みに失敗しました: \(path)"
        case .unsupportedSyntax(let message):
            "未対応の構文です: \(message)"
        case .missingMain:
            "main() 相当のトップレベル式が見つかりませんでした"
        case .swiftFrontendNotFound:
            "swift frontend adapter 実体が未リンクです（swift_irgen_adapter_compile が解決できません）"
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
        /// swift-frontend へ委譲（Swift本家互換性優先）
        case swiftFrontend
    }

    public func compileSource(_ source: String, moduleName: String = "Main") throws -> CompileOutput {
        try compileSource(source, moduleName: moduleName, mode: .swiftFrontend)
    }

    public func compileSource(
        _ source: String,
        moduleName: String = "Main",
        mode: BackendMode
    ) throws -> CompileOutput {
        switch mode {
        case .swiftFrontend:
            return try SwiftFrontendBridge().emitIR(
                source: source,
                moduleName: moduleName
            )
        }
    }

    public func compileSourceUsingSwiftFrontend(
        _ source: String,
        moduleName: String = "Main"
    ) throws -> CompileOutput {
        try compileSource(source, moduleName: moduleName, mode: .swiftFrontend)
    }

    public func compileSource(_ source: String, moduleName: String = "Main", modeRaw: String) throws -> CompileOutput {
        _ = modeRaw
        return try compileSource(source, moduleName: moduleName, mode: .swiftFrontend)
    }

    public func compileFile(at path: String, moduleName: String = "Main") throws -> CompileOutput {
        try compileFile(at: path, moduleName: moduleName, mode: .swiftFrontend)
    }

    public func compileFile(
        at path: String,
        moduleName: String = "Main",
        mode: BackendMode
    ) throws -> CompileOutput {
        guard let data = FileManager.default.contents(atPath: path),
              let source = String(data: data, encoding: .utf8) else {
            throw MiniCompilerError.sourceReadFailed(path)
        }

        return try compileSource(source, moduleName: moduleName, mode: mode)
    }
}

private struct SwiftFrontendBridge {
    func emitIR(source: String, moduleName: String) throws -> CompileOutput {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        guard let linkedResult = try SwiftFrontendAdapterBridge().emitIRUsingLinkedAdapter(
            source: source,
            moduleName: moduleName,
            temporaryDirectory: tmpDir
        ) else {
            throw MiniCompilerError.swiftFrontendNotFound
        }
        return linkedResult
    }
}

private struct SwiftFrontendAdapterBridge {
    typealias AdapterCompileEntryFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32
    nonisolated(unsafe) static var runtimeCallback: EmbeddedCompileCallback?

    func emitIRUsingLinkedAdapter(
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
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let sdk = docs.appendingPathComponent("sdk", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sdk.path) else {
            return nil
        }
        return sdk.path
    }
}
