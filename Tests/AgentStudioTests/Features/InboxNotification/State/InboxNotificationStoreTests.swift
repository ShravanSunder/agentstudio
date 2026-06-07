import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationStore")
struct InboxNotificationStoreTests {
    private func makeTempURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("notification-inbox.json")
    }

    private func makeSQLiteAdapter(
        workspaceId: UUID,
        fixture: InboxNotificationSQLiteRepositoryFixture
    ) throws -> InboxNotificationSQLiteDatastoreAdapter {
        let localBackend = WorkspaceLocalSQLiteStoreBackend { _ in
            WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: fixture.databaseQueue)
        }
        return InboxNotificationSQLiteDatastoreAdapter(
            workspaceId: workspaceId,
            datastore: try workspaceSQLiteDatastore(from: localBackend)
        )
    }

    @Test("roundtrip: save + load returns equal notifications")
    func roundtrip() async throws {
        let url = makeTempURL()
        let atom1 = InboxNotificationAtom()
        let prefs1 = InboxNotificationPrefsAtom()
        let sidebarMemory1 = InboxSidebarMemoryAtom()
        let sidebarState1 = InboxSidebarState(memoryAtom: sidebarMemory1)
        let clock = TestPushClock()
        let store1 = InboxNotificationStore(
            inboxAtom: atom1,
            prefsAtom: prefs1,
            sidebarState: sidebarState1,
            fileURL: url,
            clock: clock
        )

        let note = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: .agentDesktopNotification,
            title: "Test",
            body: nil,
            source: .pane(.init(paneId: UUID())),
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        atom1.append(note)
        prefs1.setGrouping(.byRepo)
        prefs1.setSort(.oldestFirst)
        prefs1.setBellEnabled(true)
        sidebarMemory1.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        try await store1.save()

        let atom2 = InboxNotificationAtom()
        let prefs2 = InboxNotificationPrefsAtom()
        let sidebarState2 = InboxSidebarState()
        let store2 = InboxNotificationStore(
            inboxAtom: atom2,
            prefsAtom: prefs2,
            sidebarState: sidebarState2,
            fileURL: url,
            clock: clock
        )
        try await store2.loadAsync()

        #expect(atom2.notifications.count == 1)
        #expect(atom2.notifications[0].id == note.id)
        #expect(prefs2.grouping == .byTab)
        #expect(prefs2.sort == .newestFirst)
        #expect(prefs2.bellEnabled == false)
        #expect(sidebarState2.collapsedGroups == [InboxNotificationGroupKey("repo:agent-studio")])
    }

    @Test("flush and restore round trip notifications and collapsed groups through local SQLite")
    func flushAndRestoreRoundTripThroughLocalSQLite() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let atom1 = InboxNotificationAtom()
        let prefs1 = InboxNotificationPrefsAtom()
        let sidebarState1 = InboxSidebarState()
        let store1 = InboxNotificationStore(
            inboxAtom: atom1,
            prefsAtom: prefs1,
            sidebarState: sidebarState1,
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )
        let note = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 42),
            kind: .agentDesktopNotification,
            title: "SQLite",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        atom1.append(note)
        prefs1.setGrouping(.byRepo)
        sidebarState1.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        try await store1.save()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try fixture.repository.fetchNotifications().map(\.id) == [note.id])
        #expect(try fixture.repository.fetchCollapsedGroups() == [InboxNotificationGroupKey("repo:agent-studio")])

        let atom2 = InboxNotificationAtom()
        let prefs2 = InboxNotificationPrefsAtom()
        let sidebarState2 = InboxSidebarState()
        let store2 = InboxNotificationStore(
            inboxAtom: atom2,
            prefsAtom: prefs2,
            sidebarState: sidebarState2,
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )
        try await store2.loadAsync()

        #expect(atom2.notifications.map(\.id) == [note.id])
        #expect(sidebarState2.collapsedGroups == [InboxNotificationGroupKey("repo:agent-studio")])
        #expect(prefs2.grouping == .byTab)
    }

    @Test("SQLite restore imports legacy JSON once when the inbox lane is missing")
    func sqliteRestoreImportsLegacyJSONOnceWhenInboxLaneIsMissing() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let legacyAtom = InboxNotificationAtom()
        let legacySidebarState = InboxSidebarState()
        let legacyStore = InboxNotificationStore(
            inboxAtom: legacyAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: legacySidebarState,
            fileURL: url
        )
        let note = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 84),
            kind: .agentDesktopNotification,
            title: "Legacy",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        legacyAtom.append(note)
        legacySidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:legacy"), isCollapsed: true)
        try await legacyStore.save()

        let atom = InboxNotificationAtom()
        let sidebarState = InboxSidebarState()
        let sqliteStore = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: sidebarState,
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )
        let loadOutcome = try await sqliteStore.loadAsync()

        #expect(atom.notifications.map(\.id) == [note.id])
        #expect(sidebarState.collapsedGroups == [InboxNotificationGroupKey("repo:legacy")])
        #expect(loadOutcome == .legacyFileImportedIntoSQLite)
        #expect(loadOutcome.hasMaterializedLegacyFile)
        #expect(try fixture.repository.fetchNotifications().map(\.id) == [note.id])
        #expect(try fixture.repository.fetchCollapsedGroups() == [InboxNotificationGroupKey("repo:legacy")])
        #expect(try fixture.repository.hasPersistedState())
        #expect(try fixture.repository.hasMaterializedLegacyImport())
    }

    @Test("SQLite restore does not resurrect stale legacy JSON after an empty flush")
    func sqliteRestoreDoesNotResurrectStaleLegacyJSONAfterEmptyFlush() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let staleAtom = InboxNotificationAtom()
        staleAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 120),
                kind: .agentDesktopNotification,
                title: "Stale",
                body: nil,
                source: .global,
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        try await InboxNotificationStore(
            inboxAtom: staleAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            fileURL: url
        ).save()
        let emptyStore = InboxNotificationStore(
            inboxAtom: InboxNotificationAtom(),
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: InboxSidebarState(),
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )

        try await emptyStore.save()
        try await emptyStore.loadAsync()

        #expect(emptyStore.inboxAtom.notifications.isEmpty)
        #expect(emptyStore.sidebarState.collapsedGroups.isEmpty)
        #expect(try fixture.repository.hasPersistedState())
    }

    @Test("SQLite persisted inbox snapshot reports non-materialized legacy outcome")
    func sqlitePersistedInboxSnapshotReportsNonMaterializedLegacyOutcome() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let legacyAtom = InboxNotificationAtom()
        legacyAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 121),
                kind: .agentDesktopNotification,
                title: "Legacy",
                body: nil,
                source: .global,
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        try await InboxNotificationStore(
            inboxAtom: legacyAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            fileURL: url
        ).save()
        let sqliteNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 122),
            kind: .agentDesktopNotification,
            title: "SQLite",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        try fixture.repository.replaceSnapshot(
            notifications: [sqliteNotification],
            collapsedGroups: [InboxNotificationGroupKey("repo:sqlite")]
        )
        let atom = InboxNotificationAtom()
        let sidebarState = InboxSidebarState()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: sidebarState,
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture),
            allowLegacyFileImport: true
        )

        let loadOutcome = try await store.loadAsync()

        #expect(loadOutcome == .sqliteSnapshot)
        #expect(!loadOutcome.hasMaterializedLegacyFile)
        #expect(atom.notifications.map(\.id) == [sqliteNotification.id])
        #expect(!atom.notifications.map(\.id).contains(legacyAtom.notifications.single?.id ?? UUID()))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try !fixture.repository.hasMaterializedLegacyImport())
    }

    @Test("SQLite missing inbox lane after import resets instead of replaying legacy JSON")
    func sqliteMissingInboxLaneAfterImportResetsInsteadOfReplayingLegacyJSON() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let staleNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 130),
            kind: .agentDesktopNotification,
            title: "Stale",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let staleAtom = InboxNotificationAtom()
        let staleSidebarState = InboxSidebarState()
        staleAtom.append(staleNotification)
        staleSidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:stale"), isCollapsed: true)
        try await InboxNotificationStore(
            inboxAtom: staleAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: staleSidebarState,
            fileURL: url
        ).save()
        let sqliteNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 131),
            kind: .agentDesktopNotification,
            title: "SQLite",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        try fixture.repository.replaceSnapshot(
            notifications: [sqliteNotification],
            collapsedGroups: [InboxNotificationGroupKey("repo:sqlite")]
        )
        try await fixture.databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM local_notification_inbox_item WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
            try database.execute(
                sql: "DELETE FROM local_notification_inbox_collapsed_group WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
            try database.execute(
                sql: """
                    DELETE FROM local_persistence_lane_marker
                    WHERE workspace_id = ? AND lane = 'notification_inbox'
                    """,
                arguments: [workspaceId.uuidString]
            )
        }
        let atom = InboxNotificationAtom()
        let sidebarState = InboxSidebarState()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: sidebarState,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 },
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture),
            allowLegacyFileImport: false
        )

        try await store.loadAsync()

        #expect(atom.notifications.isEmpty)
        #expect(!atom.notifications.map(\.id).contains(staleNotification.id))
        #expect(sidebarState.collapsedGroups.isEmpty)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .resetToDefaults)
    }

    @Test("SQLite persisted inbox snapshot wins even when legacy import is blocked")
    func sqlitePersistedInboxSnapshotWinsEvenWhenLegacyImportIsBlocked() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let sqliteNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 220),
            kind: .agentDesktopNotification,
            title: "SQLite Snapshot",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        try fixture.repository.replaceSnapshot(
            notifications: [sqliteNotification],
            collapsedGroups: [InboxNotificationGroupKey("repo:sqlite")]
        )
        let atom = InboxNotificationAtom()
        let sidebarState = InboxSidebarState()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: sidebarState,
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture),
            allowLegacyFileImport: false
        )

        try await store.loadAsync()

        #expect(atom.notifications.map(\.id) == [sqliteNotification.id])
        #expect(sidebarState.collapsedGroups == [InboxNotificationGroupKey("repo:sqlite")])
    }

    @Test("SQLite load failure reports recovery and does not apply stale legacy JSON")
    func sqliteLoadFailureReportsRecoveryAndDoesNotApplyStaleLegacyJSON() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let staleNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 140),
            kind: .agentDesktopNotification,
            title: "Stale",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let staleAtom = InboxNotificationAtom()
        staleAtom.append(staleNotification)
        try await InboxNotificationStore(
            inboxAtom: staleAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            fileURL: url
        ).save()
        try fixture.repository.replaceSnapshot(notifications: [], collapsedGroups: [])
        try await fixture.databaseQueue.write { database in
            try database.execute(sql: "DROP TABLE local_notification_inbox_item")
        }
        let atom = InboxNotificationAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: InboxNotificationPrefsAtom(),
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 },
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )

        do {
            try await store.loadAsync()
            Issue.record("Expected inbox SQLite load to fail")
        } catch {
            // Expected path.
        }

        #expect(atom.notifications.isEmpty)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .resetToDefaults)
    }

    @Test("load resets runtime-only pending sidebar filter")
    func loadResetsRuntimeOnlyPendingSidebarFilter() async throws {
        let url = makeTempURL()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        let sidebarState = InboxSidebarState()
        let store = InboxNotificationStore(
            inboxAtom: inboxAtom,
            prefsAtom: prefsAtom,
            sidebarState: sidebarState,
            fileURL: url
        )

        sidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        try await store.save()
        sidebarState.setPendingFilter(.repo(id: UUID()))

        try await store.loadAsync()

        #expect(sidebarState.peekPendingFilter() == nil)
        #expect(sidebarState.collapsedGroups == [InboxNotificationGroupKey("repo:agent-studio")])
    }

    @Test("save writes schema version three for feature sidebar state")
    func saveWritesSchemaVersionThreeForFeatureSidebarState() async throws {
        let url = makeTempURL()
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let sidebarState = InboxSidebarState()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            sidebarState: sidebarState,
            fileURL: url
        )

        sidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        sidebarState.setPendingFilter(.repo(id: UUID()))
        try await store.save()

        let data = try Data(contentsOf: url)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["schemaVersion"] as? Int == 3)
        let sidebarStatePayload = try #require(payload["sidebarState"] as? [String: Any])
        #expect(sidebarStatePayload["collapsedGroups"] != nil)
        #expect(sidebarStatePayload["pendingFilter"] == nil)
    }

    @Test("load accepts schema one pane source without denormalized display fields")
    func loadAcceptsSchemaOnePaneSourceWithoutDenormalizedDisplayFields() async throws {
        let url = makeTempURL()
        let paneId = UUID()
        let notificationId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "notifications": [
                    {
                        "id": "\(notificationId.uuidString)",
                        "timestamp": "2026-05-01T12:00:00Z",
                        "kind": "agentRpc",
                        "title": "Legacy",
                        "body": null,
                        "source": {
                            "pane": {
                                "_0": {
                                    "paneId": "\(paneId.uuidString)"
                                }
                            }
                        },
                        "isRead": false,
                        "isDismissedFromPaneInbox": false
                    }
                ],
                "prefs": {
                    "grouping": "none",
                    "sort": "newestFirst",
                    "bellEnabled": false
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )

        try await store.loadAsync()

        let notification = try #require(atom.notifications.first)
        #expect(notification.id == notificationId)
        guard case .pane(let paneSource) = notification.source else {
            Issue.record("Expected legacy notification to decode as pane source")
            return
        }
        #expect(paneSource.paneId == paneId)
        #expect(paneSource.paneRole == .main)
        #expect(paneSource.tabDisplayLabel == nil)
        #expect(paneSource.runtimeDisplayLabel == nil)
        let display = InboxNotificationSourceDisplay(notification: notification)
        #expect(display.sourceLine == "Pane event")
        #expect(display.groupLabel(for: .byRepo) == "Pane")
    }

    @Test("load from missing file uses defaults")
    func loadMissingFileUsesDefaults() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID()).json")
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )

        try await store.loadAsync()

        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byTab)
        #expect(prefs.bellEnabled == false)
    }

    @Test("load from corrupt file quarantines the file before falling back to defaults")
    func loadCorruptFileQuarantinesBeforeDefaulting() async throws {
        let url = makeTempURL()
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 }
        )

        try await store.loadAsync()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byTab)
        #expect(prefs.bellEnabled == false)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.lastPathComponent.hasPrefix("notification-inbox.corrupt-")
        }
        #expect(quarantinedFiles.count == 1)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
        #expect(reportedRecovery?.quarantinedFilename == quarantinedFiles.first?.lastPathComponent)
    }

    @Test("load from unknown schema quarantines instead of interpreting as v1")
    func loadUnknownSchemaQuarantinesInsteadOfInterpretingAsV1() async throws {
        let url = makeTempURL()
        let json = """
            {
                "schemaVersion": 99999,
                "notifications": [],
                "prefs": {
                    "grouping": "byRepo",
                    "sort": "newestFirst",
                    "bellEnabled": true
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 }
        )

        try await store.loadAsync()

        #expect(prefs.grouping == .byTab)
        #expect(prefs.bellEnabled == false)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
    }

    @Test("load accepts schema two payloads from sibling inbox builds")
    func loadAcceptsSchemaTwoPayloadsFromSiblingInboxBuilds() async throws {
        let url = makeTempURL()
        let notificationId = UUID()
        let json = """
            {
                "schemaVersion": 2,
                "notifications": [
                    {
                        "id": "\(notificationId.uuidString)",
                        "timestamp": "2026-05-12T10:21:49Z",
                        "kind": "persistenceRecovery",
                        "title": "Notification inbox reset",
                        "body": "The saved file could not be loaded, so it was moved aside and defaults were used.",
                        "source": { "global": {} },
                        "isRead": true,
                        "isDismissedFromPaneInbox": true
                    }
                ],
                "prefs": {
                    "grouping": "none",
                    "sort": "newestFirst",
                    "bellEnabled": false
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 }
        )

        try await store.loadAsync()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(atom.notifications.map(\.id) == [notificationId])
        #expect(atom.notifications.first?.kind == .persistenceRecovery)
        #expect(reportedRecovery == nil)
    }

    @Test("load quarantines bad notification slice")
    func loadQuarantinesBadNotificationSlice() async throws {
        let url = makeTempURL()
        let json = """
            {
                "schemaVersion": 1,
                "notifications": 42,
                "prefs": {
                    "grouping": "byRepo",
                    "sort": "oldestFirst",
                    "bellEnabled": true
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            recoveryReporter: { reportedRecovery = $0 }
        )

        try await store.loadAsync()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byTab)
        #expect(prefs.sort == .newestFirst)
        #expect(!prefs.bellEnabled)
        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
    }

    @Test("save cancels pending debounced save before writing final snapshot")
    func saveCancelsPendingDebouncedSaveBeforeWritingFinalSnapshot() async throws {
        let url = makeTempURL()
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let clock = TestPushClock()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            clock: clock,
            debounceDuration: .milliseconds(10)
        )
        let staleNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: .agentDesktopNotification,
            title: "Stale",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
        let finalNotification = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: .agentDesktopNotification,
            title: "Final",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        atom.append(staleNotification)
        store.scheduleDebouncedSave()
        await clock.waitForPendingSleepCount()
        atom.append(finalNotification)
        try await store.save()
        #expect(clock.pendingSleepCount == 0)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        let restoredAtom = InboxNotificationAtom()
        let restoredStore = InboxNotificationStore(
            inboxAtom: restoredAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            fileURL: url
        )
        try await restoredStore.loadAsync()

        #expect(restoredAtom.notifications.map(\.id) == [staleNotification.id, finalNotification.id])
    }

    @Test("load leaves legacy preference fields to settings store")
    func loadLeavesLegacyPreferenceFieldsToSettingsStore() async throws {
        let url = makeTempURL()
        let json = """
            {
                "schemaVersion": 1,
                "notifications": [],
                "prefs": {
                    "grouping": "not-a-group",
                    "sort": "oldestFirst",
                    "bellEnabled": true
                }
            }
            """
        try Data(json.utf8).write(to: url, options: .atomic)
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        prefs.setGrouping(.byRepo)
        prefs.setSort(.newestFirst)
        prefs.setBellEnabled(false)
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url
        )

        try await store.loadAsync()

        #expect(atom.notifications.isEmpty)
        #expect(prefs.grouping == .byRepo)
        #expect(prefs.sort == .newestFirst)
        #expect(!prefs.bellEnabled)
    }

    @Test("debounce clock failure still saves immediately")
    func debounceClockFailureStillSavesImmediately() async throws {
        let url = makeTempURL()
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: url,
            clock: FailingClock()
        )

        atom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(),
                kind: .agentDesktopNotification,
                title: "Saved",
                body: nil,
                source: .global,
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        store.scheduleDebouncedSave()

        await assertEventuallyMain("debounce failure should fall through to save") {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    @Test("save failure reports persistence recovery event")
    func saveFailureReportsPersistenceRecoveryEvent() async {
        let parentFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-save-parent-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: parentFileURL, options: .atomic)
        let fileURL = parentFileURL.appending(path: "notification-inbox.json")
        let atom = InboxNotificationAtom()
        let prefs = InboxNotificationPrefsAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = InboxNotificationStore(
            inboxAtom: atom,
            prefsAtom: prefs,
            fileURL: fileURL,
            recoveryReporter: { reportedRecovery = $0 }
        )

        await #expect(throws: Error.self) {
            try await store.save()
        }

        #expect(reportedRecovery?.store == .notificationInbox)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }

    private struct FailingClock: Clock {
        struct Failure: Error {}

        private let base = ContinuousClock()

        var now: ContinuousClock.Instant {
            base.now
        }

        var minimumResolution: Duration {
            base.minimumResolution
        }

        func sleep(
            until deadline: ContinuousClock.Instant,
            tolerance: Duration? = nil
        ) async throws {
            throw Failure()
        }
    }
}
