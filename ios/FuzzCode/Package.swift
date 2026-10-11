// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FuzzCode",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FuzzCodeCore",
            targets: ["FuzzCodeCore"]
        ),
        .library(
            name: "FuzzCodeUI",
            targets: ["FuzzCodeUI"]
        )
    ],
    dependencies: [
        // FuzzCode uses pure native iOS frameworks (Foundation, SwiftUI, Security, Combine, Network)
        // Zero third-party runtime bloat required for core operation.
    ],
    targets: [
        .target(
            name: "FuzzCodeCore",
            dependencies: [],
            path: "Sources/FuzzCodeCore"
        ),
        .target(
            name: "FuzzCodeUI",
            dependencies: ["FuzzCodeCore"],
            path: "Sources/FuzzCodeUI"
        ),
        .testTarget(
            name: "FuzzCodeTests",
            dependencies: ["FuzzCodeCore"],
            path: "Tests/FuzzCodeTests"
        )
    ]
)
