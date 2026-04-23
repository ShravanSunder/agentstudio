import Foundation

@MainActor
extension AppDelegate {
    func makeInboxNotificationCommands() -> InboxNotificationCommands {
        InboxNotificationCommands(
            markAllAsRead: { [weak self] in
                self?.inboxNotificationAtom.markAllRead()
            },
            clearReadHistory: { [weak self] in
                self?.inboxNotificationAtom.clearReadHistory()
            },
            clearAll: { [weak self] in
                self?.inboxNotificationAtom.clearAll()
            },
            setGrouping: { [weak self] grouping in
                self?.inboxNotificationPrefsAtom.setGrouping(grouping)
            },
            toggleSort: { [weak self] in
                guard let prefsAtom = self?.inboxNotificationPrefsAtom else { return }
                prefsAtom.setSort(prefsAtom.sort == .newestFirst ? .oldestFirst : .newestFirst)
            },
            toggleBellEnabled: { [weak self] in
                guard let prefsAtom = self?.inboxNotificationPrefsAtom else { return }
                prefsAtom.setBellEnabled(!prefsAtom.bellEnabled)
            },
            returnToWorktreeSidebar: { [weak self] in
                self?.uiState.setSidebarSurface(.repos)
            },
            bellEnabled: { [weak self] in
                self?.inboxNotificationPrefsAtom.bellEnabled ?? false
            },
            currentGrouping: { [weak self] in
                self?.inboxNotificationPrefsAtom.grouping ?? .none
            },
            currentSort: { [weak self] in
                self?.inboxNotificationPrefsAtom.sort ?? .newestFirst
            }
        )
    }
}
