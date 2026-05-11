import Foundation

enum PaneInboxAutoClearDecision: Sendable, Equatable {
    case clear
    case keep(reason: String)
}

struct PaneInboxAutoClearPolicy: Sendable {
    func decision(
        notification: InboxNotification,
        isSourcePaneAttended: Bool,
        isSourcePanePinnedToBottom: Bool
    ) -> PaneInboxAutoClearDecision {
        guard isAutoClearable(notification.kind) else {
            return .keep(reason: "requires_user_action")
        }
        guard isSourcePaneAttended else {
            return .keep(reason: "source_pane_unattended")
        }
        guard isSourcePanePinnedToBottom else {
            return .keep(reason: "source_pane_not_at_bottom")
        }
        return .clear
    }

    private func isAutoClearable(_ kind: InboxNotificationKind) -> Bool {
        switch kind {
        case .agentDesktopNotification, .bellRang, .commandFinished, .agentRpc:
            return true
        case .terminalSecureInputRequested, .terminalProgressError, .terminalRendererUnhealthy,
            .persistenceRecovery, .approvalRequested, .securityEvent:
            return false
        }
    }
}
