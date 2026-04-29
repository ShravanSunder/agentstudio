import Foundation

struct WorkspaceFocusOwnerNormalizer {
    struct Context: Equatable, Sendable {
        let activeMainPaneId: UUID?
        let expandedDrawerParentPaneId: UUID?
        let drawerPaneIds: [UUID]
        let activeDrawerPaneId: UUID?
        let minimizedDrawerPaneIds: Set<UUID>
    }

    static func normalize(
        requested: WorkspaceFocusOwner,
        context: Context
    ) -> WorkspaceFocusOwner {
        let activeMainPaneId = context.activeMainPaneId
        guard
            let expandedDrawerParentPaneId = context.expandedDrawerParentPaneId,
            expandedDrawerParentPaneId == activeMainPaneId
        else {
            return .mainPane(paneId: activeMainPaneId)
        }

        let requestedParentPaneId: UUID? =
            switch requested {
            case .mainPane:
                nil
            case .emptyDrawer(let parentPaneId):
                parentPaneId
            case .drawerPane(let parentPaneId, _):
                parentPaneId
            }

        guard requestedParentPaneId == nil || requestedParentPaneId == expandedDrawerParentPaneId else {
            return .mainPane(paneId: activeMainPaneId)
        }

        let visibleDrawerPaneIds = context.drawerPaneIds.filter { paneId in
            !context.minimizedDrawerPaneIds.contains(paneId)
        }

        if let activeDrawerPaneId = context.activeDrawerPaneId,
            visibleDrawerPaneIds.contains(activeDrawerPaneId)
        {
            return .drawerPane(parentPaneId: expandedDrawerParentPaneId, paneId: activeDrawerPaneId)
        }

        if let firstVisibleDrawerPaneId = visibleDrawerPaneIds.first {
            return .drawerPane(parentPaneId: expandedDrawerParentPaneId, paneId: firstVisibleDrawerPaneId)
        }

        return .emptyDrawer(parentPaneId: expandedDrawerParentPaneId)
    }
}
