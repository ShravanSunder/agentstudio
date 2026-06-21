import AppKit
import GhosttyKit
import Observation
import SwiftUI
import os.log

// swiftlint:disable file_length type_body_length

private final class RestoreAwareTerminalContainerView: NSView {
    var onNonEmptyLayoutBoundsChanged: ((CGRect) -> Void)?
    private var lastLoggedBounds: CGRect = .zero
    private var lastPublishedBounds: CGRect = .zero
    private var layoutGeneration: Int = 0

    override func layout() {
        super.layout()
        logBoundsChangeIfNeeded(reason: "layout")
        publishNonEmptyLayoutBoundsChangedIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        RestoreTrace.log(
            "RestoreAwareTerminalContainerView.viewDidMoveToWindow window=\(window != nil) id=\(ObjectIdentifier(self)) superview=\(superview != nil) bounds=\(NSStringFromRect(bounds))"
        )
        logBoundsChangeIfNeeded(reason: "viewDidMoveToWindow")
        publishNonEmptyLayoutBoundsChangedIfNeeded()
    }

    private func logBoundsChangeIfNeeded(reason: StaticString) {
        guard bounds != lastLoggedBounds else { return }
        layoutGeneration += 1
        lastLoggedBounds = bounds
        RestoreTrace.log(
            "RestoreAwareTerminalContainerView \(reason) generation=\(layoutGeneration) bounds=\(NSStringFromRect(bounds)) window=\(window != nil)"
        )
    }

    private func publishNonEmptyLayoutBoundsChangedIfNeeded() {
        guard !bounds.isEmpty, bounds != lastPublishedBounds else { return }
        lastPublishedBounds = bounds
        onNonEmptyLayoutBoundsChanged?(bounds)
    }
}

struct SplitDropCommitDestination: Equatable {
    let paneId: UUID
    let drawerParentPaneId: UUID?
}

private struct PaneInboxCommandTarget {
    let parentPaneId: UUID
    let paneIds: [UUID]
}

/// Tab-based terminal controller with custom Ghostty-style tab bar.
///
/// PaneTabViewController is a composition-oriented controller in `App/`. It reads
/// from WorkspaceStore for state and routes user actions through the validated
/// WorkspaceActionExecutor pipeline. Most flow changes are dispatched, while AppKit-only
/// concerns (focus, observers, empty-state visibility, tab bar coordination) stay
/// local. It also handles direct tab-order updates (`store.moveTab`) from drag
/// interactions as a UI-only mutation.
@MainActor
class PaneTabViewController: NSViewController, NSPopoverDelegate, WorkspaceCommandHandling {
    typealias OpenEditorHandler =
        @MainActor (_ id: EditorTargetId, _ path: URL, _ installedTargets: [ExternalEditorTarget]) -> Bool

    private static let logger = Logger(subsystem: "com.agentstudio", category: "PaneTabViewController")
    private static let genericGitHubURL = URL(string: "https://github.com")!

