import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneInboxAutoClearPolicy")
struct PaneInboxAutoClearPolicyTests {
    private let policy = PaneInboxAutoClearPolicy()

    @Test("auto-clearable kinds clear only when source pane is observed")
    func autoClearableKindsClearOnlyWhenSourcePaneIsObserved() {
        for kind in autoClearableKinds {
            let notification = makeNotification(kind: kind)

            #expect(
                policy.decision(
                    notification: notification,
                    isSourcePaneAttended: true,
                    isSourcePanePinnedToBottom: true
                ) == .clear
            )
            #expect(
                policy.decision(
                    notification: notification,
                    isSourcePaneAttended: false,
                    isSourcePanePinnedToBottom: true
                ) == .keep(reason: "source_pane_unattended")
            )
            #expect(
                policy.decision(
                    notification: notification,
                    isSourcePaneAttended: true,
                    isSourcePanePinnedToBottom: false
                ) == .keep(reason: "source_pane_not_at_bottom")
            )
        }
    }

    @Test("user-action-required kinds remain unread even when source pane is observed")
    func userActionRequiredKindsRemainUnreadWhenObserved() {
        for kind in userActionRequiredKinds {
            #expect(
                policy.decision(
                    notification: makeNotification(kind: kind),
                    isSourcePaneAttended: true,
                    isSourcePanePinnedToBottom: true
                ) == .keep(reason: "requires_user_action")
            )
        }
    }

    private var autoClearableKinds: [InboxNotificationKind] {
        [
            .agentDesktopNotification,
            .bellRang,
            .commandFinished,
            .agentRpc,
        ]
    }

    private var userActionRequiredKinds: [InboxNotificationKind] {
        [
            .terminalSecureInputRequested,
            .terminalProgressError,
            .terminalRendererUnhealthy,
            .persistenceRecovery,
            .approvalRequested,
            .securityEvent,
        ]
    }

    private func makeNotification(kind: InboxNotificationKind) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: kind,
            title: "Notification",
            body: nil,
            source: .pane(.init(paneId: UUID())),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
