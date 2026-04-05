import Foundation

/// Workspace-scoped activity facts emitted by app coordination code.
/// These are notification-plane events only; store mutation still happens in the coordinator.
enum WorkspaceActivityEvent: Sendable {
    case recentTargetOpened(RecentWorkspaceTarget)
}
