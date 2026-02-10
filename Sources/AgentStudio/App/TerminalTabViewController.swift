import AppKit
import SwiftUI
import GhosttyKit
import Combine

/// Tab-based terminal controller with custom Ghostty-style tab bar.
///
/// TTVC is a dispatch-only controller — it reads from WorkspaceStore
/// and dispatches actions through ActionExecutor. It never mutates
/// store or runtime state directly.
class TerminalTabViewController: NSViewController, CommandHandler {
    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let executor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry

    // MARK: - View State

    private var tabBarHostingView: DraggableTabBarHostingView!
    private var terminalContainer: NSView!
    private var emptyStateView: NSView?

    /// SwiftUI hosting view for the split container
    private var splitHostingView: NSHostingView<AnyView>?

    /// Combine subscriptions for store observation
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(store: WorkspaceStore, executor: ActionExecutor,
         tabBarAdapter: TabBarAdapter, viewRegistry: ViewRegistry) {
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
            onAdd: nil
        )
        tabBarHostingView = DraggableTabBarHostingView(rootView: tabBar)
        tabBarHostingView.configure(adapter: tabBarAdapter) { [weak self] fromId, toIndex in
            self?.handleTabReorder(fromId: fromId, toIndex: toIndex)
        }
        tabBarHostingView.dragPayloadProvider = { [weak self] tabId in
            self?.createDragPayload(for: tabId)
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
            emptyView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        view = containerView
        updateEmptyState()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Register as command handler
        CommandDispatcher.shared.handler = self

        // Observe store changes to refresh display
        observeStore()

        // Initial render for restored state — the store may already be
        // populated before this VC exists (e.g., after app relaunch).
        refreshDisplay()

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
    }

    @objc private func handleRepairSurfaceRequested(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? UUID else {
            return
        }
        dispatchAction(.repair(.recreateSurface(sessionId: sessionId)))
    }

    @objc private func handleSelectTabById(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let tabId = userInfo["tabId"] as? UUID else {
            return
        }
        dispatchAction(.selectTab(tabId: tabId))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Store Observation

    private func observeStore() {
        // Re-render when store changes (active tab, layout, etc.)
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDisplay()
            }
            .store(in: &cancellables)
    }

    private func refreshDisplay() {
        updateEmptyState()
        if let activeTabId = store.activeTabId {
            showTab(activeTabId)
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
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        // Title
        let titleLabel = NSTextField(labelWithString: "Welcome to AgentStudio")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor

        // Subtitle
        let subtitleLabel = NSTextField(wrappingLabelWithString: "Manage your AI agent worktrees with integrated terminal sessions.\nDouble-click a worktree to open a terminal.")
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
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
        ])

