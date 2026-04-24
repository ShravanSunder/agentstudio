import AppKit
import SwiftUI

struct FlatTabStripContainer: View {
    let layout: Layout
    let tabId: UUID
    let activePaneId: UUID?
    let zoomedPaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleAtom
    let onOpenPaneGitHub: (UUID) -> Void

    @State private var paneFrames: [UUID: CGRect] = [:]
    @State private var iconBarFrame: CGRect = .zero
    @State private var dropTarget: PaneDropTarget?
    @State private var dropTargetWatchdogTask: Task<Void, Never>?
    @State private var drawerPaneFramesInDrawer: [UUID: CGRect] = [:]
    @State private var drawerPanelFrameInTab: CGRect = .zero
    @State private var drawerDropTarget: DrawerRearrangeTarget?
    @State private var drawerDropTargetWatchdogTask: Task<Void, Never>?
    private var managementLayer: ManagementLayerAtom {
        atom(\.managementLayer)
    }

    private var onSaveArrangement: (() -> Void)? {
        guard store.tabLayoutAtom.tab(tabId) != nil else { return nil }

        return {
            guard let tab = store.tabLayoutAtom.tab(tabId) else { return }
            let arrangementName = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
            actionDispatcher.dispatch(
                .createArrangement(
                    tabId: tabId,
                    name: arrangementName,
                    paneIds: Set(tab.activePaneIds)
                )
            )
        }
    }

