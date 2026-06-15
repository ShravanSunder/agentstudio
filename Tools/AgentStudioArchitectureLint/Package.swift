// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgentStudioArchitectureLint",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "agentstudio-architecture-lint",
            targets: ["AgentStudioArchitectureLint"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AgentStudioArchitectureLint",
            dependencies: ["AgentStudioArchitectureLintCore"]
        ),
        .target(
            name: "AgentStudioArchitectureLintCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "AgentStudioArchitectureLintTests",
            dependencies: ["AgentStudioArchitectureLintCore"],
            exclude: ["Fixtures"]
        ),
    ]
)
