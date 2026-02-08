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
        let hasTerminals = !tabItems.isEmpty
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
            tab.splitTree.allViews.contains { $0.worktree.id == worktree.id }
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

        // Create single-pane split tree with the view directly
        let splitTree = TerminalSplitTree(view: terminalView)

        // Create tab item with the split tree
        let tabItem = TabItem(
            id: UUID(),
            title: worktree.name,
            primaryWorktreeId: worktree.id,
            primaryProjectId: project.id,
            splitTree: splitTree,
            activePaneId: terminalView.id
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
        // The decoded tree already contains AgentStudioTerminalView instances
        // (created by AgentStudioTerminalView.init(from decoder:) which looks up
        // worktree/project from SessionManager and creates fresh terminals)
        guard let firstView = savedTree.allViews.first else { return }

        let tabItem = TabItem(
            id: openTab.id,
            title: firstView.title,
            primaryWorktreeId: firstView.worktree.id,
            primaryProjectId: firstView.project.id,
            splitTree: savedTree,
            activePaneId: openTab.activePaneId ?? firstView.id
        )
        tabItems.append(tabItem)

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
            if let sessionTab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == terminalView.worktree.id }) {
                SessionManager.shared.closeTab(sessionTab)
            }
        }
    }

    private func closeTab(id tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }

        let tab = tabItems[tabIndex]

        // Terminate all terminals in this tab (views are in the tree directly)
        for terminalView in tab.splitTree.allViews {
            terminalView.terminateProcess()
            terminalView.removeFromSuperview()
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
            for terminalView in tab.splitTree.allViews {
                if let sessionTab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == terminalView.worktree.id }) {
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

        // Create the SwiftUI split container (no dictionary needed — views are in the tree)
        let splitContainer = TerminalSplitContainer(
            tree: tab.splitTree,
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

        // Focus the active pane (delayed to allow SwiftUI layout after structural identity changes)
        if let activePaneId = tab.activePaneId,
           let terminal = tab.splitTree.find(id: activePaneId) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak terminal] in
                guard let terminal = terminal, terminal.window != nil else { return }
                terminal.window?.makeFirstResponder(terminal)
                if let surfaceId = terminal.surfaceId {
                    SurfaceManager.shared.setFocus(surfaceId, focused: true)
                }
            }
        }
    }

    // MARK: - Split Operations

    private func handleSplitOperation(_ operation: SplitOperation, tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }) else { return }

        var tab = tabItems[tabIndex]
        var needsSelect = false

        switch operation {
        case .resize(let paneId, let ratio):
            // Find the pane and update the split ratio
            if let terminalView = tab.splitTree.find(id: paneId) {
                tab.splitTree = tab.splitTree.resizing(view: terminalView, ratio: Double(ratio))
            }

        case .equalize:
            tab.splitTree = tab.splitTree.equalized()

        case .focus(let paneId):
            tab.activePaneId = paneId

        case .drop(let payload, let destination, let zone):
            handleDrop(payload: payload, destination: destination, zone: zone, tab: &tab)
            needsSelect = true

        case .closePane(let paneId):
            // Re-find tab index before delegating (closePane manages its own state)
            if let updatedIndex = tabItems.firstIndex(where: { $0.id == tabId }) {
                tabItems[updatedIndex] = tab
            }
            closePane(paneId: paneId, inTab: tabId)
            return
        }

        // Re-find tab index (may have shifted if handleDrop removed a source tab)
        if let updatedIndex = tabItems.firstIndex(where: { $0.id == tabId }) {
            tabItems[updatedIndex] = tab
        }

        // For drop operations, use selectTab to ensure activeTabId is updated
        // (handleDrop may have removed the source tab, leaving activeTabId stale)
        if needsSelect {
            selectTab(id: tabId)
        } else {
            showTab(tabId)
        }

        // Auto-save split tree to SessionManager
        saveSplitTree(for: tab)
    }

    /// Save a tab's split tree to SessionManager for persistence
    private func saveSplitTree(for tab: TabItem) {
        let encoder = JSONEncoder()
        let splitTreeData = try? encoder.encode(tab.splitTree)
        SessionManager.shared.updateTabSplitTree(tab.id, splitTreeData: splitTreeData, activePaneId: tab.activePaneId)
    }

    private func handleDrop(payload: SplitDropPayload, destination: AgentStudioTerminalView, zone: DropZone, tab: inout TabItem) {
        switch payload.kind {
        case .existingTab(_, let worktreeId, _, _):
            // Find the existing terminal view across all tabs
            let existingTerminal = tabItems.flatMap { $0.splitTree.allViews }
                .first { $0.worktree.id == worktreeId }

            guard let terminalView = existingTerminal else { return }

            // Remove from source tab (find by checking which tab contains this view)
            if let sourceIndex = tabItems.firstIndex(where: { $0.splitTree.allViews.contains { $0.id == terminalView.id } }) {
                // Don't remove from the destination tab itself
                if tabItems[sourceIndex].id != tab.id {
                    var sourceTab = tabItems[sourceIndex]
                    if let newTree = sourceTab.splitTree.removing(view: terminalView) {
                        // Source tab still has other panes
                        sourceTab.splitTree = newTree
                        if sourceTab.activePaneId == terminalView.id {
                            sourceTab.activePaneId = newTree.allViews.first?.id
                        }
                        sourceTab.title = sourceTab.displayTitle
                        tabItems[sourceIndex] = sourceTab
                    } else {
                        // Source tab is now empty — remove it
                        tabItems.remove(at: sourceIndex)
                    }
                }
            }

            // Insert into split tree
            if let newTree = try? tab.splitTree.inserting(view: terminalView, at: destination, direction: zone.newDirection) {
                tab.splitTree = newTree
                tab.activePaneId = terminalView.id
                tab.title = tab.displayTitle

                // Notify SurfaceManager of the move (updates lastActiveAt and focus state)
                if let surfaceId = terminalView.surfaceId {
                    SurfaceManager.shared.attach(surfaceId, to: terminalView.containerId)
                }
            }

        case .newTerminal:
            // Create a new terminal in the split
            // For now, this requires user interaction to select a worktree
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

        // Create single-pane split tree with the view directly
        let splitTree = TerminalSplitTree(view: terminalView)

        // Create tab item with the split tree
        let tabItem = TabItem(
            id: UUID(),
            title: worktree.name,
            primaryWorktreeId: worktree.id,
            primaryProjectId: project.id,
            splitTree: splitTree,
            activePaneId: terminalView.id
        )
        tabItems.append(tabItem)

        // Select the restored tab (this will update the split container)
        selectTab(id: tabItem.id)

        updateEmptyState()
        ghosttyLogger.info("Restored tab for worktree: \(worktree.name)")
    }
}
