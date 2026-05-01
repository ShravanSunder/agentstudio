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
    let activeChildId: UUID?
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
    let paneInboxPresentation: PaneInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void
    let dropTarget: DrawerRearrangeTarget?
    /// Active drag's source pane id, used to omit self/adjacent
    /// targets from the visuals dict the overlay paints (R1, R2, R8).
    let dragSourcePaneId: UUID?

    @State private var drawerPaneFrames: [UUID: CGRect] = [:]
    @State private var drawerActionDispatcher: PaneTabActionDispatcher
    private var managementLayer: ManagementLayerAtom {
        atom(\.managementLayer)
    }

    private var drawerSurfaceId: String {
        "drawerShell:\(parentPaneId)"
    }

    private var renderedDrawerPaneIds: Set<UUID> {
        Set(layout.paneIds)
    }

    init(
        layout: DrawerGridLayout,
        parentPaneId: UUID,
        tabId: UUID,
        activeChildId: UUID?,
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
        paneInboxPresentation: PaneInboxPresentation?,
        onOpenPaneGitHub: @escaping (UUID) -> Void,
        dropTarget: DrawerRearrangeTarget?,
        dragSourcePaneId: UUID?
    ) {
        self.layout = layout
        self.parentPaneId = parentPaneId
        self.tabId = tabId
        self.activeChildId = activeChildId
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
        self.paneInboxPresentation = paneInboxPresentation
        self.onOpenPaneGitHub = onOpenPaneGitHub
        self.dropTarget = dropTarget
        self.dragSourcePaneId = dragSourcePaneId
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
                    case .closePane(let tabId, let paneId):
                        action(.closePane(tabId: tabId, paneId: paneId))
                    case .insertPaneRequest(let request):
                        action(
                            .insertDrawerPane(
                                parentPaneId: parentPaneId,
                                targetDrawerPaneId: request.targetPaneId,
                                direction: request.direction,
                                sizingMode: request.sizingMode
                            )
                        )
                    default:
                        action(paneAction)
                    }
                },
                shouldHandleSplitDragPayload: { _ in true },
                shouldAcceptDrop: { _, _, _, _ in false },
                handleDrop: { _, _, _, _ in
                    #if DEBUG
                        assertionFailure("DrawerPanel drop handling is routed by the drawer overlay")
                    #endif
                }
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
            activePaneId: activeChildId,
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
            paneInboxPresentation: paneInboxPresentation,
            onOpenPaneGitHub: onOpenPaneGitHub
        )
    }

    /// Empty-drawer keystroke hint. Both halves come from the existing
    /// command-spec system so the on-screen text stays in lockstep with
    /// the keystroke gate and the command's action label.
    ///   key   ──► AppShortcut.addDrawerPane displayed in `.emptyDrawer`
    ///             context (returns the raw-character alternate "P").
    ///   text  ──► LocalActionSpec.addDrawerPane.actionSpec.helpText
    @ViewBuilder
    private var emptyDrawerHint: some View {
        let keyDisplay = AppShortcut.addDrawerPane.displayKeyBinding(in: .emptyDrawer)?.displayString ?? ""
        let actionText = LocalActionSpec.addDrawerPane.actionSpec.helpText.lowercased()
        Text("Press \(keyDisplay) to \(actionText)")
            .font(.system(size: AppStyles.General.Typography.textXs))
            .foregroundStyle(.tertiary)
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

    var body: some View {
        GeometryReader { geometry in
            let containerBounds = CGRect(origin: .zero, size: geometry.size)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // Resize handle at top
                    DrawerResizeHandle(onDrag: onResize)

                    if !layout.isEmpty {
                        // Row-to-row spacing matches horizontal pane gap so the
                        // grid reads as a uniform 2x2 arrangement instead of
                        // two visually separate strips.
                        VStack(spacing: AppStyles.General.Layout.paneGap) {
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
                            emptyDrawerHint
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if managementLayer.isActive {
                    DrawerDropTargetOverlay(
                        target: dropTarget,
                        targetVisuals: DrawerPaneDragCoordinator.targetVisuals(
                            geometry: DrawerPaneDragGeometry(
                                paneFrames: drawerPaneFrames,
                                layout: layout,
                                containerBounds: containerBounds,
                                minimizedPaneIds: minimizedPaneIds,
                                excludedPaneIds: dragSourcePaneId.map { [$0] } ?? []
                            )
                        )
                    )
                    .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(DrawerPaneFramePreferenceKey.self) { drawerPaneFrames = $0 }
        }
        .frame(height: height)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DrawerPanelFrameInTabKey.self,
                    value: geometry.frame(in: .named("tabContainer"))
                )
            }
        )
        .coordinateSpace(name: Self.drawerDropCoordinateSpace)
        .contentShape(RoundedRectangle(cornerRadius: DrawerLayout.panelCornerRadius, style: .continuous))
        .modifier(
            DrawerSurfaceRegistrationModifier(
                viewRegistry: viewRegistry,
                surfaceId: drawerSurfaceId,
                renderedPaneIds: renderedDrawerPaneIds
            )
        )
    }

    private static let drawerDropCoordinateSpace = "drawerContainer"
}

private struct DrawerSurfaceRegistrationModifier: ViewModifier {
    let viewRegistry: ViewRegistry
    let surfaceId: String
    let renderedPaneIds: Set<UUID>

    func body(content: Content) -> some View {
        content
            .onAppear {
                viewRegistry.surfaceRenderedIds(surfaceId, ids: renderedPaneIds)
            }
            .onChange(of: renderedPaneIds) { _, paneIds in
                viewRegistry.surfaceRenderedIds(surfaceId, ids: paneIds)
            }
            .onDisappear {
                viewRegistry.unregisterSurface(surfaceId)
            }
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
                    activeChildId: nil,
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
                    paneInboxPresentation: nil,
                    onOpenPaneGitHub: { _ in },
                    dropTarget: nil,
                    dragSourcePaneId: nil
                )
                Spacer()
            }
            .frame(width: 500, height: 400)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
