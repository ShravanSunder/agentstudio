import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AppDelegate inbox notification commands")
struct AppDelegateInboxNotificationCommandsTests {
    @Test("shell clear command routes through inbox notification commands")
    func shellClearCommandRoutesThroughInboxNotificationCommands() {
        let delegate = AppDelegate()
        let inboxAtom = InboxNotificationAtom()
        delegate.atomStore = AtomRegistry()
        delegate.inboxNotificationAtom = inboxAtom
        delegate.inboxNotificationPrefsAtom = InboxNotificationPrefsAtom()
        inboxAtom.append(makeUnreadNotification())

        #expect(delegate.canExecute(.clearInboxNotifications))
        let didExecute = delegate.execute(.clearInboxNotifications)

        #expect(didExecute)
        #expect(inboxAtom.notifications.isEmpty)
    }

    @Test("shell clear command is unavailable before inbox commands are wired")
    func shellClearCommandIsUnavailableBeforeInboxCommandsAreWired() {
        let delegate = AppDelegate()

        #expect(delegate.canExecute(.clearInboxNotifications) == false)
        #expect(delegate.execute(.clearInboxNotifications) == false)
    }

    private func makeUnreadNotification() -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Agent finished",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
