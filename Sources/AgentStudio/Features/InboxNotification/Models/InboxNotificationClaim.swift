import Foundation

package enum InboxNotificationClaimLane: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case actionNeeded
    case safety
    case settledAgent
    case activity

    var canMergeWithinActivitySession: Bool {
        switch self {
        case .activity, .actionNeeded, .settledAgent:
            return true
        case .safety:
            return false
        }
    }
}

package enum InboxNotificationClaimSemantic: String, Sendable, Codable, Equatable, Hashable {
    case approvalRequested
    case unseenActivity
    case commandFinished
    case bell
    case desktopNotification
    case agentRpc
    case agentSettled
    case secureInput
    case progressError
    case rendererUnhealthy
    case persistenceRecovery
    case securityEvent
}

package struct InboxNotificationClaimKey: Sendable, Codable, Equatable, Hashable {
    package let paneId: UUID
    package let lane: InboxNotificationClaimLane
    package let semantic: InboxNotificationClaimSemantic
    package let sessionId: UUID?
}
