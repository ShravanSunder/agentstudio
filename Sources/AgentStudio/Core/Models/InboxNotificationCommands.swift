import Foundation

/// Callback seam for exposing inbox commands without importing the feature slice.
@MainActor
package struct InboxNotificationCommands {
    package struct Actions {
        package var markAllAsRead: @MainActor @Sendable () -> Void
        package var clearReadHistory: @MainActor @Sendable () -> Void
        package var clearAll: @MainActor @Sendable () -> Void
        package var setGrouping: @MainActor @Sendable (InboxNotificationGrouping) -> Void
        package var toggleBellEnabled: @MainActor @Sendable () -> Void
        package var returnToWorktreeSidebar: @MainActor @Sendable () -> Void

        package init(
            markAllAsRead: @escaping @MainActor @Sendable () -> Void,
            clearReadHistory: @escaping @MainActor @Sendable () -> Void,
            clearAll: @escaping @MainActor @Sendable () -> Void,
            setGrouping: @escaping @MainActor @Sendable (InboxNotificationGrouping) -> Void,
            toggleBellEnabled: @escaping @MainActor @Sendable () -> Void,
            returnToWorktreeSidebar: @escaping @MainActor @Sendable () -> Void
        ) {
            self.markAllAsRead = markAllAsRead
            self.clearReadHistory = clearReadHistory
            self.clearAll = clearAll
            self.setGrouping = setGrouping
            self.toggleBellEnabled = toggleBellEnabled
            self.returnToWorktreeSidebar = returnToWorktreeSidebar
        }
    }

    package struct Snapshot {
        package var bellEnabled: Bool
        package var currentGrouping: InboxNotificationGrouping
        package var currentSort: InboxNotificationSort

        package init(
            bellEnabled: Bool,
            currentGrouping: InboxNotificationGrouping,
            currentSort: InboxNotificationSort
        ) {
            self.bellEnabled = bellEnabled
            self.currentGrouping = currentGrouping
            self.currentSort = currentSort
        }
    }

    package var actions: Actions
    package var snapshot: @MainActor @Sendable () -> Snapshot

    package init(
        actions: Actions,
        snapshot: @escaping @MainActor @Sendable () -> Snapshot
    ) {
        self.actions = actions
        self.snapshot = snapshot
    }
}
