import AppKit
import SwiftUI

/// Main window controller for AgentStudio
class MainWindowController: NSWindowController, NSWindowDelegate {
    private var splitViewController: MainSplitViewController?
    private var sidebarAccessory: NSTitlebarAccessoryViewController?
    private var awaitsLaunchRestoreResize = false
    private var awaitsLaunchMaximize = false
    private var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
    private let windowId = UUID()

    private static let windowFrameKey = "windowFrame"
    private static let estimatedTitlebarHeight: CGFloat = 40

    convenience init(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache,
        uiStore: WorkspaceUIStore,
        actionExecutor: ActionExecutor,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        tabBarAdapter: TabBarAdapter, viewRegistry: ViewRegistry
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentStudio"
        window.backgroundColor = AppStyle.titlebarBackground
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
        window.delegate = self
        applicationLifecycleMonitor.handleWindowRegistered(windowId)

        // Create and set content view controller
        let splitVC = MainSplitViewController(
            store: store,
            repoCache: repoCache,
            uiStore: uiStore,
            actionExecutor: actionExecutor,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
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
        window?.contentView?.layoutSubtreeIfNeeded()
        applicationLifecycleMonitor.handleLaunchLayoutSettled()
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
        // Sidebar toggle button
        let toggleButton = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        toggleButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
        toggleButton.bezelStyle = .accessoryBarAction
        toggleButton.isBordered = false
        toggleButton.target = self
        toggleButton.action = #selector(toggleSidebarAction)
        toggleButton.toolTip = "Toggle Sidebar (⌘\\)"

        // Search button
        let searchButton = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        searchButton.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Filter Sidebar")
        searchButton.bezelStyle = .accessoryBarAction
        searchButton.isBordered = false
        searchButton.target = self
        searchButton.action = #selector(filterSidebarAction)
        searchButton.toolTip = "Filter Sidebar (⌘⇧F)"

        // Stack both buttons horizontally with standard titlebar spacing
        let stack = NSStackView(views: [toggleButton, searchButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 78, height: 28)

        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.view = stack
        accessoryVC.layoutAttribute = .left

        window?.addTitlebarAccessoryViewController(accessoryVC)
        self.sidebarAccessory = accessoryVC
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
            window.contentView?.layoutSubtreeIfNeeded()
            applicationLifecycleMonitor.handleLaunchLayoutSettled()
            return
        }
        awaitLaunchRestoreAfterNextResize()
        window.setFrame(targetFrame, display: true)
    }

    @objc private func toggleSidebarAction() {
        toggleSidebar()
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
            .managementMode,
            .space,
            .addRepo,
            .addFolder,
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
        case .managementMode:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Management Mode"
            item.paletteLabel = "Management Mode"
            // SwiftUI hosting for reactive toggle state
            let hostingView = NSHostingView(rootView: ManagementModeToolbarButton())
            hostingView.sizingOptions = .intrinsicContentSize
            item.view = hostingView
            return item

        case .addRepo:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Add Repo"
            item.paletteLabel = "Add Repo"
            item.toolTip = "Add a repo (⌘⇧O)"
            item.isBordered = true
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Repo")
            item.action = #selector(addRepoAction)
            item.target = self
            return item

        case .addFolder:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Add Folder"
            item.paletteLabel = "Add Folder"
            item.toolTip = "Add folder containing repos (⌘⌥⇧O)"
            let button = NSButton(title: "Add Folder", target: self, action: #selector(addFolderAction))
            button.bezelStyle = .rounded
            button.bezelColor = .systemTeal
            button.controlSize = .regular
            button.image = NSImage(
                systemSymbolName: "folder.badge.questionmark",
                accessibilityDescription: "Add Folder"
            )
            button.imagePosition = .imageLeading
            item.view = button
            return item

        default:
            return nil
        }
    }

    @objc private func addRepoAction() {
        CommandDispatcher.shared.dispatch(.addRepo)
    }

    @objc private func addFolderAction() {
        CommandDispatcher.shared.dispatch(.addFolder)
    }
}

// MARK: - Toolbar Item Identifiers
