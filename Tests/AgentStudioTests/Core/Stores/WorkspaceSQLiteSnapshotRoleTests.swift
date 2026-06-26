import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteSnapshotRoleTests")
struct WorkspaceSQLiteSnapshotRoleTests {
    @Test("live SQLite snapshot is not the legacy JSON persistable state type")
    func liveSQLiteSnapshotIsNotLegacyPersistableState() {
        let workspaceId = UUID()
        let snapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "SQLite Snapshot",
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        #expect(snapshot.id == workspaceId)
        #expect(String(describing: type(of: snapshot)) == "WorkspaceSQLiteSnapshot")
        #expect(String(describing: WorkspacePersistor.PersistableState.self) != String(describing: type(of: snapshot)))
    }

    @Test("live SQLite snapshot carries no repository topology fields")
    func liveSQLiteSnapshotCarriesNoRepositoryTopologyFields() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let snapshotPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift"
        )
        let source = try String(contentsOf: snapshotPath, encoding: .utf8)
        let snapshotSource = source.components(separatedBy: "struct RepositoryTopologySQLiteSnapshot").first ?? source

        #expect(!snapshotSource.contains("repos: [CanonicalRepo]"))
        #expect(!snapshotSource.contains("worktrees: [CanonicalWorktree]"))
        #expect(!snapshotSource.contains("unavailableRepoIds"))
        #expect(!snapshotSource.contains("watchedPaths"))
    }
}
