import Foundation

package struct WorkspaceFocusOwnerNormalizer {
    package struct Context: Equatable, Sendable {
        let activeMainPaneId: UUID?
        let expandedDrawerParentPaneId: UUID?
        let paneIds: [UUID]
        let activeDrawerPaneId: UUID?
        let minimizedDrawerPaneIds: Set<UUID>

        package init(
            activeMainPaneId: UUID?,
            expandedDrawerParentPaneId: UUID?,
            paneIds: [UUID],
            activeDrawerPaneId: UUID?,
            minimizedDrawerPaneIds: Set<UUID>
        ) {
            self.activeMainPaneId = activeMainPaneId
            self.expandedDrawerParentPaneId = expandedDrawerParentPaneId
            self.paneIds = paneIds
            self.activeDrawerPaneId = activeDrawerPaneId
            self.minimizedDrawerPaneIds = minimizedDrawerPaneIds
        }
    }

    package static func normalize(
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

        let requestedParentPaneId: UUID
        switch requested {
        case .mainPane:
            return .mainPane(paneId: activeMainPaneId)
        case .emptyDrawer(let parentPaneId):
            requestedParentPaneId = parentPaneId
        case .drawerPane(let parentPaneId, _):
            requestedParentPaneId = parentPaneId
        }

        guard requestedParentPaneId == expandedDrawerParentPaneId else {
            return .mainPane(paneId: activeMainPaneId)
        }

        let visibleDrawerPaneIds = context.paneIds.filter { paneId in
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
