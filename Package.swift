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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AgentStudio",
            dependencies: ["GhosttyKit"],
            path: "Sources/AgentStudio",
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
        )
    ]
)
