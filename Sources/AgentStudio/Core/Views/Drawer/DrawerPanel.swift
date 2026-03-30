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
/// Renders the drawer's flat pane strip inside a rectangular panel
/// with a resize handle at the top and material background.
///
/// Translates tab-level PaneActions dispatched by pane leaves
/// into drawer-specific actions (resize, minimize, close, focus, equalize).
struct DrawerPanel: View {
    let layout: Layout
    let parentPaneId: UUID
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let height: CGFloat
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let action: (PaneActionCommand) -> Void
    let onResize: (CGFloat) -> Void
    let onDismiss: () -> Void
    let appLifecycleStore: AppLifecycleStore

    @State private var drawerPaneFrames: [UUID: CGRect] = [:]
    @State private var dropTarget: PaneDropTarget?
    @State private var dropTargetWatchdogTask: Task<Void, Never>?
    @State private var drawerActionDispatcher: PaneTabActionDispatcher
    @Bindable private var managementMode = ManagementModeMonitor.shared

    init(
        layout: Layout,
        parentPaneId: UUID,
        tabId: UUID,
        activePaneId: UUID?,
        minimizedPaneIds: Set<UUID>,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        height: CGFloat,
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache,
        viewRegistry: ViewRegistry,
        action: @escaping (PaneActionCommand) -> Void,
        onResize: @escaping (CGFloat) -> Void,
        onDismiss: @escaping () -> Void,
        appLifecycleStore: AppLifecycleStore
    ) {
        self.layout = layout
        self.parentPaneId = parentPaneId
        self.tabId = tabId
        self.activePaneId = activePaneId
        self.minimizedPaneIds = minimizedPaneIds
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.height = height
        self.store = store
        self.repoCache = repoCache
        self.viewRegistry = viewRegistry
        self.action = action
        self.onResize = onResize
        self.onDismiss = onDismiss
        self.appLifecycleStore = appLifecycleStore
        self._drawerActionDispatcher = State(
            initialValue: PaneTabActionDispatcher(
                dispatch: { paneAction in
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
                                parentPaneId: parentPaneId,
                                targetDrawerPaneId: targetPaneId,
                                direction: direction
                            )
                        )
                    case .focusPane(_, let paneId):
                        action(.setActiveDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
                    default:
                        action(paneAction)
                    }
                },
                shouldAcceptDrop: { payload, destPaneId, zone in
                    guard let drawer = store.pane(parentPaneId)?.drawer else { return false }
                    guard drawer.layout.contains(destPaneId) else { return false }
                    guard case .existingPane(let sourcePaneId, _) = payload.kind else { return false }
                    guard sourcePaneId != destPaneId else { return false }
                    guard let sourcePane = store.pane(sourcePaneId) else { return false }
                    guard sourcePane.parentPaneId == parentPaneId else { return false }

                    let snapshot = ActionResolver.snapshot(
                        from: store.tabs,
                        activeTabId: store.activeTabId,
                        isManagementModeActive: ManagementModeMonitor.shared.isActive,
                        knownWorktreeIds: Set(store.repos.flatMap(\.worktrees).map(\.id))
                    )
                    let moveAction = PaneActionCommand.moveDrawerPane(
                        parentPaneId: parentPaneId,
                        drawerPaneId: sourcePaneId,
                        targetDrawerPaneId: destPaneId,
                        direction: Self.splitDirection(for: zone)
                    )
                    if case .success = ActionValidator.validate(moveAction, state: snapshot) {
                        return true
                    }
                    return false
                },
                handleDrop: { payload, destPaneId, zone in
                    guard case .existingPane(let sourcePaneId, _) = payload.kind else { return }
                    guard sourcePaneId != destPaneId else { return }
                    guard let sourcePane = store.pane(sourcePaneId) else { return }
                    guard sourcePane.parentPaneId == parentPaneId else { return }

                    action(
                        .moveDrawerPane(
                            parentPaneId: parentPaneId,
                            drawerPaneId: sourcePaneId,
                            targetDrawerPaneId: destPaneId,
                            direction: Self.splitDirection(for: zone)
                        )
                    )
                }
            )
        )
    }

    /// Translates tab-level actions into drawer-specific actions.
    /// Pane leaf interactions dispatch actions using tabId, but in the drawer
    /// context these need to be routed to drawer operations.
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

    var body: some View {
        GeometryReader { drawerGeometry in
            let containerBounds = CGRect(origin: .zero, size: drawerGeometry.size)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // Resize handle at top
                    DrawerResizeHandle(onDrag: onResize)

                    if !layout.isEmpty {
                        FlatPaneStripContent(
                            layout: layout,
                            tabId: tabId,
                            activePaneId: activePaneId,
                            minimizedPaneIds: minimizedPaneIds,
                            closeTransitionCoordinator: closeTransitionCoordinator,
                            actionDispatcher: drawerActionDispatcher,
                            store: store,
                            repoCache: repoCache,
                            viewRegistry: viewRegistry,
                            coordinateSpaceName: Self.drawerDropCoordinateSpace,
                            useDrawerFramePreference: true
                        )
                        .padding(.horizontal, DrawerLayout.panelContentPadding)
                        .padding(.bottom, DrawerLayout.panelContentPadding)
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
                    actionDispatcher: drawerActionDispatcher
                )
            }
            .onPreferenceChange(DrawerPaneFramePreferenceKey.self) { drawerPaneFrames = $0 }
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

        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return false }
        guard sourcePaneId != destPaneId else { return false }
        guard let sourcePane = store.pane(sourcePaneId) else { return false }
        guard sourcePane.parentPaneId == parentPaneId else { return false }

        let snapshot = ActionResolver.snapshot(
            from: store.tabs,
            activeTabId: store.activeTabId,
            isManagementModeActive: managementMode.isActive,
            knownWorktreeIds: Set(store.repos.flatMap(\.worktrees).map(\.id))
        )
        let action = PaneActionCommand.moveDrawerPane(
            parentPaneId: parentPaneId,
            drawerPaneId: sourcePaneId,
            targetDrawerPaneId: destPaneId,
            direction: Self.splitDirection(for: zone)
        )
        if case .success = ActionValidator.validate(action, state: snapshot) {
            return true
        }
        return false
    }

    private func handleDrawerDrop(payload: SplitDropPayload, destPaneId: UUID, zone: DropZone) {
        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return }
        guard sourcePaneId != destPaneId else { return }
        guard let sourcePane = store.pane(sourcePaneId) else { return }
        guard sourcePane.parentPaneId == parentPaneId else { return }

        action(
            .moveDrawerPane(
                parentPaneId: parentPaneId,
                drawerPaneId: sourcePaneId,
                targetDrawerPaneId: destPaneId,
                direction: Self.splitDirection(for: zone)
            )
        )
    }

    private static func splitDirection(for zone: DropZone) -> SplitNewDirection {
        switch zone {
        case .left: return .left
        case .right: return .right
        }
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

// Panel material is now applied at the DrawerPanelOverlay level
// using the unified DrawerOutlineShape (panel + S-curve connector as one surface).

// MARK: - Preview

#if DEBUG
    struct DrawerPanel_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                Spacer()
                DrawerPanel(
                    layout: Layout(),
                    parentPaneId: UUID(),
                    tabId: UUID(),
                    activePaneId: nil,
                    minimizedPaneIds: [],
                    closeTransitionCoordinator: PaneCloseTransitionCoordinator(),
                    height: 200,
                    store: WorkspaceStore(
                        persistor: WorkspacePersistor(workspacesDir: FileManager.default.temporaryDirectory)),
                    repoCache: WorkspaceRepoCache(),
                    viewRegistry: ViewRegistry(),
                    action: { _ in },
                    onResize: { _ in },
                    onDismiss: {},
                    appLifecycleStore: AppLifecycleStore()
                )
                Spacer()
            }
            .frame(width: 500, height: 400)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
