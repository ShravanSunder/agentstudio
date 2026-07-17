import Foundation
import Observation
import os.log

private let workspaceStoreLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

enum WorkspaceStoreError: Error {
    case missingSQLiteSaveCoordinator
}

enum WorkspaceStoreLoadFailure: Error, Equatable, Sendable {
    case missingSQLiteDatastore
    case sqliteUnavailable(WorkspaceSQLiteDatastoreFailure)
    case defaultWorkspaceInitializationFailed(WorkspaceSQLiteDatastoreFailure)
    case defaultWorkspacePersistenceMismatch
    case compositionRejected(WorkspaceCompositionPreparationRejection)
    case compositionApplyFailed(WorkspacePreparedCompositionApplyFailure)

    var diagnosticCode: WorkspaceStartupFailureDiagnosticCode {
        switch self {
        case .missingSQLiteDatastore:
            .missingSQLiteDatastore
        case .sqliteUnavailable:
            .sqliteUnavailable
        case .defaultWorkspaceInitializationFailed:
            .defaultWorkspaceInitializationFailed
        case .defaultWorkspacePersistenceMismatch:
            .defaultWorkspacePersistenceMismatch
        case .compositionRejected:
            .compositionRejected
        case .compositionApplyFailed:
            .compositionApplyFailed
        }
    }
}

enum WorkspaceStartupFailureDiagnosticCode: String, Equatable, Sendable {
    case missingSQLiteDatastore = "missing_sqlite_datastore"
    case sqliteUnavailable = "sqlite_unavailable"
    case defaultWorkspaceInitializationFailed = "default_workspace_initialization_failed"
    case defaultWorkspacePersistenceMismatch = "default_workspace_persistence_mismatch"
    case compositionRejected = "composition_rejected"
    case compositionApplyFailed = "composition_apply_failed"
}

enum WorkspaceStoreLoadResult: Equatable, Sendable {
    case loaded(WorkspacePreparedCompositionAcceptance)
    case initializedDefaultWorkspace(WorkspacePreparedCompositionAcceptance)
    case failed(WorkspaceStoreLoadFailure)
}

/// Main-actor persistence aggregate for the workspace atoms.
///
/// This type owns canonical SQLite composition loading, debounced persistence,
/// and flushing. Workspace-domain
/// mutations live on the owning atoms or `WorkspaceMutationCoordinator`.
@MainActor
final class WorkspaceStore {
    let workspacePersistenceRuntime: WorkspacePersistenceRuntime
    let workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner
    let identityAtom: WorkspaceIdentityAtom
    let windowMemoryAtom: WorkspaceWindowMemoryAtom
    let repositoryTopologyAtom: RepositoryTopologyAtom
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

    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let sqliteSaveCoordinator: WorkspaceSQLiteSaveCoordinator?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var debouncedSaveFailureDamping = DebouncedSaveFailureDamping()
    private var isObservingPersistedState = false
    private var isApplyingInitialComposition = false
    private(set) var isDirty: Bool = false

    var isAutosaveObservationActive: Bool {
        isObservingPersistedState
    }

