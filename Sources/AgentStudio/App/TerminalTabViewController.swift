import AppKit
import SwiftUI
import GhosttyKit

/// Tab-based terminal controller with custom Ghostty-style tab bar
class TerminalTabViewController: NSViewController {
    // MARK: - Properties

    private var tabBarHostingView: DraggableTabBarHostingView!
    private var terminalContainer: NSView!
    private var emptyStateView: NSView?

    /// Observable state for the tab bar
    private let tabBarState = TabBarState()

    /// Map of pane ID to terminal view (panes across all tabs)
    private var paneViews: [UUID: AgentStudioTerminalView] = [:]

    /// SwiftUI hosting view for the split container
    private var splitHostingView: NSHostingView<AnyView>?

    /// Legacy compatibility - computed from pane views
    private var terminals: [UUID: AgentStudioTerminalView] {
        // Build worktreeId -> terminal map from all tabs
        var result: [UUID: AgentStudioTerminalView] = [:]
        for tab in tabItems {
            for pane in tab.splitTree.allViews {
                if let view = paneViews[pane.id] {
                    result[pane.worktreeId] = view
                }
            }
        }
        return result
    }

    /// Legacy compatibility - computed from tabs
    private var tabToWorktree: [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for tab in tabItems {
            result[tab.id] = tab.primaryWorktreeId
        }
        return result
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
            state: tabBarState,
            onSelect: { [weak self] tabId in
                self?.selectTab(id: tabId)
            },
            onClose: { [weak self] tabId in
                self?.closeTab(id: tabId)
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
        let hintLabel = NSTextField(labelWithString: "Tip: Use Cmd+Shift+O to add a project")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor

        // Add Project button
        let addButton = NSButton(title: "Add Project...", target: self, action: #selector(addProjectAction))
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

    @objc private func addProjectAction() {
        NotificationCenter.default.post(name: .addProjectRequested, object: nil)
    }

    private func updateEmptyState() {
        let hasTerminals = !paneViews.isEmpty
        tabBarHostingView.isHidden = !hasTerminals
        terminalContainer.isHidden = !hasTerminals
        emptyStateView?.isHidden = hasTerminals
    }

    /// Convenience accessors for tab state
    private var tabItems: [TabItem] {
        get { tabBarState.tabs }
        set { tabBarState.tabs = newValue }
    }

    private var activeTabId: UUID? {
        get { tabBarState.activeTabId }
        set { tabBarState.activeTabId = newValue }
    }

    // MARK: - Terminal Management

    func openTerminal(for worktree: Worktree, in project: Project) {
        // Check if already open in any tab
        if let existingTab = tabItems.first(where: { tab in
            tab.splitTree.allViews.contains { $0.worktreeId == worktree.id }
        }) {
            selectTab(id: existingTab.id)
            return
        }

        // Create new terminal view
        let terminalView = AgentStudioTerminalView(
            worktree: worktree,
            project: project
        )
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Create pane and store the view
        let paneId = UUID()
        paneViews[paneId] = terminalView

        // Create single-pane split tree
        let pane = TerminalPaneView(
            id: paneId,
            worktreeId: worktree.id,
            projectId: project.id,
            title: worktree.name
        )
        let splitTree = TerminalSplitTree(view: pane)

        // Create tab item with the split tree
        let tabItem = TabItem(
            id: UUID(),
            title: worktree.name,
            primaryWorktreeId: worktree.id,
            primaryProjectId: project.id,
            splitTree: splitTree,
            activePaneId: paneId
        )
        tabItems.append(tabItem)

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
                  let project = SessionManager.shared.project(for: openTab) else {
                return
            }
            openTerminal(for: worktree, in: project)
        }
    }

    private func restoreTabWithTree(openTab: OpenTab, savedTree: TerminalSplitTree) {
        // Create terminal views for each pane in the tree
        for pane in savedTree.allViews {
            // Find the worktree and project for this pane
            guard let project = SessionManager.shared.projects.first(where: { $0.id == pane.projectId }),
                  let worktree = project.worktrees.first(where: { $0.id == pane.worktreeId }) else {
                ghosttyLogger.warning("Could not find worktree for pane \(pane.id)")
                continue
            }

            // Create terminal view for this pane
            let terminalView = AgentStudioTerminalView(
                worktree: worktree,
                project: project
            )
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            paneViews[pane.id] = terminalView
        }

        // Get primary worktree info for tab display
        guard let firstPane = savedTree.allViews.first,
              let project = SessionManager.shared.projects.first(where: { $0.id == firstPane.projectId }),
              let worktree = project.worktrees.first(where: { $0.id == firstPane.worktreeId }) else {
            return
        }

        // Create tab item with restored split tree
        let tabItem = TabItem(
            id: openTab.id,  // Preserve original tab ID
            title: worktree.name,
            primaryWorktreeId: worktree.id,
            primaryProjectId: project.id,
            splitTree: savedTree,
            activePaneId: openTab.activePaneId ?? firstPane.id
        )
        tabItems.append(tabItem)

        updateEmptyState()
    }

    func closeTerminal(for worktreeId: UUID) {
        // Find the tab containing this worktree
        guard let tabItem = tabItems.first(where: { tab in
            tab.splitTree.allViews.contains { $0.worktreeId == worktreeId }
        }) else {
            return
        }

        // Find the pane with this worktree
        guard let pane = tabItem.splitTree.allViews.first(where: { $0.worktreeId == worktreeId }) else {
            return
        }

        closePane(paneId: pane.id, inTab: tabItem.id)
    }

    private func closePane(paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }

        var tab = tabItems[tabIndex]

        // Get the pane to close
        guard let pane = tab.splitTree.find(id: paneId) else { return }

        // Terminate the terminal
        if let terminal = paneViews[paneId] {
            terminal.terminateProcess()
            terminal.removeFromSuperview()
            paneViews.removeValue(forKey: paneId)
        }

        // Remove pane from split tree
        if let newTree = tab.splitTree.removing(view: pane) {
            // Update the tab with new tree
            tab.splitTree = newTree

            // If active pane was removed, select another
            if tab.activePaneId == paneId {
                tab.activePaneId = newTree.allViews.first?.id
            }

            // Update tab title
            tab.title = tab.displayTitle
            tabItems[tabIndex] = tab

            // Refresh the split view
            showTab(tabId)
        } else {
            // No panes left - close the entire tab
            closeTab(id: tabId)
        }

        updateEmptyState()

        // Update session manager
        Task { @MainActor in
            if let sessionTab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == pane.worktreeId }) {
                SessionManager.shared.closeTab(sessionTab)
            }
        }
    }

    private func closeTab(id tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }

        let tab = tabItems[tabIndex]

        // Terminate all terminals in this tab
        for pane in tab.splitTree.allViews {
            if let terminal = paneViews[pane.id] {
                terminal.terminateProcess()
                terminal.removeFromSuperview()
                paneViews.removeValue(forKey: pane.id)
            }
        }

        // Remove tab
        tabItems.remove(at: tabIndex)

        // Clear split hosting view if this was the active tab
        if activeTabId == tabId {
            splitHostingView?.removeFromSuperview()
            splitHostingView = nil

            // Select another tab
            if let nextTab = tabItems.first {
                selectTab(id: nextTab.id)
            } else {
                activeTabId = nil
            }
        }

        updateEmptyState()

        // Update session manager
        Task { @MainActor in
            for pane in tab.splitTree.allViews {
                if let sessionTab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == pane.worktreeId }) {
                    SessionManager.shared.closeTab(sessionTab)
                }
            }
        }
    }

    private func selectTab(id tabId: UUID) {
        guard tabItems.contains(where: { $0.id == tabId }) else { return }

        activeTabId = tabId
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

        // Create the SwiftUI split container
        let splitContainer = TerminalSplitContainer(
            tree: tab.splitTree,
            terminalViews: paneViews,
            activePaneId: tab.activePaneId
        ) { [weak self] operation in
            self?.handleSplitOperation(operation, tabId: tabId)
        }

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

        // Focus the active pane
        if let activePaneId = tab.activePaneId,
           let terminal = paneViews[activePaneId] {
            DispatchQueue.main.async {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
    }

    // MARK: - Split Operations

    private func handleSplitOperation(_ operation: SplitOperation, tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }

        var tab = tabItems[tabIndex]

        switch operation {
        case .resize(let paneId, let ratio):
            // Find the pane and update the split ratio
            if let pane = tab.splitTree.find(id: paneId) {
                tab.splitTree = tab.splitTree.resizing(view: pane, ratio: Double(ratio))
            }

        case .equalize:
            tab.splitTree = tab.splitTree.equalized()

        case .focus(let paneId):
            tab.activePaneId = paneId

        case .drop(let payload, let destination, let zone):
            handleDrop(payload: payload, destination: destination, zone: zone, tab: &tab)
        }

        // Save updated tab
        tabItems[tabIndex] = tab

        // Refresh the view
        showTab(tabId)

        // Auto-save split tree to SessionManager
        saveSplitTree(for: tab)
    }

    /// Save a tab's split tree to SessionManager for persistence
    private func saveSplitTree(for tab: TabItem) {
        let encoder = JSONEncoder()
        let splitTreeData = try? encoder.encode(tab.splitTree)
        SessionManager.shared.updateTabSplitTree(tab.id, splitTreeData: splitTreeData, activePaneId: tab.activePaneId)
    }

    private func handleDrop(payload: SplitDropPayload, destination: TerminalPaneView, zone: DropZone, tab: inout TabItem) {
        switch payload.kind {
        case .existingTab(let draggedTabId, let worktreeId, let projectId, let title):
            // Moving an existing tab into a split
            // First, remove it from its source tab (if it's from another tab)
            if tabItems.contains(where: { $0.id == draggedTabId }) {
                // Find and close the source tab (the terminal will be moved, not destroyed)
                if let sourceIndex = tabItems.firstIndex(where: { $0.id == draggedTabId }) {
                    // Don't destroy the terminal - we'll reuse it
                    // Just remove the tab
                    tabItems.remove(at: sourceIndex)
                }
            }

            // Create new pane for the dropped tab
            let newPaneId = UUID()

            // Create terminal if needed (might need to look up existing)
            if let existingTerminal = terminals.first(where: { $0.key == worktreeId })?.value {
                paneViews[newPaneId] = existingTerminal
            }

            let newPane = TerminalPaneView(
                id: newPaneId,
                worktreeId: worktreeId,
                projectId: projectId,
                title: title
            )

            // Insert into split tree
            if let newTree = try? tab.splitTree.inserting(view: newPane, at: destination, direction: zone.newDirection) {
                tab.splitTree = newTree
                tab.activePaneId = newPaneId
                tab.title = tab.displayTitle
            }

        case .newTerminal:
            // Create a new terminal in the split
            // For now, this requires user interaction to select a worktree
            // We'll post a notification to request a new terminal selection
            NotificationCenter.default.post(
                name: .newTabRequested,
                object: nil,
                userInfo: [
                    "splitDestination": destination,
                    "splitZone": zone,
                    "targetTabId": tab.id
                ]
            )
        }
    }

    func closeActiveTab() {
        guard let activeId = activeTabId else { return }
        closeTab(id: activeId)
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabItems.count else { return }
        selectTab(id: tabItems[index].id)
    }

    // MARK: - Tab Reordering

    private func handleTabReorder(fromId: UUID, toIndex: Int) {
        tabBarState.moveTab(fromId: fromId, toIndex: toIndex)

        // Persist new order
        Task { @MainActor in
            SessionManager.shared.reorderTabs(tabBarState.tabs.map { $0.primaryWorktreeId })
        }
    }

    // MARK: - Process Termination

    @objc private func handleProcessTerminated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let worktreeId = userInfo["worktreeId"] as? UUID else {
            return
        }
        closeTerminal(for: worktreeId)
    }

    // MARK: - Undo Close Tab

    @objc private func handleUndoCloseTab() {
        guard let restored = SurfaceManager.shared.undoClose() else {
            ghosttyLogger.info("No tabs to restore")
            return
        }

        // Get worktree and project from metadata
        guard let worktreeId = restored.metadata.worktreeId,
              let projectId = restored.metadata.projectId,
              let project = SessionManager.shared.projects.first(where: { $0.id == projectId }),
              let worktree = project.worktrees.first(where: { $0.id == worktreeId }) else {
            ghosttyLogger.warning("Could not find worktree/project for restored surface")
            // Still destroy the orphan surface
            SurfaceManager.shared.destroy(restored.id)
            return
        }

        // Create terminal view using restore initializer (doesn't create new surface)
        let terminalView = AgentStudioTerminalView(
            worktree: worktree,
            project: project,
            restoredSurfaceId: restored.id
        )
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        // Attach restored surface to the terminal view
        if let surfaceView = SurfaceManager.shared.attach(restored.id, to: terminalView.containerId) {
            terminalView.displaySurface(surfaceView)
        }

        // Create pane and store the view
        let paneId = UUID()
        paneViews[paneId] = terminalView

        // Create single-pane split tree
        let pane = TerminalPaneView(
            id: paneId,
            worktreeId: worktree.id,
            projectId: project.id,
            title: worktree.name
        )
        let splitTree = TerminalSplitTree(view: pane)

        // Create tab item with the split tree
        let tabItem = TabItem(
            id: UUID(),
            title: worktree.name,
            primaryWorktreeId: worktree.id,
            primaryProjectId: project.id,
            splitTree: splitTree,
            activePaneId: paneId
        )
        tabItems.append(tabItem)

        // Select the restored tab (this will update the split container)
        selectTab(id: tabItem.id)

        updateEmptyState()
        ghosttyLogger.info("Restored tab for worktree: \(worktree.name)")
    }
}
