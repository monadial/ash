// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AshCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "AshCore", targets: ["AshCore"]),
    ],
    targets: [
        .target(
            name: "AshCore",
            dependencies: ["AshCoreFFI"],
            path: "Sources",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .binaryTarget(
            name: "AshCoreFFI",
            path: "AshCoreFFI.xcframework"
        ),
    ]
)
