import SwiftUI
import AppKit

/// Payload for drag-and-drop split operations.
struct SplitDropPayload: Equatable, Codable {
    enum Kind: Equatable, Codable {
        case existingTab(tabId: UUID, worktreeId: UUID, repoId: UUID, title: String)
        case newTerminal
    }

    let kind: Kind
}

/// SwiftUI container that renders a SplitTree of terminal panes.
struct TerminalSplitContainer: View {
    let tree: TerminalSplitTree
    let tabId: UUID
    let activePaneId: UUID?
    let action: (PaneAction) -> Void
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    var body: some View {
        if let node = tree.root {
            SplitSubtreeView(
                node: node,
                tabId: tabId,
                isSplit: tree.isSplit,
                activePaneId: activePaneId,
                action: action,
                shouldAcceptDrop: shouldAcceptDrop,
                onDrop: onDrop
            )
            .id(node.structuralIdentity)  // Prevents view recreation on ratio changes
            .padding(2)  // 2pt gap around all edges (background shows through)
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
    let tabId: UUID
    let isSplit: Bool
    let activePaneId: UUID?
    let action: (PaneAction) -> Void
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    var body: some View {
        switch node {
        case .leaf(let terminalView):
            TerminalPaneLeaf(
                terminalView: terminalView,
                tabId: tabId,
                isActive: terminalView.id == activePaneId,
                isSplit: isSplit,
                action: action,
                shouldAcceptDrop: shouldAcceptDrop,
                onDrop: onDrop
            )

        case .split(let split):
            SplitView(
                splitViewDirection,
                ratioBinding(for: split),
                left: {
                    SplitSubtreeView(
                        node: split.left,
                        tabId: tabId,
                        isSplit: true,
                        activePaneId: activePaneId,
                        action: action,
                        shouldAcceptDrop: shouldAcceptDrop,
                        onDrop: onDrop
                    )
                },
                right: {
                    SplitSubtreeView(
                        node: split.right,
                        tabId: tabId,
                        isSplit: true,
                        activePaneId: activePaneId,
                        action: action,
                        shouldAcceptDrop: shouldAcceptDrop,
                        onDrop: onDrop
                    )
                },
                onEqualize: {
                    action(.equalizePanes(tabId: tabId))
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
                    action(.resizePane(tabId: tabId, paneId: paneId, ratio: newRatio))
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