        return container
    }

    @objc private func addRepoAction() {
        NotificationCenter.default.post(name: .addRepoRequested, object: nil)
    }

    private func updateEmptyState() {
        let hasTerminals = !store.activeTabs.isEmpty
        tabBarHostingView.isHidden = !hasTerminals
        terminalContainer.isHidden = !hasTerminals
        emptyStateView?.isHidden = hasTerminals
    }

    // MARK: - Terminal Management

    func openTerminal(for worktree: Worktree, in repo: Repo) {
        executor.openTerminal(for: worktree, in: repo)
    }

    func closeTerminal(for worktreeId: UUID) {
        // Find the tab containing this worktree
        guard let tab = store.activeTabs.first(where: { tab in
            tab.sessionIds.contains { sessionId in
                store.session(sessionId)?.worktreeId == worktreeId
            }
        }) else { return }

        // Single-pane tab: close the whole tab (ActionValidator rejects .closePane
        // for single-pane tabs). Multi-pane: close just the pane.
        if tab.isSplit {
            guard let sessionId = tab.sessionIds.first(where: { sessionId in
                store.session(sessionId)?.worktreeId == worktreeId
            }) else { return }
            dispatchAction(.closePane(tabId: tab.id, paneId: sessionId))
        } else {
            dispatchAction(.closeTab(tabId: tab.id))
        }
    }

    func closeActiveTab() {
        guard let activeId = store.activeTabId else { return }
        dispatchAction(.closeTab(tabId: activeId))
    }

    func selectTab(at index: Int) {
        let tabs = store.activeTabs
        guard index >= 0, index < tabs.count else { return }
        dispatchAction(.selectTab(tabId: tabs[index].id))
    }

    // MARK: - Tab Display

    private func showTab(_ tabId: UUID) {
        guard let tab = store.tab(tabId) else {
            ghosttyLogger.warning("showTab: tab \(tabId) not found in store")
            return
        }

        // Build renderable tree from Layout + ViewRegistry
        guard let tree = viewRegistry.renderTree(for: tab.layout) else {
            ghosttyLogger.warning("Could not render tree for tab \(tabId) — missing views")
            return
        }

        ghosttyLogger.info("showTab: rendering tab \(tabId) with \(tab.sessionIds.count) session(s)")

        // Create the SwiftUI split container — views emit PaneAction directly
        let splitContainer = TerminalSplitContainer(
            tree: tree,
            tabId: tabId,
            activePaneId: tab.activeSessionId,
            action: { [weak self] action in
                self?.dispatchAction(action)
            },
            onPersist: {
                // Layout IS the tree — markDirty() handles persistence automatically
            },
            shouldAcceptDrop: { [weak self] (destPaneId: UUID, zone: DropZone) -> Bool in
                guard let self else { return false }
                // New terminal drags have no draggingTabId — always valid
                guard let draggingTabId = self.tabBarAdapter.draggingTabId else { return true }

                let snapshot = ActionResolver.snapshot(
                    from: self.store.activeTabs,
                    activeTabId: self.store.activeTabId,
                    isManagementModeActive: ManagementModeMonitor.shared.isActive
                )
                let payload = SplitDropPayload(kind: .existingTab(
                    tabId: draggingTabId, worktreeId: UUID(), repoId: UUID(), title: ""
                ))
                guard let action = ActionResolver.resolveDrop(
                    payload: payload,
                    destinationPaneId: destPaneId,
                    destinationTabId: tabId,
                    zone: zone,
                    state: snapshot
                ) else { return false }

                if case .success = ActionValidator.validate(action, state: snapshot) {
                    return true
                }
                return false
            },
            onDrop: { [weak self] (payload: SplitDropPayload, destPaneId: UUID, zone: DropZone) in
                guard let self else { return }
                let snapshot = ActionResolver.snapshot(
                    from: self.store.activeTabs,
                    activeTabId: self.store.activeTabId,
                    isManagementModeActive: ManagementModeMonitor.shared.isActive
                )
                if let action = ActionResolver.resolveDrop(
                    payload: payload,
                    destinationPaneId: destPaneId,
                    destinationTabId: tabId,
                    zone: zone,
                    state: snapshot
                ) {
                    self.dispatchAction(action)
                }
            }
        )

        // Wrap in AnyView for type erasure
        let anyView = AnyView(splitContainer)

        // Update or create the hosting view
        if let existingHostingView = splitHostingView {
            existingHostingView.rootView = anyView
        } else {
            let hostingView = NSHostingView(rootView: anyView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            terminalContainer.addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor)
            ])

            splitHostingView = hostingView
        }

        // Focus the active pane on next run loop (allows SwiftUI layout to complete)
        if let activeSessionId = tab.activeSessionId,
           let terminal = viewRegistry.view(for: activeSessionId) {
            DispatchQueue.main.async { [weak terminal] in
                guard let terminal = terminal, terminal.window != nil else { return }
                terminal.window?.makeFirstResponder(terminal)
                if let surfaceId = terminal.surfaceId {
                    SurfaceManager.shared.setFocus(surfaceId, focused: true)
                }
            }
        }
    }

    // MARK: - Validated Action Pipeline

    /// Central entry point: validates a PaneAction and executes it if valid.
    /// All input sources (keyboard, menu, drag-drop, commands) converge here.
    private func dispatchAction(_ action: PaneAction) {
        let snapshot = ActionResolver.snapshot(
            from: store.activeTabs,
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
                  let paneId = tab.activeSessionId else { return }
            let direction: SplitNewDirection = {
                switch command {
                case .splitRight: return .right
                case .splitBelow: return .down
                case .splitLeft:  return .left
                case .splitAbove: return .up
                default:          return .right
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
        guard let tab = store.tab(tabId) else { return nil }
        // Get worktree/repo from first session in the tab
        let firstSessionId = tab.sessionIds.first
        let session = firstSessionId.flatMap { store.session($0) }
        guard let worktreeId = session?.worktreeId,
              let repoId = session?.repoId else {
            // Cannot create drag payload for floating sessions (no worktree context)
            return nil
        }
        let title = session?.title ?? "Terminal"
        return TabDragPayload(tabId: tabId, worktreeId: worktreeId, repoId: repoId, title: title)
    }

    // MARK: - Process Termination

    @objc private func handleProcessTerminated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let worktreeId = userInfo["worktreeId"] as? UUID else {
            return
        }
        closeTerminal(for: worktreeId)
    }

    @objc private func handleExtractPaneRequested(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let tabId = userInfo["tabId"] as? UUID,
              let paneId = userInfo["paneId"] as? UUID else {
            return
        }
        dispatchAction(.extractPaneToTab(tabId: tabId, paneId: paneId))
    }

    // MARK: - Undo Close Tab

    @objc private func handleUndoCloseTab() {
        executor.undoCloseTab()
    }

    // MARK: - CommandHandler Conformance

    func execute(_ command: AppCommand) {
        // Try the validated pipeline for pane/tab structural actions
        if let action = ActionResolver.resolve(
            command: command, tabs: store.activeTabs, activeTabId: store.activeTabId
        ) {
            dispatchAction(action)
            return
        }

        // Non-pane commands handled directly
        switch command {
        case .addRepo:
            NotificationCenter.default.post(name: .addRepoRequested, object: nil)
        case .newTerminalInTab, .newFloatingTerminal,
             .removeRepo, .refreshWorktrees,
             .toggleSidebar, .quickFind, .commandBar:
            break // Handled elsewhere
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
            case (.closePane, .pane):
                guard let tab = store.activeTabs.first(where: { $0.sessionIds.contains(target) })
                else { return nil }
                return .closePane(tabId: tab.id, paneId: target)
            case (.extractPaneToTab, .pane):
                guard let tab = store.activeTabs.first(where: { $0.sessionIds.contains(target) })
                else { return nil }
                return .extractPaneToTab(tabId: tab.id, paneId: target)
            default:
                return nil
            }
        }()

        if let action {
            dispatchAction(action)
        } else {
            execute(command)
        }
    }

    func canExecute(_ command: AppCommand) -> Bool {
        // Try resolving — if it resolves, validate it
        if let action = ActionResolver.resolve(
            command: command, tabs: store.activeTabs, activeTabId: store.activeTabId
        ) {
            let snapshot = ActionResolver.snapshot(
                from: store.activeTabs,
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
