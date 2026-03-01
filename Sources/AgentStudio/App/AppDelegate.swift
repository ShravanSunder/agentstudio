import AppKit
import SwiftUI
import os.log

private let appLogger = Logger(subsystem: "com.agentstudio", category: "AppDelegate")

struct ZmxOrphanCleanupPlan: Equatable {
    let knownSessionIds: Set<String>
    let shouldSkipCleanup: Bool
}

enum ZmxOrphanCleanupCandidate: Equatable {
    case drawer(parentPaneId: UUID, paneId: UUID)
    case main(paneId: UUID, repoStableKey: String?, worktreeStableKey: String?)
}

enum ZmxOrphanCleanupPlanner {
    static func plan(candidates: [ZmxOrphanCleanupCandidate]) -> ZmxOrphanCleanupPlan {
        var hasUnresolvableMainPane = false
        var knownSessionIds: Set<String> = []
        knownSessionIds.reserveCapacity(candidates.count)

        for candidate in candidates {
            switch candidate {
            case .drawer(let parentPaneId, let paneId):
                knownSessionIds.insert(
                    ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: paneId)
                )
            case .main(let paneId, let repoStableKey, let worktreeStableKey):
                guard let repoStableKey, let worktreeStableKey else {
                    hasUnresolvableMainPane = true
                    continue
                }
                knownSessionIds.insert(
                    ZmxBackend.sessionId(
                        repoStableKey: repoStableKey,
                        worktreeStableKey: worktreeStableKey,
                        paneId: paneId
                    )
                )
            }
        }

        return ZmxOrphanCleanupPlan(
            knownSessionIds: knownSessionIds,
            shouldSkipCleanup: hasUnresolvableMainPane
        )
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?

    // MARK: - Shared Services (created once at launch)

    private var store: WorkspaceStore!
    private var workspaceCacheStore: WorkspaceCacheStore!
    private var workspaceUIStore: WorkspaceUIStore!
    private var workspaceCacheCoordinator: WorkspaceCacheCoordinator!
    private var viewRegistry: ViewRegistry!
    private var paneCoordinator: PaneCoordinator!
    private var executor: ActionExecutor!
    private var tabBarAdapter: TabBarAdapter!
    private var runtime: SessionRuntime!

    // MARK: - Command Bar

    private(set) var commandBarController: CommandBarPanelController!

    // MARK: - OAuth

    private var oauthService: OAuthService!
    private var appEventTask: Task<Void, Never>?
    private var filesystemPipelineBootTask: Task<Void, Never>?

    private func recordBootStep(_ step: WorkspaceBootStep) {
        RestoreTrace.log("workspace.boot.step=\(step.rawValue)")
    }

