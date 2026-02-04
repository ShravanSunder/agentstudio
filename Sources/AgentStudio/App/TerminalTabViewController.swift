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

    /// Map of worktree ID to terminal view
    private var terminals: [UUID: AgentStudioTerminalView] = [:]

    /// Map of tab ID to worktree ID
    private var tabToWorktree: [UUID: UUID] = [:]

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
        let hasTerminals = !terminals.isEmpty
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
        // Check if already open
        if terminals[worktree.id] != nil {
            // Find and select the existing tab
            if let tabItem = tabItems.first(where: { tabToWorktree[$0.id] == worktree.id }) {
                selectTab(id: tabItem.id)
            }
            return
        }

        // Create new terminal
        let terminalView = AgentStudioTerminalView(
            worktree: worktree,
            project: project
        )
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminals[worktree.id] = terminalView

        // Create tab item
        let tabItem = TabItem(
            id: UUID(),
            title: worktree.name,
            worktreeId: worktree.id
        )
        tabItems.append(tabItem)
        tabToWorktree[tabItem.id] = worktree.id

        // Add terminal to container (hidden initially)
        terminalContainer.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor)
        ])

        // Select the new tab
        selectTab(id: tabItem.id)

        updateEmptyState()
        // Tab bar updates automatically via @Published
    }

    func closeTerminal(for worktreeId: UUID) {
        // Check if terminal still exists (might already be closed)
        guard terminals[worktreeId] != nil else { return }

        // Find the tab
        guard let tabItem = tabItems.first(where: { tabToWorktree[$0.id] == worktreeId }) else { return }

        closeTab(id: tabItem.id)
    }

    private func closeTab(id tabId: UUID) {
        guard let tabIndex = tabItems.firstIndex(where: { $0.id == tabId }),
              let worktreeId = tabToWorktree[tabId],
              let terminal = terminals[worktreeId] else {
            return
        }

        // Terminate and remove terminal
        terminal.terminateProcess()
        terminal.removeFromSuperview()
        terminals.removeValue(forKey: worktreeId)

        // Remove tab
        tabItems.remove(at: tabIndex)
        tabToWorktree.removeValue(forKey: tabId)

        // Select another tab if this was active
        if activeTabId == tabId {
            if let nextTab = tabItems.first {
                selectTab(id: nextTab.id)
            } else {
                activeTabId = nil
            }
        }

        updateEmptyState()
        // Tab bar updates automatically via @Published

        // Update session manager
        Task { @MainActor in
            if let tab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == worktreeId }) {
                SessionManager.shared.closeTab(tab)
            }
        }
    }

    private func selectTab(id tabId: UUID) {
        guard let worktreeId = tabToWorktree[tabId],
              let terminal = terminals[worktreeId] else {
            return
        }

        // Hide all terminals except selected
        for (wId, term) in terminals {
            term.isHidden = (wId != worktreeId)
        }

        activeTabId = tabId
        // Tab bar updates automatically via @Published

        // Make terminal first responder
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }

        // Update session manager
        Task { @MainActor in
            if let tab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == worktreeId }) {
                SessionManager.shared.activeTabId = tab.id
            }
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
            SessionManager.shared.reorderTabs(tabBarState.tabs.map { $0.worktreeId })
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
}