    init(
        workspacePersistenceRuntime: WorkspacePersistenceRuntime,
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        paneAtom: WorkspacePaneAtom,
        tabLayoutAtom: WorkspaceTabLayoutAtom,
        mutationCoordinator: WorkspaceMutationCoordinator,
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        sqliteSaveCoordinator: WorkspaceSQLiteSaveCoordinator? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        let resolvedTabShellAtom = tabLayoutAtom.shellAtom
        let resolvedTabArrangementAtom = tabLayoutAtom.arrangementAtom
        let resolvedPaneAtom = paneAtom
        workspacePersistenceRuntime.requireExactAtomOwners(
            WorkspacePersistenceAtomOwners(
                workspaceIdentity: identityAtom,
                workspaceWindowMemory: windowMemoryAtom,
                repositoryTopology: repositoryTopologyAtom,
                workspacePaneGraph: resolvedPaneAtom.graphAtom,
                workspaceDrawerCursor: resolvedPaneAtom.drawerCursorAtom,
                workspaceTabShell: resolvedTabShellAtom,
                workspaceTabCursor: resolvedTabShellAtom.cursorAtom,
                workspaceTabGraph: resolvedTabArrangementAtom.graphAtom,
                workspaceArrangementCursor: resolvedTabArrangementAtom.cursorAtom
            )
        )
        workspacePersistenceRuntime.requireExactPresentationOwner(
            resolvedTabArrangementAtom.presentationAtom
        )
        self.workspacePersistenceRuntime = workspacePersistenceRuntime
        workspacePersistenceRevisionOwner = workspacePersistenceRuntime.revisionOwner
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
        self.tabLayoutAtom = tabLayoutAtom
        self.mutationCoordinator = mutationCoordinator
        let resolvedSQLiteSaveCoordinator =
            sqliteSaveCoordinator
            ?? sqliteDatastore.map { datastore in
                WorkspaceSQLiteSaveCoordinator(
                    identityAtom: identityAtom,
                    windowMemoryAtom: windowMemoryAtom,
                    repositoryTopologyAtom: repositoryTopologyAtom,
                    workspacePaneAtom: resolvedPaneAtom,
                    workspaceTabLayoutAtom: tabLayoutAtom,
                    sqliteDatastore: datastore
                )
            }
        self.sqliteDatastore = sqliteDatastore
        self.sqliteSaveCoordinator = resolvedSQLiteSaveCoordinator
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.recoveryReporter = recoveryReporter
    }

    typealias CloseEntry = WorkspaceMutationCoordinator.CloseEntry
    typealias TabCloseSnapshot = WorkspaceMutationCoordinator.TabCloseSnapshot
    typealias PaneCloseSnapshot = WorkspaceMutationCoordinator.PaneCloseSnapshot
    typealias CloseSnapshot = TabCloseSnapshot

    // MARK: - Persistence

    func loadCanonicalComposition() async -> WorkspaceStoreLoadResult {
        guard let sqliteDatastore else {
            return .failed(.missingSQLiteDatastore)
        }

        switch await sqliteDatastore.loadWorkspaceSnapshot() {
        case .loaded(let snapshot):
            switch await prepareAndApplyComposition(snapshot) {
            case .success(let acceptance):
                return .loaded(acceptance)
            case .failure(let failure):
                return .failed(failure)
            }
        case .uninitialized:
            return await initializeAndApplyDefaultWorkspace(using: sqliteDatastore)
        case .unavailable(let failure):
            return .failed(.sqliteUnavailable(failure))
        }
    }

    private func initializeAndApplyDefaultWorkspace(
        using sqliteDatastore: WorkspaceSQLiteDatastore
    ) async -> WorkspaceStoreLoadResult {
        let persistedAt = Date()
        let workspaceSnapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Default Workspace",
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: persistedAt,
            updatedAt: persistedAt
        )
        let saveBundle = WorkspaceSQLiteSaveBundle(
            workspace: workspaceSnapshot,
            repositoryTopology: RepositoryTopologySQLiteSnapshot(
                id: workspaceSnapshot.id,
                updatedAt: persistedAt
            )
        )
        do {
            try await sqliteDatastore.saveWorkspaceSnapshotBundle(saveBundle)
        } catch {
            return .failed(.defaultWorkspaceInitializationFailed(.init(error)))
        }

        let persistedSnapshot: WorkspaceSQLiteSnapshot
        switch await sqliteDatastore.loadWorkspaceSnapshot() {
        case .loaded(let snapshot):
            guard snapshot.hasSameSQLiteRepresentation(as: workspaceSnapshot) else {
                return .failed(.defaultWorkspacePersistenceMismatch)
            }
            persistedSnapshot = snapshot
        case .uninitialized:
            return .failed(.defaultWorkspacePersistenceMismatch)
        case .unavailable(let failure):
            return .failed(.defaultWorkspaceInitializationFailed(failure))
        }

