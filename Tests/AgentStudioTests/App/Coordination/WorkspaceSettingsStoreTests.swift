import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
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
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences
        )
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.tab)
        repoExplorerPreferences.setSortOrder(.descending)

        try await store.flush(for: workspaceId)

        let restoredEditorPreference = EditorPreferenceAtom()
        let restoredRepoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        await makeStore(
            datastore: fixture.datastore,
            editorPreference: restoredEditorPreference,
            repoExplorerPreferences: restoredRepoExplorerPreferences
        ).restoreAsync(for: workspaceId)

        #expect(restoredEditorPreference.bookmarkedEditorId == "cursor")
        #expect(restoredRepoExplorerPreferences.groupingMode == .repo)
        #expect(restoredRepoExplorerPreferences.sortOrder == .descending)

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
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.pane)
        repoExplorerPreferences.setSortOrder(.descending)

        await makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences
        ).restoreAsync(for: UUID())

        assertDefaultSettings(
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences
        )
        #expect(repoExplorerPreferences.groupingMode == .pane)
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
                    sortOrder: SQLiteLocalUXStorage.repoExplorerSortDescending,
                    visibilityMode: SQLiteLocalUXStorage.repoExplorerVisibilityAll
                )
            ),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try await fixture.localDatabaseQueue.write { database in
            try database.execute(sql: "DROP TABLE \(unavailableLane.tableName)")
        }
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()

        await makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences
        ).restoreAsync(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == (unavailableLane == .editor ? nil : "cursor"))
        #expect(repoExplorerPreferences.groupingMode == .repo)
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
                        workspace_id, sort_order, visibility_mode, updated_at
                    ) VALUES (?, ?, ?, ?)
                    """,
                arguments: [workspaceId.uuidString, "unsupported", "favoritesOnly", 1]
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
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences
        )

        await store.restoreAsync(for: workspaceId)

        #expect(editorPreference.bookmarkedEditorId == "cursor")
        #expect(repoExplorerPreferences.groupingMode == .repo)
        #expect(repoExplorerPreferences.sortOrder == .ascending)

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
    func unrelatedSettingsLifecyclePreservesEveryInboxRowAndTimestamp() async throws {
        let workspaceId = UUID()
        let fixture = try await makeFixture()
        try await fixture.localDatabaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_inbox_notification_preferences(
                        workspace_id, grouping, sort_order, bell_enabled, global_content_mode,
                        global_row_state_filter, pane_content_mode, pane_row_state_filter, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    workspaceId.uuidString, "byRepo", "oldestFirst", 1,
                    "activity", "all", "all", "unreadOnly", 123.5,
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_notification_inbox_item(
                        workspace_id, id, timestamp, kind, title, body, source_kind,
                        is_read, is_dismissed_from_pane_inbox
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    workspaceId.uuidString, UUID().uuidString, 456.25, "agentRpc",
                    "Preserved notification", "Preserved body", "global", 0, 0,
                ]
            )
        }
        let before = try await inboxRetirementSnapshot(
            databaseQueue: fixture.localDatabaseQueue,
            workspaceId: workspaceId
        )
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        let clock = TestPushClock()
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )

        await store.restoreAsync(for: workspaceId)
        store.startObserving()
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setSortOrder(.descending)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))
        await store.waitForPendingAutosave()
        try await store.flush(for: workspaceId)

        let after = try await inboxRetirementSnapshot(
            databaseQueue: fixture.localDatabaseQueue,
            workspaceId: workspaceId
        )
        #expect(after == before)
    }

    @Test
    func unavailableLocalDatabaseDefaultsWithoutBlockingAndReportsRecovery() async throws {
        let workspaceId = UUID()
        let datastore = try await makeFailingDatastore()
        let editorPreference = EditorPreferenceAtom()
        let repoExplorerPreferences = RepoExplorerSidebarPrefsAtom()
        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.pane)
        var recoveryEvents: [PersistenceRecoveryEvent] = []

        await makeStore(
            datastore: datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            recoveryReporter: { recoveryEvents.append($0) }
        ).restoreAsync(for: workspaceId)

        assertDefaultSettings(
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences
        )
        #expect(repoExplorerPreferences.groupingMode == .pane)
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
        let clock = TestPushClock()
        let store = makeStore(
            datastore: fixture.datastore,
            editorPreference: editorPreference,
            repoExplorerPreferences: repoExplorerPreferences,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        editorPreference.setBookmarkedEditor("cursor")
        repoExplorerPreferences.setGroupingMode(.pane)
        repoExplorerPreferences.setSortOrder(.descending)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))
        await store.waitForPendingAutosave()

        let repository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: fixture.localDatabaseQueue
        )
        #expect(try repository.fetchEditorPreferences().bookmarkedEditorId == "cursor")
        #expect(try repository.fetchRepoExplorerPreferences().sortOrder == "descending")
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
        persistDebounceDuration: Duration = .zero,
        clock: (any Clock<Duration> & Sendable)? = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) -> WorkspaceSettingsStore {
        WorkspaceSettingsStore(
            editorPreferenceAtom: editorPreference,
            repoExplorerSidebarPrefsAtom: repoExplorerPreferences,
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
        repoExplorerPreferences: RepoExplorerSidebarPrefsAtom
    ) {
        #expect(editorPreference.bookmarkedEditorId == nil)
        #expect(repoExplorerPreferences.sortOrder == .ascending)
    }

    private func inboxRetirementSnapshot(
        databaseQueue: DatabaseQueue,
        workspaceId: UUID
    ) async throws -> InboxRetirementDatabaseSnapshot {
        try await databaseQueue.read { database in
            let preferences = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM local_inbox_notification_preferences
                    WHERE workspace_id = ? ORDER BY workspace_id
                    """,
                arguments: [workspaceId.uuidString]
            ).map(String.init(describing:))
            let history = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM local_notification_inbox_item
                    WHERE workspace_id = ? ORDER BY timestamp, id
                    """,
                arguments: [workspaceId.uuidString]
            ).map(String.init(describing:))
            let schema = try String.fetchAll(
                database,
                sql: """
                    SELECT COALESCE(sql, '') FROM sqlite_master
                    WHERE tbl_name IN (
                        'local_inbox_notification_preferences',
                        'local_notification_inbox_item'
                    )
                    ORDER BY type, name
                    """
            )
            return InboxRetirementDatabaseSnapshot(
                preferences: preferences,
                history: history,
                schema: schema
            )
        }
    }
}

private struct SettingsFixture {
    let datastore: WorkspaceSQLiteDatastore
    let localDatabaseQueue: DatabaseQueue
}

private struct InboxRetirementDatabaseSnapshot: Equatable {
    let preferences: [String]
    let history: [String]
    let schema: [String]
}

enum SettingsPreferenceLane: CaseIterable {
    case editor
    case repoExplorer

    var tableName: String {
        switch self {
        case .editor:
            "local_editor_preferences"
        case .repoExplorer:
            "local_repo_explorer_preferences"
        }
    }
}
