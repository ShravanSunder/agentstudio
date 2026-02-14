import SwiftUI

/// Manages drawer state and composes icon bar + panel for a single pane.
/// Positioned as an overlay at the bottom of a pane leaf.
struct DrawerOverlay: View {
    let paneId: UUID
    let drawer: Drawer?
    let isIconBarVisible: Bool
    let drawerPaneView: PaneView?
    let action: (PaneAction) -> Void

    @AppStorage("drawerHeightRatio") private var heightRatio: Double = 0.75

    var body: some View {
        GeometryReader { geometry in
            let maxHeight = geometry.size.height * CGFloat(heightRatio)

            VStack(spacing: 0) {
                Spacer()

                if let drawer, isIconBarVisible || drawer.isExpanded {
                    // Expanded panel (when drawer has content and is expanded)
                    if drawer.isExpanded, drawer.activeDrawerPaneId != nil {
                        DrawerPanel(
                            drawerPaneView: drawerPaneView,
                            height: maxHeight,
                            onResize: { delta in
                                let newRatio = min(0.9, max(0.2, heightRatio + Double(delta / geometry.size.height)))
                                heightRatio = newRatio
                            },
                            onDismiss: {
                                action(.toggleDrawer(paneId: paneId))
                            }
                        )
                    }

                    // Icon bar (always visible when drawer is shown)
                    DrawerIconBar(
                        drawerPanes: drawerPaneItems(from: drawer),
                        activeDrawerPaneId: drawer.activeDrawerPaneId,
                        onSelect: { drawerPaneId in
                            action(.setActiveDrawerPane(parentPaneId: paneId, drawerPaneId: drawerPaneId))
                            if !drawer.isExpanded {
                                action(.toggleDrawer(paneId: paneId))
                            }
                        },
                        onAdd: {
                            let content = PaneContent.terminal(
                                TerminalState(provider: .ghostty, lifetime: .temporary)
                            )
                            let metadata = PaneMetadata(
                                source: .floating(workingDirectory: nil, title: nil),
                                title: "Drawer"
                            )
                            action(.addDrawerPane(parentPaneId: paneId, content: content, metadata: metadata))
                        },
                        onClose: { drawerPaneId in
                            action(.removeDrawerPane(parentPaneId: paneId, drawerPaneId: drawerPaneId))
                        },
                        onToggleExpand: {
                            action(.toggleDrawer(paneId: paneId))
                        }
                    )
                }
            }
        }
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
