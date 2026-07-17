import AgentStudioAppIPC
import AppKit
import SwiftUI
import os.log

let appLogger = Logger(subsystem: "com.agentstudio", category: "AppDelegate")

struct InstalledWorkspacePreparedContentMountOwners {
    let cohort: WorkspacePreparedContentMountCohort
    let terminalAdmissionPort: PreparedTerminalMountAdmissionPort
    let coordinator: WorkspacePreparedContentMountCoordinator
}

enum WorkspacePreparedContentMountBootState {
    case awaitingCanonicalComposition
    case accepted(WorkspacePreparedContentMountCohort)
    case installed(InstalledWorkspacePreparedContentMountOwners)
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var mainWindowController: MainWindowController?
    // MARK: - Shared Services (created once at launch)
    // Module-internal to support focused same-type AppDelegate extensions.
    var atomStore: AtomRegistry!
    private var workspacePreparedContentMountBootState = WorkspacePreparedContentMountBootState
        .awaitingCanonicalComposition
    var installedWorkspacePreparedContentMountOwners: InstalledWorkspacePreparedContentMountOwners {
        guard case .installed(let owners) = workspacePreparedContentMountBootState else {
            preconditionFailure("prepared content mount owners accessed before runtime boot")
        }
        return owners
    }
    var acceptedWorkspacePreparedContentMountCohort: WorkspacePreparedContentMountCohort {
        guard case .accepted(let cohort) = workspacePreparedContentMountBootState else {
            preconditionFailure("prepared content mount cohort accessed outside accepted boot phase")
        }
        return cohort
    }
    var store: WorkspaceStore!
    var repoCache: RepoCacheAtom! { atomStore.repoCache }
    var uiState: WorkspaceSidebarState! { atomStore.workspaceSidebarState }
    var inboxNotificationStore: InboxNotificationStore!
    var inboxNotificationRouter: InboxNotificationRouter!
    var inboxPaneFocusTracker: PaneFocusTracker!
    var paneInboxNotificationPresenter: PaneInboxNotificationPresenter!
    var pendingPersistenceRecoveryEvents: [PersistenceRecoveryEvent] = []
    var hasLoadedInboxNotificationStore = false
    var canArchiveLegacyInboxFile = true
    var terminalActivityRouter: TerminalActivityRouter!
    var traceRuntime: AgentStudioTraceRuntime!
    var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder!
    var startupTraceRecorder: AgentStudioStartupTraceRecorder!
    var repoCacheStore: RepoCacheStore!
    var repositoryTopologyStore: RepositoryTopologyStore!
    var sidebarCacheStore: SidebarCacheStore!
    var uiStateStore: UIStateStore!
    var workspaceSettingsStore: WorkspaceSettingsStore!
    var workspaceSQLiteDatastore: WorkspaceSQLiteDatastore?
    var workspaceCacheCoordinator: WorkspaceCacheCoordinator!
    var watchedFolderCommands: (any WatchedFolderCommandHandling)!
    var viewRegistry: ViewRegistry!
    var workspaceSurfaceCoordinator: WorkspaceSurfaceCoordinator!
    var closeTransitionCoordinator: PaneCloseTransitionCoordinator!
    var executor: WorkspaceActionExecutor!
    var tabBarAdapter: TabBarAdapter!
    var runtime: SessionRuntime!
    var appIPCServer: AgentStudioAppIPCServer?
    var appLifecycleStore: AppLifecycleAtom!
    var windowLifecycleStore: WindowLifecycleAtom!
    var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
    var managementLayerMonitor: ManagementLayerMonitor!

    func acceptWorkspacePreparedContentMountCohort(_ cohort: WorkspacePreparedContentMountCohort) {
        guard case .awaitingCanonicalComposition = workspacePreparedContentMountBootState else {
            preconditionFailure("prepared content mount cohort accepted more than once")
        }
        workspacePreparedContentMountBootState = .accepted(cohort)
    }

