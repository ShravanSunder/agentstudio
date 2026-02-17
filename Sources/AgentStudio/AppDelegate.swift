import AppKit
import os.log
import SwiftUI

private let appLogger = Logger(subsystem: "com.agentstudio", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?

    // MARK: - Shared Services (created once at launch)

    private var store: WorkspaceStore!
    private var viewRegistry: ViewRegistry!
    private var coordinator: TerminalViewCoordinator!
    private var executor: ActionExecutor!
    private var tabBarAdapter: TabBarAdapter!
    private var runtime: SessionRuntime!

    // MARK: - Command Bar

    private(set) var commandBarController: CommandBarPanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set GHOSTTY_RESOURCES_DIR before any GhosttyKit initialization.
        // This lets GhosttyKit find xterm-ghostty terminfo in both dev and bundle builds.
        // The value must be a subdirectory (e.g. .../ghostty) whose parent contains
        // terminfo/, because GhosttyKit computes TERMINFO = dirname(this) + "/terminfo".
        if let resourcesDir = SessionConfiguration.resolveGhosttyResourcesDir() {
            setenv("GHOSTTY_RESOURCES_DIR", resourcesDir, 1)  // 1 = overwrite; our resolved path must take priority
        }

        // Check for worktrunk dependency
        checkWorktrunkInstallation()

        // Set up main menu (doesn't depend on zmx restore)
        setupMainMenu()

        // Create new services
        store = WorkspaceStore()
        store.restore()

        runtime = SessionRuntime(store: store)

        // Clean up orphan zmx daemons from previous launches
        cleanupOrphanZmxSessions()

        viewRegistry = ViewRegistry()
        coordinator = TerminalViewCoordinator(store: store, viewRegistry: viewRegistry, runtime: runtime)
        executor = ActionExecutor(store: store, viewRegistry: viewRegistry, coordinator: coordinator)
        tabBarAdapter = TabBarAdapter(store: store)
        commandBarController = CommandBarPanelController(store: store, dispatcher: .shared)

        // Restore terminal views for persisted panes
        coordinator.restoreAllViews()

        // Create main window
        mainWindowController = MainWindowController(
            store: store,
            executor: executor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        mainWindowController?.showWindow(nil)

        // Force maximized after showWindow — macOS state restoration may override
        // the frame set during init.
        if let window = mainWindowController?.window, let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }
    }

    // MARK: - Dependency Check

    private func checkWorktrunkInstallation() {
        guard !WorktrunkService.shared.isInstalled else { return }

        let alert = NSAlert()
        alert.messageText = "Worktrunk Not Installed"
        alert.informativeText = "AgentStudio uses Worktrunk for git worktree management. Would you like to install it via Homebrew?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Install with Homebrew")
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Open Terminal and run install
            let script = """
                tell application "Terminal"
                    activate
                    do script "\(WorktrunkService.shared.installCommand)"
                end tell
                """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }

        case .alertSecondButtonReturn:
            // Copy command to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(WorktrunkService.shared.installCommand, forType: .string)

        default:
            break
        }
    }

    // MARK: - Orphan Cleanup

    /// Kill zmx daemons that aren't tracked by any persisted session.
    /// Runs once at startup to prevent accumulation across app restarts.
    /// Called from `applicationDidFinishLaunching` (always main thread).
    @MainActor
    private func cleanupOrphanZmxSessions() {
        let config = SessionConfiguration.detect()
        guard let zmxPath = config.zmxPath else {
            appLogger.debug("zmx not found — skipping orphan cleanup")
            return
        }

        // Collect known zmx session IDs from persisted panes (main-actor access).
        // These are the panes we expect to exist — everything else is an orphan.
        // Handles both main panes (worktree-based IDs) and drawer panes (parent+child UUID IDs).
        let knownSessionIds = Set(
            store.panes.values
                .filter { $0.provider == .zmx }
                .compactMap { pane -> String? in
                    // Drawer pane: session ID from parent + drawer pane UUIDs
                    if let parentPaneId = pane.parentPaneId {
                        return ZmxBackend.drawerSessionId(
                            parentPaneId: parentPaneId,
                            drawerPaneId: pane.id
                        )
                    }
                    // Main pane: session ID from repo + worktree stable keys
                    guard let worktreeId = pane.worktreeId,
                          let repo = store.repo(containing: worktreeId),
                          let worktree = store.worktree(worktreeId) else { return nil }
                    return ZmxBackend.sessionId(
                        repoStableKey: repo.stableKey,
                        worktreeStableKey: worktree.stableKey,
                        paneId: pane.id
                    )
                }
        )

        let backend = ZmxBackend(zmxPath: zmxPath, zmxDir: config.zmxDir)

        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let orphans = await backend.discoverOrphanSessions(excluding: knownSessionIds)
                        if !orphans.isEmpty {
                            appLogger.info("Found \(orphans.count) orphan zmx session(s) — cleaning up")
                            for orphanId in orphans {
                                try Task.checkCancellation()
                                do {
                                    try await backend.destroySessionById(orphanId)
                                    appLogger.debug("Killed orphan zmx session: \(orphanId)")
                                } catch is CancellationError {
                                    throw CancellationError()
                                } catch {
                                    appLogger.warning("Failed to kill orphan zmx session \(orphanId): \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(30))
                        throw CancellationError()
                    }
                    // Wait for whichever finishes first, cancel the other
                    try await group.next()
                    group.cancelAll()
                }
            } catch is CancellationError {
                appLogger.warning("Orphan zmx cleanup timed out after 30s")
            } catch {
                appLogger.warning("Orphan zmx cleanup failed: \(error.localizedDescription)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running for menu bar / dock
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen main window when clicking dock icon
        if !flag {
            showOrCreateMainWindow()
        }
        return true
    }

    private func showOrCreateMainWindow() {
        if let window = mainWindowController?.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            mainWindowController = MainWindowController(
                store: store,
                executor: executor,
                tabBarAdapter: tabBarAdapter,
                viewRegistry: viewRegistry
            )
            mainWindowController?.showWindow(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isDirty else { return .terminateNow }
        // Flush before exit — guarantees pending markDirty() writes land on disk.
        if !store.flush() {
            appLogger.warning("Workspace flush failed at termination")
        }
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu Setup

    /// Create an NSMenuItem whose shortcut is read from CommandDispatcher (single source of truth).
    /// Called from setupMainMenu() which runs on the main thread during app launch.
    private func menuItem(_ title: String, command: AppCommand, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        MainActor.assumeIsolated {
            if let binding = CommandDispatcher.shared.definitions[command]?.keyBinding {
                binding.apply(to: item)
            }
        }
        return item
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About AgentStudio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide AgentStudio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit AgentStudio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("New Window", command: .newWindow, action: #selector(newWindow)))
        fileMenu.addItem(menuItem("New Tab", command: .newTab, action: #selector(newTab)))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(menuItem("Close Tab", command: .closeTab, action: #selector(closeTab)))
        fileMenu.addItem(menuItem("Close Window", command: .closeWindow, action: #selector(closeWindow)))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(menuItem("Add Repo...", command: .addRepo, action: #selector(addRepo)))

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(menuItem("Undo Close Tab", command: .undoCloseTab, action: #selector(undoCloseTab)))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(menuItem("Toggle Sidebar", command: .toggleSidebar, action: #selector(toggleSidebar)))
        viewMenu.addItem(menuItem("Filter Sidebar", command: .filterSidebar, action: #selector(filterSidebar)))
        viewMenu.addItem(NSMenuItem.separator())

        // Command bar shortcuts
        viewMenu.addItem(NSMenuItem(title: "Quick Open", action: #selector(showCommandBar), keyEquivalent: "p"))
        let commandModeItem = NSMenuItem(title: "Command Palette", action: #selector(showCommandBarCommands), keyEquivalent: "p")
        commandModeItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(commandModeItem)
        let paneModeItem = NSMenuItem(title: "Go to Pane", action: #selector(showCommandBarPanes), keyEquivalent: "p")
        paneModeItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(paneModeItem)
        viewMenu.addItem(NSMenuItem.separator())

        // Full Screen uses ⌃⌘F (not ⇧⌘F) to avoid conflict with Filter Sidebar
        viewMenu.addItem(NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"))
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .control]

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))

        // Tab switching shortcuts (⌘1 through ⌘9)
        windowMenu.addItem(NSMenuItem.separator())
        for (i, command) in AppCommand.selectTabCommands.enumerated() {
            let item = menuItem("Select Tab \(i + 1)", command: command, action: #selector(selectTab(_:)))
            item.tag = i  // 0-indexed
            windowMenu.addItem(item)
        }

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(NSMenuItem(title: "AgentStudio Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?"))

        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        // Open settings window
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 300))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func newWindow() {
        showOrCreateMainWindow()
    }

    @objc private func newTab() {
        NotificationCenter.default.post(name: .newTabRequested, object: nil)
    }

    @objc private func closeTab() {
        NotificationCenter.default.post(name: .closeTabRequested, object: nil)
    }

    @objc private func undoCloseTab() {
        NotificationCenter.default.post(name: .undoCloseTabRequested, object: nil)
    }

    @objc private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    @objc private func addRepo() {
        NotificationCenter.default.post(name: .addRepoRequested, object: nil)
    }

    @objc private func toggleSidebar() {
        mainWindowController?.toggleSidebar()
    }

    @objc private func filterSidebar() {
        NotificationCenter.default.post(name: .filterSidebarRequested, object: nil)
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        NotificationCenter.default.post(
            name: .selectTabAtIndex,
            object: nil,
            userInfo: ["index": sender.tag]
        )
    }

    // MARK: - Command Bar Actions

    @objc private func showCommandBar() {
        appLogger.info("showCommandBar triggered")
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appLogger.warning("No window available for command bar")
            return
        }
        commandBarController.show(prefix: nil, parentWindow: window)
    }

    @objc private func showCommandBarCommands() {
        appLogger.info("showCommandBarCommands triggered")
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appLogger.warning("No window available for command bar (commands)")
            return
        }
        commandBarController.show(prefix: ">", parentWindow: window)
    }

    @objc private func showCommandBarPanes() {
        appLogger.info("showCommandBarPanes triggered")
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appLogger.warning("No window available for command bar (panes)")
            return
        }
        commandBarController.show(prefix: "@", parentWindow: window)
    }
}
