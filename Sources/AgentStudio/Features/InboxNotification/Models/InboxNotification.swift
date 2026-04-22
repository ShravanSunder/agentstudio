import Foundation

/// A single notification entry in the inbox.
///
/// Source context is denormalized at emit time so history stays readable even
/// after the source pane or worktree disappears.
struct InboxNotification: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: InboxNotificationKind
    let title: String
    let body: String?

    let paneId: UUID?
    let tabId: UUID?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?

    var isRead: Bool
    var isDismissedFromDrawer: Bool
}

enum InboxNotificationKind: String, Sendable, Codable, Equatable {
    case agentDesktopNotification
    case bellRang
    case commandFinished
    case agentRpc
    case approvalRequested
    case securityEvent
}
