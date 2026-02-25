import AppKit
import SwiftUI

/// Renders a single pane leaf container.
/// Handles terminal views (with surface dimming and drag handles) and
/// non-terminal views (webview, code viewer stubs) uniformly.
struct PaneLeafContainer: View {
    let paneView: PaneView
    let tabId: UUID
    let isActive: Bool
    let isSplit: Bool
    let store: WorkspaceStore
    let action: (PaneAction) -> Void
    let dropTargetCoordinateSpace: String?
    let useDrawerFramePreference: Bool

    @State private var isHovered: Bool = false
    @State private var globalFrame: CGRect = .zero
    @Bindable private var managementMode = ManagementModeMonitor.shared
    @State private var isMinimizeHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isSplitHovered: Bool = false

    init(
        paneView: PaneView,
        tabId: UUID,
        isActive: Bool,
        isSplit: Bool,
        store: WorkspaceStore,
        action: @escaping (PaneAction) -> Void,
        dropTargetCoordinateSpace: String? = "tabContainer",
        useDrawerFramePreference: Bool = false
    ) {
        self.paneView = paneView
        self.tabId = tabId
        self.isActive = isActive
        self.isSplit = isSplit
        self.store = store
        self.action = action
        self.dropTargetCoordinateSpace = dropTargetCoordinateSpace
        self.useDrawerFramePreference = useDrawerFramePreference
    }

    /// Whether this pane is a drawer child (no drag, no drop, no sub-drawer).
    private var isDrawerChild: Bool {
        store.pane(paneView.id)?.isDrawerChild ?? false
    }

    /// Drawer state derived from store via @Observable tracking.
    /// Only layout panes have drawers; drawer children return nil.
    private var drawer: Drawer? {
        store.pane(paneView.id)?.drawer
    }

    /// Parent pane ID for drawer children; nil for layout panes.
    private var drawerParentPaneId: UUID? {
        store.pane(paneView.id)?.parentPaneId
    }

    /// True when hover is active either via tracking events or by direct pointer query.
    /// The direct query fixes the Cmd+E case where management mode toggles while the
    /// pointer is already inside the pane and no hover transition event fires.
    private var isManagementHovered: Bool {
        isHovered || globalFrame.contains(NSEvent.mouseLocation)
    }

    /// Downcast to terminal view for terminal-specific features.
    private var terminalView: AgentStudioTerminalView? {
        paneView as? AgentStudioTerminalView
    }

