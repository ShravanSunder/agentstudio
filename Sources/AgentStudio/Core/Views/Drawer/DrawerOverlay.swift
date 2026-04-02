import SwiftUI

/// Renders the drawer icon bar at the bottom of a pane leaf.
/// Panel rendering has moved to the tab-level DrawerPanelOverlay so it can
/// overlay across all panes without being clipped by the pane's bounds.
struct DrawerOverlay: View {
    struct TrailingActions {
        let canOpenTarget: Bool
        let onOpenFinder: () -> Void
        let onOpenCursor: () -> Void
    }

    let paneId: UUID
    let drawer: Drawer?
    let isIconBarVisible: Bool
    let trailingActions: TrailingActions?
    let action: (PaneActionCommand) -> Void

    var body: some View {
        DrawerIconBar(
            isExpanded: drawer?.isExpanded ?? false,
            onAdd: { addDrawerPane() },
            onToggleExpand: { action(.toggleDrawer(paneId: paneId)) },
            trailingActions: trailingActions
        )
    }

    private func addDrawerPane() {
        action(.addDrawerPane(parentPaneId: paneId))
    }
}
