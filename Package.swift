// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-truss",
    dependencies: [
        .package(url: "https://github.com/xiaoli-white/swift-abstract.git", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "1.6.1"),
        .package(url: "https://github.com/davecom/SwiftGraph.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "TrussDiagnosis"
        ),
        .target(
            name: "TrussCore",
            dependencies: [
                "TrussDiagnosis", .product(name: "SwiftAbstract", package: "swift-abstract"),
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
            name: "TrussOperators",
            dependencies: ["TrussCore", .product(name: "SwiftGraph", package: "SwiftGraph")]
        ),
        .executableTarget(
            name: "truss",
            dependencies: [
                "TrussSyntax", "TrussSemantics",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .testTarget(
            name: "TrussDiagnosisTests",
            dependencies: ["TrussDiagnosis"]
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
