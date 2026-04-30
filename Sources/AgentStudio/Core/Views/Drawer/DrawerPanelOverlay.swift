import AppKit
import SwiftUI

// MARK: - Dismiss Monitor

/// Monitors mouseDown events and dismisses the drawer when clicking outside
/// the drawer panel, connector, and icon bar regions.
/// Installed when the drawer opens, removed when it closes.
@MainActor
final class DrawerDismissMonitor {
    private var monitor: Any?
    /// Drawer panel + connector bounding rect in global (flipped window) coordinates.
    var drawerRect: CGRect = .zero
    /// Icon bar bounding rect in global (flipped window) coordinates.
    var iconBarRect: CGRect = .zero

    var onDismiss: () -> Void = {}

    init() {}

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            guard let window = event.window else { return event }

            // Convert event location to flipped screen coordinates matching SwiftUI .global.
            // AppKit screen coords: origin at bottom-left of main screen, Y grows up.
            // SwiftUI .global:      origin at top-left of main screen, Y grows down.
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            guard let screenMaxY = (window.screen ?? NSScreen.main)?.frame.maxY else { return event }
            let globalPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

            // Returning nil consumes the event so the same click cannot also
            // make the underlying main pane firstResponder. Returning event
            // would dismiss the drawer AND focus whatever NSView is below —
            // a regression where outside clicks toggle drawer visibility but
            // also activate the main pane content underneath.
            return self.handleMouseDown(globalPoint: globalPoint) ? nil : event
        }
    }

    /// Outside-click dismissal test.
    ///
    /// Returns true when the click is outside both the drawer panel + connector
    /// region and the icon bar. Empty rects contain no points, so a click
    /// during a transient frame reset is treated as "outside both" and
    /// dismisses — this matches the working debug-branch behavior. The
    /// non-zero-only preference reducers keep `drawerRect` and `iconBarRect`
    /// stable across SwiftUI re-publish cycles.
    func shouldDismiss(globalPoint: CGPoint) -> Bool {
        !drawerRect.contains(globalPoint) && !iconBarRect.contains(globalPoint)
    }

    @discardableResult
    func handleMouseDown(globalPoint: CGPoint) -> Bool {
        guard shouldDismiss(globalPoint: globalPoint) else { return false }
        onDismiss()
        return true
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Preference Key for Drawer Panel Global Frame

/// Reports the drawer panel's frame in the global coordinate space for outside-click dismissal.
///
/// The reducer keeps the last non-zero value. SwiftUI publishes `.zero` during
/// transitions and teardown; accepting those would erase the real frame and
/// silently break the dismiss monitor's outside-click test.
struct DrawerPanelGlobalFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Preference Key for Drawer Panel Frame in Tab Space

/// Reports the drawer panel frame in the `"tabContainer"` coordinate space.
/// FlatTabStripContainer uses this to mount drawer drag capture at tab level.
///
/// Same non-zero-only reducer as `DrawerPanelGlobalFrameKey`: a transient
/// zero update during a transition must not unmount the drawer capture.
struct DrawerPanelFrameInTabKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Preference Key for Icon Bar Frame

/// Reports the icon bar's frame in the global coordinate space.
/// DrawerPanelOverlay reads this to exclude the icon bar from dismiss hit testing.
///
/// Same non-zero-only reducer: stale-but-real frame is preferred over a
/// transient zero so the dismiss monitor never loses its exclusion zone.
struct DrawerIconBarFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - DrawerPanelOverlay

/// Tab-level overlay that renders the expanded drawer panel on top of all panes.
/// Positioned at the tab container level so it can extend beyond the originating
/// pane's bounds, with an S-curve connector visually bridging the panel to the icon bar.
///
/// Uses an even-odd fill content shape to exclude the drawer area from dismiss
/// hit-testing, so only clicks genuinely outside the drawer dismiss it.
struct DrawerPanelOverlay: View {
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleAtom
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let tabId: UUID
    let paneFrames: [UUID: CGRect]
    let tabSize: CGSize
    let iconBarFrame: CGRect
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let drawerInboxPresentation: DrawerInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void
    let drawerDropTarget: DrawerRearrangeTarget?
    /// Active drag's source pane id, threaded through to DrawerPanel
    /// so its visuals dict applies the source-aware filter (R1, R2,
    /// R8/R13a).
    let dragSourcePaneId: UUID?

    @AppStorage("drawerHeightRatio") private var heightRatio: Double = DrawerLayout.heightRatioMax
    @State private var dismissMonitor = DrawerDismissMonitor()
    @State private var drawerPanelGlobalFrame: CGRect = .zero

    /// Find the pane whose drawer is currently expanded.
    /// Invariant: only one drawer can be expanded at a time (toggle behavior).
    private var expandedPaneInfo: (paneId: UUID, frame: CGRect, drawer: Drawer)? {
        for (paneId, frame) in paneFrames {
            if let drawer = store.paneAtom.pane(paneId)?.drawer,
                drawer.isExpanded
            {
                return (paneId, frame, drawer)
            }
        }
        return nil
    }

    /// Whether a drawer is currently expanded.
    private var isExpanded: Bool { expandedPaneInfo != nil }

    var body: some View {
        if let info = expandedPaneInfo, tabSize.width > 0 {
            let panelWidth = tabSize.width * DrawerLayout.panelWidthRatio
            let panelHeight = max(
                DrawerLayout.panelMinHeight,
                min(tabSize.height * CGFloat(heightRatio), tabSize.height - DrawerLayout.panelBottomMargin)
            )
            let connectorHeight = DrawerLayout.overlayConnectorHeight
            let totalHeight = panelHeight + connectorHeight

            // Bottom of overlay aligns with top of pane's icon bar
            let overlayBottomY = info.frame.maxY - iconBarFrame.height
            let centerY = overlayBottomY - totalHeight / 2

            // Centered on originating pane, clamped to tab bounds
            let halfPanel = panelWidth / 2
            let edgeMargin = DrawerLayout.tabEdgeMargin
            let centerX = max(halfPanel + edgeMargin, min(tabSize.width - halfPanel - edgeMargin, info.frame.midX))

            // Junction insets: panel edge to pane boundary
            let panelLeft = centerX - halfPanel
            let paneWidth = info.frame.width
            let junctionLeftInset = max(0, info.frame.minX - panelLeft)
            let junctionRightInset = max(0, (panelLeft + panelWidth) - info.frame.maxX)

            // Bottom insets: junction + 1/6 pane width (bottom bar = center 2/3 of pane)
            let bottomLeftInset = junctionLeftInset + paneWidth / 6
            let bottomRightInset = junctionRightInset + paneWidth / 6

            // Unified outline: panel (rounded rect) + S-curve connector
            let outlineShape = DrawerOutlineShape(
                panelHeight: panelHeight,
                cornerRadius: DrawerLayout.panelCornerRadius,
                junctionLeftInset: junctionLeftInset,
                junctionRightInset: junctionRightInset,
                bottomLeftInset: bottomLeftInset,
                bottomRightInset: bottomRightInset,
                bottomCornerRadius: DrawerLayout.connectorBottomCornerRadius
            )
            let panelFraction = panelHeight / totalHeight

            let paneId = info.paneId
            VStack(spacing: 0) {
                DrawerPanel(
                    layout: info.drawer.layout,
                    parentPaneId: paneId,
                    tabId: tabId,
                    activeChildId: info.drawer.activeChildId,
                    minimizedPaneIds: info.drawer.minimizedPaneIds,
                    closeTransitionCoordinator: closeTransitionCoordinator,
                    height: panelHeight,
                    store: store,
                    repoCache: repoCache,
                    viewRegistry: viewRegistry,
                    action: actionDispatcher.dispatch,
                    onResize: { delta in
                        let newRatio = min(
                            DrawerLayout.heightRatioMax,
                            max(DrawerLayout.heightRatioMin, heightRatio + Double(delta / tabSize.height)))
                        heightRatio = newRatio
                    },
                    onDismiss: {
                        actionDispatcher.dispatch(.toggleDrawer(paneId: paneId))
                        onPaneFocusTrigger(.drawer(.toggle(parentPaneId: paneId)))
                    },
                    onPaneFocusTrigger: onPaneFocusTrigger,
                    appLifecycleStore: appLifecycleStore,
                    drawerInboxPresentation: drawerInboxPresentation,
                    onOpenPaneGitHub: onOpenPaneGitHub,
                    dropTarget: drawerDropTarget,
                    dragSourcePaneId: dragSourcePaneId
                )
                .id(paneId)
                .frame(width: panelWidth)

                // Connector space (visual bridge from panel to icon bar)
                Color.clear
                    .frame(width: panelWidth, height: connectorHeight)
            }
            .modifier(DrawerMaterialModifier(shape: outlineShape, panelFraction: panelFraction))
            .contentShape(outlineShape)
            .shadow(color: .black.opacity(AppStyles.General.Stroke.muted), radius: 4, y: 2)
            .shadow(color: .black.opacity(AppStyles.General.Stroke.hover), radius: 16, y: 8)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: DrawerPanelGlobalFrameKey.self,
                            value: geometry.frame(in: .global)
                        )
                }
            )
            .position(x: centerX, y: centerY)
            .onPreferenceChange(DrawerPanelGlobalFrameKey.self) { drawerPanelGlobalFrame = $0 }
            .onAppear {
                dismissMonitor.onDismiss = {
                    actionDispatcher.dispatch(.toggleDrawer(paneId: paneId))
                    onPaneFocusTrigger(.drawer(.toggle(parentPaneId: paneId)))
                }
                dismissMonitor.drawerRect = drawerPanelGlobalFrame
                dismissMonitor.iconBarRect = iconBarFrame
                dismissMonitor.install()
            }
            .onDisappear {
                dismissMonitor.remove()
            }
            .task(id: paneId) {
                dismissMonitor.onDismiss = {
                    actionDispatcher.dispatch(.toggleDrawer(paneId: paneId))
                    onPaneFocusTrigger(.drawer(.toggle(parentPaneId: paneId)))
                }
            }
            .onChange(of: drawerPanelGlobalFrame) { _, frame in
                dismissMonitor.drawerRect = frame
            }
            .onChange(of: iconBarFrame) { _, frame in
                dismissMonitor.iconBarRect = frame
            }
        }
    }

}

