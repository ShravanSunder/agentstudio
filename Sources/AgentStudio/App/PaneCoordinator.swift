import AppKit
import Foundation
import GhosttyKit
import os.log

@MainActor
protocol PaneCoordinatorSurfaceManaging: AnyObject {
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

extension SurfaceManager: PaneCoordinatorSurfaceManaging {}

@MainActor
final class PaneCoordinator {
    nonisolated static let logger = Logger(subsystem: "com.agentstudio", category: "PaneCoordinator")

    struct SwitchArrangementTransitions: Equatable {
        let hiddenPaneIds: Set<UUID>
        let paneIdsToReattach: Set<UUID>
    }

    let store: WorkspaceStore
    let viewRegistry: ViewRegistry
    let runtime: SessionRuntime
    let surfaceManager: PaneCoordinatorSurfaceManaging
    let runtimeRegistry: RuntimeRegistry
    let runtimeTargetResolver: RuntimeTargetResolver
    let runtimeCommandClock: ContinuousClock
    lazy var sessionConfig = SessionConfiguration.detect()
    private var cwdChangesTask: Task<Void, Never>?
    private var runtimeEventTasks: [PaneId: Task<Void, Never>] = [:]

    /// Unified undo stack — holds both tab and pane close entries, chronologically ordered.
    /// NOTE: Undo stack owned here (not in a store) because undo is fundamentally
    /// orchestration logic: it coordinates across WorkspaceStore, ViewRegistry, and
    /// SessionRuntime. Future: extract to UndoEngine when undo requirements grow.
    private(set) var undoStack: [WorkspaceStore.CloseEntry] = []

    /// Maximum undo stack entries before oldest are garbage-collected.
    let maxUndoStackSize = 10

    convenience init(
        store: WorkspaceStore,
        viewRegistry: ViewRegistry,
        runtime: SessionRuntime
    ) {
        self.init(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: SurfaceManager.shared,
            runtimeRegistry: .shared,
            runtimeCommandClock: ContinuousClock()
        )
    }

    init(
        store: WorkspaceStore,
        viewRegistry: ViewRegistry,
        runtime: SessionRuntime,
        surfaceManager: PaneCoordinatorSurfaceManaging,
        runtimeRegistry: RuntimeRegistry,
        runtimeCommandClock: ContinuousClock = ContinuousClock()
    ) {
        self.store = store
        self.viewRegistry = viewRegistry
        self.runtime = runtime
        self.surfaceManager = surfaceManager
        self.runtimeRegistry = runtimeRegistry
        self.runtimeTargetResolver = RuntimeTargetResolver(workspaceStore: store)
        self.runtimeCommandClock = runtimeCommandClock
        subscribeToCWDChanges()
        setupPrePersistHook()
    }

    isolated deinit {
        cwdChangesTask?.cancel()
        for task in runtimeEventTasks.values {
            task.cancel()
        }
        runtimeEventTasks.removeAll()
    }

    func appendUndoEntry(_ entry: WorkspaceStore.CloseEntry) {
        undoStack.append(entry)
    }

    @discardableResult
    func popLastUndoEntry() -> WorkspaceStore.CloseEntry? {
        undoStack.popLast()
    }

    @discardableResult
    func removeFirstUndoEntry() -> WorkspaceStore.CloseEntry {
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
        store.updatePaneCWD(paneId, cwd: event.cwd)
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
            store.syncPaneWebviewState(paneId, state: webviewView.currentState())
        }
    }

    // MARK: - Runtime Registry

    func registerRuntime(_ runtime: any PaneRuntime) {
        let registrationResult = runtimeRegistry.register(runtime)
        guard registrationResult == .inserted else { return }
        startRuntimeEventSubscription(for: runtime)
    }

    @discardableResult
    func unregisterRuntime(_ paneId: PaneId) -> (any PaneRuntime)? {
        stopRuntimeEventSubscription(for: paneId)
        return runtimeRegistry.unregister(paneId)
    }

    func runtimeForPane(_ paneId: PaneId) -> (any PaneRuntime)? {
        runtimeRegistry.runtime(for: paneId)
    }

    private func startRuntimeEventSubscription(for runtime: any PaneRuntime) {
        let runtimePaneId = runtime.paneId
        guard runtimeEventTasks[runtimePaneId] == nil else { return }

        let stream = runtime.subscribe()
        runtimeEventTasks[runtimePaneId] = Task { @MainActor [weak self] in
            guard let self else { return }
            for await envelope in stream {
                if Task.isCancelled { break }
                self.handleRuntimeEnvelope(envelope)
            }
            self.runtimeEventTasks.removeValue(forKey: runtimePaneId)
        }
    }

