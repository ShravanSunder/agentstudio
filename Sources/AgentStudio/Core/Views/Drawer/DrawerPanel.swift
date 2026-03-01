import AppKit
import SwiftUI

// MARK: - DrawerResizeHandle

/// Draggable resize handle at the top of the drawer panel.
/// Reports vertical drag deltas so the parent can adjust the panel height.
struct DrawerResizeHandle: View {
    let onDrag: (CGFloat) -> Void
    @State private var isDragging = false
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: DrawerLayout.resizeHandleHeight)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(isDragging ? 0.4 : 0.2))
                    .frame(width: DrawerLayout.resizeHandlePillWidth, height: DrawerLayout.resizeHandlePillHeight)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let delta = value.translation.height - lastTranslation
                        lastTranslation = value.translation.height
                        onDrag(-delta)  // Negative: drag up = more height
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastTranslation = 0
                    }
            )
    }
}

// MARK: - DrawerPanel

/// Floating drawer panel that overlays pane content.
/// Renders the drawer's split tree (via SplitSubtreeView) in a rectangular panel
/// with a resize handle at the top and material background.
///
/// Translates tab-level PaneActions dispatched by SplitSubtreeView/PaneLeafContainer
/// into drawer-specific actions (resize, minimize, close, focus, equalize).
struct DrawerPanel: View {
    let tree: PaneSplitTree
    let parentPaneId: UUID
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let splitRenderInfo: SplitRenderInfo
    let height: CGFloat
    let store: WorkspaceStore
    let action: (PaneAction) -> Void
    let onResize: (CGFloat) -> Void
    let onDismiss: () -> Void

    @State private var drawerPaneFrames: [UUID: CGRect] = [:]
    @State private var dropTarget: PaneDropTarget?
    @State private var dropTargetWatchdogTask: Task<Void, Never>?
    @Bindable private var managementMode = ManagementModeMonitor.shared

    /// Translates tab-level actions into drawer-specific actions.
    /// SplitSubtreeView and PaneLeafContainer dispatch actions using tabId,
    /// but in the drawer context these need to be routed to drawer operations.
    @ViewBuilder
    private var addDrawerButton: some View {
        Button {
            action(.addDrawerPane(parentPaneId: parentPaneId))
        } label: {
            Image(systemName: "plus")
                .font(.system(size: AppStyle.text2xl, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(AppStyle.fillHover))
                )
        }
        .buttonStyle(.plain)
        .help("Add a drawer terminal")
    }

