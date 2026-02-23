import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

private let splitLogger = Logger(subsystem: "com.agentstudio", category: "SplitDrop")

/// Renders a single pane leaf with drop zone support for splitting.
/// Handles terminal views (with surface dimming and drag handles) and
/// non-terminal views (webview, code viewer stubs) uniformly.
struct TerminalPaneLeaf: View {
    let paneView: PaneView
    let tabId: UUID
    let isActive: Bool
    let isSplit: Bool
    let store: WorkspaceStore
    let action: (PaneAction) -> Void
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    @State private var dropZone: DropZone?
    @State private var isTargeted: Bool = false
    @State private var isHovered: Bool = false
    @Bindable private var managementMode = ManagementModeMonitor.shared
    @State private var isMinimizeHovered: Bool = false
    @State private var isCloseHovered: Bool = false
    @State private var isSplitHovered: Bool = false

    /// Whether this pane is a drawer child (no drag, no drop, no sub-drawer).
    private var isDrawerChild: Bool {
        store.pane(paneView.id)?.isDrawerChild ?? false
    }

    /// Drawer state derived from store via @Observable tracking.
    /// Only layout panes have drawers; drawer children return nil.
    private var drawer: Drawer? {
        store.pane(paneView.id)?.drawer
    }

    /// Downcast to terminal view for terminal-specific features.
    private var terminalView: AgentStudioTerminalView? {
        paneView as? AgentStudioTerminalView
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // Pane content view
                // NOTE: .allowsHitTesting removed — investigating drop overlay bug.
                // The management mode dimming overlay handles click suppression instead.
                PaneViewRepresentable(paneView: paneView)

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
                if managementMode.isActive && isHovered && !store.isSplitResizing {
                    RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                        .strokeBorder(Color.white.opacity(AppStyle.strokeVisible), lineWidth: 1)
                        .padding(1)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: AppStyle.animationFast), value: isHovered)
                }

                // Drag handle: compact centered pill (management mode + hover + no active drop).
                // Drawer children cannot be dragged out of their drawer.
                // The Color.clear fills the ZStack for centering; allowsHitTesting(false)
                // ensures only the capsule itself intercepts mouse events.
                if managementMode.isActive && isSplit && !isDrawerChild && isHovered && !isTargeted
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
                                tabId: tabId
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

                // Drop zone overlay
                if isTargeted, let zone = dropZone {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }

                // Pane controls: minimize + close (top-left, management mode + hover)
                if managementMode.isActive && isHovered && !store.isSplitResizing {
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
                if managementMode.isActive && isHovered && !store.isSplitResizing {
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
            .onDrop(
                of: [.agentStudioTab, .agentStudioNewTab, .agentStudioPane],
                delegate: SplitDropDelegate(
                    viewSize: geometry.size,
                    destination: paneView,
                    dropZone: $dropZone,
                    isTargeted: $isTargeted,
                    shouldAcceptDrop: shouldAcceptDrop,
                    onDrop: onDrop
                ))
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .onChange(of: managementMode.isActive) { _, isActive in
            // Clear stale drag overlay when management mode toggles off
            if !isActive {
                isTargeted = false
                dropZone = nil
            }
        }
        .onChange(of: isHovered) { _, hovering in
            // Safety: clear stuck drop overlay when cursor leaves the pane.
            // SwiftUI's dropExited can be unreliable when drags cancel or
            // leave the window boundary.
            if !hovering && isTargeted {
                isTargeted = false
                dropZone = nil
            }
        }
        .padding(AppStyle.paneGap)
        .background(
            GeometryReader { geo in
                // Report pane frame for tab-level overlay positioning (layout panes only).
                // Drawer children are inside the drawer panel, not in the tab coordinate space.
                if !isDrawerChild {
                    Color.clear.preference(
                        key: PaneFramePreferenceKey.self,
                        value: [paneView.id: geo.frame(in: .named("tabContainer"))]
                    )
                } else {
                    Color.clear
                }
            }
        )
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

// MARK: - Drop Delegate

/// Handles drag-and-drop for split pane creation.
private struct SplitDropDelegate: DropDelegate {
    let viewSize: CGSize
    let destination: PaneView
    @Binding var dropZone: DropZone?
    @Binding var isTargeted: Bool
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        let valid = info.hasItemsConforming(to: [.agentStudioTab, .agentStudioNewTab, .agentStudioPane])
        splitLogger.debug("[DROP-DIAG] validateDrop: \(valid) for pane \(destination.id.uuidString.prefix(8))")
        return valid
    }

    func dropEntered(info: DropInfo) {
        let zone = DropZone.calculate(at: info.location, in: viewSize)
        dropZone = zone
        let accepted = shouldAcceptDrop(destination.id, zone)
        isTargeted = accepted
        splitLogger.debug(
            "[DROP-DIAG] dropEntered: zone=\(String(describing: zone)) accepted=\(accepted) pane=\(destination.id.uuidString.prefix(8))"
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let zone = DropZone.calculate(at: info.location, in: viewSize)
        dropZone = zone
        let accepted = shouldAcceptDrop(destination.id, zone)
        isTargeted = accepted
        return DropProposal(operation: accepted ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
        splitLogger.debug("[DROP-DIAG] dropExited: pane=\(destination.id.uuidString.prefix(8))")
        isTargeted = false
        dropZone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let zone = dropZone else { return false }

        isTargeted = false
        dropZone = nil

        // Try to load the drop payload
        let providers = info.itemProviders(for: [.agentStudioTab, .agentStudioNewTab, .agentStudioPane])
        guard let provider = providers.first else { return false }

        // Check which type of drop
        if provider.hasItemConformingToTypeIdentifier(UTType.agentStudioTab.identifier) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.agentStudioTab.identifier) { data, error in
                if let error {
                    splitLogger.warning("Tab drop: failed to load data — \(error.localizedDescription)")
                    return
                }
                guard let data,
                    let payload = try? JSONDecoder().decode(TabDragPayload.self, from: data)
                else {
                    splitLogger.warning("Tab drop: failed to decode TabDragPayload")
                    return
                }

                Task { @MainActor in
                    let splitPayload = SplitDropPayload(
                        kind: .existingTab(
                            tabId: payload.tabId
                        ))
                    onDrop(splitPayload, destination.id, zone)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.agentStudioPane.identifier) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.agentStudioPane.identifier) { data, error in
                if let error {
                    splitLogger.warning("Pane drop: failed to load data — \(error.localizedDescription)")
                    return
                }
                guard let data,
                    let payload = try? JSONDecoder().decode(PaneDragPayload.self, from: data)
                else {
                    splitLogger.warning("Pane drop: failed to decode PaneDragPayload")
                    return
                }

                Task { @MainActor in
                    let splitPayload = SplitDropPayload(
                        kind: .existingPane(
                            paneId: payload.paneId,
                            sourceTabId: payload.tabId
                        ))
                    onDrop(splitPayload, destination.id, zone)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.agentStudioNewTab.identifier) {
            Task { @MainActor in
                let splitPayload = SplitDropPayload(kind: .newTerminal)
                onDrop(splitPayload, destination.id, zone)
            }
            return true
        }

        return false
    }
}

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
