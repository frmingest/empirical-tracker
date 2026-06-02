// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppAuth", targets: ["AppAuth"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .target(
            name: "AppAuth",
            dependencies: [
                "Core",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Sources/AppAuth",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "AuthTests",
            dependencies: ["AppAuth"],
            path: "Tests/AuthTests"
        ),
    ]
)
