import Foundation
import Observation
import os.log

private let workspaceStoreLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

/// Main-actor persistence aggregate for the workspace atoms.
///
/// This type owns debounced persistence, restore, and flush. Workspace-domain
/// mutations live on the owning atoms or `WorkspaceMutationCoordinator`.
@MainActor
final class WorkspaceStore {
    let metadataAtom: WorkspaceMetadataAtom
    let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    let paneAtom: WorkspacePaneAtom
    let tabShellAtom: WorkspaceTabShellAtom
    let tabArrangementAtom: WorkspaceTabArrangementAtom
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let mutationCoordinator: WorkspaceMutationCoordinator

    private let persistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingPersistedState = false
    private var isRestoringState = false
    private(set) var isDirty: Bool = false

    init(
        metadataAtom: WorkspaceMetadataAtom = WorkspaceMetadataAtom(),
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom = WorkspaceRepositoryTopologyAtom(),
        paneAtom: WorkspacePaneAtom = WorkspacePaneAtom(),
        tabShellAtom: WorkspaceTabShellAtom = WorkspaceTabShellAtom(),
        tabArrangementAtom: WorkspaceTabArrangementAtom = WorkspaceTabArrangementAtom(),
        tabLayoutAtom: WorkspaceTabLayoutAtom? = nil,
        mutationCoordinator: WorkspaceMutationCoordinator? = nil,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        let resolvedTabShellAtom = tabLayoutAtom?.shellAtom ?? tabShellAtom
        let resolvedTabArrangementAtom = tabLayoutAtom?.arrangementAtom ?? tabArrangementAtom
        self.metadataAtom = metadataAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.paneAtom = paneAtom
        self.tabShellAtom = resolvedTabShellAtom
        self.tabArrangementAtom = resolvedTabArrangementAtom
        self.tabLayoutAtom =
            tabLayoutAtom
            ?? WorkspaceTabLayoutAtom(
                shellAtom: resolvedTabShellAtom,
                arrangementAtom: resolvedTabArrangementAtom
            )
        self.mutationCoordinator =
            mutationCoordinator
            ?? WorkspaceMutationCoordinator(
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabShellAtom: resolvedTabShellAtom,
                workspaceTabArrangementAtom: resolvedTabArrangementAtom
            )
        self.persistor = persistor
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
        self.recoveryReporter = recoveryReporter
        observePersistedState()
    }

    typealias CloseEntry = WorkspaceMutationCoordinator.CloseEntry
    typealias TabCloseSnapshot = WorkspaceMutationCoordinator.TabCloseSnapshot
    typealias PaneCloseSnapshot = WorkspaceMutationCoordinator.PaneCloseSnapshot
    typealias CloseSnapshot = TabCloseSnapshot

    // MARK: - Persistence

    func restore() {
        _ = persistor.ensureDirectory()
        switch persistor.load() {
        case .loaded(let state):
            isRestoringState = true
            WorkspacePersistenceTransformer.hydrate(
                state,
                metadataAtom: metadataAtom,
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom
            )
            isRestoringState = false
            let hydratedPaneCount = paneAtom.panes.count
            let hydratedTabCount = tabLayoutAtom.tabs.count
            let droppedPaneCount = max(0, state.panes.count - hydratedPaneCount)
            let droppedTabCount = max(0, state.tabs.count - hydratedTabCount)
            workspaceStoreLogger.info(
                "Restored workspace '\(state.name)' with \(hydratedPaneCount) pane(s), \(hydratedTabCount) tab(s), dropped \(droppedPaneCount) pane(s), dropped \(droppedTabCount) tab(s)"
            )
        case .corrupt(let error):
            let quarantine = persistor.quarantineCorruptCanonicalWorkspaceFiles()
            workspaceStoreLogger.error(
                "Workspace file exists but failed to decode; quarantined canonical workspace files before starting with empty state: \(error)"
            )
            recoveryReporter?(
                .init(
                    store: .workspace,
                    workspaceId: quarantine?.workspaceId,
                    recovery: .quarantinedAndReset,
                    quarantinedFilename: quarantine?.recoveryFilename
                )
            )
        case .missing:
            workspaceStoreLogger.info("No workspace files found — first launch")
        }
    }

    @discardableResult
    func flush() -> Bool {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        return persistNow()
    }

    var prePersistHook: (() -> Void)?

    private func observePersistedState() {
        guard !isObservingPersistedState else { return }
        isObservingPersistedState = true
        withObservationTracking {
            _ = metadataAtom.workspaceId
            _ = metadataAtom.workspaceName
            _ = metadataAtom.createdAt
            _ = metadataAtom.sidebarWidth
            _ = metadataAtom.windowFrame
            _ = repositoryTopologyAtom.repos
            _ = repositoryTopologyAtom.watchedPaths
            _ = repositoryTopologyAtom.unavailableRepoIds
            _ = paneAtom.panes
            _ = tabLayoutAtom.tabs
            _ = tabLayoutAtom.activeTabId
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shouldIgnore = self.isRestoringState
                self.isObservingPersistedState = false
                self.observePersistedState()
                guard !shouldIgnore else { return }
                self.markDirtyObserved()
            }
        }
    }

    private func markDirtyObserved() {
        if !isDirty {
            isDirty = true
            ProcessInfo.processInfo.disableSuddenTermination()
        }

        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.persistDebounceDuration)
            guard !Task.isCancelled else { return }
            _ = self.persistNow()
        }
    }

    @discardableResult
    private func persistNow() -> Bool {
        prePersistHook?()
        guard persistor.ensureDirectory() else {
            workspaceStoreLogger.error(
                "Failed to persist workspace because the workspaces directory could not be created"
            )
            return false
        }

        let persistedAt = Date()
        let state = WorkspacePersistenceTransformer.makePersistableState(
            metadataAtom: metadataAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: persistedAt
        )

        do {
            try persistor.save(state)
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return true
        } catch {
            workspaceStoreLogger.error("Failed to persist workspace: \(error.localizedDescription)")
            return false
        }
    }
}
