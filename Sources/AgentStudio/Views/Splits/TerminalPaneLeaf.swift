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
    let action: (PaneAction) -> Void
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    @State private var dropZone: DropZone?
    @State private var isTargeted: Bool = false
    @State private var isHovered: Bool = false
    @ObservedObject private var managementMode = ManagementModeMonitor.shared

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
                if isSplit && !isActive {
                    Rectangle()
                        .fill(Color.black)
                        .opacity(0.15)
                        .allowsHitTesting(false)
                }

                // Hover border: drag affordance in management mode
                if managementMode.isActive && isHovered && isSplit {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        .padding(1)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }

                // Drag handle (top-left, management mode + hover only, terminal panes with worktree context)
                if managementMode.isActive && isHovered && isSplit, let tv = terminalView {
                    VStack {
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                                .draggable(PaneDragPayload(
                                    paneId: tv.id,
                                    tabId: tabId,
                                    worktreeId: tv.worktree.id,
                                    repoId: tv.repo.id
                                ))
                            Spacer()
                        }
                        Spacer()
                    }
                    .allowsHitTesting(true)
                }

                // Drop zone overlay
                if isTargeted, let zone = dropZone {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }

                // Close pane button (management mode only)
                if isSplit && managementMode.isActive {
                    Button {
                        action(.closePane(tabId: tabId, paneId: paneView.id))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity)
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
        .padding(2)
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
