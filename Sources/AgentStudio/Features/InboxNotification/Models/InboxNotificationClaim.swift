import Foundation

enum InboxNotificationClaimLane: String, Sendable, Codable, Equatable, Hashable {
    case actionNeeded
    case safety
    case activity

    var canMergeWithinActivitySession: Bool {
        switch self {
        case .activity, .actionNeeded:
            return true
        case .safety:
            return false
        }
    }
}

enum InboxNotificationClaimSemantic: String, Sendable, Codable, Equatable, Hashable {
    case inputRequired
    case approvalRequested
    case unseenActivity
    case commandFinished
    case bell
    case desktopNotification
    case agentRpc
    case secureInput
    case progressError
    case rendererUnhealthy
    case persistenceRecovery
    case securityEvent
}

struct InboxNotificationClaimKey: Sendable, Codable, Equatable, Hashable {
    let paneId: UUID
    let lane: InboxNotificationClaimLane
    let semantic: InboxNotificationClaimSemantic
    let sessionId: UUID?
}

enum InboxNotificationClaimInvalidationReason: String, Sendable, Codable, Equatable {
    case paneObserved
    case paneClosed
    case notificationRead
    case notificationDismissed
    case paneInboxCleared
    case supersededByExplicitSemanticEvent
    case routerStopped
}
