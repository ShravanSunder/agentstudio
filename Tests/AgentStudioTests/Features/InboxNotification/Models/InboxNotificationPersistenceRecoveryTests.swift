import Foundation
import Testing

@testable import AgentStudio

@Suite("Inbox notification persistence recovery")
struct InboxNotificationPersistenceRecoveryTests {
    @Test("factory creates visible global recovery notification")
    func factoryCreatesVisibleGlobalRecoveryNotification() {
        let workspaceId = UUID()
        let event = PersistenceRecoveryEvent(
            store: .sidebarCache,
            workspaceId: workspaceId,
            recovery: .quarantinedAndReset,
            quarantinedFilename: "workspace.sidebar-cache.corrupt.json"
        )

        let notification = InboxNotification.persistenceRecovery(event)

        #expect(notification.kind == .persistenceRecovery)
        #expect(notification.source == .global)
        #expect(notification.title == "Sidebar cache reset")
        #expect(notification.body?.contains("workspace.sidebar-cache.corrupt.json") == true)
        #expect(notification.isRead == false)
        #expect(notification.isDismissedFromPaneInbox == false)
    }
}
