import AppKit
import Observation
import SwiftUI

final class SidebarToolbarButton: NSButton {
    var currentSymbolName = ""
}

enum InboxToolbarUnreadBadgeText {
    static func text(for unreadCount: Int) -> String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }
}

/// Main window controller for AgentStudio
class MainWindowController: NSWindowController, NSWindowDelegate {
    private var splitViewController: MainSplitViewController?
    private var sidebarAccessory: NSTitlebarAccessoryViewController?
    private var inboxAtom: InboxNotificationAtom?
    private var uiState: WorkspaceSidebarState?
    private weak var worktreeToolbarButton: SidebarToolbarButton?
    private weak var inboxToolbarButton: SidebarToolbarButton?
    private var inboxToolbarBadgeHostingView: NSHostingView<UnreadCountBadge>?
    private var isObservingInboxUnread = false
    private var isObservingSidebarSurface = false
    private var awaitsLaunchRestoreResize = false
    private var awaitsLaunchMaximize = false
    private var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
    private var workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom!
    private let windowId = UUID()

    private static let estimatedTitlebarHeight: CGFloat = 40

    convenience init(
        store: WorkspaceStore,
        actionExecutor: ActionExecutor,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleAtom,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        inboxAtom: InboxNotificationAtom,
        inboxPrefsAtom: InboxNotificationPrefsAtom,
        inboxSidebarState: InboxSidebarState,
        paneInboxPresenter: PaneInboxNotificationPresenter,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator()
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentStudio"
        window.backgroundColor = AppStyles.Shell.TabBar.titlebarBackground
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 720, height: 600)
        window.isRestorable = false