    private func stopRuntimeEventSubscription(for paneId: PaneId) {
        runtimeEventTasks[paneId]?.cancel()
        runtimeEventTasks.removeValue(forKey: paneId)
    }

    private func handleRuntimeEnvelope(_ envelope: PaneEventEnvelope) {
        guard case .pane(let sourcePaneId) = envelope.source else { return }

        switch envelope.event {
        case .terminal(let event):
            handleTerminalRuntimeEvent(event, sourcePaneId: sourcePaneId)
        case .error(let errorEvent):
            Self.logger.warning(
                "Runtime error event received from pane \(sourcePaneId.uuid.uuidString, privacy: .public): \(String(describing: errorEvent), privacy: .public)"
            )
        case .lifecycle, .browser, .diff, .editor, .plugin, .filesystem, .artifact, .security:
            Self.logger.debug(
                "Runtime event family ignored by coordinator for pane \(sourcePaneId.uuid.uuidString, privacy: .public): \(String(describing: envelope.event), privacy: .public)"
            )
        }
    }

    private func handleTerminalRuntimeEvent(_ event: GhosttyEvent, sourcePaneId: PaneId) {
        let sourcePaneUUID = sourcePaneId.uuid
        guard let sourceTabId = store.tabs.first(where: { $0.paneIds.contains(sourcePaneUUID) })?.id else {
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
                    direction: mapSplitDirection(direction)
                )
            )
        case .gotoSplit(let direction):
            guard
                let command = mapGotoSplitDirection(direction),
                let action = ActionResolver.resolve(command: command, tabs: store.tabs, activeTabId: sourceTabId)
            else {
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
        case .titleChanged, .cwdChanged, .commandFinished, .bellRang, .scrollbarChanged, .unhandled:
            Self.logger.debug(
                "Terminal runtime event ignored by coordinator for pane \(sourcePaneUUID.uuidString, privacy: .public): \(String(describing: event), privacy: .public)"
            )
        }
    }

    private func openNewTabFromSourcePane(_ sourcePaneId: UUID) {
        if let sourcePane = store.pane(sourcePaneId),
            let worktreeId = sourcePane.worktreeId,
            let repoId = sourcePane.repoId,
            let worktree = store.worktree(worktreeId),
            let repo = store.repo(repoId)
        {
            _ = openNewTerminal(for: worktree, in: repo)
            return
        }

        if let repo = store.repos.first, let worktree = repo.worktrees.first {
            _ = openNewTerminal(for: worktree, in: repo)
            return
        }

        Self.logger.warning(
            "Unable to open new tab from source pane \(sourcePaneId.uuidString, privacy: .public): no repo/worktree available"
        )
    }

    private func executeCloseTabMode(_ mode: GhosttyCloseTabMode, sourceTabId: UUID) {
        let tabs = store.tabs
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
        let tabs = store.tabs
        guard !tabs.isEmpty else { return }

        let action: PaneAction?
        switch target {
        case .previous:
            action = ActionResolver.resolve(command: .prevTab, tabs: tabs, activeTabId: sourceTabId)
        case .next:
            action = ActionResolver.resolve(command: .nextTab, tabs: tabs, activeTabId: sourceTabId)
        case .last:
            action = tabs.last.map { .selectTab(tabId: $0.id) }
        case .index(let oneBasedIndex):
            let zeroBasedIndex = min(max(oneBasedIndex - 1, 0), tabs.count - 1)
            action = .selectTab(tabId: tabs[zeroBasedIndex].id)
        }

        if let action {
            execute(action)
        }
    }

    private func mapSplitDirection(_ direction: GhosttySplitDirection) -> SplitNewDirection {
        switch direction {
        case .left:
            return .left
        case .right:
            return .right
        case .up:
            return .up
        case .down:
            return .down
        }
    }

    private func mapResizeSplitDirection(_ direction: GhosttyResizeSplitDirection) -> SplitResizeDirection {
        switch direction {
        case .left:
            return .left
        case .right:
            return .right
        case .up:
            return .up
        case .down:
            return .down
        }
    }

    private func mapGotoSplitDirection(_ direction: GhosttyGotoSplitDirection) -> AppCommand? {
        switch direction {
        case .previous:
            return .focusPrevPane
        case .next:
            return .focusNextPane
        case .left:
            return .focusPaneLeft
        case .right:
            return .focusPaneRight
        case .up:
            return .focusPaneUp
        case .down:
            return .focusPaneDown
        }
    }
}
