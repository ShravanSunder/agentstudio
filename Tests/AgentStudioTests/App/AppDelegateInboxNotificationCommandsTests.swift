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

    @Test("shell toggle inbox sort command routes through inbox notification prefs")
    func shellToggleInboxSortCommandRoutesThroughInboxNotificationPrefs() {
        let delegate = AppDelegate()
        let prefsAtom = InboxNotificationPrefsAtom()
        delegate.atomStore = AtomRegistry()
        delegate.inboxNotificationAtom = InboxNotificationAtom()
        delegate.inboxNotificationPrefsAtom = prefsAtom

        #expect(delegate.canExecute(.toggleInboxNotificationSort))
        let didExecute = delegate.execute(.toggleInboxNotificationSort)

        #expect(didExecute)
        #expect(prefsAtom.sort == .oldestFirst)
    }

    @Test("shell toggle inbox sort command tolerates missing prefs atom during boot")
    func shellToggleInboxSortCommandToleratesMissingPrefsAtomDuringBoot() {
        let delegate = AppDelegate()

        #expect(delegate.canExecute(.toggleInboxNotificationSort))
        #expect(delegate.execute(.toggleInboxNotificationSort))
    }

    @Test("shell clear all command routes through inbox notification commands")
    func shellClearAllCommandRoutesThroughInboxNotificationCommands() {
        let delegate = AppDelegate()
        let inboxAtom = InboxNotificationAtom()
        delegate.atomStore = AtomRegistry()
        delegate.inboxNotificationAtom = inboxAtom
        delegate.inboxNotificationPrefsAtom = InboxNotificationPrefsAtom()
        inboxAtom.append(makeReadNotification())

        #expect(delegate.canExecute(.clearAllInboxNotifications))
        let didExecute = delegate.execute(.clearAllInboxNotifications)

        #expect(didExecute)
        #expect(inboxAtom.notifications.isEmpty)
    }

    @Test("shell clear all command tolerates missing inbox atom during boot")
    func shellClearAllCommandToleratesMissingInboxAtomDuringBoot() {
        let delegate = AppDelegate()

        #expect(delegate.canExecute(.clearAllInboxNotifications))
        #expect(delegate.execute(.clearAllInboxNotifications))
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
