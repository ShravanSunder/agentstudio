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
        notifications.reduce(0) { count, notification in
            notification.paneId == paneId && !notification.isRead ? count + 1 : count
        }
    }

    func unreadCount(forWorktreeId worktreeId: UUID) -> Int {
        notifications.reduce(0) { count, notification in
            notification.worktreeId == worktreeId && !notification.isRead ? count + 1 : count
        }
    }

    func unreadCount(forTabId tabId: UUID) -> Int {
        notifications.reduce(0) { count, notification in
            notification.tabId == tabId && !notification.isRead ? count + 1 : count
        }
    }

    func unreadCount(forDrawerPaneIds paneIds: [UUID]) -> Int {
        let paneIdSet = Set(paneIds)
        return notifications.reduce(0) { count, notification in
            guard
                let paneId = notification.paneId,
                paneIdSet.contains(paneId),
                !notification.isRead
            else {
                return count
            }
            return count + 1
        }
    }

    var globalUnreadCount: Int {
        notifications.reduce(0) { count, notification in
            notification.isRead ? count : count + 1
        }
    }

    func append(_ notification: InboxNotification) {
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

    private func enforceRetentionCap() {
        let retentionCap = AppPolicies.InboxNotification.maxRetained
        guard notifications.count > retentionCap else { return }
        notifications.sort { $0.timestamp < $1.timestamp }
        let overflow = notifications.count - retentionCap
        notifications.removeFirst(overflow)
    }
}
