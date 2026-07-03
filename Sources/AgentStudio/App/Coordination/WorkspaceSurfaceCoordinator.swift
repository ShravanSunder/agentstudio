import AppKit
import Foundation
import GhosttyKit
import os.log

@MainActor
protocol WorkspaceSurfaceManaging: AnyObject {
    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { get }

    func syncFocus(activeSurfaceId: UUID?)

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError>

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView?
    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason)
    func undoClose() -> ManagedSurface?
    func requeueUndo(_ surfaceId: UUID)
    func destroy(_ surfaceId: UUID)
}

extension SurfaceManager: WorkspaceSurfaceManaging {}

@MainActor
final class WorkspaceSurfaceCoordinator {
    nonisolated static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceSurfaceCoordinator")

    struct SwitchArrangementTransitions: Equatable {
        let hiddenPaneIds: Set<UUID>
        let paneIdsToReattach: Set<UUID>
    }

    let store: WorkspaceStore
    let viewRegistry: ViewRegistry
    let runtime: SessionRuntime
    let surfaceManager: WorkspaceSurfaceManaging
    let startupTraceRecorder: AgentStudioStartupTraceRecorder?
    let runtimeRegistry: RuntimeRegistry
    let visibilityTierResolver: StoreVisibilityTierResolver
    let runtimeEventReducer: NotificationReducer
    let paneEventBus: EventBus<RuntimeEnvelope>
    let runtimeTargetResolver: RuntimeTargetResolver
    let runtimeCommandClock: ContinuousClock
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let filesystemSource: any WorkspaceFilesystemSourceManaging
    let filesystemProjectionIndex: any WorkspaceFilesystemProjectionIndexing
    let paneFilesystemProjectionStore: PaneFilesystemProjectionAtom
    let windowLifecycleStore: WindowLifecycleAtom
    let traceRuntime: AgentStudioTraceRuntime?
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    #if DEBUG
        var bridgeReviewSourceProviderOverridesByPaneId: [UUID: any BridgeReviewSourceProvider] = [:]
    #endif
    var removeRepoHandler: @MainActor (UUID) -> Void = { _ in }
    lazy var sessionConfig = SessionConfiguration.detect()
    lazy var terminalRestoreRuntime = TerminalRestoreRuntime(sessionConfiguration: sessionConfig)
    private var cwdChangesTask: Task<Void, Never>?
    private var paneEventIngressTask: Task<Void, Never>?
    private var runtimeEventBridgeTasks: [PaneId: Task<Void, Never>] = [:]
    private var criticalRuntimeEventsTask: Task<Void, Never>?
    private var batchedRuntimeEventsTask: Task<Void, Never>?
    var filesystemSyncTask: Task<Void, Never>?
    var filesystemSyncRequested = false
    var pendingFocusPaneIds: Set<UUID> = []
    var filesystemRegisteredContextsByWorktreeId: [UUID: WorktreeFilesystemContext] = [:]
    var filesystemActivityByWorktreeId: [UUID: Bool] = [:]
    var filesystemLastActivePaneWorktreeId: UUID?
    var filesystemLastSidebarVisibleWorktreeIds: Set<UUID> = []
    var filesystemTopologyAssertionGeneration: UInt64 = 0
    var filesystemSyncRequestGeneration: UInt64 = 0
    var filesystemProjectionRequestGeneration: UInt64 = 0
    var filesystemAppliedTopologyGeneration: UInt64 = 0
    var paneContextGeneration: UInt64 = 0
    var pendingTerminalStartupOperationID: String?
    var terminalStartupOperationIDsByPaneID: [UUID: String] = [:]

    var arrangementView: WorkspaceArrangementViewDerived {
        WorkspaceArrangementViewDerived(
            tabLayoutAtom: store.tabLayoutAtom,
            paneAtom: store.paneAtom,
            managementLayerAtom: atom(\.managementLayer)
        )
    }

    /// Unified undo stack — holds both tab and pane close entries, chronologically ordered.
    /// NOTE: Undo stack owned here (not in a store) because undo is fundamentally
    /// orchestration logic: it coordinates across WorkspaceStore, ViewRegistry, and
    /// SessionRuntime. Future: extract to UndoEngine when undo requirements grow.
    private(set) var undoStack: [WorkspaceMutationCoordinator.CloseEntry] = []

    /// Maximum undo stack entries before oldest are garbage-collected.
    let maxUndoStackSize = 10