    private var drawerAction: (PaneAction) -> Void {
        { paneAction in
            switch paneAction {
            case .resizePane(_, let splitId, let ratio):
                action(.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: ratio))
            case .equalizePanes:
                action(.equalizeDrawerPanes(parentPaneId: parentPaneId))
            case .minimizePane(_, let paneId):
                action(.minimizeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            case .expandPane(_, let paneId):
                action(.expandDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            case .closePane(_, let paneId):
                action(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            case .insertPane(_, _, let targetPaneId, let direction):
                action(
                    .insertDrawerPane(
                        parentPaneId: parentPaneId, targetDrawerPaneId: targetPaneId, direction: direction))
            case .focusPane(_, let paneId):
                action(.setActiveDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            default:
                // Pass through any other actions (e.g., toggleDrawer)
                action(paneAction)
            }
        }
    }

    var body: some View {
        GeometryReader { drawerGeometry in
            let containerBounds = CGRect(origin: .zero, size: drawerGeometry.size)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // Resize handle at top
                    DrawerResizeHandle(onDrag: onResize)

                    // Drawer split tree content — padded to match inter-pane gap
                    if let node = tree.root, !splitRenderInfo.allMinimized {
                        SplitSubtreeView(
                            node: node,
                            tabId: tabId,
                            isSplit: tree.isSplit,
                            activePaneId: activePaneId,
                            minimizedPaneIds: minimizedPaneIds,
                            splitRenderInfo: splitRenderInfo,
                            action: drawerAction,
                            onPersist: nil,
                            store: store,
                            dropTargetCoordinateSpace: Self.drawerDropCoordinateSpace,
                            useDrawerFramePreference: true
                        )
                        .padding(.horizontal, DrawerLayout.panelContentPadding)
                        .padding(.bottom, DrawerLayout.panelContentPadding)
                    } else if splitRenderInfo.allMinimized {
                        // All drawer panes minimized — show bars + add button
                        HStack(spacing: 0) {
                            ForEach(splitRenderInfo.allMinimizedPaneIds, id: \.self) { paneId in
                                CollapsedPaneBar(
                                    paneId: paneId,
                                    tabId: tabId,
                                    title: store.pane(paneId)?.title ?? "Terminal",
                                    action: drawerAction
                                )
                                .frame(width: CollapsedPaneBar.barWidth)
                            }
                            Spacer()
                            addDrawerButton
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 12) {
                            Spacer()
                            addDrawerButton
                            Text("Add a drawer terminal")
                                .font(.system(size: AppStyle.textXs))
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if managementMode.isActive {
                    PaneDropTargetOverlay(target: dropTarget, paneFrames: drawerPaneFrames)
                        .allowsHitTesting(false)
                }

                SplitContainerDropCaptureOverlay(
                    paneFrames: drawerPaneFrames,
                    // Use full drawer panel geometry so edge corridors remain
                    // available for left/right insertion around outermost panes.
                    containerBounds: containerBounds,
                    target: $dropTarget,
                    isManagementModeActive: managementMode.isActive,
                    shouldAcceptDrop: shouldAcceptDrawerDrop,
                    onDrop: handleDrawerDrop
                )
            }
            .onPreferenceChange(DrawerPaneFramePreferenceKey.self) { drawerPaneFrames = $0 }
            .onChange(of: managementMode.isActive) { _, isActive in
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
            .task {
                for await _ in NotificationCenter.default.notifications(
                    named: NSApplication.didResignActiveNotification
                ) {
                    dropTarget = nil
                }
            }
        }
        .frame(height: height)
        .coordinateSpace(name: Self.drawerDropCoordinateSpace)
        .contentShape(RoundedRectangle(cornerRadius: DrawerLayout.panelCornerRadius, style: .continuous))
    }

    private static let drawerDropCoordinateSpace = "drawerContainer"

    private func shouldAcceptDrawerDrop(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZone
    ) -> Bool {
        guard managementMode.isActive else { return false }
        guard let drawer = store.pane(parentPaneId)?.drawer else { return false }
        guard drawer.layout.contains(destPaneId) else { return false }

        guard
            let plan = drawerDropCommitPlan(payload: payload, destPaneId: destPaneId, zone: zone),
            case .paneAction(let plannedAction) = plan,
            case .moveDrawerPane(
                let plannedParentPaneId,
                let drawerPaneId,
                let targetDrawerPaneId,
                let direction
            ) = plannedAction
        else {
            return false
        }

        return plannedParentPaneId == parentPaneId
            && drawerPaneId != destPaneId
            && targetDrawerPaneId == destPaneId
            && direction == splitDirection(for: zone)
    }

    private func handleDrawerDrop(payload: SplitDropPayload, destPaneId: UUID, zone: DropZone) {
        guard
            let plan = drawerDropCommitPlan(payload: payload, destPaneId: destPaneId, zone: zone),
            case .paneAction(let plannedAction) = plan,
            case .moveDrawerPane = plannedAction
        else {
            return
        }

        action(plannedAction)
    }

    private func splitDirection(for zone: DropZone) -> SplitNewDirection {
        switch zone {
        case .left: return .left
        case .right: return .right
        }
    }

    private func drawerDropCommitPlan(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZone
    ) -> DropCommitPlan? {
        let destination = PaneDropDestination.split(
            targetPaneId: destPaneId,
            targetTabId: tabId,
            direction: splitDirection(for: zone),
            targetDrawerParentPaneId: parentPaneId
        )
        let decision = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: destination,
            state: drawerDropSnapshot()
        )
        if case .eligible(let plan) = decision {
            return plan
        }
        return nil
    }

    private func drawerDropSnapshot() -> ActionStateSnapshot {
        let drawerParentByPaneId = store.panes.values.reduce(into: [UUID: UUID]()) { result, pane in
            guard let parentPaneId = pane.parentPaneId else { return }
            result[pane.id] = parentPaneId
        }
        return ActionResolver.snapshot(
            from: store.tabs,
            activeTabId: store.activeTabId,
            isManagementModeActive: managementMode.isActive,
            knownWorktreeIds: Set(store.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId
        )
    }

    private func startDropTargetWatchdog() {
        stopDropTargetWatchdog()

        dropTargetWatchdogTask = Task { @MainActor in
            while !Task.isCancelled {
                if DropTargetLatchState.shouldClearTarget(
                    appIsActive: NSApplication.shared.isActive,
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

// Panel material is now applied at the DrawerPanelOverlay level
// using the unified DrawerOutlineShape (panel + S-curve connector as one surface).

// MARK: - Preview

#if DEBUG
    struct DrawerPanel_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                Spacer()
                DrawerPanel(
                    tree: PaneSplitTree(),
                    parentPaneId: UUID(),
                    tabId: UUID(),
                    activePaneId: nil,
                    minimizedPaneIds: [],
                    splitRenderInfo: SplitRenderInfo.compute(layout: Layout(), minimizedPaneIds: []),
                    height: 200,
                    store: WorkspaceStore(
                        persistor: WorkspacePersistor(workspacesDir: FileManager.default.temporaryDirectory)),
                    action: { _ in },
                    onResize: { _ in },
                    onDismiss: {}
                )
                Spacer()
            }
            .frame(width: 500, height: 400)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
