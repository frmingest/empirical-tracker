// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BodyMetrics",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "BodyMetrics", targets: ["BodyMetrics"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "BodyMetrics",
            dependencies: ["Core"],
            path: "Sources/BodyMetrics",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
