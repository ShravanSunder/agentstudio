import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationStore")
struct InboxNotificationStoreTests {
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

    private func makeStore(
        workspaceId: UUID,
        fixture: InboxNotificationSQLiteRepositoryFixture,
        inboxAtom: InboxNotificationAtom = .init(),
        sidebarState: InboxSidebarState = .init(),
        clock: (any Clock<Duration> & Sendable)? = nil,
        debounceDuration: Duration = .milliseconds(500),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) throws -> InboxNotificationStore {
        InboxNotificationStore(
            inboxAtom: inboxAtom,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: sidebarState,
            clock: clock,
            debounceDuration: debounceDuration,
            recoveryReporter: recoveryReporter,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )
    }

    @Test("save and load round trip notifications and collapsed groups through SQLite")
    func saveAndLoadRoundTripThroughSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let sourceAtom = InboxNotificationAtom()
        let sourceSidebar = InboxSidebarState()
        let notification = makeNotification(title: "SQLite")
        sourceAtom.append(notification)
        sourceSidebar.setGroupCollapsed(InboxNotificationGroupKey("repo:agent-studio"), isCollapsed: true)
        let sourceStore = try makeStore(
            workspaceId: workspaceId,
            fixture: fixture,
            inboxAtom: sourceAtom,
            sidebarState: sourceSidebar
        )

        try await sourceStore.save()

        let restoredAtom = InboxNotificationAtom()
        let restoredSidebar = InboxSidebarState()
        let restoredStore = try makeStore(
            workspaceId: workspaceId,
            fixture: fixture,
            inboxAtom: restoredAtom,
            sidebarState: restoredSidebar
        )
        let outcome = await restoredStore.loadAsync()

        #expect(outcome == .sqliteSnapshot)
        #expect(restoredAtom.notifications.map(\.id) == [notification.id])
        #expect(restoredSidebar.collapsedGroups == [InboxNotificationGroupKey("repo:agent-studio")])
    }

    @Test("empty SQLite lane loads deterministic defaults and resets runtime filter")
    func emptySQLiteLaneLoadsDefaultsAndResetsRuntimeFilter() async throws {
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(makeNotification(title: "Stale live state"))
        let sidebarState = InboxSidebarState()
        sidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:stale"), isCollapsed: true)
        sidebarState.setPendingFilter(.repo(id: UUID()))
        let store = try makeStore(
            workspaceId: workspaceId,
            fixture: fixture,
            inboxAtom: inboxAtom,
            sidebarState: sidebarState
        )

        let outcome = await store.loadAsync()

        #expect(outcome == .sqliteSnapshot)
        #expect(inboxAtom.notifications.isEmpty)
        #expect(sidebarState.collapsedGroups.isEmpty)
        #expect(sidebarState.peekPendingFilter() == nil)
    }

    @Test("unavailable SQLite lane defaults and reports recovery")
    func unavailableSQLiteLaneDefaultsAndReportsRecovery() async throws {
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        try await fixture.databaseQueue.write { database in
            try database.execute(sql: "DROP TABLE local_notification_inbox_item")
        }
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(makeNotification(title: "Stale live state"))
        let sidebarState = InboxSidebarState()
        sidebarState.setGroupCollapsed(InboxNotificationGroupKey("repo:stale"), isCollapsed: true)
        var reportedRecoveries: [PersistenceRecoveryEvent] = []
        let store = try makeStore(
            workspaceId: workspaceId,
            fixture: fixture,
            inboxAtom: inboxAtom,
            sidebarState: sidebarState,
            recoveryReporter: { reportedRecoveries.append($0) }
        )

        let outcome = await store.loadAsync()

        #expect(outcome == .defaulted)
        #expect(inboxAtom.notifications.isEmpty)
        #expect(sidebarState.collapsedGroups.isEmpty)
        #expect(
            reportedRecoveries.contains { event in
                event.store == .notificationInbox && event.recovery == .resetToDefaults
            })
    }

    @Test("explicit save cancels a pending debounced SQLite save")
    func explicitSaveCancelsPendingDebouncedSQLiteSave() async throws {
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let inboxAtom = InboxNotificationAtom()
        let clock = TestPushClock()
        let store = try makeStore(
            workspaceId: workspaceId,
            fixture: fixture,
            inboxAtom: inboxAtom,
            clock: clock,
            debounceDuration: .milliseconds(10)
        )
        let first = makeNotification(title: "First")
        let second = makeNotification(title: "Second")
        inboxAtom.append(first)
        store.scheduleDebouncedSave()
        await clock.waitForPendingSleepCount()
        inboxAtom.append(second)

        try await store.save()
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        #expect(clock.pendingSleepCount == 0)
        #expect(try fixture.repository.fetchNotifications().map(\.id) == [first.id, second.id])
    }

    @Test("SQLite save failure reports persistence recovery")
    func sqliteSaveFailureReportsPersistenceRecovery() async throws {
        let workspaceId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        try await fixture.databaseQueue.write { database in
            try database.execute(sql: "DROP TABLE local_notification_inbox_item")
        }
        var reportedRecoveries: [PersistenceRecoveryEvent] = []
        let store = try makeStore(
            workspaceId: workspaceId,
            fixture: fixture,
            recoveryReporter: { reportedRecoveries.append($0) }
        )

        await #expect(throws: Error.self) {
            try await store.save()
        }

        #expect(
            reportedRecoveries.contains { event in
                event.store == .notificationInbox && event.recovery == .saveFailed
            })
    }

    private func makeNotification(title: String) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 42),
            kind: .agentDesktopNotification,
            title: title,
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
