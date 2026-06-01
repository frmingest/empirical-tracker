// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Auth", targets: ["Auth"]),
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
            name: "Auth",
            dependencies: [
                "Core",
                // Import top-level Supabase module only — avoids naming conflict
                // with our own "Auth" target.
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Sources/Auth",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "AuthTests",
            dependencies: ["Auth"],
            path: "Tests/AuthTests"
        ),
    ]
)
