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
            // HealthKit framework is linked in the app target, not here.
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
