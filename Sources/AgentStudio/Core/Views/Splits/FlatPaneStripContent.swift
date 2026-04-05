import SwiftUI

struct FlatPaneStripContent: View {
    let layout: Layout
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let coordinateSpaceName: String?
    let useDrawerFramePreference: Bool
    let onOpenPaneGitHub: (UUID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = FlatTabStripMetrics.compute(
                layout: layout,
                in: CGRect(origin: .zero, size: geometry.size),
                dividerThickness: AppStyle.paneGap,
                minimizedPaneIds: minimizedPaneIds,
                collapsedPaneWidth: CollapsedPaneBar.barWidth
            )
            // swiftlint:disable:next redundant_discardable_let
            let _ = RestoreTrace.log(
                "FlatPaneStripContent.body paneCount=\(layout.panes.count) segmentCount=\(metrics.paneSegments.count) geoSize=\(NSStringFromSize(geometry.size))"
            )

            if metrics.allMinimized {
                HStack(spacing: 0) {
                    ForEach(layout.paneIds, id: \.self) { paneId in
                        CollapsedPaneBar(
                            paneId: paneId,
                            tabId: tabId,
                            title: atom(\.paneDisplay).displayLabel(for: paneId),
                            closeTransitionCoordinator: closeTransitionCoordinator,
                            actionDispatcher: actionDispatcher,
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
                        let paneSlot = viewRegistry.slot(for: segment.paneId)
                        PaneSegmentSlotView(
                            segment: segment,
                            tabId: tabId,
                            activePaneId: activePaneId,
                            layout: layout,
                            closeTransitionCoordinator: closeTransitionCoordinator,
                            actionDispatcher: actionDispatcher,
                            store: store,
                            repoCache: repoCache,
                            coordinateSpaceName: coordinateSpaceName,
                            useDrawerFramePreference: useDrawerFramePreference,
                            onOpenPaneGitHub: onOpenPaneGitHub,
                            paneSlot: paneSlot
                        )
                        .id("\(segment.paneId.uuidString)-registered=\(paneSlot.host != nil)")
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
                            actionDispatcher: actionDispatcher
                        )
                    }
                }
            }
        }
    }
}

private struct PaneSegmentSlotView: View {
    let segment: FlatTabStripMetrics.PaneSegment
    let tabId: UUID
    let activePaneId: UUID?
    let layout: Layout
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let coordinateSpaceName: String?
    let useDrawerFramePreference: Bool
    let onOpenPaneGitHub: (UUID) -> Void
    @Bindable var paneSlot: ViewRegistry.PaneViewSlot

    var body: some View {
        if segment.isMinimized {
            CollapsedPaneBar(
                paneId: segment.paneId,
                tabId: tabId,
                title: atom(\.paneDisplay).displayLabel(for: segment.paneId),
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                dropTargetCoordinateSpace: coordinateSpaceName,
                useDrawerFramePreference: useDrawerFramePreference
            )
        } else if let paneHost = paneSlot.host {
            PaneLeafContainer(
                paneHost: paneHost,
                tabId: tabId,
                isActive: segment.paneId == activePaneId,
                isSplit: layout.isSplit,
                store: store,
                repoCache: repoCache,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                onOpenPaneGitHub: onOpenPaneGitHub,
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
    let actionDispatcher: PaneActionDispatching

    private let splitterHitSize: CGFloat = 6
    private let minSize: CGFloat = AppStyle.splitMinimumPaneSize

    @State private var hasStartedResize = false
    @State private var initialLeftWidth: CGFloat = 0
    @State private var initialRightWidth: CGFloat = 0

    /// Pure computation for drag-resize ratio. Extracted for testability.
    nonisolated static func computeResizeRatio(
        initialLeftWidth: CGFloat,
        initialRightWidth: CGFloat,
        translationWidth: CGFloat,
        minSize: CGFloat
    ) -> Double {
        let totalWidth = initialLeftWidth + initialRightWidth
        guard totalWidth > 0 else { return 0.5 }
        let clampedLeftWidth = min(
            max(initialLeftWidth + translationWidth, minSize),
            totalWidth - minSize
        )
        return clampedLeftWidth / totalWidth
    }

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
                            initialLeftWidth = leftPaneWidth
                            initialRightWidth = rightPaneWidth
                            store.isSplitResizing = true
                        }

                        let localRatio = Self.computeResizeRatio(
                            initialLeftWidth: initialLeftWidth,
                            initialRightWidth: initialRightWidth,
                            translationWidth: gesture.translation.width,
                            minSize: minSize
                        )
                        actionDispatcher.dispatch(.resizePane(tabId: tabId, splitId: dividerId, ratio: localRatio))
                    }
                    .onEnded { _ in
                        hasStartedResize = false
                        store.isSplitResizing = false
                    }
            )
    }
}
