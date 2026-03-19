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

var packageProducts: [Product] = [
    .library(
        name: "MiniSwiftCompilerCore",
        type: .static,
        targets: ["MiniSwiftCompilerCore"]
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
packageProducts.append(
    .executable(
        name: "EmbeddedCompilerIDE",
        targets: ["EmbeddedCompilerIDE"]
    )
)
#endif

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
