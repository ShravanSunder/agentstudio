import Foundation
import Observation

/// Canonical mutable state for the notification log.
///
/// Persistence lives in `InboxNotificationStore`; this atom only owns runtime
/// mutation and derived reads.
@MainActor
@Observable
final class InboxNotificationAtom {
    private(set) var notifications: [InboxNotification] = []

    func unreadCount(forPaneId paneId: UUID) -> Int {
        unreadCount { $0.paneId == paneId }
    }

    func unreadCount(forWorktreeId worktreeId: UUID) -> Int {
        unreadCount { $0.worktreeId == worktreeId }
    }

    func unreadCount(forTabId tabId: UUID) -> Int {
        unreadCount { $0.tabId == tabId }
    }

    func unreadCount(forDrawerPaneIds paneIds: [UUID]) -> Int {
        let paneIdSet = Set(paneIds)
        return unreadCount { notification in
            guard
                let paneId = notification.paneId,
                paneIdSet.contains(paneId)
            else {
                return false
            }
            return true
        }
    }

    var globalUnreadCount: Int {
        unreadCount { _ in true }
    }

    func append(_ notification: InboxNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index] = notification
            enforceRetentionCap()
            return
        }
        notifications.append(notification)
        enforceRetentionCap()
    }

    func markRead(id: UUID) {
        update(id: id) { $0.isRead = true }
    }

    func markRead(paneId: UUID) {
        for index in notifications.indices where notifications[index].paneId == paneId {
            notifications[index].isRead = true
        }
    }

    func markAllRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
    }

    func dismissFromDrawer(id: UUID) {
        update(id: id) { $0.isDismissedFromDrawer = true }
    }

    func dismissFromDrawer(paneId: UUID) {
        for index in notifications.indices where notifications[index].paneId == paneId {
            notifications[index].isDismissedFromDrawer = true
        }
    }

    func toggleReadState(id: UUID) {
        update(id: id) { $0.isRead.toggle() }
    }

    func clearReadHistory() {
        notifications.removeAll(where: \.isRead)
    }

    func clearAll() {
        notifications.removeAll()
    }

    private func update(id: UUID, mutate: (inout InboxNotification) -> Void) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        mutate(&notifications[index])
    }

    private func unreadCount(
        matching predicate: (InboxNotification) -> Bool
    ) -> Int {
        notifications.reduce(0) { count, notification in
            !notification.isRead && predicate(notification) ? count + 1 : count
        }
    }

    private func enforceRetentionCap() {
        let retentionCap = AppPolicies.InboxNotification.maxRetained
        guard notifications.count > retentionCap else { return }
        notifications.sort { $0.timestamp < $1.timestamp }
        let overflow = notifications.count - retentionCap
        notifications.removeFirst(overflow)
    }
}