    convenience init(
        store: WorkspaceStore,
        viewRegistry: ViewRegistry,
        runtime: SessionRuntime,
        windowLifecycleStore: WindowLifecycleAtom
    ) {
        self.init(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: SurfaceManager.shared,
            runtimeRegistry: .shared,
            paneEventBus: PaneRuntimeEventBus.shared,
            runtimeCommandClock: ContinuousClock(),
            windowLifecycleStore: windowLifecycleStore
        )
    }

    init(
        store: WorkspaceStore,
        viewRegistry: ViewRegistry,
        runtime: SessionRuntime,
        surfaceManager: WorkspaceSurfaceManaging,
        startupTraceRecorder: AgentStudioStartupTraceRecorder? = nil,
        runtimeRegistry: RuntimeRegistry,
        paneEventBus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        runtimeCommandClock: ContinuousClock = ContinuousClock(),
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
        filesystemSource: (any WorkspaceFilesystemSourceManaging)? = nil,
        filesystemProjectionIndex: (any WorkspaceFilesystemProjectionIndexing)? = nil,
        paneFilesystemProjectionStore: PaneFilesystemProjectionAtom = PaneFilesystemProjectionAtom(),
        windowLifecycleStore: WindowLifecycleAtom,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        let resolvedFilesystemSource =
            filesystemSource
            ?? FilesystemGitPipeline(
                bus: paneEventBus,
                gitCoalescingWindow: .milliseconds(200),
                performanceTraceRecorder: performanceTraceRecorder
            )
        let visibilityTierResolver = StoreVisibilityTierResolver(store: store)
        self.store = store
        self.viewRegistry = viewRegistry
        self.runtime = runtime
        self.surfaceManager = surfaceManager
        self.startupTraceRecorder = startupTraceRecorder
        self.runtimeRegistry = runtimeRegistry
        self.visibilityTierResolver = visibilityTierResolver
        self.runtimeEventReducer = NotificationReducer(tierResolver: visibilityTierResolver)
        self.paneEventBus = paneEventBus
        self.runtimeTargetResolver = RuntimeTargetResolver(workspaceStore: store)
        self.runtimeCommandClock = runtimeCommandClock
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.filesystemSource = resolvedFilesystemSource
        self.filesystemProjectionIndex = filesystemProjectionIndex ?? FilesystemProjectionIndex()
        self.paneFilesystemProjectionStore = paneFilesystemProjectionStore
        self.windowLifecycleStore = windowLifecycleStore
        self.traceRuntime = traceRuntime
        self.performanceTraceRecorder = performanceTraceRecorder
        Ghostty.App.setRuntimeRegistry(runtimeRegistry)
        subscribeToCWDChanges()
        setupPrePersistHook()
        setupFilesystemSourceSync()
        startPaneEventIngress()
        startRuntimeReducerConsumers()
    }

    isolated deinit {
        cwdChangesTask?.cancel()
        paneEventIngressTask?.cancel()
        for task in runtimeEventBridgeTasks.values {
            task.cancel()
        }
        runtimeEventBridgeTasks.removeAll()
        criticalRuntimeEventsTask?.cancel()
        batchedRuntimeEventsTask?.cancel()
        filesystemSyncTask?.cancel()
        let filesystemSource = filesystemSource
        Task {
            await filesystemSource.shutdown()
        }
    }

    func shutdown() async {
        let activeCWDTask = cwdChangesTask
        let activePaneEventIngressTask = paneEventIngressTask
        let activeCriticalRuntimeEventsTask = criticalRuntimeEventsTask
        let activeBatchedRuntimeEventsTask = batchedRuntimeEventsTask
        let activeFilesystemSyncTask = filesystemSyncTask
        let activeRuntimeBridgeTasks = Array(runtimeEventBridgeTasks.values)

        cwdChangesTask?.cancel()
        cwdChangesTask = nil
        paneEventIngressTask?.cancel()
        paneEventIngressTask = nil
        criticalRuntimeEventsTask?.cancel()
        criticalRuntimeEventsTask = nil
        batchedRuntimeEventsTask?.cancel()
        batchedRuntimeEventsTask = nil
        filesystemSyncTask?.cancel()
        filesystemSyncTask = nil
        filesystemSyncRequested = false

        for task in activeRuntimeBridgeTasks {
            task.cancel()
        }
        runtimeEventBridgeTasks.removeAll()

        if let activeCWDTask {
            await activeCWDTask.value
        }
        if let activePaneEventIngressTask {
            await activePaneEventIngressTask.value
        }
        if let activeCriticalRuntimeEventsTask {
            await activeCriticalRuntimeEventsTask.value
        }
        if let activeBatchedRuntimeEventsTask {
            await activeBatchedRuntimeEventsTask.value
        }
        if let activeFilesystemSyncTask {
            await activeFilesystemSyncTask.value
        }
        for task in activeRuntimeBridgeTasks {
            await task.value
        }

        await filesystemSource.shutdown()
    }

