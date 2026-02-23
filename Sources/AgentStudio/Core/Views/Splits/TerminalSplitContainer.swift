import AppKit
import SwiftUI

/// Payload for drag-and-drop split operations.
struct SplitDropPayload: Equatable, Codable {
    enum Kind: Equatable, Codable {
        case existingTab(tabId: UUID)
        case existingPane(paneId: UUID, sourceTabId: UUID)
        case newTerminal
    }

    let kind: Kind
}

/// SwiftUI container that renders a SplitTree of pane views.
///
/// Reads drawer and title data directly from WorkspaceStore via @Observable
/// property tracking — no closure-based providers needed.
struct TerminalSplitContainer: View {
    let tree: PaneSplitTree
    let tabId: UUID
    let activePaneId: UUID?
    let zoomedPaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let splitRenderInfo: SplitRenderInfo
    let action: (PaneAction) -> Void
    /// Called when a resize drag ends to persist the current split tree state.
    let onPersist: (() -> Void)?
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void
    let store: WorkspaceStore
    let viewRegistry: ViewRegistry

    @State private var paneFrames: [UUID: CGRect] = [:]
    @State private var iconBarFrame: CGRect = .zero

    /// Content shown when all panes in the tab are minimized.
    /// Collapsed bars aligned left, remaining space empty.
    @ViewBuilder
    private var allMinimizedContent: some View {
        HStack(spacing: 0) {
            ForEach(splitRenderInfo.allMinimizedPaneIds, id: \.self) { paneId in
                CollapsedPaneBar(
                    paneId: paneId,
                    tabId: tabId,
                    title: store.pane(paneId)?.title ?? "Terminal",
                    action: action
                )
                .frame(width: CollapsedPaneBar.barWidth)
            }
            Spacer()
        }
    }

