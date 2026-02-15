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
    let minimizedPaneIds: Set<UUID>
    let action: (PaneAction) -> Void
    /// Called when a resize drag ends to persist the current split tree state.
    let onPersist: (() -> Void)?
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void
    var drawerProvider: ((UUID) -> Drawer?)? = nil
    var drawerPaneViewProvider: ((UUID) -> PaneView?)? = nil
    var paneTitleProvider: ((UUID) -> String)? = nil

    var body: some View {
        GeometryReader { tabGeometry in
            let measuredTabWidth = tabGeometry.size.width
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
                            drawer: drawerProvider?(zoomedPaneId),
                            action: action,
                            shouldAcceptDrop: shouldAcceptDrop,
                            onDrop: onDrop,
                            drawerPaneViewProvider: drawerPaneViewProvider,
                            tabWidth: nil  // zoomed = single pane, no tab width needed
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
                        minimizedPaneIds: minimizedPaneIds,
                        action: action,
                        onPersist: onPersist,
                        shouldAcceptDrop: shouldAcceptDrop,
                        onDrop: onDrop,
                        drawerProvider: drawerProvider,
                        drawerPaneViewProvider: drawerPaneViewProvider,
                        paneTitleProvider: paneTitleProvider,
                        tabWidth: measuredTabWidth
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
}

/// Recursively renders a node in the split tree.
fileprivate struct SplitSubtreeView: View {
    let node: PaneSplitTree.Node
    let tabId: UUID
    let isSplit: Bool
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let action: (PaneAction) -> Void
    let onPersist: (() -> Void)?
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void
    var drawerProvider: ((UUID) -> Drawer?)? = nil
    var drawerPaneViewProvider: ((UUID) -> PaneView?)? = nil
    var paneTitleProvider: ((UUID) -> String)? = nil
    var tabWidth: CGFloat? = nil

    var body: some View {
        switch node {
        case .leaf(let paneView):
            if minimizedPaneIds.contains(paneView.id) {
                CollapsedPaneBar(
                    paneId: paneView.id,
                    tabId: tabId,
                    title: paneTitleProvider?(paneView.id) ?? "Terminal",
                    action: action
                )
            } else {
                TerminalPaneLeaf(
                    paneView: paneView,
                    tabId: tabId,
                    isActive: paneView.id == activePaneId,
                    isSplit: isSplit,
                    drawer: drawerProvider?(paneView.id),
                    action: action,
                    shouldAcceptDrop: shouldAcceptDrop,
                    onDrop: onDrop,
                    drawerPaneViewProvider: drawerPaneViewProvider,
                    tabWidth: isSplit ? tabWidth : nil
                )
            }

        case .split(let split):
            let leftMinimized = isMinimizedLeaf(split.left)
            let rightMinimized = isMinimizedLeaf(split.right)

            if leftMinimized || rightMinimized {
                // At least one side is minimized — render with collapsed bar(s)
                minimizedSplitContent(
                    split: split,
                    leftMinimized: leftMinimized,
                    rightMinimized: rightMinimized
                )
            } else {
                // Normal split rendering
                SplitView(
                    splitViewDirection,
                    ratioBinding(for: split),
                    left: {
                        subtreeView(node: split.left)
                    },
                    right: {
                        subtreeView(node: split.right)
                    },
                    onEqualize: {
                        action(.equalizePanes(tabId: tabId))
                    },
                    onResizeEnd: {
                        onPersist?()
                    }
                )
            }
        }
    }

    // MARK: - Minimized Split Rendering

    /// Check if a node is a single minimized leaf.
    private func isMinimizedLeaf(_ node: PaneSplitTree.Node) -> Bool {
        guard case .leaf(let paneView) = node else { return false }
        return minimizedPaneIds.contains(paneView.id)
    }

    /// Render a split where at least one side is minimized.
    @ViewBuilder
    private func minimizedSplitContent(
        split: TerminalSplitTree.Node.Split,
        leftMinimized: Bool,
        rightMinimized: Bool
    ) -> some View {
        let isHorizontal = split.direction == .horizontal
        if isHorizontal {
            HStack(spacing: 0) {
                if leftMinimized {
                    collapsedBarForNode(split.left)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    subtreeView(node: split.left)
                }
                if rightMinimized {
                    collapsedBarForNode(split.right)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    subtreeView(node: split.right)
                }
            }
        } else {
            VStack(spacing: 0) {
                if leftMinimized {
                    collapsedBarForNode(split.left)
                        .frame(height: CollapsedPaneBar.barHeight)
                } else {
                    subtreeView(node: split.left)
                }
                if rightMinimized {
                    collapsedBarForNode(split.right)
                        .frame(height: CollapsedPaneBar.barHeight)
                } else {
                    subtreeView(node: split.right)
                }
            }
        }
    }

    /// Create a CollapsedPaneBar for a leaf node.
    @ViewBuilder
    private func collapsedBarForNode(_ node: PaneSplitTree.Node) -> some View {
        if case .leaf(let paneView) = node {
            CollapsedPaneBar(
                paneId: paneView.id,
                tabId: tabId,
                title: paneTitleProvider?(paneView.id) ?? "Terminal",
                action: action
            )
        }
    }

    /// Create a child SplitSubtreeView with all params forwarded.
    @ViewBuilder
    private func subtreeView(node: PaneSplitTree.Node) -> some View {
        SplitSubtreeView(
            node: node,
            tabId: tabId,
            isSplit: true,
            activePaneId: activePaneId,
            minimizedPaneIds: minimizedPaneIds,
            action: action,
            onPersist: onPersist,
            shouldAcceptDrop: shouldAcceptDrop,
            onDrop: onDrop,
            drawerProvider: drawerProvider,
            drawerPaneViewProvider: drawerPaneViewProvider,
            paneTitleProvider: paneTitleProvider,
            tabWidth: tabWidth
        )
    }

    // MARK: - Helpers

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

