// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthSync",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HealthSync", targets: ["HealthSync"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../BodyMetrics"),
    ],
    targets: [
        .target(
            name: "HealthSync",
            dependencies: ["Core", "BodyMetrics"],
            path: "Sources/HealthSync",
            // HealthKit autolinks via `import HealthKit`; nothing to link here.
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "HealthSyncTests",
            dependencies: ["HealthSync", "BodyMetrics"],
            path: "Tests/HealthSyncTests"
        ),
    ]
)
