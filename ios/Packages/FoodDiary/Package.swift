// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoodDiary",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FoodDiary", targets: ["FoodDiary"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "FoodDiary",
            dependencies: ["Core"],
            path: "Sources/FoodDiary",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