    private var movePaneDestinations: [(tabId: UUID, title: String)] {
        store.tabs.enumerated().compactMap { index, tab in
            guard tab.id != tabId else { return nil }
            guard tab.activePaneId ?? tab.paneIds.first != nil else { return nil }
            let title = tabDisplayTitle(tab: tab)
            return (tab.id, "Tab \(index + 1): \(title)")
        }
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topTrailing) {
                // Pane content view
                PaneViewRepresentable(paneView: paneView)
                    // In management mode, route drag targeting through the shared
                    // SwiftUI leaf container so pane type (WKWebView/Ghostty/etc.)
                    // cannot intercept drop updates differently.
                    .allowsHitTesting(!managementMode.isActive)

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
                if managementMode.isActive && isManagementHovered && !store.isSplitResizing {
                    RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                        .strokeBorder(Color.white.opacity(AppStyle.strokeVisible), lineWidth: 1)
                        .padding(1)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: AppStyle.animationFast), value: isManagementHovered)
                }

                // Drag handle: compact centered pill (management mode + hover + no active drop).
                // The Color.clear fills the ZStack for centering; allowsHitTesting(false)
                // ensures only the capsule itself intercepts mouse events.
                if managementMode.isActive && isManagementHovered
                    && !store.isSplitResizing
                {
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
                                paneId: paneView.id,
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

                // Pane controls: minimize + close (top-left, management mode + hover)
                if managementMode.isActive && isManagementHovered && !store.isSplitResizing {
                    VStack {
                        HStack(spacing: AppStyle.spacingStandard) {
                            Button {
                                action(.minimizePane(tabId: tabId, paneId: paneView.id))
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
                                action(.closePane(tabId: tabId, paneId: paneView.id))
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

                            Spacer()
                        }
                        .padding(AppStyle.spacingStandard)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Quarter-moon split button (top-right, management mode + hover)
                if managementMode.isActive && isManagementHovered && !store.isSplitResizing {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                action(
                                    .insertPane(
                                        source: .newTerminal,
                                        targetTabId: tabId,
                                        targetPaneId: paneView.id,
                                        direction: .right
                                    ))
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: AppStyle.paneSplitIconSize, weight: .bold))
                                    .foregroundStyle(
                                        .white.opacity(
                                            isSplitHovered
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
                                                isSplitHovered
                                                    ? AppStyle.managementControlFill
                                                        + AppStyle.managementControlHoverDelta
                                                    : AppStyle.managementControlFill))
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
                            .onHover { isSplitHovered = $0 }
                            .help("Split right")
                        }
                        .padding(.top, AppStyle.spacingStandard)
                        Spacer()
                    }
                    .allowsHitTesting(true)
                    .transition(.opacity)
                }

                // Drawer icon bar (bottom of pane, layout panes only — no nested drawers)
                if !isDrawerChild {
                    DrawerOverlay(
                        paneId: paneView.id,
                        drawer: drawer,
                        isIconBarVisible: true,
                        action: action
                    )
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                action(.focusPane(tabId: tabId, paneId: paneView.id))
            }
            .contextMenu {
                if managementMode.isActive && !isDrawerChild {
                    Button("Extract Pane to New Tab") {
                        action(.extractPaneToTab(tabId: tabId, paneId: paneView.id))
                    }

                    Menu("Move Pane to Tab") {
                        ForEach(movePaneDestinations, id: \.tabId) { destination in
                            Button(destination.title) {
                                NotificationCenter.default.post(
                                    name: .movePaneToTabRequested,
                                    object: nil,
                                    userInfo: [
                                        "paneId": paneView.id,
                                        "sourceTabId": tabId,
                                        "targetTabId": destination.tabId,
                                    ]
                                )
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .padding(AppStyle.paneGap)
        .background(
            GeometryReader { geo in
                let global = geo.frame(in: .global)
                ZStack {
                    if let dropTargetCoordinateSpace {
                        // Report pane frame for overlay positioning in the configured container
                        // coordinate space (tab container or drawer container).
                        let rawFrame = geo.frame(in: .named(dropTargetCoordinateSpace))
                        let paneGap = AppStyle.paneGap
                        let measuredFrame = CGRect(
                            x: rawFrame.minX + paneGap,
                            y: rawFrame.minY + paneGap,
                            width: max(rawFrame.width - (paneGap * 2), 1),
                            height: max(rawFrame.height - (paneGap * 2), 1)
                        )
                        if useDrawerFramePreference {
                            Color.clear.preference(
                                key: DrawerPaneFramePreferenceKey.self,
                                value: [paneView.id: measuredFrame]
                            )
                        } else {
                            Color.clear.preference(
                                key: PaneFramePreferenceKey.self,
                                value: [paneView.id: measuredFrame]
                            )
                        }
                    } else {
                        Color.clear
                    }
                }
                .onAppear {
                    globalFrame = global
                }
                .onChange(of: global) { _, newGlobalFrame in
                    globalFrame = newGlobalFrame
                }
            }
        )
    }

    private func tabDisplayTitle(tab: Tab) -> String {
        let paneTitles = tab.paneIds.map(paneDisplayTitle)
        if paneTitles.count > 1 {
            return paneTitles.joined(separator: " | ")
        }
        return paneTitles.first ?? "Terminal"
    }

    private func paneDisplayTitle(_ paneId: UUID) -> String {
        guard let pane = store.pane(paneId) else { return "Terminal" }
        let rawTitle = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGenericTitle =
            rawTitle.isEmpty || rawTitle.localizedCaseInsensitiveCompare("Terminal") == .orderedSame
            || rawTitle.localizedCaseInsensitiveCompare("Drawer") == .orderedSame

        if isGenericTitle,
            let cwdName = pane.metadata.cwd?.lastPathComponent,
            !cwdName.isEmpty
        {
            return cwdName
        }

        return rawTitle.isEmpty ? "Terminal" : rawTitle
    }
}

// MARK: - NSViewRepresentable for PaneView

/// Bridges any PaneView (NSView) into SwiftUI.
/// Returns the stable swiftUIContainer — same NSView every time, preventing IOSurface reparenting.
struct PaneViewRepresentable: NSViewRepresentable {
    let paneView: PaneView

    func makeNSView(context: Context) -> NSView {
        paneView.swiftUIContainer
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Nothing — container is stable, pane manages itself
    }
}

/// Backwards-compatible alias.
typealias TerminalViewRepresentable = PaneViewRepresentable

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
