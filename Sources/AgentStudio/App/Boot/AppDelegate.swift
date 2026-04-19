import AppKit
import SwiftUI
import os.log

private let appLogger = Logger(subsystem: "com.agentstudio", category: "AppDelegate")
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var mainWindowController: MainWindowController?
    // MARK: - Shared Services (created once at launch)
    // Module-internal to support focused same-type AppDelegate extensions.
    var atomStore: AtomRegistry!
    var store: WorkspaceStore!
    var repoCache: RepoCacheAtom! { atomStore.repoCache }
    var uiState: UIStateAtom! { atomStore.uiState }
    var repoCacheStore: RepoCacheStore!
    var uiStateStore: UIStateStore!
    var workspaceCacheCoordinator: WorkspaceCacheCoordinator!
    var watchedFolderCommands: (any WatchedFolderCommandHandling)!
    var viewRegistry: ViewRegistry!
    var paneCoordinator: PaneCoordinator!
    private var executor: ActionExecutor!
    private var tabBarAdapter: TabBarAdapter!
    private var runtime: SessionRuntime!
    var appLifecycleStore: AppLifecycleAtom!
    var windowLifecycleStore: WindowLifecycleAtom!
    var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
    var managementLayerMonitor: ManagementLayerMonitor!
    // MARK: - Command Bar
    private(set) var commandBarController: CommandBarPanelController!
    // MARK: - OAuth
    private var oauthService: OAuthService!
    private var filesystemPipelineBootTask: Task<Void, Never>?
    var launchRestoreObservationTask: Task<Void, Never>?
    var windowRestoreBridge: WindowRestoreBridge?
    let launchRestoreObservationState = AppDelegateLaunchRestoreObservationState()

    private func recordBootStep(_ step: WorkspaceBootStep) {
        RestoreTrace.log("workspace.boot.step=\(step.rawValue)")
    }

    private func executeBootStep(
        _ step: WorkspaceBootStep,
        persistor: WorkspacePersistor,
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) {
        switch step {
        case .loadCanonicalStore:
            bootLoadCanonicalStore()
        case .loadCacheStore:
            bootLoadCacheStore(persistor: persistor)
        case .loadUIStore:
            bootLoadUIStore(persistor: persistor)
        case .establishRuntimeBus:
            bootEstablishRuntimeBus(paneRuntimeBus: paneRuntimeBus, filesystemSource: &filesystemSource)
        case .startFilesystemActor:
            bootChainPipelineStep(filesystemSource) { await $0.startFilesystemActor() }
        case .startGitProjector:
            bootChainPipelineStep(filesystemSource) { await $0.startGitProjector() }
        case .startForgeActor:
            bootChainPipelineStep(filesystemSource) { await $0.startForgeActor() }
        case .startCacheCoordinator:
            workspaceCacheCoordinator.startConsuming()
        case .triggerInitialTopologySync:
            bootTriggerInitialTopologySync()
        case .readyForReactiveSidebar:
            break
        }
    }

    // MARK: - Boot Step Implementations

    private func bootLoadCanonicalStore() {
        atomStore = AtomRegistry()
        AtomScope.setUp(atomStore)
        store = WorkspaceStore(
            metadataAtom: atomStore.workspaceMetadata,
            repositoryTopologyAtom: atomStore.workspaceRepositoryTopology,
            paneAtom: atomStore.workspacePane,
            tabLayoutAtom: atomStore.workspaceTabLayout,
            mutationCoordinator: atomStore.workspaceMutationCoordinator
        )
        repoCacheStore = RepoCacheStore(atom: atomStore.repoCache)
        uiStateStore = UIStateStore(atom: atomStore.uiState)
        store.restore()
        managementLayerMonitor = ManagementLayerMonitor()
        appLifecycleStore = AppLifecycleAtom()
        windowLifecycleStore = WindowLifecycleAtom()
        applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        RestoreTrace.log(
            "store.restore complete tabs=\(store.tabLayoutAtom.tabs.count) panes=\(store.paneAtom.panes.count) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil")"
        )
    }

    private func bootLoadCacheStore(persistor: WorkspacePersistor) {
        _ = persistor
        repoCacheStore.restore(for: store.metadataAtom.workspaceId)
        pruneStaleCache(store: store, repoCache: repoCache)
    }

    private func bootLoadUIStore(persistor: WorkspacePersistor) {
        _ = persistor
        uiStateStore.restore(for: store.metadataAtom.workspaceId)
    }

    private func bootEstablishRuntimeBus(
        paneRuntimeBus: EventBus<RuntimeEnvelope>,
        filesystemSource: inout FilesystemGitPipeline?
    ) {
        runtime = SessionRuntime(atom: atomStore.sessionRuntime, store: store)
        cleanupOrphanZmxSessions()
        viewRegistry = ViewRegistry()
        seedSlotsForRestoredPanes()
        let pipeline = FilesystemGitPipeline(
            bus: paneRuntimeBus,
            fseventStreamClient: DarwinFSEventStreamClient()
        )
        filesystemSource = pipeline
        watchedFolderCommands = pipeline
        paneCoordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: SurfaceManager.shared,
            runtimeRegistry: .shared,
            paneEventBus: paneRuntimeBus,
            filesystemSource: pipeline,
            windowLifecycleStore: windowLifecycleStore
        )
        workspaceCacheCoordinator = WorkspaceCacheCoordinator(
            bus: paneRuntimeBus,
            workspaceStore: store,
            repoCache: repoCache,
            welcomeAtom: atomStore.welcome,
            topologyEffectHandler: paneCoordinator,
            scopeSyncHandler: { [weak pipeline] change in
                guard let pipeline else { return }
                await pipeline.applyScopeChange(change)
            }
        )
        paneCoordinator.removeRepoHandler = { [weak self] repoId in
            self?.workspaceCacheCoordinator.handleRepoRemoval(repoId: repoId)
            self?.paneCoordinator.syncFilesystemRootsAndActivity()
        }
        executor = ActionExecutor(coordinator: paneCoordinator, store: store)
        tabBarAdapter = TabBarAdapter(store: store, repoCache: repoCache)
        commandBarController = CommandBarPanelController(
            store: store,
            repoCache: repoCache,
            dispatcher: .shared
        )
        CommandDispatcher.shared.appCommandRouter = self
        oauthService = OAuthService()
    }

    private func bootChainPipelineStep(
        _ filesystemSource: FilesystemGitPipeline?,
        action: @escaping @Sendable (FilesystemGitPipeline) async -> Void
    ) {
        guard let filesystemSource else { return }
        let previousTask = filesystemPipelineBootTask
        filesystemPipelineBootTask = Task {
            if let previousTask {
                await previousTask.value
            }
            await action(filesystemSource)
        }
    }

    private func bootTriggerInitialTopologySync() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.replayBootTopology(store: self.store, coordinator: self.workspaceCacheCoordinator)
            if let filesystemPipelineBootTask = self.filesystemPipelineBootTask {
                await filesystemPipelineBootTask.value
            }
            self.paneCoordinator.syncFilesystemRootsAndActivity()
        }
    }

    // MARK: - Boot Helpers

    private func pruneStaleCache(store: WorkspaceStore, repoCache: RepoCacheAtom) {
        let repos = store.repositoryTopologyAtom.repos
        let validRepoIds = Set(repos.map(\.id))
        let validWorktreeIds = Set(repos.flatMap(\.worktrees).map(\.id))
        for repoId in Array(repoCache.repoEnrichmentByRepoId.keys) where !validRepoIds.contains(repoId) {
            repoCache.removeRepo(repoId)
        }
        for worktreeId in Array(repoCache.worktreeEnrichmentByWorktreeId.keys)
        where !validWorktreeIds.contains(worktreeId) {
            repoCache.removeWorktree(worktreeId)
        }
    }

    private func replayBootTopology(store: WorkspaceStore, coordinator: WorkspaceCacheCoordinator) async {
        let tabLayout = store.tabLayoutAtom
        let workspacePane = store.paneAtom
        let repos = store.repositoryTopologyAtom.repos
        let watchedPaths = store.repositoryTopologyAtom.watchedPaths
        let activePaneRepoIds: Set<UUID> = {
            guard let activeTab = tabLayout.activeTab else { return [] }
            let repoIds = activeTab.activePaneIds.compactMap { workspacePane.panes[$0]?.repoId }
            return Set(repoIds)
        }()
        let prioritizedRepos = repos.sorted { a, b in
            let aActive = activePaneRepoIds.contains(a.id)
            let bActive = activePaneRepoIds.contains(b.id)
            if aActive != bActive { return aActive }
            return false
        }
        let bus = PaneRuntimeEventBus.shared
        for repo in prioritizedRepos {
            await bus.post(
                Self.makeTopologyEnvelope(
                    repoPath: repo.repoPath,
                    source: .builtin(.coordinator)
                )
            )
        }

        if !watchedPaths.isEmpty {
            await coordinator.syncScope(
                .updateWatchedFolders(paths: watchedPaths.map(\.path))
            )
        }
    }

    /// Seed pane slots immediately after canonical restore and before any hosting controller exists.
    /// Restored panes already live in `store.paneAtom.panes`; creating their slots here ensures the first
    /// SwiftUI read during tab-host creation sees stable slot identity instead of the lazy fallback.
    func seedSlotsForRestoredPanes() {
        guard store != nil, viewRegistry != nil else { return }
        for paneId in store.paneAtom.panes.keys {
            viewRegistry.ensureSlot(for: paneId)
        }
        RestoreTrace.log("seedSlotsForRestoredPanes count=\(store.paneAtom.panes.count)")
    }

    private static var nextTopologySeq: UInt64 = 0
    private static var nextWorkspaceActivitySeq: UInt64 = 0

    /// Build a canonical `.repoDiscovered` topology envelope.
    /// Coordinator-originated events use `.builtin(.coordinator)`;
    /// filesystem-originated events use `.builtin(.filesystemWatcher)`.
    static func makeTopologyEnvelope(repoPath: URL, source: SystemSource) -> RuntimeEnvelope {
        nextTopologySeq += 1
        return .system(
            SystemEnvelope(
                source: source,
                seq: nextTopologySeq,
                timestamp: .now,
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: repoPath.deletingLastPathComponent()
                    ))
            )
        )
    }

    static func makeWorkspaceActivityEnvelope(_ event: WorkspaceActivityEvent) -> RuntimeEnvelope {
        nextWorkspaceActivitySeq += 1
        return .system(
            SystemEnvelope(
                source: .builtin(.coordinator),
                seq: nextWorkspaceActivitySeq,
                timestamp: .now,
                event: .workspaceActivity(event)
            )
        )
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
            actionExecutor: executor,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        mainWindowController?.prepareLaunchMaximizeAndRestore()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.completeLaunchPresentation()
        observeLaunchRestoreReadiness()
        wireLifecycleConsumers()
        if let window = mainWindowController?.window {
            RestoreTrace.log(
                "mainWindow showWindow frame=\(NSStringFromRect(window.frame)) content=\(NSStringFromRect(window.contentLayoutRect))"
            )
        } else {
            RestoreTrace.log("mainWindow showWindow: window=nil")
        }

        RestoreTrace.log("appDidFinishLaunching: end")
    }

    isolated deinit {
        filesystemPipelineBootTask?.cancel()
        launchRestoreObservationTask?.cancel()
        launchRestoreObservationState.cancelDiagnostics()
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
        let candidates: [ZmxOrphanCleanupCandidate] = store.paneAtom.panes.values
            .filter { $0.provider == .zmx }
            .map { pane in
                if let parentPaneId = pane.parentPaneId {
                    return .drawer(parentPaneId: parentPaneId, paneId: pane.id)
                }
                let resolvedKeys: (repoStableKey: String?, worktreeStableKey: String?)
                if let worktreeId = pane.worktreeId,
                    let repo = store.repositoryTopologyAtom.repo(containing: worktreeId),
                    let worktree = store.repositoryTopologyAtom.worktree(worktreeId)
                {
                    resolvedKeys = (repo.stableKey, worktree.stableKey)
                } else if let cwd = pane.metadata.facets.cwd {
                    let stableKey = StableKey.fromPath(cwd)
                    resolvedKeys = (stableKey, stableKey)
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
                actionExecutor: executor,
                applicationLifecycleMonitor: applicationLifecycleMonitor,
                appLifecycleStore: appLifecycleStore,
                tabBarAdapter: tabBarAdapter,
                viewRegistry: viewRegistry
            )
            mainWindowController?.showWindow(nil)
            wireLifecycleConsumers()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }

        do {
            try repoCacheStore.flush(for: store.metadataAtom.workspaceId)
        } catch {
            appLogger.warning("Workspace cache flush failed at termination: \(error.localizedDescription)")
        }

        do {
            try uiStateStore.flush(for: store.metadataAtom.workspaceId)
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
    private func menuItem(command: AppCommand, action: Selector) -> NSMenuItem {
        let definition = CommandDispatcher.shared.definition(for: command)
        let item = NSMenuItem(title: definition.actionSpec.label, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = command.rawValue
        if let binding = definition.keyBinding {
            binding.apply(to: item)
        }
        return item
    }

    private func makeCommandBarMenuItems() -> [NSMenuItem] {
        [
            menuItem(command: .showCommandBarEverything, action: #selector(showCommandBarEverything)),
            menuItem(command: .showCommandBarCommands, action: #selector(showCommandBarCommands)),
            menuItem(command: .showCommandBarPanes, action: #selector(showCommandBarPanes)),
        ]
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard
            let rawValue = menuItem.representedObject as? String,
            let command = AppCommand(rawValue: rawValue)
        else {
            return true
        }

        let definition = CommandDispatcher.shared.definition(for: command)
        let workspaceTab = WorkspaceTabDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let focus = atom(\.workspacePaneFocus).currentFocus(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            workspaceFocusOwner: atom(\.workspaceFocusOwner)
        )
        let isVisible = definition.isVisible(in: focus)
        menuItem.isHidden = !isVisible
        guard isVisible else { return false }
        return CommandDispatcher.shared.canDispatch(command)
    }

    // swiftlint:disable:next function_body_length
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
        fileMenu.addItem(menuItem(command: .newWindow, action: #selector(newWindow)))
        fileMenu.addItem(menuItem(command: .newTab, action: #selector(newTab)))
        fileMenu.addItem(menuItem(command: .showCommandBarRepos, action: #selector(showCommandBarRepos)))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(menuItem(command: .closeTab, action: #selector(closeTab)))
        fileMenu.addItem(menuItem(command: .closeWindow, action: #selector(closeWindow)))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(menuItem(command: .addFolder, action: #selector(addFolder)))

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(menuItem(command: .undoCloseTab, action: #selector(undoCloseTab)))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())

        let findMenu = NSMenu(title: "Find")
        let findItem = NSMenuItem(
            title: "Find…",
            action: #selector(TerminalPaneMountView.startSearch(_:)),
            keyEquivalent: "f"
        )
        findItem.keyEquivalentModifierMask = [.command]
        findMenu.addItem(findItem)

        let findNextItem = NSMenuItem(
            title: "Find Next",
            action: #selector(TerminalPaneMountView.findNext(_:)),
            keyEquivalent: "g"
        )
        findNextItem.keyEquivalentModifierMask = [.command]
        findMenu.addItem(findNextItem)

        let findPreviousItem = NSMenuItem(
            title: "Find Previous",
            action: #selector(TerminalPaneMountView.findPrevious(_:)),
            keyEquivalent: "G"
        )
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(findPreviousItem)

        let findMenuItem = NSMenuItem()
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(menuItem(command: .toggleSidebar, action: #selector(toggleSidebar)))
        viewMenu.addItem(menuItem(command: .filterSidebar, action: #selector(filterSidebar)))
        viewMenu.addItem(NSMenuItem.separator())

        for item in makeCommandBarMenuItems() {
            viewMenu.addItem(item)
        }
        viewMenu.addItem(NSMenuItem.separator())

        viewMenu.addItem(menuItem(command: .openWebview, action: #selector(openWebviewAction)))

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
            let item = menuItem(command: command, action: #selector(selectTab(_:)))
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
        CommandDispatcher.shared.dispatch(.newTab)
    }

    @objc private func closeTab() {
        CommandDispatcher.shared.dispatch(.closeTab)
    }

    @objc private func undoCloseTab() {
        CommandDispatcher.shared.dispatch(.undoCloseTab)
    }

    @objc private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    @objc private func addFolder() {
        CommandDispatcher.shared.dispatch(.addFolder)
    }

    // MARK: - Repo/Folder Intake

    private func handleAddFolderRequested(startingAt initialURL: URL? = nil) async {
        let welcome = atomStore.welcome
        welcome.beginChoosingFolder()
        defer { welcome.endChoosingFolder() }

        let rootURL: URL
        if let initialURL {
            rootURL = initialURL.standardizedFileURL
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose a folder to scan for Git repositories."
            panel.prompt = "Scan Folder"

            guard panel.runModal() == .OK, let selectedURL = panel.url else {
                return
            }
            rootURL = selectedURL.standardizedFileURL
        }

        // 1. Persist the watched path (direct store mutation)
        _ = store.repositoryTopologyAtom.addWatchedPath(rootURL)

        // 2. Signal scanning state for UI. Sidebar stays collapsed until
        //    the first repo is discovered — never show an empty sidebar.
        welcome.beginFolderScan(rootURL)

        // Expand sidebar when a repo from this folder is discovered.
        // Scoped to rootURL so unrelated discoveries don't trigger it.
        let sidebarExpandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let normalizedRoot = rootURL.standardizedFileURL.path
            await PaneRuntimeEventBus.shared.waitForFirst { envelope -> Void? in
                guard case .system(let sys) = envelope,
                    case .topology(.repoDiscovered(let repoPath, let parentPath, _)) = sys.event,
                    parentPath.standardizedFileURL.path == normalizedRoot
                        || repoPath.standardizedFileURL.path.hasPrefix(normalizedRoot)
                else { return nil }
                return ()
            }
            self.mainWindowController?.expandSidebar()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                sidebarExpandTask.cancel()
                // Safety net: if the .folderScanFinished event never reaches
                // the coordinator (late subscription, bus cancellation), the
                // scan state would stay .scanning forever. Clear it here so
                // the view falls back to .launcher once repos populate.
                if case .scanning(let rootPath) = welcome.folderScanState,
                    rootPath == rootURL.standardizedFileURL
                {
                    welcome.clearFolderScanState()
                }
            }

            let refreshSummary = await self.watchedFolderCommands.refreshWatchedFolders(
                self.store.repositoryTopologyAtom.watchedPaths.map(\.path)
            )

            let repoPaths = refreshSummary.repoPaths(in: rootURL)
            let activityEnvelope = Self.makeWorkspaceActivityEnvelope(
                .folderScanFinished(
                    rootPath: rootURL,
                    discoveredRepoCount: repoPaths.count
                )
            )
            await PaneRuntimeEventBus.shared.post(activityEnvelope)
        }
    }

    @objc private func toggleSidebar() {
        mainWindowController?.toggleSidebar()
    }

    @objc private func filterSidebar() {
        CommandDispatcher.shared.dispatch(.filterSidebar)
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < AppCommand.selectTabCommands.count else { return }
        CommandDispatcher.shared.dispatch(AppCommand.selectTabCommands[sender.tag])
    }

    // MARK: - Webview Actions

    @objc private func openWebviewAction() {
        CommandDispatcher.shared.dispatch(.openWebview)
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

    @objc private func showCommandBarEverything() {
        CommandDispatcher.shared.dispatch(.showCommandBarEverything)
    }

    @objc private func showCommandBarCommands() {
        CommandDispatcher.shared.dispatch(.showCommandBarCommands)
    }

    @objc private func showCommandBarPanes() {
        CommandDispatcher.shared.dispatch(.showCommandBarPanes)
    }

}
// MARK: - ShellCommandHandling

extension AppDelegate: ShellCommandHandling {
    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .addFolder, .toggleSidebar, .filterSidebar, .signInGitHub, .signInGoogle,
            .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes, .showCommandBarRepos:
            true
        default: false
        }
    }

    func execute(_ command: AppCommand) -> Bool {
        switch command {
        case .addFolder:
            Task { await handleAddFolderRequested() }
            return true
        case .toggleSidebar:
            mainWindowController?.toggleSidebar()
            return true
        case .filterSidebar:
            mainWindowController?.showSidebarFilter()
            return true
        case .newWindow:
            newWindow()
            return true
        case .closeWindow:
            closeWindow()
            return true
        case .showCommandBarEverything:
            showCommandBar(prefix: nil, context: "command bar")
            return true
        case .showCommandBarCommands:
            showCommandBar(prefix: ">", context: "command bar (commands)")
            return true
        case .showCommandBarPanes:
            showCommandBar(prefix: "$", context: "command bar (panes)")
            return true
        case .showCommandBarRepos:
            showCommandBar(prefix: "#", context: "command bar (repos)")
            return true
        case .signInGitHub:
            handleSignInRequested(provider: .github)
            return true
        case .signInGoogle:
            handleSignInRequested(provider: .google)
            return true
        default: return false
        }
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        switch (command, targetType) {
        default: return false
        }
    }

    private func showCommandBar(prefix: String?, context: String) {
        appLogger.info("showCommandBar context=\(context, privacy: .public)")
        guard let window = NSApp.keyWindow ?? mainWindowController?.window else {
            appLogger.warning("No window available for \(context, privacy: .public)")
            return
        }
        commandBarController.show(prefix: prefix, parentWindow: window)
    }

}
