import Foundation

/// Callback seam for exposing inbox commands without importing the feature slice.
@MainActor
struct InboxNotificationCommands {
    struct Actions {
        var markAllAsRead: @MainActor @Sendable () -> Void
        var clearReadHistory: @MainActor @Sendable () -> Void
        var clearAll: @MainActor @Sendable () -> Void
        var setGrouping: @MainActor @Sendable (InboxNotificationGrouping) -> Void
        var toggleSort: @MainActor @Sendable () -> Void
        var toggleBellEnabled: @MainActor @Sendable () -> Void
        var returnToWorktreeSidebar: @MainActor @Sendable () -> Void
    }

    struct Snapshot {
        var bellEnabled: Bool
        var currentGrouping: InboxNotificationGrouping
        var currentSort: InboxNotificationSort
    }

    var actions: Actions
    var snapshot: @MainActor @Sendable () -> Snapshot
}
