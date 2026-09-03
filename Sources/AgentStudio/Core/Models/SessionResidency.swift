import Foundation

/// Tracks the pane's application placement lifecycle independently of its
/// filesystem location and optional repository/worktree association.
package enum SessionResidency: Equatable, Codable, Hashable, Sendable {
    /// Pane participates in canonical workspace presentation and content mounting.
    case active
    /// Session was closed and is in the undo window. Not an orphan.
    case pendingUndo(expiresAt: Date)
    /// Session is alive but not visible in the current view. Not an orphan.
    case backgrounded
    /// Legacy persisted state from releases that coupled pane placement to a
    /// worktree path. Boot reconciliation converts this to active or backgrounded.
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