    func installWorkspacePreparedContentMountOwners(
        _ owners: InstalledWorkspacePreparedContentMountOwners
    ) {
        guard case .accepted(let acceptedCohort) = workspacePreparedContentMountBootState,
            acceptedCohort == owners.cohort
        else {
            preconditionFailure("prepared content mount owners installed without their accepted cohort")
        }
        workspacePreparedContentMountBootState = .installed(owners)
    }
    // MARK: - Command Bar
    var commandBarController: CommandBarPanelController!
    // MARK: - OAuth
    var oauthService: OAuthService!
    var filesystemPipelineBootTask: Task<Void, Never>?
    var shouldStartRepositoryTopologyAfterWindowPresentation = false
    var repositoryTopologyLoadTask: Task<Void, Never>?
    var initialTopologySyncTask: Task<Void, Never>?
    var persistenceObservationBootTask: Task<Void, Never>?
    var isObservingTraceIdentityInputs = false
    private var terminationDrainTask: Task<Void, Never>?
    var launchRestoreObservationTask: Task<Void, Never>?
    var windowRestoreBridge: WindowRestoreBridge?
    let launchRestoreObservationState = AppDelegateLaunchRestoreObservationState()

    override convenience init() {
        let traceRuntime = AgentStudioTraceRuntime.fromEnvironment()
        self.init(
            traceRuntime: traceRuntime,
            startupTraceRecorder: AgentStudioStartupTraceRecorder(traceRuntime: traceRuntime)
        )
    }

    init(
        traceRuntime: AgentStudioTraceRuntime,
        startupTraceRecorder: AgentStudioStartupTraceRecorder
    ) {
        self.traceRuntime = traceRuntime
        self.performanceTraceRecorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        self.startupTraceRecorder = startupTraceRecorder
        super.init()
        Ghostty.ActionRouter.bindTraceRuntime(traceRuntime)
        Ghostty.ActionRouter.bindStartupTraceRecorder(startupTraceRecorder)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RestoreTrace.log("appDidFinishLaunching: begin")
        startupTraceRecorder.recordAppStartup(
            "app.did_finish_launching.started",
            phase: "did_finish_launching"
        )
        GhosttyStartupEnvironment.apply()

        // Some parent shells export NO_COLOR=1, which disables ANSI color in CLIs
        // (Codex, Gemini, etc.). Clear it for app-hosted terminal sessions.
        if getenv("NO_COLOR") != nil {
            unsetenv("NO_COLOR")
            RestoreTrace.log("unset NO_COLOR for terminal color support")
        }

        // Set up main menu (doesn't depend on zmx restore)
        setupMainMenu()

        // Create new services following the workspace boot contract.
        let persistor = WorkspacePersistor()
        let paneRuntimeBus = PaneRuntimeEventBus.shared
        var filesystemSource: FilesystemGitPipeline?

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.bootWorkspacePresentationPrerequisites(
                persistor: persistor,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
            self.presentWindowAfterWorkspaceComposition()
            await self.bootWorkspacePostPresentationServices(
                persistor: persistor,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
            self.finishPostPresentationStartup()
        }
    }

    private func presentWindowAfterWorkspaceComposition() {
        // Create main window
        mainWindowController = MainWindowController(
            store: store,
            workspaceActionExecutor: executor,
            runtimeCommandDispatcher: workspaceSurfaceCoordinator,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            inboxAtom: atomStore.inboxNotification,
            inboxPrefsAtom: atomStore.inboxNotificationPrefs,
            inboxSidebarState: atomStore.inboxSidebarState,
            paneInboxPresenter: paneInboxNotificationPresenter,
            performanceTraceRecorder: performanceTraceRecorder,
            closeTransitionCoordinator: closeTransitionCoordinator
        )
        mainWindowController?.prepareLaunchMaximizeAndRestore()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.completeLaunchPresentation()
        observeLaunchRestoreReadiness()
        wireLifecycleConsumers()
        startAppIPCServer()
        if let window = mainWindowController?.window {
            RestoreTrace.log(
                "mainWindow showWindow frame=\(NSStringFromRect(window.frame)) content=\(NSStringFromRect(window.contentLayoutRect))"
            )
        } else {
            RestoreTrace.log("mainWindow showWindow: window=nil")
        }
    }

    private func finishPostPresentationStartup() {
        startupTraceRecorder.recordAppStartup(
            "app.did_finish_launching.succeeded",
            phase: "did_finish_launching",
            outcome: "succeeded"
        )
        RestoreTrace.log("appDidFinishLaunching: end")
        runStartupDiagnosticActionIfRequested()
        scheduleFullDiskAccessHealthCheck()
    }

    isolated deinit {
        appIPCServer?.stop()
        filesystemPipelineBootTask?.cancel()
        repositoryTopologyLoadTask?.cancel()
        initialTopologySyncTask?.cancel()
        persistenceObservationBootTask?.cancel()
        launchRestoreObservationTask?.cancel()
        launchRestoreObservationState.cancelDiagnostics()
    }

    // MARK: - Dependency Check

    func presentWorktrunkInstallationOfferIfNeeded() {
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
                workspaceActionExecutor: executor,
                runtimeCommandDispatcher: workspaceSurfaceCoordinator,
                applicationLifecycleMonitor: applicationLifecycleMonitor,
                appLifecycleStore: appLifecycleStore,
                tabBarAdapter: tabBarAdapter,
                viewRegistry: viewRegistry,
                inboxAtom: atomStore.inboxNotification,
                inboxPrefsAtom: atomStore.inboxNotificationPrefs,
                inboxSidebarState: atomStore.inboxSidebarState,
                paneInboxPresenter: paneInboxNotificationPresenter,
                performanceTraceRecorder: performanceTraceRecorder,
                closeTransitionCoordinator: closeTransitionCoordinator
            )
            mainWindowController?.showWindow(nil)
            wireLifecycleConsumers()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }

