import SwiftUI
import AppKit

/// Payload for drag-and-drop split operations.
struct SplitDropPayload: Equatable, Codable {
    enum Kind: Equatable, Codable {
        case existingTab(tabId: UUID, worktreeId: UUID, repoId: UUID, title: String)
        case existingPane(paneId: UUID, sourceTabId: UUID)
        case newTerminal
    }

    let kind: Kind
}

/// SwiftUI container that renders a SplitTree of pane views.
struct TerminalSplitContainer: View {
    let tree: PaneSplitTree
    let tabId: UUID
    let activePaneId: UUID?
    let zoomedPaneId: UUID?
    let action: (PaneAction) -> Void
    /// Called when a resize drag ends to persist the current split tree state.
    let onPersist: (() -> Void)?
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    var body: some View {
        if let node = tree.root {
            if let zoomedPaneId,
               let zoomedView = tree.allViews.first(where: { $0.id == zoomedPaneId }) {
                // Zoomed: render single pane at full size
                ZStack(alignment: .topTrailing) {
                    TerminalPaneLeaf(
                        paneView: zoomedView,
                        tabId: tabId,
                        isActive: true,
                        isSplit: false,
                        action: action,
                        shouldAcceptDrop: shouldAcceptDrop,
                        onDrop: onDrop
                    )
                    // Zoom indicator badge
                    Text("ZOOM")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.15)))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            } else {
                // Normal split rendering
                SplitSubtreeView(
                    node: node,
                    tabId: tabId,
                    isSplit: tree.isSplit,
                    activePaneId: activePaneId,
                    action: action,
                    onPersist: onPersist,
                    shouldAcceptDrop: shouldAcceptDrop,
                    onDrop: onDrop
                )
                .id(node.structuralIdentity)  // Prevents view recreation on ratio changes
            }
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
    let node: PaneSplitTree.Node
    let tabId: UUID
    let isSplit: Bool
    let activePaneId: UUID?
    let action: (PaneAction) -> Void
    let onPersist: (() -> Void)?
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    var body: some View {
        switch node {
        case .leaf(let paneView):
            TerminalPaneLeaf(
                paneView: paneView,
                tabId: tabId,
                isActive: paneView.id == activePaneId,
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
                        onPersist: onPersist,
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
                        onPersist: onPersist,
                        shouldAcceptDrop: shouldAcceptDrop,
                        onDrop: onDrop
                    )
                },
                onEqualize: {
                    action(.equalizePanes(tabId: tabId))
                },
                onResizeEnd: {
                    // Persist only when drag ends — avoids I/O on every pixel of movement
                    onPersist?()
                }
            )
        }
    }

    private var splitViewDirection: SplitViewDirection {
        guard case .split(let split) = node else { return .horizontal }
        return split.direction
    }

    private func ratioBinding(for split: TerminalSplitTree.Node.Split) -> Binding<CGFloat> {
        let splitId = split.id
        return Binding(
            get: { CGFloat(split.ratio) },
            set: { newRatio in
                action(.resizePane(tabId: tabId, splitId: splitId, ratio: Double(newRatio)))
            }
        )
    }
}

