import SwiftUI
import os.log

private let flatPaneStripLogger = Logger(subsystem: "com.agentstudio", category: "FlatPaneStripContent")

enum PaneSegmentMissingHostDisposition: Equatable {
    case deferredInitialRestore
    case deferredInactiveTabRestore
    case retiredTransition
    case unexpectedMissingHost

    static func resolve(isRetired: Bool, isInitialRestorePending: Bool, isInactivePersistentTab: Bool) -> Self {
        if isRetired {
            return .retiredTransition
        }
        if isInitialRestorePending {
            return .deferredInitialRestore
        }
        if isInactivePersistentTab {
            return .deferredInactiveTabRestore
        }
        return .unexpectedMissingHost
    }
}

struct FlatPaneStripContent: View {
    let layout: Layout
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let ordinalMap: PaneOrdinalMap
    let collapsedPaneWidth: CGFloat
    let onSaveArrangement: (() -> Void)?
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let coordinateSpaceName: String?
    let useDrawerFramePreference: Bool
    let isInactivePersistentTab: Bool
    let paneInboxPresentation: PaneInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void
    let workspaceWindowId: UUID?
    @State private var isSplitResizing = false

    var body: some View {
        GeometryReader { geometry in
            let metrics = FlatTabStripMetrics.compute(
                layout: layout,
                in: CGRect(origin: .zero, size: geometry.size),
                dividerThickness: AppStyles.General.Layout.paneGap,
                minimizedPaneIds: minimizedPaneIds,
                collapsedPaneWidth: collapsedPaneWidth
            )
            // swiftlint:disable:next redundant_discardable_let
            let _ = RestoreTrace.log(
                "FlatPaneStripContent.body paneCount=\(layout.panes.count) segmentCount=\(metrics.paneSegments.count) geoSize=\(NSStringFromSize(geometry.size))"
            )

            if metrics.allMinimized {
                if collapsedPaneWidth > 0 {
                    HStack(spacing: 0) {
                        ForEach(layout.paneIds, id: \.self) { paneId in
                            CollapsedPaneBar(
                                paneId: paneId,
                                tabId: tabId,
                                closeTransitionCoordinator: closeTransitionCoordinator,
                                actionDispatcher: actionDispatcher,
                                onSaveArrangement: onSaveArrangement,
                                dropTargetCoordinateSpace: coordinateSpaceName,
                                useDrawerFramePreference: useDrawerFramePreference,
                                ordinal: ordinalMap.ordinal(forPaneId: paneId),
                                workspaceWindowId: workspaceWindowId
                            )
                            .frame(width: collapsedPaneWidth)
                        }
                        Spacer()
                    }
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
                            collapsedPaneWidth: collapsedPaneWidth,
                            onSaveArrangement: onSaveArrangement,
                            closeTransitionCoordinator: closeTransitionCoordinator,
                            actionDispatcher: actionDispatcher,
                            onPaneFocusTrigger: onPaneFocusTrigger,
                            store: store,
                            repoCache: repoCache,
                            isSplitResizing: isSplitResizing,
                            coordinateSpaceName: coordinateSpaceName,
                            useDrawerFramePreference: useDrawerFramePreference,
                            isInactivePersistentTab: isInactivePersistentTab,
                            paneInboxPresentation: paneInboxPresentation,
                            onOpenPaneGitHub: onOpenPaneGitHub,
                            viewRegistry: viewRegistry,
                            paneSlot: paneSlot,
                            ordinal: ordinalMap.ordinal(forPaneId: segment.paneId),
                            workspaceWindowId: workspaceWindowId
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
                            isSplitResizing: $isSplitResizing,
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
    let collapsedPaneWidth: CGFloat
    let onSaveArrangement: (() -> Void)?
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let isSplitResizing: Bool
    let coordinateSpaceName: String?
    let useDrawerFramePreference: Bool
    let isInactivePersistentTab: Bool
    let paneInboxPresentation: PaneInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void
    let viewRegistry: ViewRegistry
    @Bindable var paneSlot: ViewRegistry.PaneViewSlot
    let ordinal: Int?
    let workspaceWindowId: UUID?

    var body: some View {
        ZStack {
            if segment.isMinimized {
                if collapsedPaneWidth > 0 {
                    CollapsedPaneBar(
                        paneId: segment.paneId,
                        tabId: tabId,
                        closeTransitionCoordinator: closeTransitionCoordinator,
                        actionDispatcher: actionDispatcher,
                        onSaveArrangement: onSaveArrangement,
                        dropTargetCoordinateSpace: coordinateSpaceName,
                        useDrawerFramePreference: useDrawerFramePreference,
                        ordinal: ordinal,
                        workspaceWindowId: workspaceWindowId
                    )
                }
            } else if let paneHost = paneSlot.host {
                PaneLeafContainer(
                    paneHost: paneHost,
                    tabId: tabId,
                    isActive: segment.paneId == activePaneId,
                    isSplit: layout.isSplit,
                    isSplitResizing: isSplitResizing,
                    store: store,
                    repoCache: repoCache,
                    closeTransitionCoordinator: closeTransitionCoordinator,
                    actionDispatcher: actionDispatcher,
                    onPaneFocusTrigger: onPaneFocusTrigger,
                    onOpenPaneGitHub: onOpenPaneGitHub,
                    dropTargetCoordinateSpace: coordinateSpaceName,
                    useDrawerFramePreference: useDrawerFramePreference,
                    paneInboxPresentation: paneInboxPresentation,
                    ordinal: ordinal,
                    workspaceWindowId: workspaceWindowId
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
            } else {
                switch PaneSegmentMissingHostDisposition.resolve(
                    isRetired: viewRegistry.isRetired(for: segment.paneId),
                    isInitialRestorePending: viewRegistry.isInitialRestorePending,
                    isInactivePersistentTab: isInactivePersistentTab
                ) {
                case .deferredInitialRestore:
                    Color.clear

                case .deferredInactiveTabRestore:
                    Color.clear

                case .retiredTransition:
                    Color.clear

                case .unexpectedMissingHost:
                    UnexpectedMissingPaneHostPlaceholder(paneId: segment.paneId)
                }
            }
        }
    }
}

private struct UnexpectedMissingPaneHostPlaceholder: View {
    let paneId: UUID

    var body: some View {
        Color.clear
            .onAppear {
                Self.reportUnexpectedMissingHost(paneId: paneId)
            }
    }

    private static func reportUnexpectedMissingHost(paneId: UUID) {
        let message = "FlatPaneStripContent: missing host for non-retired pane \(paneId)"
        #if DEBUG
            assertionFailure(message)
        #endif
        flatPaneStripLogger.error(
            "FlatPaneStripContent: missing host for non-retired pane \(paneId.uuidString, privacy: .public)"
        )
        RestoreTrace.log(message)
    }
}

struct FlatPaneDivider: View {
    let dividerId: UUID
    let frame: CGRect
    let leftPaneWidth: CGFloat
    let rightPaneWidth: CGFloat
    let layout: Layout
    @Binding var isSplitResizing: Bool
    let tabId: UUID
    let actionDispatcher: PaneActionDispatching

    private let splitterHitSize: CGFloat = 6
    private let minSize: CGFloat = AppPolicies.DragAndDrop.splitMinimumPaneSize

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
                            isSplitResizing = true
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
                        isSplitResizing = false
                    }
            )
    }
}
