import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct WorkspaceSettingsStoreTests {
    @Test
    func flushAndRestoreRoundTripsTypedSQLiteSettings() async throws {
        let workspaceId = UUID()
        let fixture = try await makeFixture()
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
        #expect(restoredInboxPreferences.grouping == .byRepo)
        #expect(restoredInboxPreferences.sort == .oldestFirst)
        #expect(restoredInboxPreferences.bellEnabled)
        #expect(restoredInboxPreferences.globalInboxContentMode == .activity)
        #expect(restoredInboxPreferences.globalInboxRowStateFilter == .all)
        #expect(restoredInboxPreferences.paneInboxContentMode == .all)
        #expect(restoredInboxPreferences.paneInboxRowStateFilter == .unreadOnly)

        let repository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: fixture.localDatabaseQueue
        )
        #expect(
            try repository.fetchRepoExplorerPreferences().visibilityMode
                == SQLiteLocalUXStorage.repoExplorerVisibilityAll
        )
    }

    @Test
    func restoreMissingRowsAppliesTypedDefaults() async throws {
        let fixture = try await makeFixture()
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let inboxPreferences = InboxNotificationPrefsAtom()
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.pane)
        repoExplorerPreferences.setSortOrder(.descending)
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

    @Test(
        "one unavailable settings table defaults only its owning preference lane",
        arguments: SettingsPreferenceLane.allCases
    )
    func unavailableSettingsTableDefaultsOnlyItsOwningLane(
        _ unavailableLane: SettingsPreferenceLane
    ) async throws {
        let workspaceId = UUID()
        let fixture = try await makeFixture()
        let repository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: fixture.localDatabaseQueue
        )
        try repository.replaceEditorPreferences(
            .init(bookmarkedEditorId: "cursor"),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try repository.replaceRepoExplorerPreferences(
            try #require(
                WorkspaceLocalRepository.RepoExplorerPreferencesRecord.validated(
                    groupingMode: SQLiteLocalUXStorage.repoExplorerGroupingPane,
                    sortOrder: SQLiteLocalUXStorage.repoExplorerSortDescending,
                    visibilityMode: SQLiteLocalUXStorage.repoExplorerVisibilityAll
                )
            ),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try repository.replaceInboxNotificationPreferences(
            try #require(
                WorkspaceLocalRepository.InboxNotificationPreferencesRecord.validated(
                    grouping: SQLiteLocalUXStorage.inboxNotificationGroupingByRepo,
                    sortOrder: SQLiteLocalUXStorage.inboxNotificationSortOldestFirst,
                    bellEnabled: true,
                    globalFilter: .init(
                        contentMode: SQLiteLocalUXStorage.inboxNotificationContentActivity,
                        rowStateFilter: SQLiteLocalUXStorage.inboxNotificationRowStateAll
                    ),
                    paneFilter: .init(
                        contentMode: SQLiteLocalUXStorage.inboxNotificationContentAll,
                        rowStateFilter: SQLiteLocalUXStorage.inboxNotificationRowStateAll
                    )
                )
            ),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try await fixture.localDatabaseQueue.write { database in
            try database.execute(sql: "DROP TABLE \(unavailableLane.tableName)")
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

        #expect(editorPreference.bookmarkedEditorId == (unavailableLane == .editor ? nil : "cursor"))
        #expect(repoExplorerPreferences.groupingMode == (unavailableLane == .repoExplorer ? .repo : .pane))
        #expect(
            inboxPreferences.grouping
                == (unavailableLane == .inboxNotification ? .byTab : .byRepo)
        )
        let tableStillMissing = try await fixture.localDatabaseQueue.read { database in
            try !database.tableExists(unavailableLane.tableName)
        }
        #expect(tableStillMissing)
    }

    @Test
    func invalidPreferenceDefaultsWithoutHydrationWriteAndRepairsOnNextSave() async throws {
        let workspaceId = UUID()
        let fixture = try await makeFixture()
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
                    workspaceId.uuidString, "byRepo", "oldestFirst", 1,
                    "activity", "all", "all", "unreadOnly", 1,
                ]
            )
        }
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let inboxPreferences = InboxNotificationPrefsAtom()
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            inboxPreferences: inboxPreferences
        )

        await store.restoreAsync(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == "cursor")
        #expect(repoExplorerPreferences.groupingMode == .repo)
        #expect(repoExplorerPreferences.sortOrder == .ascending)
        #expect(inboxPreferences.grouping == .byRepo)
        #expect(inboxPreferences.sort == .oldestFirst)
        #expect(inboxPreferences.bellEnabled)
        #expect(inboxPreferences.globalInboxContentMode == .activity)
        #expect(inboxPreferences.globalInboxRowStateFilter == .all)
        #expect(inboxPreferences.paneInboxContentMode == .all)
        #expect(inboxPreferences.paneInboxRowStateFilter == .unreadOnly)

        let groupingAfterHydration = try await repoExplorerGrouping(
            workspaceId: workspaceId,
            databaseQueue: fixture.localDatabaseQueue
        )
        #expect(groupingAfterHydration == "unsupported")
        let repository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: fixture.localDatabaseQueue
        )
        #expect(
            try repository.fetchRepoExplorerPreferences().visibilityMode
                == SQLiteLocalUXStorage.repoExplorerVisibilityAll
        )

        editorPreference.setBookmarkedEditor("zed")
        try await store.flush(for: workspaceId)

        let groupingAfterSave = try await repoExplorerGrouping(
            workspaceId: workspaceId,
            databaseQueue: fixture.localDatabaseQueue
        )
        #expect(groupingAfterSave == "repo")
        #expect(try repository.fetchEditorPreferences().bookmarkedEditorId == "zed")
        #expect(
            try repository.fetchRepoExplorerPreferences().visibilityMode
                == SQLiteLocalUXStorage.repoExplorerVisibilityAll
        )
        #expect(
            try repository.fetchInboxNotificationPreferences().grouping
                == SQLiteLocalUXStorage.inboxNotificationGroupingByRepo
        )
    }

    @Test
    func unavailableLocalDatabaseDefaultsWithoutBlockingAndReportsRecovery() async throws {
        let workspaceId = UUID()
        let datastore = try await makeFailingDatastore()
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
        let fixture = try await makeFixture()
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
        #expect(try repository.fetchRepoExplorerPreferences().groupingMode == "pane")
        #expect(try repository.fetchRepoExplorerPreferences().sortOrder == "descending")
        #expect(try repository.fetchInboxNotificationPreferences().grouping == "byRepo")
        #expect(try repository.fetchInboxNotificationPreferences().bellEnabled)
    }

    @Test
    func restoreCancelsPendingDebouncedSaveForPreviousWorkspace() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        let fixture = try await makeFixture()
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
        let datastore = try await makeFailingDatastore()
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
        let fixture = try await makeFixture()
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

    private func makeFixture() async throws -> SettingsFixture {
        let localDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(localDatabaseQueue)
        let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
        try coreRepository.migrate()
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            preparedApplicationLocalRepository: WorkspaceLocalRepository(
                workspaceId: UUID(),
                databaseWriter: localDatabaseQueue
            )
        )
        return .init(datastore: datastore, localDatabaseQueue: localDatabaseQueue)
    }

    private func makeFailingDatastore() async throws -> WorkspaceSQLiteDatastore {
        let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
        try coreRepository.migrate()
        return try await preparedWorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            localUnavailable: .init(CocoaError(.fileNoSuchFile))
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

enum SettingsPreferenceLane: CaseIterable {
    case editor
    case repoExplorer
    case inboxNotification

    var tableName: String {
        switch self {
        case .editor:
            "local_editor_preferences"
        case .repoExplorer:
            "local_repo_explorer_preferences"
        case .inboxNotification:
            "local_inbox_notification_preferences"
        }
    }
}

private func repoExplorerGrouping(
    workspaceId: UUID,
    databaseQueue: DatabaseQueue
) async throws -> String? {
    try await databaseQueue.read { database in
        try String.fetchOne(
            database,
            sql: """
                SELECT grouping_mode
                FROM local_repo_explorer_preferences
                WHERE workspace_id = ?
                """,
            arguments: [workspaceId.uuidString]
        )
    }
}
