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
            url: "https://github.com/DengNaichen/Stet/releases/download/v0.0.0-assets/sensevoice.xcframework.zip",
            checksum: "1baa70b7c3f52ba0074ef4f0d608917b45fd722a779c9f7a096a77c12c8b3bc1"
        ),
    ]
)
