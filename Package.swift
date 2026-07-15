// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-truss",
    dependencies: [
        .package(url: "https://github.com/xiaoli-white/swift-abstract.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "TrussCore",
            dependencies: [.product(name: "SwiftAbstract", package: "swift-abstract")]
        ),
        .target(
            name: "TrussSyntax",
            dependencies: ["TrussCore"]
        ),
        .executableTarget(
            name: "truss",
            dependencies: ["TrussSyntax"]
        ),
        .testTarget(
            name: "TrussSyntaxTests",
            dependencies: ["TrussSyntax", "TrussCore"]
        ),
        .testTarget(
            name: "trussTests",
            dependencies: ["truss"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