    var body: some View {
        GeometryReader { tabGeometry in
            let containerBounds = CGRect(origin: .zero, size: tabGeometry.size)
            let showMinimizedBars = managementLayer.isActive || atom(\.uiState).showMinimizedBars
            let effectiveCollapsedWidth: CGFloat = showMinimizedBars ? CollapsedPaneBar.barWidth : 0
            let expandedDrawerParentPaneId = DrawerDragOwnershipPolicy.expandedDrawerParentPaneId(
                tabId: tabId,
                tabLayoutAtom: store.tabLayoutAtom,
                paneAtom: store.paneAtom
            )
            let mainSplitDragCaptureEnabled = DrawerDragOwnershipPolicy.mainSplitDragEnabled(
                managementLayerActive: managementLayer.isActive,
                expandedDrawerParentPaneId: expandedDrawerParentPaneId
            )
            let metrics = FlatTabStripMetrics.compute(
                layout: layout,
                in: containerBounds,
                dividerThickness: AppStyles.General.Layout.paneGap,
                minimizedPaneIds: minimizedPaneIds,
                collapsedPaneWidth: effectiveCollapsedWidth
            )
            let closingPaneIds = closeTransitionCoordinator.closingPaneIds

            ZStack(alignment: .topLeading) {
                if let zoomedPane = zoomedPaneLeafContainer() {
                    ZStack(alignment: .topTrailing) {
                        zoomedPane
                            .id(zoomedPaneId)
                            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
                        Text("ZOOM")
                            .font(
                                .system(size: AppStyles.General.Typography.textSm, weight: .medium, design: .monospaced)
                            )
                            .foregroundStyle(.white.opacity(AppStyles.General.Foreground.secondary))
                            .padding(.horizontal, AppStyles.General.Spacing.standard)
                            .padding(.vertical, AppStyles.General.Layout.paneGap)
                            .background(Capsule().fill(.white.opacity(AppStyles.General.Stroke.muted)))
                            .padding(AppStyles.General.Spacing.loose)
                            .allowsHitTesting(false)
                    }
                } else if metrics.allMinimized {
                    if showMinimizedBars {
                        HStack(spacing: 0) {
                            ForEach(layout.paneIds, id: \.self) { paneId in
                                CollapsedPaneBar(
                                    paneId: paneId,
                                    tabId: tabId,
                                    closeTransitionCoordinator: closeTransitionCoordinator,
                                    actionDispatcher: actionDispatcher,
                                    onSaveArrangement: onSaveArrangement,
                                    dropTargetCoordinateSpace: "tabContainer"
                                )
                                .frame(width: CollapsedPaneBar.barWidth)
                            }
                            Spacer()
                        }
                    }
                } else {
                    FlatPaneStripContent(
                        layout: layout,
                        tabId: tabId,
                        activePaneId: activePaneId,
                        minimizedPaneIds: minimizedPaneIds,
                        collapsedPaneWidth: effectiveCollapsedWidth,
                        onSaveArrangement: onSaveArrangement,
                        closeTransitionCoordinator: closeTransitionCoordinator,
                        actionDispatcher: actionDispatcher,
                        onPaneFocusTrigger: onPaneFocusTrigger,
                        store: store,
                        repoCache: repoCache,
                        viewRegistry: viewRegistry,
                        coordinateSpaceName: "tabContainer",
                        useDrawerFramePreference: false,
                        onOpenPaneGitHub: onOpenPaneGitHub
                    )
                    .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: closingPaneIds)
                    .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: minimizedPaneIds)
                }

                DrawerPanelOverlay(
                    store: store,
                    repoCache: repoCache,
                    viewRegistry: viewRegistry,
                    appLifecycleStore: appLifecycleStore,
                    closeTransitionCoordinator: closeTransitionCoordinator,
                    tabId: tabId,
                    paneFrames: paneFrames,
                    tabSize: tabGeometry.size,
                    iconBarFrame: iconBarFrame,
                    actionDispatcher: actionDispatcher,
                    onPaneFocusTrigger: onPaneFocusTrigger,
                    onOpenPaneGitHub: onOpenPaneGitHub,
                    drawerDropTarget: drawerDropTarget
                )

                if managementLayer.isActive && mainSplitDragCaptureEnabled {
                    PaneDropTargetOverlay(
                        target: dropTarget,
                        targetRects: PaneDragCoordinator.targetRects(
                            paneFrames: paneFrames,
                            containerBounds: containerBounds,
                            minimizedPaneIds: minimizedPaneIds
                        )
                    )
                    .allowsHitTesting(false)
                }

                SplitContainerDropCaptureOverlay(
                    paneFrames: paneFrames,
                    containerBounds: containerBounds,
                    minimizedPaneIds: minimizedPaneIds,
                    target: $dropTarget,
                    isManagementLayerActive: managementLayer.isActive && mainSplitDragCaptureEnabled,
                    actionDispatcher: actionDispatcher
                )

                tabLevelDrawerCapture(expandedDrawerParentPaneId: expandedDrawerParentPaneId)
            }
            .onPreferenceChange(PaneFramePreferenceKey.self) { paneFrames = $0 }
            .onPreferenceChange(DrawerIconBarFrameKey.self) { iconBarFrame = $0 }
            .onPreferenceChange(DrawerPaneFramePreferenceKey.self) { drawerPaneFramesInDrawer = $0 }
            .onPreferenceChange(DrawerPanelFrameInTabKey.self) { drawerPanelFrameInTab = $0 }
            .onChange(of: managementLayer.isActive) { _, isActive in
                if !isActive {
                    dropTarget = nil
                    drawerDropTarget = nil
                }
            }
            .onChange(of: appLifecycleStore.isActive) { _, isActive in
                if !isActive {
                    dropTarget = nil
                    drawerDropTarget = nil
                }
            }
            .onChange(of: dropTarget) { _, target in
                if target == nil {
                    stopDropTargetWatchdog()
                } else {
                    startDropTargetWatchdog()
                }
            }
            .onChange(of: drawerDropTarget) { _, target in
                if target == nil {
                    stopDrawerDropTargetWatchdog()
                } else {
                    startDrawerDropTargetWatchdog()
                }
            }
            .onDisappear {
                stopDropTargetWatchdog()
                stopDrawerDropTargetWatchdog()
            }
        }
        .animation(.easeOut(duration: AppStyles.General.Animation.standard), value: atom(\.uiState).showMinimizedBars)
        .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: managementLayer.isActive)
        .coordinateSpace(name: "tabContainer")
    }

    @ViewBuilder
    private func tabLevelDrawerCapture(expandedDrawerParentPaneId: UUID?) -> some View {
        if DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: managementLayer.isActive,
            expandedDrawerParentPaneId: expandedDrawerParentPaneId,
            drawerPanelFrameInTab: drawerPanelFrameInTab
        ),
            let expandedDrawerPaneId = expandedDrawerParentPaneId,
            let expandedDrawer = store.paneAtom.pane(expandedDrawerPaneId)?.drawer
        {
            let drawerBounds = CGRect(origin: .zero, size: drawerPanelFrameInTab.size)
            DrawerSplitContainerDropCaptureOverlay(
                paneFrames: drawerPaneFramesInDrawer,
                layout: expandedDrawer.layout,
                minimizedPaneIds: expandedDrawer.minimizedPaneIds,
                containerBounds: drawerBounds,
                target: $drawerDropTarget,
                isManagementLayerActive: true,
                shouldAcceptDrop: { payload, target, sizingMode in
                    DrawerDropDispatch.shouldAcceptDrop(
                        payload: payload,
                        target: target,
                        sizingMode: sizingMode,
                        parentPaneId: expandedDrawerPaneId,
                        store: store
                    )
                },
                handleDrop: { payload, target, sizingMode in
                    DrawerDropDispatch.handleDrop(
                        payload: payload,
                        target: target,
                        sizingMode: sizingMode,
                        parentPaneId: expandedDrawerPaneId,
                        actionDispatcher: actionDispatcher,
                        store: store
                    )
                }
            )
            .frame(width: drawerPanelFrameInTab.width, height: drawerPanelFrameInTab.height)
            .position(x: drawerPanelFrameInTab.midX, y: drawerPanelFrameInTab.midY)
        }
    }

    func zoomedPaneLeafContainer() -> PaneLeafContainer? {
        guard let zoomedPaneId, let zoomedView = viewRegistry.view(for: zoomedPaneId) else {
            return nil
        }

        return PaneLeafContainer(
            paneHost: zoomedView,
            tabId: tabId,
            isActive: true,
            isSplit: false,
            isSplitResizing: false,
            store: store,
            repoCache: repoCache,
            closeTransitionCoordinator: closeTransitionCoordinator,
            actionDispatcher: actionDispatcher,
            onPaneFocusTrigger: onPaneFocusTrigger,
            onOpenPaneGitHub: onOpenPaneGitHub
        )
    }

    private func startDropTargetWatchdog() {
        stopDropTargetWatchdog()

        dropTargetWatchdogTask = Task { @MainActor in
            while !Task.isCancelled {
                if DropTargetLatchState.shouldClearTarget(
                    appIsActive: appLifecycleStore.isActive,
                    pressedMouseButtons: NSEvent.pressedMouseButtons
                ) {
                    dropTarget = nil
                    return
                }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopDropTargetWatchdog() {
        dropTargetWatchdogTask?.cancel()
        dropTargetWatchdogTask = nil
    }

    private func startDrawerDropTargetWatchdog() {
        stopDrawerDropTargetWatchdog()

        drawerDropTargetWatchdogTask = Task { @MainActor in
            while !Task.isCancelled {
                if DropTargetLatchState.shouldClearTarget(
                    appIsActive: appLifecycleStore.isActive,
                    pressedMouseButtons: NSEvent.pressedMouseButtons
                ) {
                    drawerDropTarget = nil
                    return
                }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopDrawerDropTargetWatchdog() {
        drawerDropTargetWatchdogTask?.cancel()
        drawerDropTargetWatchdogTask = nil
    }
}
