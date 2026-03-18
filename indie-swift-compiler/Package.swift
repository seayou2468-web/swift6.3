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
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .target(
            name: "MiniSwiftCompilerCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "MiniSwiftCompilerCoreTests",
            dependencies: ["MiniSwiftCompilerCore"]
        )
    ]
)