// MARK: - DrawerOutlineShape

/// Unified outline tracing the panel (rounded rectangle with all 4 corners) and
/// S-curve connector as a single continuous path. The connector narrows from panel
/// width to the bottom bar width via smooth cubic bezier S-curves, then continues
/// with straight vertical sides to a rounded bottom edge.
struct DrawerOutlineShape: Shape {
    let panelHeight: CGFloat
    let cornerRadius: CGFloat
    let junctionLeftInset: CGFloat
    let junctionRightInset: CGFloat
    let bottomLeftInset: CGFloat
    let bottomRightInset: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = min(cornerRadius, panelHeight / 2)
        let br = bottomCornerRadius

        // Junction x-coordinates (where S-curves meet panel bottom edge)
        // Clamped to corner radius so S-curves start after panel corner arcs
        let jLeft = max(r, junctionLeftInset)
        let jRight = w - max(r, junctionRightInset)

        // Bottom bar x-coordinates
        let bLeft = bottomLeftInset
        let bRight = w - bottomRightInset

        // S-curves end just above the bottom corner arcs
        let sCurveBottomY = h - br

        var path = Path()

        // --- Panel: rounded rectangle (all 4 corners identical) ---

        path.move(to: CGPoint(x: 0, y: r))

        // Top-left corner
        path.addArc(
            center: CGPoint(x: r, y: r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: w - r, y: 0))

