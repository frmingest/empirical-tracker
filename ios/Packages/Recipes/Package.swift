// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Recipes",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Recipes", targets: ["Recipes"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "Recipes",
            dependencies: ["Core"],
            path: "Sources/Recipes",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "RecipesTests",
            dependencies: ["Recipes", "Core"],
            path: "Tests/RecipesTests"
        ),
    ]
)
