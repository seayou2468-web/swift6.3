// swift-tools-version: 6.0
import Foundation
import PackageDescription

let fileManager = FileManager.default
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let llvmXCFrameworkPath = packageRoot.appendingPathComponent("LLVM.xcframework").path
let clangXCFrameworkPath = packageRoot.appendingPathComponent("Clang.xcframework").path
let hasEmbeddedToolchainXCFrameworks =
    fileManager.fileExists(atPath: llvmXCFrameworkPath) &&
    fileManager.fileExists(atPath: clangXCFrameworkPath)

let embeddedToolchainDependencies: [Target.Dependency] =
    hasEmbeddedToolchainXCFrameworks
    ? [
        "LLVMEmbedded",
        "ClangEmbedded",
    ]
    : []

var packageTargets: [Target] = [
    .target(
        name: "MiniSwiftCompilerCore",
        dependencies: embeddedToolchainDependencies
    ),
    .testTarget(
        name: "MiniSwiftCompilerCoreTests",
        dependencies: ["MiniSwiftCompilerCore"]
    )
]

var packageProducts: [Product] = [
    .library(
        name: "MiniSwiftCompilerCore",
        type: .static,
        targets: ["MiniSwiftCompilerCore"]
    )
]

if hasEmbeddedToolchainXCFrameworks {
    packageTargets.append(
        .binaryTarget(
            name: "LLVMEmbedded",
            path: "LLVM.xcframework"
        )
    )
    packageTargets.append(
        .binaryTarget(
            name: "ClangEmbedded",
            path: "Clang.xcframework"
        )
    )
}

let package = Package(
    name: "IndieSwiftCompiler",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: packageProducts,
    dependencies: [],
    targets: packageTargets
)
