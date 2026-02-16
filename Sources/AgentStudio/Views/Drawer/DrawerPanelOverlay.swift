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

    @AppStorage("drawerHeightRatio") private var heightRatio: Double = DrawerLayout.heightRatioMax

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
            let panelWidth = tabSize.width * DrawerLayout.panelWidthRatio
            let panelHeight = max(
                DrawerLayout.panelMinHeight,
                min(tabSize.height * CGFloat(heightRatio), tabSize.height - DrawerLayout.panelBottomMargin)
            )
            let trapHeight = DrawerLayout.trapezoidHeight
            let totalHeight = panelHeight + trapHeight

            // Bottom of overlay trapezoid aligns with top of pane's icon bar
            let overlayBottomY = info.frame.maxY - DrawerLayout.iconBarFrameHeight
            let centerY = overlayBottomY - totalHeight / 2

            // Centered on originating pane, clamped to tab bounds
            let halfPanel = panelWidth / 2
            let edgeMargin = DrawerLayout.tabEdgeMargin
            let centerX = max(halfPanel + edgeMargin, min(tabSize.width - halfPanel - edgeMargin, info.frame.midX))

            // Asymmetric trapezoid insets: bottom edges align with pane borders.
            // Edge panes get a flush side (inset ≈ 0), middle panes get symmetric taper.
            let panelLeft = centerX - halfPanel
            let insetPad = DrawerLayout.trapezoidInsetPadding
            let bottomLeftInset = max(0, info.frame.minX - panelLeft) + insetPad
            let bottomRightInset = max(0, (panelLeft + panelWidth) - info.frame.maxX) + insetPad

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
                        let newRatio = min(DrawerLayout.heightRatioMax, max(DrawerLayout.heightRatioMin, heightRatio + Double(delta / tabSize.height)))
                        heightRatio = newRatio
                    },
                    onDismiss: {
                        action(.toggleDrawer(paneId: info.paneId))
                    }
                )
                .frame(width: panelWidth)
                // Layered shadow — tight contact + soft ambient
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                // Trapezoid: visual bridge from panel to pane icon bar.
                // Uses same material as DrawerIconBar for cohesive look.
                DrawerOverlayTrapezoid(bottomLeftInset: bottomLeftInset, bottomRightInset: bottomRightInset)
                    .fill(.ultraThinMaterial)
                    .frame(width: panelWidth, height: trapHeight)
            }
            .position(x: centerX, y: centerY)
        }
    }
}

/// Unified outline shape tracing the panel (rounded top corners) and trapezoid connector
/// as a single continuous path, so the border reads as one cohesive element.
struct DrawerOutlineShape: Shape {
    let panelHeight: CGFloat
    let cornerRadius: CGFloat
    let bottomLeftInset: CGFloat
    let bottomRightInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let r = min(cornerRadius, panelHeight / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: r))
        // Top-left corner
        path.addArc(
            center: CGPoint(x: r, y: r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        // Top edge
        path.addLine(to: CGPoint(x: w - r, y: 0))
        // Top-right corner
        path.addArc(
            center: CGPoint(x: w - r, y: r),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        // Right side → panel bottom
        path.addLine(to: CGPoint(x: w, y: panelHeight))
        // Trapezoid right slope
        path.addLine(to: CGPoint(x: w - bottomRightInset, y: rect.height))
        // Trapezoid bottom
        path.addLine(to: CGPoint(x: bottomLeftInset, y: rect.height))
        // Trapezoid left slope → panel bottom-left
        path.addLine(to: CGPoint(x: 0, y: panelHeight))
        path.closeSubpath()
        return path
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
