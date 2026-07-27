import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
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
package final class InboxNotificationAtom {
    package struct RetentionOutcome: Sendable, Equatable {
        package static let empty = Self(droppedCount: 0, droppedNotificationIds: [])

        package let droppedCount: Int
        package let droppedNotificationIds: [UUID]
    }

    struct MutationOutcome: Sendable, Equatable {
        let notificationId: UUID
        let didCoalesce: Bool
        let retentionOutcome: RetentionOutcome
    }

    package private(set) var notifications: [InboxNotification] = []
    package private(set) var globalUnreadCount = 0
    package private(set) var globalRollUpAlertCount = 0

    package init() {}

    func unreadCount(forPaneId paneId: UUID) -> Int {
        unreadCount { $0.paneId == paneId }
    }

    package func unreadCount(forWorktreeId worktreeId: UUID) -> Int {
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

    package func rollUpAlertCount(forWorktreeId worktreeId: UUID) -> Int {
        rollUpAlertCount { $0.worktreeId == worktreeId }
    }

    package func rollUpAlertCount(forTabId tabId: UUID) -> Int {
        rollUpAlertCount { $0.tabId == tabId }
    }

    package func rollUpAlertCount(forPaneIds paneIds: [UUID]) -> Int {
        let paneIdSet = Set(paneIds)
        return rollUpAlertCount { notification in
            guard
                let paneId = notification.paneId,
                paneIdSet.contains(paneId)
            else {
                return false
            }
            return true
        }
    }

    package func visiblePaneInboxUnreadCount(forPaneIds paneIds: [UUID]) -> Int {
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

    package func visiblePaneInboxRollUpAlertCount(forPaneIds paneIds: [UUID]) -> Int {
        let paneIdSet = Set(paneIds)
        return rollUpAlertCount { notification in
            guard
                let paneId = notification.paneId,
                paneIdSet.contains(paneId)
            else {
                return false
            }
            return !notification.isDismissedFromPaneInbox
        }
    }

    package func rollUpAlertLane(forPaneIds paneIds: [UUID]) -> InboxNotificationClaimLane? {
        let paneIdSet = Set(paneIds)
        let matchingLanes = notifications.compactMap { notification -> InboxNotificationClaimLane? in
            guard notification.contributesToRollUpAlert else { return nil }
            guard let paneId = notification.paneId, paneIdSet.contains(paneId) else { return nil }
            return notification.displayLane
        }
        if matchingLanes.contains(.actionNeeded) { return .actionNeeded }
        if matchingLanes.contains(.safety) { return .safety }
        return nil
    }

    package func attentionLane(forPaneIds paneIds: [UUID]) -> InboxNotificationClaimLane? {
        let paneIdSet = Set(paneIds)
        let matchingLanes = notifications.compactMap { notification -> InboxNotificationClaimLane? in
            guard notification.contributesToAttentionDot else { return nil }
            guard let paneId = notification.paneId, paneIdSet.contains(paneId) else { return nil }
            return notification.displayLane
        }
        if matchingLanes.contains(.actionNeeded) { return .actionNeeded }
        if matchingLanes.contains(.safety) { return .safety }
        if matchingLanes.contains(.settledAgent) { return .settledAgent }
        return nil
    }

    @discardableResult
    func revokeSettledAgentAttention(forPaneId paneId: UUID) -> Bool {
        var didRevoke = false
        for index in notifications.indices {
            let notification = notifications[index]
            guard
                !notification.isRead,
                notification.paneId == paneId,
                notification.displayLane == .settledAgent
            else {
                continue
            }
            notifications[index] = InboxNotification(
                id: notification.id,
                timestamp: notification.timestamp,
                kind: .unseenActivity,
                title: "New terminal activity",
                body: nil,
                source: notification.source,
                activityContext: notification.activityContext,
                claimKey: notification.claimKey.map {
                    InboxNotificationClaimKey(
                        paneId: $0.paneId,
                        lane: .activity,
                        semantic: .unseenActivity,
                        sessionId: $0.sessionId
                    )
                },
                isRead: false,
                isDismissedFromPaneInbox: false
            )
            didRevoke = true
        }
        if didRevoke {
            recalculateGlobalUnreadCount()
        }
        return didRevoke
    }

    @discardableResult
    package func append(_ notification: InboxNotification) -> RetentionOutcome {
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

    @discardableResult
    func upsertByClaim(
        _ notification: InboxNotification,
        merge: (InboxNotification, InboxNotification) -> InboxNotification
    ) -> MutationOutcome {
        guard let claimKey = notification.claimKey else {
            return MutationOutcome(
                notificationId: notification.id,
                didCoalesce: false,
                retentionOutcome: append(notification)
            )
        }

        if let index = notifications.firstIndex(where: { existing in
            existing.claimKey == claimKey
                && claimKey.lane.canMergeWithinActivitySession
                && canCoalesceClaim(existing: existing, incoming: notification)
        }) {
            let replacement = merge(notifications[index], notification)
            notifications[index] = replacement
            recalculateGlobalUnreadCount()
            return MutationOutcome(
                notificationId: replacement.id,
                didCoalesce: true,
                retentionOutcome: .empty
            )
        }

        if let sessionId = claimKey.sessionId,
            let index = notifications.firstIndex(where: { existing in
                guard
                    let existingClaimKey = existing.claimKey,
                    existingClaimKey.paneId == claimKey.paneId,
                    existingClaimKey.sessionId == sessionId,
                    canCoalesceClaim(existing: existing, incoming: notification)
                else {
                    return false
                }
                return existingClaimKey.lane.canMergeWithinActivitySession
            })
        {
            let replacement = merge(notifications[index], notification)
            notifications[index] = replacement
            recalculateGlobalUnreadCount()
            return MutationOutcome(
                notificationId: replacement.id,
                didCoalesce: true,
                retentionOutcome: .empty
            )
        }

        return MutationOutcome(
            notificationId: notification.id,
            didCoalesce: false,
            retentionOutcome: append(notification)
        )
    }

    private func canCoalesceClaim(
        existing: InboxNotification,
        incoming: InboxNotification
    ) -> Bool {
        InboxNotificationClaimCoalescencePolicy.canCoalesce(existing: existing, incoming: incoming)
    }

    package func replaceAll(_ replacement: [InboxNotification]) {
        notifications = replacement
        _ = enforceRetentionCap()
        recalculateGlobalUnreadCount()
    }

    @discardableResult
    package func markRead(id: UUID) -> Bool {
        let updated = update(id: id) { $0.isRead = true }
        recalculateGlobalUnreadCount()
        return updated
    }

    func markRead(paneId: UUID) {
        markRead(scope: .paneIds([paneId]))
    }

    package func markAllRead() {
        markRead(scope: .workspace)
    }

    func markRead(scope: InboxNotificationReadScope) {
        for index in notifications.indices where scope.matches(notifications[index]) {
            notifications[index].isRead = true
        }
        recalculateGlobalUnreadCount()
    }

    @discardableResult
    package func dismissFromPaneInbox(id: UUID) -> Bool {
        update(id: id) { $0.isDismissedFromPaneInbox = true }
    }

    func dismissFromPaneInbox(paneId: UUID) {
        for index in notifications.indices where notifications[index].paneId == paneId {
            notifications[index].isDismissedFromPaneInbox = true
        }
    }

    package func clearPaneInbox(paneIds: [UUID]) {
        let paneIdSet = Set(paneIds)
        for index in notifications.indices {
            guard let paneId = notifications[index].paneId, paneIdSet.contains(paneId) else { continue }
            notifications[index].isRead = true
            notifications[index].isDismissedFromPaneInbox = true
        }
        recalculateGlobalUnreadCount()
    }

    func toggleReadState(id: UUID) {
        _ = update(id: id) {
            $0.isRead.toggle()
            if !$0.isRead {
                $0.isDismissedFromPaneInbox = false
            }
        }
        recalculateGlobalUnreadCount()
    }

    package func clearReadHistory() {
        notifications.removeAll(where: \.isRead)
        recalculateGlobalUnreadCount()
    }

    package func clearAll() {
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

    private func rollUpAlertCount(
        matching predicate: (InboxNotification) -> Bool
    ) -> Int {
        notifications.reduce(0) { count, notification in
            notification.contributesToRollUpAlert && predicate(notification) ? count + 1 : count
        }
    }

    private func enforceRetentionCap() -> RetentionOutcome {
        let retentionCap = AppPolicies.InboxNotification.maxRetained
        guard notifications.count > retentionCap else { return .empty }
        let overflow = notifications.count - retentionCap
        let droppedNotificationIds = InboxNotificationRetentionPolicy.droppedNotificationIds(
            from: notifications,
            overflow: overflow
        )
        let droppedNotificationIdSet = Set(droppedNotificationIds)
        notifications.removeAll { droppedNotificationIdSet.contains($0.id) }
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
        globalRollUpAlertCount = rollUpAlertCount { _ in true }
    }
}
