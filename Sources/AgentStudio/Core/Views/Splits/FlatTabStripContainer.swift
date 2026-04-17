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
            let metrics = FlatTabStripMetrics.compute(
                layout: layout,
                in: containerBounds,
                dividerThickness: AppStyle.paneGap,
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
                            .font(.system(size: AppStyle.textSm, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(AppStyle.foregroundSecondary))
                            .padding(.horizontal, AppStyle.spacingStandard)
                            .padding(.vertical, AppStyle.paneGap)
                            .background(Capsule().fill(.white.opacity(AppStyle.strokeMuted)))
                            .padding(AppStyle.spacingLoose)
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
                    .animation(.easeOut(duration: AppStyle.animationFast), value: closingPaneIds)
                    .animation(.easeInOut(duration: AppStyle.animationStandard), value: minimizedPaneIds)
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
                    onOpenPaneGitHub: onOpenPaneGitHub
                )

                if managementLayer.isActive {
                    PaneDropTargetOverlay(target: dropTarget, paneFrames: paneFrames)
                        .allowsHitTesting(false)
                }

                SplitContainerDropCaptureOverlay(
                    paneFrames: paneFrames,
                    containerBounds: containerBounds,
                    target: $dropTarget,
                    isManagementLayerActive: managementLayer.isActive,
                    actionDispatcher: actionDispatcher
                )
            }
            .onPreferenceChange(PaneFramePreferenceKey.self) { paneFrames = $0 }
            .onPreferenceChange(DrawerIconBarFrameKey.self) { iconBarFrame = $0 }
            .onChange(of: managementLayer.isActive) { _, isActive in
                if !isActive {
                    dropTarget = nil
                }
            }
            .onChange(of: appLifecycleStore.isActive) { _, isActive in
                if !isActive {
                    dropTarget = nil
                }
            }
            .onChange(of: dropTarget) { _, target in
                if target == nil {
                    stopDropTargetWatchdog()
                } else {
                    startDropTargetWatchdog()
                }
            }
            .onDisappear {
                stopDropTargetWatchdog()
            }
        }
        .animation(.easeOut(duration: AppStyle.animationStandard), value: atom(\.uiState).showMinimizedBars)
        .animation(.easeOut(duration: AppStyle.animationFast), value: managementLayer.isActive)
        .coordinateSpace(name: "tabContainer")
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
}
