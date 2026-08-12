import Foundation

struct PullRequestDemandProjection {
    enum WindowPresentation: Equatable, Sendable {
        case visible
        case hidden
        case miniaturized
        case occluded
    }

    struct ExpandedDrawer: Sendable {
        let parentPaneId: UUID
        let paneIds: Set<UUID>
        let minimizedPaneIds: Set<UUID>
    }

    struct Zoom: Sendable {
        let sourcePaneId: UUID
        let visibleCompanionWorktreeId: UUID?
    }

    struct Input: Sendable {
        let windowPresentation: WindowPresentation
        let sidebarWorktreeIds: Set<UUID>
        let activeLayoutPaneIds: Set<UUID>
        let minimizedLayoutPaneIds: Set<UUID>
        let isManagementLayerActive: Bool
        let expandedDrawer: ExpandedDrawer?
        let zoom: Zoom?
        let worktreeIdByPaneId: [UUID: UUID]
    }

    static func worktreeIds(from input: Input) -> Set<UUID> {
        guard input.windowPresentation == .visible else { return [] }

        var demandedWorktreeIds = input.sidebarWorktreeIds
        if let zoom = input.zoom {
            if let sourceWorktreeId = input.worktreeIdByPaneId[zoom.sourcePaneId] {
                demandedWorktreeIds.insert(sourceWorktreeId)
            }
            if let visibleCompanionWorktreeId = zoom.visibleCompanionWorktreeId {
                demandedWorktreeIds.insert(visibleCompanionWorktreeId)
            }
            return demandedWorktreeIds
        }

        var visiblePaneIds = input.activeLayoutPaneIds
        if !input.isManagementLayerActive {
            visiblePaneIds.subtract(input.minimizedLayoutPaneIds)
        }
        if let expandedDrawer = input.expandedDrawer,
            visiblePaneIds.contains(expandedDrawer.parentPaneId)
        {
            var visibleDrawerPaneIds = expandedDrawer.paneIds
            if !input.isManagementLayerActive {
                visibleDrawerPaneIds.subtract(expandedDrawer.minimizedPaneIds)
            }
            visiblePaneIds.formUnion(visibleDrawerPaneIds)
        }
        demandedWorktreeIds.formUnion(visiblePaneIds.compactMap { input.worktreeIdByPaneId[$0] })
        return demandedWorktreeIds
    }
}
