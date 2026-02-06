import SwiftUI
import AppKit

/// Operations that can be performed on the split tree.
enum SplitOperation {
    case resize(paneId: UUID, ratio: CGFloat)
    case equalize
    case drop(payload: SplitDropPayload, destination: AgentStudioTerminalView, zone: DropZone)
    case focus(paneId: UUID)
    case closePane(paneId: UUID)
}

extension SplitOperation: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.resize(let p1, let r1), .resize(let p2, let r2)):
            return p1 == p2 && r1 == r2
        case (.equalize, .equalize):
            return true
        case (.drop(let pl1, let d1, let z1), .drop(let pl2, let d2, let z2)):
            return pl1 == pl2 && d1 === d2 && z1 == z2
        case (.focus(let p1), .focus(let p2)):
            return p1 == p2
        case (.closePane(let p1), .closePane(let p2)):
            return p1 == p2
        default:
            return false
        }
    }
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
    let activePaneId: UUID?
    let action: (SplitOperation) -> Void

    var body: some View {
        if let node = tree.root {
            SplitSubtreeView(
                node: node,
                isSplit: tree.isSplit,
                activePaneId: activePaneId,
                action: action
            )
            .id(node.structuralIdentity)  // Prevents view recreation on ratio changes
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
    let isSplit: Bool
    let activePaneId: UUID?
    let action: (SplitOperation) -> Void

    var body: some View {
        switch node {
        case .leaf(let terminalView):
            TerminalPaneLeaf(
                terminalView: terminalView,
                isActive: terminalView.id == activePaneId,
                isSplit: isSplit,
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
                        isSplit: true,
                        activePaneId: activePaneId,
                        action: action
                    )
                },
                right: {
                    SplitSubtreeView(
                        node: split.right,
                        isSplit: true,
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
        case .leaf(let terminalView):
            return terminalView.id
        case .split(let split):
            return split.left.firstPaneId
        }
    }
}
