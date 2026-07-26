import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSettingsStoreTests {
    @Test
    func flushAndRestoreRoundTripsTypedSQLiteSettings() async throws {
        let workspaceId = UUID()
        let fixture = try makeFixture()
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let inboxPreferences = InboxNotificationPrefsAtom()
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences
        )
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.tab)
        repoExplorerPreferences.setSortOrder(.descending)
        repoExplorerPreferences.setRepoVisibilityMode(.favoritesOnly)
        inboxPreferences.setGrouping(.byRepo)
        inboxPreferences.setSort(.oldestFirst)
        inboxPreferences.setBellEnabled(true)
        inboxPreferences.setGlobalInboxContentMode(.activity)
        inboxPreferences.setGlobalInboxRowStateFilter(.all)
        inboxPreferences.setPaneInboxContentMode(.all)
        inboxPreferences.setPaneInboxRowStateFilter(.unreadOnly)

        try await store.flush(for: workspaceId)

        let restoredEditorPreference = EditorPreferenceAtom()
        let restoredRepoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let restoredInboxPreferences = InboxNotificationPrefsAtom()
        await makeStore(
            datastore: fixture.datastore,
            editorPreference: restoredEditorPreference,
            repoExplorerPreferences: restoredRepoExplorerPreferences,
            inboxPreferences: restoredInboxPreferences
        ).restoreAsync(for: workspaceId)

        #expect(restoredEditorPreference.bookmarkedEditorId == "cursor")
        #expect(restoredRepoExplorerPreferences.groupingMode == .tab)
        #expect(restoredRepoExplorerPreferences.sortOrder == .descending)
        #expect(restoredRepoExplorerPreferences.repoVisibilityMode == .favoritesOnly)
        #expect(restoredInboxPreferences.grouping == .byRepo)
        #expect(restoredInboxPreferences.sort == .oldestFirst)
        #expect(restoredInboxPreferences.bellEnabled)
        #expect(restoredInboxPreferences.globalInboxContentMode == .activity)
        #expect(restoredInboxPreferences.globalInboxRowStateFilter == .all)
        #expect(restoredInboxPreferences.paneInboxContentMode == .all)
        #expect(restoredInboxPreferences.paneInboxRowStateFilter == .unreadOnly)
    }

    @Test
    func restoreMissingRowsAppliesTypedDefaults() async throws {
        let fixture = try makeFixture()
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let inboxPreferences = InboxNotificationPrefsAtom()
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.pane)
        repoExplorerPreferences.setSortOrder(.descending)
        repoExplorerPreferences.setRepoVisibilityMode(.favoritesOnly)
        inboxPreferences.setGrouping(.byRepo)
        inboxPreferences.setSort(.oldestFirst)
        inboxPreferences.setBellEnabled(true)

        await makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences
        ).restoreAsync(for: UUID())

        assertDefaultSettings(
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences
        )
    }

    @Test
    func restoreInvalidProductVocabularyDefaultsEachTypedPreferenceLane() async throws {
        let workspaceId = UUID()
        let fixture = try makeFixture()
        try await fixture.localDatabaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_editor_preferences(workspace_id, bookmarked_editor_id, updated_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [workspaceId.uuidString, "cursor", 1]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_repo_explorer_preferences(
                        workspace_id, grouping_mode, sort_order, visibility_mode, updated_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [workspaceId.uuidString, "unsupported", "descending", "favoritesOnly", 1]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_inbox_notification_preferences(
                        workspace_id, grouping, sort_order, bell_enabled, global_content_mode,
                        global_row_state_filter, pane_content_mode, pane_row_state_filter, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    workspaceId.uuidString, "unsupported", "oldestFirst", 1,
                    "activity", "all", "all", "unreadOnly", 1,
                ]
            )
        }
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let inboxPreferences = InboxNotificationPrefsAtom()

        await makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences
        ).restoreAsync(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == "cursor")
        #expect(repoExplorerPreferences.groupingMode == .repo)
        #expect(repoExplorerPreferences.sortOrder == .ascending)
        #expect(repoExplorerPreferences.repoVisibilityMode == .all)
        #expect(inboxPreferences.grouping == .byTab)
        #expect(inboxPreferences.sort == .newestFirst)
        #expect(!inboxPreferences.bellEnabled)
        #expect(inboxPreferences.globalInboxContentMode == .rollUpAlerts)
        #expect(inboxPreferences.globalInboxRowStateFilter == .unreadOnly)
        #expect(inboxPreferences.paneInboxContentMode == .rollUpAlerts)
        #expect(inboxPreferences.paneInboxRowStateFilter == .unreadOnly)
    }

    @Test
    func unavailableLocalDatabaseDefaultsWithoutBlockingAndReportsRecovery() async throws {
        let workspaceId = UUID()
        let datastore = try makeFailingDatastore()
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let inboxPreferences = InboxNotificationPrefsAtom()
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.pane)
        inboxPreferences.setBellEnabled(true)
        var recoveryEvents: [PersistenceRecoveryEvent] = []

        await makeStore(
            datastore: datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences,
            recoveryReporter: { recoveryEvents.append($0) }
        ).restoreAsync(for: workspaceId)

        assertDefaultSettings(
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences
        )
        #expect(
            recoveryEvents.contains(
                .init(store: .workspaceSettings, workspaceId: workspaceId, recovery: .resetToDefaults)
            )
        )
    }

    @Test
    func observedSettingsMutationsAutosaveSettledTypedValues() async throws {
        let workspaceId = UUID()
        let fixture = try makeFixture()
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let inboxPreferences = InboxNotificationPrefsAtom()
        let clock = TestPushClock()
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.pane)
        repoExplorerPreferences.setSortOrder(.descending)
        inboxPreferences.setGrouping(.byRepo)
        inboxPreferences.setBellEnabled(true)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))
        await store.waitForPendingAutosave()

        let repository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: fixture.localDatabaseQueue
        )
        #expect(try repository.fetchEditorPreferences().bookmarkedEditorId == "cursor")
        #expect(try repository.fetchRepoExplorerPreferences().groupingMode == .pane)
        #expect(try repository.fetchRepoExplorerPreferences().sortOrder == .descending)
        #expect(try repository.fetchInboxNotificationPreferences().grouping == .byRepo)
        #expect(try repository.fetchInboxNotificationPreferences().bellEnabled)
    }

    @Test
    func restoreCancelsPendingDebouncedSaveForPreviousWorkspace() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        let fixture = try makeFixture()
        let editorPreference = EditorPreferenceAtom()
        let clock = TestPushClock()
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceAId)
        store.startObserving()
        editorPreference.setBookmarkedEditor("workspace-a")
        await clock.waitForPendingSleepCount()

        await store.restoreAsync(for: workspaceBId)
        clock.advance(by: .milliseconds(10))
        await store.waitForPendingAutosave()

        let workspaceARepository = WorkspaceLocalRepository(
            workspaceId: workspaceAId,
            databaseWriter: fixture.localDatabaseQueue
        )
        #expect(try workspaceARepository.fetchEditorPreferences() == .default)
    }

    @Test
    func flushFailureReportsSaveFailedRecovery() async throws {
        let workspaceId = UUID()
        let datastore = try makeFailingDatastore()
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = makeStore(
            datastore: datastore,
            recoveryReporter: { recoveryEvents.append($0) }
        )

        await #expect(throws: Error.self) {
            try await store.flush(for: workspaceId)
        }

        #expect(
            recoveryEvents.contains(
                .init(store: .workspaceSettings, workspaceId: workspaceId, recovery: .saveFailed)
            )
        )
    }

    @Test
    func autosaveObservationStateIsExplicitlyArmed() async throws {
        let fixture = try makeFixture()
        let store = makeStore(datastore: fixture.datastore)

        #expect(!store.isAutosaveObservationActive)
        await store.restoreAsync(for: UUID())
        #expect(!store.isAutosaveObservationActive)
        store.startObserving()
        #expect(store.isAutosaveObservationActive)
    }

    private func makeStore(
        datastore: WorkspaceSQLiteDatastore,
        editorPreference: EditorPreferenceAtom = EditorPreferenceAtom(),
        repoExplorerPreferences: RepoExplorerSidebarPrefsAtom = RepoExplorerSidebarPrefsAtom(),
        inboxPreferences: InboxNotificationPrefsAtom = InboxNotificationPrefsAtom(),
        persistDebounceDuration: Duration = .zero,
        clock: (any Clock<Duration> & Sendable)? = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) -> WorkspaceSettingsStore {
        WorkspaceSettingsStore(
            editorPreferenceAtom: editorPreference,
            repoExplorerSidebarPrefsAtom: repoExplorerPreferences,
            inboxNotificationPrefsAtom: inboxPreferences,
            sqliteDatastore: datastore,
            persistDebounceDuration: persistDebounceDuration,
            clock: clock,
            recoveryReporter: recoveryReporter
        )
    }

    private func makeFixture() throws -> SettingsFixture {
        let localDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(localDatabaseQueue)
        let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
        try coreRepository.migrate()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localDatabaseQueue)
            }
        )
        return .init(datastore: datastore, localDatabaseQueue: localDatabaseQueue)
    }

    private func makeFailingDatastore() throws -> WorkspaceSQLiteDatastore {
        let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
        try coreRepository.migrate()
        return WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw CocoaError(.fileNoSuchFile) }
        )
    }

    private func assertDefaultSettings(
        editorPreference: EditorPreferenceAtom,
        repoExplorerPreferences: RepoExplorerSidebarPrefsAtom,
        inboxPreferences: InboxNotificationPrefsAtom
    ) {
        #expect(editorPreference.bookmarkedEditorId == nil)
        #expect(repoExplorerPreferences.groupingMode == .repo)
        #expect(repoExplorerPreferences.sortOrder == .ascending)
        #expect(repoExplorerPreferences.repoVisibilityMode == .all)
        #expect(inboxPreferences.grouping == .byTab)
        #expect(inboxPreferences.sort == .newestFirst)
        #expect(!inboxPreferences.bellEnabled)
        #expect(inboxPreferences.globalInboxContentMode == .rollUpAlerts)
        #expect(inboxPreferences.globalInboxRowStateFilter == .unreadOnly)
        #expect(inboxPreferences.paneInboxContentMode == .rollUpAlerts)
        #expect(inboxPreferences.paneInboxRowStateFilter == .unreadOnly)
    }
}

private struct SettingsFixture {
    let datastore: WorkspaceSQLiteDatastore
    let localDatabaseQueue: DatabaseQueue
}
