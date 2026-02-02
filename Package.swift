// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentStudio",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AgentStudio", targets: ["AgentStudio"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.2.5")
    ],
    targets: [
        .executableTarget(
            name: "AgentStudio",
            dependencies: ["SwiftTerm"],
            path: "Sources/AgentStudio"
        )
    ]
)
