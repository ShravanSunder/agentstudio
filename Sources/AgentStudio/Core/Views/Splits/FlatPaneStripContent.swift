import SwiftUI

struct FlatPaneStripContent: View {
    let layout: Layout
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let action: (PaneActionCommand) -> Void
    let onPersist: (() -> Void)?
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let coordinateSpaceName: String?
    let useDrawerFramePreference: Bool

    var body: some View {
        GeometryReader { geometry in
            let metrics = FlatTabStripMetrics.compute(
                layout: layout,
                in: CGRect(origin: .zero, size: geometry.size),
                dividerThickness: AppStyle.paneGap,
                minimizedPaneIds: minimizedPaneIds,
                collapsedPaneWidth: CollapsedPaneBar.barWidth
            )

            if metrics.allMinimized {
                HStack(spacing: 0) {
                    ForEach(layout.paneIds, id: \.self) { paneId in
                        CollapsedPaneBar(
                            paneId: paneId,
                            tabId: tabId,
                            title: PaneDisplayProjector.displayLabel(for: paneId, store: store, repoCache: repoCache),
                            closeTransitionCoordinator: closeTransitionCoordinator,
                            action: action,
                            dropTargetCoordinateSpace: coordinateSpaceName,
                            useDrawerFramePreference: useDrawerFramePreference
                        )
                        .frame(width: CollapsedPaneBar.barWidth)
                    }
                    Spacer()
                }
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(metrics.paneSegments, id: \.paneId) { segment in
                        paneSegmentView(segment)
                            .frame(width: segment.frame.width, height: segment.frame.height)
                            .offset(x: segment.frame.minX, y: segment.frame.minY)
                    }

                    ForEach(metrics.dividerSegments, id: \.dividerId) { divider in
                        FlatPaneDivider(
                            dividerId: divider.dividerId,
                            frame: divider.frame,
                            leftPaneWidth: divider.leftPaneWidth,
                            rightPaneWidth: divider.rightPaneWidth,
                            layout: layout,
                            store: store,
                            tabId: tabId,
                            action: action,
                            onPersist: onPersist
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paneSegmentView(_ segment: FlatTabStripMetrics.PaneSegment) -> some View {
        if segment.isMinimized {
            CollapsedPaneBar(
                paneId: segment.paneId,
                tabId: tabId,
                title: PaneDisplayProjector.displayLabel(for: segment.paneId, store: store, repoCache: repoCache),
                closeTransitionCoordinator: closeTransitionCoordinator,
                action: action,
                dropTargetCoordinateSpace: coordinateSpaceName,
                useDrawerFramePreference: useDrawerFramePreference
            )
        } else if let paneHost = viewRegistry.view(for: segment.paneId) {
            PaneLeafContainer(
                paneHost: paneHost,
                tabId: tabId,
                isActive: segment.paneId == activePaneId,
                isSplit: layout.isSplit,
                store: store,
                repoCache: repoCache,
                closeTransitionCoordinator: closeTransitionCoordinator,
                action: action,
                dropTargetCoordinateSpace: coordinateSpaceName,
                useDrawerFramePreference: useDrawerFramePreference
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
        } else {
            Color.clear
        }
    }
}

struct FlatPaneDivider: View {
    let dividerId: UUID
    let frame: CGRect
    let leftPaneWidth: CGFloat
    let rightPaneWidth: CGFloat
    let layout: Layout
    let store: WorkspaceStore
    let tabId: UUID
    let action: (PaneActionCommand) -> Void
    let onPersist: (() -> Void)?

    private let splitterHitSize: CGFloat = 6
    private let minSize: CGFloat = AppStyle.splitMinimumPaneSize

    @State private var hasStartedResize = false

    var body: some View {
        Color.clear
            .frame(width: splitterHitSize, height: frame.height)
            .contentShape(Rectangle())
            .position(x: frame.midX, y: frame.midY)
            .backport.pointerStyle(.resizeLeftRight)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        guard layout.dividerIds.contains(dividerId) else { return }
                        if !hasStartedResize {
                            hasStartedResize = true
                            store.isSplitResizing = true
                        }

                        let clampedLeftWidth = min(
                            max(leftPaneWidth + gesture.translation.width, minSize),
                            leftPaneWidth + rightPaneWidth - minSize
                        )
                        let localRatio = clampedLeftWidth / (leftPaneWidth + rightPaneWidth)
                        action(.resizePane(tabId: tabId, splitId: dividerId, ratio: localRatio))
                    }
                    .onEnded { _ in
                        hasStartedResize = false
                        store.isSplitResizing = false
                        onPersist?()
                    }
            )
    }
}
