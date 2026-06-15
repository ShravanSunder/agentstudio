// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AgentStudio",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AgentStudio", targets: ["AgentStudio"]),
        .executable(name: "agentstudio-ipc", targets: ["AgentStudioIPCClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.10.0"),
        .package(url: "https://github.com/swift-otel/swift-otel.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.10.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(
            url: "https://github.com/ShravanSunder/agentstudio-git.git",
            revision: "90bb17da9d7030f4ae954d45cf150a0f5fe6511b"
        ),
    ],
    targets: [
        .executableTarget(
            name: "AgentStudio",
            dependencies: [
                "AgentStudioAppIPC",
                "GhosttyKit",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "OTel", package: "swift-otel"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Sources/AgentStudio",
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.svg",
                "Resources/terminfo-src",
                "Resources/AgentStudio.entitlements",
            ],
            resources: [
                .process("Resources/Icons.xcassets"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppLogoTransparent.svg"),
                .copy("Resources/AppIcon.iconset"),
                .copy("Resources/terminfo"),
                .copy("Resources/ghostty"),
                .copy("Resources/BridgeWeb"),
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
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "AgentStudioIPCTransport",
            path: "Sources/AgentStudioIPCTransport",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioProgrammaticControl",
            path: "Sources/AgentStudioProgrammaticControl",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioAppIPC",
            dependencies: [
                "AgentStudioIPCTransport",
                "AgentStudioProgrammaticControl",
            ],
            path: "Sources/AgentStudioAppIPC",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioIPCClientCore",
            dependencies: [
                "AgentStudioIPCTransport",
                "AgentStudioProgrammaticControl",
            ],
            path: "Sources/AgentStudioIPCClientCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AgentStudioIPCClient",
            dependencies: [
                "AgentStudioIPCClientCore"
            ],
            path: "Sources/AgentStudioIPCClient",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioIPCTransportTests",
            dependencies: [
                "AgentStudioIPCTransport"
            ],
            path: "Tests/AgentStudioIPCTransportTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioProgrammaticControlTests",
            dependencies: [
                "AgentStudioProgrammaticControl"
            ],
            path: "Tests/AgentStudioProgrammaticControlTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioAppIPCTests",
            dependencies: [
                "AgentStudioAppIPC",
                "AgentStudioIPCTransport",
                "AgentStudioProgrammaticControl",
            ],
            path: "Tests/AgentStudioAppIPCTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioIPCClientTests",
            dependencies: [
                "AgentStudioIPCClientCore",
                "AgentStudioIPCTransport",
                "AgentStudioProgrammaticControl",
            ],
            path: "Tests/AgentStudioIPCClientTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioTests",
            dependencies: [
                "AgentStudio",
                "AgentStudioAppIPC",
                "AgentStudioProgrammaticControl",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "InMemoryTracing", package: "swift-distributed-tracing"),
                .product(name: "Instrumentation", package: "swift-distributed-tracing"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Tests/AgentStudioTests",
            exclude: [
                "Fixtures/AtomLibCompileFailures",
                "Fixtures/SwiftLintLegacyCustomRules",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
