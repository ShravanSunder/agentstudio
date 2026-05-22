import AppKit
import SwiftUI

struct FlatTabStripContainer: View {
    let layout: Layout
    let tabId: UUID
    let activePaneId: UUID?
    let zoomedPaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let visiblePaneIds: [UUID]?
    let showsMinimizedPanes: Bool
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleAtom
    let paneInboxPresentation: PaneInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void

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
    private var managementLayer: ManagementLayerAtom {
        atom(\.managementLayer)
    }

    init(
        layout: Layout,
        tabId: UUID,
        activePaneId: UUID?,
        zoomedPaneId: UUID?,
        minimizedPaneIds: Set<UUID>,
        visiblePaneIds: [UUID]? = nil,
        showsMinimizedPanes: Bool = true,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        viewRegistry: ViewRegistry,
        appLifecycleStore: AppLifecycleAtom,
        paneInboxPresentation: PaneInboxPresentation? = nil,
        onOpenPaneGitHub: @escaping (UUID) -> Void
    ) {
        self.layout = layout
        self.tabId = tabId
        self.activePaneId = activePaneId
        self.zoomedPaneId = zoomedPaneId
        self.minimizedPaneIds = minimizedPaneIds
        self.visiblePaneIds = visiblePaneIds
        self.showsMinimizedPanes = showsMinimizedPanes
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.onPaneFocusTrigger = onPaneFocusTrigger
        self.store = store
        self.repoCache = repoCache
        self.viewRegistry = viewRegistry
        self.appLifecycleStore = appLifecycleStore
        self.paneInboxPresentation = paneInboxPresentation
        self.onOpenPaneGitHub = onOpenPaneGitHub
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
            let rendersMinimizedBars = managementLayer.isActive || showsMinimizedPanes
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
            let surfaceId = "tab:\(tabId)"
            let renderedPaneIds: Set<UUID> = {
                if let zoomedPaneId {
                    return [zoomedPaneId]
                }
                if effectiveVisiblePaneIds.isEmpty {
                    return []
                } else if metrics.allMinimized {
                    return rendersMinimizedBars ? Set(layout.paneIds) : []
                }
                return Set(effectiveVisiblePaneIds)
            }()
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
                } else if effectiveVisiblePaneIds.isEmpty {
                    EmptyArrangementPlaceholderView()
                } else if metrics.allMinimized {
                    if rendersMinimizedBars {
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
                        isInactivePersistentTab: isInactivePersistentTab,
                        paneInboxPresentation: paneInboxPresentation,
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
                    paneInboxPresentation: paneInboxPresentation,
                    onOpenPaneGitHub: onOpenPaneGitHub,
                    drawerDropTarget: drawerDropTarget,
                    dismissCoordinateView: drawerDismissCoordinateView,
                    dragSourcePaneId: activeDragSourcePaneId
                )

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
            value: managementLayer.isActive || showsMinimizedPanes
        )
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
            onOpenPaneGitHub: onOpenPaneGitHub,
            paneInboxPresentation: paneInboxPresentation
        )
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