    var body: some View {
        GeometryReader { tabGeometry in
            ZStack {
                if let node = tree.root {
                    if let zoomedPaneId,
                        let zoomedView = tree.allViews.first(where: { $0.id == zoomedPaneId })
                    {
                        // Zoomed: render single pane at full size
                        ZStack(alignment: .topTrailing) {
                            TerminalPaneLeaf(
                                paneView: zoomedView,
                                tabId: tabId,
                                isActive: true,
                                isSplit: false,
                                store: store,
                                action: action,
                                shouldAcceptDrop: shouldAcceptDrop,
                                onDrop: onDrop
                            )
                            // Zoom indicator badge
                            Text("ZOOM")
                                .font(.system(size: AppStyle.textSm, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(AppStyle.foregroundSecondary))
                                .padding(.horizontal, AppStyle.spacingStandard)
                                .padding(.vertical, AppStyle.paneGap)
                                .background(Capsule().fill(.white.opacity(AppStyle.strokeMuted)))
                                .padding(AppStyle.spacingLoose)
                                .allowsHitTesting(false)
                        }
                    } else if splitRenderInfo.allMinimized {
                        // All panes minimized — show bars + empty content
                        allMinimizedContent
                    } else {
                        // Normal split rendering
                        SplitSubtreeView(
                            node: node,
                            tabId: tabId,
                            isSplit: tree.isSplit,
                            activePaneId: activePaneId,
                            minimizedPaneIds: minimizedPaneIds,
                            splitRenderInfo: splitRenderInfo,
                            action: action,
                            onPersist: onPersist,
                            shouldAcceptDrop: shouldAcceptDrop,
                            onDrop: onDrop,
                            store: store
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

                // Tab-level drawer panel overlay (renders on top of all panes)
                DrawerPanelOverlay(
                    store: store,
                    viewRegistry: viewRegistry,
                    tabId: tabId,
                    paneFrames: paneFrames,
                    tabSize: tabGeometry.size,
                    iconBarFrame: iconBarFrame,
                    action: action
                )
            }
            .onPreferenceChange(PaneFramePreferenceKey.self) { paneFrames = $0 }
            .onPreferenceChange(DrawerIconBarFrameKey.self) { iconBarFrame = $0 }
        }
        .coordinateSpace(name: "tabContainer")
    }
}

/// Recursively renders a node in the split tree.
/// Used by both TerminalSplitContainer (tab context) and DrawerPanel (drawer context).
struct SplitSubtreeView: View {
    let node: PaneSplitTree.Node
    let tabId: UUID
    let isSplit: Bool
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let splitRenderInfo: SplitRenderInfo
    let action: (PaneAction) -> Void
    let onPersist: (() -> Void)?
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void
    let store: WorkspaceStore

    var body: some View {
        switch node {
        case .leaf(let paneView):
            if minimizedPaneIds.contains(paneView.id) {
                CollapsedPaneBar(
                    paneId: paneView.id,
                    tabId: tabId,
                    title: store.pane(paneView.id)?.title ?? "Terminal",
                    action: action
                )
            } else {
                TerminalPaneLeaf(
                    paneView: paneView,
                    tabId: tabId,
                    isActive: paneView.id == activePaneId,
                    isSplit: isSplit,
                    store: store,
                    action: action,
                    shouldAcceptDrop: shouldAcceptDrop,
                    onDrop: onDrop
                )
            }

        case .split(let split):
            let info = splitRenderInfo.splitInfo[split.id]

            if let info, info.leftFullyMinimized && info.rightFullyMinimized {
                // Both sides fully minimized — render all bars
                allCollapsedBars(paneIds: info.leftMinimizedPaneIds + info.rightMinimizedPaneIds)
            } else if let info, info.leftFullyMinimized {
                // Left fully minimized — bars + right fills rest
                minimizedSideContent(
                    minimizedPaneIds: info.leftMinimizedPaneIds,
                    visibleSide: split.right,
                    direction: split.direction,
                    minimizedOnLeft: true
                )
            } else if let info, info.rightFullyMinimized {
                // Right fully minimized — left fills rest + bars
                minimizedSideContent(
                    minimizedPaneIds: info.rightMinimizedPaneIds,
                    visibleSide: split.left,
                    direction: split.direction,
                    minimizedOnLeft: false
                )
            } else {
                // Both sides have visible panes — use adjusted ratio
                let ratio = info?.adjustedRatio ?? split.ratio
                SplitView(
                    splitViewDirection,
                    adjustedRatioBinding(for: split, renderRatio: ratio, splitInfo: info),
                    left: {
                        subtreeView(node: split.left)
                    },
                    right: {
                        subtreeView(node: split.right)
                    },
                    onEqualize: {
                        action(.equalizePanes(tabId: tabId))
                    },
                    onResizeBegin: {
                        store.isSplitResizing = true
                    },
                    onResizeEnd: {
                        store.isSplitResizing = false
                        onPersist?()
                    }
                )
            }
        }
    }

    // MARK: - Minimized Split Rendering

    /// Render a split where one side is fully minimized (bars) and the other has visible content.
    @ViewBuilder
    private func minimizedSideContent(
        minimizedPaneIds: [UUID],
        visibleSide: PaneSplitTree.Node,
        direction: SplitViewDirection,
        minimizedOnLeft: Bool
    ) -> some View {
        let isHorizontal = direction == .horizontal

        if isHorizontal {
            HStack(spacing: 0) {
                if minimizedOnLeft {
                    collapsedBarsForDirection(paneIds: minimizedPaneIds, isHorizontal: true)
                    subtreeView(node: visibleSide)
                } else {
                    subtreeView(node: visibleSide)
                    collapsedBarsForDirection(paneIds: minimizedPaneIds, isHorizontal: true)
                }
            }
        } else {
            VStack(spacing: 0) {
                if minimizedOnLeft {
                    collapsedBarsForDirection(paneIds: minimizedPaneIds, isHorizontal: false)
                    subtreeView(node: visibleSide)
                } else {
                    subtreeView(node: visibleSide)
                    collapsedBarsForDirection(paneIds: minimizedPaneIds, isHorizontal: false)
                }
            }
        }
    }

    /// Render collapsed bars for a list of minimized pane IDs.
    @ViewBuilder
    private func collapsedBarsForDirection(paneIds: [UUID], isHorizontal: Bool) -> some View {
        ForEach(paneIds, id: \.self) { paneId in
            CollapsedPaneBar(
                paneId: paneId,
                tabId: tabId,
                title: store.pane(paneId)?.title ?? "Terminal",
                action: action
            )
            .frame(
                width: isHorizontal ? CollapsedPaneBar.barWidth : nil,
                height: isHorizontal ? nil : CollapsedPaneBar.barHeight
            )
        }
    }

    /// Render all collapsed bars horizontally (both sides fully minimized).
    @ViewBuilder
    private func allCollapsedBars(paneIds: [UUID]) -> some View {
        HStack(spacing: 0) {
            collapsedBarsForDirection(paneIds: paneIds, isHorizontal: true)
        }
    }

    /// Create a child SplitSubtreeView with all params forwarded.
    @ViewBuilder
    private func subtreeView(node: PaneSplitTree.Node) -> some View {
        Self(
            node: node,
            tabId: tabId,
            isSplit: true,
            activePaneId: activePaneId,
            minimizedPaneIds: minimizedPaneIds,
            splitRenderInfo: splitRenderInfo,
            action: action,
            onPersist: onPersist,
            shouldAcceptDrop: shouldAcceptDrop,
            onDrop: onDrop,
            store: store
        )
    }

    // MARK: - Helpers

    private var splitViewDirection: SplitViewDirection {
        guard case .split(let split) = node else { return .horizontal }
        return split.direction
    }

    private func adjustedRatioBinding(
        for split: PaneSplitTree.Node.Split,
        renderRatio: Double,
        splitInfo: SplitRenderInfo.SplitInfo?
    ) -> Binding<CGFloat> {
        let splitId = split.id
        return Binding(
            get: { CGFloat(renderRatio) },
            set: { newRenderRatio in
                let modelRatio =
                    splitInfo?.modelRatio(fromRenderRatio: Double(newRenderRatio))
                    ?? Double(newRenderRatio)
                action(.resizePane(tabId: tabId, splitId: splitId, ratio: modelRatio))
            }
        )
    }
}
