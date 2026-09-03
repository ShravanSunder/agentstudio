import AgentStudioInfrastructure
import Foundation
import Observation
import os.log

private let workspaceStoreLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

enum WorkspaceStoreError: Error {
    case missingSQLiteSaveCoordinator
}

package enum WorkspaceStoreLoadFailure: Error, Equatable, Sendable {
    case missingSQLiteDatastore
    case sqliteUnavailable(WorkspaceSQLiteDatastoreFailure)
    case defaultWorkspaceInitializationFailed(WorkspaceSQLiteDatastoreFailure)
    case defaultWorkspacePersistenceMismatch
    case compositionRejected(WorkspaceCompositionPreparationRejection)
    case compositionApplyFailed(WorkspacePreparedCompositionApplyFailure)
    case topologyRejected(RepositoryTopologyIdentityRejection)

    package var diagnosticCode: WorkspaceStartupFailureDiagnosticCode {
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
        case .topologyRejected:
            .topologyRejected
        }
    }
}

package enum WorkspaceStartupFailureDiagnosticCode: String, Equatable, Sendable {
    case missingSQLiteDatastore = "missing_sqlite_datastore"
    case sqliteUnavailable = "sqlite_unavailable"
    case defaultWorkspaceInitializationFailed = "default_workspace_initialization_failed"
    case defaultWorkspacePersistenceMismatch = "default_workspace_persistence_mismatch"
    case compositionRejected = "composition_rejected"
    case compositionApplyFailed = "composition_apply_failed"
    case topologyRejected = "topology_rejected"
}

package enum WorkspaceStoreLoadResult: Equatable, Sendable {
    case loaded(WorkspacePreparedCompositionAcceptance)
    case initializedDefaultWorkspace(WorkspacePreparedCompositionAcceptance)
    case failed(WorkspaceStoreLoadFailure)
}

package typealias PaneAssociationBootReconciliationReporter =
    @MainActor @Sendable (PaneAssociationBootReconciliationSummary) -> Void

