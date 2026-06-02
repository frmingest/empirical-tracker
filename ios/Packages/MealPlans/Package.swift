// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MealPlans",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MealPlans", targets: ["MealPlans"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "MealPlans",
            dependencies: ["Core"],
            path: "Sources/MealPlans",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
