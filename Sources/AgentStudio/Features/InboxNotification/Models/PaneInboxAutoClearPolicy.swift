import Foundation

struct PaneInboxAutoClearPolicy: Sendable {
    func canAutoClear(kind: InboxNotificationKind) -> Bool {
        switch kind {
        case .agentDesktopNotification,
            .bellRang,
            .commandFinished,
            .agentRpc:
            return true
        case .approvalRequested,
            .securityEvent,
            .persistenceRecovery,
            .terminalProgressError,
            .terminalRendererUnhealthy,
            .terminalSecureInputRequested:
            return false
        }
    }
}
