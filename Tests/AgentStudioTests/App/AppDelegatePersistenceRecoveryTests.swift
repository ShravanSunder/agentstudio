import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AppDelegate persistence recovery")
struct AppDelegatePersistenceRecoveryTests {
    @Test("boot-time recovery events flush into inbox after inbox store loads")
    func bootTimeRecoveryEventsFlushIntoInboxAfterInboxStoreLoads() {
        let delegate = AppDelegate()
        delegate.inboxNotificationAtom = InboxNotificationAtom()
        delegate.inboxNotificationPrefsAtom = InboxNotificationPrefsAtom()
        let event = PersistenceRecoveryEvent(
            store: .sidebarCache,
            workspaceId: UUID(),
            recovery: .quarantinedAndReset,
            quarantinedFilename: "workspace.sidebar-cache.corrupt.json"
        )

        delegate.recordPersistenceRecovery(event)
        #expect(delegate.inboxNotificationAtom.notifications.isEmpty)

        delegate.hasLoadedInboxNotificationStore = true
        delegate.flushPersistenceRecoveryNotifications()

        #expect(delegate.pendingPersistenceRecoveryEvents.isEmpty)
        #expect(delegate.inboxNotificationAtom.notifications.count == 1)
        #expect(delegate.inboxNotificationAtom.notifications.first?.kind == .persistenceRecovery)
    }
}