    func appendUndoEntry(_ entry: WorkspaceMutationCoordinator.CloseEntry) {
        undoStack.append(entry)
    }

    @discardableResult
    func popLastUndoEntry() -> WorkspaceMutationCoordinator.CloseEntry? {
        undoStack.popLast()
    }

    @discardableResult
    func removeFirstUndoEntry() -> WorkspaceMutationCoordinator.CloseEntry {
        undoStack.removeFirst()
    }

    // MARK: - CWD Propagation

    private func subscribeToCWDChanges() {
        cwdChangesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.surfaceManager.surfaceCWDChanges {
                if Task.isCancelled { break }
                self.onSurfaceCWDChanged(event)
            }
        }
    }

    private func onSurfaceCWDChanged(_ event: SurfaceManager.SurfaceCWDChangeEvent) {
        guard let paneId = event.paneId else { return }
        // Surface CWD events already arrive as file URLs from the hosting layer.
        // Runtime envelopes carry raw shell strings, so that path normalizes at
        // the runtime ingress before entering the shared atom update path.
        updatePaneCWDAndResolvedContext(paneId: paneId, cwd: event.cwd)
    }

    private func updatePaneCWDAndResolvedContext(paneId: UUID, cwd: URL?) {
        let previousWorktreeId = store.paneAtom.pane(paneId)?.worktreeId
        let resolvedContext = store.repositoryTopologyAtom.repoAndWorktree(containing: cwd)
        let updateResult = store.paneAtom.updatePaneCWDAndResolvedContext(
            paneId,
            cwd: cwd,
            resolvedContext: resolvedContext
        )
        switch updateResult {
        case .applied:
            guard let pane = store.paneAtom.pane(paneId) else {
                removePaneFilesystemProjectionContext(paneId: paneId)
                return
            }
            upsertPaneFilesystemProjectionContext(for: pane)
            if previousWorktreeId != pane.worktreeId {
                syncFilesystemRootsAndActivity()
            }
        case .unchanged:
            return
        case .paneMissing:
            Self.logger.warning("cwd update ignored for missing pane \(paneId.uuidString, privacy: .public)")
            return
        }
    }

    // MARK: - Webview State Sync

    private func setupPrePersistHook() {
        store.prePersistHook = { [weak self] in
            self?.syncWebviewStates()
        }
    }

    /// Sync runtime webview tab state back to persisted pane model.
    /// Uses syncPaneWebviewState (not updatePaneWebviewState) to avoid
    /// marking dirty during an in-flight persist, which would cause a save-loop.
    func syncWebviewStates() {
        for (paneId, webviewView) in viewRegistry.allWebviewViews {
            store.paneAtom.syncPaneWebviewState(paneId, state: webviewView.currentState())
        }
    }

    // MARK: - Runtime Registry

    func registerRuntime(_ runtime: any PaneRuntime) {
        let registrationResult = runtimeRegistry.register(runtime)
        guard registrationResult == .inserted else { return }
        startRuntimeEventBridge(for: runtime)
    }

    @discardableResult
    func unregisterRuntime(_ paneId: PaneId) -> (any PaneRuntime)? {
        stopRuntimeEventBridge(for: paneId)
        return runtimeRegistry.unregister(paneId)
    }

    func runtimeForPane(_ paneId: PaneId) -> (any PaneRuntime)? {
        runtimeRegistry.runtime(for: paneId)
    }

    private func startPaneEventIngress() {
        guard paneEventIngressTask == nil else { return }
        paneEventIngressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let subscription = await self.paneEventBus.subscribe(
                policy: .criticalUnbounded,
                subscriberName: "WorkspaceSurfaceCoordinator"
            )
            for await envelope in subscription {
                if Task.isCancelled { break }
                self.runtimeEventReducer.submit(envelope)
            }
        }
    }

    private func startRuntimeEventBridge(for runtime: any PaneRuntime) {
        guard !(runtime is any BusPostingPaneRuntime) else { return }

        let runtimePaneId = runtime.paneId
        guard runtimeEventBridgeTasks[runtimePaneId] == nil else { return }

        let stream = runtime.subscribe()
        runtimeEventBridgeTasks[runtimePaneId] = Task { @MainActor [weak self] in
            guard let self else { return }
            for await envelope in stream {
                if Task.isCancelled { break }
                await self.paneEventBus.post(envelope)
            }
            self.runtimeEventBridgeTasks.removeValue(forKey: runtimePaneId)
        }
    }

    private func stopRuntimeEventBridge(for paneId: PaneId) {
        runtimeEventBridgeTasks[paneId]?.cancel()
        runtimeEventBridgeTasks.removeValue(forKey: paneId)
    }

    private func startRuntimeReducerConsumers() {
        guard criticalRuntimeEventsTask == nil, batchedRuntimeEventsTask == nil else { return }

        criticalRuntimeEventsTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            for await envelope in self.runtimeEventReducer.criticalEvents {
                if Task.isCancelled { break }
                await self.handleRuntimeEnvelope(envelope)
            }
        }

        batchedRuntimeEventsTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            for await batch in self.runtimeEventReducer.batchedEvents {
                if Task.isCancelled { break }
                for envelope in batch {
                    await self.handleRuntimeEnvelope(envelope)
                }
            }
        }
    }

    private func handleRuntimeEnvelope(_ envelope: RuntimeEnvelope) async {
        if await handleFilesystemEnvelopeIfNeeded(envelope) {
            return
        }

        switch envelope {
        case .pane(let paneEnvelope):
            let sourcePaneId = paneEnvelope.paneId
            switch paneEnvelope.event {
            case .terminal(let event):
                handleTerminalRuntimeEvent(event, sourcePaneId: sourcePaneId)
            case .error(let errorEvent):
                Self.logger.warning(
                    "Runtime error event received from pane \(sourcePaneId.uuid.uuidString, privacy: .public): \(String(describing: errorEvent), privacy: .public)"
                )
            case .paneFilesystemContext(let event):
                await handleBridgePaneFilesystemContext(event, sourcePaneId: sourcePaneId)
            case .lifecycle, .terminalActivity, .browser, .diff, .editor, .agentNotificationRequested, .plugin,
                .artifact, .security, .filesystem:
                Self.logger.debug(
                    "Runtime event family ignored by coordinator for pane \(sourcePaneId.uuid.uuidString, privacy: .public): \(String(describing: paneEnvelope.event), privacy: .public)"
                )
            }
        case .system(let systemEnvelope):
            Self.logger.debug(
                "Runtime event ignored for system source \(String(describing: systemEnvelope.source), privacy: .public): \(String(describing: systemEnvelope.event), privacy: .public)"
            )
        case .worktree(let worktreeEnvelope):
            Self.logger.debug(
                "Runtime event ignored for worktree source \(String(describing: worktreeEnvelope.worktreeId), privacy: .public): \(String(describing: worktreeEnvelope.event), privacy: .public)"
            )
        }
    }

    func handleBridgePaneFilesystemContext(
        _ event: PaneFilesystemContextEvent,
        sourcePaneId: PaneId
    ) async {
        guard
            let bridgeView = viewRegistry.view(for: sourcePaneId.uuid)?
                .mountedContent(as: BridgePaneMountView.self)
        else {
            Self.logger.debug(
                "Runtime filesystem context ignored for non-Bridge pane \(sourcePaneId.uuid.uuidString, privacy: .public)"
            )
            return
        }
        await bridgeView.controller.handlePaneFilesystemContextEvent(event)
    }

    private func handleTerminalRuntimeEvent(_ event: GhosttyEvent, sourcePaneId: PaneId) {
        let sourcePaneUUID = sourcePaneId.uuid
        let tabs = store.tabLayoutAtom.tabs
        guard let sourceTabId = tabs.first(where: { $0.activePaneIds.contains(sourcePaneUUID) })?.id else {
            Self.logger.warning(
                "Terminal runtime event dropped: source pane \(sourcePaneUUID.uuidString, privacy: .public) is not present in any tab. event=\(String(describing: event), privacy: .public)"
            )
            return
        }

        switch event {
        case .newTab:
            openNewTabFromSourcePane(sourcePaneUUID)
        case .newSplit(let direction):
            execute(
                .insertPane(
                    source: .newTerminal,
                    targetTabId: sourceTabId,
                    targetPaneId: sourcePaneUUID,
                    direction: mapSplitDirection(direction),
                    sizingMode: .halveTarget
                )
            )
        case .gotoSplit(let direction):
            guard
                let command = mapGotoSplitDirection(direction),
                let action = WorkspaceCommandResolver.resolve(
                    command: command, tabs: tabs, activeTabId: sourceTabId)
            else {
                Self.logger.debug(
                    "Unable to resolve gotoSplit runtime event for pane \(sourcePaneUUID.uuidString, privacy: .public) direction=\(String(describing: direction), privacy: .public)"
                )
                return
            }
            execute(action)
        case .resizeSplit(let amount, let direction):
            execute(
                .resizePaneByDelta(
                    tabId: sourceTabId,
                    paneId: sourcePaneUUID,
                    direction: mapResizeSplitDirection(direction),
                    amount: amount
                )
            )
        case .equalizeSplits:
            execute(.equalizePanes(tabId: sourceTabId))
        case .toggleSplitZoom:
            execute(.toggleSplitZoom(tabId: sourceTabId, paneId: sourcePaneUUID))
        case .closeTab(let mode):
            executeCloseTabMode(mode, sourceTabId: sourceTabId)
        case .gotoTab(let target):
            executeGotoTabTarget(target, sourceTabId: sourceTabId)
        case .moveTab(let amount):
            execute(.moveTab(tabId: sourceTabId, delta: amount))
        case .titleChanged(let title):
            store.paneAtom.updatePaneTitle(sourcePaneUUID, title: title)
        case .tabTitleChanged(let title):
            store.paneAtom.updatePaneTitle(sourcePaneUUID, title: title)
        case .cwdChanged(let cwdPath):
            // Runtime CWD is a shell string and may contain relative segments;
            // normalize here so both runtime and surface facts converge in the
            // shared pane identity update path below.
            updatePaneCWDAndResolvedContext(paneId: sourcePaneUUID, cwd: CWDNormalizer.normalize(cwdPath))
        case .commandFinished(let exitCode, _):
            Self.logger.debug(
                "Terminal commandFinished event received for pane \(sourcePaneUUID.uuidString, privacy: .public) exitCode=\(exitCode, privacy: .public)"
            )
        case .bellRang:
            AppEventBus.post(.worktreeBellRang(paneId: sourcePaneUUID))
            Self.logger.debug(
                "Terminal bell event received for pane \(sourcePaneUUID.uuidString, privacy: .public)"
            )
        case .progressReportUpdated, .readOnlyChanged, .secureInputRequested, .secureInputChanged,
            .rendererHealthChanged, .cellSizeChanged, .initialSizeChanged, .sizeLimitChanged,
            .mouseShapeChanged, .mouseVisibilityChanged, .mouseLinkHovered, .keySequenceChanged,
            .keyTableChanged, .colorChanged, .configReloadRequested, .configChanged,
            .searchStarted, .searchEnded, .searchMatchesUpdated, .searchSelectionChanged,
            .promptTitleRequested, .desktopNotificationRequested, .openURLRequested, .undoRequested,
            .redoRequested, .copyTitleToClipboardRequested, .scrollbarChanged, .deferred, .unhandled:
            Self.logger.debug(
                "Terminal runtime event ignored by coordinator for pane \(sourcePaneUUID.uuidString, privacy: .public): \(String(describing: event), privacy: .public)"
            )
        }
    }

    private func openNewTabFromSourcePane(_ sourcePaneId: UUID) {
        let workspaceRepositoryTopology = store.repositoryTopologyAtom
        if let sourcePane = store.paneAtom.pane(sourcePaneId),
            let worktreeId = sourcePane.worktreeId,
            let repoId = sourcePane.repoId,
            let worktree = workspaceRepositoryTopology.worktree(worktreeId),
            let repo = workspaceRepositoryTopology.repo(repoId)
        {
            _ = openNewTerminal(for: worktree, in: repo)
            return
        }

        if let repo = workspaceRepositoryTopology.repos.first, let worktree = repo.worktrees.first {
            _ = openNewTerminal(for: worktree, in: repo)
            return
        }

        Self.logger.warning(
            "Unable to open new tab from source pane \(sourcePaneId.uuidString, privacy: .public): no repo/worktree available"
        )
    }

    private func executeCloseTabMode(_ mode: GhosttyCloseTabMode, sourceTabId: UUID) {
        let tabs = store.tabLayoutAtom.tabs
        switch mode {
        case .thisTab:
            execute(.closeTab(tabId: sourceTabId))
        case .otherTabs:
            for tab in tabs where tab.id != sourceTabId {
                execute(.closeTab(tabId: tab.id))
            }
        case .rightTabs:
            guard let sourceTabIndex = tabs.firstIndex(where: { $0.id == sourceTabId }) else { return }
            let rightTabs = tabs.dropFirst(sourceTabIndex + 1)
            for tab in rightTabs {
                execute(.closeTab(tabId: tab.id))
            }
        }
    }

    private func executeGotoTabTarget(_ target: GhosttyGotoTabTarget, sourceTabId: UUID) {
        let tabs = store.tabLayoutAtom.tabs
        guard !tabs.isEmpty else { return }

        let action: WorkspaceActionCommand?
        switch target {
        case .previous:
            action = WorkspaceCommandResolver.resolve(command: .prevTab, tabs: tabs, activeTabId: sourceTabId)
        case .next:
            action = WorkspaceCommandResolver.resolve(command: .nextTab, tabs: tabs, activeTabId: sourceTabId)
        case .last:
            action = tabs.last.map { .selectTab(tabId: $0.id) }
        case .index(let oneBasedIndex):
            let zeroBasedIndex = min(max(oneBasedIndex - 1, 0), tabs.count - 1)
            action = .selectTab(tabId: tabs[zeroBasedIndex].id)
        }

        if let action {
            execute(action)
        } else {
            Self.logger.debug(
                "Unable to resolve gotoTab runtime event for sourceTabId \(sourceTabId.uuidString, privacy: .public) target=\(String(describing: target), privacy: .public)"
            )
        }
    }

    /// Map Ghostty split direction to layout direction.
    /// The flat pane strip only supports horizontal layout, so vertical
    /// directions are mapped to their horizontal equivalents.
    private func mapSplitDirection(_ direction: GhosttySplitDirection) -> SplitNewDirection {
        switch direction {
        case .left, .up:
            return .left
        case .right, .down:
            return .right
        }
    }

    /// Map Ghostty resize direction to layout resize direction.
    /// Vertical resize is mapped to horizontal (flat strip only).
    private func mapResizeSplitDirection(_ direction: GhosttyResizeSplitDirection) -> SplitResizeDirection {
        switch direction {
        case .left, .up:
            return .left
        case .right, .down:
            return .right
        }
    }

    /// Map Ghostty goto-split direction to an app command.
    /// Vertical focus is mapped to horizontal (flat strip only).
    private func mapGotoSplitDirection(_ direction: GhosttyGotoSplitDirection) -> AppCommand? {
        switch direction {
        case .previous:
            return .focusPrevPane
        case .next:
            return .focusNextPane
        case .left, .up:
            return .focusPaneLeft
        case .right, .down:
            return .focusPaneRight
        }
    }
}

