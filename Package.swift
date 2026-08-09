// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AgentStudio",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AgentStudio", targets: ["AgentStudio"]),
        .executable(
            name: "agentstudio-bridge-dev-server",
            targets: ["AgentStudioBridgeDevelopmentServer"]
        ),
        .executable(name: "agentstudio-ipc", targets: ["AgentStudioIPCClient"]),
        .executable(name: "agentstudio-pane-agent", targets: ["AgentStudioPaneAgent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.10.0"),
        .package(url: "https://github.com/swift-otel/swift-otel.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.10.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(
            url: "https://github.com/ShravanSunder/agentstudio-git.git",
            revision: "dea894ac6c3607a40c260b8379107447c0a3519f"
        ),
    ],
    targets: [
        .executableTarget(
            name: "AgentStudio",
            dependencies: [
                "AgentStudioAppIPC",
                "AgentStudioBridge",
                "AgentStudioCodeViewer",
                "AgentStudioCommandBar",
                "AgentStudioCore",
                "AgentStudioEditorChooser",
                "AgentStudioInboxNotification",
                "AgentStudioInfrastructure",
                "AgentStudioRepoExplorer",
                "AgentStudioSharedComponents",
                "AgentStudioTerminal",
                "AgentStudioWebview",
                "GhosttyKit",
            ],
            path: "Sources/AgentStudio",
            exclude: [
                "Core",
                "Features",
                "Infrastructure",
                "Resources/Info.plist",
                "Resources/AppIcon.svg",
                "Resources/terminfo-src",
                "Resources/AgentStudio.entitlements",
                "SharedComponents",
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
            name: "AgentStudioInfrastructure",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "OTel", package: "swift-otel"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Sources/AgentStudio/Infrastructure",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioSharedComponents",
            dependencies: [
                "AgentStudioInfrastructure"
            ],
            path: "Sources/AgentStudio/SharedComponents",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioCore",
            dependencies: [
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Sources/AgentStudio/Core",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioBridge",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioProgrammaticControl",
                "AgentStudioSharedComponents",
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Sources/AgentStudio/Features/Bridge",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioCodeViewer",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
            ],
            path: "Sources/AgentStudio/Features/CodeViewer",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioCommandBar",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
            ],
            path: "Sources/AgentStudio/Features/CommandBar",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioEditorChooser",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
            ],
            path: "Sources/AgentStudio/Features/EditorChooser",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioInboxNotification",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/AgentStudio/Features/InboxNotification",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioRepoExplorer",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
            ],
            path: "Sources/AgentStudio/Features/RepoExplorer",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioTerminal",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "GhosttyKit",
            ],
            path: "Sources/AgentStudio/Features/Terminal",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioWebview",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
            ],
            path: "Sources/AgentStudio/Features/Webview",
            swiftSettings: [
                .swiftLanguageMode(.v6)
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
            name: "AgentStudioBridgeDevelopmentServer",
            dependencies: [
                "AgentStudioBridge",
                "AgentStudioCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            path: "Sources/AgentStudioBridgeDevelopmentServer",
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
        .executableTarget(
            name: "AgentStudioPaneAgent",
            dependencies: [
                "AgentStudioIPCClientCore"
            ],
            path: "Sources/AgentStudioPaneAgent",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AgentStudioTestSupport",
            dependencies: [
                "AgentStudioCore"
            ],
            path: "Tests/AgentStudioTests/TestSupport",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioBridgeDevelopmentServerTests",
            dependencies: [
                "AgentStudioBridgeDevelopmentServer",
                "AgentStudioCore",
                "AgentStudioTestSupport",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/AgentStudioBridgeDevelopmentServerTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioInfrastructureTests",
            dependencies: [
                "AgentStudioInfrastructure",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Tests/AgentStudioTests/Infrastructure",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioSharedComponentsTests",
            dependencies: [
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
            ],
            path: "Tests/AgentStudioTests/SharedComponents",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioCoreTests",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Tests/AgentStudioTests/Core",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioBridgeTests",
            dependencies: [
                "AgentStudioBridge",
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioProgrammaticControl",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "AgentStudioGit", package: "agentstudio-git"),
            ],
            path: "Tests/AgentStudioTests/Features/Bridge",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioCodeViewerTests",
            dependencies: [
                "AgentStudioCodeViewer",
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
            ],
            path: "Tests/AgentStudioTests/Features/CodeViewer",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioCommandBarTests",
            dependencies: [
                "AgentStudioCommandBar",
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
            ],
            path: "Tests/AgentStudioTests/Features/CommandBar",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioEditorChooserTests",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioEditorChooser",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
            ],
            path: "Tests/AgentStudioTests/Features/EditorChooser",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioInboxNotificationTests",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInboxNotification",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/AgentStudioTests/Features/InboxNotification",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioRepoExplorerTests",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioRepoExplorer",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
            ],
            path: "Tests/AgentStudioTests/Features/RepoExplorer",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioTerminalTests",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "AgentStudioTerminal",
                "AgentStudioTestSupport",
                "GhosttyKit",
            ],
            path: "Tests/AgentStudioTests/Features/Terminal",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AgentStudioWebviewTests",
            dependencies: [
                "AgentStudioCore",
                "AgentStudioInfrastructure",
                "AgentStudioSharedComponents",
                "AgentStudioTestSupport",
                "AgentStudioWebview",
            ],
            path: "Tests/AgentStudioTests/Features/Webview",
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
                "AgentStudio",
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
                "AgentStudioBridge",
                "AgentStudioCodeViewer",
                "AgentStudioCommandBar",
                "AgentStudioCore",
                "AgentStudioEditorChooser",
                "AgentStudioInboxNotification",
                "AgentStudioInfrastructure",
                "AgentStudioProgrammaticControl",
                "AgentStudioRepoExplorer",
                "AgentStudioSharedComponents",
                "AgentStudioTerminal",
                "AgentStudioTestSupport",
                "AgentStudioWebview",
                "GhosttyKit",
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
            sources: [
                "App",
                "Architecture",
                "Helpers",
                "Integration",
                "Scripts",
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
