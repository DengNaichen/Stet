// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StetEngine",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "StetCore", targets: ["StetCore"]),
        .library(name: "StetAI", targets: ["StetAI"]),
        .library(name: "StetRewrite", targets: ["StetRewrite"]),
        .library(name: "StetASR", targets: ["StetASR"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", exact: "0.4.7"),
        .package(url: "https://github.com/mattt/EventSource.git", exact: "1.4.1"),
        .package(path: "Vendor/SherpaOnnxPackage"),
        .package(path: "Vendor/FunASRPackage"),
    ],
    targets: [
        .target(
            name: "StetCore",
            path: "Sources/StetCore"
        ),
        .target(
            name: "StetASR",
            dependencies: [
                "StetCore",
                .product(name: "sherpa_onnx", package: "SherpaOnnxPackage"),
                .product(
                    name: "FunASRRuntime",
                    package: "FunASRPackage",
                    condition: .when(platforms: [.macOS])
                ),
            ],
            path: "Sources/StetASR",
            linkerSettings: [
                .linkedFramework("Accelerate", .when(platforms: [.macOS])),
                .linkedLibrary("c++", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "StetRewrite",
            dependencies: [
                "StetCore",
            ],
            path: "Sources/StetRewrite"
        ),
        .target(
            name: "StetAI",
            dependencies: [
                "StetCore",
                "StetRewrite",
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "EventSource", package: "EventSource"),
            ],
            path: "Sources/StetAI"
        ),
        .testTarget(
            name: "StetCoreTests",
            dependencies: [
                "StetCore",
            ],
            path: "Tests/StetCoreTests"
        ),
        .testTarget(
            name: "StetRewriteTests",
            dependencies: [
                "StetRewrite",
            ],
            path: "Tests/StetRewriteTests"
        ),
        .testTarget(
            name: "StetAITests",
            dependencies: [
                "StetAI",
                "StetCore",
                "StetRewrite",
            ],
            path: "Tests/StetAITests"
        ),
    ]
)
