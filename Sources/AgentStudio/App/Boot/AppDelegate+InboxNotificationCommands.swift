import Foundation

@MainActor
extension AppDelegate {
    func makeInboxNotificationCommands() -> InboxNotificationCommands {
        let inboxAtom = inboxNotificationAtom!
        let prefsAtom = inboxNotificationPrefsAtom!
        let uiState = uiState!
        return InboxNotificationCommands(
            actions: .init(
                markAllAsRead: { inboxAtom.markAllRead() },
                clearReadHistory: { inboxAtom.clearReadHistory() },
                clearAll: { inboxAtom.clearAll() },
                setGrouping: { grouping in prefsAtom.setGrouping(grouping) },
                toggleSort: {
                    prefsAtom.setSort(prefsAtom.sort == .newestFirst ? .oldestFirst : .newestFirst)
                },
                toggleBellEnabled: {
                    prefsAtom.setBellEnabled(!prefsAtom.bellEnabled)
                },
                returnToWorktreeSidebar: {
                    uiState.setSidebarSurface(.repos)
                }
            ),
            snapshot: {
                .init(
                    bellEnabled: prefsAtom.bellEnabled,
                    currentGrouping: prefsAtom.grouping,
                    currentSort: prefsAtom.sort
                )
            }
        )
    }

    func executeClearInboxNotificationsCommand() -> Bool {
        guard canExecuteClearInboxNotificationsCommand() else { return false }

        makeInboxNotificationCommands().actions.clearAll()
        return true
    }

    func canExecuteClearInboxNotificationsCommand() -> Bool {
        inboxNotificationAtom != nil
            && inboxNotificationPrefsAtom != nil
            && atomStore != nil
    }
}
