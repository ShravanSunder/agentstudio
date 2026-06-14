import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationStore SQLite round trips")
struct InboxNotificationStoreSQLiteRoundTripTests {
    @Test("read and pane-dismiss state round trips through local SQLite")
    func readAndPaneDismissStateRoundTripsThroughLocalSQLite() async throws {
        let url = makeTempURL()
        let workspaceId = UUID()
        let paneId = UUID()
        let notificationId = UUID()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let atom1 = InboxNotificationAtom()
        let store1 = InboxNotificationStore(
            inboxAtom: atom1,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: InboxSidebarState(),
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )
        let notification = InboxNotification(
            id: notificationId,
            timestamp: Date(timeIntervalSince1970: 42),
            kind: .agentDesktopNotification,
            title: "Observed",
            body: nil,
            source: .pane(.init(paneId: paneId)),
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        atom1.append(notification)
        #expect(atom1.markRead(id: notificationId))
        #expect(atom1.dismissFromPaneInbox(id: notificationId))
        try await store1.save()

        let atom2 = InboxNotificationAtom()
        let store2 = InboxNotificationStore(
            inboxAtom: atom2,
            prefsAtom: InboxNotificationPrefsAtom(),
            sidebarState: InboxSidebarState(),
            fileURL: url,
            sqliteAdapter: try makeSQLiteAdapter(workspaceId: workspaceId, fixture: fixture)
        )
        try await store2.loadAsync()

        let restoredNotification = try #require(atom2.notifications.first)
        #expect(restoredNotification.id == notificationId)
        #expect(restoredNotification.isRead)
        #expect(restoredNotification.isDismissedFromPaneInbox)
        #expect(atom2.globalUnreadCount == 0)
        #expect(atom2.visiblePaneInboxUnreadCount(forPaneIds: [paneId]) == 0)
    }

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
}
