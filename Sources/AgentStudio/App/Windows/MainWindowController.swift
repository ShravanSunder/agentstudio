import AppKit
import Observation
import SwiftUI

/// Main window controller for AgentStudio
class MainWindowController: NSWindowController, NSWindowDelegate {
    private var splitViewController: MainSplitViewController?
    private var sidebarAccessory: NSTitlebarAccessoryViewController?
    private var inboxAtom = InboxNotificationAtom()
    private weak var inboxToolbarBellDot: NSView?
    private var isObservingInboxUnread = false
    private var awaitsLaunchRestoreResize = false
    private var awaitsLaunchMaximize = false
    private var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
    private let windowId = UUID()

    private static let windowFrameKey = "windowFrame"
    private static let estimatedTitlebarHeight: CGFloat = 40

    convenience init(
        store: WorkspaceStore,
        actionExecutor: ActionExecutor,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleAtom,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        inboxAtom: InboxNotificationAtom = InboxNotificationAtom(),
        inboxPrefsAtom: InboxNotificationPrefsAtom = InboxNotificationPrefsAtom(),
        drawerInboxPresenter: InboxNotificationDrawerPresenter = InboxNotificationDrawerPresenter()
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

        // Always launch maximized to the current screen (not full-screen mode)
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: false)
        } else {
            window.center()
        }

        self.init(window: window)
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.inboxAtom = inboxAtom
        window.delegate = self
        applicationLifecycleMonitor.handleWindowRegistered(windowId)

        // Create and set content view controller
        let splitVC = MainSplitViewController(
            store: store,
            actionExecutor: actionExecutor,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            inboxAtom: inboxAtom,
            inboxPrefsAtom: inboxPrefsAtom,
            drawerInboxPresenter: drawerInboxPresenter
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

    private func saveWindowFrame() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.windowFrameKey)
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
        let filterSidebarPresentation = CommandDispatcher.shared.definition(for: .filterSidebar)

        // Worktree sidebar button
        let worktreeButton = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        worktreeButton.image = NSImage(
            systemSymbolName: "sidebar.left",
            accessibilityDescription: worktreeSidebarPresentation.actionSpec.label
        )
        worktreeButton.bezelStyle = .accessoryBarAction
        worktreeButton.isBordered = false
        worktreeButton.target = self
        worktreeButton.action = #selector(showWorktreeSidebarAction)
        worktreeButton.toolTip = worktreeSidebarPresentation.controlToolTip

        // Inbox sidebar button
        let inboxButton = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        inboxButton.image = NSImage(
            systemSymbolName: "bell",
            accessibilityDescription: inboxSidebarPresentation.actionSpec.label
        )
        inboxButton.bezelStyle = .accessoryBarAction
        inboxButton.isBordered = false
        inboxButton.identifier = NSUserInterfaceItemIdentifier("inboxToolbarBell")
        inboxButton.target = self
        inboxButton.action = #selector(showInboxSidebarAction)
        inboxButton.toolTip = inboxSidebarPresentation.controlToolTip
        installInboxUnreadDot(on: inboxButton)

        // Search button
        let searchButton = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        searchButton.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: filterSidebarPresentation.actionSpec.label
        )
        searchButton.bezelStyle = .accessoryBarAction
        searchButton.isBordered = false
        searchButton.target = self
        searchButton.action = #selector(filterSidebarAction)
        searchButton.toolTip = filterSidebarPresentation.controlToolTip

        // Stack buttons horizontally with standard titlebar spacing
        let stack = NSStackView(views: [worktreeButton, inboxButton, searchButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 128, height: 28)

        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.view = stack
        accessoryVC.layoutAttribute = .left

        window?.addTitlebarAccessoryViewController(accessoryVC)
        self.sidebarAccessory = accessoryVC
    }

    private func installInboxUnreadDot(on button: NSButton) {
        let dot = NSView(frame: NSRect(x: 24, y: 18, width: 6, height: 6))
        dot.identifier = NSUserInterfaceItemIdentifier("inboxToolbarBellDot")
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 3
        dot.autoresizingMask = [.minXMargin, .minYMargin]
        button.addSubview(dot)
        inboxToolbarBellDot = dot
        updateInboxUnreadDot()
        observeInboxUnreadCount()
    }

    private func updateInboxUnreadDot() {
        inboxToolbarBellDot?.isHidden = inboxAtom.globalUnreadCount == 0
    }

    private func observeInboxUnreadCount() {
        guard !isObservingInboxUnread else { return }
        isObservingInboxUnread = true
        withObservationTracking {
            _ = inboxAtom.globalUnreadCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingInboxUnread = false
                self.updateInboxUnreadDot()
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
    }

    @objc private func showInboxSidebarAction() {
        showInboxNotifications(commandBarIsKey: false)
    }

    @objc private func filterSidebarAction() {
        CommandDispatcher.shared.dispatch(.filterSidebar)
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .managementLayer,
            .space,
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

        default:
            return nil
        }
    }
}

// MARK: - Toolbar Item Identifiers