    // swiftlint:disable:next function_body_length
    private func executeBootStep(
        _ step: WorkspaceBootStep,
        persistor: WorkspacePersistor,
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) {
        switch step {
        case .loadCanonicalStore:
            store = WorkspaceStore()
            store.restore()
            RestoreTrace.log(
                "store.restore complete tabs=\(store.tabs.count) panes=\(store.panes.count) activeTab=\(store.activeTabId?.uuidString ?? "nil")"
            )
        case .loadCacheStore:
            workspaceCacheStore = WorkspaceCacheStore()
            if let cacheState = persistor.loadCache(for: store.workspaceId) {
                for enrichment in cacheState.repoEnrichmentByRepoId.values {
                    workspaceCacheStore.setRepoEnrichment(enrichment)
                }
                for enrichment in cacheState.worktreeEnrichmentByWorktreeId.values {
                    workspaceCacheStore.setWorktreeEnrichment(enrichment)
                }
                for (worktreeId, count) in cacheState.pullRequestCountByWorktreeId {
                    workspaceCacheStore.setPullRequestCount(count, for: worktreeId)
                }
                for (worktreeId, count) in cacheState.notificationCountByWorktreeId {
                    workspaceCacheStore.setNotificationCount(count, for: worktreeId)
                }
                workspaceCacheStore.markRebuilt(
                    sourceRevision: cacheState.sourceRevision,
                    at: cacheState.lastRebuiltAt ?? Date()
                )
            }
        case .loadUIStore:
            workspaceUIStore = WorkspaceUIStore()
            if let uiState = persistor.loadUI(for: store.workspaceId) {
                workspaceUIStore.setExpandedGroups(uiState.expandedGroups)
                for (stableKey, colorHex) in uiState.checkoutColors {
                    workspaceUIStore.setCheckoutColor(colorHex, for: stableKey)
                }
                workspaceUIStore.setFilterText(uiState.filterText)
                workspaceUIStore.setFilterVisible(uiState.isFilterVisible)
            }
        case .establishRuntimeBus:
            runtime = SessionRuntime(store: store)
            cleanupOrphanZmxSessions()
            viewRegistry = ViewRegistry()
            let pipeline = FilesystemGitPipeline(
                bus: paneRuntimeBus,
                fseventStreamClient: DarwinFSEventStreamClient()
            )
            filesystemSource = pipeline
            paneCoordinator = PaneCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: runtime,
                surfaceManager: SurfaceManager.shared,
                runtimeRegistry: .shared,
                paneEventBus: paneRuntimeBus,
                filesystemSource: pipeline
            )
            workspaceCacheCoordinator = WorkspaceCacheCoordinator(
                bus: paneRuntimeBus,
                workspaceStore: store,
                cacheStore: workspaceCacheStore,
                scopeSyncHandler: { [weak pipeline] change in
                    guard let pipeline else { return }
                    await pipeline.applyScopeChange(change)
                }
            )
            executor = ActionExecutor(coordinator: paneCoordinator, store: store)
            tabBarAdapter = TabBarAdapter(store: store)
            commandBarController = CommandBarPanelController(store: store, dispatcher: .shared)
            oauthService = OAuthService()
        case .startFilesystemActor:
            if let filesystemSource {
                let previousTask = filesystemPipelineBootTask
                filesystemPipelineBootTask = Task {
                    if let previousTask {
                        await previousTask.value
                    }
                    await filesystemSource.startFilesystemActor()
                }
            }
        case .startGitProjector:
            if let filesystemSource {
                let previousTask = filesystemPipelineBootTask
                filesystemPipelineBootTask = Task {
                    if let previousTask {
                        await previousTask.value
                    }
                    await filesystemSource.startGitProjector()
                }
            }
        case .startForgeActor:
            if let filesystemSource {
                let previousTask = filesystemPipelineBootTask
                filesystemPipelineBootTask = Task {
                    if let previousTask {
                        await previousTask.value
                    }
                    await filesystemSource.startForgeActor()
                }
            }
        case .startCacheCoordinator:
            workspaceCacheCoordinator.startConsuming()
        case .triggerInitialTopologySync:
            if let filesystemPipelineBootTask {
                Task { [weak self] in
                    await filesystemPipelineBootTask.value
                    await MainActor.run {
                        self?.paneCoordinator.syncFilesystemRootsAndActivity()
                    }
                }
            } else {
                paneCoordinator.syncFilesystemRootsAndActivity()
            }
        case .readyForReactiveSidebar:
            break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RestoreTrace.log("appDidFinishLaunching: begin")
        // Set GHOSTTY_RESOURCES_DIR before any GhosttyKit initialization.
        // This lets GhosttyKit find xterm-ghostty terminfo in both dev and bundle builds.
        // The value must be a subdirectory (e.g. .../ghostty) whose parent contains
        // terminfo/, because GhosttyKit computes TERMINFO = dirname(this) + "/terminfo".
        if let resourcesDir = SessionConfiguration.resolveGhosttyResourcesDir() {
            setenv("GHOSTTY_RESOURCES_DIR", resourcesDir, 1)  // 1 = overwrite; our resolved path must take priority
            RestoreTrace.log("GHOSTTY_RESOURCES_DIR=\(resourcesDir)")
        } else {
            RestoreTrace.log("GHOSTTY_RESOURCES_DIR unresolved")
        }

        // Some parent shells export NO_COLOR=1, which disables ANSI color in CLIs
        // (Codex, Gemini, etc.). Clear it for app-hosted terminal sessions.
        if getenv("NO_COLOR") != nil {
            unsetenv("NO_COLOR")
            RestoreTrace.log("unset NO_COLOR for terminal color support")
        }

        // Check for worktrunk dependency
        checkWorktrunkInstallation()

        // Set up main menu (doesn't depend on zmx restore)
        setupMainMenu()

        // Create new services following the 10-step workspace boot contract.
        let persistor = WorkspacePersistor()
        let paneRuntimeBus = PaneRuntimeEventBus.shared
        var filesystemSource: FilesystemGitPipeline?

        WorkspaceBootSequence.run { [self] step in
            recordBootStep(step)
            executeBootStep(
                step,
                persistor: persistor,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
        }

        // Create main window
        mainWindowController = MainWindowController(
            store: store,
            cacheStore: workspaceCacheStore,
            uiStore: workspaceUIStore,
            actionExecutor: executor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        mainWindowController?.showWindow(nil)
        if let window = mainWindowController?.window {
            RestoreTrace.log(
                "mainWindow showWindow frame=\(NSStringFromRect(window.frame)) content=\(NSStringFromRect(window.contentLayoutRect))"
            )
        } else {
            RestoreTrace.log("mainWindow showWindow: window=nil")
        }

        // Force maximized after showWindow — macOS state restoration may override
        // the frame set during init.
        if let window = mainWindowController?.window, let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
            RestoreTrace.log(
                "mainWindow forceMaximize screenVisible=\(NSStringFromRect(screen.visibleFrame)) finalFrame=\(NSStringFromRect(window.frame))"
            )
        }

        // Restore persisted pane views after the first frame so launch remains responsive.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            RestoreTrace.log("restoreAllViews: start")
            await self.paneCoordinator.restoreAllViews()
            RestoreTrace.log("restoreAllViews: end registeredViews=\(self.viewRegistry.registeredPaneIds.count)")
        }

        appEventTask?.cancel()
        appEventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case .showCommandBarRepos:
                    self.showCommandBarRepos()
                case .signInRequested(let providerName):
                    guard let provider = OAuthProvider(rawValue: providerName) else { continue }
                    self.handleSignInRequested(provider: provider)
                case .addRepoAtPathRequested(let path):
                    _ = self.store.addRepo(at: path)
                    self.paneCoordinator.syncFilesystemRootsAndActivity()
                case .removeRepoRequested(let repoId):
                    self.store.removeRepo(repoId)
                    self.paneCoordinator.syncFilesystemRootsAndActivity()
                default:
                    continue
                }
            }
        }
        RestoreTrace.log("appDidFinishLaunching: end")
    }

    isolated deinit {
        appEventTask?.cancel()
        filesystemPipelineBootTask?.cancel()
    }

    // MARK: - Dependency Check

    private func checkWorktrunkInstallation() {
        guard !WorktrunkService.shared.isInstalled else { return }

        let alert = NSAlert()
        alert.messageText = "Worktrunk Not Installed"
        alert.informativeText =
            "AgentStudio uses Worktrunk for git worktree management. Would you like to install it via Homebrew?"
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

        // Collect known zmx session IDs from persisted panes. If any main pane cannot
        // resolve stable repo/worktree keys, skip cleanup to avoid deleting valid sessions.
        let candidates: [ZmxOrphanCleanupCandidate] = store.panes.values
            .filter { $0.provider == .zmx }
            .map { pane in
                if let parentPaneId = pane.parentPaneId {
                    return .drawer(parentPaneId: parentPaneId, paneId: pane.id)
                }
                let resolvedKeys: (repoStableKey: String?, worktreeStableKey: String?)
                if let worktreeId = pane.worktreeId,
                    let repo = store.repo(containing: worktreeId),
                    let worktree = store.worktree(worktreeId)
                {
                    resolvedKeys = (repo.stableKey, worktree.stableKey)
                } else {
                    resolvedKeys = (nil, nil)
                }
                return .main(
                    paneId: pane.id,
                    repoStableKey: resolvedKeys.repoStableKey,
                    worktreeStableKey: resolvedKeys.worktreeStableKey
                )
            }

        let plan = ZmxOrphanCleanupPlanner.plan(candidates: candidates)

        if plan.shouldSkipCleanup {
            appLogger.warning(
                "Skipping orphan zmx cleanup: unable to resolve one or more main-pane session IDs from persisted state"
            )
            return
        }
        if !plan.knownSessionIds.isEmpty {
            appLogger.info("Orphan cleanup: protecting \(plan.knownSessionIds.count) known persisted zmx session(s)")
        }

        let backend = ZmxBackend(zmxPath: zmxPath, zmxDir: config.zmxDir)

        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let orphans = await backend.discoverOrphanSessions(excluding: plan.knownSessionIds)
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
                                    appLogger.warning(
                                        "Failed to kill orphan zmx session \(orphanId): \(error.localizedDescription)")
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
        false  // Keep running for menu bar / dock
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
                cacheStore: workspaceCacheStore,
                uiStore: workspaceUIStore,
                actionExecutor: executor,
                tabBarAdapter: tabBarAdapter,
                viewRegistry: viewRegistry
            )
            mainWindowController?.showWindow(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        let persistor = WorkspacePersistor()

        do {
            try persistor.saveCache(
                .init(
                    workspaceId: store.workspaceId,
                    repoEnrichmentByRepoId: workspaceCacheStore.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: workspaceCacheStore.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: workspaceCacheStore.pullRequestCountByWorktreeId,
                    notificationCountByWorktreeId: workspaceCacheStore.notificationCountByWorktreeId,
                    sourceRevision: workspaceCacheStore.sourceRevision,
                    lastRebuiltAt: workspaceCacheStore.lastRebuiltAt
                )
            )
        } catch {
            appLogger.warning("Workspace cache flush failed at termination: \(error.localizedDescription)")
        }

        do {
            try persistor.saveUI(
                .init(
                    workspaceId: store.workspaceId,
                    expandedGroups: workspaceUIStore.expandedGroups,
                    checkoutColors: workspaceUIStore.checkoutColors,
                    filterText: workspaceUIStore.filterText,
                    isFilterVisible: workspaceUIStore.isFilterVisible
                )
            )
        } catch {
            appLogger.warning("Workspace UI flush failed at termination: \(error.localizedDescription)")
        }

        // Always flush on quit — the pre-persist hook syncs runtime webview state
        // back to the pane model, so this must run even when isDirty == false.
        if !store.flush() {
            appLogger.warning("Workspace flush failed at termination")
        }
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu Setup

    /// Create an NSMenuItem whose shortcut is read from CommandDispatcher (single source of truth).
    /// Called from setupMainMenu() which runs on the main thread during app launch.
    private func menuItem(_ title: String, command: AppCommand, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let binding = CommandDispatcher.shared.definitions[command]?.keyBinding {
            binding.apply(to: item)
        }
        return item
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "About AgentStudio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            NSMenuItem(title: "Hide AgentStudio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(
            title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(
            NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            NSMenuItem(title: "Quit AgentStudio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
        fileMenu.addItem(menuItem("Add Folder...", command: .addFolder, action: #selector(addFolder)))

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
        let commandModeItem = NSMenuItem(
            title: "Command Palette", action: #selector(showCommandBarCommands), keyEquivalent: "p")
        commandModeItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(commandModeItem)
        let paneModeItem = NSMenuItem(title: "Go to Pane", action: #selector(showCommandBarPanes), keyEquivalent: "p")
        paneModeItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(paneModeItem)
        viewMenu.addItem(NSMenuItem.separator())

        viewMenu.addItem(menuItem("Open New Webview Tab", command: .openWebview, action: #selector(openWebviewAction)))

        viewMenu.addItem(NSMenuItem.separator())

        // Full Screen uses ⌃⌘F (not ⇧⌘F) to avoid conflict with Filter Sidebar
        viewMenu.addItem(
            NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        )
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .control]

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(
            NSMenuItem(
                title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))

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
        helpMenu.addItem(
            NSMenuItem(title: "AgentStudio Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?"))

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
        window.setContentSize(NSSize(width: 450, height: 380))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func newWindow() {
        showOrCreateMainWindow()
    }

    @objc private func newTab() {
        postAppEvent(.newTabRequested)
    }

    @objc private func closeTab() {
        postAppEvent(.closeTabRequested)
    }

    @objc private func undoCloseTab() {
        postAppEvent(.undoCloseTabRequested)
    }

    @objc private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    @objc private func addRepo() {
        postAppEvent(.addRepoRequested)
    }

    @objc private func addFolder() {
        postAppEvent(.addFolderRequested)
    }

    @objc private func toggleSidebar() {
        mainWindowController?.toggleSidebar()
    }

    @objc private func filterSidebar() {
        postAppEvent(.filterSidebarRequested)
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        postAppEvent(.selectTabAtIndex(index: sender.tag))
    }

    // MARK: - Webview Actions

    @objc private func openWebviewAction() {
        postAppEvent(.openWebviewRequested)
    }

    private func handleSignInRequested(provider: OAuthProvider) {
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appLogger.warning("No window available for OAuth")
            return
        }
        Task {
            do {
                let code = try await oauthService.authenticate(provider: provider, window: window)
                appLogger.info("OAuth succeeded for \(provider.rawValue), code length: \(code.count)")
                // TODO: Exchange code for token and store credentials
            } catch is CancellationError {
                appLogger.info("OAuth task cancelled externally")
            } catch OAuthError.cancelled {
                appLogger.info("OAuth cancelled by user in browser")
            } catch {
                appLogger.error("OAuth failed: \(error.localizedDescription)")
            }
        }
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

    @objc private func showCommandBarRepos() {
        appLogger.info("showCommandBarRepos triggered")
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appLogger.warning("No window available for command bar (repos)")
            return
        }
        commandBarController.show(prefix: "#", parentWindow: window)
    }
}