        switch await prepareAndApplyComposition(persistedSnapshot) {
        case .success(let acceptance):
            return .initializedDefaultWorkspace(acceptance)
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private func prepareAndApplyComposition(
        _ snapshot: WorkspaceSQLiteSnapshot
    ) async -> Result<WorkspacePreparedCompositionAcceptance, WorkspaceStoreLoadFailure> {
        let preparation = await WorkspaceCompositionPreparer.prepareOffMain(snapshot)
        let preparedComposition: PreparedWorkspaceComposition
        switch preparation {
        case .prepared(let prepared):
            preparedComposition = prepared
        case .rejected(let rejection):
            return .failure(.compositionRejected(rejection))
        }

        isApplyingInitialComposition = true
        defer { isApplyingInitialComposition = false }
        switch workspacePersistenceRuntime.preparedCompositionApplier.apply(preparedComposition) {
        case .accepted(let acceptance):
            workspaceStoreLogger.info(
                "Installed SQLite workspace '\(preparedComposition.identity.workspaceName)' with \(preparedComposition.panes.count) pane(s), \(preparedComposition.tabs.count) tab(s)"
            )
            return .success(acceptance)
        case .failed(let failure):
            return .failure(.compositionApplyFailed(failure))
        }
    }

    @discardableResult
    func flushAsync() async -> WorkspaceStoreFlushOutcome {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        let outcome = await persistNow()
        clearDebouncedSaveFailureDampingIfSucceeded(outcome)
        return outcome
    }

    var prePersistHook: (() -> Void)?

    func startObserving() {
        guard !isObservingPersistedState else { return }
        isObservingPersistedState = true
        withObservationTracking {
            _ = identityAtom.workspaceId
            _ = identityAtom.workspaceName
            _ = identityAtom.createdAt
            _ = windowMemoryAtom.sidebarWidth
            _ = windowMemoryAtom.windowFrame
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
                let shouldIgnore = self.isApplyingInitialComposition
                self.isObservingPersistedState = false
                self.startObserving()
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
            await self.persistDebouncedAutosave()
        }
    }

    private func persistDebouncedAutosave() async {
        let shouldReportFailure = !debouncedSaveFailureDamping.shouldDampNextDebouncedFailureReport
        if !shouldReportFailure {
            workspaceStoreLogger.warning(
                "Damping repeated workspace autosave failure report after \(self.debouncedSaveFailureDamping.consecutiveFailureCount) identical failure(s); autosave will still retry"
            )
        }
        let outcome = await persistNow(shouldReportSaveFailure: shouldReportFailure)
        debouncedSaveFailureDamping.record(outcome)
    }

    @discardableResult
    private func persistNow(shouldReportSaveFailure: Bool = true) async -> WorkspaceStoreFlushOutcome {
        let persistedAt = Date()
        do {
            prePersistHook?()
            guard sqliteDatastore != nil, let sqliteSaveCoordinator else {
                throw WorkspaceStoreError.missingSQLiteSaveCoordinator
            }
            _ = try await sqliteSaveCoordinator.save(persistedAt: persistedAt)
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return .persisted
        } catch {
            workspaceStoreLogger.error("Failed to persist workspace: \(String(reflecting: error))")
            if shouldReportSaveFailure {
                reportSaveFailed()
            }
            return .failed(String(describing: error))
        }
    }

    private func clearDebouncedSaveFailureDampingIfSucceeded(_ outcome: WorkspaceStoreFlushOutcome) {
        guard outcome.succeeded else { return }
        debouncedSaveFailureDamping.reset()
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

private struct DebouncedSaveFailureDamping {
    private var failureSummary: String?
    private(set) var consecutiveFailureCount: Int = 0

    var shouldDampNextDebouncedFailureReport: Bool {
        consecutiveFailureCount >= AppPolicies.WorkspacePersistence.debouncedAutosaveFailureDampingThreshold
    }

    mutating func record(_ outcome: WorkspaceStoreFlushOutcome) {
        switch outcome {
        case .persisted:
            reset()
        case .failed(let summary):
            if failureSummary == summary {
                consecutiveFailureCount += 1
            } else {
                failureSummary = summary
                consecutiveFailureCount = 1
            }
        }
    }

    mutating func reset() {
        failureSummary = nil
        consecutiveFailureCount = 0
    }
}
