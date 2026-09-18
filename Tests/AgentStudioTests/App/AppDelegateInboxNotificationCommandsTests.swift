import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification

@MainActor
@Suite("AppDelegate retired Inbox commands", .serialized)
struct AppDelegateInboxNotificationCommandsTests {
    @Test("shell Inbox commands are unsupported and preserve dormant state")
    func shellInboxCommandsAreUnsupportedAndPreserveDormantState() {
        let delegate = AppDelegate()
        let inboxAtom = InboxNotificationAtom()
        let prefsAtom = InboxNotificationPrefsAtom()
        delegate.atomStore = AtomRegistry(
            inboxNotification: inboxAtom,
            inboxNotificationPrefs: prefsAtom
        )
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Agent finished",
            body: nil,
            source: .global,
            isRead: true,
            isDismissedFromPaneInbox: false
        )
        inboxAtom.append(notification)

        let commands: [AppCommand] = [
            .clearReadInboxNotifications,
            .clearAllInboxNotifications,
            .toggleInboxNotificationSort,
            .setInboxGroupingTab,
            .setInboxGroupingRepo,
            .setInboxGroupingPane,
            .setInboxGroupingNone,
        ]
        for command in commands {
            #expect(!delegate.canExecute(command))
            #expect(!delegate.execute(command))
        }

        #expect(inboxAtom.notifications == [notification])
        #expect(prefsAtom.sort == .newestFirst)
    }

    @Test("retired Inbox command requests remain unsupported without mutating preferences")
    func typedInboxCommandsFailAsUnsupportedWithoutMutatingPreferences() {
        let delegate = AppDelegate()
        let prefsAtom = InboxNotificationPrefsAtom()
        delegate.atomStore = AtomRegistry(inboxNotificationPrefs: prefsAtom)

        let rowFilterOutcome = delegate.execute(
            AppCommandExecutionRequest(
                command: .setInboxRowStateFilter,
                executionContext: .headlessIPC(admitsDebugTestingCommands: true)
            )
        )
        let contentModeOutcome = delegate.execute(
            AppCommandExecutionRequest(
                command: .setInboxContentMode,
                executionContext: .headlessIPC(admitsDebugTestingCommands: true)
            )
        )

        #expect(rowFilterOutcome == .unsupportedCommand)
        #expect(contentModeOutcome == .unsupportedCommand)
        #expect(prefsAtom.globalInboxRowStateFilter == .unreadOnly)
        #expect(prefsAtom.globalInboxContentMode == .rollUpAlerts)
    }
}
