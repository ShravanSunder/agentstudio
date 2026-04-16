import Foundation
import Testing

@Suite("WelcomeLauncherArchitectureTests")
struct WelcomeLauncherArchitectureTests {
    @Test("legacy AppStyle compatibility layer is removed")
    func legacyAppStyleCompatibilityLayerIsRemoved() {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let legacyPath = projectRoot.appending(path: "Sources/AgentStudio/Infrastructure/AppStyle.swift")

        #expect(FileManager.default.fileExists(atPath: legacyPath.path) == false)
    }

    @Test("file menu keeps real new tab command")
    func fileMenuKeepsRealNewTabCommand() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"),
            encoding: .utf8
        )

        #expect(source.contains("fileMenu.addItem(menuItem(command: .newTab, action: #selector(newTab)))"))
    }
}
