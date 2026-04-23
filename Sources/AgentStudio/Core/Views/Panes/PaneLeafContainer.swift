import AppKit
import SwiftUI

@MainActor
private func ancestorChainDescription(for view: NSView) -> String {
    var nodes: [String] = []
    var current: NSView? = view
    while let currentView = current {
        nodes.append("class=\(type(of: currentView)) id=\(ObjectIdentifier(currentView))")
        current = currentView.superview
    }
    return nodes.joined(separator: " -> ")
}

/// Renders a single pane leaf container.
/// Handles terminal views (with surface dimming and drag handles) and
/// non-terminal views (webview, code viewer stubs) uniformly.
struct PaneLeafContainer: View {
    let paneHost: PaneHostView
    let tabId: UUID
    let isActive: Bool
    let isSplit: Bool
    let isSplitResizing: Bool
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let onOpenPaneGitHub: (UUID) -> Void
    let dropTargetCoordinateSpace: String?
    let useDrawerFramePreference: Bool

    @State private var isHovered: Bool = false
    private var managementLayer: ManagementLayerAtom {
        atom(\.managementLayer)
    }
    @State private var isDragHandleHovered: Bool = false
    @State private var isMinimizeHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isSplitHovered: Bool = false
    @State private var isBrowserHovered: Bool = false
    @State private var isDetachHovered: Bool = false

    init(
        paneHost: PaneHostView,
        tabId: UUID,
        isActive: Bool,
        isSplit: Bool,
        isSplitResizing: Bool,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler,
        onOpenPaneGitHub: @escaping (UUID) -> Void,
        dropTargetCoordinateSpace: String? = "tabContainer",
        useDrawerFramePreference: Bool = false
    ) {
        self.paneHost = paneHost
        self.tabId = tabId
        self.isActive = isActive
        self.isSplit = isSplit
        self.isSplitResizing = isSplitResizing
        self.store = store
        self.repoCache = repoCache
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.onPaneFocusTrigger = onPaneFocusTrigger
        self.onOpenPaneGitHub = onOpenPaneGitHub
        self.dropTargetCoordinateSpace = dropTargetCoordinateSpace
        self.useDrawerFramePreference = useDrawerFramePreference
    }

    /// Whether this pane is a drawer child (no drag, no drop, no sub-drawer).
    private var isDrawerChild: Bool {
        store.paneAtom.pane(paneHost.id)?.isDrawerChild ?? false
    }

    /// Drawer state derived from store via @Observable tracking.
    /// Only layout panes have drawers; drawer children return nil.
    private var drawer: Drawer? {
        store.paneAtom.pane(paneHost.id)?.drawer
    }

    /// Parent pane ID for drawer children; nil for layout panes.
    private var drawerParentPaneId: UUID? {
        store.paneAtom.pane(paneHost.id)?.parentPaneId
    }

    private var tabContainsExpandedDrawer: Bool {
        guard let tab = store.tabLayoutAtom.tab(tabId) else { return false }
        return tab.paneIds.contains { paneId in
            store.paneAtom.pane(paneId)?.drawer?.isExpanded == true
        }
    }

    private var suppressMainPaneManagementInteraction: Bool {
        PaneInteractionOcclusionPolicy.suppressMainPaneManagementInteraction(
            isDrawerChild: isDrawerChild,
            tabContainsExpandedDrawer: tabContainsExpandedDrawer
        )
    }

    private var isClosing: Bool {
        closeTransitionCoordinator.closingPaneIds.contains(paneHost.id)
    }

    /// True when hover is active either via tracking events or by direct pointer query.
    /// The direct pointer query fixes the Cmd+E case where management layer toggles
    /// while the pointer is already inside the pane and no hover transition fires.
    private var isManagementHovered: Bool {
        guard !suppressMainPaneManagementInteraction else { return false }
        return isHovered || isPointerInsidePaneView
    }

    private var isPointerInsidePaneView: Bool {
        guard !suppressMainPaneManagementInteraction else { return false }
        guard managementLayer.isActive else { return false }
        guard let window = paneHost.window else { return false }
        let pointInWindow = window.mouseLocationOutsideOfEventStream
        let pointInPane = paneHost.convert(pointInWindow, from: nil)
        return paneHost.bounds.contains(pointInPane)
    }

    /// Downcast to terminal view for terminal-specific features.
    private var terminalView: TerminalPaneMountView? {
        paneHost.mountedContent(as: TerminalPaneMountView.self)
    }

