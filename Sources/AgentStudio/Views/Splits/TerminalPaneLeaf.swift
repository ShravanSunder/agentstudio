import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @ObservedObject private var managementMode = ManagementModeMonitor.shared

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
                PaneViewRepresentable(paneView: paneView)

                // Ghostty-style dimming for unfocused panes
                if !isActive {
                    Rectangle()
                        .fill(Color.black)
                        .opacity(0.15)
                        .allowsHitTesting(false)
                }

                // Hover border: drag affordance in management mode
                if managementMode.isActive && isHovered {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        .padding(1)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }

                // Drag handle: compact centered pill (edit mode + hover + no active drop).
                // Drawer children cannot be dragged out of their drawer.
                // The Color.clear fills the ZStack for centering; allowsHitTesting(false)
                // ensures only the capsule itself intercepts mouse events.
                if managementMode.isActive && isSplit && !isDrawerChild && isHovered && !isTargeted,
                   let tv = terminalView,
                   let worktree = tv.worktree,
                   let repo = tv.repo {
                    ZStack {
                        Color.clear
                            .allowsHitTesting(false)
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(
                            width: max(60, geometry.size.width * 0.2),
                            height: max(60 * 1.6, geometry.size.width * 0.2 * 1.6)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .draggable(PaneDragPayload(
                            paneId: tv.id,
                            tabId: tabId,
                            worktreeId: worktree.id,
                            repoId: repo.id
                        )) {
                            // Solid drag preview — .ultraThinMaterial renders as
                            // concentric circles when captured without a background.
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.windowBackgroundColor).opacity(0.8))
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: max(60, geometry.size.width * 0.2),
                                   height: max(96, geometry.size.width * 0.2 * 1.6))
                        }
                    }
                }

                // Drop zone overlay
                if isTargeted, let zone = dropZone {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }

                // Pane controls: minimize + close (top-left, edit mode + hover)
                if managementMode.isActive && isHovered {
                    VStack {
                        HStack(spacing: 4) {
                            Button {
                                action(.minimizePane(tabId: tabId, paneId: paneView.id))
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .background(Circle().fill(.black.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                            .help("Minimize pane")

                            Button {
                                action(.closePane(tabId: tabId, paneId: paneView.id))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .background(Circle().fill(.black.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                            .help("Close pane")

                            Spacer()
                        }
                        .padding(6)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Quarter-moon split button (top-right, edit mode + hover, layout panes only)
                // Drawer children use the icon bar [+] button to add panes.
                if managementMode.isActive && isHovered && !isDrawerChild {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                action(.insertPane(
                                    source: .newTerminal,
                                    targetTabId: tabId,
                                    targetPaneId: paneView.id,
                                    direction: .right
                                ))
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 20, height: 36)
                                    .background(
                                        UnevenRoundedRectangle(
                                            topLeadingRadius: 10,
                                            bottomLeadingRadius: 10,
                                            bottomTrailingRadius: 0,
                                            topTrailingRadius: 0
                                        )
                                        .fill(Color.black.opacity(0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Split right")
                        }
                        .padding(.top, 6)
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
            .onDrop(of: [.agentStudioTab, .agentStudioNewTab, .agentStudioPane], delegate: SplitDropDelegate(
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
        .padding(2)
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
        info.hasItemsConforming(to: [.agentStudioTab, .agentStudioNewTab, .agentStudioPane])
    }

    func dropEntered(info: DropInfo) {
        let zone = DropZone.calculate(at: info.location, in: viewSize)
        dropZone = zone
        isTargeted = shouldAcceptDrop(destination.id, zone)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let zone = DropZone.calculate(at: info.location, in: viewSize)
        dropZone = zone
        let accepted = shouldAcceptDrop(destination.id, zone)
        isTargeted = accepted
        return DropProposal(operation: accepted ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
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
                guard let data,
                      let payload = try? JSONDecoder().decode(TabDragPayload.self, from: data) else {
                    return
                }

                DispatchQueue.main.async {
                    let splitPayload = SplitDropPayload(kind: .existingTab(
                        tabId: payload.tabId,
                        worktreeId: payload.worktreeId,
                        repoId: payload.repoId,
                        title: payload.title
                    ))
                    onDrop(splitPayload, destination.id, zone)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.agentStudioPane.identifier) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.agentStudioPane.identifier) { data, error in
                guard let data,
                      let payload = try? JSONDecoder().decode(PaneDragPayload.self, from: data) else {
                    return
                }

                DispatchQueue.main.async {
                    let splitPayload = SplitDropPayload(kind: .existingPane(
                        paneId: payload.paneId,
                        sourceTabId: payload.tabId
                    ))
                    onDrop(splitPayload, destination.id, zone)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.agentStudioNewTab.identifier) {
            DispatchQueue.main.async {
                let splitPayload = SplitDropPayload(kind: .newTerminal)
                onDrop(splitPayload, destination.id, zone)
            }
            return true
        }

        return false
    }
}

// MARK: - UTType Extensions

extension UTType {
    /// Type for dragging existing tabs
    static let agentStudioTab = UTType(exportedAs: "com.agentstudio.tab")

    /// Type for dragging new tab button
    static let agentStudioNewTab = UTType(exportedAs: "com.agentstudio.newtab")

    /// Type for dragging individual panes
    static let agentStudioPane = UTType(exportedAs: "com.agentstudio.pane")
}

// MARK: - Drag Payloads

/// Payload for dragging an existing tab.
struct TabDragPayload: Codable, Transferable {
    let tabId: UUID
    let worktreeId: UUID
    let repoId: UUID
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioTab)
    }
}

/// Payload for dragging an individual pane.
struct PaneDragPayload: Codable, Transferable {
    let paneId: UUID
    let tabId: UUID
    let worktreeId: UUID
    let repoId: UUID

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
