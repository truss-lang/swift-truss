// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-truss",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
        .package(url: "https://github.com/davecom/SwiftGraph.git", from: "4.0.0"),
        .package(url: "https://github.com/xiaoli-white/swift-abstract.git", from: "1.0.0"),
        .package(url: "https://github.com/xiaoli-white/swift-better-diagnostic.git", from: "1.1.2"),
        .package(url: "https://github.com/xiaoli-white/llvm-swift-binding", from: "1.0.6"),
    ],
    targets: [
        .target(
            name: "TrussCore",
            dependencies: [
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
                .product(name: "SwiftAbstract", package: "swift-abstract"),
            ]
        ),
        .target(
            name: "TrussSyntax",
            dependencies: ["TrussCore"]
        ),
        .target(
            name: "TrussSemantics",
            dependencies: ["TrussCore"]
        ),
        .target(
            name: "TrussOperator",
            dependencies: [
                "TrussCore",
                .product(name: "SwiftGraph", package: "SwiftGraph"),
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
            ]
        ),
        .target(
            name: "TrussTIRGen",
            dependencies: ["TrussCore"]
        ),
        .target(
            name: "TrussCodeGen",
            dependencies: [
                "TrussCore",
                .product(name: "LLVMSwiftBinding", package: "llvm-swift-binding"),
            ]
        ),
        .target(
            name: "TrussPackageManager",
            dependencies: [
                "TrussCore", "TrussDriver",
                .product(name: "SwiftGraph", package: "SwiftGraph"),
            ]
        ),
        .target(
            name: "TrussDriver",
            dependencies: [
                "TrussSyntax", "TrussSemantics", "TrussOperator", "TrussTIRGen", "TrussCodeGen",
                .product(name: "LLVMSwiftBinding", package: "llvm-swift-binding"),
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
            ]
        ),
        .executableTarget(
            name: "TrussExample",
            dependencies: ["TrussDriver"]
        ),
        .executableTarget(
            name: "truss",
            dependencies: [
                "TrussPackageManager",
                "TrussDriver",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "trussc",
            dependencies: [
                "TrussDriver",
                "TrussPackageManager",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "TrussSyntaxTests",
            dependencies: [
                "TrussSyntax", "TrussCore",
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
            ]
        ),
        .testTarget(
            name: "TrussCoreTests",
            dependencies: [
                "TrussCore", "TrussSyntax", "TrussSemantics", "TrussOperator",
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
            ]
        ),
        .testTarget(
            name: "TrussSemanticTests",
            dependencies: [
                "TrussOperator", "TrussSemantics", "TrussSyntax", "TrussCore",
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
            ]
        ),
        .testTarget(
            name: "TrussOperatorTests",
            dependencies: [
                "TrussOperator", "TrussSyntax", "TrussCore", "TrussSemantics",
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
            ]
        ),
        .testTarget(
            name: "TrussDriverTests",
            dependencies: ["truss", "TrussDriver"]
        ),
        .testTarget(
            name: "TrussPackageManagerTests",
            dependencies: ["TrussPackageManager", "TrussDriver", "TrussCore"]
        ),
        .testTarget(
            name: "TrussTIRGenTests",
            dependencies: [
                "TrussTIRGen", "TrussSyntax", "TrussSemantics", "TrussOperator", "TrussCore",
                .product(name: "SwiftBetterDiagnostic", package: "swift-better-diagnostic"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)