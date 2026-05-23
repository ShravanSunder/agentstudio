import Foundation

enum TabArrangementSelectionRules {
    static func firstUnminimizedPaneId(in arrangement: PaneArrangement) -> UUID? {
        arrangement.layout.paneIds.first {
            !arrangement.minimizedPaneIds.contains(MainPaneId($0))
        }
    }

    static func fallbackActivePaneId(
        currentActivePaneId: UUID?,
        in arrangement: PaneArrangement
    ) -> UUID? {
        if let currentActivePaneId,
            arrangement.layout.contains(currentActivePaneId),
            !arrangement.minimizedPaneIds.contains(MainPaneId(currentActivePaneId))
        {
            return currentActivePaneId
        }

        return firstUnminimizedPaneId(in: arrangement)
    }
}
