import AppKit
import SwiftUI
import GhosttyKit

/// Tab-based terminal controller with custom Ghostty-style tab bar
class TerminalTabViewController: NSViewController, CommandHandler {
    // MARK: - Properties

    private var tabBarHostingView: DraggableTabBarHostingView!
    private var terminalContainer: NSView!
    private var emptyStateView: NSView?

    /// Observable state for the tab bar
    private let tabBarState = TabBarState()

    /// SwiftUI hosting view for the split container
    private var splitHostingView: NSHostingView<AnyView>?

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
            state: tabBarState,
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
        tabBarHostingView.configure(state: tabBarState) { [weak self] fromId, toIndex in
            self?.handleTabReorder(fromId: fromId, toIndex: toIndex)
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
    }

    @objc private func handleSelectTabById(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let tabId = userInfo["tabId"] as? UUID else {
            return
        }
        selectTab(id: tabId)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        let hasTerminals = !tabItems.isEmpty
        tabBarHostingView.isHidden = !hasTerminals
        terminalContainer.isHidden = !hasTerminals
        emptyStateView?.isHidden = hasTerminals
    }

    /// Read-only convenience accessors for tab state.
    /// All mutations go through TabBarState's named methods.
    private var tabItems: [TabItem] { tabBarState.tabs }
    private var activeTabId: UUID? { tabBarState.activeTabId }

    // MARK: - Terminal Management

