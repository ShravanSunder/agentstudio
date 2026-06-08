import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AppDelegate persistence recovery")
struct AppDelegatePersistenceRecoveryTests {
    @Test("boot-time recovery events flush into inbox after inbox store loads")
    func bootTimeRecoveryEventsFlushIntoInboxAfterInboxStoreLoads() {
        let delegate = AppDelegate()
        delegate.atomStore = AtomRegistry()
        let event = PersistenceRecoveryEvent(
            store: .sidebarCache,
            workspaceId: UUID(),
            recovery: .quarantinedAndReset,
            quarantinedFilename: "workspace.sidebar-cache.corrupt.json"
        )

        delegate.recordPersistenceRecovery(event)
        #expect(delegate.atomStore.inboxNotification.notifications.isEmpty)

        delegate.hasLoadedInboxNotificationStore = true
        delegate.flushPersistenceRecoveryNotifications()

        #expect(delegate.pendingPersistenceRecoveryEvents.isEmpty)
        #expect(delegate.atomStore.inboxNotification.notifications.count == 1)
        #expect(delegate.atomStore.inboxNotification.notifications.first?.kind == .persistenceRecovery)
    }

    @Test("duplicate unread recovery events do not flood inbox")
    func duplicateUnreadRecoveryEventsDoNotFloodInbox() {
        let delegate = AppDelegate()
        delegate.atomStore = AtomRegistry()
        delegate.hasLoadedInboxNotificationStore = true
        let workspaceId = UUID()
        let event = PersistenceRecoveryEvent(
            store: .workspace,
            workspaceId: workspaceId,
            recovery: .saveFailed
        )

        delegate.recordPersistenceRecovery(event)
        delegate.recordPersistenceRecovery(event)

        #expect(delegate.atomStore.inboxNotification.notifications.count == 1)
        #expect(delegate.atomStore.inboxNotification.notifications.first?.title == "Workspace save failed")
    }

    @Test("workspace recovery events for different workspaces do not collapse")
    func workspaceRecoveryEventsForDifferentWorkspacesDoNotCollapse() {
        let delegate = AppDelegate()
        delegate.atomStore = AtomRegistry()
        delegate.hasLoadedInboxNotificationStore = true
        let firstWorkspaceId = UUID()
        let secondWorkspaceId = UUID()

        delegate.recordPersistenceRecovery(
            .init(store: .workspace, workspaceId: firstWorkspaceId, recovery: .saveFailed)
        )
        delegate.recordPersistenceRecovery(
            .init(store: .workspace, workspaceId: secondWorkspaceId, recovery: .saveFailed)
        )

        #expect(delegate.atomStore.inboxNotification.notifications.count == 2)
        #expect(
            delegate.atomStore.inboxNotification.notifications.contains {
                $0.body?.contains(firstWorkspaceId.uuidString) == true
            }
        )
        #expect(
            delegate.atomStore.inboxNotification.notifications.contains {
                $0.body?.contains(secondWorkspaceId.uuidString) == true
            }
        )
    }
}