        // Top-right corner
        path.addArc(
            center: CGPoint(x: w - r, y: r),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: w, y: panelHeight - r))

        // Bottom-right panel corner
        path.addArc(
            center: CGPoint(x: w - r, y: panelHeight - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // --- Right S-curve: panel bottom → bottom bar ---

        path.addLine(to: CGPoint(x: jRight, y: panelHeight))
        // S-curve spans full connector height: horizontal start, vertical end
        path.addCurve(
            to: CGPoint(x: bRight, y: sCurveBottomY),
            control1: CGPoint(x: (jRight + bRight) / 2, y: panelHeight),
            control2: CGPoint(x: bRight, y: (panelHeight + sCurveBottomY) / 2)
        )

        // --- Bottom bar (rounded corners) ---

        path.addArc(
            center: CGPoint(x: bRight - br, y: h - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bLeft + br, y: h))
        path.addArc(
            center: CGPoint(x: bLeft + br, y: h - br),
            radius: br,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // --- Left S-curve: bottom bar → panel bottom ---

        // S-curve spans full connector height: vertical start, horizontal end
        path.addCurve(
            to: CGPoint(x: jLeft, y: panelHeight),
            control1: CGPoint(x: bLeft, y: (panelHeight + sCurveBottomY) / 2),
            control2: CGPoint(x: (jLeft + bLeft) / 2, y: panelHeight)
        )

        // Panel bottom edge to bottom-left panel corner
        path.addLine(to: CGPoint(x: r, y: panelHeight))

        // Bottom-left panel corner
        path.addArc(
            center: CGPoint(x: r, y: panelHeight - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - DrawerMaterialModifier

/// Applies liquid glass on macOS 26+, falls back to ultraThinMaterial on older versions.
/// Includes a gradient mask that keeps full material on the panel and fades the connector.
struct DrawerMaterialModifier: ViewModifier {
    let shape: DrawerOutlineShape
    let panelFraction: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay(connectorFadeOverlay)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
        }
    }

    /// Gradient overlay that transitions the connector from glass toward the toolbar color.
    /// Clear over the panel, gradually fading to the window background tint through the connector
    /// so the bottom visually matches the icon bar toolbar.
    private var connectorFadeOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: panelFraction),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.95), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}
