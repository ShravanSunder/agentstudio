import Foundation

@MainActor
extension AppDelegate {
    func makeInboxNotificationCommands() -> InboxNotificationCommands {
        let inboxAtom = atomStore.inboxNotification
        let prefsAtom = atomStore.inboxNotificationPrefs
        let uiState = uiState!
        return InboxNotificationCommands(
            actions: .init(
                markAllAsRead: { inboxAtom.markAllRead() },
                clearReadHistory: { inboxAtom.clearReadHistory() },
                clearAll: { inboxAtom.clearAll() },
                setGrouping: { grouping in prefsAtom.setGrouping(grouping) },
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
}
