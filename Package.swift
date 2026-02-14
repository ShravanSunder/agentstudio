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
            exclude: [
                "Resources/Info.plist",
                "Resources/terminfo-src",
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.iconset"),
                .copy("Resources/terminfo"),
                .copy("Resources/ghostty"),
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
        .testTarget(
            name: "AgentStudioTests",
            dependencies: ["AgentStudio"],
            path: "Tests/AgentStudioTests"
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "Frameworks/GhosttyKit.xcframework"
        )
    ]
)
