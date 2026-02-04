// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentStudio", targets: ["AgentStudio"])
    ],
    dependencies: [
        // Snapshot testing for UI verification
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "AgentStudio",
            dependencies: ["GhosttyKit"],
            path: "Sources/AgentStudio",
            resources: [
                .copy("Resources/zellij")
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreServices"),
                .linkedLibrary("z"),
                .linkedLibrary("c++")
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "Frameworks/GhosttyKit.xcframework"
        ),
        // Unit and integration tests
        .testTarget(
            name: "AgentStudioTests",
            dependencies: ["AgentStudio"],
            path: "Tests/AgentStudioTests"
        ),
        // UI and snapshot tests
        .testTarget(
            name: "AgentStudioUITests",
            dependencies: [
                "AgentStudio",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/AgentStudioUITests"
        )
    ]
)
