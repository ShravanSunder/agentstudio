import AgentStudioCore
import AgentStudioInboxNotification
import Foundation

/// Lightweight display item for the tab bar.
/// Contains only what the UI needs to render — no live views or split trees.
struct TabBarItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var isSplit: Bool
    var displayTitle: String
    var activeArrangementName: String?
    var activeArrangementBadgeNumber: Int?
    var arrangementCount: Int
    var colorHex: String?
    var panes: [PaneVisibilityInfo]
    var zoomMode: ArrangementPanelZoomMode?
    var arrangements: [ArrangementInfo]
    var minimizedCount: Int
    var notificationDotColor: TabNotificationDotColor?
}

enum TabNotificationDotColor: Equatable, Sendable {
    case red
    case amber
    case yellow
}

struct TabBarProjectionGeneration: Equatable, Sendable {
    let value: UInt64
}

struct TabBarProjectionRequest: Sendable {
    let generation: TabBarProjectionGeneration
    let coreRequest: CoreTabBarProjectionRequest
    let inboxAttentionFacts: InboxAttentionFactSnapshot
}

struct TabBarProjection: Equatable, Sendable {
    let items: [TabBarItem]
    let activeTabID: UUID?
}

enum TabBarProjector {
    nonisolated static func project(
        _ request: TabBarProjectionRequest,
        cancellationCheck: () throws(CancellationError) -> Void = checkCancellation
    ) throws(CancellationError) -> TabBarProjection {
        let coreProjection = try CoreTabBarProjector.project(
            request.coreRequest,
            cancellationCheck: cancellationCheck
        )
        var paneIDsByTabID: [UUID: Set<UUID>] = [:]
        paneIDsByTabID.reserveCapacity(coreProjection.items.count)
        for coreItem in coreProjection.items {
            try cancellationCheck()
            paneIDsByTabID[coreItem.id] = Set(coreItem.paneIds)
        }
        let attentionLanesByTabID = try InboxAttentionProjector.project(
            snapshot: request.inboxAttentionFacts,
            groups: paneIDsByTabID,
            cancellationCheck: cancellationCheck
        )

        var items: [TabBarItem] = []
        items.reserveCapacity(coreProjection.items.count)
        for coreItem in coreProjection.items {
            try cancellationCheck()
            let zoomManagementTitle = ZoomManagementTitle.text(
                sourceOrdinal: coreItem.zoomSourcePaneOrdinal,
                activeArrangementName: coreItem.activeArrangementName
            )
            items.append(
                TabBarItem(
                    id: coreItem.id,
                    title: coreItem.title,
                    isSplit: coreItem.isSplit,
                    displayTitle: coreItem.displayTitle,
                    activeArrangementName: zoomManagementTitle ?? coreItem.activeArrangementName,
                    activeArrangementBadgeNumber: coreItem.activeArrangementBadgeNumber,
                    arrangementCount: coreItem.arrangementCount,
                    colorHex: coreItem.colorHex,
                    panes: coreItem.panes,
                    zoomMode: coreItem.zoomMode,
                    arrangements: coreItem.arrangements,
                    minimizedCount: coreItem.minimizedCount,
                    notificationDotColor: notificationDotColor(
                        for: attentionLanesByTabID[coreItem.id]
                    )
                )
            )
        }

        try cancellationCheck()
        return TabBarProjection(
            items: items,
            activeTabID: coreProjection.activeTabId
        )
    }

    private nonisolated static func notificationDotColor(
        for lane: InboxNotificationClaimLane?
    ) -> TabNotificationDotColor? {
        switch lane {
        case .actionNeeded:
            return .red
        case .safety:
            return .amber
        case .settledAgent:
            return .yellow
        case .activity, nil:
            return nil
        }
    }

    private nonisolated static func checkCancellation() throws(CancellationError) {
        guard Task.isCancelled else { return }
        throw CancellationError()
    }
}