    private var movePaneDestinations: [(tabId: UUID, title: String)] {
        store.tabLayoutAtom.tabs.enumerated().compactMap { index, tab in
            guard tab.id != tabId else { return nil }
            guard tab.activePaneId ?? tab.activePaneIds.first != nil else { return nil }
            let title = tabDisplayTitle(tab: tab)
            return (tab.id, "Tab \(index + 1): \(title)")
        }
    }

    private func normalizedMeasuredFrame(from rawFrame: CGRect) -> CGRect {
        let paneGap = AppStyles.General.Layout.paneGap
        return CGRect(
            x: rawFrame.minX + paneGap,
            y: rawFrame.minY + paneGap,
            width: max(rawFrame.width - (paneGap * 2), 1),
            height: max(rawFrame.height - (paneGap * 2), 1)
        )
    }

    var body: some View {
        GeometryReader { _ in
            let managementContext = PaneManagementContext.project(
                paneId: paneHost.id,
                store: store
            )
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    PaneViewRepresentable(paneHost: paneHost)
                        // Force SwiftUI to recreate the representable when the host
                        // instance changes (e.g. after repair or placeholder retry).
                        // Without this, updateNSView is a no-op and the old NSView
                        // stays mounted.
                        .id(paneHost.hostIdentity)
                        // In management layer, route drag targeting through the shared
                        // SwiftUI leaf container so pane type (WKWebView/Ghostty/etc.)
                        // cannot intercept drop updates differently.
                        .allowsHitTesting(!managementLayer.isActive)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if managementLayer.isActive && !isDrawerChild && managementContext.showsIdentityBlock {
                        ManagementPaneIdentityStrip(context: managementContext)
                    }

                    if !isDrawerChild {
                        DrawerOverlay(
                            paneId: paneHost.id,
                            drawer: drawer,
                            isIconBarVisible: true,
                            trailingActions: DrawerOverlay.TrailingActions(
                                canOpenTarget: managementContext.targetPath != nil,
                                onOpenFinder: { openInFinder(managementContext) },
                                onOpenCursor: { openInCursor(managementContext) }
                            ),
                            action: actionDispatcher.dispatch,
                            onPaneFocusTrigger: onPaneFocusTrigger
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Regular inactive split panes keep a readable center and dim only the edge band.
                if isSplit && !isActive {
                    InactivePaneEdgeDimmingOverlay()
                }

                // Management layer dimming: persistent overlay signaling content is non-interactive
                if managementLayer.isActive {
                    Rectangle()
                        .fill(Color.black)
                        .opacity(AppStyles.Shell.ManagementLayer.modeDimmingOpacity)
                        .allowsHitTesting(false)
                }

                // Hover border: drag affordance in management layer
                if managementLayer.isActive
                    && isManagementHovered
                    && !isSplitResizing
                    && !suppressMainPaneManagementInteraction
                {
                    RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.panel)
                        .strokeBorder(Color.white.opacity(AppStyles.General.Stroke.visible), lineWidth: 1)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: AppStyles.General.Animation.fast), value: isManagementHovered)
                }

                // Drag handle: compact centered pill in management layer.
                // The Color.clear fills the ZStack for centering; allowsHitTesting(false)
                // ensures only the capsule itself intercepts mouse events.
                if managementLayer.isActive && !isSplitResizing && !suppressMainPaneManagementInteraction {
                    ZStack {
                        Color.clear
                            .allowsHitTesting(false)
                        ZStack {
                            RoundedRectangle(cornerRadius: AppStyles.Shell.ManagementLayer.dragHandleCornerRadius)
                                .fill(
                                    Color.black.opacity(
                                        AppStyles.Shell.ManagementLayer.backgroundOpacity(
                                            isHovered: isDragHandleHovered
                                        )
                                    )
                                )
                                .shadow(color: .black.opacity(AppStyles.General.Stroke.visible), radius: 4, y: 2)
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: AppStyles.General.Icon.toolbar, weight: .medium))
                                .foregroundStyle(
                                    .white.opacity(
                                        AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: isDragHandleHovered))
                                )
                        }
                        .frame(
                            width: AppStyles.Shell.ManagementLayer.dragHandleWidth,
                            height: AppStyles.Shell.ManagementLayer.dragHandleHeight
                        )
                        .contentShape(
                            RoundedRectangle(cornerRadius: AppStyles.Shell.ManagementLayer.dragHandleCornerRadius)
                        )
                        .onHover { hovered in
                            isDragHandleHovered = hovered
                            RestoreTrace.log(
                                "PaneLeafContainer.dragHandle.onHover hovered=\(hovered) pane=\(paneHost.id) drawerParent=\(drawerParentPaneId?.uuidString ?? "nil")"
                            )
                        }
                        .draggable(
                            PaneDragPayload(
                                paneId: paneHost.id,
                                tabId: tabId,
                                drawerParentPaneId: drawerParentPaneId
                            )
                        ) {
                            DragHandleDragPreview(
                                paneId: paneHost.id,
                                drawerParentPaneId: drawerParentPaneId,
                                tabId: tabId
                            )
                        }
                    }
                }

                // Pane controls: minimize + close (top-left, management layer)
                if managementLayer.isActive && !isSplitResizing && !suppressMainPaneManagementInteraction {
                    VStack {
                        HStack(spacing: AppStyles.General.Spacing.standard) {
                            Button {
                                actionDispatcher.dispatch(.minimizePane(tabId: tabId, paneId: paneHost.id))
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: AppStyles.Shell.ManagementLayer.actionIconSize, weight: .bold))
                                    .foregroundStyle(
                                        .white.opacity(
                                            AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: isMinimizeHovered))
                                    )
                                    .frame(
                                        width: AppStyles.Shell.ManagementLayer.actionSize,
                                        height: AppStyles.Shell.ManagementLayer.actionSize
                                    )
                                    .background(
                                        Circle()
                                            .fill(
                                                Color.black.opacity(
                                                    AppStyles.Shell.ManagementLayer.backgroundOpacity(
                                                        isHovered: isMinimizeHovered)))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isMinimizeHovered = $0 }
                            .help(AppCommand.minimizePane.definition.helpText)

                            Button {
                                beginCloseTransition()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: AppStyles.Shell.ManagementLayer.actionIconSize, weight: .bold))
                                    .foregroundStyle(
                                        .white.opacity(
                                            AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: isCloseHovered))
                                    )
                                    .frame(
                                        width: AppStyles.Shell.ManagementLayer.actionSize,
                                        height: AppStyles.Shell.ManagementLayer.actionSize
                                    )
                                    .background(
                                        Circle()
                                            .fill(
                                                Color.black.opacity(
                                                    AppStyles.Shell.ManagementLayer.backgroundOpacity(
                                                        isHovered: isCloseHovered)))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isCloseHovered = $0 }
                            .help(AppCommand.closePane.definition.helpText)
                            .disabled(isClosing)

                            Spacer()
                        }
                        .padding(AppStyles.General.Spacing.standard)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Quarter-moon split and browser buttons (top-right, management layer)
                if managementLayer.isActive && !isSplitResizing && !suppressMainPaneManagementInteraction {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(spacing: AppStyles.General.Spacing.standard) {
                                paneEdgeButton(
                                    systemName: "plus",
                                    isHovered: isSplitHovered,
                                    helpText: AppCommand.splitRight.definition.helpText
                                ) {
                                    actionDispatcher.dispatch(
                                        .insertPane(
                                            source: .newTerminal,
                                            targetTabId: tabId,
                                            targetPaneId: paneHost.id,
                                            direction: .right,
                                            sizingMode: .halveTarget
                                        )
                                    )
                                }
                                .onHover { isSplitHovered = $0 }

                                paneEdgeButton(
                                    systemName: "globe",
                                    isHovered: isBrowserHovered,
                                    helpText: LocalActionSpec.openGitHubInNewTab.actionSpec.helpText
                                ) {
                                    onOpenPaneGitHub(paneHost.id)
                                }
                                .onHover { isBrowserHovered = $0 }
                            }
                        }
                        .padding(.top, AppStyles.General.Spacing.standard)
                        Spacer()

                        if isDrawerChild {
                            HStack {
                                Spacer()
                                paneEdgeButton(
                                    systemName: AppCommand.detachDrawerPane.definition.icon ?? "arrow.up.right.square",
                                    isHovered: isDetachHovered,
                                    helpText: AppCommand.detachDrawerPane.definition.helpText
                                ) {
                                    CommandDispatcher.shared.dispatch(
                                        .detachDrawerPane,
                                        target: paneHost.id,
                                        targetType: .pane
                                    )
                                }
                                .onHover { isDetachHovered = $0 }
                            }
                            .padding(.bottom, AppStyles.General.Spacing.standard)
                        }
                    }
                    .allowsHitTesting(true)
                    .transition(.opacity)
                }

            }
            .contentShape(Rectangle())
            .onHover { isHovered = suppressMainPaneManagementInteraction ? false : $0 }
            .onTapGesture {
                if let drawerParentPaneId {
                    onPaneFocusTrigger(
                        .drawer(
                            .selectPane(parentPaneId: drawerParentPaneId, drawerPaneId: paneHost.id)
                        )
                    )
                } else {
                    onPaneFocusTrigger(
                        .contentClick(
                            PaneContentClickFocusTrigger(
                                targetPaneId: paneHost.id,
                                location: .content,
                                clickPhase: .completed
                            )
                        )
                    )
                }
            }
            .opacity(isClosing ? 0.58 : 1)
            .scaleEffect(isClosing ? 0.985 : 1)
            .zIndex(isClosing ? 1 : 0)
            .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: isClosing)
            .allowsHitTesting(!isClosing)
            .contextMenu {
                if managementLayer.isActive && !isDrawerChild {
                    Button(LocalActionSpec.extractPaneToNewTab.actionSpec.label) {
                        actionDispatcher.dispatch(.extractPaneToTab(tabId: tabId, paneId: paneHost.id))
                    }

                    Menu(LocalActionSpec.movePaneToTabMenu.actionSpec.label) {
                        ForEach(movePaneDestinations, id: \.tabId) { destination in
                            Button(destination.title) {
                                guard
                                    let targetTab = store.tabLayoutAtom.tab(destination.tabId),
                                    let targetPaneId = targetTab.activePaneId ?? targetTab.activePaneIds.first
                                else { return }

                                actionDispatcher.dispatch(
                                    .insertPane(
                                        source: .existingPane(paneId: paneHost.id, sourceTabId: tabId),
                                        targetTabId: destination.tabId,
                                        targetPaneId: targetPaneId,
                                        direction: .right,
                                        sizingMode: .halveTarget
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.panel))
        .padding(AppStyles.General.Layout.paneGap)
        .background(
            GeometryReader { geo in
                ZStack {
                    if let dropTargetCoordinateSpace {
                        // Report pane frame for overlay positioning in the configured container
                        // coordinate space (tab container or drawer container).
                        let rawFrame = geo.frame(in: .named(dropTargetCoordinateSpace))
                        let measuredFrame = normalizedMeasuredFrame(from: rawFrame)
                        let frameDestinations = PaneFramePublicationPolicy.destinations(
                            useDrawerFramePreference: useDrawerFramePreference
                        )
                        if frameDestinations.contains(.drawerContainer) {
                            Color.clear.preference(
                                key: DrawerPaneFramePreferenceKey.self,
                                value: [paneHost.id: measuredFrame]
                            )
                        } else {
                            Color.clear.preference(
                                key: PaneFramePreferenceKey.self,
                                value: [paneHost.id: measuredFrame]
                            )
                        }
                    } else {
                        Color.clear
                    }
                }
            }
        )
    }

    func beginCloseTransition() {
        RestoreTrace.log(
            "PaneLeafContainer.beginCloseTransition pane=\(paneHost.id) drawerChild=\(drawerParentPaneId != nil) tab=\(tabId) closing=\(isClosing)"
        )
        closeTransitionCoordinator.beginClosingPane(paneHost.id) {
            RestoreTrace.log(
                "PaneLeafContainer.performClose pane=\(self.paneHost.id) drawerChild=\(self.drawerParentPaneId != nil) tab=\(self.tabId)"
            )
            actionDispatcher.dispatch(.closePane(tabId: tabId, paneId: paneHost.id))
        }
    }

    private func tabDisplayTitle(tab: Tab) -> String {
        atom(\.paneDisplay).tabDisplayLabel(for: tab)
    }

    private func paneDisplayTitle(_ paneId: UUID) -> String {
        atom(\.paneDisplay).displayLabel(for: paneId)
    }

    private func paneEdgeButton(
        systemName: String,
        isHovered: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AppStyles.Shell.PaneChrome.paneSplitIconSize, weight: .bold))
                .foregroundStyle(
                    .white.opacity(AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: isHovered))
                )
                .frame(
                    width: AppStyles.Shell.PaneChrome.paneSplitButtonSize,
                    height: AppStyles.Shell.PaneChrome.paneSplitButtonSize + 12
                )
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(
                        Color.black.opacity(
                            AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: isHovered)
                        )
                    )
                )
                .contentShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomLeadingRadius: AppStyles.General.CornerRadius.panel + 4,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func openInFinder(_ context: PaneManagementContext) {
        guard let targetPath = context.targetPath else { return }
        ExternalWorkspaceOpener.openInFinder(targetPath)
    }

    private func openInCursor(_ context: PaneManagementContext) {
        guard let targetPath = context.targetPath else { return }
        ExternalWorkspaceOpener.openInPreferredEditor(targetPath)
    }

}

