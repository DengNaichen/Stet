// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FunASRPackage",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "FunASRRuntime", targets: ["FunASRRuntime"]),
    ],
    targets: [
        .binaryTarget(
            name: "FunASRRuntime",
            path: "Artifacts/FunASRRuntime.xcframework"
        ),
    ]
)