        guard terminationDrainTask == nil else { return .terminateLater }
        terminationDrainTask = Task { @MainActor [weak self] in
            await self?.flushApplicationStateBeforeTermination(store: store)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Setup

    /// Create an NSMenuItem whose shortcut is read from AppCommandDispatcher (single source of truth).
    /// Called from setupMainMenu() which runs on the main thread during app launch.
    private func menuItem(command: AppCommand, action: Selector) -> NSMenuItem {
        let definition = AppCommandDispatcher.shared.definition(for: command)
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

        let definition = AppCommandDispatcher.shared.definition(for: command)
        let workspaceTab = WorkspaceTabLayoutDerived(
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
        return AppCommandDispatcher.shared.canDispatch(command)
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
        viewMenu.addItem(menuItem(command: .filterSidebar, action: #selector(filterSidebar)))
        viewMenu.addItem(NSMenuItem.separator())

        for item in makeCommandBarMenuItems() {
            viewMenu.addItem(item)
        }
        viewMenu.addItem(NSMenuItem.separator())

        viewMenu.addItem(menuItem(command: .openWebview, action: #selector(openWebviewAction)))

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

    @objc func newWindow() {
        showOrCreateMainWindow()
    }

    @objc private func newTab() {
        AppCommandDispatcher.shared.dispatch(.newTab)
    }

    @objc private func closeTab() {
        AppCommandDispatcher.shared.dispatch(.closeTab)
    }

    @objc private func undoCloseTab() {
        AppCommandDispatcher.shared.dispatch(.undoCloseTab)
    }

    @objc func closeWindow() {
        NSApp.keyWindow?.close()
    }

    // MARK: - Repo/Folder Intake

    func handleWatchFolderRequested(startingAt initialURL: URL? = nil) async {
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
            await PaneRuntimeEventBus.shared.waitForFirst(
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "AppDelegate.folderScanSidebarExpansion"
            ) { envelope -> Void? in
                guard case .system(let sys) = envelope,
                    case .topology(let topologyEvent) = sys.event
                else {
                    return nil
                }
                switch topologyEvent {
                case .repoDiscovered(let repoPath, let parentPath, _):
                    guard
                        parentPath.standardizedFileURL.path == normalizedRoot
                            || repoPath.standardizedFileURL.path.hasPrefix(normalizedRoot)
                    else { return nil }
                    return ()
                case .reposDiscovered(let parentPath, let repositories):
                    guard
                        parentPath.standardizedFileURL.path == normalizedRoot
                            || repositories.contains(where: {
                                $0.repoPath.standardizedFileURL.path.hasPrefix(normalizedRoot)
                            })
                    else { return nil }
                    return ()
                case .repoRemoved, .worktreeRegistered, .worktreeUnregistered:
                    return nil
                }
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
                self.store.repositoryTopologyAtom.watchedPaths
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
        AppCommandDispatcher.shared.dispatch(.filterSidebar)
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < AppCommand.selectTabCommands.count else { return }
        AppCommandDispatcher.shared.dispatch(AppCommand.selectTabCommands[sender.tag])
    }

    // MARK: - Webview Actions

    @objc private func openWebviewAction() {
        AppCommandDispatcher.shared.dispatch(.openWebview)
    }

    func handleSignInRequested(provider: OAuthProvider) {
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
        AppCommandDispatcher.shared.dispatch(.showCommandBarEverything)
    }

    @objc private func showCommandBarCommands() {
        AppCommandDispatcher.shared.dispatch(.showCommandBarCommands)
    }

    @objc private func showCommandBarPanes() {
        AppCommandDispatcher.shared.dispatch(.showCommandBarPanes)
    }

}
