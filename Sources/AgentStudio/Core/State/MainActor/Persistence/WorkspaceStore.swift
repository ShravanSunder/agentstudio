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

    let persistor: WorkspacePersistor
    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    let recoveryReporter: PersistenceRecoveryReporter?
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
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
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
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.recoveryReporter = recoveryReporter
        observePersistedState()
    }

    typealias CloseEntry = WorkspaceMutationCoordinator.CloseEntry
    typealias TabCloseSnapshot = WorkspaceMutationCoordinator.TabCloseSnapshot
    typealias PaneCloseSnapshot = WorkspaceMutationCoordinator.PaneCloseSnapshot
    typealias CloseSnapshot = TabCloseSnapshot

    // MARK: - Persistence

    func restore() {
        guard sqliteDatastore == nil else {
            preconditionFailure("Use await restoreAsync() when SQLite datastore is enabled")
        }
        _ = restoreFromLegacyJSON()
    }

    func restoreAsync() async {
        guard let sqliteDatastore else {
            _ = restoreFromLegacyJSON()
            return
        }

        let hadActiveSelectionBeforeSQLiteRestore = await sqliteDatastoreHasActiveWorkspaceSelection(sqliteDatastore)
        switch await restoreFromSQLite(sqliteDatastore) {
        case .restored(let recoveryEvents):
            reportRecoveryEvents(recoveryEvents)
            await resumeUnfinishedLegacySQLiteImportKeepingCurrentSelection(sqliteDatastore)
            return
        case .uninitialized(let recoveryEvents):
            reportRecoveryEvents(recoveryEvents)
            if await sqliteDatastoreHasWorkspaceRows(sqliteDatastore) {
                let outcome = await resumeUnfinishedLegacySQLiteImportAfterIncompleteSQLiteRestore(
                    sqliteDatastore,
                    hadActiveSelectionBeforeRestore: hadActiveSelectionBeforeSQLiteRestore
                )
                switch outcome {
                case .failedNoUsableImport, .noLegacyFiles, .noPendingFilesKeepingSelection,
                    .retriedWithoutSelectionChange:
                    reportSQLiteRestoreFailed()
                case .failedButImportedSome, .importedInitialActive:
                    break
                }
                return
            }
            switch await importLegacySQLiteWorkspacesInPlaceOnFirstBoot(sqliteDatastore) {
            case .importedInitialActive, .failedButImportedSome, .failedNoUsableImport:
                return
            case .noLegacyFiles, .noPendingFilesKeepingSelection, .retriedWithoutSelectionChange:
                break
            }
        case .unavailable(let recoveryEvents):
            reportRecoveryEvents(recoveryEvents)
            if await sqliteDatastoreHasWorkspaceRows(sqliteDatastore) {
                let outcome = await resumeUnfinishedLegacySQLiteImportAfterIncompleteSQLiteRestore(
                    sqliteDatastore,
                    hadActiveSelectionBeforeRestore: hadActiveSelectionBeforeSQLiteRestore
                )
                switch outcome {
                case .failedNoUsableImport, .noLegacyFiles, .noPendingFilesKeepingSelection,
                    .retriedWithoutSelectionChange:
                    reportSQLiteRestoreFailed()
                case .failedButImportedSome, .importedInitialActive:
                    break
                }
            }
            return
        }

        if let restoredLegacyState = restoreFromLegacyJSON() {
            _ = await materializeRestoredSQLiteState(
                from: restoredLegacyState,
                sourceStatePath: persistor.canonicalWorkspaceStatePath(for: restoredLegacyState.id),
                using: sqliteDatastore
            )
        }
    }

    @discardableResult
    private func restoreFromLegacyJSON() -> WorkspacePersistor.PersistableState? {
        _ = persistor.ensureDirectory()
        switch persistor.load() {
        case .loaded(let state):
            hydrateWorkspaceState(state)
            let hydratedPaneCount = paneAtom.panes.count
            let hydratedTabCount = tabLayoutAtom.tabs.count
            let droppedPaneCount = max(0, state.panes.count - hydratedPaneCount)
            let droppedTabCount = max(0, state.tabs.count - hydratedTabCount)
            workspaceStoreLogger.info(
                "Restored workspace '\(state.name)' with \(hydratedPaneCount) pane(s), \(hydratedTabCount) tab(s), dropped \(droppedPaneCount) pane(s), dropped \(droppedTabCount) tab(s)"
            )
            return state
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
        return nil
    }

    private func sqliteDatastoreHasActiveWorkspaceSelection(_ sqliteDatastore: WorkspaceSQLiteDatastore) async -> Bool {
        switch await sqliteDatastore.inspectActiveWorkspaceSelection() {
        case .present:
            return true
        case .missing:
            return false
        case .unavailable(let failure):
            workspaceStoreLogger.error(
                "Failed to inspect active SQLite workspace selection: \(failure.description)")
            return true
        }
    }

    private func sqliteDatastoreHasWorkspaceRows(_ sqliteDatastore: WorkspaceSQLiteDatastore) async -> Bool {
        switch await sqliteDatastore.inspectWorkspaceRows() {
        case .hasWorkspaceRows:
            return true
        case .empty:
            return false
        case .unavailable(let failure):
            workspaceStoreLogger.error("Failed to inspect SQLite workspace rows: \(failure.description)")
            return true
        }
    }

    private func reportSQLiteRestoreFailed() {
        recoveryReporter?(
            .init(
                store: .workspace,
                workspaceId: identityAtom.workspaceId,
                recovery: .resetToDefaults
            )
        )
    }

    @discardableResult
    func flush() -> Bool {
        guard sqliteDatastore == nil else {
            preconditionFailure("Use await flushAsync() when SQLite datastore is enabled")
        }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        return persistLegacyJSONSnapshot(persistedAt: Date()).succeeded
    }

    @discardableResult
    func flushAsync() async -> WorkspaceStoreFlushOutcome {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        return await persistNow()
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
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        debouncedSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            _ = await self.persistNow()
        }
    }

    @discardableResult
    private func persistNow() async -> WorkspaceStoreFlushOutcome {
        let persistedAt = Date()
        do {
            if let sqliteDatastore {
                prePersistHook?()
                let snapshot = WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(
                    identityAtom: identityAtom,
                    windowMemoryAtom: windowMemoryAtom,
                    repositoryTopologyAtom: repositoryTopologyAtom,
                    workspacePaneAtom: paneAtom,
                    workspaceTabLayoutAtom: tabLayoutAtom,
                    persistedAt: persistedAt
                )
                try await sqliteDatastore.saveWorkspaceSnapshot(snapshot)
            } else {
                return persistLegacyJSONSnapshot(persistedAt: persistedAt)
            }
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return .persisted
        } catch {
            workspaceStoreLogger.error("Failed to persist workspace: \(String(reflecting: error))")
            reportSaveFailed()
            return .failed(String(describing: error))
        }
    }

    private enum SQLiteRestoreOutcome {
        case restored(recoveryEvents: [PersistenceRecoveryEvent])
        case uninitialized(recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(recoveryEvents: [PersistenceRecoveryEvent])
    }

    private func restoreFromSQLite(_ sqliteDatastore: WorkspaceSQLiteDatastore) async -> SQLiteRestoreOutcome {
        switch await sqliteDatastore.loadWorkspaceSnapshot(preferredWorkspaceId: identityAtom.workspaceId) {
        case .loaded(let snapshot, let recoveryEvents):
            let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
            hydrateWorkspaceState(state)
            workspaceStoreLogger.info(
                "Restored SQLite workspace '\(state.name)' with \(self.paneAtom.panes.count) pane(s), \(self.tabLayoutAtom.tabs.count) tab(s)"
            )
            return .restored(recoveryEvents: recoveryEvents)
        case .uninitialized(let recoveryEvents):
            return .uninitialized(recoveryEvents: recoveryEvents)
        case .unavailable(let failure, let recoveryEvents):
            isRestoringState = false
            workspaceStoreLogger.error("Failed to restore SQLite workspace: \(failure.description)")
            reportSQLiteRestoreFailed()
            return .unavailable(recoveryEvents: recoveryEvents)
        }
    }

    func hydrateWorkspaceState(_ state: WorkspacePersistor.PersistableState) {
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
    }

    func reportSaveFailed() {
        recoveryReporter?(
            .init(
                store: .workspace,
                workspaceId: identityAtom.workspaceId,
                recovery: .saveFailed
            )
        )
    }

    private func reportRecoveryEvents(_ events: [PersistenceRecoveryEvent]) {
        for event in events {
            recoveryReporter?(event)
        }
    }

    private func persistLegacyJSONSnapshot(persistedAt: Date) -> WorkspaceStoreFlushOutcome {
        prePersistHook?()
        do {
            guard persistor.ensureDirectory() else {
                workspaceStoreLogger.error(
                    "Failed to persist workspace because the workspaces directory could not be created"
                )
                reportSaveFailed()
                return .failed("Failed to create workspaces directory")
            }
            let state = WorkspacePersistenceTransformer.makePersistableState(
                identityAtom: identityAtom,
                windowMemoryAtom: windowMemoryAtom,
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom,
                persistedAt: persistedAt
            )
            try persistor.save(state)
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return .persisted
        } catch {
            workspaceStoreLogger.error("Failed to persist workspace: \(String(reflecting: error))")
            reportSaveFailed()
            return .failed(String(describing: error))
        }
    }
}

enum WorkspaceStoreFlushOutcome: Equatable {
    case persisted
    case failed(String)

    var succeeded: Bool {
        if case .persisted = self {
            return true
        }
        return false
    }
}
