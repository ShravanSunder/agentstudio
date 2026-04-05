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
    let onOpenPaneGitHub: (UUID) -> Void
    let dropTargetCoordinateSpace: String?
    let useDrawerFramePreference: Bool

    @State private var isHovered: Bool = false
    private var managementMode: ManagementModeAtom {
        atom(\.managementMode)
    }
    @State private var isMinimizeHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isSplitHovered: Bool = false
    @State private var isBrowserHovered: Bool = false

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
        self.onOpenPaneGitHub = onOpenPaneGitHub
        self.dropTargetCoordinateSpace = dropTargetCoordinateSpace
        self.useDrawerFramePreference = useDrawerFramePreference
    }

    /// Whether this pane is a drawer child (no drag, no drop, no sub-drawer).
    private var isDrawerChild: Bool {
        store.pane(paneHost.id)?.isDrawerChild ?? false
    }

    /// Drawer state derived from store via @Observable tracking.
    /// Only layout panes have drawers; drawer children return nil.
    private var drawer: Drawer? {
        store.pane(paneHost.id)?.drawer
    }

    /// Parent pane ID for drawer children; nil for layout panes.
    private var drawerParentPaneId: UUID? {
        store.pane(paneHost.id)?.parentPaneId
    }

    private var isClosing: Bool {
        closeTransitionCoordinator.closingPaneIds.contains(paneHost.id)
    }

    /// True when hover is active either via tracking events or by direct pointer query.
    /// The direct pointer query fixes the Cmd+E case where management mode toggles
    /// while the pointer is already inside the pane and no hover transition fires.
    private var isManagementHovered: Bool {
        isHovered || isPointerInsidePaneView
    }

    private var isPointerInsidePaneView: Bool {
        guard managementMode.isActive else { return false }
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
        store.tabs.enumerated().compactMap { index, tab in
            guard tab.id != tabId else { return nil }
            guard tab.activePaneId ?? tab.paneIds.first != nil else { return nil }
            let title = tabDisplayTitle(tab: tab)
            return (tab.id, "Tab \(index + 1): \(title)")
        }
    }

    private func normalizedMeasuredFrame(from rawFrame: CGRect) -> CGRect {
        let paneGap = AppStyle.paneGap
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
                        // In management mode, route drag targeting through the shared
                        // SwiftUI leaf container so pane type (WKWebView/Ghostty/etc.)
                        // cannot intercept drop updates differently.
                        .allowsHitTesting(!managementMode.isActive)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if managementMode.isActive && !isDrawerChild && managementContext.showsIdentityBlock {
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
                            action: actionDispatcher.dispatch
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Ghostty-style dimming for unfocused panes
                if !isActive {
                    Rectangle()
                        .fill(Color.black)
                        .opacity(AppStyle.strokeMuted)
                        .allowsHitTesting(false)
                }

                // Management mode dimming: persistent overlay signaling content is non-interactive
                if managementMode.isActive {
                    Rectangle()
                        .fill(Color.black)
                        .opacity(AppStyle.managementModeDimming)
                        .allowsHitTesting(false)
                }

                // Hover border: drag affordance in management mode
                if managementMode.isActive && isManagementHovered && !isSplitResizing {
                    RoundedRectangle(cornerRadius: AppStyle.panelCornerRadius)
                        .strokeBorder(Color.white.opacity(AppStyle.strokeVisible), lineWidth: 1)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: AppStyle.animationFast), value: isManagementHovered)
                }

                // Drag handle: compact centered pill in management mode.
                // The Color.clear fills the ZStack for centering; allowsHitTesting(false)
                // ensures only the capsule itself intercepts mouse events.
                if managementMode.isActive && !isSplitResizing {
                    ZStack {
                        Color.clear
                            .allowsHitTesting(false)
                        ZStack {
                            RoundedRectangle(cornerRadius: AppStyle.managementDragHandleCornerRadius)
                                .fill(Color.black.opacity(AppStyle.managementControlFill))
                                .shadow(color: .black.opacity(AppStyle.strokeVisible), radius: 4, y: 2)
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: AppStyle.toolbarIconSize, weight: .medium))
                                .foregroundStyle(.white.opacity(AppStyle.foregroundMuted))
                        }
                        .frame(
                            width: AppStyle.managementDragHandleWidth,
                            height: AppStyle.managementDragHandleHeight
                        )
                        .contentShape(
                            RoundedRectangle(cornerRadius: AppStyle.managementDragHandleCornerRadius)
                        )
                        .draggable(
                            PaneDragPayload(
                                paneId: paneHost.id,
                                tabId: tabId,
                                drawerParentPaneId: drawerParentPaneId
                            )
                        ) {
                            ZStack {
                                RoundedRectangle(cornerRadius: AppStyle.managementDragHandleCornerRadius)
                                    .fill(Color(.windowBackgroundColor).opacity(0.8))
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: AppStyle.toolbarIconSize, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(
                                width: AppStyle.managementDragHandleWidth,
                                height: AppStyle.managementDragHandleHeight
                            )
                        }
                    }
                }

                // Pane controls: minimize + close (top-left, management mode)
                if managementMode.isActive && !isSplitResizing {
                    VStack {
                        HStack(spacing: AppStyle.spacingStandard) {
                            Button {
                                actionDispatcher.dispatch(.minimizePane(tabId: tabId, paneId: paneHost.id))
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: AppStyle.managementActionIconSize, weight: .bold))
                                    .foregroundStyle(
                                        .white.opacity(
                                            isMinimizeHovered
                                                ? AppStyle.foregroundSecondary
                                                : AppStyle.foregroundMuted)
                                    )
                                    .frame(
                                        width: AppStyle.managementActionSize,
                                        height: AppStyle.managementActionSize
                                    )
                                    .background(
                                        Circle()
                                            .fill(
                                                Color.black.opacity(
                                                    isMinimizeHovered
                                                        ? AppStyle.managementControlFill
                                                            + AppStyle.managementControlHoverDelta
                                                        : AppStyle.managementControlFill))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isMinimizeHovered = $0 }
                            .help("Minimize pane")

                            Button {
                                beginCloseTransition()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: AppStyle.managementActionIconSize, weight: .bold))
                                    .foregroundStyle(
                                        .white.opacity(
                                            isCloseHovered
                                                ? AppStyle.foregroundSecondary
                                                : AppStyle.foregroundMuted)
                                    )
                                    .frame(
                                        width: AppStyle.managementActionSize,
                                        height: AppStyle.managementActionSize
                                    )
                                    .background(
                                        Circle()
                                            .fill(
                                                Color.black.opacity(
                                                    isCloseHovered
                                                        ? AppStyle.managementControlFill
                                                            + AppStyle.managementControlHoverDelta
                                                        : AppStyle.managementControlFill))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isCloseHovered = $0 }
                            .help("Close pane")
                            .disabled(isClosing)

                            Spacer()
                        }
                        .padding(AppStyle.spacingStandard)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Quarter-moon split and browser buttons (top-right, management mode)
                if managementMode.isActive && !isSplitResizing {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(spacing: AppStyle.spacingStandard) {
                                paneEdgeButton(
                                    systemName: "plus",
                                    isHovered: isSplitHovered,
                                    helpText: "Split right"
                                ) {
                                    actionDispatcher.dispatch(
                                        .insertPane(
                                            source: .newTerminal,
                                            targetTabId: tabId,
                                            targetPaneId: paneHost.id,
                                            direction: .right
                                        )
                                    )
                                }
                                .onHover { isSplitHovered = $0 }

                                paneEdgeButton(
                                    systemName: "globe",
                                    isHovered: isBrowserHovered,
                                    helpText: "Open GitHub for pane context"
                                ) {
                                    onOpenPaneGitHub(paneHost.id)
                                }
                                .onHover { isBrowserHovered = $0 }
                            }
                        }
                        .padding(.top, AppStyle.spacingStandard)
                        Spacer()
                    }
                    .allowsHitTesting(true)
                    .transition(.opacity)
                }

            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                actionDispatcher.dispatch(.focusPane(tabId: tabId, paneId: paneHost.id))
            }
            .opacity(isClosing ? 0.58 : 1)
            .scaleEffect(isClosing ? 0.985 : 1)
            .zIndex(isClosing ? 1 : 0)
            .animation(.easeOut(duration: AppStyle.animationFast), value: isClosing)
            .allowsHitTesting(!isClosing)
            .contextMenu {
                if managementMode.isActive && !isDrawerChild {
                    Button("Extract Pane to New Tab") {
                        actionDispatcher.dispatch(.extractPaneToTab(tabId: tabId, paneId: paneHost.id))
                    }

                    Menu("Move Pane to Tab") {
                        ForEach(movePaneDestinations, id: \.tabId) { destination in
                            Button(destination.title) {
                                guard
                                    let targetTab = store.tab(destination.tabId),
                                    let targetPaneId = targetTab.activePaneId ?? targetTab.paneIds.first
                                else { return }

                                actionDispatcher.dispatch(
                                    .insertPane(
                                        source: .existingPane(paneId: paneHost.id, sourceTabId: tabId),
                                        targetTabId: destination.tabId,
                                        targetPaneId: targetPaneId,
                                        direction: .right
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.panelCornerRadius))
        .padding(AppStyle.paneGap)
        .background(
            GeometryReader { geo in
                ZStack {
                    if let dropTargetCoordinateSpace {
                        // Report pane frame for overlay positioning in the configured container
                        // coordinate space (tab container or drawer container).
                        let rawFrame = geo.frame(in: .named(dropTargetCoordinateSpace))
                        let measuredFrame = normalizedMeasuredFrame(from: rawFrame)
                        if useDrawerFramePreference {
                            let tabRawFrame = geo.frame(in: .named("tabContainer"))
                            let tabMeasuredFrame = normalizedMeasuredFrame(from: tabRawFrame)
                            Color.clear.preference(
                                key: DrawerPaneFramePreferenceKey.self,
                                value: [paneHost.id: measuredFrame]
                            )
                            .preference(
                                key: PaneFramePreferenceKey.self,
                                value: [paneHost.id: tabMeasuredFrame]
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
        closeTransitionCoordinator.beginClosingPane(paneHost.id) {
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
                .font(.system(size: AppStyle.paneSplitIconSize, weight: .bold))
                .foregroundStyle(
                    .white.opacity(
                        isHovered
                            ? AppStyle.foregroundSecondary
                            : AppStyle.foregroundMuted)
                )
                .frame(
                    width: AppStyle.paneSplitButtonSize,
                    height: AppStyle.paneSplitButtonSize + 12
                )
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppStyle.panelCornerRadius + 4,
                        bottomLeadingRadius: AppStyle.panelCornerRadius + 4,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(
                        Color.black.opacity(
                            isHovered
                                ? AppStyle.managementControlFill
                                    + AppStyle.managementControlHoverDelta
                                : AppStyle.managementControlFill
                        )
                    )
                )
                .contentShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppStyle.panelCornerRadius + 4,
                        bottomLeadingRadius: AppStyle.panelCornerRadius + 4,
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
