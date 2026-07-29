import Foundation
import Testing

@Suite("App command Core boundary")
struct AppCommandCoreBoundaryTests {
    @Test("Core command vocabulary has no IPC or Feature dependencies")
    func coreCommandVocabularyHasNoIPCOrFeatureDependencies() throws {
        let commandsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AgentStudio/Core/Actions/Commands")
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: commandsDirectory,
            includingPropertiesForKeys: nil
        )
        let combinedSource =
            try sourceFiles
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        #expect(!combinedSource.contains("AgentStudioProgrammaticControl"))
        #expect(!combinedSource.contains("IPCCommand"))
        #expect(!combinedSource.contains("IPCHandleKind"))
        #expect(!combinedSource.contains("IPCPrivilege"))
        #expect(!combinedSource.contains("RepoExplorerGroupingMode"))
        #expect(!combinedSource.contains("RepoExplorerVisibilityMode"))
        #expect(!combinedSource.contains("RepoExplorerSortOrder"))
        #expect(!combinedSource.contains("InboxNotificationRowStateFilter"))
        #expect(!combinedSource.contains("InboxNotificationContentMode"))
        #expect(!combinedSource.contains("AppCommandExecutionRequest"))
        #expect(!combinedSource.contains("AppCommandDispatcher"))
    }
}
