// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AgentStudio",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AgentStudio", targets: ["AgentStudio"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentStudio",
            dependencies: [
                "GhosttyKit",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "Sources/AgentStudio",
            exclude: [
                "Resources/Info.plist",
                "Resources/terminfo-src",
            ],
            resources: [
                .process("Resources/SidebarIcons.xcassets"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.iconset"),
                .copy("Resources/terminfo"),
                .copy("Resources/ghostty"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
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
                .linkedFramework("WebKit"),
                .linkedFramework("AuthenticationServices"),
                .linkedLibrary("z"),
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "AgentStudioTests",
            dependencies: [
                "AgentStudio",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "Tests/AgentStudioTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "Frameworks/GhosttyKit.xcframework"
        )
    ]
)