    private enum WorkspaceNavigationFocusScope: Equatable {
        case mainRow
        case drawer(parentPaneId: UUID)
    }

    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let applicationLifecycleMonitor: ApplicationLifecycleMonitor
    private let appLifecycleStore: AppLifecycleAtom
    private let windowLifecycleStore: WindowLifecycleAtom
    private let workspaceWindowId: UUID?
    private let executor: WorkspaceActionExecutor
    private let runtimeCommandDispatcher: any PaneRuntimeCommandDispatching
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry
    private let paneInboxPresentation: PaneInboxPresentation?
    private let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    private let tabRenamePopoverState: TabRenamePopoverState
    private let arrangementInlineRenameState: ArrangementInlineRenameState
    private let arrangementPanelPresentation: ArrangementPanelPresentationAtom
    private let registersAsCommandHandler: Bool
    private var tabRenamePopover: NSPopover?
    private var paneNotePopover: NSPopover?
    private var tabRenameTransientSurfaceToken: TransientKeyboardSurfaceToken?
    private let installedEditorTargetsProvider: @MainActor () -> [ExternalEditorTarget]
    private let openEditorHandler: OpenEditorHandler
    private let openFinderHandler: @MainActor (URL) -> Bool
    private let copyPathHandler: @MainActor (URL) -> Void
    private let paneNotePresentation: PaneNotePresentation?
    private var arrangementView: WorkspaceArrangementViewDerived {
        WorkspaceArrangementViewDerived(
            tabLayoutAtom: store.tabLayoutAtom,
            paneAtom: store.paneAtom,
            managementLayerAtom: atom(\.managementLayer)
        )
    }
    private lazy var actionDispatcher = PaneTabActionDispatcher(
        dispatch: { [weak self] action in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.dispatch dropped ownerReleased action=\(String(describing: action))"
                )
                return
            }
            self.dispatchAction(action)
        },
        shouldHandleSplitDragPayload: { [weak self] payload in
            guard let self else {
                RestoreTrace.log("PaneTabActionDispatcher.shouldHandleSplitDragPayload dropped ownerReleased")
                return false
            }
            return self.shouldHandleSplitDragPayload(payload)
        },
        shouldAcceptDrop: { [weak self] payload, destPaneId, zone, sizingMode in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.shouldAcceptDrop dropped ownerReleased destPaneId=\(destPaneId) zone=\(zone)"
                )
                return false
            }
            return self.evaluateDropAcceptance(
                payload: payload,
                destPaneId: destPaneId,
                zone: zone,
                sizingMode: sizingMode
            )
        },
        handleDrop: { [weak self] payload, destPaneId, zone, sizingMode in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.handleDrop dropped ownerReleased destPaneId=\(destPaneId) zone=\(zone)"
                )
                return
            }
            self.handleSplitDrop(payload: payload, destPaneId: destPaneId, zone: zone, sizingMode: sizingMode)
        }
    )

    // MARK: - View State

    private var tabBarHostingView: DraggableTabBarHostingView!
    private var terminalContainer: RestoreAwareTerminalContainerView!
    private var emptyStateView: NSHostingView<WorkspaceEmptyStateView>?
    private var lastEmptyStateModel: WorkspaceEmptyStateModel?
    private var tabContentHosts: [UUID: PersistentTabHostView] = [:]
    #if DEBUG
        private(set) var paneRepresentableDismantleCount = 0
    #endif

    /// Local event monitor for arrangement bar keyboard shortcut
    private var arrangementBarEventMonitor: Any?
    private var notificationTasks: [Task<Void, Never>] = []
    private var pendingVisibleViewRestoreTask: Task<Void, Never>?

    /// Focus tracking — only refocus when the active tab or pane actually changes
    private var lastFocusedTabId: UUID?
    private var lastFocusedPaneId: UUID?
    private var suppressedSelectionDrivenRefocus: (tabId: UUID?, paneId: UUID?)?
    private var lastManagementLayerActive = false
    private var managementNavigationScope: WorkspaceNavigationFocusScope = .mainRow
    private lazy var paneFocusExecutor = makePaneFocusExecutor()

    // MARK: - Init

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleAtom,
        windowLifecycleStore: WindowLifecycleAtom = atom(\.windowLifecycle),
        workspaceWindowId: UUID? = nil,
        executor: WorkspaceActionExecutor,
        runtimeCommandDispatcher: any PaneRuntimeCommandDispatching,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        paneInboxPresentation: PaneInboxPresentation? = nil,
        installedEditorTargetsProvider: @escaping @MainActor () -> [ExternalEditorTarget] = {
            ExternalEditorTarget.refreshInstalledTargets()
        },
        openEditorHandler: @escaping OpenEditorHandler = { id, path, installedTargets in
            ExternalWorkspaceOpener.openInEditor(
                id: id,
                path: path,
                installedTargets: installedTargets
            )
        },
        openFinderHandler: @escaping @MainActor (URL) -> Bool = { path in
            ExternalWorkspaceOpener.openInFinder(path)
        },
        copyPathHandler: @escaping @MainActor (URL) -> Void = { path in
            PathActions.copyPath(path)
        },
        paneNotePresentation: PaneNotePresentation? = nil,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
        tabRenamePopoverState: TabRenamePopoverState = TabRenamePopoverState(),
        arrangementInlineRenameState: ArrangementInlineRenameState = ArrangementInlineRenameState(),
        arrangementPanelPresentation: ArrangementPanelPresentationAtom = atom(\.arrangementPanelPresentation),
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        registersAsCommandHandler: Bool = true
    ) {
        self.store = store
        self.repoCache = repoCache
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.windowLifecycleStore = windowLifecycleStore
        self.workspaceWindowId = workspaceWindowId
        self.executor = executor
        self.runtimeCommandDispatcher = runtimeCommandDispatcher
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        self.paneInboxPresentation = paneInboxPresentation
        self.installedEditorTargetsProvider = installedEditorTargetsProvider
        self.openEditorHandler = openEditorHandler
        self.openFinderHandler = openFinderHandler
        self.copyPathHandler = copyPathHandler
        self.paneNotePresentation = paneNotePresentation
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.performanceTraceRecorder = performanceTraceRecorder
        self.tabRenamePopoverState = tabRenamePopoverState
        self.arrangementInlineRenameState = arrangementInlineRenameState
        self.arrangementPanelPresentation = arrangementPanelPresentation
        self.registersAsCommandHandler = registersAsCommandHandler
        super.init(nibName: nil, bundle: nil)
        setupNotificationObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    #if DEBUG
        func recordPaneRepresentableDismantleForTesting() {
            paneRepresentableDismantleCount += 1
        }
    #endif

    // MARK: - View Lifecycle

    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true

        // Create terminal container FIRST (so it's behind tab bar)
        terminalContainer = RestoreAwareTerminalContainerView()
        terminalContainer.wantsLayer = true
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.layer?.cornerRadius = 8
        terminalContainer.layer?.masksToBounds = true
        terminalContainer.onNonEmptyLayoutBoundsChanged = { [weak self] bounds in
            self?.applicationLifecycleMonitor.handleTerminalContainerBoundsChanged(bounds)
            self?.handleTerminalContainerBoundsChanged(reason: "terminalContainerLayout")
        }
        containerView.addSubview(terminalContainer)

        // Create custom tab bar AFTER (so it's on top visually)
        let tabBar = CustomTabBar(
            adapter: tabBarAdapter,
            arrangementInlineRenameState: arrangementInlineRenameState,
            onSelect: { [weak self] tabId in
                self?.handlePaneFocusTrigger(.tabClick(PaneTabClickFocusTrigger(targetTabId: tabId)))
            },
            onClose: { [weak self] tabId in
                self?.dispatchAction(.closeTab(tabId: tabId))
            },
            onCommand: { [weak self] command, tabId in
                self?.handleTabCommand(command, tabId: tabId)
            },
            onTabFramesChanged: { [weak self] frames in
                self?.tabBarHostingView?.updateTabFrames(frames)
            },
            onAdd: { [weak self] in
                self?.addNewTab()
            },
            onOpenGitHub: { [weak self] in
                self?.openGitHubWebview()
            },
            onPaneAction: { [weak self] action in
                self?.dispatchAction(action)
            },
            onSaveArrangement: { [weak self] tabId in
                guard let self, let tab = self.store.tabLayoutAtom.tab(tabId) else { return }
                let name = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
                self.dispatchAction(.createArrangement(tabId: tabId, name: name))
            },
            onOpenRepoInTab: {
                AppCommandDispatcher.shared.dispatch(.showCommandBarRepos)
            },
            workspaceWindowId: workspaceWindowId
        )
        tabBarHostingView = DraggableTabBarHostingView(rootView: tabBar)
        tabBarHostingView.configure(adapter: tabBarAdapter) { [weak self] fromId, toIndex in
            self?.handleTabReorder(fromId: fromId, toIndex: toIndex)
        }
        tabBarHostingView.dragPayloadProvider = { [weak self] tabId in
            self?.createDragPayload(for: tabId)
        }
        tabBarHostingView.onSelect = { [weak self] tabId in
            self?.handlePaneFocusTrigger(.tabClick(PaneTabClickFocusTrigger(targetTabId: tabId)))
        }
        tabBarHostingView.expandedDrawerParentIdForTab = { [weak self] tabId in
            guard let self else { return nil }
            return DrawerDragOwnershipPolicy.expandedDrawerParentPaneId(
                tabId: tabId,
                tabLayoutAtom: self.store.tabLayoutAtom,
                paneAtom: self.store.paneAtom
            )
        }
        tabBarHostingView.onAutoDismissDrawerForDrag = { [weak self] _, drawerParentPaneId in
            self?.dispatchAction(.toggleDrawer(paneId: drawerParentPaneId))
        }
        tabBarHostingView.translatesAutoresizingMaskIntoConstraints = false
        tabBarHostingView.wantsLayer = true
        containerView.addSubview(tabBarHostingView)

        // Create empty state view
        let emptyView = createEmptyStateView()
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(emptyView)
        self.emptyStateView = emptyView
        lastEmptyStateModel = emptyStateModel

        NSLayoutConstraint.activate([
            // Tab bar at top - use safeAreaLayoutGuide to respect titlebar
            tabBarHostingView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            tabBarHostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tabBarHostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tabBarHostingView.heightAnchor.constraint(equalToConstant: AppStyles.Shell.TabBar.height),

            // Terminal container below tab bar
            terminalContainer.topAnchor.constraint(equalTo: tabBarHostingView.bottomAnchor),
            terminalContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            terminalContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            terminalContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // Empty state fills container (respects safe area)
            emptyView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            emptyView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        view = containerView
        updateEmptyState()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if registersAsCommandHandler {
            AppCommandDispatcher.shared.handler = self
        }

        syncTabContentHosts()
        updateVisibleTabHost()

        // Observe store for AppKit-level concerns (empty state visibility, focus management)
        updateEmptyState()
        observeForAppKitState()
        observeForManagementLayerState()

        // App-owned global shortcuts route through the centralized command pipeline.
        arrangementBarEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.view.window?.isKeyWindow == true else { return event }
            if self.handleAppOwnedKeyEvent(event) {
                return nil
            }
            return event
        }

    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: true) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewWillLayout() {
        let clock = ContinuousClock()
        let layoutStart = clock.now
        super.viewWillLayout()
        syncTabContentHosts()
        updateVisibleTabHost()
        updateEmptyState()
        performanceTraceRecorder?.recordDuration(
            .paneTabLayout,
            duration: layoutStart.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.pane_tab_layout.pane.count": .int(store.paneAtom.panes.count),
                "agentstudio.performance.pane_tab_layout.tab.count": .int(store.tabLayoutAtom.tabs.count),
                "agentstudio.performance.pane_tab_layout.subview.count": .int(view.subviews.count),
                "agentstudio.performance.management_layer.is_active": .bool(atom(\.managementLayer).isActive),
            ]
        )
    }

    private func setupNotificationObservers() {
        guard notificationTasks.isEmpty else { return }
        setupAppNotificationObservers()
    }

    private func setupAppNotificationObservers() {
        notificationTasks.append(
            Task { [weak self] in
                let stream = await AppEventBus.shared.subscribe()
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .terminalProcessTerminated(let paneId):
                        await MainActor.run { [weak self] in
                            self?.handleTerminalProcessTerminated(paneId: paneId)
                        }
                    case .terminalProcessTerminationHandled, .worktreeBellRang:
                        continue
                    }
                }
            })
    }

    func shutdown() {
        pendingVisibleViewRestoreTask?.cancel()
        pendingVisibleViewRestoreTask = nil
        if let monitor = arrangementBarEventMonitor {
            NSEvent.removeMonitor(monitor)
            arrangementBarEventMonitor = nil
        }
        for task in notificationTasks {
            task.cancel()
        }
        notificationTasks.removeAll()
    }

    isolated deinit {
        let monitor = arrangementBarEventMonitor
        let tasks = notificationTasks
        let pendingVisibleViewRestoreTask = pendingVisibleViewRestoreTask
        pendingVisibleViewRestoreTask?.cancel()
        Task { @MainActor in
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            for task in tasks {
                task.cancel()
            }
        }
    }

    // MARK: - Store Observation (AppKit-Level Concerns)

    /// Observe store for AppKit-level state: empty state visibility and focus management.
    /// SwiftUI rendering is handled by per-tab SingleTabContent hosts — this method
    /// only handles things that live outside the SwiftUI tree (host visibility, firstResponder).
    private func observeForAppKitState() {
        withObservationTracking {
            _ = self.store.tabLayoutAtom.tabs
            _ = self.store.tabLayoutAtom.activeTabId
            _ = self.store.repositoryTopologyAtom.repos
            _ = atom(\.welcome).isChoosingFolder
            _ = atom(\.welcome).folderScanState
            _ = self.repoCache.recentTargets
        } onChange: {
            Task { @MainActor [weak self] in
                self?.handleAppKitStateChange()
                self?.observeForAppKitState()
            }
        }
    }

    private func observeForManagementLayerState() {
        withObservationTracking {
            _ = atom(\.managementLayer).isActive
        } onChange: {
            Task { @MainActor [weak self] in
                self?.handleManagementLayerStateChange()
                self?.observeForManagementLayerState()
            }
        }
    }

    private func handleAppKitStateChange() {
        syncTabContentHosts()
        updateVisibleTabHost()
        rebuildEmptyStateView()
        updateEmptyState()
        prunePaneInboxPresentationState()

        managementNavigationScope = normalizedWorkspaceNavigationFocusScope()

        // Focus management: only refocus when active tab or pane actually changes
        let currentTabId = store.tabLayoutAtom.activeTabId
        let currentPaneId = preferredVisibleFocusPaneId()
        let selectionChanged = currentTabId != lastFocusedTabId || currentPaneId != lastFocusedPaneId
        let activePaneViewMissing = currentPaneId.map { viewRegistry.view(for: $0) == nil } ?? false

        if selectionChanged || activePaneViewMissing {
            executor.restoreVisibleViewsForActiveTabIfNeeded()
        }

        if selectionChanged {
            lastFocusedTabId = currentTabId
            lastFocusedPaneId = currentPaneId
            if shouldSkipSelectionDrivenRefocus(currentTabId: currentTabId, currentPaneId: currentPaneId) {
                suppressedSelectionDrivenRefocus = nil
            } else {
                scheduleSelectionDrivenRefocus()
            }
        }
    }

    private func handleManagementLayerStateChange() {
        let clock = ContinuousClock()
        let start = clock.now
        let isManagementLayerActive = atom(\.managementLayer).isActive
        let didExitManagementLayer = lastManagementLayerActive && !isManagementLayerActive
        if lastManagementLayerActive != isManagementLayerActive {
            let transition: PaneModeFocusTrigger.Transition =
                isManagementLayerActive ? .enteredManagementLayer : .exitedManagementLayer
            handlePaneFocusTrigger(
                .mode(
                    PaneModeFocusTrigger(
                        transition: transition,
                        source: .command
                    )
                )
            )
        }

        if !lastManagementLayerActive && isManagementLayerActive {
            managementNavigationScope = initialWorkspaceNavigationFocusScope()
        }
        lastManagementLayerActive = isManagementLayerActive
        managementNavigationScope = normalizedWorkspaceNavigationFocusScope()

        // Management layer exit is intentionally a two-step sequence:
        // the mode trigger releases content interaction, then refocus chooses
        // the pane-specific responder target once the mode change has landed.
        if didExitManagementLayer {
            requestPaneRefocus(.managementLayerExited)
        }

        performanceTraceRecorder?.recordDuration(
            .managementLayerAppKitState,
            duration: start.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.management_layer.is_active": .bool(isManagementLayerActive),
                "agentstudio.performance.management_layer.did_exit": .bool(didExitManagementLayer),
            ]
        )
    }

    private func prunePaneInboxPresentationState() {
        guard let paneInboxPresentation else { return }
        let retainedParentPaneIds = Set(
            store.paneAtom.panes.values.compactMap { pane in
                pane.isDrawerChild ? nil : pane.id
            }
        )
        paneInboxPresentation.pruneFilterModes(retainedParentPaneIds)
    }

    private func preferredVisibleFocusPaneId() -> UUID? {
        switch normalizedWorkspaceNavigationScopeState() {
        case .drawerPane(_, let drawerPaneId):
            return drawerPaneId
        case .emptyDrawer:
            return nil
        case .mainPane(let paneId):
            return paneId
        }
    }

    private func scheduleSelectionDrivenRefocus() {
        // Tab host visibility changes land after the active-tab mutation, so
        // refocus on the next main-actor turn instead of racing the hidden host.
        Task { @MainActor [weak self] in
            self?.requestPaneRefocus(.explicit)
        }
    }

    private func makePaneFocusExecutor() -> PaneFocusExecutor {
        PaneFocusExecutor(
            hostViewProvider: { [weak self] paneId in
                self?.viewRegistry.view(for: paneId)
            },
            hostViewsProvider: { [weak self] in
                guard let self else { return [] }
                return self.viewRegistry.registeredPaneIds.compactMap { self.viewRegistry.view(for: $0) }
            },
            selectTab: { [weak self] tabId in
                guard let self else { return }
                self.selectTabAndRestoreVisibleViews(tabId)
                self.restoreFocusOwnerForSelectedTab()
            },
            selectPane: { [weak self] tabId, paneId in
                guard let self else { return }
                self.recordSelectionDrivenRefocusSuppression(tabId: tabId, paneId: paneId)
                if self.store.tabLayoutAtom.activeTabId != tabId {
                    self.selectTabAndRestoreVisibleViews(tabId)
                }
                self.revealArrangementContainingPane(tabId: tabId, paneId: paneId)
                if let tab = self.store.tabLayoutAtom.tab(tabId),
                    tab.activeMinimizedPaneIds.contains(paneId)
                {
                    self.executor.execute(.expandPane(tabId: tabId, paneId: paneId))
                }
                self.store.tabLayoutAtom.setActivePane(paneId, inTab: tabId)
                atom(\.workspaceFocusOwner).focusMainPane(paneId)
                self.managementNavigationScope = .mainRow
            },
            selectDrawerPane: { [weak self] parentPaneId, drawerPaneId in
                guard let self else { return }
                self.recordSelectionDrivenRefocusSuppression(
                    tabId: self.store.tabLayoutAtom.activeTabId,
                    paneId: drawerPaneId
                )
                if let tabId = self.store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
                    let drawerId = self.store.paneAtom.pane(parentPaneId)?.drawer?.drawerId
                {
                    self.store.tabArrangementAtom.setActiveDrawerPane(drawerPaneId, drawerId: drawerId, inTab: tabId)
                }
                atom(\.workspaceFocusOwner).focusDrawerPane(
                    parentPaneId: parentPaneId,
                    paneId: drawerPaneId
                )
                self.managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            },
            selectEmptyDrawer: { [weak self] parentPaneId in
                guard let self else { return }
                atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
                self.managementNavigationScope = .drawer(parentPaneId: parentPaneId)
                _ = self.clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
            },
            syncRuntimeFocus: { surfaceId in
                SurfaceManager.shared.syncFocus(activeSurfaceId: surfaceId)
            }
        )
    }

    private func selectTabAndRestoreVisibleViews(_ tabId: UUID) {
        store.tabLayoutAtom.setActiveTab(tabId)
        executor.restoreVisibleViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)
    }

    private func restoreFocusOwnerForSelectedTab() {
        guard let parentPaneId = activeMainPaneId() else {
            applyWorkspaceFocusOwner(.mainPane(paneId: nil))
            return
        }

        let requestedFocusOwner: WorkspaceFocusOwner =
            if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true {
                .emptyDrawer(parentPaneId: parentPaneId)
            } else {
                .mainPane(paneId: parentPaneId)
            }

        applyWorkspaceFocusOwner(
            WorkspaceFocusOwnerNormalizer.normalize(
                requested: requestedFocusOwner,
                context: currentWorkspaceFocusOwnerContext()
            )
        )
    }

    private func applyWorkspaceFocusOwner(_ owner: WorkspaceFocusOwner) {
        switch owner {
        case .mainPane(let paneId):
            atom(\.workspaceFocusOwner).focusMainPane(paneId)
            managementNavigationScope = .mainRow
        case .drawerPane(let parentPaneId, let drawerPaneId):
            atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPaneId, paneId: drawerPaneId)
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
        case .emptyDrawer(let parentPaneId):
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            _ = clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
        }
    }

    private func recordSelectionDrivenRefocusSuppression(tabId: UUID?, paneId: UUID?) {
        suppressedSelectionDrivenRefocus = (tabId, paneId)
    }

    private func shouldSkipSelectionDrivenRefocus(currentTabId: UUID?, currentPaneId: UUID?) -> Bool {
        suppressedSelectionDrivenRefocus?.tabId == currentTabId
            && suppressedSelectionDrivenRefocus?.paneId == currentPaneId
    }

    func handlePaneFocusTrigger(_ trigger: PaneFocusTrigger) {
        guard let context = makePaneFocusContext(for: trigger) else {
            Self.logger.warning(
                "Pane focus trigger dropped because context assembly failed trigger=\(String(describing: trigger), privacy: .public)"
            )
            return
        }
        let decision = PaneFocusOrchestrator.decide(trigger: trigger, context: context)
        if !paneFocusExecutor.apply(decision) {
            Self.logger.warning(
                "Pane focus apply returned false for trigger \(String(describing: trigger), privacy: .public)")
        }
    }

    func requestPaneRefocus(_ reason: PaneRefocusRequestTrigger.Reason = .explicit) {
        handlePaneFocusTrigger(.refocusRequest(PaneRefocusRequestTrigger(reason: reason)))
    }

    private func makePaneFocusContext(for trigger: PaneFocusTrigger) -> PaneFocusContext? {
        let activeTabId = store.tabLayoutAtom.activeTabId
        let activePaneId = preferredVisibleFocusPaneId()
        let targetTabId = paneFocusTargetTabId(for: trigger, activeTabId: activeTabId)
        let targetPaneId = paneFocusTargetPaneId(
            for: trigger,
            targetTabId: targetTabId,
            activePaneId: activePaneId
        )
        guard targetPaneId == nil || targetTabId != nil else {
            return nil
        }
        let targetPaneKind = PaneFocusContext.PaneKind(
            content: targetPaneId.flatMap { store.paneAtom.pane($0)?.content }
        )
        let targetMountedContent =
            targetPaneId
            .flatMap { viewRegistry.view(for: $0)?.mountedContentStateForPaneFocus }
            ?? .unmounted
        let activeDrawerParentPaneId = activeMainPaneId()

        return PaneFocusContext(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            activeDrawer: activeDrawerParentPaneId.map {
                .init(
                    parentPaneId: $0,
                    paneId: visibleActiveDrawerPaneId(for: $0),
                    isEmpty: store.paneAtom.pane($0)?.drawer?.paneIds.isEmpty == true
                )
            },
            targetPaneId: targetPaneId,
            targetTabId: targetTabId,
            targetPaneKind: targetPaneKind,
            targetPaneIsAlreadyActive: paneFocusTargetIsAlreadyActive(
                trigger: trigger,
                targetPaneId: targetPaneId,
                activePaneId: activePaneId,
                activeTabId: activeTabId
            ),
            targetMountedContent: targetMountedContent,
            managementLayer: atom(\.managementLayer).isActive
                ? .active(scope: paneFocusManagementScope)
                : .inactive,
            windowState: paneFocusWindowState(for: targetPaneId)
        )
    }

    private var paneFocusManagementScope: PaneManagementFocusScope {
        switch managementNavigationScope {
        case .mainRow:
            return .mainRow
        case .drawer(let parentPaneId):
            return .drawer(parentPaneId: parentPaneId)
        }
    }

    private func paneFocusTargetTabId(for trigger: PaneFocusTrigger, activeTabId: UUID?) -> UUID? {
        switch trigger {
        case .contentClick(let trigger):
            return store.tabLayoutAtom.tabs.first { $0.paneIds.contains(trigger.targetPaneId) }?.id
        case .tabClick(let trigger):
            return trigger.targetTabId
        case .drawer:
            return activeTabId
        case .keyboard(let trigger):
            switch trigger {
            case .moveToPane(let tabId, _, _):
                return tabId
            }
        case .mode, .refocusRequest:
            return activeTabId
        case .command(let trigger):
            switch trigger {
            case .focusPane(let tabId, _):
                return tabId
            case .selectTab(let tabId):
                return tabId
            case .paneCreated:
                return activeTabId
            }
        }
    }

    private func paneFocusTargetPaneId(
        for trigger: PaneFocusTrigger,
        targetTabId: UUID?,
        activePaneId: UUID?
    ) -> UUID? {
        switch trigger {
        case .contentClick(let trigger):
            return trigger.targetPaneId
        case .tabClick:
            return targetTabId.flatMap { store.tabLayoutAtom.tab($0) }?.activePaneId
        case .drawer(let trigger):
            switch trigger {
            case .selectPane(_, let drawerPaneId):
                return drawerPaneId
            case .toggle(let parentPaneId):
                return parentPaneId
            }
        case .keyboard(let trigger):
            switch trigger {
            case .moveToPane(_, let paneId, _):
                return paneId
            }
        case .mode:
            return activePaneId
        case .refocusRequest:
            return activePaneId
        case .command(let trigger):
            switch trigger {
            case .focusPane(_, let paneId), .paneCreated(let paneId, _):
                return paneId
            case .selectTab(let tabId):
                return store.tabLayoutAtom.tab(tabId)?.activePaneId
            }
        }
    }

    private func paneFocusTargetIsAlreadyActive(
        trigger: PaneFocusTrigger,
        targetPaneId: UUID?,
        activePaneId: UUID?,
        activeTabId: UUID?
    ) -> Bool {
        switch trigger {
        case .tabClick(let trigger):
            return activeTabId == trigger.targetTabId
        case .drawer(let trigger):
            switch trigger {
            case .selectPane(_, let drawerPaneId):
                return activeMainPaneId().flatMap { visibleActiveDrawerPaneId(for: $0) } == drawerPaneId
            case .toggle(let parentPaneId):
                return activePaneId == parentPaneId
            }
        default:
            return activePaneId == targetPaneId
        }
    }

    private func paneFocusWindowState(for paneId: UUID?) -> PaneFocusContext.WindowState {
        let window = paneId.flatMap { viewRegistry.view(for: $0)?.window } ?? view.window
        guard let window else { return .background }
        if window.isKeyWindow {
            return .key
        }
        if window.isMainWindow {
            return .focused
        }
        return .background
    }

    private func normalizedWorkspaceNavigationFocusScope() -> WorkspaceNavigationFocusScope {
        guard case .drawer(let parentPaneId) = managementNavigationScope else {
            return managementNavigationScope
        }
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let activePaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId,
            activePaneId == parentPaneId,
            let drawer = store.paneAtom.pane(parentPaneId)?.drawer,
            drawer.isExpanded
        else {
            return .mainRow
        }
        return managementNavigationScope
    }

    private func normalizedWorkspaceNavigationScopeState() -> WorkspaceFocusOwner {
        WorkspaceFocusOwnerNormalizer.normalize(
            requested: atom(\.workspaceFocusOwner).owner,
            context: currentWorkspaceFocusOwnerContext()
        )
    }

    @discardableResult
    private func clearFirstResponderToWindowContentForDrawer(parentPaneId: UUID) -> Bool {
        let window = viewRegistry.view(for: parentPaneId)?.window ?? view.window ?? NSApp.keyWindow
        guard let window, let contentView = window.contentView else { return false }
        return window.makeFirstResponder(contentView)
    }

    private func currentWorkspaceFocusOwnerContext() -> WorkspaceFocusOwnerNormalizer.Context {
        let activeMainPaneId = activeMainPaneId()
        let drawer = activeMainPaneId.flatMap { store.paneAtom.pane($0)?.drawer }
        let drawerView = activeMainPaneId.flatMap { arrangementView.drawerView(forParent: $0) }
        return .init(
            activeMainPaneId: activeMainPaneId,
            expandedDrawerParentPaneId: drawer?.isExpanded == true ? activeMainPaneId : nil,
            paneIds: drawer?.paneIds ?? [],
            activeDrawerPaneId: drawerView?.activeChildId,
            minimizedDrawerPaneIds: drawerView?.minimizedPaneIds ?? []
        )
    }

    private func syncFocusOwnerAfterDrawerMutation(parentPaneId: UUID) {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return }

        if drawer.isExpanded {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            let drawerView = arrangementView.drawerView(forParent: parentPaneId)
            if let drawerPaneId = drawerView?.activeChildId,
                drawerView?.minimizedPaneIds.contains(drawerPaneId) == false
            {
                atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPaneId, paneId: drawerPaneId)
            } else {
                atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
                _ = clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
            }
        } else {
            managementNavigationScope = .mainRow
            atom(\.workspaceFocusOwner).focusMainPane(parentPaneId)
        }
    }

    private func drawerParentByPaneId() -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard let parentPaneId = pane.parentPaneId else { return nil }
                return (pane.id, parentPaneId)
            }
        )
    }

    private func drawerLayoutByParentPaneId() -> [UUID: DrawerGridLayout] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard pane.drawer != nil, let drawerView = arrangementView.drawerView(forParent: pane.id) else {
                    return nil
                }
                return (pane.id, drawerView.layout)
            }
        )
    }

    private func visibleActiveDrawerPaneId(for parentPaneId: UUID) -> UUID? {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return nil }
        guard drawer.isExpanded else { return nil }
        guard let drawerView = arrangementView.drawerView(forParent: parentPaneId),
            let drawerPaneId = drawerView.activeChildId
        else { return nil }
        guard !drawerView.minimizedPaneIds.contains(drawerPaneId) else { return nil }
        return drawerPaneId
    }

    // MARK: - Tab Content Hosts

    private func buildTabContentHost(for tabId: UUID) -> PersistentTabHostView {
        let contentView = SingleTabContent(
            tabId: tabId,
            store: store,
            repoCache: repoCache,
            viewRegistry: viewRegistry,
            appLifecycleStore: appLifecycleStore,
            closeTransitionCoordinator: closeTransitionCoordinator,
            actionDispatcher: actionDispatcher,
            onPaneFocusTrigger: { [weak self] trigger in
                self?.handlePaneFocusTrigger(trigger)
            },
            paneInboxPresentation: paneInboxPresentation,
            onOpenPaneGitHub: { [weak self] paneId in
                self?.openGitHubWebview(for: paneId)
            },
            notificationCountForWorktree: { worktreeId in
                WorkspaceNotificationCountProjection.rollUpAlertCount(
                    worktreeId: worktreeId,
                    inboxAtom: atom(\.inboxNotification)
                )
            },
            workspaceWindowId: workspaceWindowId
        )

        return PersistentTabHostView(tabId: tabId, rootView: contentView)
    }

    private func syncTabContentHosts() {
        for paneId in store.paneAtom.panes.keys {
            viewRegistry.ensureSlot(for: paneId)
        }

        let liveTabIds = Set(store.tabLayoutAtom.tabs.map(\.id))
        guard liveTabIds != Set(tabContentHosts.keys) else { return }

        for tab in store.tabLayoutAtom.tabs where tabContentHosts[tab.id] == nil {
            let host = buildTabContentHost(for: tab.id)
            terminalContainer.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                host.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
                host.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
            ])
            tabContentHosts[tab.id] = host
        }

        for (tabId, host) in tabContentHosts where !liveTabIds.contains(tabId) {
            host.removeFromSuperview()
            tabContentHosts.removeValue(forKey: tabId)
        }
    }

    private func updateVisibleTabHost() {
        let activeTabId = store.tabLayoutAtom.activeTabId
        for (tabId, host) in tabContentHosts {
            host.isHidden = tabId != activeTabId
        }
    }

    private func activeTabHost() -> PersistentTabHostView? {
        guard let activeTabId = store.tabLayoutAtom.activeTabId else { return nil }
        return tabContentHosts[activeTabId]
    }

    private func handleTerminalContainerBoundsChanged(reason: StaticString) {
        let terminalContainerBounds = terminalContainer?.bounds ?? .zero
        RestoreTrace.log(
            "PaneTabViewController terminalContainerBoundsChanged reason=\(reason) bounds=\(NSStringFromRect(terminalContainerBounds))"
        )
        RestoreTrace.log(geometryHierarchySnapshot(reason: reason))
        scheduleVisibleViewRestoreAfterLayout(reason: reason)
    }

    private func scheduleVisibleViewRestoreAfterLayout(reason: StaticString) {
        pendingVisibleViewRestoreTask?.cancel()
        pendingVisibleViewRestoreTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.executor.restoreVisibleViewsForActiveTabIfNeeded()
            self.syncVisibleTerminalGeometry(reason: reason)
            self.pendingVisibleViewRestoreTask = nil
        }
    }

    func syncVisibleTerminalGeometry(reason: StaticString) {
        let traceClock = performanceTraceRecorder?.isEnabled == true ? ContinuousClock() : nil
        let syncStart = traceClock?.now
        let visibleTerminalViews = visibleTerminalPaneIdsForActiveTab().compactMap {
            viewRegistry.terminalView(for: $0)
        }.filter { terminalView in
            terminalView.window != nil && !terminalView.isHidden
        }
        guard !visibleTerminalViews.isEmpty else { return }
        RestoreTrace.log(
            "PaneTabViewController.syncVisibleTerminalGeometry reason=\(reason) count=\(visibleTerminalViews.count)"
        )
        for terminalView in visibleTerminalViews {
            terminalView.forceGeometrySync(reason: reason)
        }
        guard let traceClock, let syncStart else { return }
        performanceTraceRecorder?.recordDuration(
            .terminalGeometrySync,
            duration: syncStart.duration(to: traceClock.now),
            attributes: [
                "agentstudio.performance.terminal.geometry.reason": .string("\(reason)"),
                "agentstudio.performance.terminal.geometry.visible_terminal.count": .double(
                    Double(visibleTerminalViews.count)),
            ]
        )
    }

    func visibleTerminalPaneIdsForActiveTab() -> [UUID] {
        guard let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId)
        else { return [] }

        var seenPaneIds: Set<UUID> = []
        var paneIds: [UUID] = []
        func append(_ candidatePaneId: UUID) {
            guard seenPaneIds.insert(candidatePaneId).inserted else { return }
            paneIds.append(candidatePaneId)
        }

        for paneId in tab.activeArrangement.layout.paneIds {
            append(paneId)
            guard let drawer = store.paneAtom.pane(paneId)?.drawer, drawer.isExpanded else { continue }
            guard let drawerView = tab.activeArrangement.drawerViews[drawer.drawerId] else { continue }
            for drawerPaneId in drawerView.layout.paneIds where !drawerView.minimizedPaneIds.contains(drawerPaneId) {
                append(drawerPaneId)
            }
        }

        return paneIds
    }

    func geometryHierarchySnapshot(reason: StaticString) -> String {
        let rootFrame = isViewLoaded ? NSStringFromRect(view.frame) : "nil"
        let rootBounds = isViewLoaded ? NSStringFromRect(view.bounds) : "nil"
        let terminalFrame = terminalContainer.map { NSStringFromRect($0.frame) } ?? "nil"
        let terminalBounds = terminalContainer.map { NSStringFromRect($0.bounds) } ?? "nil"
        let hostingFrame = activeTabHost().map { NSStringFromRect($0.frame) } ?? "nil"
        let hostingBounds = activeTabHost().map { NSStringFromRect($0.bounds) } ?? "nil"
        let tabBarFrame = tabBarHostingView.map { NSStringFromRect($0.frame) } ?? "nil"
        return
            "PaneTabViewController.geometry reason=\(reason) viewFrame=\(rootFrame) viewBounds=\(rootBounds) terminalFrame=\(terminalFrame) terminalBounds=\(terminalBounds) hostingFrame=\(hostingFrame) hostingBounds=\(hostingBounds) tabBarFrame=\(tabBarFrame)"
    }

    /// Evaluate whether a drop is acceptable at the given pane and zone.
    private func evaluateDropAcceptance(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) -> Bool {
        guard shouldHandleSplitDragPayload(payload) else {
            return false
        }
        let snapshot = dragDropSnapshot()
        return Self.splitDropCommitPlan(
            payload: payload,
            destination: SplitDropCommitDestination(
                paneId: destPaneId,
                drawerParentPaneId: store.paneAtom.pane(destPaneId)?.parentPaneId
            ),
            zone: zone,
            sizingMode: sizingMode,
            activeTabId: store.tabLayoutAtom.activeTabId,
            state: snapshot
        ) != nil
    }

    /// Handle a completed drop on a split pane.
    private func handleSplitDrop(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) {
        guard shouldHandleSplitDragPayload(payload) else {
            return
        }
        let snapshot = dragDropSnapshot()
        guard
            let plan = Self.splitDropCommitPlan(
                payload: payload,
                destination: SplitDropCommitDestination(
                    paneId: destPaneId,
                    drawerParentPaneId: store.paneAtom.pane(destPaneId)?.parentPaneId
                ),
                zone: zone,
                sizingMode: sizingMode,
                activeTabId: store.tabLayoutAtom.activeTabId,
                state: snapshot
            )
        else {
            return
        }
        executeDropCommitPlan(plan)
    }

    private func dragDropSnapshot() -> ActionStateSnapshot {
        WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId(),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        )
    }

    private func executeDropCommitPlan(_ plan: DropCommitPlan) {
        switch plan {
        case .paneAction(let action):
            dispatchAction(action)
        case .moveTab(let tabId, let toIndex):
            dispatchAction(.reorderTab(tabId: tabId, newIndex: toIndex))
        case .extractPaneToTabThenMove(let paneId, let sourceTabId, let toIndex):
            let tabCountBefore = store.tabLayoutAtom.tabs.count
            dispatchAction(.extractPaneToTab(tabId: sourceTabId, paneId: paneId))
            guard
                store.tabLayoutAtom.tabs.count == tabCountBefore + 1,
                let extractedTabId = store.tabLayoutAtom.activeTabId
            else {
                return
            }
            dispatchAction(.reorderTab(tabId: extractedTabId, newIndex: toIndex))
        }
    }

    nonisolated static func splitDropCommitPlan(
        payload: SplitDropPayload,
        destination: SplitDropCommitDestination,
        zone: DropZoneSide,
        sizingMode: DropSizingMode,
        activeTabId: UUID?,
        state: ActionStateSnapshot
    ) -> DropCommitPlan? {
        guard let activeTabId else {
            return nil
        }
        let paneDropDestination = PaneDropDestination.split(
            targetPaneId: destination.paneId,
            targetTabId: activeTabId,
            direction: splitDirection(for: zone),
            sizingMode: sizingMode,
            targetDrawerParentPaneId: destination.drawerParentPaneId
        )
        let decision = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: paneDropDestination,
            state: state
        )
        if case .eligible(let plan) = decision {
            return plan
        }
        return nil
    }

    private func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool {
        switch payload.kind {
        case .existingPane(let sourcePaneId, _):
            guard let sourcePane = store.paneAtom.pane(sourcePaneId) else { return false }
            return sourcePane.parentPaneId == nil
        case .newTerminal:
            return true
        case .existingTab:
            return false
        }
    }

    // MARK: - Empty State

    private var emptyStateModel: WorkspaceEmptyStateModel {
        WorkspaceLauncherProjector.project(
            store: store
        )
    }

    private func createEmptyStateView() -> NSHostingView<WorkspaceEmptyStateView> {
        PaneTabEmptyStateViewFactory.make(
            model: emptyStateModel,

            onWatchFolder: { [weak self] in self?.watchFolderAction() },
            onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
            onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
        )
    }

    @objc private func watchFolderAction() {
        AppCommandDispatcher.shared.dispatch(.watchFolder)
    }

    private func updateEmptyState() {
        let hasTabs = !store.tabLayoutAtom.tabs.isEmpty
        tabBarHostingView.isHidden = !hasTabs
        terminalContainer.isHidden = !hasTabs
        emptyStateView?.isHidden = hasTabs
    }

    private func rebuildEmptyStateView() {
        let currentModel = emptyStateModel
        guard currentModel != lastEmptyStateModel else { return }
        emptyStateView?.rootView = WorkspaceEmptyStateView(
            model: currentModel,

            onWatchFolder: { [weak self] in self?.watchFolderAction() },
            onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
            onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
        )
        lastEmptyStateModel = currentModel
    }

    private func openRecentTarget(_ target: RecentWorkspaceTarget) {
        let fileManager = FileManager.default
        if let worktreeId = target.worktreeId {
            guard store.repositoryTopologyAtom.worktree(worktreeId) != nil else {
                Self.logger.warning(
                    "Recent target removed because worktree is missing: \(target.id, privacy: .public)")
                repoCache.removeRecentTarget(target.id)
                return
            }
            guard store.repositoryTopologyAtom.repo(containing: worktreeId) != nil else {
                Self.logger.warning(
                    "Recent target removed because repo is missing for worktreeId=\(worktreeId.uuidString, privacy: .public)"
                )
                repoCache.removeRecentTarget(target.id)
                return
            }
            guard fileManager.fileExists(atPath: target.path.path) else {
                Self.logger.warning(
                    "Recent target removed because path is missing: \(target.path.path, privacy: .public)")
                repoCache.removeRecentTarget(target.id)
                return
            }
            dispatchAction(
                .openNewTerminalInTab(
                    worktreeId: worktreeId,
                    launchDirectory: target.path,
                    title: target.displayTitle
                )
            )
            return
        }

        guard fileManager.fileExists(atPath: target.path.path) else {
            Self.logger.warning(
                "Recent target removed because path is missing: \(target.path.path, privacy: .public)")
            repoCache.removeRecentTarget(target.id)
            return
        }

        dispatchAction(.openFloatingTerminal(launchDirectory: target.path, title: target.displayTitle))
    }

    private func openAllRecentTargets() {
        for target in emptyStateModel.recentTargets {
            openRecentTarget(target)
        }
    }

    private func openGitHubWebview() {
        executor.openWebview(url: Self.genericGitHubURL)
    }

    private func openGitHubWebview(for paneId: UUID) {
        let url = GitHubWebviewLaunchResolver.url(
            for: paneId,
            store: store,
            repoCache: repoCache
        )
        guard let targetTabId = store.tabLayoutAtom.activeTabId else {
            executor.openWebview(url: url)
            return
        }
        _ = executor.openContextualWebviewInPane(
            sourcePaneId: paneId,
            targetTabId: targetTabId,
            url: url
        )
    }

    private func activeMainPaneId() -> UUID? {
        store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0) }?
            .activePaneId
    }

    func handleAppOwnedKeyEvent(
        _ event: NSEvent,
        allowsModifiedEmptyDrawerShortcutWithTextFocus: Bool = false
    ) -> Bool {
        guard let trigger = ShortcutDecoder.decode(event: event) else {
            return false
        }

        if shouldConsumeSuppressedTerminalHostTrigger(trigger) { return true }

        let globalShortcut = ShortcutDecoder.shortcut(for: trigger, in: .global)

        let keyboardContext = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycleStore,
            managementLayer: atom(\.managementLayer),
            uiState: atom(\.workspaceSidebarState),
            commandBarSurface: atom(\.commandBarSurface),
            transientKeyboardSurface: atom(\.transientKeyboardSurface),
            workspaceWindowId: workspaceWindowId
        )

        if let shortcut = globalShortcut,
            AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut)
        {
            guard
                AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                    shortcut,
                    context: keyboardContext
                ),
                AppCommandDispatcher.shared.canDispatch(shortcut.command)
            else {
                return false
            }
            AppCommandDispatcher.shared.dispatch(shortcut.command)
            return true
        }

        if let handled = handleTerminalRuntimeShortcut(trigger, context: keyboardContext) {
            return handled
        }

        if let shortcut = globalShortcut {
            let shouldDispatchGlobalShortcut = AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                shortcut,
                context: keyboardContext
            )
            guard shouldDispatchGlobalShortcut || shortcut.requiresPaneTargetFallback else {
                return false
            }
            guard
                shouldDispatchGlobalShortcut
                    || AppShortcutDispatchPolicy.shouldRouteAppOwnedKeyEvent(context: keyboardContext)
            else {
                return false
            }
            if AppCommandDispatcher.shared.canDispatch(shortcut.command) {
                AppCommandDispatcher.shared.dispatch(shortcut.command)
                return true
            }
            if AppShortcutDispatchPolicy.shouldConsumeUnavailableGlobalShortcut(
                shortcut,
                context: keyboardContext
            ) {
                // Global shortcuts only consume unavailable commands when
                // the active surface explicitly reserves that chord.
                return true
            }
            guard shortcut.requiresPaneTargetFallback else {
                return false
            }
            // Empty-drawer creation needs a pane target, so it falls
            // through to the targeted app-owned path below.
        }

        guard AppShortcutDispatchPolicy.shouldRouteAppOwnedKeyEvent(context: keyboardContext) else {
            return false
        }

        // Raw-character triggers always require neutral focus, even
        // when modifier-keyed shortcuts are allowed through text focus.
        if let parentPaneId = firstDrawerPaneParentId(
            for: trigger,
            event: event,
            requiresNeutralFocus: trigger.modifiers.isEmpty || !allowsModifiedEmptyDrawerShortcutWithTextFocus
        ) {
            guard
                AppCommandDispatcher.shared.canDispatch(
                    .addDrawerPane,
                    target: parentPaneId,
                    targetType: .pane
                )
            else {
                return false
            }
            AppCommandDispatcher.shared.dispatch(.addDrawerPane, target: parentPaneId, targetType: .pane)
            return true
        }

        let keyboardOwner = keyboardContext.stableOwner

        if shouldHandleScopeAwarePaneTrigger(event: event, keyboardOwner: keyboardOwner),
            isScopeAwarePaneMovementTrigger(trigger)
        {
            // Consume every reserved option-I/J/K/L chord in pane scope,
            // even when there is no concrete move, so terminal content
            // never receives app-owned navigation keystrokes.
            if let command = scopeAwarePaneCommand(for: trigger), canExecute(command) {
                execute(command)
            }
            return true
        }

        return false
    }

    private func shouldConsumeSuppressedTerminalHostTrigger(_ trigger: ShortcutTrigger) -> Bool {
        AppShortcutDispatchPolicy.shouldSuppressTerminalHostTrigger(trigger)
    }

    private func handleTerminalRuntimeShortcut(
        _ trigger: ShortcutTrigger,
        context keyboardContext: KeyboardRoutingContext
    ) -> Bool? {
        guard let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned),
            AppShortcutDispatchPolicy.isTerminalRuntimeCommand(shortcut.command)
        else {
            return nil
        }

        // Terminal runtime shortcuts are app-owned reservations. When AppKit
        // sends them through the pane controller instead of Ghostty, consume
        // even rejected chords so terminal/default responders never see them.
        guard
            AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(
                shortcut,
                context: keyboardContext
            ),
            AppCommandDispatcher.shared.canDispatch(shortcut.command)
        else {
            return true
        }
        AppCommandDispatcher.shared.dispatch(shortcut.command)
        return true
    }

    private func scopeAwarePaneCommand(for trigger: ShortcutTrigger) -> AppCommand? {
        let scope = normalizedWorkspaceNavigationScopeState()
        switch trigger {
        case .init(key: .character(.i), modifiers: [.option]):
            return if case .drawerPane = scope { .focusDrawerPaneUp } else { nil }
        case .init(key: .character(.j), modifiers: [.option]):
            switch scope {
            case .mainPane:
                return .focusPaneLeft
            case .emptyDrawer:
                return nil
            case .drawerPane:
                return .focusDrawerPaneLeft
            }
        case .init(key: .character(.k), modifiers: [.option]):
            switch scope {
            case .mainPane:
                return nil
            case .emptyDrawer:
                return nil
            case .drawerPane:
                return .focusDrawerPaneDown
            }
        case .init(key: .character(.l), modifiers: [.option]):
            switch scope {
            case .mainPane:
                return .focusPaneRight
            case .emptyDrawer:
                return nil
            case .drawerPane:
                return .focusDrawerPaneRight
            }
        default:
            return nil
        }
    }

    private func isScopeAwarePaneMovementTrigger(_ trigger: ShortcutTrigger) -> Bool {
        switch trigger {
        case .init(key: .character(.i), modifiers: [.option]),
            .init(key: .character(.j), modifiers: [.option]),
            .init(key: .character(.k), modifiers: [.option]),
            .init(key: .character(.l), modifiers: [.option]):
            return true
        default:
            return false
        }
    }

    private func shouldHandleScopeAwarePaneTrigger(
        event: NSEvent,
        keyboardOwner: KeyboardOwner
    ) -> Bool {
        guard keyboardOwner == .mainWindowChain else { return false }
        return !rawCharacterHasTextResponder(for: event)
    }

    private func firstDrawerPaneParentId(
        for trigger: ShortcutTrigger,
        event: NSEvent,
        requiresNeutralFocus: Bool = true
    ) -> UUID? {
        // Routing goes through the command-spec system: decode the
        // event once, then ask whether it dispatches `.addDrawerPane`
        // in the `.emptyDrawer` context. The raw-character "P"
        // alternate is empty-drawer only; cmd-shift-D reaches this
        // path when the drawer is open and empty.
        guard
            atom(\.managementLayer).isActive == false,
            ShortcutDecoder.shortcut(for: trigger, in: .emptyDrawer) == .addDrawerPane
        else {
            return nil
        }
        // Raw-character alternates must never be intercepted while
        // text input owns focus. Modified shortcuts may fire from
        // performKeyEquivalent even when a text field is focused.
        if requiresNeutralFocus, rawCharacterHasTextResponder(for: event) {
            return nil
        }

        guard
            case .emptyDrawer(let parentPaneId) = normalizedWorkspaceNavigationScopeState(),
            store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.isEmpty == true
        else {
            Self.logger.warning(
                "empty drawer shortcut ignored because navigation scope and pane drawer state disagree")
            return nil
        }
        return parentPaneId
    }

    private func rawCharacterHasTextResponder(for event: NSEvent) -> Bool {
        let eventWindow = event.window ?? windowForRawCharacterEvent(event)
        let responders = [
            eventWindow?.firstResponder,
            view.window?.firstResponder,
        ]
        return responders.contains { !Self.isNeutralResponderForRawCharacter($0) }
    }

    private func windowForRawCharacterEvent(_ event: NSEvent) -> NSWindow? {
        guard event.windowNumber > 0 else { return nil }

        let application = NSApplication.shared
        return application.window(withWindowNumber: event.windowNumber)
            ?? application.windows.first { $0.windowNumber == event.windowNumber }
    }

    /// A responder is "neutral" for raw character keystrokes when it
    /// will NOT consume the keystroke as text input. NSText (and its
    /// subclasses NSTextView / NSTextField field editor) absorb typed
    /// characters; everything else is considered neutral.
    static func isNeutralResponderForRawCharacter(_ responder: NSResponder?) -> Bool {
        guard let responder else { return true }
        return !(responder is NSText)
    }

    private func managementLayerParentPaneId() -> UUID? {
        switch normalizedWorkspaceNavigationFocusScope() {
        case .mainRow:
            return activeMainPaneId()
        case .drawer(let parentPaneId):
            return parentPaneId
        }
    }

    private func initialWorkspaceNavigationFocusScope() -> WorkspaceNavigationFocusScope {
        if let parentPaneId = activeMainPaneId(),
            store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true
        {
            return .drawer(parentPaneId: parentPaneId)
        }

        return .mainRow
    }

    private func managementLayerCreationScope() -> WorkspaceNavigationFocusScope {
        // Intentional: creation follows the normalized navigation scope first,
        // then upgrades main-row scope to an already-expanded drawer so
        // management-layer create commands act in visible drawer context.
        let navigationScope = normalizedWorkspaceNavigationFocusScope()

        if case .drawer = navigationScope {
            return navigationScope
        }

        return initialWorkspaceNavigationFocusScope()
    }

    private func visibleDrawerPaneIds(for parentPaneId: UUID) -> [UUID] {
        arrangementView.drawerVisiblePaneIds(forParent: parentPaneId)
    }

    private func focusSiblingDrawerPane(in parentPaneId: UUID, delta: Int) {
        let visiblePaneIds = visibleDrawerPaneIds(for: parentPaneId)
        guard !visiblePaneIds.isEmpty else { return }

        let currentPaneId = visibleActiveDrawerPaneId(for: parentPaneId) ?? visiblePaneIds.first!
        guard let currentIndex = visiblePaneIds.firstIndex(of: currentPaneId) else { return }

        let nextIndex = (currentIndex + delta + visiblePaneIds.count) % visiblePaneIds.count
        let nextPaneId = visiblePaneIds[nextIndex]
        managementNavigationScope = .drawer(parentPaneId: parentPaneId)
        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: nextPaneId)))
    }

    private func handleManagementMoveLeft() {
        switch normalizedWorkspaceNavigationFocusScope() {
        case .mainRow:
            execute(.focusPaneLeft)
        case .drawer(let parentPaneId):
            focusSiblingDrawerPane(in: parentPaneId, delta: -1)
        }
    }

    private func handleManagementMoveRight() {
        switch normalizedWorkspaceNavigationFocusScope() {
        case .mainRow:
            execute(.focusPaneRight)
        case .drawer(let parentPaneId):
            focusSiblingDrawerPane(in: parentPaneId, delta: 1)
        }
    }

    private func handleManagementMoveDown() {
        guard case .drawer(let parentPaneId) = normalizedWorkspaceNavigationFocusScope() else {
            return
        }
        managementNavigationScope = .drawer(parentPaneId: parentPaneId)
        if let drawerPaneId = visibleActiveDrawerPaneId(for: parentPaneId) {
            handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
        }
    }

    private func handleManagementOpenDrawer() {
        guard let parentPaneId = activeMainPaneId() else {
            Self.logger.warning("management open drawer ignored because active main pane is unavailable")
            return
        }
        let drawerIsExpanded = store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true
        if !drawerIsExpanded {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
            handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: parentPaneId)))
        }

        managementNavigationScope = .drawer(parentPaneId: parentPaneId)

        if let drawerPaneId = visibleActiveDrawerPaneId(for: parentPaneId) {
            handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
        }
    }

    private func handleManagementMoveUp() {
        guard case .drawer(let parentPaneId) = normalizedWorkspaceNavigationFocusScope() else { return }
        if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
            handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: parentPaneId)))
        }
        managementNavigationScope = .mainRow
    }

    private func enterDrawerFromActivePane() {
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let parentPaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId
        else { return }

        if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == false {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
        }

        if let drawerPaneId = arrangementView.drawerView(forParent: parentPaneId)?.activeChildId {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
        } else {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
            _ = clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
        }
    }

    private func moveDrawerFocus(_ command: AppCommand) {
        guard let target = drawerFocusNeighbor(for: command) else { return }
        handlePaneFocusTrigger(
            .drawer(.selectPane(parentPaneId: target.parentPaneId, drawerPaneId: target.drawerPaneId)))
    }

    private func drawerFocusNeighbor(for command: AppCommand) -> (parentPaneId: UUID, drawerPaneId: UUID)? {
        guard case .drawerPane(let parentPaneId, let drawerPaneId) = normalizedWorkspaceNavigationScopeState() else {
            return nil
        }

        let direction: FocusDirection
        switch command {
        case .focusDrawerPaneUp:
            direction = .up
        case .focusDrawerPaneLeft:
            direction = .left
        case .focusDrawerPaneDown:
            direction = .down
        case .focusDrawerPaneRight:
            direction = .right
        default:
            return nil
        }

        guard
            let drawerView = arrangementView.drawerView(forParent: parentPaneId),
            let targetPaneId = drawerView.layout.neighbor(of: drawerPaneId, direction: direction)
        else { return nil }

        return (parentPaneId, targetPaneId)
    }

    private func focusDrawerPaneOrdinal(command: AppCommand) -> Bool {
        guard let target = resolveDrawerPaneOrdinalTarget(for: command) else { return false }
        if target.drawerView.minimizedPaneIds.contains(target.drawerPaneId) {
            dispatchAction(.expandDrawerPane(parentPaneId: target.parentPaneId, drawerPaneId: target.drawerPaneId))
        }
        focusTargetedDrawerPane(parentPaneId: target.parentPaneId, drawerPaneId: target.drawerPaneId)
        return true
    }

    private func resolveDrawerPaneOrdinalTarget(for command: AppCommand) -> (
        parentPaneId: UUID,
        drawerView: DrawerView,
        drawerPaneId: UUID
    )? {
        guard
            let ordinal = drawerPaneOrdinal(for: command),
            let parentPaneId = activeMainPaneId(),
            let drawerView = arrangementView.drawerView(forParent: parentPaneId),
            let drawerPaneId = PaneOrdinalMap(orderedPaneIds: drawerView.layout.paneIds).paneId(forOrdinal: ordinal)
        else {
            return nil
        }
        return (parentPaneId, drawerView, drawerPaneId)
    }

    private func drawerPaneOrdinal(for command: AppCommand) -> Int? {
        AppCommand.focusDrawerPaneCommands.firstIndex(of: command).map { $0 + 1 }
    }

    private func handleManagementCreateTerminal() {
        switch managementLayerCreationScope() {
        case .mainRow:
            managementNavigationScope = .mainRow
            execute(.newTerminalInTab)
        case .drawer(let parentPaneId):
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            dispatchAction(.addDrawerPane(parentPaneId: parentPaneId))
        }
    }

    private func handleManagementCreateBrowser() {
        switch managementLayerCreationScope() {
        case .mainRow:
            managementNavigationScope = .mainRow
            guard let paneId = activeMainPaneId() else {
                Self.logger.warning("management create browser ignored because active main pane is unavailable")
                return
            }
            openGitHubWebview(for: paneId)
        case .drawer(let parentPaneId):
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            let url = GitHubWebviewLaunchResolver.url(
                for: parentPaneId,
                store: store,
                repoCache: repoCache
            )
            _ = executor.openContextualWebviewInDrawer(
                parentPaneId: parentPaneId,
                url: url
            )
        }
    }

    private func canExecuteManagementCommand(_ command: AppCommand) -> Bool {
        let navigationScope = normalizedWorkspaceNavigationFocusScope()

        switch command {
        case .managementLayerFocusLeft:
            switch navigationScope {
            case .mainRow:
                return canExecute(.focusPaneLeft)
            case .drawer(let parentPaneId):
                return visibleDrawerPaneIds(for: parentPaneId).count > 1
            }
        case .managementLayerFocusRight:
            switch navigationScope {
            case .mainRow:
                return canExecute(.focusPaneRight)
            case .drawer(let parentPaneId):
                return visibleDrawerPaneIds(for: parentPaneId).count > 1
            }
        case .managementLayerEnterDrawer, .managementLayerOpenDrawer:
            return activeMainPaneId() != nil
        case .managementLayerExitDrawer, .managementLayerExit:
            if case .drawer = navigationScope {
                return true
            }
            return command == .managementLayerExit
        case .managementLayerCreateTerminal:
            switch managementLayerCreationScope() {
            case .mainRow:
                return canExecute(.newTerminalInTab)
            case .drawer(let parentPaneId):
                return store.paneAtom.pane(parentPaneId)?.drawer != nil
            }
        case .managementLayerCreateBrowser:
            return managementLayerCreationScope() != .mainRow || activeMainPaneId() != nil
        default:
            return false
        }
    }

    private func canExecuteContextualCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .addDrawerPane, .toggleDrawer:
            return activeMainPaneId() != nil
        case .closeDrawerPane:
            guard let parentPaneId = activeMainPaneId() else { return false }
            return visibleActiveDrawerPaneId(for: parentPaneId) != nil
        default:
            return false
        }
    }

    // MARK: - New Tab

    /// Create a new empty tab rooted at the first watched folder, or the user's
    /// home directory when no watched folder exists yet.
    private func addNewTab() {
        let launchDirectory =
            store.repositoryTopologyAtom.watchedPaths.first?.path
            ?? FileManager.default.homeDirectoryForCurrentUser
        dispatchAction(.openFloatingTerminal(launchDirectory: launchDirectory, title: nil))
    }

    // MARK: - Terminal Management

    func openTerminal(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openWorktree(worktreeId: worktree.id))
    }

    func openNewTerminal(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openNewTerminalInTab(worktreeId: worktree.id, launchDirectory: nil, title: nil))
    }

    func openWorktreeInPane(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openWorktreeInPane(worktreeId: worktree.id))
    }

    func closeTerminal(for worktreeId: UUID) {
        // Find the tab containing this worktree
        guard
            let tab = store.tabLayoutAtom.tabs.first(where: { tab in
                tab.allPaneIds.contains { id in
                    store.paneAtom.pane(id)?.worktreeId == worktreeId
                }
            })
        else { return }

        guard
            let matchedPaneId = tab.allPaneIds.first(where: { id in
                store.paneAtom.pane(id)?.worktreeId == worktreeId
            })
        else { return }
        dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
    }

    func closeActiveTab() {
        guard let activeId = store.tabLayoutAtom.activeTabId else { return }
        dispatchAction(.closeTab(tabId: activeId))
    }

    func selectTab(at index: Int) {
        let tabs = store.tabLayoutAtom.tabs
        guard index >= 0, index < tabs.count else { return }
        handlePaneFocusTrigger(.command(.selectTab(tabs[index].id)))
    }

    // MARK: - Validated Action Pipeline

    /// Central entry point: validates a WorkspaceActionCommand and executes it if valid.
    /// All input sources (keyboard, menu, drag-drop, commands) converge here.
    private func dispatchAction(_ action: WorkspaceActionCommand) {
        let snapshot = WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId(),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        )

        switch WorkspaceCommandValidator.validate(action, state: snapshot) {
        case .success:
            executor.execute(action)
            syncFocusOwnerAfterValidatedAction(action)
        case .failure(let error):
            ghosttyLogger.warning("Action rejected: \(error)")
        }
    }

    private func syncFocusOwnerAfterValidatedAction(_ action: WorkspaceActionCommand) {
        switch action {
        case .addDrawerPane(let parentPaneId),
            .removeDrawerPane(let parentPaneId, _),
            .toggleDrawer(let parentPaneId),
            .setActiveDrawerPane(let parentPaneId, _),
            .insertDrawerPane(let parentPaneId, _, _, _),
            .moveDrawerPane(let parentPaneId, _, _, _),
            .minimizeDrawerPane(let parentPaneId, _),
            .expandDrawerPane(let parentPaneId, _):
            syncFocusOwnerAfterDrawerMutation(parentPaneId: parentPaneId)
        case .detachDrawerPane:
            managementNavigationScope = .mainRow
            atom(\.workspaceFocusOwner).focusMainPane(activeMainPaneId())
        default:
            break
        }
    }

    // MARK: - Tab Commands

    func executeTabContextMenuCommand(_ command: AppCommand, tabId: UUID) {
        handleTabCommand(command, tabId: tabId)
    }

    /// Route tab context menu commands through the validated pipeline.
    private func handleTabCommand(_ command: AppCommand, tabId: UUID) {
        if command == .renameTab {
            guard store.tabLayoutAtom.tab(tabId) != nil else {
                Self.logger.warning("renameTab context menu command ignored: tab \(tabId) not found")
                return
            }
            requestTabRenamePresentation(for: tabId)
            return
        }

        let action: WorkspaceActionCommand?

        switch command {
        case .closeTab:
            action = .closeTab(tabId: tabId)
        case .breakUpTab:
            action = .breakUpTab(tabId: tabId)
        case .equalizePanes:
            action = .equalizePanes(tabId: tabId)
        case .splitRight, .splitLeft:
            // Resolve split direction using the target tab's active pane
            guard let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { return }
            let direction: SplitNewDirection = {
                switch command {
                case .splitRight: return .right
                case .splitLeft: return .left
                default: return .right
                }
            }()
            action = .insertPane(
                source: .newTerminal,
                targetTabId: tabId,
                targetPaneId: paneId,
                direction: direction,
                sizingMode: .halveTarget
            )
        case .newFloatingTerminal:
            action = nil
        case .switchArrangement, .deleteArrangement, .renameArrangement:
            // Arrangement management now handled through the arrangement panel popover
            // in the tab bar. Context menu entries still work as no-ops here.
            action = nil
        case .saveArrangement:
            // Direct action — save current layout as a new arrangement
            guard let tab = store.tabLayoutAtom.tab(tabId) else { return }
            let name = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
            action = .createArrangement(tabId: tabId, name: name)
        default:
            action = nil
        }

        if let action {
            dispatchAction(action)
        }
    }

    private func requestTabRenamePresentation(for tabId: UUID) {
        guard store.tabLayoutAtom.tab(tabId) != nil else {
            Self.logger.warning("renameTab presentation ignored: tab \(tabId) not found")
            return
        }
        if store.tabLayoutAtom.activeTabId != tabId {
            dispatchAction(.selectTab(tabId: tabId))
        }

        tabRenamePopoverState.dismiss()

        // Context menus and command-bar dispatch both run while another transient
        // AppKit surface is unwinding. Move the editor presentation to default
        // run-loop mode and let the controller own the AppKit popover anchor.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.presentTabRenamePopover(for: tabId)
            }
        }
    }

    private func presentTabRenamePopover(for tabId: UUID) {
        guard let tab = store.tabLayoutAtom.tab(tabId) else {
            Self.logger.warning("renameTab presentation ignored after defer: tab \(tabId) not found")
            return
        }

        closeTabRenamePopover(updateState: false)
        tabRenamePopoverState.present(for: tabId)

        guard isViewLoaded, let tabBarHostingView, tabBarHostingView.window != nil else {
            return
        }

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: TabRenamePopover(
                currentTitle: tabBarAdapter.tabs.first(where: { $0.id == tabId })?.displayTitle ?? tab.name,
                onCommit: { [weak self] name in
                    guard let self else { return }
                    self.dispatchAction(.renameTab(tabId: tabId, name: name))
                    self.closeTabRenamePopover()
                },
                onCancel: { [weak self] in
                    self?.closeTabRenamePopover()
                }
            )
        )
        tabRenamePopover = popover
        if let workspaceWindowId = workspaceWindowId ?? windowLifecycleStore.focusedWindowId
            ?? windowLifecycleStore.keyWindowId
        {
            tabRenameTransientSurfaceToken = atom(\.transientKeyboardSurface).present(
                .tabRename(tabId: tabId),
                workspaceWindowId: workspaceWindowId
            )
        }

        let anchorRect = tabBarHostingView.tabFrameInView(for: tabId) ?? tabBarHostingView.bounds
        popover.show(relativeTo: anchorRect, of: tabBarHostingView, preferredEdge: .minY)
    }

    private func closeTabRenamePopover(updateState: Bool = true) {
        dismissTabRenameTransientSurface()
        let popover = tabRenamePopover
        tabRenamePopover = nil
        popover?.delegate = nil
        popover?.close()
        if updateState {
            tabRenamePopoverState.dismiss()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover === paneNotePopover {
            paneNotePopover = nil
            return
        }

        guard notification.object as? NSPopover === tabRenamePopover else { return }
        dismissTabRenameTransientSurface()
        tabRenamePopover = nil
        tabRenamePopoverState.dismiss()
    }

    private func dismissTabRenameTransientSurface() {
        guard let tabRenameTransientSurfaceToken else { return }
        atom(\.transientKeyboardSurface).dismiss(tabRenameTransientSurfaceToken)
        self.tabRenameTransientSurfaceToken = nil
    }

    // MARK: - Tab Reordering

    private func handleTabReorder(fromId: UUID, toIndex: Int) {
        dispatchAction(.reorderTab(tabId: fromId, newIndex: toIndex))
    }

    // MARK: - Drag Payload

    private func createDragPayload(for tabId: UUID) -> TabDragPayload? {
        guard store.tabLayoutAtom.tab(tabId) != nil else { return nil }
        return TabDragPayload(tabId: tabId)
    }

    // MARK: - Process Termination

    func handleTerminalProcessTerminated(paneId: UUID) {
        if closeTransitionCoordinator.closingPaneIds.contains(paneId) {
            return
        }
        if let pane = store.paneAtom.pane(paneId) {
            AppEventBus.post(.terminalProcessTerminationHandled(paneId: paneId))
            if let parentPaneId = pane.parentPaneId,
                let parentTab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)
            {
                dispatchAction(.closePane(tabId: parentTab.id, paneId: paneId))
                return
            }

            if let tab = store.tabLayoutAtom.tabContaining(paneId: paneId) {
                dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
                return
            }

            RestoreTrace.log(
                "PaneTabViewController.handleTerminalProcessTerminated deferredNoop pane=\(paneId) reason=orphanedPane"
            )
            return
        }

        RestoreTrace.log(
            "PaneTabViewController.handleTerminalProcessTerminated deferredNoop pane=\(paneId) reason=notInAnyTab"
        )
    }

    private func handleExtractPaneRequested(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        // Single-pane tabs cannot extract; treat tab-bar pane drag as tab reorder
        // so "single pane move ability" still works.
        if let sourceTab = store.tabLayoutAtom.tab(tabId),
            sourceTab.activePaneIds.count == 1
        {
            if let targetTabIndex {
                dispatchAction(.reorderTab(tabId: tabId, newIndex: targetTabIndex))
            }
            return
        }

        let tabCountBefore = store.tabLayoutAtom.tabs.count
        dispatchAction(.extractPaneToTab(tabId: tabId, paneId: paneId))

        // For tab-bar drops, place the newly extracted tab at the drop insertion index.
        guard let targetTabIndex,
            store.tabLayoutAtom.tabs.count == tabCountBefore + 1,
            let extractedTabId = store.tabLayoutAtom.activeTabId
        else {
            return
        }

        dispatchAction(.reorderTab(tabId: extractedTabId, newIndex: targetTabIndex))
    }

    private func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        guard
            let action = makeMovePaneToTabAction(
                sourcePaneId: sourcePaneId,
                sourceTabId: sourceTabId,
                targetTabId: targetTabId
            )
        else { return }
        dispatchAction(action)
    }

    private func makeMovePaneToTabAction(
        sourcePaneId: UUID,
        sourceTabId: UUID?,
        targetTabId: UUID
    ) -> WorkspaceActionCommand? {
        let resolvedSourceTabId: UUID? =
            if let sourceTabId, store.tabLayoutAtom.tab(sourceTabId)?.activePaneIds.contains(sourcePaneId) == true {
                sourceTabId
            } else {
                store.tabLayoutAtom.tabs.first(where: { $0.activePaneIds.contains(sourcePaneId) })?.id
            }

        guard let resolvedSourceTabId else { return nil }
        guard resolvedSourceTabId != targetTabId else { return nil }
        guard let targetTab = store.tabLayoutAtom.tab(targetTabId) else { return nil }
        guard let targetPaneId = targetTab.activePaneId ?? targetTab.activePaneIds.first else { return nil }

        return .movePaneAcrossTabs(
            CrossTabPaneMoveRequest(
                paneId: sourcePaneId,
                sourceTabId: resolvedSourceTabId,
                destTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: .horizontal,
                position: .after
            )
        )
    }

    // MARK: - Undo Close Tab

    private func handleUndoCloseTab() {
        executor.undoCloseTab()
    }

    // MARK: - Refocus Active Pane

    func refocusActivePane() {
        requestPaneRefocus(.explicit)
    }

    // MARK: - WorkspaceCommandHandling Conformance

    func execute(_ command: AppCommand) {
        if handlePaneFocusCommand(command) {
            return
        }

        if handleTerminalRuntimeCommand(command) {
            return
        }

        // Try the validated pipeline for pane/tab structural actions
        if let action = WorkspaceCommandResolver.resolve(
            command: command,
            tabs: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        ) {
            dispatchAction(action)
            return
        }

        if handleManagementCommand(command) {
            return
        }

        if handleArrangementCommand(command) {
            return
        }

        handleDirectCommand(command)
    }

    private func handleArrangementCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .switchArrangement:
            requestArrangementPanel()
            return true
        case .previousArrangement:
            switchActiveArrangement(delta: -1)
            return true
        case .nextArrangement, .cycleArrangement:
            switchActiveArrangement(delta: 1)
            return true
        default:
            return false
        }
    }

    private func handleTerminalRuntimeCommand(_ command: AppCommand) -> Bool {
        guard let paneId = focusedTerminalCommandTargetPaneId() else { return false }
        return dispatchTerminalRuntimeCommand(command, paneId: paneId)
    }

    private func dispatchTerminalRuntimeCommand(_ command: AppCommand, paneId: UUID) -> Bool {
        let runtimeCommand: PaneRuntimeCommand
        switch command {
        case .scrollToBottom:
            runtimeCommand = .terminal(.scrollToBottom)
        case .scrollPageUp:
            runtimeCommand = .terminal(.scrollPageUp)
        case .jumpToPreviousPrompt:
            runtimeCommand = .terminal(.jumpToPrompt(delta: -1))
        case .jumpToNextPrompt:
            runtimeCommand = .terminal(.jumpToPrompt(delta: 1))
        default:
            return false
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.runtimeCommandDispatcher.dispatchRuntimeCommand(
                runtimeCommand,
                target: .pane(PaneId(uuid: paneId)),
                correlationId: nil
            )
        }
        return true
    }

    private func handleTargetedTerminalRuntimeCommand(
        _ command: AppCommand,
        target targetId: UUID,
        targetType: SearchItemType
    ) -> Bool {
        guard isPaneTargetType(targetType), canExecuteTargetedTerminalRuntimeCommand(command, target: targetId) else {
            return false
        }
        return dispatchTerminalRuntimeCommand(command, paneId: targetId)
    }

    private func canExecuteTargetedTerminalRuntimeCommand(
        _ command: AppCommand,
        target targetId: UUID
    ) -> Bool {
        guard AppShortcutDispatchPolicy.isTerminalRuntimeCommand(command),
            let pane = store.paneAtom.pane(targetId)
        else {
            return false
        }
        guard case .terminal = pane.content else { return false }
        return true
    }

    private func isPaneTargetType(_ targetType: SearchItemType) -> Bool {
        targetType == .pane || targetType == .floatingTerminal
    }

    private func focusedTerminalCommandTargetPaneId() -> UUID? {
        let candidatePaneId: UUID?
        switch normalizedWorkspaceNavigationScopeState() {
        case .mainPane(let mainPaneId):
            candidatePaneId = mainPaneId ?? activeMainPaneId()
        case .emptyDrawer(let parentPaneId):
            candidatePaneId = parentPaneId
        case .drawerPane(_, let drawerPaneId):
            candidatePaneId = drawerPaneId
        }

        guard
            let candidatePaneId,
            let pane = store.paneAtom.pane(candidatePaneId),
            case .terminal = pane.content
        else {
            return nil
        }
        return candidatePaneId
    }

    private func handleManagementCommand(_ command: AppCommand) -> Bool {
        guard isManagementCommand(command) else { return false }

        let clock = ContinuousClock()
        let commandStart = clock.now
        defer {
            performanceTraceRecorder?.recordDuration(
                .managementLayerCommand,
                duration: commandStart.duration(to: clock.now),
                attributes: [
                    "agentstudio.performance.management_layer.command": .string(command.rawValue),
                    "agentstudio.performance.management_layer.is_active": .bool(atom(\.managementLayer).isActive),
                    "agentstudio.performance.management_layer.pane.count": .int(store.paneAtom.panes.count),
                    "agentstudio.performance.management_layer.tab.count": .int(store.tabLayoutAtom.tabs.count),
                ]
            )
        }

        switch command {
        case .toggleManagementLayer:
            let wasManagementLayerActive = atom(\.managementLayer).isActive
            atom(\.managementLayer).toggle()
            if !wasManagementLayerActive {
                managementNavigationScope = initialWorkspaceNavigationFocusScope()
            }
            return true

        case .managementLayerFocusLeft:
            handleManagementMoveLeft()
            return true

        case .managementLayerFocusRight:
            handleManagementMoveRight()
            return true

        case .managementLayerEnterDrawer:
            handleManagementMoveDown()
            return true

        case .managementLayerExitDrawer:
            handleManagementMoveUp()
            return true

        case .managementLayerOpenDrawer:
            handleManagementOpenDrawer()
            return true

        case .managementLayerCreateTerminal:
            handleManagementCreateTerminal()
            return true

        case .managementLayerCreateBrowser:
            handleManagementCreateBrowser()
            return true

        case .managementLayerExit:
            atom(\.managementLayer).deactivate()
            return true

        default:
            return false
        }
    }

    private func isManagementCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .toggleManagementLayer,
            .managementLayerFocusLeft,
            .managementLayerFocusRight,
            .managementLayerEnterDrawer,
            .managementLayerExitDrawer,
            .managementLayerOpenDrawer,
            .managementLayerCreateTerminal,
            .managementLayerCreateBrowser,
            .managementLayerExit:
            return true
        default:
            return false
        }
    }

    private func handleWebSurfaceCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .openWebview:
            executor.openWebview()
            return true
        case .openBridgeReview:
            executor.openBridgeReview()
            return true
        default:
            return false
        }
    }

    private func handleDirectCommand(_ command: AppCommand) {
        if handlePaneLocationCommand(command) {
            return
        }
        if handlePaneInboxCommand(command) {
            return
        }
        if handleWebSurfaceCommand(command) {
            return
        }

        switch command {
        case .newTab:
            addNewTab()

        case .undoCloseTab:
            handleUndoCloseTab()
        case .renameTab:
            guard let activeTabId = store.tabLayoutAtom.activeTabId else { break }
            requestTabRenamePresentation(for: activeTabId)
        case .watchFolder, .toggleSidebar, .filterSidebar,
            .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications, .showWorktreeSidebar,
            .signInGitHub, .signInGoogle:
            break
        case .enterDrawer:
            enterDrawerFromActivePane()
        case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
            moveDrawerFocus(command)
        case .addDrawerPane:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { break }
            dispatchAction(.addDrawerPane(parentPaneId: paneId))

        case .toggleDrawer:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { break }
            dispatchAction(.toggleDrawer(paneId: paneId))
            handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: paneId)))
            syncFocusOwnerAfterDrawerMutation(parentPaneId: paneId)

        case .closeDrawerPane:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId,
                store.paneAtom.pane(paneId)?.drawer != nil,
                let activeDrawerPaneId = arrangementView.drawerView(forParent: paneId)?.activeChildId
            else { break }
            dispatchAction(.closePane(tabId: tabId, paneId: activeDrawerPaneId))

        case .saveArrangement:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId)
            else { break }
            let name = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
            dispatchAction(.createArrangement(tabId: tabId, name: name))

        case .newTerminalInTab:
            guard let activeTabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(activeTabId),
                let targetPaneId = tab.activePaneId
            else { break }
            dispatchAction(
                .insertPane(
                    source: .newTerminal,
                    targetTabId: activeTabId,
                    targetPaneId: targetPaneId,
                    direction: .right,
                    sizingMode: .halveTarget
                ))
        case .newFloatingTerminal:
            let activePaneCwd = store.tabLayoutAtom.activeTabId
                .flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
                .flatMap { store.paneAtom.pane($0)?.metadata.facets.cwd }
            dispatchAction(.openFloatingTerminal(launchDirectory: activePaneCwd, title: nil))
        case .detachDrawerPane:
            guard case .drawerPane(let parentPaneId, let drawerPaneId) = normalizedWorkspaceNavigationScopeState()
            else {
                break
            }
            dispatchAction(.detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId))
        case .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos,
            .openNewTerminalInTab, .openWorktree, .openWorktreeInPane,
            .switchArrangement, .deleteArrangement, .renameArrangement,
            .navigateDrawerPane, .movePaneToTab,
            .selectTab, .focusPane:
            return  // Handled via drill-in (target selection in command bar)
        default:
            Self.logger.warning(
                "PaneTabViewController.handleDirectCommand ignored unhandled command=\(String(describing: command), privacy: .public)"
            )
        }
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        if command == .selectTab, targetType == .tab {
            handlePaneFocusTrigger(.command(.selectTab(target)))
            return
        }

        if isPaneInboxCommand(command), isPaneInboxTargetType(targetType) {
            handleTargetedPaneInboxCommand(command, target: target, targetType: targetType)
            return
        }

        if command == .focusPane && (targetType == .pane || targetType == .floatingTerminal) {
            focusTargetedPane(target)
            return
        }

        if handleTargetedTerminalRuntimeCommand(command, target: target, targetType: targetType) {
            return
        }

        if let action = targetedAction(command: command, target: target, targetType: targetType) {
            dispatchAction(action)
            return
        }

        // Targeted non-pane commands (e.g. from command bar)
        switch (command, targetType) {
        case (.renameTab, .tab):
            guard store.tabLayoutAtom.tab(target) != nil else {
                Self.logger.warning("renameTab targeted command ignored: tab \(target) not found")
                return
            }
            requestTabRenamePresentation(for: target)
        case (.renameArrangement, .tab):
            guard
                let tab = store.tabLayoutAtom.tabs.first(where: { tab in
                    tab.arrangements.contains(where: { $0.id == target })
                }),
                let arrangement = tab.arrangements.first(where: { $0.id == target })
            else {
                Self.logger.warning("renameArrangement targeted command ignored: arrangement \(target) not found")
                return
            }
            guard !arrangement.isDefault else {
                Self.logger.warning("renameArrangement targeted command ignored: cannot rename default arrangement")
                return
            }
            if store.tabLayoutAtom.activeTabId != tab.id {
                dispatchAction(.selectTab(tabId: tab.id))
            }
            arrangementInlineRenameState.beginEditing(
                arrangementId: arrangement.id,
                currentName: arrangement.name,
                isDefault: arrangement.isDefault
            )
        default:
            Self.logger.warning(
                "Targeted command ignored for unsupported target pair command=\(String(describing: command), privacy: .public) targetType=\(targetType.rawValue, privacy: .public)"
            )
        }
    }

    private func focusTargetedPane(_ paneId: UUID) {
        if let parentPaneId = store.paneAtom.pane(paneId)?.parentPaneId {
            focusTargetedDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId)
            return
        }

        guard let tab = store.tabLayoutAtom.tabContaining(paneId: paneId) else { return }
        handlePaneFocusTrigger(.command(.focusPane(tabId: tab.id, paneId: paneId)))
    }

    private func revealArrangementContainingPane(tabId: UUID, paneId: UUID) {
        guard let tab = store.tabLayoutAtom.tab(tabId),
            !tab.activeArrangement.layout.contains(paneId),
            let containingArrangement = tab.arrangements.first(where: { $0.layout.contains(paneId) })
        else {
            return
        }

        store.tabLayoutAtom.switchArrangement(to: containingArrangement.id, inTab: tabId)
    }

    private func focusTargetedDrawerPane(parentPaneId: UUID, drawerPaneId: UUID) {
        guard
            let tab = store.tabLayoutAtom.tabContaining(paneId: parentPaneId),
            store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.contains(drawerPaneId) == true
        else {
            return
        }

        handlePaneFocusTrigger(.command(.focusPane(tabId: tab.id, paneId: parentPaneId)))
        if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == false {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
        }
        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
    }

    private func focusMainPaneOrdinal(command: AppCommand) -> Bool {
        guard let target = resolveMainPaneOrdinalTarget(for: command) else { return false }
        if target.tab.activeMinimizedPaneIds.contains(target.paneId) {
            dispatchAction(.expandPane(tabId: target.tab.id, paneId: target.paneId))
        }
        if let zoomedPaneId = target.tab.zoomedPaneId, zoomedPaneId != target.paneId {
            dispatchAction(.toggleSplitZoom(tabId: target.tab.id, paneId: target.paneId))
        }
        handlePaneFocusTrigger(.command(.focusPane(tabId: target.tab.id, paneId: target.paneId)))
        return true
    }

    private func resolveMainPaneOrdinalTarget(for command: AppCommand) -> (tab: Tab, paneId: UUID)? {
        guard
            let ordinal = mainPaneOrdinal(for: command),
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId),
            let paneId = PaneOrdinalMap(orderedPaneIds: tab.activePaneIds).paneId(forOrdinal: ordinal)
        else {
            return nil
        }
        return (tab, paneId)
    }

    private func mainPaneOrdinal(for command: AppCommand) -> Int? {
        AppCommand.focusPaneCommands.firstIndex(of: command).map { $0 + 1 }
    }

    private func requestArrangementPanel() {
        guard let activeTabId = store.tabLayoutAtom.activeTabId else { return }
        guard
            let workspaceWindowId =
                workspaceWindowId
                ?? windowLifecycleStore.focusedWindowId
                ?? windowLifecycleStore.keyWindowId
        else { return }
        arrangementPanelPresentation.present(
            tabId: activeTabId,
            workspaceWindowId: workspaceWindowId
        )
    }

    private func switchActiveArrangement(delta: Int) {
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId),
            tab.arrangements.count > 1,
            let activeIndex = tab.arrangements.firstIndex(where: { $0.id == tab.activeArrangementId })
        else {
            return
        }

        let count = tab.arrangements.count
        let nextIndex = (activeIndex + delta + count) % count
        let arrangement = tab.arrangements[nextIndex]
        dispatchAction(.switchArrangement(tabId: tab.id, arrangementId: arrangement.id))
    }

    private func handlePaneFocusCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9:
            return focusMainPaneOrdinal(command: command)
        case .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9:
            return focusDrawerPaneOrdinal(command: command)
        case .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown, .focusNextPane, .focusPrevPane:
            guard let trigger = makePaneKeyboardFocusTrigger(for: command) else { return false }
            handlePaneFocusTrigger(.keyboard(trigger))
            return true
        case .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            guard let tabId = resolvePaneFocusTabSelectionTarget(for: command) else { return false }
            handlePaneFocusTrigger(.command(.selectTab(tabId)))
            return true
        default:
            return false
        }
    }

    private func makePaneKeyboardFocusTrigger(for command: AppCommand) -> PaneKeyboardFocusTrigger? {
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId),
            let activePaneId = tab.activePaneId
        else {
            Self.logger.warning(
                "Pane keyboard focus trigger dropped reason=activeSelectionUnavailable command=\(String(describing: command), privacy: .public)"
            )
            return nil
        }

        let targetPaneId: UUID?
        switch command {
        case .focusPaneLeft:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .left)
        case .focusPaneRight:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .right)
        case .focusPaneUp:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .up)
        case .focusPaneDown:
            targetPaneId = tab.neighborPaneId(of: activePaneId, direction: .down)
        case .focusNextPane:
            targetPaneId = tab.nextPaneId(after: activePaneId)
        case .focusPrevPane:
            targetPaneId = tab.previousPaneId(before: activePaneId)
        default:
            targetPaneId = nil
        }

        guard let targetPaneId else {
            Self.logger.warning(
                "Pane keyboard focus trigger dropped reason=neighborUnavailable command=\(String(describing: command), privacy: .public) activePane=\(activePaneId.uuidString, privacy: .public)"
            )
            return nil
        }
        return .moveToPane(
            tabId: activeTabId,
            paneId: targetPaneId,
            paneKind: PaneFocusContext.PaneKind(content: store.paneAtom.pane(targetPaneId)?.content)
        )
    }

    private func resolvePaneFocusTabSelectionTarget(for command: AppCommand) -> UUID? {
        let tabs = store.tabLayoutAtom.tabs
        guard !tabs.isEmpty else {
            Self.logger.warning(
                "Pane tab selection trigger dropped reason=noTabs command=\(String(describing: command), privacy: .public)"
            )
            return nil
        }

        switch command {
        case .nextTab:
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }),
                !tabs.isEmpty
            else {
                Self.logger.warning(
                    "Pane tab selection trigger dropped reason=activeTabUnavailable command=\(String(describing: command), privacy: .public)"
                )
                return nil
            }
            return tabs[(currentIndex + 1) % tabs.count].id
        case .prevTab:
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }),
                !tabs.isEmpty
            else {
                Self.logger.warning(
                    "Pane tab selection trigger dropped reason=activeTabUnavailable command=\(String(describing: command), privacy: .public)"
                )
                return nil
            }
            return tabs[(currentIndex - 1 + tabs.count) % tabs.count].id
        case .selectTab1:
            return tabs.isEmpty ? nil : tabs[0].id
        case .selectTab2:
            return tabs.count > 1 ? tabs[1].id : nil
        case .selectTab3:
            return tabs.count > 2 ? tabs[2].id : nil
        case .selectTab4:
            return tabs.count > 3 ? tabs[3].id : nil
        case .selectTab5:
            return tabs.count > 4 ? tabs[4].id : nil
        case .selectTab6:
            return tabs.count > 5 ? tabs[5].id : nil
        case .selectTab7:
            return tabs.count > 6 ? tabs[6].id : nil
        case .selectTab8:
            return tabs.count > 7 ? tabs[7].id : nil
        case .selectTab9:
            return tabs.count > 8 ? tabs[8].id : nil
        default:
            return nil
        }
    }

    private func targetedAction(
        command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) -> WorkspaceActionCommand? {
        if let repositoryAction = targetedRepositoryAction(command: command, target: target, targetType: targetType) {
            return repositoryAction
        }

        switch (command, targetType) {
        case (.selectTab, .tab):
            return .selectTab(tabId: target)
        case (.closeTab, .tab):
            return .closeTab(tabId: target)
        case (.breakUpTab, .tab):
            return .breakUpTab(tabId: target)
        case (.closePane, .pane), (.closePane, .floatingTerminal):
            guard let tab = store.tabLayoutAtom.tabs.first(where: { $0.activePaneIds.contains(target) }) else {
                return nil
            }
            return .closePane(tabId: tab.id, paneId: target)
        case (.extractPaneToTab, .pane), (.extractPaneToTab, .floatingTerminal):
            guard let tab = store.tabLayoutAtom.tabs.first(where: { $0.activePaneIds.contains(target) }) else {
                return nil
            }
            return .extractPaneToTab(tabId: tab.id, paneId: target)
        case (.movePaneToTab, .tab):
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let activePaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId
            else { return nil }
            return makeMovePaneToTabAction(
                sourcePaneId: activePaneId,
                sourceTabId: activeTabId,
                targetTabId: target
            )
        case (.switchArrangement, .tab):
            guard let tabId = store.tabLayoutAtom.activeTabId else { return nil }
            return .switchArrangement(tabId: tabId, arrangementId: target)
        case (.deleteArrangement, .tab):
            guard let tabId = store.tabLayoutAtom.activeTabId else { return nil }
            return .removeArrangement(tabId: tabId, arrangementId: target)
        case (.navigateDrawerPane, .pane):
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId),
                let paneId = tab.activePaneId
            else { return nil }
            return .setActiveDrawerPane(parentPaneId: paneId, drawerPaneId: target)
        case (.detachDrawerPane, .pane):
            guard let parentPaneId = store.paneAtom.pane(target)?.parentPaneId else { return nil }
            return .detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: target)
        case (.addDrawerPane, .pane), (.addDrawerPane, .floatingTerminal):
            return .addDrawerPane(parentPaneId: target)
        case (.newTerminalInTab, .tab):
            guard let tab = store.tabLayoutAtom.tab(target), let targetPaneId = tab.activePaneId else { return nil }
            return .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPaneId,
                direction: .right,
                sizingMode: .halveTarget
            )
        case (.renameArrangement, .tab):
            return nil
        default:
            return nil
        }
    }

    private func targetedRepositoryAction(
        command: AppCommand,
        target: UUID,
        targetType: SearchItemType
    ) -> WorkspaceActionCommand? {
        switch (command, targetType) {
        case (.removeRepo, .repo):
            return .removeRepo(repoId: target)
        case (.openWorktree, .worktree):
            return .openWorktree(worktreeId: target)
        case (.openNewTerminalInTab, .worktree):
            return .openNewTerminalInTab(worktreeId: target, launchDirectory: nil, title: nil)
        case (.openWorktreeInPane, .worktree):
            return .openWorktreeInPane(worktreeId: target)
        default:
            return nil
        }
    }

    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        handleExtractPaneRequested(tabId: tabId, paneId: paneId, targetTabIndex: targetTabIndex)
    }

    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        dispatchMovePaneToTab(
            sourcePaneId: sourcePaneId,
            sourceTabId: sourceTabId,
            targetTabId: targetTabId
        )
    }

    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        if isPaneInboxCommand(command), isPaneInboxTargetType(targetType) {
            return paneInboxPresentation != nil && paneInboxTarget(anchorPaneId: target) != nil
        }

        if canExecuteTargetedTerminalRuntimeCommand(command, target: target),
            isPaneTargetType(targetType)
        {
            return true
        }

        if let action = targetedAction(command: command, target: target, targetType: targetType) {
            let snapshot = WorkspaceCommandResolver.snapshot(
                from: store.tabLayoutAtom.tabs,
                activeTabId: store.tabLayoutAtom.activeTabId,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                knownRepoIds: Set(store.repositoryTopologyAtom.repos.map(\.id)),
                knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
                drawerParentByPaneId: drawerParentByPaneId(),
                drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
                visiblePaneIds: { [arrangementView] tab in
                    arrangementView.activeVisiblePaneIds(forTab: tab.id)
                }
            )
            if case .success = WorkspaceCommandValidator.validate(action, state: snapshot) {
                return true
            }
            return false
        }

        switch (command, targetType) {
        case (.renameTab, .tab):
            return store.tabLayoutAtom.tab(target) != nil
        case (.renameArrangement, .tab):
            guard
                let tab = store.tabLayoutAtom.tabs.first(where: { tab in
                    tab.arrangements.contains(where: { $0.id == target })
                }),
                let arrangement = tab.arrangements.first(where: { $0.id == target })
            else {
                return false
            }
            return !arrangement.isDefault
        default:
            return false
        }
    }

    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .managementLayerFocusLeft, .managementLayerFocusRight, .managementLayerEnterDrawer,
            .managementLayerExitDrawer, .managementLayerOpenDrawer,
            .managementLayerCreateTerminal, .managementLayerCreateBrowser, .managementLayerExit:
            return canExecuteManagementCommand(command)
        case .enterDrawer:
            return activeMainPaneId() != nil
        case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
            return drawerFocusNeighbor(for: command) != nil
        case .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9:
            return resolveDrawerPaneOrdinalTarget(for: command) != nil
        case .navigateDrawerPane:
            guard let parentPaneId = activeMainPaneId() else { return false }
            return !(store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.isEmpty ?? true)
        case .detachDrawerPane:
            if case .drawerPane = normalizedWorkspaceNavigationScopeState() {
                return true
            }
            return false
        case .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown, .focusNextPane, .focusPrevPane:
            return makePaneKeyboardFocusTrigger(for: command) != nil
        case .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9:
            return resolveMainPaneOrdinalTarget(for: command) != nil
        case .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            return resolvePaneFocusTabSelectionTarget(for: command) != nil
        case .renameTab:
            return store.tabLayoutAtom.activeTabId != nil
        case .switchArrangement:
            return store.tabLayoutAtom.activeTabId != nil
        case .previousArrangement, .nextArrangement, .cycleArrangement:
            guard
                let activeTabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(activeTabId)
            else {
                return false
            }
            return tab.arrangements.count > 1
        case .scrollToBottom, .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt:
            return focusedTerminalCommandTargetPaneId() != nil
        case .addDrawerPane, .toggleDrawer, .closeDrawerPane:
            return canExecuteContextualCommand(command)
        case .showPaneInboxNotifications, .clearPaneInboxNotifications:
            return paneInboxPresentation != nil && activePaneInboxTarget() != nil
        case .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder,
            .openPaneLocationInEditorMenu:
            return selectedPaneManagementContext()?.targetPath != nil
        case .editPaneNote:
            return activeMainPaneCommandTarget() != nil
        case .copyCurrentPanePath:
            return activeMainPanePath() != nil
        default:
            break
        }

        // Try resolving — if it resolves, validate it
        if let action = WorkspaceCommandResolver.resolve(
            command: command,
            tabs: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            visiblePaneIds: { [arrangementView] tab in
                arrangementView.activeVisiblePaneIds(forTab: tab.id)
            }
        ) {
            let snapshot = WorkspaceCommandResolver.snapshot(
                from: store.tabLayoutAtom.tabs,
                activeTabId: store.tabLayoutAtom.activeTabId,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                knownRepoIds: Set(store.repositoryTopologyAtom.repos.map(\.id)),
                knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
                drawerParentByPaneId: drawerParentByPaneId(),
                drawerLayoutByParentPaneId: drawerLayoutByParentPaneId(),
                visiblePaneIds: { [arrangementView] tab in
                    arrangementView.activeVisiblePaneIds(forTab: tab.id)
                }
            )
            switch WorkspaceCommandValidator.validate(action, state: snapshot) {
            case .success: return true
            case .failure: return false
            }
        }
        return true
    }

    private func handlePaneLocationCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .openPaneLocationInBookmarkedEditor:
            guard let targetPath = selectedPaneManagementContext()?.targetPath else { return false }
            let installedTargets = installedEditorTargetsProvider()
            var resolution = ExternalEditorTarget.resolveBookmarkedOrDefault(
                bookmarkedEditorId: atom(\.editorChooser).bookmarkedEditorId,
                installedTargets: installedTargets
            )
            if case .bookmarkedEditorNotInstalled = resolution {
                // A saved bookmark that is no longer installed should heal back to
                // the implicit default launch order on the same key press.
                atom(\.editorChooser).setBookmarkedEditor(nil)
                resolution = ExternalEditorTarget.resolveBookmarkedOrDefault(
                    bookmarkedEditorId: nil,
                    installedTargets: installedTargets
                )
            }
            guard case .resolved(let target) = resolution else { return false }
            return openEditorHandler(target.id, targetPath, installedTargets)
        case .openPaneLocationInFinder:
            guard let targetPath = selectedPaneManagementContext()?.targetPath else { return false }
            return openFinderHandler(targetPath)
        case .openPaneLocationInEditorMenu:
            guard let activePaneId = activePaneIdForChooserRequest() else { return false }
            if atom(\.editorChooser).openForPaneId == activePaneId {
                atom(\.editorChooser).setOpenEditorPane(nil)
                return true
            }
            atom(\.editorChooser).setAvailableTargets(installedEditorTargetsProvider())
            atom(\.editorChooser).setOpenEditorPane(activePaneId)
            return true
        case .editPaneNote:
            guard let paneId = activeMainPaneCommandTarget() else { return false }
            if let paneNotePresentation {
                paneNotePresentation.present(paneId)
            } else {
                requestPaneNotePresentation(for: paneId)
            }
            return true
        case .copyCurrentPanePath:
            guard let path = activeMainPanePath() else { return false }
            copyPathHandler(path)
            return true
        default:
            return false
        }
    }

    private func handlePaneInboxCommand(_ command: AppCommand) -> Bool {
        guard let paneInboxPresentation, let target = activePaneInboxTarget() else { return false }
        switch command {
        case .showPaneInboxNotifications:
            paneInboxPresentation.toggle(target.parentPaneId, target.paneIds)
            return true
        case .clearPaneInboxNotifications:
            paneInboxPresentation.clear(target.parentPaneId, target.paneIds)
            return true
        default:
            return false
        }
    }

    private func handleTargetedPaneInboxCommand(
        _ command: AppCommand,
        target targetId: UUID,
        targetType: SearchItemType
    ) {
        guard isPaneInboxCommand(command), isPaneInboxTargetType(targetType) else { return }
        guard let paneInboxPresentation, let target = paneInboxTarget(anchorPaneId: targetId) else { return }

        switch command {
        case .showPaneInboxNotifications:
            focusTargetedPane(targetId)
            paneInboxPresentation.toggle(target.parentPaneId, target.paneIds)
        case .clearPaneInboxNotifications:
            paneInboxPresentation.clear(target.parentPaneId, target.paneIds)
        default:
            return
        }
    }

    private func activePaneInboxTarget() -> PaneInboxCommandTarget? {
        guard let parentPaneId = activePaneInboxParentPaneId() else { return nil }
        return paneInboxTarget(anchorPaneId: parentPaneId)
    }

    private func paneInboxTarget(anchorPaneId: UUID) -> PaneInboxCommandTarget? {
        guard store.paneAtom.pane(anchorPaneId) != nil else { return nil }
        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: anchorPaneId,
            pane: { store.paneAtom.pane($0) }
        )
        guard store.tabLayoutAtom.tabContaining(paneId: scope.parentPaneId) != nil else {
            return nil
        }
        return PaneInboxCommandTarget(parentPaneId: scope.parentPaneId, paneIds: scope.paneIds)
    }

    private func isPaneInboxCommand(_ command: AppCommand) -> Bool {
        command == .showPaneInboxNotifications || command == .clearPaneInboxNotifications
    }

    private func isPaneInboxTargetType(_ targetType: SearchItemType) -> Bool {
        targetType == .pane || targetType == .floatingTerminal
    }

    private func activePaneInboxParentPaneId() -> UUID? {
        guard let activePaneId = activeMainPaneId(),
            let activePane = store.paneAtom.pane(activePaneId)
        else {
            return nil
        }

        return activePane.parentPaneId ?? activePane.id
    }

    private func selectedPaneManagementContext() -> PaneManagementContext? {
        guard let paneId = selectedPaneIdForLocationCommands() else {
            return nil
        }

        return PaneManagementContext.project(
            paneId: paneId,
            store: store,
            notificationCountForWorktree: { worktreeId in
                WorkspaceNotificationCountProjection.rollUpAlertCount(
                    worktreeId: worktreeId,
                    inboxAtom: atom(\.inboxNotification)
                )
            }
        )
    }

    private func activeMainPaneCommandTarget() -> UUID? {
        guard case .mainPane(let paneId) = normalizedWorkspaceNavigationScopeState(),
            let activePaneId = paneId ?? activeMainPaneId(),
            let pane = store.paneAtom.pane(activePaneId),
            pane.parentPaneId == nil
        else {
            return nil
        }

        return activePaneId
    }

    private func requestPaneNotePresentation(for paneId: UUID) {
        guard store.paneAtom.pane(paneId) != nil else {
            Self.logger.warning("editPaneNote presentation ignored: pane \(paneId) not found")
            return
        }

        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.presentPaneNotePopover(for: paneId)
            }
        }
    }

    private func presentPaneNotePopover(for paneId: UUID) {
        guard let pane = store.paneAtom.pane(paneId) else {
            Self.logger.warning("editPaneNote presentation ignored after defer: pane \(paneId) not found")
            return
        }

        closePaneNotePopover()
        guard isViewLoaded else { return }

        let resolvedWindowId =
            workspaceWindowId ?? windowLifecycleStore.focusedWindowId
            ?? windowLifecycleStore.keyWindowId
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PaneNotePopover(
                currentNote: pane.metadata.note,
                onCommit: { [weak self] note in
                    guard let self else { return }
                    self.store.paneAtom.updatePaneNote(paneId, note: note)
                    self.closePaneNotePopover()
                },
                onCancel: { [weak self] in
                    self?.closePaneNotePopover()
                }
            )
            .transientKeyboardSurface(
                .paneNote(paneId: paneId),
                workspaceWindowId: resolvedWindowId,
                onDismiss: { [weak self] in
                    self?.closePaneNotePopover()
                }
            )
        )
        paneNotePopover = popover

        let anchorView = viewRegistry.view(for: paneId) ?? view
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }

    private func closePaneNotePopover() {
        let popover = paneNotePopover
        paneNotePopover = nil
        popover?.delegate = nil
        popover?.close()
    }

    private func activeMainPanePath() -> URL? {
        guard let paneId = activeMainPaneCommandTarget(),
            let pane = store.paneAtom.pane(paneId)
        else {
            return nil
        }

        return pane.metadata.cwd ?? pane.metadata.launchDirectory
    }

    private func activePaneIdForChooserRequest() -> UUID? {
        selectedPaneIdForLocationCommands()
    }

    private func selectedPaneIdForLocationCommands() -> UUID? {
        guard let parentPaneId = activeMainPaneId() else {
            return nil
        }

        if let drawerPaneId = visibleActiveDrawerPaneId(for: parentPaneId) {
            return drawerPaneId
        }

        return parentPaneId
    }
}

#if DEBUG
    extension PaneTabViewController {
        var splitHostingViewForTesting: NSView? { activeTabHost()?.hostingView }
        var appLifecycleStoreForTesting: AppLifecycleAtom { appLifecycleStore }
        func tabHostViewForTesting(tabId: UUID) -> NSView? {
            tabContentHosts[tabId]
        }
        var paneRepresentableDismantleCountForTesting: Int {
            paneRepresentableDismantleCount
        }
        var managementNavigationScopeDescriptionForTesting: String {
            switch managementNavigationScope {
            case .mainRow:
                return "mainRow"
            case .drawer(let parentPaneId):
                return "drawer:\(parentPaneId.uuidString)"
            }
        }
        func setManagementNavigationScopeToDrawerForTesting(parentPaneId: UUID) {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
        }
    }
#endif
