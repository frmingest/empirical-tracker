// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DietEvents",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DietEvents", targets: ["DietEvents"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "DietEvents",
            dependencies: ["Core"],
            path: "Sources/DietEvents",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
