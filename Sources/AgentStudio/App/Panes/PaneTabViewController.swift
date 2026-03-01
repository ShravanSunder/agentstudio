import AppKit
import GhosttyKit
import Observation
import SwiftUI

/// Tab-based terminal controller with custom Ghostty-style tab bar.
///
/// PaneTabViewController is a composition-oriented controller in `App/`. It reads
/// from WorkspaceStore for state and routes user actions through the validated
/// ActionExecutor pipeline. Most flow changes are dispatched, while AppKit-only
/// concerns (focus, observers, empty-state visibility, tab bar coordination) stay
/// local. It also handles direct tab-order updates (`store.moveTab`) from drag
/// interactions as a UI-only mutation.
@MainActor
class PaneTabViewController: NSViewController, CommandHandler {
    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let executor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry

    // MARK: - View State

    private var tabBarHostingView: DraggableTabBarHostingView!
    private var terminalContainer: NSView!
    private var emptyStateView: NSView?

    /// SwiftUI hosting view for the split container (created once, observes store via @Observable)
    private var splitHostingView: NSHostingView<ActiveTabContent>?

    /// Local event monitor for arrangement bar keyboard shortcut
    private var arrangementBarEventMonitor: Any?
    private var notificationTasks: [Task<Void, Never>] = []

    /// Focus tracking — only refocus when the active tab or pane actually changes
    private var lastFocusedTabId: UUID?
    private var lastFocusedPaneId: UUID?

    // MARK: - Init

    init(
        store: WorkspaceStore, executor: ActionExecutor,
        tabBarAdapter: TabBarAdapter, viewRegistry: ViewRegistry
    ) {
        self.store = store
        self.executor = executor
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true

        // Create terminal container FIRST (so it's behind tab bar)
        terminalContainer = NSView()
        terminalContainer.wantsLayer = true
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.layer?.cornerRadius = 8
        terminalContainer.layer?.masksToBounds = true
        containerView.addSubview(terminalContainer)

        // Create custom tab bar AFTER (so it's on top visually)
        let tabBar = CustomTabBar(
            adapter: tabBarAdapter,
            onSelect: { [weak self] tabId in
                self?.dispatchAction(.selectTab(tabId: tabId))
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
            onPaneAction: { [weak self] action in
                self?.dispatchAction(action)
            },
            onSaveArrangement: { [weak self] tabId in
                guard let self, let tab = self.store.tab(tabId) else { return }
                let name = Self.nextArrangementName(existing: tab.arrangements)
                self.dispatchAction(
                    .createArrangement(
                        tabId: tabId, name: name, paneIds: Set(tab.paneIds)
                    ))
            },
            onOpenRepoInTab: {
                postAppEvent(.showCommandBarRepos)
            }
        )
        tabBarHostingView = DraggableTabBarHostingView(rootView: tabBar)
        tabBarHostingView.configure(adapter: tabBarAdapter) { [weak self] fromId, toIndex in
            self?.handleTabReorder(fromId: fromId, toIndex: toIndex)
        }
        tabBarHostingView.canPreviewPaneDropAtIndex = { [weak self] payload, targetTabIndex in
            self?.canPreviewTabBarPaneDrop(payload: payload, targetTabIndex: targetTabIndex) ?? false
        }
        tabBarHostingView.commitPaneDropAtIndex = { [weak self] payload, targetTabIndex in
            self?.commitTabBarPaneDrop(payload: payload, targetTabIndex: targetTabIndex) ?? false
        }
        tabBarHostingView.dragPayloadProvider = { [weak self] tabId in
            self?.createDragPayload(for: tabId)
        }
        tabBarHostingView.onSelect = { [weak self] tabId in
            self?.dispatchAction(.selectTab(tabId: tabId))
        }
        tabBarHostingView.translatesAutoresizingMaskIntoConstraints = false
        tabBarHostingView.wantsLayer = true
        containerView.addSubview(tabBarHostingView)

        // Create empty state view
        let emptyView = createEmptyStateView()
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(emptyView)
        self.emptyStateView = emptyView

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

        // Create stable SwiftUI content view — observes store directly via @Observable.
        // Created once; @Observable tracking handles all re-renders automatically.
        setupSplitContentView()

        // Observe store for AppKit-level concerns (empty state visibility, focus management)
        updateEmptyState()
        observeForAppKitState()

        setupNotificationObservers()

        // Cmd+E for management mode — handled via command pipeline (key event monitor)
        arrangementBarEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil else { return event }
            // Cmd+E toggles management mode (negative modifier check: only bare Cmd+E)
            if event.modifierFlags.contains([.command]),
                !event.modifierFlags.contains([.shift, .option, .control]),
                event.charactersIgnoringModifiers == "e"
            {
                CommandDispatcher.shared.dispatch(.toggleManagementMode)
                return nil
            }
            return event
        }

    }

