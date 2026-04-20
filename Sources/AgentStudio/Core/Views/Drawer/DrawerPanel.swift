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
    let layout: DrawerGridLayout
    let parentPaneId: UUID
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let height: CGFloat
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let action: (PaneActionCommand) -> Void
    let onResize: (CGFloat) -> Void
    let onDismiss: () -> Void
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let appLifecycleStore: AppLifecycleAtom
    let onOpenPaneGitHub: (UUID) -> Void

    @State private var drawerPaneFrames: [UUID: CGRect] = [:]
    @State private var dropTarget: DrawerPaneDropTarget?
    @State private var dropTargetWatchdogTask: Task<Void, Never>?
    @State private var drawerActionDispatcher: PaneTabActionDispatcher
    private var managementLayer: ManagementLayerAtom {
        atom(\.managementLayer)
    }

    init(
        layout: DrawerGridLayout,
        parentPaneId: UUID,
        tabId: UUID,
        activePaneId: UUID?,
        minimizedPaneIds: Set<UUID>,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        height: CGFloat,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        viewRegistry: ViewRegistry,
        action: @escaping (PaneActionCommand) -> Void,
        onResize: @escaping (CGFloat) -> Void,
        onDismiss: @escaping () -> Void,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler,
        appLifecycleStore: AppLifecycleAtom,
        onOpenPaneGitHub: @escaping (UUID) -> Void
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
        self.onPaneFocusTrigger = onPaneFocusTrigger
        self.appLifecycleStore = appLifecycleStore
        self.onOpenPaneGitHub = onOpenPaneGitHub
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
                    default:
                        action(paneAction)
                    }
                },
                shouldAcceptDrop: { _, _, _ in false },
                handleDrop: { _, _, _ in }
            )
        )
    }

    /// Translates tab-level actions into drawer-specific actions.
    /// Pane leaf interactions dispatch actions using tabId, but in the drawer
    /// context these need to be routed to drawer operations.
    @ViewBuilder
    private func rowContent(_ rowLayout: Layout) -> some View {
        FlatPaneStripContent(
            layout: rowLayout,
            tabId: tabId,
            activePaneId: activePaneId,
            minimizedPaneIds: minimizedPaneIds,
            collapsedPaneWidth: CollapsedPaneBar.barWidth,
            onSaveArrangement: nil,
            closeTransitionCoordinator: closeTransitionCoordinator,
            actionDispatcher: drawerActionDispatcher,
            onPaneFocusTrigger: onPaneFocusTrigger,
            store: store,
            repoCache: repoCache,
            viewRegistry: viewRegistry,
            coordinateSpaceName: Self.drawerDropCoordinateSpace,
            useDrawerFramePreference: true,
            onOpenPaneGitHub: onOpenPaneGitHub
        )
    }

    @ViewBuilder
    private var addDrawerButton: some View {
        Button {
            action(.addDrawerPane(parentPaneId: parentPaneId))
        } label: {
            Image(systemName: "plus")
                .font(.system(size: AppStyles.General.Typography.text2xl, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(AppStyles.General.Fill.hover))
                )
        }
        .buttonStyle(.plain)
        .help(LocalActionSpec.addDrawerTerminal.actionSpec.helpText)
    }

    private func shouldAcceptDrawerDrop(
        payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DrawerDropZone
    ) -> Bool {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return false }
        guard drawer.layout.contains(destinationPaneId) else { return false }
        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return false }
        guard sourcePaneId != destinationPaneId else { return false }
        guard let sourcePane = store.paneAtom.pane(sourcePaneId) else { return false }
        guard sourcePane.parentPaneId == parentPaneId else { return false }

        let snapshot = WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId(),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId()
        )
        let moveAction = PaneActionCommand.moveDrawerPane(
            parentPaneId: parentPaneId,
            drawerPaneId: sourcePaneId,
            target: drawer.layout.legacyMoveTarget(
                targetPaneId: destinationPaneId,
                direction: zone.newDirection
            ) ?? .rowSlot(row: .top, insertionIndex: 0)
        )
        if case .success = WorkspaceCommandValidator.validate(moveAction, state: snapshot) {
            return true
        }
        return false
    }

    private func handleDrawerDrop(
        payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DrawerDropZone
    ) {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return }
        guard case .existingPane(let sourcePaneId, _) = payload.kind else { return }
        guard sourcePaneId != destinationPaneId else { return }
        guard let sourcePane = store.paneAtom.pane(sourcePaneId) else { return }
        guard sourcePane.parentPaneId == parentPaneId else { return }

        action(
            .moveDrawerPane(
                parentPaneId: parentPaneId,
                drawerPaneId: sourcePaneId,
                target: drawer.layout.legacyMoveTarget(
                    targetPaneId: destinationPaneId,
                    direction: zone.newDirection
                ) ?? .rowSlot(row: .top, insertionIndex: 0)
            )
        )
    }

    private func drawerParentByPaneId() -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard let drawerParentPaneId = pane.parentPaneId else { return nil }
                return (pane.id, drawerParentPaneId)
            }
        )
    }

    private func drawerLayoutByParentPaneId() -> [UUID: DrawerGridLayout] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard let drawer = pane.drawer else { return nil }
                return (pane.id, drawer.layout)
            }
        )
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // Resize handle at top
                    DrawerResizeHandle(onDrag: onResize)

                    if !layout.isEmpty {
                        VStack(spacing: DrawerLayout.panelContentPadding) {
                            rowContent(layout.topRow)
                            if let bottomRow = layout.bottomRow {
                                rowContent(bottomRow)
                            }
                        }
                        .padding(.horizontal, DrawerLayout.panelContentPadding)
                        .padding(.bottom, DrawerLayout.panelContentPadding)
                    } else {
                        VStack(spacing: 12) {
                            Spacer()
                            addDrawerButton
                            Text(
                                managementLayer.isActive
                                    ? "Press P to add the first drawer pane"
                                    : "Press D to add the first drawer pane"
                            )
                            .font(.system(size: AppStyles.General.Typography.textXs))
                            .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if managementLayer.isActive {
                    DrawerDropTargetOverlay(target: dropTarget, paneFrames: drawerPaneFrames)
                        .allowsHitTesting(false)
                }

                DrawerSplitContainerDropCaptureOverlay(
                    paneFrames: drawerPaneFrames,
                    target: $dropTarget,
                    isManagementLayerActive: managementLayer.isActive,
                    shouldAcceptDrop: shouldAcceptDrawerDrop,
                    handleDrop: handleDrawerDrop
                )
            }
            .onPreferenceChange(DrawerPaneFramePreferenceKey.self) { drawerPaneFrames = $0 }
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
        .frame(height: height)
        .coordinateSpace(name: Self.drawerDropCoordinateSpace)
        .contentShape(RoundedRectangle(cornerRadius: DrawerLayout.panelCornerRadius, style: .continuous))
    }

    private static let drawerDropCoordinateSpace = "drawerContainer"

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
                    layout: DrawerGridLayout(),
                    parentPaneId: UUID(),
                    tabId: UUID(),
                    activePaneId: nil,
                    minimizedPaneIds: [],
                    closeTransitionCoordinator: PaneCloseTransitionCoordinator(),
                    height: 200,
                    store: WorkspaceStore(
                        persistor: WorkspacePersistor(workspacesDir: FileManager.default.temporaryDirectory)),
                    repoCache: RepoCacheAtom(),
                    viewRegistry: ViewRegistry(),
                    action: { _ in },
                    onResize: { _ in },
                    onDismiss: {},
                    onPaneFocusTrigger: { _ in },
                    appLifecycleStore: AppLifecycleAtom(),
                    onOpenPaneGitHub: { _ in }
                )
                Spacer()
            }
            .frame(width: 500, height: 400)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
