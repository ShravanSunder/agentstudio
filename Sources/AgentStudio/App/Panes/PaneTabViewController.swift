// swiftlint:disable file_length type_body_length
import AppKit
import GhosttyKit
import Observation
import SwiftUI

/// Tab-based terminal controller with custom Ghostty-style tab bar.
///
/// PaneTabViewController is a dispatch-only controller — it reads from WorkspaceStore
/// and dispatches actions through ActionExecutor. It never mutates
/// store or runtime state directly.
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

        // Listen for process termination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProcessTerminated(_:)),
            name: .terminalProcessTerminated,
            object: nil
        )

        // Listen for tab selection by ID (from drag view)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectTabById(_:)),
            name: .selectTabById,
            object: nil
        )

        // Listen for undo close tab
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUndoCloseTab),
            name: .undoCloseTabRequested,
            object: nil
        )

        // Listen for pane extract (from tab bar pane drop)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExtractPaneRequested(_:)),
            name: .extractPaneRequested,
            object: nil
        )

        // Listen for surface repair requests (from error overlay)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRepairSurfaceRequested(_:)),
            name: .repairSurfaceRequested,
            object: nil
        )

        // Listen for refocus terminal requests (e.g. after sidebar filter dismiss)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRefocusTerminal),
            name: .refocusTerminalRequested,
            object: nil
        )

        // Cmd+E for edit mode — handled via command pipeline (key event monitor)
        arrangementBarEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil else { return event }
            // Cmd+E toggles edit mode (negative modifier check: only bare Cmd+E)
            if event.modifierFlags.contains([.command]),
                !event.modifierFlags.contains([.shift, .option, .control]),
                event.charactersIgnoringModifiers == "e"
            {
                CommandDispatcher.shared.dispatch(.toggleEditMode)
                return nil
            }
            return event
        }

        // Listen for open webview requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenWebviewRequested),
            name: .openWebviewRequested,
            object: nil
        )

        // Ghostty split and tab action observers
        let ghosttyObservers: [(Notification.Name, Selector)] = [
            (.ghosttyNewSplit, #selector(handleGhosttyNewSplit(_:))),
            (.ghosttyGotoSplit, #selector(handleGhosttyGotoSplit(_:))),
            (.ghosttyResizeSplit, #selector(handleGhosttyResizeSplit(_:))),
            (.ghosttyEqualizeSplits, #selector(handleGhosttyEqualizeSplits(_:))),
            (.ghosttyToggleSplitZoom, #selector(handleGhosttyToggleSplitZoom(_:))),
            (.ghosttyCloseTab, #selector(handleGhosttyCloseTab(_:))),
            (.ghosttyGotoTab, #selector(handleGhosttyGotoTab(_:))),
            (.ghosttyMoveTab, #selector(handleGhosttyMoveTab(_:))),
        ]
        for (name, selector) in ghosttyObservers {
            NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
        }
    }

    @objc private func handleOpenWebviewRequested() {
        executor.openWebview()
    }

    @objc private func handleRepairSurfaceRequested(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let paneId = userInfo["paneId"] as? UUID
        else {
            return
        }
        dispatchAction(.repair(.recreateSurface(paneId: paneId)))
    }

    @objc private func handleSelectTabById(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let tabId = userInfo["tabId"] as? UUID
        else {
            return
        }
        dispatchAction(.selectTab(tabId: tabId))

        // If a specific pane was requested, focus it within the tab
        if let paneId = userInfo["paneId"] as? UUID {
            dispatchAction(.focusPane(tabId: tabId, paneId: paneId))
        }
    }

    deinit {
        if let monitor = arrangementBarEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
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

        // Deactivate edit mode if no tabs
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
        DispatchQueue.main.async { [weak paneView] in
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
            shouldAcceptDrop: { [weak self] destPaneId, zone in
                self?.evaluateDropAcceptance(destPaneId: destPaneId, zone: zone) ?? false
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
    private func evaluateDropAcceptance(destPaneId: UUID, zone: DropZone) -> Bool {
        // New terminal drags have no draggingTabId — always valid
        guard let draggingTabId = tabBarAdapter.draggingTabId else { return true }
        guard let tabId = store.activeTabId else { return false }

        let snapshot = ActionResolver.snapshot(
            from: store.tabs,
            activeTabId: store.activeTabId,
            isManagementModeActive: ManagementModeMonitor.shared.isActive
        )
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: draggingTabId
            ))
        guard
            let action = ActionResolver.resolveDrop(
                payload: payload,
                destinationPaneId: destPaneId,
                destinationTabId: tabId,
                zone: zone,
                state: snapshot
            )
        else { return false }

        if case .success = ActionValidator.validate(action, state: snapshot) {
            return true
        }
        return false
    }

    /// Handle a completed drop on a split pane.
    private func handleSplitDrop(payload: SplitDropPayload, destPaneId: UUID, zone: DropZone) {
        guard let tabId = store.activeTabId else { return }

        let snapshot = ActionResolver.snapshot(
            from: store.tabs,
            activeTabId: store.activeTabId,
            isManagementModeActive: ManagementModeMonitor.shared.isActive
        )
        if let action = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: destPaneId,
            destinationTabId: tabId,
            zone: zone,
            state: snapshot
        ) {
            dispatchAction(action)
        }
    }

    // MARK: - Empty State

    private func createEmptyStateView() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Icon with gradient background
        let iconContainer = NSView()
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 20
        iconContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Terminal")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 80),
            iconContainer.heightAnchor.constraint(equalToConstant: 80),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
        ])

        // Title
        let titleLabel = NSTextField(labelWithString: "Welcome to AgentStudio")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor

        // Subtitle
        let subtitleLabel = NSTextField(
            wrappingLabelWithString:
                "Manage your AI agent worktrees with integrated terminal sessions.\nDouble-click a worktree to open a terminal."
        )
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3

        // Keyboard shortcut hint
        let hintLabel = NSTextField(labelWithString: "Tip: Use Cmd+Shift+O to add a repo")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor

        // Add Repo button
        let addButton = NSButton(title: "Add Repo...", target: self, action: #selector(addRepoAction))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .large
        addButton.keyEquivalent = "\r"

        stackView.addArrangedSubview(iconContainer)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(addButton)
        stackView.addArrangedSubview(hintLabel)

        stackView.setCustomSpacing(24, after: iconContainer)
        stackView.setCustomSpacing(8, after: titleLabel)
        stackView.setCustomSpacing(24, after: subtitleLabel)
        stackView.setCustomSpacing(12, after: addButton)

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])

        return container
    }

    @objc private func addRepoAction() {
        NotificationCenter.default.post(name: .addRepoRequested, object: nil)
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

    func openTerminal(for worktree: Worktree, in repo: Repo) {
        executor.openTerminal(for: worktree, in: repo)
    }

    func openNewTerminal(for worktree: Worktree, in repo: Repo) {
        executor.openNewTerminal(for: worktree, in: repo)
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
            isManagementModeActive: ManagementModeMonitor.shared.isActive
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
        store.moveTab(fromId: fromId, toIndex: toIndex)
    }

    // MARK: - Drag Payload

    private func createDragPayload(for tabId: UUID) -> TabDragPayload? {
        guard store.tab(tabId) != nil else { return nil }
        return TabDragPayload(tabId: tabId)
    }

    // MARK: - Process Termination

    @objc private func handleProcessTerminated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let worktreeId = userInfo["worktreeId"] as? UUID
        else {
            return
        }
        closeTerminal(for: worktreeId)
    }

    @objc private func handleExtractPaneRequested(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let tabId = userInfo["tabId"] as? UUID,
            let paneId = userInfo["paneId"] as? UUID
        else {
            return
        }
        dispatchAction(.extractPaneToTab(tabId: tabId, paneId: paneId))
    }

    // MARK: - Undo Close Tab

    @objc private func handleUndoCloseTab() {
        executor.undoCloseTab()
    }

    // MARK: - Refocus Terminal

    @objc private func handleRefocusTerminal() {
        guard let activeTabId = store.activeTabId,
            let tab = store.tab(activeTabId),
            let activePaneId = tab.activePaneId,
            let paneView = viewRegistry.view(for: activePaneId)
        else { return }
        RestoreTrace.log("\(Self.self).handleRefocusTerminal tab=\(activeTabId) pane=\(activePaneId)")
        DispatchQueue.main.async { [weak paneView] in
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

    // MARK: - Ghostty Target Resolution

    private func resolveGhosttyTarget(_ surfaceView: Ghostty.SurfaceView) -> (tabId: UUID, paneId: UUID)? {
        guard let surfaceId = SurfaceManager.shared.surfaceId(forView: surfaceView) else {
            ghosttyLogger.warning("[\(Self.self)] resolveGhosttyTarget: surfaceView not found in SurfaceManager")
            return nil
        }
        guard let paneId = SurfaceManager.shared.paneId(for: surfaceId) else {
            ghosttyLogger.warning("[\(Self.self)] resolveGhosttyTarget: no pane for surfaceId \(surfaceId)")
            return nil
        }
        guard let tab = store.tabs.first(where: { $0.paneIds.contains(paneId) }) else {
            ghosttyLogger.warning("[\(Self.self)] resolveGhosttyTarget: no tab contains pane \(paneId)")
            return nil
        }
        return (tab.id, paneId)
    }

    // MARK: - Ghostty Split Action Handlers

    @objc private func handleGhosttyNewSplit(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let dirValue = notification.userInfo?["direction"] as? UInt32,
            let direction = mapGhosttyNewSplitDirection(dirValue),
            let (tabId, paneId) = resolveGhosttyTarget(surfaceView)
        else { return }
        dispatchAction(
            .insertPane(
                source: .newTerminal, targetTabId: tabId,
                targetPaneId: paneId, direction: direction))
    }

    @objc private func handleGhosttyGotoSplit(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let gotoValue = notification.userInfo?["goto"] as? UInt32,
            let command = mapGhosttyGotoSplit(gotoValue),
            let (tabId, _) = resolveGhosttyTarget(surfaceView)
        else { return }
        if let action = ActionResolver.resolve(command: command, tabs: store.tabs, activeTabId: tabId) {
            dispatchAction(action)
        }
    }

    @objc private func handleGhosttyResizeSplit(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let amount = notification.userInfo?["amount"] as? UInt16,
            let dirValue = notification.userInfo?["direction"] as? UInt32,
            let direction = mapGhosttyResizeDirection(dirValue),
            let (tabId, paneId) = resolveGhosttyTarget(surfaceView)
        else { return }
        dispatchAction(
            .resizePaneByDelta(
                tabId: tabId, paneId: paneId,
                direction: direction, amount: amount))
    }

    @objc private func handleGhosttyEqualizeSplits(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let (tabId, _) = resolveGhosttyTarget(surfaceView)
        else { return }
        dispatchAction(.equalizePanes(tabId: tabId))
    }

    @objc private func handleGhosttyToggleSplitZoom(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let (tabId, paneId) = resolveGhosttyTarget(surfaceView)
        else { return }
        dispatchAction(.toggleSplitZoom(tabId: tabId, paneId: paneId))
    }

    // MARK: - Ghostty Tab Action Handlers

    @objc private func handleGhosttyCloseTab(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let modeValue = notification.userInfo?["mode"] as? UInt32,
            let (tabId, _) = resolveGhosttyTarget(surfaceView)
        else { return }
        let tabs = store.tabs
        switch modeValue {
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS.rawValue:
            dispatchAction(.closeTab(tabId: tabId))
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER.rawValue:
            for tab in tabs where tab.id != tabId {
                dispatchAction(.closeTab(tabId: tab.id))
            }
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT.rawValue:
            guard let currentIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return }
            for tab in tabs[(currentIndex + 1)...] {
                dispatchAction(.closeTab(tabId: tab.id))
            }
        default:
            ghosttyLogger.warning("[\(Self.self)] Unknown close_tab mode: \(modeValue)")
        }
    }

    @objc private func handleGhosttyGotoTab(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let targetValue = notification.userInfo?["target"] as? Int32,
            let (tabId, _) = resolveGhosttyTarget(surfaceView)
        else { return }

        let tabs = store.tabs
        let action: PaneAction?

        switch targetValue {
        case GHOSTTY_GOTO_TAB_PREVIOUS.rawValue:
            action = ActionResolver.resolve(command: .prevTab, tabs: tabs, activeTabId: tabId)
        case GHOSTTY_GOTO_TAB_NEXT.rawValue:
            action = ActionResolver.resolve(command: .nextTab, tabs: tabs, activeTabId: tabId)
        case GHOSTTY_GOTO_TAB_LAST.rawValue:
            if let lastTab = tabs.last {
                action = .selectTab(tabId: lastTab.id)
            } else {
                action = nil
            }
        default:
            // Ghostty uses 1-indexed tab numbers for positive values.
            // Out-of-range snaps to the last tab (matches Ghostty's TerminalController).
            guard targetValue >= 1 else {
                ghosttyLogger.warning("[\(Self.self)] goto_tab index \(targetValue) out of range")
                action = nil
                break
            }
            let index = min(Int(targetValue - 1), tabs.count - 1)
            action = .selectTab(tabId: tabs[index].id)
        }

        if let action { dispatchAction(action) }
    }

    @objc private func handleGhosttyMoveTab(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let amount = notification.userInfo?["amount"] as? Int,
            let (tabId, _) = resolveGhosttyTarget(surfaceView)
        else { return }
        dispatchAction(.moveTab(tabId: tabId, delta: amount))
    }

    // MARK: - Ghostty Enum Mapping

    private func mapGhosttyNewSplitDirection(_ raw: UInt32) -> SplitNewDirection? {
        switch raw {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT.rawValue: return .right
        case GHOSTTY_SPLIT_DIRECTION_DOWN.rawValue: return .down
        case GHOSTTY_SPLIT_DIRECTION_LEFT.rawValue: return .left
        case GHOSTTY_SPLIT_DIRECTION_UP.rawValue: return .up
        default:
            ghosttyLogger.warning("[\(Self.self)] Unknown split direction: \(raw)")
            return nil
        }
    }

    private func mapGhosttyGotoSplit(_ raw: UInt32) -> AppCommand? {
        switch raw {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS.rawValue: return .focusPrevPane
        case GHOSTTY_GOTO_SPLIT_NEXT.rawValue: return .focusNextPane
        case GHOSTTY_GOTO_SPLIT_UP.rawValue: return .focusPaneUp
        case GHOSTTY_GOTO_SPLIT_DOWN.rawValue: return .focusPaneDown
        case GHOSTTY_GOTO_SPLIT_LEFT.rawValue: return .focusPaneLeft
        case GHOSTTY_GOTO_SPLIT_RIGHT.rawValue: return .focusPaneRight
        default:
            ghosttyLogger.warning("[\(Self.self)] Unknown goto_split value: \(raw)")
            return nil
        }
    }

    private func mapGhosttyResizeDirection(_ raw: UInt32) -> SplitResizeDirection? {
        switch raw {
        case GHOSTTY_RESIZE_SPLIT_UP.rawValue: return .up
        case GHOSTTY_RESIZE_SPLIT_DOWN.rawValue: return .down
        case GHOSTTY_RESIZE_SPLIT_LEFT.rawValue: return .left
        case GHOSTTY_RESIZE_SPLIT_RIGHT.rawValue: return .right
        default:
            ghosttyLogger.warning("[\(Self.self)] Unknown resize direction: \(raw)")
            return nil
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
        case .toggleEditMode:
            ManagementModeMonitor.shared.toggle()

        case .addRepo:
            NotificationCenter.default.post(name: .addRepoRequested, object: nil)
        case .filterSidebar:
            NotificationCenter.default.post(name: .filterSidebarRequested, object: nil)
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
            NotificationCenter.default.post(name: .signInRequested, object: nil, userInfo: ["provider": "github"])
        case .signInGoogle:
            NotificationCenter.default.post(name: .signInRequested, object: nil, userInfo: ["provider": "google"])
        case .newTerminalInTab, .newFloatingTerminal,
            .removeRepo, .refreshWorktrees,
            .toggleSidebar, .quickFind, .commandBar,
            .openNewTerminalInTab,
            .switchArrangement, .deleteArrangement, .renameArrangement,
            .navigateDrawerPane:
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
        case (.openNewTerminalInTab, .worktree):
            guard let worktree = store.worktree(target),
                let repo = store.repo(containing: target)
            else {
                return
            }
            executor.openNewTerminal(for: worktree, in: repo)
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
                isManagementModeActive: ManagementModeMonitor.shared.isActive
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
