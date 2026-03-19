// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IndieSwiftCompiler",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MiniSwiftCompilerCore",
            type: .dynamic,
            targets: ["MiniSwiftCompilerCore"]
        ),
        .library(
            name: "MiniSwiftCompilerCoreStatic",
            type: .static,
            targets: ["MiniSwiftCompilerCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MiniSwiftCompilerCore",
            dependencies: []
        ),
        .testTarget(
            name: "MiniSwiftCompilerCoreTests",
            dependencies: ["MiniSwiftCompilerCore"]
        )
    ]
)
