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
    struct RetentionOutcome: Sendable, Equatable {
        static let empty = Self(droppedCount: 0, droppedNotificationIds: [])

        let droppedCount: Int
        let droppedNotificationIds: [UUID]
    }

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

    @discardableResult
    func append(_ notification: InboxNotification) -> RetentionOutcome {
        let outcome: RetentionOutcome
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index] = notification
            outcome = enforceRetentionCap()
            recalculateGlobalUnreadCount()
            return outcome
        }
        notifications.append(notification)
        outcome = enforceRetentionCap()
        recalculateGlobalUnreadCount()
        return outcome
    }

    func replaceAll(_ replacement: [InboxNotification]) {
        notifications = replacement
        _ = enforceRetentionCap()
        recalculateGlobalUnreadCount()
    }

    @discardableResult
    func markRead(id: UUID) -> Bool {
        let updated = update(id: id) { $0.isRead = true }
        recalculateGlobalUnreadCount()
        return updated
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

    @discardableResult
    func dismissFromPaneInbox(id: UUID) -> Bool {
        update(id: id) { $0.isDismissedFromPaneInbox = true }
    }

    func dismissFromPaneInbox(paneId: UUID) {
        for index in notifications.indices where notifications[index].paneId == paneId {
            notifications[index].isDismissedFromPaneInbox = true
        }
    }

    func toggleReadState(id: UUID) {
        _ = update(id: id) { $0.isRead.toggle() }
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

    private func update(id: UUID, mutate: (inout InboxNotification) -> Void) -> Bool {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else {
            inboxNotificationAtomLogger.warning(
                "Ignored inbox notification update for unknown id \(id.uuidString, privacy: .public)"
            )
            return false
        }
        mutate(&notifications[index])
        return true
    }

    private func unreadCount(
        matching predicate: (InboxNotification) -> Bool
    ) -> Int {
        notifications.reduce(0) { count, notification in
            !notification.isRead && predicate(notification) ? count + 1 : count
        }
    }

    private func enforceRetentionCap() -> RetentionOutcome {
        let retentionCap = AppPolicies.InboxNotification.maxRetained
        guard notifications.count > retentionCap else { return .empty }
        notifications.sort { $0.timestamp < $1.timestamp }
        let overflow = notifications.count - retentionCap
        let droppedNotificationIds = notifications.prefix(overflow).map(\.id)
        notifications.removeFirst(overflow)
        inboxNotificationAtomLogger.warning(
            "Inbox notification retention cap dropped \(overflow, privacy: .public) oldest row(s)"
        )
        return RetentionOutcome(
            droppedCount: overflow,
            droppedNotificationIds: droppedNotificationIds
        )
    }

    private func recalculateGlobalUnreadCount() {
        globalUnreadCount = unreadCount { _ in true }
    }
}
