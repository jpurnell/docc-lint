// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "docc-lint",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "docc-lint", targets: ["DocCLint"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "DocCLint",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "DocCLintTests",
            dependencies: ["DocCLint"]
        ),
    ]
)
