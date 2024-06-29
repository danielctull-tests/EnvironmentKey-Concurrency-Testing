// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "EnvironmentKey-Concurrency-Testing",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "DetailUI", targets: ["DetailUI"]),
    ],
    targets: [
        .target(
            name: "DetailUI",
            swiftSettings: [
              .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
