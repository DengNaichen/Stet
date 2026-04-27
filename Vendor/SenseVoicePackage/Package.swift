// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SenseVoicePackage",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "sensevoice",
            targets: ["sensevoice"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "sensevoice",
            path: "sensevoice.xcframework"
        ),
    ]
)
