import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInboxNotification
@testable import AgentStudioRepoExplorer

@MainActor
@Suite(.serialized)
struct WorkspaceSettingsStoreRootIdentityTests {
    @Test
    func appCompositionPersistsTheExactRootFeatureAtoms() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atomStore = AtomRegistry()
        let appDelegate = AppDelegate()
        appDelegate.atomStore = atomStore
        let settingsStore = appDelegate.makeWorkspaceSettingsStore(
            sqliteDatastore: try await workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        atomStore.editorPreference.setBookmarkedEditor("cursor")
        atomStore.repoExplorerSidebarPrefs.setGroupingMode(.pane)
        atomStore.repoExplorerSidebarPrefs.setSortOrder(.descending)
        atomStore.repoExplorerSidebarPrefs.setRepoVisibilityMode(.favoritesOnly)
        atomStore.inboxNotificationPrefs.setGrouping(.byRepo)
        atomStore.inboxNotificationPrefs.setBellEnabled(true)

        try await settingsStore.flush(for: workspaceId)

        #expect(try fixture.repository.fetchEditorPreferences().bookmarkedEditorId == "cursor")
        #expect(try fixture.repository.fetchRepoExplorerPreferences().groupingMode == "pane")
        #expect(try fixture.repository.fetchRepoExplorerPreferences().sortOrder == "descending")
        #expect(try fixture.repository.fetchRepoExplorerPreferences().visibilityMode == "favoritesOnly")
        #expect(try fixture.repository.fetchInboxNotificationPreferences().grouping == "byRepo")
        #expect(try fixture.repository.fetchInboxNotificationPreferences().bellEnabled)
    }
}
