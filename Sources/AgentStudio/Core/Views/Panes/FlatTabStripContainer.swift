import AppKit
import SwiftUI

struct FlatTabStripContainer: View {
    let layout: Layout
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let visiblePaneIds: [UUID]?
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let onFocusPane: (UUID) -> Void
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleAtom
    let paneInboxPresentation: PaneInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void
    let onToggleZoom: (UUID?) -> Void
    let notificationCountForWorktree: (UUID) -> Int
    let workspaceWindowId: UUID?
    let paneSurfaceToolbarPresentation: (UUID) -> PaneSurfaceToolbarPresentation

    @State private var paneFrames: [UUID: CGRect] = [:]
    @State private var iconBarFrame: CGRect = .zero
    @State private var dropTarget: PaneDropTarget?
    @State private var dropTargetMouseUpMonitor: Any?
    @State private var drawerPaneFramesInDrawer: [UUID: CGRect] = [:]
    @State private var drawerPanelFrameInTab: CGRect = .zero
    @State private var drawerDismissCoordinateView: NSView?
    @State private var drawerDropTarget: DrawerRearrangeTarget?
    @State private var drawerDropTargetMouseUpMonitor: Any?
    /// Active drag's source pane id, published by either capture
    /// overlay so the visuals layer can apply the source-aware
    /// filter (R1-R18). Only one drag is active at a time across
    /// main + drawer.
    @State private var activeDragSourcePaneId: UUID?

    private struct PrimaryPaneLayerState {
        let metrics: FlatTabStripMetrics
        let effectiveVisiblePaneIds: [UUID]
        let rendersMinimizedBars: Bool
        let effectiveCollapsedWidth: CGFloat
        let mainOrdinalMap: PaneOrdinalMap
        let isInactivePersistentTab: Bool
        let closingPaneIds: Set<UUID>
    }

    private var managementLayer: ManagementLayerAtom {
        atom(\.managementLayer)
    }

    init(
        layout: Layout,
        tabId: UUID,
        activePaneId: UUID?,
        minimizedPaneIds: Set<UUID>,
        visiblePaneIds: [UUID]? = nil,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler,
        onFocusPane: @escaping (UUID) -> Void,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        viewRegistry: ViewRegistry,
        appLifecycleStore: AppLifecycleAtom,
        paneInboxPresentation: PaneInboxPresentation? = nil,
        onOpenPaneGitHub: @escaping (UUID) -> Void,
        onToggleZoom: @escaping (UUID?) -> Void = { _ in },
        notificationCountForWorktree: @escaping (UUID) -> Int = { _ in 0 },
        workspaceWindowId: UUID? = nil,
        paneSurfaceToolbarPresentation: @escaping (UUID) -> PaneSurfaceToolbarPresentation
    ) {
        self.layout = layout
        self.tabId = tabId
        self.activePaneId = activePaneId
        self.minimizedPaneIds = minimizedPaneIds
        self.visiblePaneIds = visiblePaneIds
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.onPaneFocusTrigger = onPaneFocusTrigger
        self.onFocusPane = onFocusPane
        self.store = store
        self.repoCache = repoCache
        self.viewRegistry = viewRegistry
        self.appLifecycleStore = appLifecycleStore
        self.paneInboxPresentation = paneInboxPresentation
        self.onOpenPaneGitHub = onOpenPaneGitHub
        self.onToggleZoom = onToggleZoom
        self.notificationCountForWorktree = notificationCountForWorktree
        self.workspaceWindowId = workspaceWindowId
        self.paneSurfaceToolbarPresentation = paneSurfaceToolbarPresentation
    }

    private var onSaveArrangement: (() -> Void)? {
        guard store.tabLayoutAtom.tab(tabId) != nil else { return nil }

        return {
            guard let tab = store.tabLayoutAtom.tab(tabId) else { return }
            let arrangementName = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
            actionDispatcher.dispatch(
                .createArrangement(
                    tabId: tabId,
                    name: arrangementName
                )
            )
        }
    }

