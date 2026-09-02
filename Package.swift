// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipMaster",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClipMaster",
            targets: ["ClipMaster"]
        ),
    ],
    dependencies: [
        // WhisperKit: On-Device CoreML Speech-to-Text
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "ClipMaster",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/ClipMaster"
        ),
        .testTarget(
            name: "ClipMasterTests",
            dependencies: ["ClipMaster"],
            path: "Tests/ClipMasterTests"
        ),
    ]
)
