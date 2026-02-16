import SwiftUI

/// Tab-level overlay that renders the expanded drawer panel on top of all panes.
/// Positioned at the tab container level so it can extend beyond the originating
/// pane's bounds, with a trapezoid visually connecting the panel to the icon bar.
struct DrawerPanelOverlay: View {
    let store: WorkspaceStore
    let viewRegistry: ViewRegistry
    let tabId: UUID
    let paneFrames: [UUID: CGRect]
    let tabSize: CGSize
    let action: (PaneAction) -> Void

    @AppStorage("drawerHeightRatio") private var heightRatio: Double = 0.75

    /// Height of the DrawerIconBar (8px trapezoid + ~32px icon strip).
    /// Matches DrawerIconBar layout: TrapezoidConnector(8) + padded HStack(~32).
    private static let iconBarHeight: CGFloat = 40

    /// Find the pane whose drawer is currently expanded.
    /// Invariant: only one drawer can be expanded at a time (toggle behavior).
    private var expandedPaneInfo: (paneId: UUID, frame: CGRect, drawer: Drawer)? {
        for (paneId, frame) in paneFrames {
            if let drawer = store.pane(paneId)?.drawer,
               drawer.isExpanded, !drawer.paneIds.isEmpty {
                return (paneId, frame, drawer)
            }
        }
        return nil
    }

    var body: some View {
        // Read viewRevision so @Observable tracks it — triggers re-render after repair
        let _ = store.viewRevision

        if let info = expandedPaneInfo,
           let drawerTree = viewRegistry.renderTree(for: info.drawer.layout),
           tabSize.width > 0 {
            let paneWidth = info.frame.width
            let panelWidth = max(paneWidth, min(paneWidth * 2, tabSize.width * 0.8))
            let panelHeight = max(100, min(tabSize.height * CGFloat(heightRatio), tabSize.height - 60))
            let trapHeight: CGFloat = 12
            let totalHeight = panelHeight + trapHeight

            // Bottom of overlay trapezoid aligns with top of pane's icon bar
            let overlayBottomY = info.frame.maxY - Self.iconBarHeight
            let centerY = overlayBottomY - totalHeight / 2

            // Centered on originating pane, clamped to tab bounds
            let halfPanel = panelWidth / 2
            let centerX = max(halfPanel + 4, min(tabSize.width - halfPanel - 4, info.frame.midX))

            VStack(spacing: 0) {
                DrawerPanel(
                    tree: drawerTree,
                    parentPaneId: info.paneId,
                    tabId: tabId,
                    activePaneId: info.drawer.activePaneId,
                    minimizedPaneIds: info.drawer.minimizedPaneIds,
                    height: panelHeight,
                    store: store,
                    action: action,
                    onResize: { delta in
                        let newRatio = min(0.9, max(0.2, heightRatio + Double(delta / tabSize.height)))
                        heightRatio = newRatio
                    },
                    onDismiss: {
                        action(.toggleDrawer(paneId: info.paneId))
                    }
                )
                .frame(width: panelWidth)

                // Trapezoid: panel width at top → pane width at bottom
                DrawerOverlayTrapezoid(bottomRatio: paneWidth / panelWidth)
                    .fill(.ultraThinMaterial)
                    .frame(width: panelWidth, height: trapHeight)
            }
            .shadow(color: .black.opacity(0.4), radius: 16, y: -4)
            .position(x: centerX, y: centerY)
        }
    }
}

/// Trapezoid shape for the drawer overlay connector.
/// Full width at top (matches panel), narrower at bottom (matches originating pane).
struct DrawerOverlayTrapezoid: Shape {
    /// Ratio of bottom width to top width (0..1).
    let bottomRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let bottomInset = rect.width * (1 - min(1, max(0, bottomRatio))) / 2
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width - bottomInset, y: rect.height))
        path.addLine(to: CGPoint(x: bottomInset, y: rect.height))
        path.closeSubpath()
        return path
    }
}
