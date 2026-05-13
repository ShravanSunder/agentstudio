import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AppDelegate inbox notification commands")
struct AppDelegateInboxNotificationCommandsTests {
    @Test("shell clear read command routes through inbox notification commands")
    func shellClearReadCommandRoutesThroughInboxNotificationCommands() {
        let delegate = AppDelegate()
        let inboxAtom = InboxNotificationAtom()
        delegate.atomStore = AtomRegistry()
        delegate.inboxNotificationAtom = inboxAtom
        delegate.inboxNotificationPrefsAtom = InboxNotificationPrefsAtom()
        inboxAtom.append(makeReadNotification())

        #expect(delegate.canExecute(.clearReadInboxNotifications))
        let didExecute = delegate.execute(.clearReadInboxNotifications)

        #expect(didExecute)
        #expect(inboxAtom.notifications.isEmpty)
    }

    @Test("shell clear read command tolerates missing inbox atom during boot")
    func shellClearReadCommandToleratesMissingInboxAtomDuringBoot() {
        let delegate = AppDelegate()

        #expect(delegate.canExecute(.clearReadInboxNotifications))
        #expect(delegate.execute(.clearReadInboxNotifications))
    }

    private func makeReadNotification() -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Agent finished",
            body: nil,
            source: .global,
            isRead: true,
            isDismissedFromPaneInbox: false
        )
    }
}
