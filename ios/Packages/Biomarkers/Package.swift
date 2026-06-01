// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Biomarkers",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Biomarkers", targets: ["Biomarkers"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "Biomarkers",
            dependencies: ["Core"],
            path: "Sources/Biomarkers",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
