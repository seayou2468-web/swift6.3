import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
            "swift frontend adapter が未リンクか、実行に必要なツールチェーンが見つかりませんでした"
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
            guard let frontendPath = SwiftFrontendResolver.resolveFrontendExecutable() else {
                throw MiniCompilerError.swiftFrontendNotFound
            }

            let src = tmpDir.appendingPathComponent("input.swift")
            let out = tmpDir.appendingPathComponent("output.ll")
            try source.write(to: src, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: frontendPath)
            process.arguments = [
                "-frontend",
                "-emit-ir",
                src.path,
                "-module-name",
                moduleName,
                "-o",
                out.path
            ]
            SwiftFrontendAdapterBridge().applyEmbeddedSDKDefaults()

            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            let diagnosticsData = stderr.fileHandleForReading.readDataToEndOfFile()
            let diagnostics = String(data: diagnosticsData, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw MiniCompilerError.unsupportedSyntax("swift-frontend 実行失敗: \(diagnostics)")
            }

            let ir = try String(contentsOf: out, encoding: .utf8)
            let lines = diagnostics.split(separator: "\n").map(String.init)
            return CompileOutput(llvmIR: ir, diagnostics: lines)
        }
        return linkedResult
    }
}

private struct SwiftFrontendAdapterBridge {
    typealias AdapterCompileFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32

    func emitIRUsingLinkedAdapter(
        source: String,
        moduleName: String,
        temporaryDirectory: URL
    ) throws -> CompileOutput? {
        guard let compileFn = resolveCompileFunction() else {
            return nil
        }

        let outputPath = temporaryDirectory.appendingPathComponent("output.ll")
        applyEmbeddedSDKDefaults()

        let rc = source.withCString { src in
            moduleName.withCString { mod in
                outputPath.path.withCString { out in
                    compileFn(src, mod, out)
                }
            }
        }

        guard rc == 0 else {
            throw MiniCompilerError.unsupportedSyntax("swift frontend adapter 実行失敗: rc=\(rc)")
        }

        let ir = try String(contentsOf: outputPath, encoding: .utf8)
        return CompileOutput(llvmIR: ir, diagnostics: [])
    }

    private func resolveCompileFunction() -> AdapterCompileFn? {
        guard let symbol = dlsym(nil, "swift_irgen_adapter_compile") else {
            return nil
        }
        return unsafeBitCast(symbol, to: AdapterCompileFn.self)
    }

    func applyEmbeddedSDKDefaults() {
        if let target = ProcessInfo.processInfo.environment["SWIFT_TARGET_TRIPLE"], !target.isEmpty {
            _ = setenv("SWIFT_TARGET_TRIPLE", target, 1)
        }

        if let sdkPath = ProcessInfo.processInfo.environment["SWIFT_SDK_PATH"], !sdkPath.isEmpty {
            _ = setenv("SWIFT_SDK_PATH", sdkPath, 1)
            return
        }

        if let docsSDK = SwiftFrontendResolver.resolveDocumentsSDKPath() {
            _ = setenv("SWIFT_SDK_PATH", docsSDK, 1)
            return
        }

        if let sdk = ProcessInfo.processInfo.environment["SWIFT_SDK"], !sdk.isEmpty,
           let resolved = SwiftFrontendResolver.resolveSDKPath(sdk: sdk) {
            _ = setenv("SWIFT_SDK_PATH", resolved, 1)
        }
    }
}

private enum SwiftFrontendResolver {
    static func resolveFrontendExecutable() -> String? {
        if let envPath = ProcessInfo.processInfo.environment["SWIFT_FRONTEND_PATH"], !envPath.isEmpty {
            return envPath
        }
        if let fromPATH = runAndReadOutput("/usr/bin/env", ["which", "swift-frontend"]), !fromPATH.isEmpty {
            return fromPATH
        }
        return nil
    }

    static func resolveSDKPath(sdk: String) -> String? {
        runAndReadOutput("/usr/bin/xcrun", ["--sdk", sdk, "--show-sdk-path"])
    }

    static func resolveDocumentsSDKPath() -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let sdk = docs.appendingPathComponent("sdk", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sdk.path) else {
            return nil
        }
        return sdk.path
    }

    private static func runAndReadOutput(_ executable: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
