// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Account",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Account", targets: ["Account"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "Account",
            dependencies: ["Core"],
            path: "Sources/Account",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
