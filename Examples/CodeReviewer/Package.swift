// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodeReviewer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "CodeReviewer",
            dependencies: [
                .product(name: "Swarm", package: "Swarm")
            ],
            path: "Sources/CodeReviewer",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CodeReviewerTests",
            dependencies: [
                .target(name: "CodeReviewer"),
                .product(name: "Swarm", package: "Swarm")
            ],
            path: "Tests/CodeReviewerTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
