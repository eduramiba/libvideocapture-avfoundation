// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "videocapture-avfoundation",
    platforms: [
        .macOS(.v10_10)
    ],
    products: [
        .library(
            name: "videocapture-avfoundation",
            targets: ["videocapture-avfoundation"]
        )
    ],
    targets: [
        .target(
            name: "videocapture-avfoundation",
            path: "Sources/videocapture-avfoundation",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "videocapture-avfoundationTests",
            dependencies: ["videocapture-avfoundation"]
        )
    ]
)
