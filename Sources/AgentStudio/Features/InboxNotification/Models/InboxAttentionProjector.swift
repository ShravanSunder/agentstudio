import Foundation

package struct InboxAttentionFactSnapshot: Equatable, Sendable {
    package static let empty = Self(facts: [])

    struct Fact: Equatable, Sendable {
        let paneId: UUID
        let lane: InboxNotificationClaimLane
        let isRead: Bool
    }

    let facts: [Fact]

    init(notifications: [InboxNotification]) {
        self.facts = notifications.compactMap { notification in
            guard let paneId = notification.paneId else { return nil }
            return Fact(
                paneId: paneId,
                lane: notification.displayLane,
                isRead: notification.isRead
            )
        }
    }

    private init(facts: [Fact]) {
        self.facts = facts
    }
}

package enum InboxAttentionProjector: Sendable {
    package nonisolated static func project<GroupID: Hashable & Sendable>(
        snapshot: InboxAttentionFactSnapshot,
        groups: [GroupID: Set<UUID>],
        cancellationCheck: () throws(CancellationError) -> Void = checkCancellation
    ) throws(CancellationError) -> [GroupID: InboxNotificationClaimLane] {
        var groupIdsByPaneId: [UUID: [GroupID]] = [:]
        for (groupIndex, group) in groups.enumerated() {
            if groupIndex.isMultiple(of: 256) { try cancellationCheck() }
            for (paneIndex, paneId) in group.value.enumerated() {
                if paneIndex.isMultiple(of: 256) { try cancellationCheck() }
                groupIdsByPaneId[paneId, default: []].append(group.key)
            }
        }

        var lanesByGroupId: [GroupID: InboxNotificationClaimLane] = [:]
        for (factIndex, fact) in snapshot.facts.enumerated() {
            if factIndex.isMultiple(of: 256) { try cancellationCheck() }
            guard !fact.isRead, fact.lane != .activity else { continue }
            guard let groupIds = groupIdsByPaneId[fact.paneId] else { continue }
            for (groupIndex, groupId) in groupIds.enumerated() {
                if groupIndex.isMultiple(of: 256) { try cancellationCheck() }
                lanesByGroupId[groupId] = strongerLane(
                    lanesByGroupId[groupId],
                    candidate: fact.lane
                )
            }
        }
        try cancellationCheck()
        return lanesByGroupId
    }

    private nonisolated static func strongerLane(
        _ current: InboxNotificationClaimLane?,
        candidate: InboxNotificationClaimLane
    ) -> InboxNotificationClaimLane {
        switch (current, candidate) {
        case (_, .actionNeeded):
            return .actionNeeded
        case (.actionNeeded, _):
            return .actionNeeded
        case (_, .safety):
            return .safety
        case (.safety, _):
            return .safety
        case (_, .settledAgent):
            return .settledAgent
        case (.settledAgent, _):
            return .settledAgent
        case (_, .activity):
            return current ?? .activity
        }
    }

    private nonisolated static func checkCancellation() throws(CancellationError) {
        guard Task.isCancelled else { return }
        throw CancellationError()
    }
}
