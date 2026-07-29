import Foundation

/// Tracks where a session currently resides in the application lifecycle.
/// Used by the Reconciler to determine intent — avoids false-positive orphan detection.
package enum SessionResidency: Equatable, Codable, Hashable, Sendable {
    /// Session is in a layout, view exists, fully active.
    case active
    /// Session was closed and is in the undo window. Not an orphan.
    case pendingUndo(expiresAt: Date)
    /// Session is alive but not visible in the current view. Not an orphan.
    case backgrounded
    /// Session is still persisted but its backing worktree path is unavailable.
    case orphaned(reason: WorktreeUnavailableReason)

    package var isPendingUndo: Bool {
        if case .pendingUndo = self { return true }
        return false
    }

    package var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    package var isOrphaned: Bool {
        if case .orphaned = self { return true }
        return false
    }
}

package enum WorktreeUnavailableReason: Equatable, Codable, Hashable, Sendable {
    case worktreeNotFound(path: String)
}
