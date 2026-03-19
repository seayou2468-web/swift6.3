import Foundation

public struct MiniCompilerCompileRequest: Sendable, Equatable {
  public var source: String
  public var moduleName: String

  public init(source: String, moduleName: String = "Main") {
    self.source = source
    self.moduleName = moduleName
  }
}

public struct MiniCompilerToolchainLayout: Sendable, Equatable {
  public static let `default` = MiniCompilerToolchainLayout()

  public var llvmXCFrameworkName: String
  public var clangXCFrameworkName: String
  public var swiftResourceDirectory: String?
  public var swiftSDKPath: String?
  public var swiftTargetTriple: String?

  public init(
    llvmXCFrameworkName: String = "LLVM.xcframework",
    clangXCFrameworkName: String = "Clang.xcframework",
    swiftResourceDirectory: String? = nil,
    swiftSDKPath: String? = nil,
    swiftTargetTriple: String? = nil
  ) {
    self.llvmXCFrameworkName = llvmXCFrameworkName
    self.clangXCFrameworkName = clangXCFrameworkName
    self.swiftResourceDirectory = swiftResourceDirectory
    self.swiftSDKPath = swiftSDKPath
    self.swiftTargetTriple = swiftTargetTriple
  }
}

public enum MiniCompilerEmbeddedRuntime {
  public static func configureProcessEnvironment(
    for layout: MiniCompilerToolchainLayout = .default,
    environment: inout [String: String]
  ) {
    if let swiftResourceDirectory = layout.swiftResourceDirectory {
      environment["SWIFT_RESOURCE_DIR"] = swiftResourceDirectory
    }
    if let swiftSDKPath = layout.swiftSDKPath {
      environment["SWIFT_SDK_PATH"] = swiftSDKPath
    }
    if let swiftTargetTriple = layout.swiftTargetTriple {
      environment["SWIFT_TARGET_TRIPLE"] = swiftTargetTriple
    }
  }

  public static func configureCurrentProcess(
    for layout: MiniCompilerToolchainLayout = .default
  ) {
    if let swiftResourceDirectory = layout.swiftResourceDirectory {
      setenv("SWIFT_RESOURCE_DIR", swiftResourceDirectory, 1)
    }
    if let swiftSDKPath = layout.swiftSDKPath {
      setenv("SWIFT_SDK_PATH", swiftSDKPath, 1)
    }
    if let swiftTargetTriple = layout.swiftTargetTriple {
      setenv("SWIFT_TARGET_TRIPLE", swiftTargetTriple, 1)
    }
  }
}

public final class MiniCompilerIOSAdapter {
  public let compiler: MiniCompiler
  public let toolchainLayout: MiniCompilerToolchainLayout

  public init(
    compiler: MiniCompiler = MiniCompiler(),
    toolchainLayout: MiniCompilerToolchainLayout = .default
  ) {
    self.compiler = compiler
    self.toolchainLayout = toolchainLayout
  }

  public func prepareEmbeddedRuntime() {
    MiniCompilerEmbeddedRuntime.configureCurrentProcess(for: toolchainLayout)
  }

  public func compile(_ request: MiniCompilerCompileRequest) throws -> CompileOutput {
    prepareEmbeddedRuntime()
    return try compiler.compileSource(request.source, moduleName: request.moduleName)
  }

  public func compileToIR(_ request: MiniCompilerCompileRequest) throws -> String {
    try compile(request).llvmIR
  }
}
