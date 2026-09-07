import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioRepoExplorer

@MainActor
@Suite(.serialized)
struct WorkspaceSettingsStoreRootIdentityTests {
    @Test
    func appCompositionPersistsOnlySettingsOwnedRootFeatureAtoms() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atomStore = AtomRegistry()
        let appDelegate = AppDelegate()
        appDelegate.atomStore = atomStore
        let settingsStore = appDelegate.makeWorkspaceSettingsStore(
            sqliteDatastore: try await workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        atomStore.editorPreference.setBookmarkedEditor("cursor")
        atomStore.repoExplorerSidebarPrefs.setSortField(.activity, for: .panes)
        atomStore.repoExplorerSidebarPrefs.setSortDirection(.descending, for: .panes)
        try await settingsStore.flush(for: workspaceId)

        #expect(try fixture.repository.fetchEditorPreferences().bookmarkedEditorId == "cursor")
        #expect(try fixture.repository.fetchRepoExplorerPreferences().panesSortField == .activity)
        #expect(try fixture.repository.fetchRepoExplorerPreferences().panesSortDirection == .descending)
        #expect(try fixture.repository.hasSidebarState() == false)
        #expect(try fixture.repository.fetchInboxNotificationPreferences() == .default)
    }
}
