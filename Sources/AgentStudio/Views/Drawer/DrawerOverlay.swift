import SwiftUI

/// Renders the drawer icon bar at the bottom of a pane leaf.
/// Panel rendering has moved to the tab-level DrawerPanelOverlay so it can
/// overlay across all panes without being clipped by the pane's bounds.
struct DrawerOverlay: View {
    let paneId: UUID
    let drawer: Drawer?
    let isIconBarVisible: Bool
    let action: (PaneAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            DrawerIconBar(
                isExpanded: drawer?.isExpanded ?? false,
                onAdd: { addDrawerPane() },
                onToggleExpand: { action(.toggleDrawer(paneId: paneId)) }
            )
        }
    }

    private func addDrawerPane() {
        action(.addDrawerPane(parentPaneId: paneId))
    }
}
