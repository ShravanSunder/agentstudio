import Foundation
import Observation
import os.log

private let inboxNotificationAtomLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationAtom"
)

/// Canonical mutable state for the notification log.
///
/// Persistence lives in `InboxNotificationStore`; this atom only owns runtime
/// mutation and derived reads.
@MainActor
@Observable
final class InboxNotificationAtom {
    private(set) var notifications: [InboxNotification] = []
    private(set) var globalUnreadCount = 0

    func unreadCount(forPaneId paneId: UUID) -> Int {
        unreadCount { $0.paneId == paneId }
    }

    func unreadCount(forWorktreeId worktreeId: UUID) -> Int {
        unreadCount { $0.worktreeId == worktreeId }
    }

    func unreadCount(forTabId tabId: UUID) -> Int {
        unreadCount { $0.tabId == tabId }
    }

    func unreadCount(forPaneIds paneIds: [UUID]) -> Int {
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

    func visiblePaneInboxUnreadCount(forPaneIds paneIds: [UUID]) -> Int {
        let paneIdSet = Set(paneIds)
        return unreadCount { notification in
            guard
                let paneId = notification.paneId,
                paneIdSet.contains(paneId)
            else {
                return false
            }
            return !notification.isDismissedFromPaneInbox
        }
    }

    func append(_ notification: InboxNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index] = notification
            enforceRetentionCap()
            recalculateGlobalUnreadCount()
            return
        }
        notifications.append(notification)
        enforceRetentionCap()
        recalculateGlobalUnreadCount()
    }

    func replaceAll(_ replacement: [InboxNotification]) {
        notifications = replacement
        enforceRetentionCap()
        recalculateGlobalUnreadCount()
    }

    func markRead(id: UUID) {
        update(id: id) { $0.isRead = true }
        recalculateGlobalUnreadCount()
    }

    func markRead(paneId: UUID) {
        for index in notifications.indices where notifications[index].paneId == paneId {
            notifications[index].isRead = true
        }
        recalculateGlobalUnreadCount()
    }

    func markAllRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
        recalculateGlobalUnreadCount()
    }

    func dismissFromPaneInbox(id: UUID) {
        update(id: id) { $0.isDismissedFromPaneInbox = true }
    }

    func dismissFromPaneInbox(paneId: UUID) {
        for index in notifications.indices where notifications[index].paneId == paneId {
            notifications[index].isDismissedFromPaneInbox = true
        }
    }

    func clearPaneInboxScope(paneIds: [UUID]) {
        let paneIdSet = Set(paneIds)
        guard !paneIdSet.isEmpty else { return }

        for index in notifications.indices {
            guard
                let paneId = notifications[index].paneId,
                paneIdSet.contains(paneId)
            else { continue }
            notifications[index].isRead = true
            notifications[index].isDismissedFromPaneInbox = true
        }
        recalculateGlobalUnreadCount()
    }

    @discardableResult
    func autoClearPaneInbox(paneId: UUID, canAutoClear: (InboxNotificationKind) -> Bool) -> Int {
        var clearedCount = 0
        for index in notifications.indices
        where notifications[index].paneId == paneId && canAutoClear(notifications[index].kind) {
            if !notifications[index].isRead || !notifications[index].isDismissedFromPaneInbox {
                clearedCount += 1
            }
            notifications[index].isRead = true
            notifications[index].isDismissedFromPaneInbox = true
        }
        recalculateGlobalUnreadCount()
        return clearedCount
    }

    func toggleReadState(id: UUID) {
        update(id: id) { $0.isRead.toggle() }
        recalculateGlobalUnreadCount()
    }

    func clearReadHistory() {
        notifications.removeAll(where: \.isRead)
        recalculateGlobalUnreadCount()
    }

    func clearAll() {
        notifications.removeAll()
        recalculateGlobalUnreadCount()
    }

    private func update(id: UUID, mutate: (inout InboxNotification) -> Void) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else {
            inboxNotificationAtomLogger.warning(
                "Ignored inbox notification update for unknown id \(id.uuidString, privacy: .public)"
            )
            return
        }
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
        inboxNotificationAtomLogger.warning(
            "Inbox notification retention cap dropped \(overflow, privacy: .public) oldest row(s)"
        )
    }

    private func recalculateGlobalUnreadCount() {
        globalUnreadCount = unreadCount { _ in true }
    }
}
