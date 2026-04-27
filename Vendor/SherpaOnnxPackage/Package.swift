// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SherpaOnnxPackage",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "sherpa_onnx",
            targets: ["sherpa_onnx"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "sherpa_onnx",
            url: "https://github.com/DengNaichen/Stet/releases/download/v0.0.0-assets/sherpa-onnx-new.xcframework.zip",
            checksum: "1ef5044fb21a1775c82d046697bc47904c61dfa80955aa552bedc85a66d7b62e"
        ),
    ]
)
