// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StetEngine",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "StetCore", targets: ["StetCore"]),
        .library(name: "StetAI", targets: ["StetAI"]),
        .library(name: "StetRewrite", targets: ["StetRewrite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", exact: "0.4.7"),
        .package(url: "https://github.com/mattt/EventSource.git", exact: "1.4.1"),
    ],
    targets: [
        .target(
            name: "StetCore",
            path: "Sources/StetCore"
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
    ]
)
