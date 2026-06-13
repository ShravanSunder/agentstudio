import AppKit
import SwiftUI
import os.log

protocol ZmxStartupSessionInventory: Sendable {
    func discoverLiveSessionInventory() async -> ZmxSessionInventorySnapshot
}

extension ZmxBackend: ZmxStartupSessionInventory {
    func discoverLiveSessionInventory() async -> ZmxSessionInventorySnapshot {
        await discoverAgentStudioSessions()
    }
}

struct ZmxStartupReconciliationSummary: Equatable, Sendable {
    let inventoryOutcome: ZmxSessionInventoryOutcome
    let liveSessionCount: Int
    let hydratedAnchorCount: Int
    let protectedSessionCount: Int
    let unresolvedCandidateCount: Int
    let unmatchedLiveSessionCount: Int
}

let appLogger = Logger(subsystem: "com.agentstudio", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var mainWindowController: MainWindowController?
    // MARK: - Shared Services (created once at launch)
    // Module-internal to support focused same-type AppDelegate extensions.
    var atomStore: AtomRegistry!
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
    var sidebarCacheStore: SidebarCacheStore!
    var uiStateStore: UIStateStore!
    var workspaceSettingsStore: WorkspaceSettingsStore!
    var workspaceSQLiteDatastore: WorkspaceSQLiteDatastore?
    var workspaceCacheCoordinator: WorkspaceCacheCoordinator!
    var watchedFolderCommands: (any WatchedFolderCommandHandling)!
    var viewRegistry: ViewRegistry!
    var paneCoordinator: PaneCoordinator!
    var closeTransitionCoordinator: PaneCloseTransitionCoordinator!
    var executor: ActionExecutor!
    var tabBarAdapter: TabBarAdapter!
    var runtime: SessionRuntime!
    var appLifecycleStore: AppLifecycleAtom!
    var windowLifecycleStore: WindowLifecycleAtom!
    var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
    var managementLayerMonitor: ManagementLayerMonitor!
    // MARK: - Command Bar
    var commandBarController: CommandBarPanelController!
    // MARK: - OAuth
    var oauthService: OAuthService!
    var filesystemPipelineBootTask: Task<Void, Never>?
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

        // Create new services following the workspace boot contract.
        let persistor = WorkspacePersistor()
        let paneRuntimeBus = PaneRuntimeEventBus.shared
        var filesystemSource: FilesystemGitPipeline?

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.bootWorkspaceServices(
                persistor: persistor,
                paneRuntimeBus: paneRuntimeBus,
                filesystemSource: &filesystemSource
            )
            self.finishLaunchingAfterWorkspaceBoot()
        }
    }

    private func finishLaunchingAfterWorkspaceBoot() {
        startupTraceRecorder.recordAppStartup(
            "app.did_finish_launching.succeeded",
            phase: "did_finish_launching",
            outcome: "succeeded"
        )
        // Create main window
        mainWindowController = MainWindowController(
            store: store,
            actionExecutor: executor,
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
        if let window = mainWindowController?.window {
            RestoreTrace.log(
                "mainWindow showWindow frame=\(NSStringFromRect(window.frame)) content=\(NSStringFromRect(window.contentLayoutRect))"
            )
        } else {
            RestoreTrace.log("mainWindow showWindow: window=nil")
        }

        RestoreTrace.log("appDidFinishLaunching: end")
        runStartupDiagnosticActionIfRequested()
    }

    isolated deinit {
        filesystemPipelineBootTask?.cancel()
        initialTopologySyncTask?.cancel()
        persistenceObservationBootTask?.cancel()
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

    // MARK: - Startup zmx Session Reconciliation

    /// Hydrate legacy zmx session anchors from live inventory at startup.
    /// This path is intentionally non-destructive: boot may classify and
    /// persist, but it must never kill zmx sessions.
    /// Called from `applicationDidFinishLaunching` (always main thread).
    @MainActor
    func reconcileZmxSessionAnchorsAtStartup(
        sessionConfiguration: SessionConfiguration = .detect(),
        makeInventory: (SessionConfiguration) -> (any ZmxStartupSessionInventory)? =
            AppDelegate.makeZmxStartupSessionInventory
    ) async {
        guard needsStartupZmxAnchorHydration() else {
            appLogger.debug("Skipping startup zmx session reconciliation: all persistent zmx panes have stored anchors")
            recordZmxStartupReconciliation(
                .init(
                    inventoryOutcome: .skipped("no legacy zmx panes missing stored anchors"),
                    liveSessionCount: 0,
                    hydratedAnchorCount: 0,
                    protectedSessionCount: 0,
                    unresolvedCandidateCount: 0,
                    unmatchedLiveSessionCount: 0
                )
            )
            return
        }

        let config = sessionConfiguration
        guard let zmxPath = config.zmxPath else {
            appLogger.debug("zmx not found — skipping startup zmx session reconciliation")
            recordZmxStartupReconciliation(
                .init(
                    inventoryOutcome: .unavailable("zmx not found"),
                    liveSessionCount: 0,
                    hydratedAnchorCount: 0,
                    protectedSessionCount: 0,
                    unresolvedCandidateCount: 0,
                    unmatchedLiveSessionCount: 0
                )
            )
            return
        }

        let terminalRestoreRuntime = TerminalRestoreRuntime(sessionConfiguration: config)
        guard let inventory = makeInventory(config) else {
            appLogger.warning("Startup zmx session reconciliation skipped because inventory could not be created")
            recordZmxStartupReconciliation(
                .init(
                    inventoryOutcome: .unavailable("inventory unavailable for \(zmxPath)"),
                    liveSessionCount: 0,
                    hydratedAnchorCount: 0,
                    protectedSessionCount: 0,
                    unresolvedCandidateCount: 0,
                    unmatchedLiveSessionCount: 0
                )
            )
            return
        }

        let reconciliationTask = Task { @MainActor () -> Result<ZmxStartupReconciliationSummary, any Error> in
            do {
                let summary = try await self.runZmxStartupSessionReconciliation(
                    inventory: inventory,
                    terminalRestoreRuntime: terminalRestoreRuntime
                )
                return .success(summary)
            } catch {
                return .failure(error)
            }
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: AppPolicies.ZmxStartup.reconciliationTimeout.nanosecondsForTaskSleep)
                reconciliationTask.cancel()
            } catch {}
        }
        defer {
            timeoutTask.cancel()
        }

        do {
            switch await reconciliationTask.value {
            case .success(let summary):
                recordZmxStartupReconciliation(summary)
            case .failure(let reconciliationError):
                throw reconciliationError
            }
        } catch is CancellationError {
            appLogger.warning("Startup zmx session reconciliation timed out")
            recordZmxStartupReconciliation(
                unavailableStartupReconciliationSummary(
                    reason: "startup reconciliation timeout",
                    terminalRestoreRuntime: terminalRestoreRuntime
                )
            )
        } catch {
            appLogger.warning("Startup zmx session reconciliation failed: \(error.localizedDescription)")
            recordZmxStartupReconciliation(
                unavailableStartupReconciliationSummary(
                    reason: "startup reconciliation failed",
                    terminalRestoreRuntime: terminalRestoreRuntime
                )
            )
        }
    }

    private func unavailableStartupReconciliationSummary(
        reason: String,
        terminalRestoreRuntime: TerminalRestoreRuntime
    ) -> ZmxStartupReconciliationSummary {
        let candidates = zmxOrphanCleanupCandidates(terminalRestoreRuntime: terminalRestoreRuntime)
        let unavailableSummary = ZmxOrphanCleanupPlanner.unavailableInventorySummary(candidates: candidates)
        return .init(
            inventoryOutcome: .unavailable(reason),
            liveSessionCount: 0,
            hydratedAnchorCount: 0,
            protectedSessionCount: unavailableSummary.protectedSessionCount,
            unresolvedCandidateCount: unavailableSummary.unresolvedCandidateCount,
            unmatchedLiveSessionCount: 0
        )
    }

    nonisolated static func makeZmxStartupSessionInventory(
        sessionConfiguration config: SessionConfiguration
    ) -> (any ZmxStartupSessionInventory)? {
        guard let zmxPath = config.zmxPath else { return nil }
        let inventory: any ZmxStartupSessionInventory = ZmxBackend(zmxPath: zmxPath, zmxDir: config.zmxDir)
        return inventory
    }

    func runZmxStartupSessionReconciliation(
        inventory: any ZmxStartupSessionInventory,
        terminalRestoreRuntime: TerminalRestoreRuntime
    ) async throws -> ZmxStartupReconciliationSummary {
        let liveInventory = await inventory.discoverLiveSessionInventory()
        let candidates = zmxOrphanCleanupCandidates(terminalRestoreRuntime: terminalRestoreRuntime)

        switch liveInventory.outcome {
        case .complete:
            break
        case .unavailable(let reason), .skipped(let reason):
            appLogger.warning("Startup zmx session inventory unavailable: \(reason)")
            let unavailableSummary = ZmxOrphanCleanupPlanner.unavailableInventorySummary(candidates: candidates)
            return .init(
                inventoryOutcome: liveInventory.outcome,
                liveSessionCount: 0,
                hydratedAnchorCount: 0,
                protectedSessionCount: unavailableSummary.protectedSessionCount,
                unresolvedCandidateCount: unavailableSummary.unresolvedCandidateCount,
                unmatchedLiveSessionCount: 0
            )
        }

        let liveSessionIds = liveInventory.sessionIds
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: liveSessionIds
        )
        let reconciliationPlan = hydrationPlan.cleanupPlan

        guard await persistHydratedZmxSessionAnchors(hydrationPlan.sessionIdsToPersistByPaneId) else {
            return .init(
                inventoryOutcome: liveInventory.outcome,
                liveSessionCount: liveSessionIds.count,
                hydratedAnchorCount: 0,
                protectedSessionCount: reconciliationPlan.knownSessionIds.count,
                unresolvedCandidateCount: reconciliationPlan.unresolvedCandidateCount,
                unmatchedLiveSessionCount: 0
            )
        }

        if reconciliationPlan.shouldSkipCleanup {
            appLogger.warning(
                "Startup zmx session reconciliation found one or more unresolved persisted zmx pane session IDs"
            )
        }
        if !reconciliationPlan.knownSessionIds.isEmpty {
            appLogger.info(
                "Startup zmx session reconciliation: protecting \(reconciliationPlan.knownSessionIds.count) known persisted zmx session(s)"
            )
        }

        let unmatchedLiveSessionIds = reconciliationPlan.destroyableOrphanSessionIds(from: liveSessionIds)
        if !unmatchedLiveSessionIds.isEmpty {
            appLogger.info(
                "Startup zmx session reconciliation observed \(unmatchedLiveSessionIds.count) unmatched live zmx session(s); boot is non-destructive"
            )
        }

        return .init(
            inventoryOutcome: liveInventory.outcome,
            liveSessionCount: liveSessionIds.count,
            hydratedAnchorCount: hydrationPlan.sessionIdsToPersistByPaneId.count,
            protectedSessionCount: reconciliationPlan.knownSessionIds.count,
            unresolvedCandidateCount: reconciliationPlan.unresolvedCandidateCount,
            unmatchedLiveSessionCount: unmatchedLiveSessionIds.count
        )
    }

    func recordZmxStartupReconciliation(_ summary: ZmxStartupReconciliationSummary) {
        startupTraceRecorder.recordZmxStartupReconciliation(summary)
    }

    func zmxOrphanCleanupCandidates(
        terminalRestoreRuntime: TerminalRestoreRuntime
    ) -> [ZmxOrphanCleanupCandidate] {
        store.paneAtom.panes.values.compactMap { pane in
            guard pane.provider == .zmx else { return nil }
            let storedSessionId = pane.terminalState?.zmxSessionId
            let derivedSessionId = terminalRestoreRuntime.legacyZmxSessionId(for: pane, store: store)
            if let parentPaneId = pane.parentPaneId {
                return .drawer(
                    parentPaneId: parentPaneId,
                    paneId: pane.id,
                    storedSessionId: storedSessionId,
                    derivedSessionId: derivedSessionId
                )
            }
            return .main(
                paneId: pane.id,
                storedSessionId: storedSessionId,
                derivedSessionId: derivedSessionId
            )
        }
    }

    func needsStartupZmxAnchorHydration() -> Bool {
        store.paneAtom.panes.values.contains { pane in
            guard pane.provider == .zmx else { return false }
            guard let storedSessionId = pane.terminalState?.zmxSessionId else { return true }
            if let parentPaneId = pane.parentPaneId {
                return !ZmxBackend.isValidStoredDrawerSessionId(
                    storedSessionId,
                    parentPaneId: parentPaneId,
                    drawerPaneId: pane.id
                )
            }
            return !ZmxBackend.isValidStoredLayoutPaneSessionId(storedSessionId, paneId: pane.id)
        }
    }

    func persistHydratedZmxSessionAnchors(_ sessionIdsByPaneId: [UUID: String]) async -> Bool {
        guard !sessionIdsByPaneId.isEmpty else { return true }
        let sortedAnchors = sessionIdsByPaneId.sorted { lhs, rhs in
            lhs.key.uuidString < rhs.key.uuidString
        }
        var didChange = false
        for (paneId, sessionId) in sortedAnchors {
            if store.paneAtom.setTerminalZmxSessionId(paneId, sessionId: sessionId) {
                didChange = true
            }
        }
        guard didChange else { return true }

        let flushOutcome = await store.flushAsync()
        guard flushOutcome.succeeded else {
            appLogger.warning("Startup zmx session reconciliation failed to persist hydrated zmx session anchors")
            return false
        }
        appLogger.info(
            "Persisted \(sessionIdsByPaneId.count) hydrated zmx session anchor(s) during startup reconciliation")
        return true
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

    @objc func newWindow() {
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
            await PaneRuntimeEventBus.shared.waitForFirst { envelope -> Void? in
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
        CommandDispatcher.shared.dispatch(.showCommandBarEverything)
    }

    @objc private func showCommandBarCommands() {
        CommandDispatcher.shared.dispatch(.showCommandBarCommands)
    }

    @objc private func showCommandBarPanes() {
        CommandDispatcher.shared.dispatch(.showCommandBarPanes)
    }

}
