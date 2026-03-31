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
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleStore

    @State private var paneFrames: [UUID: CGRect] = [:]
    @State private var iconBarFrame: CGRect = .zero
    @State private var dropTarget: PaneDropTarget?
    @State private var dropTargetWatchdogTask: Task<Void, Never>?
    @Bindable private var managementMode = ManagementModeMonitor.shared

    var body: some View {
        GeometryReader { tabGeometry in
            let containerBounds = CGRect(origin: .zero, size: tabGeometry.size)
            let metrics = FlatTabStripMetrics.compute(
                layout: layout,
                in: containerBounds,
                dividerThickness: AppStyle.paneGap,
                minimizedPaneIds: minimizedPaneIds,
                collapsedPaneWidth: CollapsedPaneBar.barWidth
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
                    HStack(spacing: 0) {
                        ForEach(layout.paneIds, id: \.self) { paneId in
                            CollapsedPaneBar(
                                paneId: paneId,
                                tabId: tabId,
                                title: PaneDisplayProjector.displayLabel(
                                    for: paneId, store: store, repoCache: repoCache),
                                closeTransitionCoordinator: closeTransitionCoordinator,
                                actionDispatcher: actionDispatcher,
                                dropTargetCoordinateSpace: "tabContainer"
                            )
                            .frame(width: CollapsedPaneBar.barWidth)
                        }
                        Spacer()
                    }
                } else {
                    FlatPaneStripContent(
                        layout: layout,
                        tabId: tabId,
                        activePaneId: activePaneId,
                        minimizedPaneIds: minimizedPaneIds,
                        closeTransitionCoordinator: closeTransitionCoordinator,
                        actionDispatcher: actionDispatcher,
                        store: store,
                        repoCache: repoCache,
                        viewRegistry: viewRegistry,
                        coordinateSpaceName: "tabContainer",
                        useDrawerFramePreference: false
                    )
                    .animation(.easeOut(duration: AppStyle.animationFast), value: closingPaneIds)
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
                    actionDispatcher: actionDispatcher
                )

                if managementMode.isActive {
                    PaneDropTargetOverlay(target: dropTarget, paneFrames: paneFrames)
                        .allowsHitTesting(false)
                }

                SplitContainerDropCaptureOverlay(
                    paneFrames: paneFrames,
                    containerBounds: containerBounds,
                    target: $dropTarget,
                    isManagementModeActive: managementMode.isActive,
                    actionDispatcher: actionDispatcher
                )
            }
            .onPreferenceChange(PaneFramePreferenceKey.self) { paneFrames = $0 }
            .onPreferenceChange(DrawerIconBarFrameKey.self) { iconBarFrame = $0 }
            .onChange(of: managementMode.isActive) { _, isActive in
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
            store: store,
            repoCache: repoCache,
            closeTransitionCoordinator: closeTransitionCoordinator,
            actionDispatcher: actionDispatcher
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
