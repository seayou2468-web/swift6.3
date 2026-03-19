// swift-tools-version: 6.0
import PackageDescription

var packageTargets: [Target] = [
    .target(
        name: "MiniSwiftCompilerCore",
        dependencies: []
    ),
    .testTarget(
        name: "MiniSwiftCompilerCoreTests",
        dependencies: ["MiniSwiftCompilerCore"]
    )
]

#if os(macOS)
packageTargets.insert(
    .executableTarget(
        name: "EmbeddedCompilerIDE",
        dependencies: ["MiniSwiftCompilerCore"],
        path: "Demo/EmbeddedCompilerIDE",
        exclude: ["README.md"]
    ),
    at: 1
)
#endif

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
    targets: packageTargets
)
