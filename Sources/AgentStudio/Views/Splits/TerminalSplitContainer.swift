import SwiftUI
import AppKit

/// Operations that can be performed on the split tree.
enum SplitOperation: Equatable {
    case resize(paneId: UUID, ratio: CGFloat)
    case equalize
    case drop(payload: SplitDropPayload, destination: TerminalPaneView, zone: DropZone)
    case focus(paneId: UUID)
}

/// Payload for drag-and-drop split operations.
struct SplitDropPayload: Equatable, Codable {
    enum Kind: Equatable, Codable {
        case existingTab(tabId: UUID, worktreeId: UUID, projectId: UUID, title: String)
        case newTerminal
    }

    let kind: Kind
}

/// SwiftUI container that renders a SplitTree of terminal panes.
struct TerminalSplitContainer: View {
    let tree: TerminalSplitTree
    let terminalViews: [UUID: AgentStudioTerminalView]  // paneId → NSView
    let activePaneId: UUID?
    let action: (SplitOperation) -> Void

    var body: some View {
        if let node = tree.root {
            SplitSubtreeView(
                node: node,
                terminalViews: terminalViews,
                activePaneId: activePaneId,
                action: action
            )
        } else {
            // Empty tree - show placeholder
            ContentUnavailableView(
                "No Terminal",
                systemImage: "terminal",
                description: Text("Drag a tab here to create a split")
            )
        }
    }
}

/// Recursively renders a node in the split tree.
fileprivate struct SplitSubtreeView: View {
    let node: TerminalSplitTree.Node
    let terminalViews: [UUID: AgentStudioTerminalView]
    let activePaneId: UUID?
    let action: (SplitOperation) -> Void

    var body: some View {
        switch node {
        case .leaf(let pane):
            TerminalPaneLeaf(
                pane: pane,
                terminalView: terminalViews[pane.id],
                isActive: pane.id == activePaneId,
                action: action
            )

        case .split(let split):
            SplitView(
                splitViewDirection,
                ratioBinding(for: split),
                dividerColor: .gray.opacity(0.4),
                left: {
                    SplitSubtreeView(
                        node: split.left,
                        terminalViews: terminalViews,
                        activePaneId: activePaneId,
                        action: action
                    )
                },
                right: {
                    SplitSubtreeView(
                        node: split.right,
                        terminalViews: terminalViews,
                        activePaneId: activePaneId,
                        action: action
                    )
                },
                onEqualize: {
                    action(.equalize)
                }
            )
        }
    }

    private var splitViewDirection: SplitViewDirection {
        guard case .split(let split) = node else { return .horizontal }
        return split.direction
    }

    private func ratioBinding(for split: TerminalSplitTree.Node.Split) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(split.ratio) },
            set: { newRatio in
                // Find a pane in this split to identify it
                if let paneId = split.left.firstPaneId {
                    action(.resize(paneId: paneId, ratio: newRatio))
                }
            }
        )
    }
}

// MARK: - Helper Extensions

extension TerminalSplitTree.Node {
    /// Get the ID of the first pane in this node (for identifying the split).
    var firstPaneId: UUID? {
        switch self {
        case .leaf(let pane):
            return pane.id
        case .split(let split):
            return split.left.firstPaneId
        }
    }
}
