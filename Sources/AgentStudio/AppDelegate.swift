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

    private(set) var commandBarController = CommandBarPanelController()

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

        // Set up main menu (doesn't depend on session restore)
        setupMainMenu()

        // Create new services
        store = WorkspaceStore()
        store.restore()

        runtime = SessionRuntime(store: store)
        viewRegistry = ViewRegistry()
        coordinator = TerminalViewCoordinator(store: store, viewRegistry: viewRegistry, runtime: runtime)
        executor = ActionExecutor(store: store, viewRegistry: viewRegistry, coordinator: coordinator)
        tabBarAdapter = TabBarAdapter(store: store)

        // Restore terminal views for persisted sessions
        coordinator.restoreAllViews()

        // Create main window
        mainWindowController = MainWindowController(
            store: store,
            executor: executor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        mainWindowController?.showWindow(nil)
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
        fileMenu.addItem(NSMenuItem(title: "New Window", action: #selector(newWindow), keyEquivalent: "n"))
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(newTabItem)
        fileMenu.addItem(NSMenuItem.separator())
        // Cmd+W closes tab (standard terminal behavior)
        fileMenu.addItem(NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w"))
        let closeWindowItem = NSMenuItem(title: "Close Window", action: #selector(closeWindow), keyEquivalent: "W")
        closeWindowItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(closeWindowItem)
        fileMenu.addItem(NSMenuItem.separator())
        let addRepoItem = NSMenuItem(title: "Add Repo...", action: #selector(addRepo), keyEquivalent: "O")
        addRepoItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(addRepoItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        let undoCloseTabItem = NSMenuItem(title: "Undo Close Tab", action: #selector(undoCloseTab), keyEquivalent: "T")
        undoCloseTabItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(undoCloseTabItem)
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
        viewMenu.addItem(NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "s"))
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        let filterSidebarItem = NSMenuItem(title: "Filter Sidebar", action: #selector(filterSidebar), keyEquivalent: "f")
        filterSidebarItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(filterSidebarItem)
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

        // Tab switching shortcuts (Cmd+1 through Cmd+9)
        windowMenu.addItem(NSMenuItem.separator())
        for i in 1...9 {
            let item = NSMenuItem(title: "Select Tab \(i)", action: #selector(selectTab(_:)), keyEquivalent: "\(i)")
            item.tag = i - 1  // 0-indexed
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
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else { return }
        commandBarController.show(prefix: ">", parentWindow: window)
    }

    @objc private func showCommandBarPanes() {
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else { return }
        commandBarController.show(prefix: "@", parentWindow: window)
    }
}
