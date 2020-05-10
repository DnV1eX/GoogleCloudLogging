// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "GoogleCloudLogging",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_13),
        .tvOS(.v11),
        .watchOS(.v4),
    ],
    products: [
        .library(
            name: "GoogleCloudLogging",
            targets: ["GoogleCloudLogging"]),
    ],
    dependencies: [
         .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "GoogleCloudLogging",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]),
        .testTarget(
            name: "GoogleCloudLoggingTests",
            dependencies: ["GoogleCloudLogging"]),
    ]
)