// MARK: - DragHandleDragPreview

/// Preview view shown by SwiftUI's `.draggable(_:preview:)` when a drag session
/// actually begins. By wrapping the preview in a dedicated `View` struct with
/// `init` + `onAppear` traces, we can distinguish "SwiftUI evaluated the preview
/// closure during body construction" (doesn't mean a drag started) from
/// "SwiftUI initiated an NSDraggingSession and is rendering this preview
/// attached to the cursor" (definitive signal that .draggable recognized).
struct DragHandleDragPreview: View {
    let paneId: UUID
    let drawerParentPaneId: UUID?
    let tabId: UUID

    init(paneId: UUID, drawerParentPaneId: UUID?, tabId: UUID) {
        self.paneId = paneId
        self.drawerParentPaneId = drawerParentPaneId
        self.tabId = tabId
        RestoreTrace.log(
            "DragHandleDragPreview.init pane=\(paneId) drawerParent=\(drawerParentPaneId?.uuidString ?? "nil") tab=\(tabId)"
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppStyles.Shell.ManagementLayer.dragHandleCornerRadius)
                .fill(Color(.windowBackgroundColor).opacity(0.8))
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: AppStyles.General.Icon.toolbar, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(
            width: AppStyles.Shell.ManagementLayer.dragHandleWidth,
            height: AppStyles.Shell.ManagementLayer.dragHandleHeight
        )
        .onAppear {
            let sessionID = DragSession.start()
            let source = drawerParentPaneId == nil ? "main-pane" : "drawer-pane"
            RestoreTrace.log(
                "DragHandleDragPreview.onAppear session=\(sessionID) source=\(source) pane=\(paneId) drawerParent=\(drawerParentPaneId?.uuidString ?? "nil") tab=\(tabId)"
            )
        }
        .onDisappear {
            RestoreTrace.log(
                "DragHandleDragPreview.onDisappear pane=\(paneId) drawerParent=\(drawerParentPaneId?.uuidString ?? "nil") tab=\(tabId)"
            )
        }
    }
}

