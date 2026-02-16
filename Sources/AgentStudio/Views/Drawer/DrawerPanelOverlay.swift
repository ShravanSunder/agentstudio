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

    @AppStorage("drawerHeightRatio") private var heightRatio: Double = 0.80

    /// Height of the DrawerIconBar (8px trapezoid + ~32px icon strip).
    /// Matches DrawerIconBar layout: TrapezoidConnector(8) + padded HStack(~32).
    private static let iconBarHeight: CGFloat = 40

    /// Find the pane whose drawer is currently expanded.
    /// Invariant: only one drawer can be expanded at a time (toggle behavior).
    private var expandedPaneInfo: (paneId: UUID, frame: CGRect, drawer: Drawer)? {
        for (paneId, frame) in paneFrames {
            if let drawer = store.pane(paneId)?.drawer,
               drawer.isExpanded {
                return (paneId, frame, drawer)
            }
        }
        return nil
    }

    var body: some View {
        // Read viewRevision so @Observable tracks it — triggers re-render after repair
        let _ = store.viewRevision

        if let info = expandedPaneInfo, tabSize.width > 0 {
            let drawerTree = viewRegistry.renderTree(for: info.drawer.layout)
            let panelWidth = tabSize.width * 0.8
            let panelHeight = max(100, min(tabSize.height * CGFloat(heightRatio), tabSize.height - 60))
            let trapHeight: CGFloat = 60
            let totalHeight = panelHeight + trapHeight

            // Bottom of overlay trapezoid aligns with top of pane's icon bar
            let overlayBottomY = info.frame.maxY - Self.iconBarHeight
            let centerY = overlayBottomY - totalHeight / 2

            // Centered on originating pane, clamped to tab bounds
            let halfPanel = panelWidth / 2
            let centerX = max(halfPanel + 4, min(tabSize.width - halfPanel - 4, info.frame.midX))

            // Asymmetric trapezoid insets: bottom edges align with pane borders.
            // Edge panes get a flush side (inset ≈ 0), middle panes get symmetric taper.
            let panelLeft = centerX - halfPanel
            let bottomLeftInset = max(0, info.frame.minX - panelLeft)
            let bottomRightInset = max(0, (panelLeft + panelWidth) - info.frame.maxX)

            VStack(spacing: 0) {
                let drawerRenderInfo = SplitRenderInfo.compute(
                    layout: info.drawer.layout,
                    minimizedPaneIds: info.drawer.minimizedPaneIds
                )
                DrawerPanel(
                    tree: drawerTree ?? PaneSplitTree(),
                    parentPaneId: info.paneId,
                    tabId: tabId,
                    activePaneId: info.drawer.activePaneId,
                    minimizedPaneIds: info.drawer.minimizedPaneIds,
                    splitRenderInfo: drawerRenderInfo,
                    height: panelHeight,
                    store: store,
                    action: action,
                    onResize: { delta in
                        let newRatio = min(0.8, max(0.2, heightRatio + Double(delta / tabSize.height)))
                        heightRatio = newRatio
                    },
                    onDismiss: {
                        action(.toggleDrawer(paneId: info.paneId))
                    }
                )
                .frame(width: panelWidth)

                // Trapezoid: panel width at top → pane width at bottom (asymmetric)
                DrawerOverlayTrapezoid(bottomLeftInset: bottomLeftInset, bottomRightInset: bottomRightInset)
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
/// Supports asymmetric insets so edge panes get a flush side while middle panes taper symmetrically.
struct DrawerOverlayTrapezoid: Shape {
    /// How far the bottom-left corner is inset from the left edge (0 = flush).
    let bottomLeftInset: CGFloat
    /// How far the bottom-right corner is inset from the right edge (0 = flush).
    let bottomRightInset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))                                          // top-left
        path.addLine(to: CGPoint(x: rect.width, y: 0))                              // top-right
        path.addLine(to: CGPoint(x: rect.width - bottomRightInset, y: rect.height)) // bottom-right
        path.addLine(to: CGPoint(x: bottomLeftInset, y: rect.height))               // bottom-left
        path.closeSubpath()
        return path
    }
}
