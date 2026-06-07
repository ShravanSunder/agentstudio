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
    let identityAtom: WorkspaceIdentityAtom
    let windowMemoryAtom: WorkspaceWindowMemoryAtom
    let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    let paneGraphAtom: WorkspacePaneGraphAtom
    let drawerCursorAtom: WorkspaceDrawerCursorAtom
    let paneAtom: WorkspacePaneAtom
    let tabShellAtom: WorkspaceTabShellAtom
    let tabCursorAtom: WorkspaceTabCursorAtom
    let tabGraphAtom: WorkspaceTabGraphAtom
    let arrangementCursorAtom: WorkspaceArrangementCursorAtom
    let panePresentationAtom: WorkspacePanePresentationAtom
    let tabArrangementAtom: WorkspaceTabArrangementAtom
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let mutationCoordinator: WorkspaceMutationCoordinator

    private let persistor: WorkspacePersistor
    private let sqliteBackend: WorkspaceSQLiteStoreBackend?
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingPersistedState = false
    private var isRestoringState = false
    private(set) var isDirty: Bool = false

    init(
        identityAtom: WorkspaceIdentityAtom = WorkspaceIdentityAtom(),
        windowMemoryAtom: WorkspaceWindowMemoryAtom = WorkspaceWindowMemoryAtom(),
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom = WorkspaceRepositoryTopologyAtom(),
        paneGraphAtom: WorkspacePaneGraphAtom = WorkspacePaneGraphAtom(),
        drawerCursorAtom: WorkspaceDrawerCursorAtom = WorkspaceDrawerCursorAtom(),
        paneAtom: WorkspacePaneAtom? = nil,
        tabShellAtom: WorkspaceTabShellAtom = WorkspaceTabShellAtom(),
        tabArrangementAtom: WorkspaceTabArrangementAtom = WorkspaceTabArrangementAtom(),
        tabLayoutAtom: WorkspaceTabLayoutAtom? = nil,
        mutationCoordinator: WorkspaceMutationCoordinator? = nil,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        sqliteBackend: WorkspaceSQLiteStoreBackend? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        let resolvedTabShellAtom = tabLayoutAtom?.shellAtom ?? tabShellAtom
        let resolvedTabArrangementAtom = tabLayoutAtom?.arrangementAtom ?? tabArrangementAtom
        let resolvedPaneAtom =
            paneAtom
            ?? WorkspacePaneAtom(
                graphAtom: paneGraphAtom,
                drawerCursorAtom: drawerCursorAtom,
                repositoryTopologyAtom: repositoryTopologyAtom
            )
        self.identityAtom = identityAtom
        self.windowMemoryAtom = windowMemoryAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.paneGraphAtom = resolvedPaneAtom.graphAtom
        self.drawerCursorAtom = resolvedPaneAtom.drawerCursorAtom
        self.paneAtom = resolvedPaneAtom
        self.tabShellAtom = resolvedTabShellAtom
        self.tabCursorAtom = resolvedTabShellAtom.cursorAtom
        self.tabArrangementAtom = resolvedTabArrangementAtom
        self.tabGraphAtom = resolvedTabArrangementAtom.graphAtom
        self.arrangementCursorAtom = resolvedTabArrangementAtom.cursorAtom
        self.panePresentationAtom = resolvedTabArrangementAtom.presentationAtom
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
                workspacePaneAtom: resolvedPaneAtom,
                workspaceTabShellAtom: resolvedTabShellAtom,
                workspaceTabArrangementAtom: resolvedTabArrangementAtom
            )
        self.persistor = persistor
        self.sqliteBackend = sqliteBackend
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
        if let sqliteBackend, restoreFromSQLite(sqliteBackend) {
            return
        }

        _ = persistor.ensureDirectory()
        switch persistor.load() {
        case .loaded(let state):
            isRestoringState = true
            WorkspacePersistenceTransformer.hydrate(
                state,
                identityAtom: identityAtom,
                windowMemoryAtom: windowMemoryAtom,
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
            if let sqliteBackend {
                materializeRestoredSQLiteState(from: state, using: sqliteBackend)
            }
        case .corrupt(let error):
            let quarantine = persistor.quarantineCorruptCanonicalWorkspaceFiles()
            workspaceStoreLogger.error(
                "Workspace file exists but failed to decode; quarantined canonical workspace files before starting with empty state: \(error)"
            )
            recoveryReporter?(
                .init(
                    store: .workspace,
                    workspaceId: quarantine?.workspaceId,
                    recovery: quarantine?.recovery ?? .quarantineFailed,
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
            _ = identityAtom.workspaceId
            _ = identityAtom.workspaceName
            _ = identityAtom.createdAt
            _ = windowMemoryAtom.sidebarWidth
            _ = windowMemoryAtom.windowFrame
            _ = repositoryTopologyAtom.repos
            _ = repositoryTopologyAtom.watchedPaths
            _ = repositoryTopologyAtom.unavailableRepoIds
            _ = paneGraphAtom.paneStates
            _ = drawerCursorAtom.expandedDrawerId
            _ = tabShellAtom.tabShells
            _ = tabCursorAtom.activeTabId
            _ = tabGraphAtom.tabStates
            _ = arrangementCursorAtom.activeArrangementIdsByTabId
            _ = arrangementCursorAtom.paneCursorsByArrangementId
            _ = arrangementCursorAtom.drawerCursorsByKey
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

        let persistedAt = Date()
        let state = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: persistedAt
        )

        do {
            if let sqliteBackend {
                try sqliteBackend.save(state)
            } else {
                guard persistor.ensureDirectory() else {
                    workspaceStoreLogger.error(
                        "Failed to persist workspace because the workspaces directory could not be created"
                    )
                    reportSaveFailed()
                    return false
                }
                try persistor.save(state)
            }
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return true
        } catch {
            workspaceStoreLogger.error("Failed to persist workspace: \(error.localizedDescription)")
            reportSaveFailed()
            return false
        }
    }

    private func restoreFromSQLite(_ sqliteBackend: WorkspaceSQLiteStoreBackend) -> Bool {
        do {
            guard let state = try sqliteBackend.load(preferredWorkspaceId: identityAtom.workspaceId) else {
                return false
            }
            isRestoringState = true
            WorkspacePersistenceTransformer.hydrate(
                state,
                identityAtom: identityAtom,
                windowMemoryAtom: windowMemoryAtom,
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom
            )
            isRestoringState = false
            workspaceStoreLogger.info(
                "Restored SQLite workspace '\(state.name)' with \(self.paneAtom.panes.count) pane(s), \(self.tabLayoutAtom.tabs.count) tab(s)"
            )
            return true
        } catch {
            isRestoringState = false
            workspaceStoreLogger.error("Failed to restore SQLite workspace: \(error.localizedDescription)")
            recoveryReporter?(
                .init(
                    store: .workspace,
                    workspaceId: identityAtom.workspaceId,
                    recovery: .resetToDefaults
                )
            )
            return false
        }
    }

    private func materializeRestoredSQLiteState(
        from legacyState: WorkspacePersistor.PersistableState,
        using sqliteBackend: WorkspaceSQLiteStoreBackend
    ) {
        let materializedState = WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: legacyState.updatedAt
        )
        do {
            try sqliteBackend.save(materializedState)
        } catch {
            workspaceStoreLogger.error(
                "Failed to materialize restored legacy workspace into SQLite: \(error.localizedDescription)"
            )
            reportSaveFailed()
        }
    }

    private func reportSaveFailed() {
        recoveryReporter?(
            .init(
                store: .workspace,
                workspaceId: identityAtom.workspaceId,
                recovery: .saveFailed
            )
        )
    }
}
