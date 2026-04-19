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
        switch requested {
        case .mainPane:
            return .mainPane(paneId: context.activeMainPaneId)

        case .emptyDrawer(let parentPaneId):
            guard
                context.activeMainPaneId == parentPaneId,
                context.expandedDrawerParentPaneId == parentPaneId,
                context.drawerPaneIds.isEmpty
            else {
                return .mainPane(paneId: context.activeMainPaneId)
            }
            return .emptyDrawer(parentPaneId: parentPaneId)

        case .drawerPane(let parentPaneId, let paneId):
            guard
                context.activeMainPaneId == parentPaneId,
                context.expandedDrawerParentPaneId == parentPaneId
            else {
                return .mainPane(paneId: context.activeMainPaneId)
            }

            guard !context.drawerPaneIds.isEmpty else {
                return .emptyDrawer(parentPaneId: parentPaneId)
            }

            if context.drawerPaneIds.contains(paneId),
                context.activeDrawerPaneId == paneId,
                !context.minimizedDrawerPaneIds.contains(paneId)
            {
                return .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
            }

            if let fallbackPaneId = context.activeDrawerPaneId,
                context.drawerPaneIds.contains(fallbackPaneId),
                !context.minimizedDrawerPaneIds.contains(fallbackPaneId)
            {
                return .drawerPane(parentPaneId: parentPaneId, paneId: fallbackPaneId)
            }

            return .emptyDrawer(parentPaneId: parentPaneId)
        }
    }
}
