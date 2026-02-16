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

            if let drawer, isIconBarVisible || drawer.isExpanded {
                // Icon bar (always visible when drawer has panes)
                DrawerIconBar(
                    drawerPanes: drawerPaneItems(from: drawer),
                    activeDrawerPaneId: drawer.activeDrawerPaneId,
                    isExpanded: drawer.isExpanded,
                    onSelect: { drawerPaneId in
                        action(.setActiveDrawerPane(parentPaneId: paneId, drawerPaneId: drawerPaneId))
                        if !drawer.isExpanded {
                            action(.toggleDrawer(paneId: paneId))
                        }
                    },
                    onAdd: {
                        addDrawerPane()
                    },
                    onClose: { drawerPaneId in
                        action(.removeDrawerPane(parentPaneId: paneId, drawerPaneId: drawerPaneId))
                    },
                    onToggleExpand: {
                        action(.toggleDrawer(paneId: paneId))
                    }
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

    private func drawerPaneItems(from drawer: Drawer) -> [DrawerPaneItem] {
        drawer.panes.map { drawerPane in
            DrawerPaneItem(
                id: drawerPane.id,
                title: drawerPane.metadata.title,
                icon: iconForContent(drawerPane.content)
            )
        }
    }

    private func iconForContent(_ content: PaneContent) -> String {
        switch content {
        case .terminal: return "terminal"
        case .webview: return "globe"
        case .codeViewer: return "doc.text"
        case .unsupported: return "questionmark.circle"
        }
    }
}
