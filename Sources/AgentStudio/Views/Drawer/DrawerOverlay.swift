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

            if let drawer, !drawer.paneIds.isEmpty, isIconBarVisible || drawer.isExpanded {
                // Drawer has panes — show toggle/add bar
                DrawerIconBar(
                    isExpanded: drawer.isExpanded,
                    onAdd: { addDrawerPane() },
                    onToggleExpand: { action(.toggleDrawer(paneId: paneId)) }
                )
            } else {
                // Empty drawer: slim bar with [+] button
                EmptyDrawerBar(onAdd: addDrawerPane)
            }
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