    private func setupNotificationObservers() {
        setupAppNotificationObservers()
    }

    private func setupAppNotificationObservers() {
        notificationTasks.append(
            Task { [weak self] in
                guard let self else { return }
                let stream = await AppEventBus.shared.subscribe()
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .terminalProcessTerminated(let worktreeId, _):
                        self.handleProcessTerminated(worktreeId: worktreeId)
                    case .selectTabById(let tabId, let paneId):
                        self.handleSelectTabById(tabId: tabId, paneId: paneId)
                    case .undoCloseTabRequested:
                        self.handleUndoCloseTab()
                    case .extractPaneRequested(let tabId, let paneId, let targetTabIndex):
                        self.handleExtractPaneRequested(tabId: tabId, paneId: paneId, targetTabIndex: targetTabIndex)
                    case .movePaneToTabRequested(let paneId, let sourceTabId, let targetTabId):
                        self.handleMovePaneToTabRequested(
                            paneId: paneId,
                            sourceTabId: sourceTabId,
                            targetTabId: targetTabId
                        )
                    case .repairSurfaceRequested(let paneId):
                        self.handleRepairSurfaceRequested(paneId: paneId)
                    case .refocusTerminalRequested:
                        self.handleRefocusTerminal()
                    case .openWebviewRequested:
                        self.handleOpenWebviewRequested()
                    default:
                        continue
                    }
                }
            })
    }

    private func handleOpenWebviewRequested() {
        executor.openWebview()
    }

    private func handleRepairSurfaceRequested(paneId: UUID) {
        dispatchAction(.repair(.recreateSurface(paneId: paneId)))
    }

    private func handleSelectTabById(tabId: UUID, paneId: UUID?) {
        dispatchAction(.selectTab(tabId: tabId))

        // If a specific pane was requested, focus it within the tab
        if let paneId {
            dispatchAction(.focusPane(tabId: tabId, paneId: paneId))
        }
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
    /// SwiftUI rendering is handled by ActiveTabContent via @Observable — this method
    /// only handles things that live outside the SwiftUI tree (NSView visibility, firstResponder).
    private func observeForAppKitState() {
        withObservationTracking {
            _ = self.store.tabs
            _ = self.store.activeTabId
        } onChange: {
            Task { @MainActor [weak self] in
                self?.handleAppKitStateChange()
                self?.observeForAppKitState()
            }
        }
    }

    private func handleAppKitStateChange() {
        updateEmptyState()

        // Deactivate management mode if no tabs
        if store.tabs.isEmpty && ManagementModeMonitor.shared.isActive {
            ManagementModeMonitor.shared.deactivate()
        }

        // Focus management: only refocus when active tab or pane actually changes
        let currentTabId = store.activeTabId
        let currentPaneId = currentTabId.flatMap { store.tab($0) }?.activePaneId

        if currentTabId != lastFocusedTabId || currentPaneId != lastFocusedPaneId {
            lastFocusedTabId = currentTabId
            lastFocusedPaneId = currentPaneId
            focusActivePane()
        }
    }

    /// Make the active pane's NSView the first responder and sync Ghostty focus state.
    private func focusActivePane() {
        guard let activeTabId = store.activeTabId,
            let tab = store.tab(activeTabId),
            let activePaneId = tab.activePaneId,
            let paneView = viewRegistry.view(for: activePaneId)
        else { return }

        RestoreTrace.log(
            "\(Self.self).focusActivePane tab=\(activeTabId) pane=\(activePaneId) paneClass=\(String(describing: type(of: paneView))) windowReady=\(paneView.window != nil)"
        )
        Task { @MainActor [weak paneView] in
            guard let paneView, paneView.window != nil else { return }
            paneView.window?.makeFirstResponder(paneView)
            RestoreTrace.log(
                "\(Self.self).focusActivePane async firstResponder paneClass=\(String(describing: type(of: paneView)))"
            )

            if let terminal = paneView as? AgentStudioTerminalView {
                SurfaceManager.shared.syncFocus(activeSurfaceId: terminal.surfaceId)
                RestoreTrace.log(
                    "\(Self.self).focusActivePane syncFocus activeSurface=\(terminal.surfaceId?.uuidString ?? "nil")")
            }
        }
    }

    // MARK: - Split Content View Setup

    /// Create the NSHostingView for ActiveTabContent once. @Observable handles all re-renders.
    private func setupSplitContentView() {
        let contentView = ActiveTabContent(
            store: store,
            viewRegistry: viewRegistry,
            action: { [weak self] action in self?.dispatchAction(action) },
            shouldAcceptDrop: { [weak self] payload, destPaneId, zone in
                self?.evaluateDropAcceptance(
                    payload: payload,
                    destPaneId: destPaneId,
                    zone: zone
                ) ?? false
            },
            onDrop: { [weak self] payload, destPaneId, zone in
                self?.handleSplitDrop(payload: payload, destPaneId: destPaneId, zone: zone)
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = [.minSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
        ])

        splitHostingView = hostingView
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
            destinationPane: store.pane(destPaneId),
            destinationPaneId: destPaneId,
            zone: zone,
            activeTabId: store.activeTabId,
            state: snapshot
        ) != nil
    }

    /// Handle a completed drop on a split pane.
    private func handleSplitDrop(payload: SplitDropPayload, destPaneId: UUID, zone: DropZone) {
        let snapshot = dragDropSnapshot()
        guard
            let plan = Self.splitDropCommitPlan(
                payload: payload,
                destinationPane: store.pane(destPaneId),
                destinationPaneId: destPaneId,
                zone: zone,
                activeTabId: store.activeTabId,
                state: snapshot
            )
        else {
            return
        }
        executeDropCommitPlan(plan)
    }

    private func canPreviewTabBarPaneDrop(payload: PaneDragPayload, targetTabIndex: Int) -> Bool {
        let snapshot = dragDropSnapshot()
        return Self.tabBarDropCommitPlan(
            payload: payload,
            targetTabIndex: targetTabIndex,
            state: snapshot
        ) != nil
    }

    private func commitTabBarPaneDrop(payload: PaneDragPayload, targetTabIndex: Int) -> Bool {
        let snapshot = dragDropSnapshot()
        guard
            let plan = Self.tabBarDropCommitPlan(
                payload: payload,
                targetTabIndex: targetTabIndex,
                state: snapshot
            )
        else {
            return false
        }

        executeDropCommitPlan(plan)
        return true
    }

    private func dragDropSnapshot() -> ActionStateSnapshot {
        let drawerParentByPaneId = store.panes.values.reduce(into: [UUID: UUID]()) { result, pane in
            guard let parentPaneId = pane.parentPaneId else { return }
            result[pane.id] = parentPaneId
        }

        return ActionResolver.snapshot(
            from: store.tabs,
            activeTabId: store.activeTabId,
            isManagementModeActive: ManagementModeMonitor.shared.isActive,
            knownWorktreeIds: Set(store.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneId
        )
    }

    private func executeDropCommitPlan(_ plan: DropCommitPlan) {
        switch plan {
        case .paneAction(let action):
            dispatchAction(action)
        case .moveTab(let tabId, let toIndex):
            moveTabThroughActionPipeline(tabId: tabId, toIndex: toIndex)
        case .extractPaneToTabThenMove(let paneId, let sourceTabId, let toIndex):
            let tabCountBefore = store.tabs.count
            dispatchAction(.extractPaneToTab(tabId: sourceTabId, paneId: paneId))
            guard
                store.tabs.count == tabCountBefore + 1,
                let extractedTabId = store.activeTabId
            else {
                return
            }
            moveTabThroughActionPipeline(tabId: extractedTabId, toIndex: toIndex)
        }
    }

    private func moveTabThroughActionPipeline(tabId: UUID, toIndex: Int) {
        guard let fromIndex = store.tabs.firstIndex(where: { $0.id == tabId }) else {
            return
        }

        let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        let clampedIndex = max(0, min(adjustedIndex, max(store.tabs.count - 1, 0)))
        let delta = clampedIndex - fromIndex

        if delta != 0 {
            dispatchAction(.moveTab(tabId: tabId, delta: delta))
        }
        dispatchAction(.selectTab(tabId: tabId))
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
    ) -> PaneAction? {
        let destinationPane = store.pane(destPaneId)
        let sourcePane: Pane? =
            if case .existingPane(let sourcePaneId, _) = payload.kind {
                store.pane(sourcePaneId)
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

    private func createEmptyStateView() -> NSView {
        PaneTabEmptyStateViewFactory.make(
            target: self,
            addRepoAction: #selector(addRepoAction),
            addFolderAction: #selector(addFolderAction)
        )
    }

    @objc private func addRepoAction() {
        postAppEvent(.addRepoRequested)
    }

    @objc private func addFolderAction() {
        postAppEvent(.addFolderRequested)
    }

    private func updateEmptyState() {
        let hasTerminals = !store.tabs.isEmpty
        tabBarHostingView.isHidden = !hasTerminals
        terminalContainer.isHidden = !hasTerminals
        emptyStateView?.isHidden = hasTerminals
    }

    // MARK: - New Tab

    /// Create a new tab by cloning the active pane's worktree/repo context.
    /// Falls back to the first available worktree if no active pane exists.
    private func addNewTab() {
        // Try to clone context from the active pane
        if let activeTabId = store.activeTabId,
            let tab = store.tab(activeTabId),
            let activePaneId = tab.activePaneId,
            let pane = store.pane(activePaneId),
            let worktreeId = pane.worktreeId,
            let repoId = pane.repoId,
            let worktree = store.worktree(worktreeId),
            let repo = store.repo(repoId)
        {
            executor.openNewTerminal(for: worktree, in: repo)
            return
        }

        // Fallback: use the first worktree from the first repo
        if let repo = store.repos.first,
            let worktree = repo.worktrees.first
        {
            executor.openNewTerminal(for: worktree, in: repo)
        }
    }

    // MARK: - Terminal Management

    func openTerminal(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openWorktree(worktreeId: worktree.id))
    }

    func openNewTerminal(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openNewTerminalInTab(worktreeId: worktree.id))
    }

    func openWorktreeInPane(for worktree: Worktree, in _: Repo) {
        dispatchAction(.openWorktreeInPane(worktreeId: worktree.id))
    }

    func closeTerminal(for worktreeId: UUID) {
        // Find the tab containing this worktree
        guard
            let tab = store.tabs.first(where: { tab in
                tab.paneIds.contains { id in
                    store.pane(id)?.worktreeId == worktreeId
                }
            })
        else { return }

        // Single-pane tab: close the whole tab (ActionValidator rejects .closePane
        // for single-pane tabs). Multi-pane: close just the pane.
        if tab.isSplit {
            guard
                let matchedPaneId = tab.paneIds.first(where: { id in
                    store.pane(id)?.worktreeId == worktreeId
                })
            else { return }
            dispatchAction(.closePane(tabId: tab.id, paneId: matchedPaneId))
        } else {
            dispatchAction(.closeTab(tabId: tab.id))
        }
    }

    func closeActiveTab() {
        guard let activeId = store.activeTabId else { return }
        dispatchAction(.closeTab(tabId: activeId))
    }

    func selectTab(at index: Int) {
        let tabs = store.tabs
        guard index >= 0, index < tabs.count else { return }
        dispatchAction(.selectTab(tabId: tabs[index].id))
    }

    // MARK: - Validated Action Pipeline

    /// Central entry point: validates a PaneAction and executes it if valid.
    /// All input sources (keyboard, menu, drag-drop, commands) converge here.
    private func dispatchAction(_ action: PaneAction) {
        let snapshot = ActionResolver.snapshot(
            from: store.tabs,
            activeTabId: store.activeTabId,
            isManagementModeActive: ManagementModeMonitor.shared.isActive,
            knownWorktreeIds: Set(store.repos.flatMap(\.worktrees).map(\.id))
        )

        switch ActionValidator.validate(action, state: snapshot) {
        case .success:
            executor.execute(action)
        case .failure(let error):
            ghosttyLogger.warning("Action rejected: \(error)")
        }
    }

    // MARK: - Tab Commands

    /// Route tab context menu commands through the validated pipeline.
    private func handleTabCommand(_ command: AppCommand, tabId: UUID) {
        let action: PaneAction?

        switch command {
        case .closeTab:
            action = .closeTab(tabId: tabId)
        case .breakUpTab:
            action = .breakUpTab(tabId: tabId)
        case .equalizePanes:
            action = .equalizePanes(tabId: tabId)
        case .splitRight, .splitBelow, .splitLeft, .splitAbove:
            // Resolve split direction using the target tab's active pane
            guard let tab = store.tab(tabId),
                let paneId = tab.activePaneId
            else { return }
            let direction: SplitNewDirection = {
                switch command {
                case .splitRight: return .right
                case .splitBelow: return .down
                case .splitLeft: return .left
                case .splitAbove: return .up
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
            guard let tab = store.tab(tabId) else { return }
            let name = Self.nextArrangementName(existing: tab.arrangements)
            action = .createArrangement(
                tabId: tabId, name: name, paneIds: Set(tab.paneIds)
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
        moveTabThroughActionPipeline(tabId: fromId, toIndex: toIndex)
    }

    // MARK: - Drag Payload

    private func createDragPayload(for tabId: UUID) -> TabDragPayload? {
        guard store.tab(tabId) != nil else { return nil }
        return TabDragPayload(tabId: tabId)
    }

    // MARK: - Process Termination

    private func handleProcessTerminated(worktreeId: UUID?) {
        guard let worktreeId else { return }
        closeTerminal(for: worktreeId)
    }

    private func handleExtractPaneRequested(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        guard let targetTabIndex else { return }
        let payload = PaneDragPayload(
            paneId: paneId,
            tabId: tabId,
            drawerParentPaneId: store.pane(paneId)?.parentPaneId
        )
        _ = commitTabBarPaneDrop(payload: payload, targetTabIndex: targetTabIndex)
    }

    private func handleMovePaneToTabRequested(paneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        dispatchMovePaneToTab(sourcePaneId: paneId, sourceTabId: sourceTabId, targetTabId: targetTabId)
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
    ) -> PaneAction? {
        let resolvedSourceTabId: UUID? =
            if let sourceTabId, store.tab(sourceTabId)?.paneIds.contains(sourcePaneId) == true {
                sourceTabId
            } else {
                store.tabs.first(where: { $0.paneIds.contains(sourcePaneId) })?.id
            }

        guard let resolvedSourceTabId else { return nil }
        guard resolvedSourceTabId != targetTabId else { return nil }
        guard let targetTab = store.tab(targetTabId) else { return nil }
        guard let targetPaneId = targetTab.activePaneId ?? targetTab.paneIds.first else { return nil }

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

    // MARK: - Refocus Terminal

    private func handleRefocusTerminal() {
        guard let activeTabId = store.activeTabId,
            let tab = store.tab(activeTabId),
            let activePaneId = tab.activePaneId,
            let paneView = viewRegistry.view(for: activePaneId)
        else { return }
        RestoreTrace.log("\(Self.self).handleRefocusTerminal tab=\(activeTabId) pane=\(activePaneId)")
        Task { @MainActor [weak paneView] in
            guard let paneView, paneView.window != nil else { return }
            paneView.window?.makeFirstResponder(paneView)
            RestoreTrace.log("\(Self.self).handleRefocusTerminal async firstResponder set")

            if let terminal = paneView as? AgentStudioTerminalView {
                SurfaceManager.shared.syncFocus(activeSurfaceId: terminal.surfaceId)
                RestoreTrace.log(
                    "\(Self.self).handleRefocusTerminal syncFocus activeSurface=\(terminal.surfaceId?.uuidString ?? "nil")"
                )
            }
        }
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

    // MARK: - CommandHandler Conformance

    func execute(_ command: AppCommand) {
        // Try the validated pipeline for pane/tab structural actions
        if let action = ActionResolver.resolve(
            command: command, tabs: store.tabs, activeTabId: store.activeTabId
        ) {
            dispatchAction(action)
            return
        }

        // Non-pane commands handled directly
        switch command {
        case .toggleManagementMode:
            ManagementModeMonitor.shared.toggle()

        case .addRepo:
            postAppEvent(.addRepoRequested)
        case .addFolder:
            postAppEvent(.addFolderRequested)
        case .filterSidebar:
            postAppEvent(.filterSidebarRequested)
        case .addDrawerPane:
            guard let tabId = store.activeTabId,
                let tab = store.tab(tabId),
                let paneId = tab.activePaneId
            else { break }
            dispatchAction(.addDrawerPane(parentPaneId: paneId))

        case .toggleDrawer:
            guard let tabId = store.activeTabId,
                let tab = store.tab(tabId),
                let paneId = tab.activePaneId
            else { break }
            dispatchAction(.toggleDrawer(paneId: paneId))

        case .closeDrawerPane:
            guard let tabId = store.activeTabId,
                let tab = store.tab(tabId),
                let paneId = tab.activePaneId,
                let pane = store.pane(paneId),
                let drawer = pane.drawer,
                let activeDrawerPaneId = drawer.activePaneId
            else { break }
            dispatchAction(.removeDrawerPane(parentPaneId: paneId, drawerPaneId: activeDrawerPaneId))

        case .saveArrangement:
            guard let tabId = store.activeTabId,
                let tab = store.tab(tabId)
            else { break }
            let name = Self.nextArrangementName(existing: tab.arrangements)
            dispatchAction(
                .createArrangement(
                    tabId: tabId, name: name, paneIds: Set(tab.paneIds)
                ))

        case .openWebview:
            executor.openWebview()
        case .signInGitHub:
            postAppEvent(.signInRequested(provider: OAuthProvider.github.rawValue))
        case .signInGoogle:
            postAppEvent(.signInRequested(provider: OAuthProvider.google.rawValue))
        case .newTerminalInTab, .newFloatingTerminal,
            .removeRepo, .refreshWorktrees,
            .toggleSidebar, .quickFind, .commandBar,
            .openNewTerminalInTab, .openWorktree, .openWorktreeInPane,
            .switchArrangement, .deleteArrangement, .renameArrangement,
            .navigateDrawerPane, .movePaneToTab:
            break  // Handled via drill-in (target selection in command bar)
        default:
            break
        }
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        // Build a targeted PaneAction based on the command and target
        let action: PaneAction? = {
            switch (command, targetType) {
            case (.closeTab, .tab):
                return .closeTab(tabId: target)
            case (.breakUpTab, .tab):
                return .breakUpTab(tabId: target)
            case (.closePane, .pane), (.closePane, .floatingTerminal):
                guard let tab = store.tabs.first(where: { $0.paneIds.contains(target) })
                else { return nil }
                return .closePane(tabId: tab.id, paneId: target)
            case (.extractPaneToTab, .pane), (.extractPaneToTab, .floatingTerminal):
                guard let tab = store.tabs.first(where: { $0.paneIds.contains(target) })
                else { return nil }
                return .extractPaneToTab(tabId: tab.id, paneId: target)
            case (.movePaneToTab, .tab):
                guard let activeTabId = store.activeTabId,
                    let activePaneId = store.tab(activeTabId)?.activePaneId
                else { return nil }
                return makeMovePaneToTabAction(
                    sourcePaneId: activePaneId,
                    sourceTabId: activeTabId,
                    targetTabId: target
                )
            case (.switchArrangement, .tab):
                guard let tabId = store.activeTabId else { return nil }
                return .switchArrangement(tabId: tabId, arrangementId: target)
            case (.deleteArrangement, .tab):
                guard let tabId = store.activeTabId else { return nil }
                return .removeArrangement(tabId: tabId, arrangementId: target)
            case (.renameArrangement, .tab):
                // Name input will be added in a later task; for now, just select the target
                return nil
            case (.navigateDrawerPane, .pane):
                guard let tabId = store.activeTabId,
                    let tab = store.tab(tabId),
                    let paneId = tab.activePaneId
                else { return nil }
                return .setActiveDrawerPane(parentPaneId: paneId, drawerPaneId: target)
            case (.openWorktree, .worktree):
                return .openWorktree(worktreeId: target)
            case (.openNewTerminalInTab, .worktree):
                return .openNewTerminalInTab(worktreeId: target)
            case (.openWorktreeInPane, .worktree):
                return .openWorktreeInPane(worktreeId: target)
            default:
                return nil
            }
        }()

        if let action {
            dispatchAction(action)
            return
        }

        // Targeted non-pane commands (e.g. from command bar)
        switch (command, targetType) {
        default:
            execute(command)
        }
    }

    func canExecute(_ command: AppCommand) -> Bool {
        // Try resolving — if it resolves, validate it
        if let action = ActionResolver.resolve(
            command: command, tabs: store.tabs, activeTabId: store.activeTabId
        ) {
            let snapshot = ActionResolver.snapshot(
                from: store.tabs,
                activeTabId: store.activeTabId,
                isManagementModeActive: ManagementModeMonitor.shared.isActive,
                knownWorktreeIds: Set(store.repos.flatMap(\.worktrees).map(\.id))
            )
            switch ActionValidator.validate(action, state: snapshot) {
            case .success: return true
            case .failure: return false
            }
        }
        // Non-pane commands are always available
        return true
    }
}