    func openTerminal(for worktree: Worktree, in repo: Repo) {
        // Check if already open in any tab
        if let existingTab = tabItems.first(where: { tab in
            tab.splitTree.allViews.contains { $0.worktree.id == worktree.id }
        }) {
            selectTab(id: existingTab.id)
            return
        }

        // Create new terminal view
        let terminalView = AgentStudioTerminalView(
            worktree: worktree,
            repo: repo
        )
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Create single-pane split tree with the view directly
        let splitTree = TerminalSplitTree(view: terminalView)

        // Reuse the OpenTab ID from SessionManager so persistence stays in sync
        let tabId: UUID
        if let existingOpenTab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == worktree.id }) {
            tabId = existingOpenTab.id
        } else {
            tabId = UUID()
        }

        // Create tab item with the split tree
        let tabItem = TabItem(
            id: tabId,
            title: worktree.name,
            primaryWorktreeId: worktree.id,
            primaryRepoId: repo.id,
            splitTree: splitTree,
            activePaneId: terminalView.id
        )
        tabBarState.appendTab(tabItem)

        // Ensure SessionManager has a record for this tab
        SessionManager.shared.addTabRecord(
            id: tabItem.id,
            worktreeId: worktree.id,
            repoId: repo.id
        )

        // Select the new tab (this will update the split container)
        selectTab(id: tabItem.id)

        // Auto-save the new tab's split tree
        saveSplitTree(for: tabItem)

        updateEmptyState()
    }

    /// Restore a tab from persisted OpenTab data, including split tree layout
    func restoreTab(from openTab: OpenTab) {
        // Try to decode saved split tree
        if let splitTreeData = openTab.splitTreeData,
           let savedTree = try? JSONDecoder().decode(TerminalSplitTree.self, from: splitTreeData) {
            // Restore with saved split layout
            restoreTabWithTree(openTab: openTab, savedTree: savedTree)
        } else {
            // Legacy: single worktree, create fresh
            guard let worktree = SessionManager.shared.worktree(for: openTab),
                  let repo = SessionManager.shared.repo(for: openTab) else {
                return
            }
            openTerminal(for: worktree, in: repo)
        }
    }

    private func restoreTabWithTree(openTab: OpenTab, savedTree: TerminalSplitTree) {
        // The decoded tree already contains AgentStudioTerminalView instances
        // (created by AgentStudioTerminalView.init(from decoder:) which looks up
        // worktree/repo from SessionManager and creates fresh terminals)
        guard let firstView = savedTree.allViews.first else { return }

        let tabItem = TabItem(
            id: openTab.id,
            title: firstView.title,
            primaryWorktreeId: firstView.worktree.id,
            primaryRepoId: firstView.repo.id,
            splitTree: savedTree,
            activePaneId: openTab.activePaneId ?? firstView.id
        )
        tabBarState.appendTab(tabItem)

        updateEmptyState()
    }

    func closeTerminal(for worktreeId: UUID) {
        // Find the tab containing this worktree
        guard let tabItem = tabItems.first(where: { tab in
            tab.splitTree.allViews.contains { $0.worktree.id == worktreeId }
        }) else {
            return
        }

        // Find the pane with this worktree
        guard let terminalView = tabItem.splitTree.allViews.first(where: { $0.worktree.id == worktreeId }) else {
            return
        }

        closePane(paneId: terminalView.id, inTab: tabItem.id)
    }

    private func closePane(paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }

        var tab = tabItems[tabIndex]

        // Get the terminal view from the tree
        guard let terminalView = tab.splitTree.find(id: paneId) else { return }

        // Terminate the terminal
        terminalView.terminateProcess()
        terminalView.removeFromSuperview()

        // Remove pane from split tree
        if let newTree = tab.splitTree.removing(view: terminalView) {
            // Update the tab with new tree
            tab.splitTree = newTree

            // If active pane was removed, select another
            if tab.activePaneId == paneId {
                tab.activePaneId = newTree.allViews.first?.id
            }

            // Update tab title
            tab.title = tab.displayTitle
            tabBarState.replaceTab(at: tabIndex, with: tab)

            // Persist the updated split tree
            saveSplitTree(for: tab)

            // Refresh the split view
            showTab(tabId)
        } else {
            // No panes left - close the entire tab
            closeTab(id: tabId)
        }

        updateEmptyState()

    }

    private func closeTab(id tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }

        let tab = tabItems[tabIndex]
        let allViews = tab.splitTree.allViews
        let runningCount = allViews.filter(\.isProcessRunning).count

        // Skip confirmation for single-pane tabs with no running process
        if allViews.count == 1 && runningCount == 0 {
            performCloseTab(at: tabIndex, tab: tab)
            return
        }

        // Show confirmation alert for tabs with running processes
        let alert = NSAlert()
        alert.messageText = "Close tab '\(tab.displayTitle)'?"
        alert.informativeText = "This will terminate \(runningCount) terminal session\(runningCount == 1 ? "" : "s")."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        // Style the Close button as destructive
        alert.buttons.first?.hasDestructiveAction = true

        guard let window = view.window else {
            performCloseTab(at: tabIndex, tab: tab)
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            // Re-lookup by ID — tabs may have been reordered/closed while alert was open
            guard let currentIndex = self.tabItems.firstIndex(where: { $0.id == tabId }) else { return }
            let currentTab = self.tabItems[currentIndex]
            self.performCloseTab(at: currentIndex, tab: currentTab)
        }
    }

    private func performCloseTab(at tabIndex: Int, tab: TabItem) {
        // Terminate all terminals in this tab
        for terminalView in tab.splitTree.allViews {
            terminalView.terminateProcess()
            terminalView.removeFromSuperview()
        }

        // Remove tab
        tabBarState.removeTab(at: tabIndex)

        // Clear split hosting view if this was the active tab
        if activeTabId == tab.id {
            splitHostingView?.removeFromSuperview()
            splitHostingView = nil

            // Select another tab
            if let nextTab = tabItems.first {
                selectTab(id: nextTab.id)
            } else {
                tabBarState.setActiveTabId(nil)
            }
        }

        updateEmptyState()

        // Update session manager
        Task { @MainActor in
            SessionManager.shared.closeTabById(tab.id)
        }
    }

    private func selectTab(id tabId: UUID) {
        guard tabItems.contains(where: { $0.id == tabId }) else { return }

        tabBarState.setActiveTabId(tabId)
        showTab(tabId)

        // Update session manager
        Task { @MainActor in
            if let tab = tabItems.first(where: { $0.id == tabId }),
               let sessionTab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == tab.primaryWorktreeId }) {
                SessionManager.shared.activeTabId = sessionTab.id
            }
        }
    }

    private func showTab(_ tabId: UUID) {
        guard let tab = tabItems.first(where: { $0.id == tabId }) else { return }

        // Create the SwiftUI split container — views emit PaneAction directly
        let splitContainer = TerminalSplitContainer(
            tree: tab.splitTree,
            tabId: tabId,
            activePaneId: tab.activePaneId,
            action: { [weak self] action in
                self?.dispatchAction(action)
            },
            onPersist: { [weak self] in
                guard let self,
                      let currentTab = self.tabItems.first(where: { $0.id == tabId }) else { return }
                self.saveSplitTree(for: currentTab)
            },
            shouldAcceptDrop: { [weak self] destPaneId, zone in
                guard let self else { return false }
                // New terminal drags have no draggingTabId — always valid
                guard let draggingTabId = self.tabBarState.draggingTabId else { return true }

                let snapshot = ActionResolver.snapshot(
                    from: self.tabItems,
                    activeTabId: self.activeTabId,
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
            onDrop: { [weak self] payload, destPaneId, zone in
                guard let self else { return }
                let snapshot = ActionResolver.snapshot(
                    from: self.tabItems,
                    activeTabId: self.activeTabId,
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
        if let activePaneId = tab.activePaneId,
           let terminal = tab.splitTree.find(id: activePaneId) {
            DispatchQueue.main.async { [weak terminal] in
                guard let terminal = terminal, terminal.window != nil else { return }
                terminal.window?.makeFirstResponder(terminal)
                if let surfaceId = terminal.surfaceId {
                    SurfaceManager.shared.setFocus(surfaceId, focused: true)
                }
            }
        }
    }

    // MARK: - Split Operations

    /// Save a tab's split tree to SessionManager for persistence
    private func saveSplitTree(for tab: TabItem) {
        let encoder = JSONEncoder()
        guard let splitTreeData = try? encoder.encode(tab.splitTree) else {
            ghosttyLogger.error("Failed to encode split tree for tab \(tab.id)")
            return
        }
        SessionManager.shared.updateTabSplitTree(tab.id, splitTreeData: splitTreeData, activePaneId: tab.activePaneId)
    }

    // MARK: - Validated Action Pipeline

    /// Central entry point: validates a PaneAction and executes it if valid.
    /// All input sources (keyboard, menu, drag-drop, commands) converge here.
    private func dispatchAction(_ action: PaneAction) {
        let snapshot = ActionResolver.snapshot(
            from: tabItems,
            activeTabId: activeTabId,
            isManagementModeActive: ManagementModeMonitor.shared.isActive
        )

        switch ActionValidator.validate(action, state: snapshot) {
        case .success(let validated):
            executeValidated(validated)
        case .failure(let error):
            ghosttyLogger.warning("Action rejected: \(error)")
        }
    }

    /// Execute a validated action. Only callable with a ValidatedAction
    /// (which can only be created by ActionValidator).
    private func executeValidated(_ validated: ValidatedAction) {
        switch validated.action {
        case .selectTab(let tabId):
            selectTab(id: tabId)

        case .closeTab(let tabId):
            closeTab(id: tabId)

        case .breakUpTab(let tabId):
            breakUpTab(id: tabId)

        case .closePane(let tabId, let paneId):
            closePane(paneId: paneId, inTab: tabId)

        case .extractPaneToTab(_, let paneId):
            extractPaneToTab(paneId: paneId)

        case .focusPane(let tabId, let paneId):
            guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }
            var tab = tabItems[tabIndex]
            tab.activePaneId = paneId
            tabBarState.replaceTab(at: tabIndex, with: tab)
            showTab(tabId)

        case .insertPane(let source, let targetTabId, let targetPaneId, let direction):
            executeInsertPane(source: source, targetTabId: targetTabId,
                            targetPaneId: targetPaneId, direction: direction)

        case .resizePane(let tabId, let splitId, let ratio):
            guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }
            var tab = tabItems[tabIndex]
            tab.splitTree = tab.splitTree.resizing(splitId: splitId, ratio: ratio)
            tabBarState.replaceTab(at: tabIndex, with: tab)
            showTab(tabId)
            // Persistence is handled by onResizeEnd — not on every pixel of drag

        case .equalizePanes(let tabId):
            guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }
            var tab = tabItems[tabIndex]
            tab.splitTree = tab.splitTree.equalized()
            tabBarState.replaceTab(at: tabIndex, with: tab)
            showTab(tabId)
            saveSplitTree(for: tab)

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, let direction):
            executeMergeTab(sourceTabId: sourceTabId, targetTabId: targetTabId,
                          targetPaneId: targetPaneId, direction: direction)
        }
    }

    /// Execute an insertPane action (existing pane move or new terminal).
    private func executeInsertPane(
        source: PaneSource,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == targetTabId }),
              let destination = tabItems[tabIndex].splitTree.find(id: targetPaneId) else { return }

        var tab = tabItems[tabIndex]
        let newDirection = splitTreeDirection(from: direction)

        switch source {
        case .existingPane(let sourcePaneId, let sourceTabId):
            // Find the terminal view
            guard let terminalView = tabItems.flatMap({ $0.splitTree.allViews })
                .first(where: { $0.id == sourcePaneId }) else { return }

            if sourceTabId == targetTabId {
                // Same-tab move: remove from current position first to avoid duplicate node
                if let cleaned = tab.splitTree.removing(view: terminalView) {
                    tab.splitTree = cleaned
                } else {
                    // Only pane in the tree — nothing to move
                    return
                }
                tabBarState.replaceTab(at: tabIndex, with: tab)
            } else if let sourceIndex = tabItems.firstIndex(where: { $0.id == sourceTabId }) {
                // Cross-tab move: remove from source tab
                var sourceTab = tabItems[sourceIndex]
                if let newTree = sourceTab.splitTree.removing(view: terminalView) {
                    sourceTab.splitTree = newTree
                    if sourceTab.activePaneId == terminalView.id {
                        sourceTab.activePaneId = newTree.allViews.first?.id
                    }
                    sourceTab.title = sourceTab.displayTitle
                    tabBarState.replaceTab(at: sourceIndex, with: sourceTab)
                    saveSplitTree(for: sourceTab)
                } else {
                    tabBarState.removeTab(at: sourceIndex)
                    SessionManager.shared.removeTabRecord(sourceTabId)
                }
            }

            // Re-find tab index (may have shifted)
            guard let updatedIndex = tabItems.firstIndex(where: { $0.id == targetTabId }) else { return }
            tab = tabItems[updatedIndex]

            // Re-find destination pane (tree structure may have changed)
            guard let updatedDestination = tab.splitTree.find(id: targetPaneId) else { return }

            // Insert into target
            if let newTree = try? tab.splitTree.inserting(
                view: terminalView, at: updatedDestination, direction: newDirection
            ) {
                tab.splitTree = newTree
                tab.activePaneId = terminalView.id
                tab.title = tab.displayTitle
                tabBarState.replaceTab(at: updatedIndex, with: tab)

                if let surfaceId = terminalView.surfaceId {
                    SurfaceManager.shared.attach(surfaceId, to: terminalView.containerId)
                }
            }

            selectTab(id: targetTabId)
            saveSplitTree(for: tab)
            SessionManager.shared.syncTabOrder(tabIds: tabBarState.tabs.map(\.id))

        case .newTerminal:
            // Create new terminal pane inline using the destination pane's worktree/repo
            let terminalView = AgentStudioTerminalView(
                worktree: destination.worktree,
                repo: destination.repo
            )
            terminalView.translatesAutoresizingMaskIntoConstraints = false

            guard let newTree = try? tab.splitTree.inserting(
                view: terminalView, at: destination, direction: newDirection
            ) else {
                ghosttyLogger.error("Failed to insert new terminal pane into split tree")
                return
            }
            tab.splitTree = newTree
            tab.activePaneId = terminalView.id
            tab.title = tab.displayTitle
            tabBarState.replaceTab(at: tabIndex, with: tab)

            selectTab(id: targetTabId)
            saveSplitTree(for: tab)
        }
    }

    /// Execute a mergeTab action — move ALL panes from source tab into target tab.
    private func executeMergeTab(
        sourceTabId: UUID,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        guard let sourceIndex = tabItems.firstIndex(where: { $0.id == sourceTabId }) else { return }
        let sourceTab = tabItems[sourceIndex]
        let sourceViews = sourceTab.splitTree.allViews
        guard !sourceViews.isEmpty else { return }

        // Find target tab BEFORE removing source (so index is still valid)
        guard let targetIndex = tabItems.firstIndex(where: { $0.id == targetTabId }),
              let targetPane = tabItems[targetIndex].splitTree.find(id: targetPaneId) else { return }

        var tab = tabItems[targetIndex]
        let newDirection = splitTreeDirection(from: direction)

        // Insert source views into target tab's tree FIRST (before removing source tab)
        var insertTarget = targetPane
        for sourceView in sourceViews {
            if let surfaceId = sourceView.surfaceId {
                SurfaceManager.shared.attach(surfaceId, to: sourceView.containerId)
            }
            if let newTree = try? tab.splitTree.inserting(
                view: sourceView, at: insertTarget, direction: newDirection
            ) {
                tab.splitTree = newTree
                insertTarget = sourceView
            }
        }

        tab.activePaneId = sourceViews.first?.id
        tab.title = tab.displayTitle
        tabBarState.replaceTab(at: targetIndex, with: tab)

        // Remove source tab AFTER views are safely inserted into target
        // Re-lookup source index since replaceTab above may not have shifted it,
        // but removeTab at an earlier index would shift targetIndex
        if let currentSourceIndex = tabItems.firstIndex(where: { $0.id == sourceTabId }) {
            tabBarState.removeTab(at: currentSourceIndex)
        }

        // Sync session: remove source tab record, update order
        SessionManager.shared.removeTabRecord(sourceTabId)
        SessionManager.shared.syncTabOrder(tabIds: tabBarState.tabs.map(\.id))

        selectTab(id: targetTabId)
        saveSplitTree(for: tab)
    }

    /// Convert SplitNewDirection to SplitTree.NewDirection
    private func splitTreeDirection(from direction: SplitNewDirection) -> TerminalSplitTree.NewDirection {
        switch direction {
        case .left:  return .left
        case .right: return .right
        case .up:    return .up
        case .down:  return .down
        }
    }

    /// Convert SplitNewDirection to DropZone (for notification compatibility)
    private func dropZone(from direction: SplitNewDirection) -> DropZone {
        switch direction {
        case .left:   return .left
        case .right:  return .right
        case .up:     return .top
        case .down:   return .bottom
        }
    }

    // MARK: - Tab Commands

    /// Route tab context menu commands through the validated pipeline.
    private func handleTabCommand(_ command: AppCommand, tabId: UUID) {
        // Build a tab-specific resolution (use tabId instead of activeTabId)
        let tabs = tabItems
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
            guard let tab = tabs.first(where: { $0.id == tabId }),
                  let paneId = tab.activePaneId else { return }
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
            // Not yet a PaneAction — handled directly
            action = nil
        default:
            action = nil
        }

        if let action {
            dispatchAction(action)
        }
    }

    /// Break up a multi-pane tab into individual single-pane tabs
    private func breakUpTab(id tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }
        let tab = tabItems[tabIndex]

        let allViews = tab.splitTree.allViews
        guard allViews.count > 1 else { return }

        // Remove original tab
        tabBarState.removeTab(at: tabIndex)

        // Create individual tabs for each pane
        var newTabs: [TabItem] = []
        for terminalView in allViews {
            let newTree = TerminalSplitTree(view: terminalView)
            let newTab = TabItem(
                title: terminalView.title,
                primaryWorktreeId: terminalView.worktree.id,
                primaryRepoId: terminalView.repo.id,
                splitTree: newTree,
                activePaneId: terminalView.id
            )
            newTabs.append(newTab)
        }

        // Insert new tabs at original position
        let insertIndex = min(tabIndex, tabItems.count)
        tabBarState.insertTabs(newTabs, at: insertIndex)

        // Sync session: remove original, add individual tabs
        SessionManager.shared.removeTabRecord(tab.id)
        for newTab in newTabs {
            SessionManager.shared.addTabRecord(
                id: newTab.id,
                worktreeId: newTab.primaryWorktreeId,
                repoId: newTab.primaryRepoId
            )
            saveSplitTree(for: newTab)
        }
        SessionManager.shared.syncTabOrder(tabIds: tabBarState.tabs.map(\.id))

        // Select the tab that contains the previously active pane
        let activeTab = newTabs.first { $0.activePaneId == tab.activePaneId } ?? newTabs.first
        if let activeTab {
            selectTab(id: activeTab.id)
        }

        updateEmptyState()
    }

    func closeActiveTab() {
        guard let activeId = activeTabId else { return }
        dispatchAction(.closeTab(tabId: activeId))
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabItems.count else { return }
        dispatchAction(.selectTab(tabId: tabItems[index].id))
    }

    // MARK: - Tab Reordering

    private func handleTabReorder(fromId: UUID, toIndex: Int) {
        tabBarState.moveTab(fromId: fromId, toIndex: toIndex)

        // Persist new order
        Task { @MainActor in
            SessionManager.shared.reorderTabs(tabBarState.tabs.map { $0.primaryWorktreeId })
        }
    }

    // MARK: - Pane Commands

    private func extractPaneToTab(paneId: UUID) {
        guard let activeId = activeTabId,
              let tabIndex = tabItems.firstIndex(where: { $0.id == activeId }) else { return }

        var tab = tabItems[tabIndex]
        guard let terminalView = tab.splitTree.find(id: paneId),
              tab.splitTree.allViews.count > 1 else { return }

        // Remove pane from source tab
        guard let newTree = tab.splitTree.removing(view: terminalView) else { return }
        tab.splitTree = newTree
        if tab.activePaneId == paneId {
            tab.activePaneId = newTree.allViews.first?.id
        }
        tab.title = tab.displayTitle
        tabBarState.replaceTab(at: tabIndex, with: tab)

        // Create new single-pane tab
        let newSplitTree = TerminalSplitTree(view: terminalView)
        let newTab = TabItem(
            title: terminalView.title,
            primaryWorktreeId: terminalView.worktree.id,
            primaryRepoId: terminalView.repo.id,
            splitTree: newSplitTree,
            activePaneId: terminalView.id
        )
        tabBarState.insertTabs([newTab], at: tabIndex + 1)

        // Sync session: add extracted tab
        SessionManager.shared.addTabRecord(
            id: newTab.id,
            worktreeId: newTab.primaryWorktreeId,
            repoId: newTab.primaryRepoId
        )
        saveSplitTree(for: newTab)
        SessionManager.shared.syncTabOrder(tabIds: tabBarState.tabs.map(\.id))

        // Refresh source tab display
        showTab(activeId)
        saveSplitTree(for: tab)

        // Select the new extracted tab
        selectTab(id: newTab.id)
        updateEmptyState()
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
        extractPaneToTab(paneId: paneId, fromTabId: tabId)
    }

    /// Extract a specific pane from a specific tab (used by tab bar pane drop)
    private func extractPaneToTab(paneId: UUID, fromTabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == fromTabId }) else { return }

        var tab = tabItems[tabIndex]
        guard let terminalView = tab.splitTree.find(id: paneId),
              tab.splitTree.allViews.count > 1 else { return }

        // Remove pane from source tab
        guard let newTree = tab.splitTree.removing(view: terminalView) else { return }
        tab.splitTree = newTree
        if tab.activePaneId == paneId {
            tab.activePaneId = newTree.allViews.first?.id
        }
        tab.title = tab.displayTitle
        tabBarState.replaceTab(at: tabIndex, with: tab)

        // Create new single-pane tab
        let newSplitTree = TerminalSplitTree(view: terminalView)
        let newTab = TabItem(
            title: terminalView.title,
            primaryWorktreeId: terminalView.worktree.id,
            primaryRepoId: terminalView.repo.id,
            splitTree: newSplitTree,
            activePaneId: terminalView.id
        )
        tabBarState.insertTabs([newTab], at: tabIndex + 1)

        // Sync session
        SessionManager.shared.addTabRecord(
            id: newTab.id,
            worktreeId: newTab.primaryWorktreeId,
            repoId: newTab.primaryRepoId
        )
        saveSplitTree(for: newTab)
        SessionManager.shared.syncTabOrder(tabIds: tabBarState.tabs.map(\.id))

        showTab(fromTabId)
        saveSplitTree(for: tab)
        selectTab(id: newTab.id)
        updateEmptyState()
    }

    // MARK: - Undo Close Tab

    // MARK: - CommandHandler Conformance

    func execute(_ command: AppCommand) {
        // Try the validated pipeline for pane/tab structural actions
        if let action = ActionResolver.resolve(
            command: command, tabs: tabItems, activeTabId: activeTabId
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
                guard let tab = tabItems.first(where: { $0.allPaneIds.contains(target) })
                else { return nil }
                return .closePane(tabId: tab.id, paneId: target)
            case (.extractPaneToTab, .pane):
                guard let tab = tabItems.first(where: { $0.allPaneIds.contains(target) })
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
            command: command, tabs: tabItems, activeTabId: activeTabId
        ) {
            let snapshot = ActionResolver.snapshot(
                from: tabItems,
                activeTabId: activeTabId,
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

    @objc private func handleUndoCloseTab() {
        guard let restored = SurfaceManager.shared.undoClose() else {
            ghosttyLogger.info("No tabs to restore")
            return
        }

        // Get worktree and repo from metadata
        guard let worktreeId = restored.metadata.worktreeId,
              let repoId = restored.metadata.repoId,
              let repo = SessionManager.shared.repos.first(where: { $0.id == repoId }),
              let worktree = repo.worktrees.first(where: { $0.id == worktreeId }) else {
            ghosttyLogger.warning("Could not find worktree/repo for restored surface")
            // Still destroy the orphan surface
            SurfaceManager.shared.destroy(restored.id)
            return
        }

        // Create terminal view using restore initializer (doesn't create new surface)
        let terminalView = AgentStudioTerminalView(
            worktree: worktree,
            repo: repo,
            restoredSurfaceId: restored.id
        )
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Attach restored surface to the terminal view
        if let surfaceView = SurfaceManager.shared.attach(restored.id, to: terminalView.containerId) {
            terminalView.displaySurface(surfaceView)
        }

        // Create single-pane split tree with the view directly
        let splitTree = TerminalSplitTree(view: terminalView)

        // Create tab item with the split tree
        let tabItem = TabItem(
            id: UUID(),
            title: worktree.name,
            primaryWorktreeId: worktree.id,
            primaryRepoId: repo.id,
            splitTree: splitTree,
            activePaneId: terminalView.id
        )
        tabBarState.appendTab(tabItem)

        // Sync session: add restored tab record
        SessionManager.shared.addTabRecord(
            id: tabItem.id,
            worktreeId: tabItem.primaryWorktreeId,
            repoId: tabItem.primaryRepoId
        )
        saveSplitTree(for: tabItem)
        SessionManager.shared.syncTabOrder(tabIds: tabBarState.tabs.map(\.id))

        // Select the restored tab (this will update the split container)
        selectTab(id: tabItem.id)

        updateEmptyState()
        ghosttyLogger.info("Restored tab for worktree: \(worktree.name)")
    }
}