    var body: some View {
        GeometryReader { tabGeometry in
            let containerBounds = CGRect(origin: .zero, size: tabGeometry.size)
            let isInactivePersistentTab = store.tabLayoutAtom.activeTabId != tabId
            let rendersMinimizedBars = managementLayer.isActive
            let effectiveCollapsedWidth: CGFloat = rendersMinimizedBars ? CollapsedPaneBar.barWidth : 0
            let effectiveVisiblePaneIds =
                visiblePaneIds
                ?? layout.paneIds.filter { paneId in
                    !minimizedPaneIds.contains(paneId) || rendersMinimizedBars
                }
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
            let mainOrdinalMap = PaneOrdinalMap(orderedPaneIds: layout.paneIds)
            let surfaceId = "tab:\(tabId)"
            let renderedPaneIds: Set<UUID> = {
                if effectiveVisiblePaneIds.isEmpty {
                    return []
                } else if metrics.allMinimized {
                    return rendersMinimizedBars ? Set(layout.paneIds) : []
                }
                return Set(effectiveVisiblePaneIds)
            }()
            let closingPaneIds = closeTransitionCoordinator.closingPaneIds
            let primaryPaneLayerState = PrimaryPaneLayerState(
                metrics: metrics,
                effectiveVisiblePaneIds: effectiveVisiblePaneIds,
                rendersMinimizedBars: rendersMinimizedBars,
                effectiveCollapsedWidth: effectiveCollapsedWidth,
                mainOrdinalMap: mainOrdinalMap,
                isInactivePersistentTab: isInactivePersistentTab,
                closingPaneIds: closingPaneIds
            )

            ZStack(alignment: .topLeading) {
                primaryPaneLayer(primaryPaneLayerState)

                drawerPanelOverlay(tabSize: tabGeometry.size)

                mainSplitManagementOverlay(
                    containerBounds: containerBounds,
                    mainSplitDragCaptureEnabled: mainSplitDragCaptureEnabled
                )

                tabLevelDrawerCapture(expandedDrawerParentPaneId: expandedDrawerParentPaneId)
            }
            .background(
                DrawerDismissCoordinateSpaceBridge { view in
                    if drawerDismissCoordinateView !== view {
                        drawerDismissCoordinateView = view
                    }
                }
                .allowsHitTesting(false)
            )
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
            .onChange(of: expandedDrawerParentPaneId) { _, parentPaneId in
                drawerDropTarget = DrawerDragOwnershipPolicy.retainedDrawerDropTarget(
                    drawerDropTarget,
                    expandedDrawerParentPaneId: parentPaneId
                )
            }
            .onChange(of: dropTarget) { _, target in
                if target == nil {
                    stopDropTargetMouseUpMonitor()
                } else {
                    startDropTargetMouseUpMonitor()
                }
            }
            .onChange(of: drawerDropTarget) { _, target in
                if target == nil {
                    stopDrawerDropTargetMouseUpMonitor()
                } else {
                    startDrawerDropTargetMouseUpMonitor()
                }
            }
            .onAppear {
                viewRegistry.surfaceRenderedIds(surfaceId, ids: renderedPaneIds)
            }
            .onChange(of: renderedPaneIds) { _, paneIds in
                viewRegistry.surfaceRenderedIds(surfaceId, ids: paneIds)
            }
            .onDisappear {
                viewRegistry.unregisterSurface(surfaceId)
                stopDropTargetMouseUpMonitor()
                stopDrawerDropTargetMouseUpMonitor()
            }
        }
        .animation(
            .easeOut(duration: AppStyles.General.Animation.standard),
            value: managementLayer.isActive
        )
        .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: managementLayer.isActive)
        .coordinateSpace(name: "tabContainer")
    }

    @ViewBuilder
    private func primaryPaneLayer(_ state: PrimaryPaneLayerState) -> some View {
        if state.effectiveVisiblePaneIds.isEmpty {
            EmptyArrangementPlaceholderView()
        } else if state.metrics.allMinimized {
            if state.rendersMinimizedBars {
                HStack(spacing: 0) {
                    ForEach(layout.paneIds, id: \.self) { paneId in
                        CollapsedPaneBar(
                            paneId: paneId,
                            tabId: tabId,
                            closeTransitionCoordinator: closeTransitionCoordinator,
                            actionDispatcher: actionDispatcher,
                            onFocus: { onFocusPane(paneId) },
                            onSaveArrangement: onSaveArrangement,
                            onToggleZoom: onToggleZoom,
                            dropTargetCoordinateSpace: "tabContainer",
                            ordinal: state.mainOrdinalMap.ordinal(forPaneId: paneId),
                            workspaceWindowId: workspaceWindowId
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
                ordinalMap: state.mainOrdinalMap,
                collapsedPaneWidth: state.effectiveCollapsedWidth,
                onSaveArrangement: onSaveArrangement,
                onToggleZoom: onToggleZoom,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger,
                onFocusPane: onFocusPane,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                coordinateSpaceName: "tabContainer",
                useDrawerFramePreference: false,
                isInactivePersistentTab: state.isInactivePersistentTab,
                paneInboxPresentation: paneInboxPresentation,
                onOpenPaneGitHub: onOpenPaneGitHub,
                notificationCountForWorktree: notificationCountForWorktree,
                workspaceWindowId: workspaceWindowId,
                paneSurfaceToolbarPresentation: paneSurfaceToolbarPresentation
            )
            .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: state.closingPaneIds)
            .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: minimizedPaneIds)
        }
    }

    private func drawerPanelOverlay(tabSize: CGSize) -> DrawerPanelOverlay {
        DrawerPanelOverlay(
            store: store,
            repoCache: repoCache,
            viewRegistry: viewRegistry,
            appLifecycleStore: appLifecycleStore,
            closeTransitionCoordinator: closeTransitionCoordinator,
            tabId: tabId,
            paneFrames: paneFrames,
            tabSize: tabSize,
            iconBarFrame: iconBarFrame,
            actionDispatcher: actionDispatcher,
            onPaneFocusTrigger: onPaneFocusTrigger,
            onFocusPane: onFocusPane,
            paneInboxPresentation: paneInboxPresentation,
            onOpenPaneGitHub: onOpenPaneGitHub,
            notificationCountForWorktree: notificationCountForWorktree,
            drawerDropTarget: drawerDropTarget,
            dismissCoordinateView: drawerDismissCoordinateView,
            workspaceWindowId: workspaceWindowId,
            dragSourcePaneId: activeDragSourcePaneId
        )
    }

    @ViewBuilder
    private func mainSplitManagementOverlay(
        containerBounds: CGRect,
        mainSplitDragCaptureEnabled: Bool
    ) -> some View {
        if managementLayer.isActive && mainSplitDragCaptureEnabled {
            let activeVisual: DropTargetVisual? =
                dropTarget.flatMap { activeTarget in
                    PaneDragCoordinator.visual(
                        for: activeTarget,
                        paneFrames: paneFrames,
                        containerBounds: containerBounds,
                        minimizedPaneIds: minimizedPaneIds,
                        sourcePaneId: activeDragSourcePaneId
                    )
                }
            PaneDropTargetOverlay(visual: activeVisual)
                .allowsHitTesting(false)

            SplitContainerDropCaptureOverlay(
                paneFrames: paneFrames,
                containerBounds: containerBounds,
                minimizedPaneIds: minimizedPaneIds,
                target: $dropTarget,
                sourcePaneId: $activeDragSourcePaneId,
                isManagementLayerActive: true,
                actionDispatcher: actionDispatcher
            )
        }
    }

    @ViewBuilder
    private func tabLevelDrawerCapture(expandedDrawerParentPaneId: UUID?) -> some View {
        if DrawerDragOwnershipPolicy.drawerCaptureEnabled(
            managementLayerActive: managementLayer.isActive,
            expandedDrawerParentPaneId: expandedDrawerParentPaneId,
            drawerPanelFrameInTab: drawerPanelFrameInTab
        ),
            let expandedDrawerPaneId = expandedDrawerParentPaneId,
            store.paneAtom.pane(expandedDrawerPaneId)?.drawer != nil,
            let expandedDrawerView = atom(\.arrangementView).drawerView(forParent: expandedDrawerPaneId),
            let captureGeometry = DrawerCaptureGeometry.make(
                panelFrameInTab: drawerPanelFrameInTab,
                paneFramesInDrawer: drawerPaneFramesInDrawer
            )
        {
            let drawerBounds = captureGeometry.containerBounds
            let drawerDispatchContext = DrawerDropDispatch.context(
                parentPaneId: expandedDrawerPaneId,
                store: store
            )
            DrawerSplitContainerDropCaptureOverlay(
                paneFrames: captureGeometry.paneFramesInDrawer,
                layout: expandedDrawerView.layout,
                minimizedPaneIds: expandedDrawerView.minimizedPaneIds,
                containerBounds: drawerBounds,
                target: $drawerDropTarget,
                sourcePaneId: $activeDragSourcePaneId,
                isManagementLayerActive: true,
                shouldAcceptDrop: { payload, target, sizingMode in
                    DrawerDropDispatch.shouldAcceptDrop(
                        payload: payload,
                        target: target,
                        sizingMode: sizingMode,
                        context: drawerDispatchContext
                    )
                },
                handleDrop: { payload, target, sizingMode in
                    DrawerDropDispatch.handleDrop(
                        payload: payload,
                        target: target,
                        sizingMode: sizingMode,
                        context: drawerDispatchContext,
                        actionDispatcher: actionDispatcher
                    )
                }
            )
            .frame(width: drawerBounds.width, height: drawerBounds.height)
            .position(x: captureGeometry.panelFrameInTab.midX, y: captureGeometry.panelFrameInTab.midY)
        }
    }

    private func startDropTargetMouseUpMonitor() {
        stopDropTargetMouseUpMonitor()

        dropTargetMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            dropTarget = nil
            return event
        }
    }

    private func stopDropTargetMouseUpMonitor() {
        if let dropTargetMouseUpMonitor {
            NSEvent.removeMonitor(dropTargetMouseUpMonitor)
            self.dropTargetMouseUpMonitor = nil
        }
    }

    private func startDrawerDropTargetMouseUpMonitor() {
        stopDrawerDropTargetMouseUpMonitor()

        drawerDropTargetMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            drawerDropTarget = nil
            return event
        }
    }

    private func stopDrawerDropTargetMouseUpMonitor() {
        if let drawerDropTargetMouseUpMonitor {
            NSEvent.removeMonitor(drawerDropTargetMouseUpMonitor)
            self.drawerDropTargetMouseUpMonitor = nil
        }
    }
}