extension WorkspaceSurfaceCoordinator: TopologyEffectHandler {
    func topologyDidChange(_ delta: WorktreeTopologyDelta) {
        applyTopologyRemovals(from: [delta])
        syncFilesystemRootsAndActivity()
    }

    func topologyDidChange(_ deltas: [WorktreeTopologyDelta]) {
        applyTopologyRemovals(from: deltas)
        syncFilesystemRootsAndActivity()
    }

    private func applyTopologyRemovals(from deltas: [WorktreeTopologyDelta]) {
        for delta in deltas {
            applyTopologyRemovals(from: delta)
        }
    }

    private func applyTopologyRemovals(from delta: WorktreeTopologyDelta) {
        for entry in delta.removedWorktrees {
            let orphanedPaneIds = store.paneAtom.orphanPanesForWorktree(entry.id, path: entry.path.path)
            if !orphanedPaneIds.isEmpty {
                Self.logger.info(
                    "Worktree removed id=\(entry.id.uuidString, privacy: .public) path=\(entry.path.path, privacy: .public); orphaned \(orphanedPaneIds.count, privacy: .public) pane(s)"
                )
            }
        }
    }

    // MARK: - Tab Name Derivation

    /// Seed a stable tab name once at creation time from the pane's context.
    /// Worktree-backed panes get "folder · branch", others get the pane title.
    /// We intentionally do not auto-rename tabs later when enrichment changes.
    func tabNameForPane(_ pane: Pane) -> String {
        atom(\.tabDisplay).title(
            for: pane,
            workspaceRepositoryTopology: store.repositoryTopologyAtom,
            repoCache: atom(\.repoCache)
        )
    }
}
