import Foundation

/// Callback bundle that lets non-inbox features expose notification commands
/// without importing the InboxNotification feature slice.
@MainActor
struct InboxNotificationCommands {
    var markAllAsRead: @MainActor @Sendable () -> Void
    var clearReadHistory: @MainActor @Sendable () -> Void
    var clearAll: @MainActor @Sendable () -> Void
    var setGrouping: @MainActor @Sendable (InboxNotificationGrouping) -> Void
    var toggleSort: @MainActor @Sendable () -> Void
    var toggleBellEnabled: @MainActor @Sendable () -> Void
    var returnToWorktreeSidebar: @MainActor @Sendable () -> Void

    var bellEnabled: @MainActor @Sendable () -> Bool
    var currentGrouping: @MainActor @Sendable () -> InboxNotificationGrouping
    var currentSort: @MainActor @Sendable () -> InboxNotificationSort
}
