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
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            watchedPaths: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        #expect(snapshot.id == workspaceId)
        #expect(String(describing: type(of: snapshot)) == "WorkspaceSQLiteSnapshot")
        #expect(String(describing: WorkspacePersistor.PersistableState.self) != String(describing: type(of: snapshot)))
    }
}
