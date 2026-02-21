import Foundation

/// Tracks where a session currently resides in the application lifecycle.
/// Used by the Reconciler to determine intent — avoids false-positive orphan detection.
enum SessionResidency: Equatable, Codable, Hashable {
    /// Session is in a layout, view exists, fully active.
    case active
    /// Session was closed and is in the undo window. Not an orphan.
    case pendingUndo(expiresAt: Date)
    /// Session is alive but not visible in the current view. Not an orphan.
    case backgrounded

    var isPendingUndo: Bool {
        if case .pendingUndo = self { return true }
        return false
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}