// MARK: - NSViewRepresentable for PaneHostView

/// Bridges any PaneHostView (NSView) into SwiftUI.
/// Returns the stable swiftUIContainer — same NSView every time, preventing IOSurface reparenting.
struct PaneViewRepresentable: NSViewRepresentable {
    let paneHost: PaneHostView

    #if DEBUG
        static var onDismantleForTesting: (() -> Void)?
    #endif

    func makeNSView(context: Context) -> NSView {
        RestoreTrace.log(
            "PaneViewRepresentable.makeNSView paneId=\(paneHost.paneId) containerId=\(ObjectIdentifier(paneHost.swiftUIContainer)) hostId=\(ObjectIdentifier(paneHost))"
        )
        return paneHost.swiftUIContainer
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Nothing — container is stable, pane manages itself.
        // Host replacement is handled by .id(paneHost.hostIdentity) on the
        // PaneViewRepresentable call site, which forces SwiftUI to dismantle
        // and recreate when the host instance changes.
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        RestoreTrace.log(
            "PaneViewRepresentable.dismantleNSView viewId=\(ObjectIdentifier(nsView)) superview=\(nsView.superview != nil) window=\(nsView.window != nil) ancestry=\(ancestorChainDescription(for: nsView))"
        )
        #if DEBUG
            onDismantleForTesting?()
        #endif
    }
}

@available(*, deprecated, renamed: "PaneLeafContainer")
typealias TerminalPaneLeaf = PaneLeafContainer

// MARK: - Drag Payloads

/// Payload for dragging an existing tab.
struct TabDragPayload: Codable, Transferable {
    let tabId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioTab)
    }
}

/// Payload for dragging an individual pane.
struct PaneDragPayload: Codable, Transferable {
    let paneId: UUID
    let tabId: UUID
    let drawerParentPaneId: UUID?

    init(paneId: UUID, tabId: UUID, drawerParentPaneId: UUID? = nil) {
        self.paneId = paneId
        self.tabId = tabId
        self.drawerParentPaneId = drawerParentPaneId
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioPane)
    }
}

/// Payload for dragging the new tab button.
struct NewTabDragPayload: Codable, Transferable {
    var timestamp: Date

    init() {
        self.timestamp = Date()
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioNewTab)
    }
}
