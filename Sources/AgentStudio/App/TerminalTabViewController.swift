import AppKit
import GhosttyKit

/// Tab-based terminal controller using pure AppKit
class TerminalTabViewController: NSViewController {
    private var tabView: NSTabView!
    private var terminals: [UUID: AgentStudioTerminalView] = [:]
    private var tabToWorktree: [NSTabViewItem: UUID] = [:]
    private var emptyStateView: NSView?

    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true

        // Create tab view
        tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.delegate = self
        containerView.addSubview(tabView)

        // Create empty state view
        let emptyView = createEmptyStateView()
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(emptyView)
        self.emptyStateView = emptyView

        // Add leading padding so split view drag handle is accessible
        let leadingPadding: CGFloat = 8

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: containerView.topAnchor),
            tabView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: leadingPadding),
            tabView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tabView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            emptyView.topAnchor.constraint(equalTo: containerView.topAnchor),
            emptyView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: leadingPadding),
            emptyView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        view = containerView
        updateEmptyState()
    }

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

        // Add Project button with accent color
        let addButton = NSButton(title: "Add Project...", target: self, action: #selector(addProjectAction))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .large
        addButton.keyEquivalent = "\r"  // Make it the default button

        stackView.addArrangedSubview(iconContainer)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(addButton)
        stackView.addArrangedSubview(hintLabel)

        // Add custom spacing
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
        tabView.isHidden = !hasTerminals
        emptyStateView?.isHidden = hasTerminals
    }

    // MARK: - Terminal Management

    func openTerminal(for worktree: Worktree, in project: Project) {
        // Check if already open
        if let existingTerminal = terminals[worktree.id] {
            // Find and select the tab
            for (tabItem, worktreeId) in tabToWorktree {
                if worktreeId == worktree.id {
                    tabView.selectTabViewItem(tabItem)
                    existingTerminal.window?.makeFirstResponder(existingTerminal)
                    return
                }
            }
        }

        // Create new terminal
        let terminalView = AgentStudioTerminalView(
            worktree: worktree,
            project: project
        )
        terminals[worktree.id] = terminalView

        // Create tab item
        let tabItem = NSTabViewItem()
        tabItem.label = worktree.name
        tabItem.view = terminalView
        tabItem.toolTip = worktree.path.path

        tabToWorktree[tabItem] = worktree.id

        tabView.addTabViewItem(tabItem)
        tabView.selectTabViewItem(tabItem)

        updateEmptyState()

        // Make terminal first responder
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }

    func closeTerminal(for worktreeId: UUID) {
        guard let terminal = terminals[worktreeId] else { return }
        terminal.terminateProcess()

        // Find and remove the tab
        for (tabItem, id) in tabToWorktree {
            if id == worktreeId {
                tabView.removeTabViewItem(tabItem)
                tabToWorktree.removeValue(forKey: tabItem)
                break
            }
        }

        terminals.removeValue(forKey: worktreeId)
        updateEmptyState()

        // Update session manager
        Task { @MainActor in
            if let tab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == worktreeId }) {
                SessionManager.shared.closeTab(tab)
            }
        }
    }

    func closeActiveTab() {
        guard let selectedItem = tabView.selectedTabViewItem,
              let worktreeId = tabToWorktree[selectedItem] else {
            return
        }
        closeTerminal(for: worktreeId)
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabView.numberOfTabViewItems else { return }
        tabView.selectTabViewItem(at: index)
    }

    // MARK: - Tab Close Handling

    override func viewDidLoad() {
        super.viewDidLoad()

        // Listen for process termination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProcessTerminated(_:)),
            name: .terminalProcessTerminated,
            object: nil
        )
    }

    @objc private func handleProcessTerminated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let worktreeId = userInfo["worktreeId"] as? UUID else {
            return
        }

        // Clean up when process terminates
        closeTerminal(for: worktreeId)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - NSTabViewDelegate

extension TerminalTabViewController: NSTabViewDelegate {
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let tabItem = tabViewItem,
              let worktreeId = tabToWorktree[tabItem] else {
            return
        }

        // Update active tab in session manager
        Task { @MainActor in
            if let tab = SessionManager.shared.openTabs.first(where: { $0.worktreeId == worktreeId }) {
                SessionManager.shared.activeTabId = tab.id
            }
        }

        // Make terminal first responder
        if let terminal = terminals[worktreeId] {
            DispatchQueue.main.async {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
    }
}

