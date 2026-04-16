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

    private enum ManagementNavigationScope: Equatable {
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
    private var lastManagementModeActive = false
    private var managementNavigationScope: ManagementNavigationScope = .mainRow
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
        tabRenamePopoverState: TabRenamePopoverState = TabRenamePopoverState()
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
                let name = Self.nextArrangementName(existing: tab.arrangements)
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
            guard self != nil else { return event }
            if let trigger = ShortcutDecoder.decode(event: event),
                let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .global),
                CommandDispatcher.shared.canDispatch(shortcut.command)
            {
                CommandDispatcher.shared.dispatch(shortcut.command)
                return nil
            }
            return event
        }

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
            _ = self.store.scanningPath
            _ = self.repoCache.recentTargets
            _ = atom(\.managementMode).isActive
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

        let isManagementModeActive = atom(\.managementMode).isActive
        let didExitManagementMode = lastManagementModeActive && !isManagementModeActive
        if lastManagementModeActive != isManagementModeActive {
            let transition: PaneModeFocusTrigger.Transition =
                isManagementModeActive ? .enteredManagementMode : .exitedManagementMode
            handlePaneFocusTrigger(
                .mode(
                    PaneModeFocusTrigger(
                        transition: transition,
                        source: .command
                    )
                )
            )
        }

        if !lastManagementModeActive && isManagementModeActive {
            managementNavigationScope = .mainRow
        }
        lastManagementModeActive = isManagementModeActive
        normalizeManagementNavigationScope()

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
                requestPaneRefocus(.explicit)
            }
        }

        // Management mode exit is intentionally a two-step sequence:
        // the mode trigger releases content interaction, then refocus chooses
        // the pane-specific responder target once the mode change has landed.
        if didExitManagementMode {
            requestPaneRefocus(.managementModeExited)
        }
    }

    private func preferredVisibleFocusPaneId() -> UUID? {
        normalizeManagementNavigationScope()

        if case .drawer(let parentPaneId) = managementNavigationScope,
            let drawerPaneId = visibleActiveDrawerPaneId(for: parentPaneId)
        {
            return drawerPaneId
        }

        return store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0) }?
            .activePaneId
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
                let paneId = self.store.tabLayoutAtom.tab(tabId)?.activePaneId
                self.recordSelectionDrivenRefocusSuppression(tabId: tabId, paneId: paneId)
                self.store.tabLayoutAtom.setActiveTab(tabId)
                if atom(\.managementMode).isActive {
                    self.managementNavigationScope = .mainRow
                }
            },
            selectPane: { [weak self] tabId, paneId in
                guard let self else { return }
                self.recordSelectionDrivenRefocusSuppression(tabId: tabId, paneId: paneId)
                if self.store.tabLayoutAtom.activeTabId != tabId {
                    self.store.tabLayoutAtom.setActiveTab(tabId)
                }
                if let tab = self.store.tabLayoutAtom.tab(tabId), tab.minimizedPaneIds.contains(paneId) {
                    self.executor.execute(.expandPane(tabId: tabId, paneId: paneId))
                }
                self.store.tabLayoutAtom.setActivePane(paneId, inTab: tabId)
                if atom(\.managementMode).isActive {
                    self.managementNavigationScope = .mainRow
                }
            },
            selectDrawerPane: { [weak self] parentPaneId, drawerPaneId in
                guard let self else { return }
                self.recordSelectionDrivenRefocusSuppression(
                    tabId: self.store.tabLayoutAtom.activeTabId,
                    paneId: drawerPaneId
                )
                self.store.paneAtom.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
                if atom(\.managementMode).isActive {
                    self.managementNavigationScope = .drawer(parentPaneId: parentPaneId)
                }
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
                .init(parentPaneId: $0, paneId: visibleActiveDrawerPaneId(for: $0))
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
            managementMode: atom(\.managementMode).isActive
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

    private func normalizeManagementNavigationScope() {
        guard case .drawer(let parentPaneId) = managementNavigationScope else { return }
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let activePaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId,
            activePaneId == parentPaneId,
            store.paneAtom.pane(parentPaneId)?.drawer != nil
        else {
            managementNavigationScope = .mainRow
            return
        }
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
        let drawerParentByPaneId = store.paneAtom.panes.values.reduce(into: [UUID: UUID]()) { result, pane in
            guard let parentPaneId = pane.parentPaneId else { return }
            result[pane.id] = parentPaneId
        }

        return WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementModeActive: atom(\.managementMode).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId
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

    private func managementParentPaneId() -> UUID? {
        normalizeManagementNavigationScope()

        switch managementNavigationScope {
        case .mainRow:
            return activeMainPaneId()
        case .drawer(let parentPaneId):
            return parentPaneId
        }
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
        normalizeManagementNavigationScope()

        switch managementNavigationScope {
        case .mainRow:
            execute(.focusPaneLeft)
        case .drawer(let parentPaneId):
            focusSiblingDrawerPane(in: parentPaneId, delta: -1)
        }
    }

    private func handleManagementMoveRight() {
        normalizeManagementNavigationScope()

        switch managementNavigationScope {
        case .mainRow:
            execute(.focusPaneRight)
        case .drawer(let parentPaneId):
            focusSiblingDrawerPane(in: parentPaneId, delta: 1)
        }
    }

    private func handleManagementMoveDown() {
        guard let parentPaneId = activeMainPaneId() else { return }
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
        normalizeManagementNavigationScope()
        guard case .drawer(let parentPaneId) = managementNavigationScope else { return }
        if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
            handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: parentPaneId)))
        }
        managementNavigationScope = .mainRow
    }

    private func handleManagementCreateTerminal() {
        normalizeManagementNavigationScope()

        switch managementNavigationScope {
        case .mainRow:
            execute(.newTerminalInTab)
        case .drawer(let parentPaneId):
            dispatchAction(.addDrawerPane(parentPaneId: parentPaneId))
        }
    }

    private func handleManagementCreateBrowser() {
        normalizeManagementNavigationScope()

        switch managementNavigationScope {
        case .mainRow:
            guard let paneId = activeMainPaneId() else { return }
            openGitHubWebview(for: paneId)
        case .drawer(let parentPaneId):
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
        normalizeManagementNavigationScope()

        switch command {
        case .managementFocusLeft:
            switch managementNavigationScope {
            case .mainRow:
                return canExecute(.focusPaneLeft)
            case .drawer(let parentPaneId):
                return visibleDrawerPaneIds(for: parentPaneId).count > 1
            }
        case .managementFocusRight:
            switch managementNavigationScope {
            case .mainRow:
                return canExecute(.focusPaneRight)
            case .drawer(let parentPaneId):
                return visibleDrawerPaneIds(for: parentPaneId).count > 1
            }
        case .managementEnterDrawer, .managementOpenDrawer:
            return activeMainPaneId() != nil
        case .managementExitDrawer, .managementExitMode:
            if case .drawer = managementNavigationScope {
                return true
            }
            return command == .managementExitMode
        case .managementCreateTerminal:
            switch managementNavigationScope {
            case .mainRow:
                return canExecute(.newTerminalInTab)
            case .drawer(let parentPaneId):
                return store.paneAtom.pane(parentPaneId)?.drawer != nil
            }
        case .managementCreateBrowser:
            return managementParentPaneId() != nil
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

    /// Create a new tab by cloning the active pane's worktree/repo context.
    /// Falls back to the first available worktree if no active pane exists.
    private func addNewTab() {
        // Try to clone context from the active pane
        if let activeTabId = store.tabLayoutAtom.activeTabId,
            let tab = store.tabLayoutAtom.tab(activeTabId),
            let activePaneId = tab.activePaneId,
            let pane = store.paneAtom.pane(activePaneId)
        {
            if let worktreeId = worktreeIdForNewTab(from: pane) {
                dispatchAction(
                    .openNewTerminalInTab(
                        worktreeId: worktreeId,
                        launchDirectory: pane.metadata.cwd,
                        title: pane.metadata.title
                    )
                )
                return
            }

            dispatchAction(.openFloatingTerminal(launchDirectory: pane.metadata.cwd, title: pane.metadata.title))
            return
        }

        // Fallback: use the first worktree from the first repo
        if let worktree = store.repositoryTopologyAtom.repos.first?.worktrees.first {
            dispatchAction(.openNewTerminalInTab(worktreeId: worktree.id, launchDirectory: nil, title: nil))
            return
        }

        dispatchAction(.openFloatingTerminal(launchDirectory: nil, title: nil))
    }

    private func worktreeIdForNewTab(from pane: Pane) -> UUID? {
        if let worktreeId = pane.worktreeId {
            return worktreeId
        }

        return store.repositoryTopologyAtom.repoAndWorktree(containing: pane.metadata.facets.cwd)?.worktree.id
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
            isManagementModeActive: atom(\.managementMode).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id))
        )

        switch WorkspaceCommandValidator.validate(action, state: snapshot) {
        case .success:
            executor.execute(action)
        case .failure(let error):
            ghosttyLogger.warning("Action rejected: \(error)")
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
            let name = Self.nextArrangementName(existing: tab.arrangements)
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

    // MARK: - Arrangement Naming

    /// Generate a unique arrangement name by finding the next unused index.
    static func nextArrangementName(existing: [PaneArrangement]) -> String {
        let existingNames = Set(existing.map(\.name))
        var index = existing.count
        while existingNames.contains("Arrangement \(index)") {
            index += 1
        }
        return "Arrangement \(index)"
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
        case .toggleManagementMode:
            let wasManagementModeActive = atom(\.managementMode).isActive
            atom(\.managementMode).toggle()
            if !wasManagementModeActive {
                managementNavigationScope = .mainRow
            }
            return true

        case .managementFocusLeft:
            handleManagementMoveLeft()
            return true

        case .managementFocusRight:
            handleManagementMoveRight()
            return true

        case .managementEnterDrawer:
            handleManagementMoveDown()
            return true

        case .managementExitDrawer:
            handleManagementMoveUp()
            return true

        case .managementOpenDrawer:
            handleManagementMoveDown()
            return true

        case .managementCreateTerminal:
            handleManagementCreateTerminal()
            return true

        case .managementCreateBrowser:
            handleManagementCreateBrowser()
            return true

        case .managementExitMode:
            atom(\.managementMode).deactivate()
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
        case .addRepo, .addFolder, .toggleSidebar, .filterSidebar, .signInGitHub, .signInGoogle:
            break
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
            let name = Self.nextArrangementName(existing: tab.arrangements)
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
            .selectTab, .focusPane:
            break  // Handled via drill-in (target selection in command bar)
        default:
            break
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

    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .managementFocusLeft, .managementFocusRight, .managementEnterDrawer,
            .managementExitDrawer, .managementOpenDrawer,
            .managementCreateTerminal, .managementCreateBrowser, .managementExitMode:
            return canExecuteManagementCommand(command)
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
                isManagementModeActive: atom(\.managementMode).isActive,
                knownRepoIds: Set(store.repositoryTopologyAtom.repos.map(\.id)),
                knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id))
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
