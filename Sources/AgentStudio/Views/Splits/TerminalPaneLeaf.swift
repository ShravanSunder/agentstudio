import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Renders a single terminal pane with drop zone support for splitting.
struct TerminalPaneLeaf: View {
    let pane: TerminalPaneView
    let terminalView: AgentStudioTerminalView?
    let isActive: Bool
    let action: (SplitOperation) -> Void

    @State private var dropZone: DropZone?
    @State private var isTargeted: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Terminal view
                if let terminalView {
                    TerminalViewRepresentable(terminalView: terminalView)
                } else {
                    // Placeholder if terminal not yet created
                    Color(nsColor: .windowBackgroundColor)
                        .overlay {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                }

                // Focus border for active pane
                if isActive {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                        .padding(1)
                }

                // Drop zone overlay
                if isTargeted, let zone = dropZone {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                action(.focus(paneId: pane.id))
            }
            .onDrop(of: [.agentStudioTab, .agentStudioNewTab], delegate: SplitDropDelegate(
                viewSize: geometry.size,
                destination: pane,
                dropZone: $dropZone,
                isTargeted: $isTargeted,
                action: action
            ))
        }
    }
}

// MARK: - NSViewRepresentable for Terminal

/// Bridges AgentStudioTerminalView (NSView) into SwiftUI.
struct TerminalViewRepresentable: NSViewRepresentable {
    let terminalView: AgentStudioTerminalView

    func makeNSView(context: Context) -> NSView {
        // Create a container that will hold the terminal
        let container = NSView()
        container.wantsLayer = true

        // Add terminal as subview
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Terminal updates are handled by the view itself
    }
}

// MARK: - Drop Delegate

/// Handles drag-and-drop for split pane creation.
private struct SplitDropDelegate: DropDelegate {
    let viewSize: CGSize
    let destination: TerminalPaneView
    @Binding var dropZone: DropZone?
    @Binding var isTargeted: Bool
    let action: (SplitOperation) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.agentStudioTab, .agentStudioNewTab])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        dropZone = DropZone.calculate(at: info.location, in: viewSize)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropZone = DropZone.calculate(at: info.location, in: viewSize)
        return DropProposal(operation: .move)
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
        let providers = info.itemProviders(for: [.agentStudioTab, .agentStudioNewTab])
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
                        projectId: payload.projectId,
                        title: payload.title
                    ))
                    action(.drop(payload: splitPayload, destination: destination, zone: zone))
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.agentStudioNewTab.identifier) {
            DispatchQueue.main.async {
                let splitPayload = SplitDropPayload(kind: .newTerminal)
                action(.drop(payload: splitPayload, destination: destination, zone: zone))
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
}

// MARK: - Drag Payloads

/// Payload for dragging an existing tab.
struct TabDragPayload: Codable, Transferable {
    let tabId: UUID
    let worktreeId: UUID
    let projectId: UUID
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .agentStudioTab)
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
