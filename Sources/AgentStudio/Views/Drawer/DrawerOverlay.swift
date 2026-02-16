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
        let content = PaneContent.terminal(
            TerminalState(provider: .ghostty, lifetime: .temporary)
        )
        let metadata = PaneMetadata(
            source: .floating(workingDirectory: nil, title: nil),
            title: "Drawer"
        )
        action(.addDrawerPane(parentPaneId: paneId, content: content, metadata: metadata))
    }
}
