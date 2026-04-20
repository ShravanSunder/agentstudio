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

/// Tab-based terminal controller with custom Ghostty-style tab bar.
///
/// PaneTabViewController is a composition-oriented controller in `App/`. It reads
/// from WorkspaceStore for state and routes user actions through the validated
/// ActionExecutor pipeline. Most flow changes are dispatched, while AppKit-only
/// concerns (focus, observers, empty-state visibility, tab bar coordination) stay
/// local. It also handles direct tab-order updates (`store.moveTab`) from drag
/// interactions as a UI-only mutation.
@MainActor
class PaneTabViewController: NSViewController, WorkspaceCommandHandling {
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
    private let executor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry
    private let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    private let tabRenamePopoverState: TabRenamePopoverState
    private let arrangementInlineRenameState: ArrangementInlineRenameState
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
        shouldAcceptDrop: { [weak self] payload, destPaneId, zone in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.shouldAcceptDrop dropped ownerReleased destPaneId=\(destPaneId) zone=\(zone)"
                )
                return false
            }
            return self.evaluateDropAcceptance(payload: payload, destPaneId: destPaneId, zone: zone)
        },
        handleDrop: { [weak self] payload, destPaneId, zone in
            guard let self else {
                RestoreTrace.log(
                    "PaneTabActionDispatcher.handleDrop dropped ownerReleased destPaneId=\(destPaneId) zone=\(zone)"
                )
                return
            }
            self.handleSplitDrop(payload: payload, destPaneId: destPaneId, zone: zone)
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
        executor: ActionExecutor,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
        tabRenamePopoverState: TabRenamePopoverState = TabRenamePopoverState(),
        arrangementInlineRenameState: ArrangementInlineRenameState = ArrangementInlineRenameState()
    ) {
        self.store = store
        self.repoCache = repoCache
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.executor = executor
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.tabRenamePopoverState = tabRenamePopoverState
        self.arrangementInlineRenameState = arrangementInlineRenameState
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
            renamePopoverState: tabRenamePopoverState,
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
            onRenameCommit: { [weak self] tabId, name in
                self?.dispatchAction(.renameTab(tabId: tabId, name: name))
                self?.tabRenamePopoverState.dismiss()
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
                self.dispatchAction(
                    .createArrangement(
                        tabId: tabId, name: name, paneIds: Set(tab.activePaneIds)
                    ))
            },
            onOpenRepoInTab: {
                CommandDispatcher.shared.dispatch(.showCommandBarRepos)
            }
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
            tabBarHostingView.heightAnchor.constraint(equalToConstant: 36),

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

        // Register as command handler
        CommandDispatcher.shared.handler = self

        syncTabContentHosts()
        updateVisibleTabHost()

        // Observe store for AppKit-level concerns (empty state visibility, focus management)
        updateEmptyState()
        observeForAppKitState()

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
        if handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        syncTabContentHosts()
        updateVisibleTabHost()
        updateEmptyState()
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
                    default:
                        continue
                    }
                }
            })
    }

    isolated deinit {
        if let monitor = arrangementBarEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        for task in notificationTasks {
            task.cancel()
        }
        notificationTasks.removeAll()
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
            _ = atom(\.managementLayer).isActive
        } onChange: {
            Task { @MainActor [weak self] in
                self?.handleAppKitStateChange()
                self?.observeForAppKitState()
            }
        }
    }

    private func handleAppKitStateChange() {
        syncTabContentHosts()
        updateVisibleTabHost()
        rebuildEmptyStateView()
        updateEmptyState()

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

        // Management layer exit is intentionally a two-step sequence:
        // the mode trigger releases content interaction, then refocus chooses
        // the pane-specific responder target once the mode change has landed.
        if didExitManagementLayer {
            requestPaneRefocus(.managementLayerExited)
        }
    }

    private func preferredVisibleFocusPaneId() -> UUID? {
        let navigationScope = normalizedWorkspaceNavigationFocusScope()

        if case .drawer(let parentPaneId) = navigationScope,
            let drawerPaneId = visibleActiveDrawerPaneId(for: parentPaneId)
        {
            return drawerPaneId
        }

        return store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0) }?
            .activePaneId
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
                self.store.tabLayoutAtom.setActiveTab(tabId)
                atom(\.workspaceFocusOwner).focusMainPane(
                    self.store.tabLayoutAtom.tab(tabId)?.activePaneId
                )
                self.managementNavigationScope = .mainRow
            },
            selectPane: { [weak self] tabId, paneId in
                guard let self else { return }
                self.recordSelectionDrivenRefocusSuppression(tabId: tabId, paneId: paneId)
                if self.store.tabLayoutAtom.activeTabId != tabId {
                    self.store.tabLayoutAtom.setActiveTab(tabId)
                }
                if let tab = self.store.tabLayoutAtom.tab(tabId), tab.activeMinimizedPaneIds.contains(paneId) {
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
                self.store.paneAtom.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
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
        return .init(
            activeMainPaneId: activeMainPaneId,
            expandedDrawerParentPaneId: drawer?.isExpanded == true ? activeMainPaneId : nil,
            drawerPaneIds: drawer?.paneIds ?? [],
            activeDrawerPaneId: drawer?.activePaneId,
            minimizedDrawerPaneIds: drawer?.minimizedPaneIds ?? []
        )
    }

    private func syncFocusOwnerAfterDrawerMutation(parentPaneId: UUID) {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return }

        if drawer.isExpanded {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            if let drawerPaneId = drawer.activePaneId, !drawer.minimizedPaneIds.contains(drawerPaneId) {
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
                guard let drawer = pane.drawer else { return nil }
                return (pane.id, drawer.layout)
            }
        )
    }

    private func visibleActiveDrawerPaneId(for parentPaneId: UUID) -> UUID? {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return nil }
        guard drawer.isExpanded else { return nil }
        guard let drawerPaneId = drawer.activePaneId else { return nil }
        guard !drawer.minimizedPaneIds.contains(drawerPaneId) else { return nil }
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
            onOpenPaneGitHub: { [weak self] paneId in
                self?.openGitHubWebview(for: paneId)
            }
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
        executor.restoreVisibleViewsForActiveTabIfNeeded()
        syncVisibleTerminalGeometry(reason: reason)
    }

    func syncVisibleTerminalGeometry(reason: StaticString) {
        guard let activeTabId = store.tabLayoutAtom.activeTabId else { return }
        let visibleTerminalViews =
            store.tabLayoutAtom.tab(activeTabId)?.paneIds.compactMap {
                viewRegistry.terminalView(for: $0)
            }.filter { terminalView in
                terminalView.window != nil && !terminalView.isHidden
            } ?? []
        guard !visibleTerminalViews.isEmpty else { return }
        RestoreTrace.log(
            "PaneTabViewController.syncVisibleTerminalGeometry reason=\(reason) count=\(visibleTerminalViews.count)"
        )
        for terminalView in visibleTerminalViews {
            terminalView.forceGeometrySync(reason: reason)
        }
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
        zone: DropZone
    ) -> Bool {
        guard shouldHandleSplitDragPayload(payload) else {
            return false
        }
        let snapshot = dragDropSnapshot()
        return Self.splitDropCommitPlan(
            payload: payload,
            destinationPane: store.paneAtom.pane(destPaneId),
            destinationPaneId: destPaneId,
            zone: zone,
            activeTabId: store.tabLayoutAtom.activeTabId,
            state: snapshot
        ) != nil
    }

    /// Handle a completed drop on a split pane.
    private func handleSplitDrop(payload: SplitDropPayload, destPaneId: UUID, zone: DropZone) {
        guard shouldHandleSplitDragPayload(payload) else {
            return
        }
        let snapshot = dragDropSnapshot()
        guard
            let plan = Self.splitDropCommitPlan(
                payload: payload,
                destinationPane: store.paneAtom.pane(destPaneId),
                destinationPaneId: destPaneId,
                zone: zone,
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
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId()
        )
    }

    private func executeDropCommitPlan(_ plan: DropCommitPlan) {
        switch plan {
        case .paneAction(let action):
            dispatchAction(action)
        case .moveTab(let tabId, let toIndex):
            store.tabLayoutAtom.moveTab(fromId: tabId, toIndex: toIndex)
            store.tabLayoutAtom.setActiveTab(tabId)
        case .extractPaneToTabThenMove(let paneId, let sourceTabId, let toIndex):
            let tabCountBefore = store.tabLayoutAtom.tabs.count
            dispatchAction(.extractPaneToTab(tabId: sourceTabId, paneId: paneId))
            guard
                store.tabLayoutAtom.tabs.count == tabCountBefore + 1,
                let extractedTabId = store.tabLayoutAtom.activeTabId
            else {
                return
            }
            store.tabLayoutAtom.moveTab(fromId: extractedTabId, toIndex: toIndex)
            store.tabLayoutAtom.setActiveTab(extractedTabId)
        }
    }

    nonisolated static func splitDropCommitPlan(
        payload: SplitDropPayload,
        destinationPane: Pane?,
        destinationPaneId: UUID,
        zone: DropZone,
        activeTabId: UUID?,
        state: ActionStateSnapshot
    ) -> DropCommitPlan? {
        guard let activeTabId else {
            return nil
        }
        let destination = PaneDropDestination.split(
            targetPaneId: destinationPaneId,
            targetTabId: activeTabId,
            direction: splitDirection(for: zone),
            targetDrawerParentPaneId: destinationPane?.parentPaneId
        )
        let decision = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: destination,
            state: state
        )
        if case .eligible(let plan) = decision {
            return plan
        }
        return nil
    }

    private func drawerMoveDropAction(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZone
    ) -> PaneActionCommand? {
        let destinationPane = store.paneAtom.pane(destPaneId)
        let sourcePane: Pane? =
            if case .existingPane(let sourcePaneId, _) = payload.kind {
                store.paneAtom.pane(sourcePaneId)
            } else {
                nil
            }

        return Self.resolveDrawerMoveDropAction(
            payload: payload,
            destinationPane: destinationPane,
            sourcePane: sourcePane,
            zone: zone
        )
    }

    private func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool {
        switch payload.kind {
        case .existingPane(let sourcePaneId, _):
            guard let sourcePane = store.paneAtom.pane(sourcePaneId) else { return false }
            return sourcePane.parentPaneId == nil
        case .existingTab, .newTerminal:
            return true
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

            onAddFolder: { [weak self] in self?.addFolderAction() },
            onOpenRecent: { [weak self] target in self?.openRecentTarget(target) },
            onOpenAllRecent: { [weak self] in self?.openAllRecentTargets() }
        )
    }

    @objc private func addFolderAction() {
        CommandDispatcher.shared.dispatch(.addFolder)
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

            onAddFolder: { [weak self] in self?.addFolderAction() },
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
        requiresNeutralDrawerFocus: Bool = true
    ) -> Bool {
        if shouldCreateFirstDrawerPane(
            from: event,
            requiresNeutralFocus: requiresNeutralDrawerFocus
        ) {
            dispatchAction(.addDrawerPane(parentPaneId: activeMainPaneId()!))
            return true
        }

        if let trigger = ShortcutDecoder.decode(event: event),
            let command = scopeAwarePaneCommand(for: trigger)
        {
            execute(command)
            return true
        }

        if let trigger = ShortcutDecoder.decode(event: event),
            shouldConsumeScopeAwarePaneTrigger(trigger)
        {
            return true
        }

        if let trigger = ShortcutDecoder.decode(event: event),
            let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .global),
            CommandDispatcher.shared.canDispatch(shortcut.command)
        {
            CommandDispatcher.shared.dispatch(shortcut.command)
            return true
        }

        return false
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

    private func shouldConsumeScopeAwarePaneTrigger(_ trigger: ShortcutTrigger) -> Bool {
        switch trigger {
        case .init(key: .character(.i), modifiers: [.option]),
            .init(key: .character(.k), modifiers: [.option]):
            return true
        default:
            return scopeAwarePaneCommand(for: trigger) != nil
        }
    }

    private func shouldCreateFirstDrawerPane(
        from event: NSEvent,
        requiresNeutralFocus: Bool = true
    ) -> Bool {
        guard
            atom(\.managementLayer).isActive == false,
            event.charactersIgnoringModifiers?.lowercased() == "d",
            event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
            case .emptyDrawer(let parentPaneId) = normalizedWorkspaceNavigationScopeState(),
            store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.isEmpty == true
        else {
            return false
        }
        return true
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
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return [] }
        return drawer.paneIds.filter { !drawer.minimizedPaneIds.contains($0) }
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

        if let drawerPaneId = store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
        } else {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
            _ = clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
        }
    }

    private func moveDrawerFocus(_ command: AppCommand) {
        guard case .drawer(let parentPaneId) = normalizedWorkspaceNavigationFocusScope() else { return }
        guard let drawerPaneId = store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId else { return }

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
            return
        }

        guard
            let targetPaneId = store.paneAtom.pane(parentPaneId)?
                .drawer?
                .layout
                .neighbor(of: drawerPaneId, direction: direction)
        else { return }

        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: targetPaneId)))
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

        // Single-pane tab: close the whole tab (WorkspaceCommandValidator rejects .closePane
        // for single-pane tabs). Multi-pane: close just the pane.
        if tab.allPaneIds.count > 1 {
            guard
                let matchedPaneId = tab.allPaneIds.first(where: { id in
                    store.paneAtom.pane(id)?.worktreeId == worktreeId
                })
            else { return }
            dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
        } else {
            dispatchAction(.closeTab(tabId: tab.id))
        }
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

    /// Central entry point: validates a PaneActionCommand and executes it if valid.
    /// All input sources (keyboard, menu, drag-drop, commands) converge here.
    private func dispatchAction(_ action: PaneActionCommand) {
        let snapshot = WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId(),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneId()
        )

        switch WorkspaceCommandValidator.validate(action, state: snapshot) {
        case .success:
            executor.execute(action)
            syncFocusOwnerAfterValidatedAction(action)
        case .failure(let error):
            ghosttyLogger.warning("Action rejected: \(error)")
        }
    }

    private func syncFocusOwnerAfterValidatedAction(_ action: PaneActionCommand) {
        switch action {
        case .addDrawerPane(let parentPaneId),
            .removeDrawerPane(let parentPaneId, _),
            .toggleDrawer(let parentPaneId),
            .setActiveDrawerPane(let parentPaneId, _),
            .insertDrawerPane(let parentPaneId, _, _),
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

    /// Route tab context menu commands through the validated pipeline.
    private func handleTabCommand(_ command: AppCommand, tabId: UUID) {
        if command == .renameTab {
            tabRenamePopoverState.present(for: tabId)
            return
        }

        let action: PaneActionCommand?

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
                direction: direction
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
            action = .createArrangement(
                tabId: tabId, name: name, paneIds: Set(tab.activePaneIds)
            )
        default:
            action = nil
        }

        if let action {
            dispatchAction(action)
        }
    }

    // MARK: - Tab Reordering

    private func handleTabReorder(fromId: UUID, toIndex: Int) {
        store.tabLayoutAtom.moveTab(fromId: fromId, toIndex: toIndex)
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
            if let parentPaneId = pane.parentPaneId,
                store.tabLayoutAtom.tabContaining(paneId: parentPaneId) != nil
            {
                dispatchAction(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
                return
            }

            if let tab = store.tabLayoutAtom.tabContaining(paneId: paneId) {
                if tab.allPaneIds.count > 1 {
                    dispatchAction(.closePane(tabId: tab.id, paneId: paneId))
                } else {
                    dispatchAction(.closeTab(tabId: tab.id))
                }
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
                store.tabLayoutAtom.moveTab(fromId: tabId, toIndex: targetTabIndex)
                store.tabLayoutAtom.setActiveTab(tabId)
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

        store.tabLayoutAtom.moveTab(fromId: extractedTabId, toIndex: targetTabIndex)
        store.tabLayoutAtom.setActiveTab(extractedTabId)
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
    ) -> PaneActionCommand? {
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

        return .insertPane(
            source: .existingPane(paneId: sourcePaneId, sourceTabId: resolvedSourceTabId),
            targetTabId: targetTabId,
            targetPaneId: targetPaneId,
            direction: .right
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

        // Try the validated pipeline for pane/tab structural actions
        if let action = WorkspaceCommandResolver.resolve(
            command: command, tabs: store.tabLayoutAtom.tabs, activeTabId: store.tabLayoutAtom.activeTabId
        ) {
            dispatchAction(action)
            return
        }

        if handleManagementCommand(command) {
            return
        }

        handleDirectCommand(command)
    }

    private func handleManagementCommand(_ command: AppCommand) -> Bool {
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

    private func handleDirectCommand(_ command: AppCommand) {
        switch command {
        case .newTab:
            addNewTab()

        case .undoCloseTab:
            handleUndoCloseTab()
        case .renameTab:
            guard let activeTabId = store.tabLayoutAtom.activeTabId else { break }
            tabRenamePopoverState.present(for: activeTabId)
        case .addFolder, .toggleSidebar, .filterSidebar, .signInGitHub, .signInGoogle:
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
                let pane = store.paneAtom.pane(paneId),
                let drawer = pane.drawer,
                let activeDrawerPaneId = drawer.activePaneId
            else { break }
            dispatchAction(.removeDrawerPane(parentPaneId: paneId, drawerPaneId: activeDrawerPaneId))

        case .saveArrangement:
            guard let tabId = store.tabLayoutAtom.activeTabId,
                let tab = store.tabLayoutAtom.tab(tabId)
            else { break }
            let name = ArrangementDerived.nextCustomArrangementName(existing: tab.arrangements)
            dispatchAction(
                .createArrangement(
                    tabId: tabId, name: name, paneIds: Set(tab.activePaneIds)
                ))

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
                    direction: .right
                ))
        case .newFloatingTerminal:
            let activePaneCwd = store.tabLayoutAtom.activeTabId
                .flatMap { store.tabLayoutAtom.tab($0)?.activePaneId }
                .flatMap { store.paneAtom.pane($0)?.metadata.facets.cwd }
            dispatchAction(.openFloatingTerminal(launchDirectory: activePaneCwd, title: nil))
        case .openWebview:
            executor.openWebview()
        case .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos,
            .openNewTerminalInTab, .openWorktree, .openWorktreeInPane,
            .switchArrangement, .deleteArrangement, .renameArrangement,
            .navigateDrawerPane, .movePaneToTab,
            .selectTab, .focusPane, .detachDrawerPane:
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

        if command == .focusPane && (targetType == .pane || targetType == .floatingTerminal) {
            focusTargetedPane(target)
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
            if store.tabLayoutAtom.activeTabId != target {
                dispatchAction(.selectTab(tabId: target))
            }
            tabRenamePopoverState.present(for: target)
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
            execute(command)
        }
    }

    private func focusTargetedPane(_ paneId: UUID) {
        guard let tab = store.tabLayoutAtom.tabs.first(where: { $0.activePaneIds.contains(paneId) }) else { return }
        handlePaneFocusTrigger(.command(.focusPane(tabId: tab.id, paneId: paneId)))
    }

    private func handlePaneFocusCommand(_ command: AppCommand) -> Bool {
        switch command {
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
    ) -> PaneActionCommand? {
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
        case (.newTerminalInTab, .tab):
            guard let tab = store.tabLayoutAtom.tab(target), let targetPaneId = tab.activePaneId else { return nil }
            return .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: targetPaneId,
                direction: .right
            )
        case (.removeRepo, .repo):
            return .removeRepo(repoId: target)
        case (.openWorktree, .worktree):
            return .openWorktree(worktreeId: target)
        case (.openNewTerminalInTab, .worktree):
            return .openNewTerminalInTab(worktreeId: target, launchDirectory: nil, title: nil)
        case (.openWorktreeInPane, .worktree):
            return .openWorktreeInPane(worktreeId: target)
        case (.renameArrangement, .tab):
            return nil
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
        if let action = targetedAction(command: command, target: target, targetType: targetType) {
            let snapshot = WorkspaceCommandResolver.snapshot(
                from: store.tabLayoutAtom.tabs,
                activeTabId: store.tabLayoutAtom.activeTabId,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                knownRepoIds: Set(store.repositoryTopologyAtom.repos.map(\.id)),
                knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
                drawerParentByPaneId: drawerParentByPaneId(),
                drawerLayoutByParentPaneId: drawerLayoutByParentPaneId()
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
            return canExecute(command)
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
            if case .drawerPane(let parentPaneId, _) = normalizedWorkspaceNavigationScopeState() {
                return store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId != nil
            }
            return false
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
        case .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            return resolvePaneFocusTabSelectionTarget(for: command) != nil
        case .renameTab:
            return store.tabLayoutAtom.activeTabId != nil
        case .addDrawerPane, .toggleDrawer, .closeDrawerPane:
            return canExecuteContextualCommand(command)
        default:
            break
        }

        // Try resolving — if it resolves, validate it
        if let action = WorkspaceCommandResolver.resolve(
            command: command, tabs: store.tabLayoutAtom.tabs, activeTabId: store.tabLayoutAtom.activeTabId
        ) {
            let snapshot = WorkspaceCommandResolver.snapshot(
                from: store.tabLayoutAtom.tabs,
                activeTabId: store.tabLayoutAtom.activeTabId,
                isManagementLayerActive: atom(\.managementLayer).isActive,
                knownRepoIds: Set(store.repositoryTopologyAtom.repos.map(\.id)),
                knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
                drawerParentByPaneId: drawerParentByPaneId(),
                drawerLayoutByParentPaneId: drawerLayoutByParentPaneId()
            )
            switch WorkspaceCommandValidator.validate(action, state: snapshot) {
            case .success: return true
            case .failure: return false
            }
        }
        // Non-pane commands are always available
        return true
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