/// Main-actor persistence aggregate for the workspace atoms.
///
/// This type owns canonical SQLite composition loading, debounced persistence,
/// and flushing. Workspace-domain
/// mutations live on the owning atoms or `WorkspaceMutationCoordinator`.
@MainActor
package final class WorkspaceStore {
    package let identityAtom: WorkspaceIdentityAtom
    package let windowMemoryAtom: WorkspaceWindowMemoryAtom
    package let repositoryTopologyAtom: RepositoryTopologyAtom
    let paneGraphAtom: WorkspacePaneGraphAtom
    let drawerCursorAtom: WorkspaceDrawerCursorAtom
    package let paneAtom: WorkspacePaneAtom
    package let tabShellAtom: WorkspaceTabShellAtom
    let tabCursorAtom: WorkspaceTabCursorAtom
    let tabGraphAtom: WorkspaceTabGraphAtom
    let arrangementCursorAtom: WorkspaceArrangementCursorAtom
    package let panePresentationAtom: WorkspacePanePresentationAtom
    package let tabArrangementAtom: WorkspaceTabArrangementAtom
    package let tabLayoutAtom: WorkspaceTabLayoutAtom
    package let mutationCoordinator: WorkspaceMutationCoordinator

    private let sqliteDatastore: WorkspaceSQLiteDatastoreActor?
    private let sqliteSaveCoordinator: WorkspaceSQLiteSaveCoordinator?
    private let preparedCompositionApplier: WorkspacePreparedCompositionApplier
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    let recoveryReporter: PersistenceRecoveryReporter?
    private let paneAssociationBootReconciliationReporter: PaneAssociationBootReconciliationReporter?
    private let persistenceReasonReporter: PaneTopologyPersistenceReasonReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var debouncedSaveFailureDamping = DebouncedSaveFailureDamping()
    private var isObservingPersistedState = false
    private var isApplyingInitialComposition = false
    private(set) var isDirty: Bool = false

    package var isAutosaveObservationActive: Bool {
        isObservingPersistedState
    }

    package init(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        paneAtom: WorkspacePaneAtom,
        tabLayoutAtom: WorkspaceTabLayoutAtom,
        mutationCoordinator: WorkspaceMutationCoordinator,
        sqliteDatastore: WorkspaceSQLiteDatastoreActor? = nil,
        sqliteSaveCoordinator: WorkspaceSQLiteSaveCoordinator? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil,
        paneAssociationBootReconciliationReporter: PaneAssociationBootReconciliationReporter? = nil,
        persistenceReasonReporter: PaneTopologyPersistenceReasonReporter? = nil
    ) {
        let resolvedTabShellAtom = tabLayoutAtom.shellAtom
        let resolvedTabArrangementAtom = tabLayoutAtom.arrangementAtom
        let resolvedPaneAtom = paneAtom
        preparedCompositionApplier = WorkspacePreparedCompositionApplier(
            owners: WorkspacePreparedCompositionOwners(
                workspaceIdentityAtom: identityAtom,
                workspaceWindowMemoryAtom: windowMemoryAtom,
                workspacePaneGraphAtom: resolvedPaneAtom.graphAtom,
                workspaceDrawerCursorAtom: resolvedPaneAtom.drawerCursorAtom,
                workspaceTabShellAtom: resolvedTabShellAtom,
                workspaceTabCursorAtom: resolvedTabShellAtom.cursorAtom,
                workspaceTabGraphAtom: resolvedTabArrangementAtom.graphAtom,
                workspaceArrangementCursorAtom: resolvedTabArrangementAtom.cursorAtom
            )
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
        self.tabLayoutAtom = tabLayoutAtom
        self.mutationCoordinator = mutationCoordinator
        let resolvedSQLiteSaveCoordinator =
            sqliteSaveCoordinator
            ?? sqliteDatastore.map { datastore in
                WorkspaceSQLiteSaveCoordinator(
                    identityAtom: identityAtom,
                    windowMemoryAtom: windowMemoryAtom,
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
        self.paneAssociationBootReconciliationReporter = paneAssociationBootReconciliationReporter
        self.persistenceReasonReporter = persistenceReasonReporter
    }

    typealias CloseEntry = WorkspaceMutationCoordinator.CloseEntry
    typealias TabCloseSnapshot = WorkspaceMutationCoordinator.TabCloseSnapshot
    typealias PaneCloseSnapshot = WorkspaceMutationCoordinator.PaneCloseSnapshot
    typealias CloseSnapshot = TabCloseSnapshot

    // MARK: - Persistence

    package func loadCanonicalComposition() async -> WorkspaceStoreLoadResult {
        guard let sqliteDatastore else {
            return .failed(.missingSQLiteDatastore)
        }

        switch await sqliteDatastore.loadAuthoritativeCoreSnapshot() {
        case .loaded(let snapshot):
            let restoreReasons = snapshot.persistenceReasons.union(
                WorkspacePersistenceTransformer.topologyRestoreReasons(snapshot.repositoryTopology)
            )
            for reason in restoreReasons {
                persistenceReasonReporter?(reason)
            }
            switch await prepareAndApplyAuthoritativeSnapshot(snapshot) {
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
        using sqliteDatastore: WorkspaceSQLiteDatastoreActor
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
        let saveBundle = WorkspaceSQLiteSaveBundle(workspace: workspaceSnapshot)
        do {
            try await sqliteDatastore.saveWorkspaceSnapshotBundle(saveBundle)
        } catch {
            return .failed(.defaultWorkspaceInitializationFailed(.init(error)))
        }

        let persistedSnapshot: WorkspaceCoreLoadSnapshot
        switch await sqliteDatastore.loadAuthoritativeCoreSnapshot() {
        case .loaded(let snapshot):
            guard snapshot.workspace.hasSameSQLiteRepresentation(as: workspaceSnapshot) else {
                return .failed(.defaultWorkspacePersistenceMismatch)
            }
            persistedSnapshot = snapshot
        case .uninitialized:
            return .failed(.defaultWorkspacePersistenceMismatch)
        case .unavailable(let failure):
            return .failed(.defaultWorkspaceInitializationFailed(failure))
        }

        switch await prepareAndApplyAuthoritativeSnapshot(persistedSnapshot) {
        case .success(let acceptance):
            return .initializedDefaultWorkspace(acceptance)
        case .failure(let failure):
            return .failed(failure)
        }
    }

    private func prepareAndApplyAuthoritativeSnapshot(
        _ snapshot: WorkspaceCoreLoadSnapshot
    ) async -> Result<WorkspacePreparedCompositionAcceptance, WorkspaceStoreLoadFailure> {
        let topologyPreparation = await WorkspacePersistenceTransformer.prepareRepositoryTopologyOffMain(
            snapshot.repositoryTopology
        )

        let preparedTopology: RepositoryTopologyReplacement
        switch topologyPreparation {
        case .prepared(let replacement):
            preparedTopology = replacement
        case .rejected(let rejection):
            return .failure(.topologyRejected(rejection))
        }

        let associationReconciliation = await WorkspacePersistenceTransformer.reconcilePaneAssociationsOffMain(
            in: snapshot.workspace,
            topology: preparedTopology
        )
        let didRepairAssociations = associationReconciliation.summary.changedCount > 0

        let preparedComposition: PreparedWorkspaceComposition
        switch await WorkspaceCompositionPreparer.prepareOffMain(associationReconciliation.workspace) {
        case .prepared(let prepared):
            preparedComposition = prepared
        case .rejected(let rejection):
            return .failure(.compositionRejected(rejection))
        }

        isApplyingInitialComposition = true
        defer { isApplyingInitialComposition = false }
        switch preparedCompositionApplier.apply(preparedComposition) {
        case .accepted(let acceptance):
            WorkspacePersistenceTransformer.applyPreparedRepositoryTopology(
                preparedTopology,
                repositoryTopologyAtom: repositoryTopologyAtom
            )
            _ = mutationCoordinator.restoreOrphanedPaneResidencyForCurrentTopology()
            paneAssociationBootReconciliationReporter?(associationReconciliation.summary)
            isDirty = false
            if didRepairAssociations {
                _ = await persistNow()
            }
            workspaceStoreLogger.info(
                "Installed SQLite workspace '\(preparedComposition.identity.workspaceName)' with \(preparedComposition.panes.count) pane(s), \(preparedComposition.tabs.count) tab(s)"
            )
            return .success(acceptance)
        case .failed(let failure):
            return .failure(.compositionApplyFailed(failure))
        }
    }

    @discardableResult
    package func flushAsync() async -> WorkspaceStoreFlushOutcome {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        let outcome = await persistNow()
        clearDebouncedSaveFailureDampingIfSucceeded(outcome)
        return outcome
    }

    private var prePersistHook: (() -> Void)?

    package func setPrePersistHook(_ hook: @escaping () -> Void) {
        prePersistHook = hook
    }

    package func startObserving() {
        guard !isObservingPersistedState else { return }
        isObservingPersistedState = true
        withObservationTracking {
            _ = identityAtom.workspaceId
            _ = identityAtom.workspaceName
            _ = identityAtom.createdAt
            _ = windowMemoryAtom.sidebarWidth
            _ = windowMemoryAtom.windowFrame
            _ = paneGraphAtom.paneAcceptedCommitRevision
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
            persistenceReasonReporter?(Self.persistenceFailureReason(for: error))
            if shouldReportSaveFailure {
                reportSaveFailed()
            }
            return .failed(String(describing: error))
        }
    }

    package static func persistenceFailureReason(
        for error: any Error
    ) -> PaneTopologyPersistenceReason {
        guard let failure = error as? WorkspaceSQLiteSaveCoordinatorFailure else {
            return .workspaceSaveDatabaseFailed
        }
        switch failure {
        case .compositionRejected:
            return .workspaceSaveCompositionRejected
        case .datastore(let datastoreFailure):
            return datastoreFailure.kind == .stateBridge
                ? .workspaceSaveBridgeFailed
                : .workspaceSaveDatabaseFailed
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

package enum WorkspaceStoreFlushOutcome: Equatable {
    case persisted
    case failed(String)

    package var succeeded: Bool {
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
