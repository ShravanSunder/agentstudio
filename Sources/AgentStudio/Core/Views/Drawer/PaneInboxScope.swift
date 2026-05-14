import Foundation

struct PaneInboxScope: Equatable {
    let parentPaneId: UUID
    let paneIds: [UUID]
}

@MainActor
enum PaneInboxScopeResolver {
    static func resolve(
        anchorPaneId: UUID,
        pane: (UUID) -> Pane?
    ) -> PaneInboxScope {
        let parentPaneId = pane(anchorPaneId)?.parentPaneId ?? anchorPaneId
        let drawerPaneIds = pane(parentPaneId)?.drawer?.paneIds ?? []
        return PaneInboxScope(
            parentPaneId: parentPaneId,
            paneIds: orderedUnique([parentPaneId] + drawerPaneIds)
        )
    }

    private static func orderedUnique(_ paneIds: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return paneIds.filter { paneId in
            seen.insert(paneId).inserted
        }
    }
}