        // Always launch maximized to the current screen (not full-screen mode)
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: false)
        } else {
            window.center()
        }

        self.init(window: window)
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.workspaceWindowMemoryAtom = store.windowMemoryAtom
        self.inboxAtom = inboxAtom
        self.uiState = atom(\.workspaceSidebarState)
        window.delegate = self
        applicationLifecycleMonitor.handleWindowRegistered(windowId)

        // Create and set content view controller
        let splitVC = MainSplitViewController(
            store: store,
            workspaceWindowId: windowId,
            actionExecutor: actionExecutor,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            inboxAtom: inboxAtom,
            inboxPrefsAtom: inboxPrefsAtom,
            inboxSidebarState: inboxSidebarState,
            paneInboxPresenter: paneInboxPresenter,
            performanceTraceRecorder: performanceTraceRecorder,
            closeTransitionCoordinator: closeTransitionCoordinator
        )
        self.splitViewController = splitVC
        window.contentViewController = splitVC

        // Set up titlebar and toolbar
        setupTitlebarAccessory()
        setupToolbar()
    }

    // MARK: - NSWindowDelegate (frame persistence)

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
        guard awaitsLaunchRestoreResize else { return }
        awaitsLaunchRestoreResize = false
        applicationLifecycleMonitor.handleLaunchLayoutSettled()
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func windowDidBecomeMain(_ notification: Notification) {
        applyLaunchMaximizeIfNeeded()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyLaunchMaximizeIfNeeded()
        applicationLifecycleMonitor.handleWindowDidBecomeKey(windowId)
    }

    func windowDidResignKey(_ notification: Notification) {
        applicationLifecycleMonitor.handleWindowDidResignKey(windowId)
    }

    func makePaneFocusAppControl(store: WorkspaceStore) -> (any PaneFocusAppControlling)? {
        splitViewController?.makePaneFocusAppControl(store: store)
    }

    private func saveWindowFrame() {
        guard let frame = window?.frame else { return }
        workspaceWindowMemoryAtom.setWindowFrame(frame)
    }

    // MARK: - Frame Validation

    /// Check if at least the titlebar region of the frame is visible on any connected screen.
    private static func isFrameOnScreen(_ frame: NSRect) -> Bool {
        guard !NSScreen.screens.isEmpty else { return false }
        let titleBarRect = NSRect(
            x: frame.origin.x, y: frame.maxY - estimatedTitlebarHeight,
            width: frame.width, height: estimatedTitlebarHeight
        )
        return NSScreen.screens.contains { $0.visibleFrame.intersects(titleBarRect) }
    }

    /// Shrink the window if it exceeds the current screen's visible area.
    private static func clampFrameToScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        var frame = window.frame
        var changed = false
        if frame.width > screenFrame.width {
            frame.size.width = screenFrame.width
            changed = true
        }
        if frame.height > screenFrame.height {
            frame.size.height = screenFrame.height
            changed = true
        }
        if changed {
            window.setFrame(frame, display: true)
        }
    }

    // MARK: - Titlebar Accessory

    private func setupTitlebarAccessory() {
        let worktreeSidebarPresentation = CommandDispatcher.shared.definition(for: .showWorktreeSidebar)
        let inboxSidebarPresentation = CommandDispatcher.shared.definition(for: .showInboxNotifications)

        // Worktree sidebar button
        let worktreeButton = makeSidebarToolbarButton(
            identifier: "worktreeToolbarButton",
            accessibilityLabel: worktreeSidebarPresentation.actionSpec.label,
            toolTip: worktreeSidebarPresentation.controlToolTip,
            action: #selector(showWorktreeSidebarAction)
        )
        self.worktreeToolbarButton = worktreeButton

        // Inbox sidebar button
        let inboxButton = makeSidebarToolbarButton(
            identifier: "inboxToolbarBell",
            accessibilityLabel: inboxSidebarPresentation.actionSpec.label,
            toolTip: inboxSidebarPresentation.controlToolTip,
            action: #selector(showInboxSidebarAction)
        )
        self.inboxToolbarButton = inboxButton
        installInboxUnreadBadge(on: inboxButton)

        // Stack buttons horizontally with standard titlebar spacing
        let stack = NSStackView(views: [worktreeButton, inboxButton])
        stack.identifier = NSUserInterfaceItemIdentifier("sidebarToolbarAccessory")
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 104, height: 28)

        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.view = stack
        accessoryVC.layoutAttribute = .left

        window?.addTitlebarAccessoryViewController(accessoryVC)
        self.sidebarAccessory = accessoryVC
        updateSidebarToolbarIcons()
        observeSidebarSurface()
    }

    private func makeSidebarToolbarButton(
        identifier: String,
        accessibilityLabel: String,
        toolTip: String,
        action: Selector
    ) -> SidebarToolbarButton {
        let button = SidebarToolbarButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.image = sidebarToolbarImage(
            symbolName: "circle",
            accessibilityDescription: accessibilityLabel
        )
        return button
    }

    private func updateSidebarToolbarIcons() {
        guard let uiState else { return }
        let worktreeSymbol =
            uiState.sidebarSurface == .repos
            ? "square.stack.3d.down.right.fill"
            : "square.stack.3d.down.right"
        let inboxSymbol =
            uiState.sidebarSurface == .inbox
            ? "bell.fill"
            : "bell"

        applySidebarToolbarImage(
            symbolName: worktreeSymbol,
            accessibilityDescription: CommandDispatcher.shared.definition(for: .showWorktreeSidebar).actionSpec.label,
            to: worktreeToolbarButton
        )
        applySidebarToolbarImage(
            symbolName: inboxSymbol,
            accessibilityDescription: CommandDispatcher.shared.definition(for: .showInboxNotifications).actionSpec
                .label,
            to: inboxToolbarButton
        )
    }

    private func sidebarToolbarImage(
        symbolName: String,
        accessibilityDescription: String
    ) -> NSImage? {
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        image?.setName(NSImage.Name(symbolName))
        return image
    }

    private func applySidebarToolbarImage(
        symbolName: String,
        accessibilityDescription: String,
        to button: SidebarToolbarButton?
    ) {
        button?.currentSymbolName = symbolName
        button?.image = sidebarToolbarImage(
            symbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
    }

    private func observeSidebarSurface() {
        guard !isObservingSidebarSurface, let uiState else { return }
        isObservingSidebarSurface = true
        withObservationTracking {
            _ = uiState.sidebarSurface
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingSidebarSurface = false
                self.updateSidebarToolbarIcons()
                self.observeSidebarSurface()
            }
        }
    }

    private func installInboxUnreadBadge(on button: NSButton) {
        let badgeAnchor = NSView()
        badgeAnchor.identifier = NSUserInterfaceItemIdentifier("inboxToolbarBadgeAnchor")
        badgeAnchor.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(badgeAnchor)

        let badge = NSHostingView(rootView: UnreadCountBadge(text: "1"))
        badge.identifier = NSUserInterfaceItemIdentifier("inboxToolbarUnreadBadge")
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .vertical)
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badgeAnchor.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            badgeAnchor.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            badgeAnchor.widthAnchor.constraint(equalToConstant: AppStyles.Shell.Sidebar.badgeHitboxSize),
            badgeAnchor.heightAnchor.constraint(equalToConstant: AppStyles.Shell.Sidebar.badgeHitboxSize),
            badge.topAnchor.constraint(
                equalTo: badgeAnchor.topAnchor,
                constant: -AppStyles.Shell.Sidebar.badgeOffset
            ),
            badge.trailingAnchor.constraint(
                equalTo: badgeAnchor.trailingAnchor,
                constant: AppStyles.Shell.Sidebar.badgeOffset
            ),
        ])
        inboxToolbarBadgeHostingView = badge
        updateInboxUnreadBadge()
        observeInboxUnreadCount()
    }

    private func updateInboxUnreadBadge() {
        let unreadCount = inboxAtom?.globalRollUpAlertCount ?? 0
        guard unreadCount > 0 else {
            inboxToolbarBadgeHostingView?.isHidden = true
            return
        }
        inboxToolbarBadgeHostingView?.rootView = UnreadCountBadge(
            text: InboxToolbarUnreadBadgeText.text(for: unreadCount)
        )
        inboxToolbarBadgeHostingView?.isHidden = false
    }

    private func observeInboxUnreadCount() {
        guard !isObservingInboxUnread else { return }
        isObservingInboxUnread = true
        withObservationTracking {
            _ = inboxAtom?.globalRollUpAlertCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingInboxUnread = false
                self.updateInboxUnreadBadge()
                self.observeInboxUnreadCount()
            }
        }
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    // MARK: - Actions

    func toggleSidebar() {
        splitViewController?.toggleSidebarFromCommand()
    }

    func showSidebarFilter() {
        splitViewController?.showSidebarFilter()
    }

    func showInboxNotifications(commandBarIsKey: Bool) {
        splitViewController?.showInboxNotifications(commandBarIsKey: commandBarIsKey)
    }

    func showRollUpInboxNotifications(commandBarIsKey: Bool) {
        splitViewController?.showRollUpInboxNotifications(commandBarIsKey: commandBarIsKey)
    }

    func showWorktreeSidebar() {
        splitViewController?.showWorktreeSidebar()
    }

    func expandSidebar() {
        splitViewController?.expandSidebar()
    }

    func refocusActivePane() {
        splitViewController?.refocusActivePane()
    }

    func awaitLaunchRestoreAfterNextResize() {
        awaitsLaunchRestoreResize = true
    }

    func prepareLaunchMaximizeAndRestore() {
        awaitsLaunchMaximize = true
    }

    func syncVisibleTerminalGeometry(reason: StaticString) {
        splitViewController?.syncVisibleTerminalGeometry(reason: reason)
    }

    func completeLaunchPresentation() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        applyLaunchMaximizeIfNeeded()
    }

    private func applyLaunchMaximizeIfNeeded() {
        guard awaitsLaunchMaximize else { return }
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        awaitsLaunchMaximize = false
        let targetFrame = screen.visibleFrame
        RestoreTrace.log(
            "MainWindowController.applyLaunchMaximize currentFrame=\(NSStringFromRect(window.frame)) targetFrame=\(NSStringFromRect(targetFrame))"
        )
        if window.frame.equalTo(targetFrame) {
            RestoreTrace.log("MainWindowController.applyLaunchMaximize alreadyAtTargetFrame")
            applicationLifecycleMonitor.handleLaunchLayoutSettled()
            window.contentView?.layoutSubtreeIfNeeded()
            return
        }
        // Mark launch geometry as settled before the maximize resize begins so the
        // first full-size terminalContainer bounds publish can immediately
        // materialize the active tab instead of waiting for the later bridge path.
        applicationLifecycleMonitor.handleLaunchLayoutSettled()
        awaitLaunchRestoreAfterNextResize()
        window.setFrame(targetFrame, display: true)
    }

    @objc private func toggleSidebarAction() {
        toggleSidebar()
    }

    @objc private func showWorktreeSidebarAction() {
        showWorktreeSidebar()
        updateSidebarToolbarIcons()
    }

    @objc private func showInboxSidebarAction() {
        showRollUpInboxNotifications(commandBarIsKey: false)
        updateSidebarToolbarIcons()
    }

    @objc private func watchFolderAction() {
        CommandDispatcher.shared.dispatch(.watchFolder)
    }

    private func commandToolbarButtonItem(
        for command: AppCommand,
        action: Selector
    ) -> NSToolbarItem {
        let definition = CommandDispatcher.shared.definition(for: command)
        let item = NSToolbarItem(itemIdentifier: .watchFolder)
        item.label = definition.actionSpec.label
        item.paletteLabel = definition.actionSpec.label
        item.toolTip = definition.controlToolTip

        let button = NSButton(
            title: definition.actionSpec.label,
            target: self,
            action: action
        )
        button.bezelStyle = .rounded
        button.bezelColor = .systemTeal
        button.controlSize = .regular

        if case .system(let systemName) = definition.actionSpec.icon {
            button.image = NSImage(
                systemSymbolName: systemName.rawValue,
                accessibilityDescription: definition.actionSpec.label
            )
        }

        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(
            string: "  " + definition.actionSpec.label,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        )
        item.view = button
        return item
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .managementLayer,
            .space,
            .watchFolder,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .managementLayer:
            let presentation = CommandDispatcher.shared.definition(for: .toggleManagementLayer).actionSpec
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = presentation.label
            item.paletteLabel = presentation.label
            // SwiftUI hosting for reactive toggle state
            let hostingView = NSHostingView(rootView: ManagementLayerToolbarButton())
            hostingView.sizingOptions = .intrinsicContentSize
            item.view = hostingView
            return item
        case .watchFolder:
            return commandToolbarButtonItem(for: .watchFolder, action: #selector(watchFolderAction))

        default:
            return nil
        }
    }
}

// MARK: - Toolbar Item Identifiers
