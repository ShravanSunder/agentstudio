import Foundation
import GRDB

actor WorkspaceSQLiteDatastore {
    private struct LocalRepositoryOpenResult: Sendable {
        var repository: WorkspaceLocalRepository
        var recoveryEvent: PersistenceRecoveryEvent?
    }

    private var backend: WorkspaceSQLiteStoreBackend?
    private let configuration: WorkspaceSQLiteDatastoreConfiguration?
    private let makeLocalRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let makeLocalLegacyImportDecision:
        (@Sendable (UUID, WorkspaceLocalSQLiteLegacyLane) throws -> WorkspaceLocalSQLiteLegacyImportDecision)?
    private let beforeCoreSnapshotCommit: @Sendable (WorkspaceSQLiteSnapshot) throws -> Void
    private let probe: (@Sendable (ProbeEvent) async -> Void)?
    private let traceRecorder: WorkspaceSQLiteTraceRecorder

    private var saveLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var restoreLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var pendingGlobalRecoveryEvents: [PersistenceRecoveryEvent] = []
    private var pendingRecoveryEventsByWorkspaceId: [UUID: [PersistenceRecoveryEvent]] = [:]

    init(
        configuration: WorkspaceSQLiteDatastoreConfiguration,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        beforeCoreSnapshotCommit: @escaping @Sendable (WorkspaceSQLiteSnapshot) throws -> Void = { _ in },
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = nil
        self.configuration = configuration
        self.makeLocalRepository = nil
        self.makeLocalRestoreRepository = nil
        self.makeLocalLegacyImportDecision = nil
        self.beforeCoreSnapshotCommit = beforeCoreSnapshotCommit
        self.probe = probe
        self.traceRecorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)
    }

    init(
        coreRepository: WorkspaceCoreRepository,
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil,
        makeLocalLegacyImportDecision:
            (@Sendable (UUID, WorkspaceLocalSQLiteLegacyLane) throws -> WorkspaceLocalSQLiteLegacyImportDecision)? =
            nil,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        beforeCoreSnapshotCommit: @escaping @Sendable (WorkspaceSQLiteSnapshot) throws -> Void = { _ in },
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            makeLocalRestoreRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            beforeCoreSnapshotCommit: beforeCoreSnapshotCommit
        )
        self.configuration = nil
        self.makeLocalRepository = makeLocalRepository
        self.makeLocalRestoreRepository = makeLocalRestoreRepository ?? makeLocalRepository
        self.makeLocalLegacyImportDecision = makeLocalLegacyImportDecision
        self.beforeCoreSnapshotCommit = beforeCoreSnapshotCommit
        self.probe = probe
        self.traceRecorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)
    }

    func saveWorkspaceSnapshot(_ snapshot: WorkspaceSQLiteSnapshot) async throws {
        await recordProbe(.saveWorkspaceSnapshot)
        let saveStart = RestoreTrace.nowIfEnabled()
        defer {
            RestoreTrace.logWorkspaceSaveDuration(
                workspaceId: snapshot.id,
                paneCount: snapshot.panes.count,
                tabCount: snapshot.tabs.count,
                start: saveStart
            )
        }
        var failurePhase = WorkspaceSQLiteTracePhase.openCore
        var failureDatabase: WorkspaceSQLiteTraceDatabase? = .core
        await traceRecorder.recordOperation(
            .workspaceSave,
            phase: .stageCore,
            lane: .workspace,
            outcome: .started,
            workspaceId: snapshot.id,
            database: .core
        )
        await traceRecorder.recordSnapshot(
            .init(
                snapshot: snapshot,
                operation: .workspaceSave,
                phase: .stageCore,
                outcome: .started,
                error: nil
            )
        )
        do {
            let backend = try resolvedBackend()
            let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
            failurePhase = .stageCore
            failureDatabase = .core
            try backend.replaceWorkspaceSnapshotStaged(snapshot, updatesActiveSelection: true)
            await traceRecorder.recordOperation(
                .workspaceSave,
                phase: .stageCore,
                lane: .workspace,
                outcome: .succeeded,
                workspaceId: snapshot.id,
                database: .core
            )
            failurePhase = .openLocalSave
            failureDatabase = .local
            let localRepository = try await cachedSaveLocalRepository(
                workspaceId: snapshot.id,
                operation: .workspaceSave,
                lane: .workspace
            )
            failurePhase = .writeLocal
            failureDatabase = .local
            await traceRecorder.recordOperation(
                .workspaceSave,
                phase: .writeLocal,
                lane: .workspace,
                outcome: .started,
                workspaceId: snapshot.id,
                database: .local
            )
            try backend.writeLocalSnapshot(snapshot, state: state, localRepository: localRepository)
            await traceRecorder.recordOperation(
                .workspaceSave,
                phase: .writeLocal,
                lane: .workspace,
                outcome: .succeeded,
                workspaceId: snapshot.id,
                database: .local
            )
            failurePhase = .commitCore
            failureDatabase = .core
            await traceRecorder.recordOperation(
                .workspaceSave,
                phase: .commitCore,
                lane: .workspace,
                outcome: .started,
                workspaceId: snapshot.id,
                database: .core
            )
            try backend.commitWorkspaceSnapshot(snapshot)
            await traceRecorder.recordOperation(
                .workspaceSave,
                phase: .commitCore,
                lane: .workspace,
                outcome: .succeeded,
                workspaceId: snapshot.id,
                database: .core
            )
        } catch {
            await recordWorkspaceSaveFailure(
                snapshot: snapshot,
                phase: failurePhase,
                database: failureDatabase,
                error: error
            )
            throw error
        }
    }

    private func recordWorkspaceSaveFailure(
        snapshot: WorkspaceSQLiteSnapshot,
        phase: WorkspaceSQLiteTracePhase,
        database: WorkspaceSQLiteTraceDatabase?,
        error: any Error
    ) async {
        await traceRecorder.recordSnapshot(
            .init(
                snapshot: snapshot,
                operation: .workspaceSave,
                phase: phase,
                outcome: .failed,
                error: error
            )
        )
        await traceRecorder.recordOperation(
            .workspaceSave,
            phase: phase,
            lane: .workspace,
            outcome: .failed,
            workspaceId: snapshot.id,
            database: database,
            error: error
        )
        await traceRecorder.recordRecovery(
            .init(
                recoveryKind: .saveFailed,
                operation: .workspaceSave,
                phase: phase,
                lane: .workspace,
                outcome: .failed,
                workspaceId: snapshot.id,
                database: database,
                databaseURL: nil,
                error: error
            )
        )
    }

    func loadWorkspaceSnapshot(preferredWorkspaceId: UUID) async -> LoadResult {
        await recordProbe(.loadWorkspaceSnapshot)
        await traceRecorder.recordOperation(
            .workspaceLoad,
            phase: .openCore,
            lane: .workspace,
            outcome: .started,
            workspaceId: preferredWorkspaceId,
            database: .core
        )
        do {
            let backend = try resolvedBackend()
            let recoverableStagedWorkspaceId =
                try backend.coreRepository.fetchActiveOrPreferredRecoverableStagedWorkspaceId(
                    preferredWorkspaceId: preferredWorkspaceId
                )
                ?? backend.coreRepository.fetchRecoverableStagedWorkspaceId(preferredWorkspaceId: preferredWorkspaceId)
            let load = try await backend.loadCompletedSnapshot(
                preferredWorkspaceId: preferredWorkspaceId,
                localRepositoryForWorkspaceId: { workspaceId in
                    try await self.cachedRestoreLocalRepository(
                        workspaceId: workspaceId,
                        operation: .workspaceLoad,
                        lane: .workspace
                    )
                },
                repairLocalRepositoryForWorkspaceId: { workspaceId in
                    try await self.cachedSaveLocalRepository(
                        workspaceId: workspaceId,
                        operation: .workspaceLoad,
                        lane: .workspace
                    )
                }
            )
            let snapshot = load.snapshot
            if let localStateResetSummary = load.localStateResetSummary {
                appendRecoveryEvent(
                    .init(
                        store: .workspace,
                        workspaceId: snapshot.id,
                        recovery: .localStateRebuilt,
                        localStateResetSummary: localStateResetSummary
                    ),
                    workspaceId: snapshot.id
                )
            }
            if recoverableStagedWorkspaceId == snapshot.id {
                await traceRecorder.recordRecovery(
                    .init(
                        recoveryKind: .incompleteSnapshot,
                        operation: .workspaceLoad,
                        phase: .synthesizeDefaults,
                        lane: .workspace,
                        outcome: .recovered,
                        workspaceId: snapshot.id,
                        database: nil,
                        databaseURL: nil,
                        error: nil
                    )
                )
            }
            await traceRecorder.recordOperation(
                .workspaceLoad,
                phase: .openCore,
                lane: .workspace,
                outcome: .succeeded,
                workspaceId: snapshot.id,
                database: .core
            )
            return .loaded(snapshot, recoveryEvents: drainRecoveryEvents(workspaceId: snapshot.id))
        } catch is BackendUninitializedError {
            await traceRecorder.recordOperation(
                .workspaceLoad,
                phase: .openCore,
                lane: .workspace,
                outcome: .skipped,
                workspaceId: preferredWorkspaceId,
                database: .core
            )
            return .uninitialized(recoveryEvents: drainAllRecoveryEvents())
        } catch {
            await traceRecorder.recordOperation(
                .workspaceLoad,
                phase: .openCore,
                lane: .workspace,
                outcome: .failed,
                workspaceId: preferredWorkspaceId,
                database: .core,
                error: error
            )
            return .unavailable(.init(error), recoveryEvents: drainAllRecoveryEvents())
        }
    }

    func completedSnapshotStatus(workspaceId: UUID) async -> CompletedSnapshotStatusResult {
        do {
            let backend = try resolvedBackend()
            guard
                try backend.coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) != nil
            else {
                return .completed(false, recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
            }
            let localRepository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceId,
                operation: .snapshotStatus,
                lane: .workspace
            )
            return .completed(
                try backend.hasCompletedSnapshot(workspaceId: workspaceId, localRepository: localRepository),
                recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
            )
        } catch WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(let workspaceId, _) {
            return .completed(false, recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        } catch WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(let workspaceId, _) {
            return .completed(false, recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func selectActiveWorkspace(_ workspaceId: UUID, updatedAt: Date) async throws {
        try resolvedBackend().selectActiveWorkspace(workspaceId, updatedAt: updatedAt)
    }

    func markLegacyWorkspaceCompanionImportsCompleted(workspaceId: UUID, importedAt: Date) async throws {
        try resolvedBackend().markLegacyWorkspaceCompanionImportsCompleted(
            workspaceId: workspaceId,
            importedAt: importedAt
        )
    }

    func markLegacyWorkspaceArchived(workspaceId: UUID, archivedAt: Date) async throws {
        try resolvedBackend().markLegacyWorkspaceArchived(workspaceId: workspaceId, archivedAt: archivedAt)
    }

    func saveImportedLegacySnapshot(_ snapshot: WorkspaceSQLiteSnapshot, sourceStatePath: String) async throws {
        let backend = try resolvedBackend()
        try backend.replaceWorkspaceSnapshotStaged(snapshot, updatesActiveSelection: false)
        let localRepository = try await cachedSaveLocalRepository(
            workspaceId: snapshot.id,
            operation: .legacyImport,
            lane: .legacyImport
        )
        try backend.writeImportedLegacySnapshotLocalStateAndCommit(
            snapshot,
            sourceStatePath: sourceStatePath,
            localRepository: localRepository
        )
    }

    func markLegacyWorkspaceImportFailed(
        _ snapshot: WorkspaceSQLiteSnapshot,
        sourceStatePath: String,
        error: any Error
    ) async -> LegacyImportFailureRecordOutcome {
        do {
            try resolvedBackend().markLegacyWorkspaceImportFailed(
                WorkspacePersistenceTransformer.persistableState(from: snapshot),
                sourceStatePath: sourceStatePath,
                error: error
            )
            return .recorded
        } catch {
            return .failedToRecord(.init(error))
        }
    }

    func inspectWorkspaceRows() async -> WorkspaceRowsInspectionResult {
        do {
            return try resolvedBackend().coreRepository.fetchWorkspaces().isEmpty ? .empty : .hasWorkspaceRows
        } catch {
            return .unavailable(.init(error))
        }
    }

    func inspectActiveWorkspaceSelection() async -> ActiveWorkspaceSelectionInspectionResult {
        do {
            return try resolvedBackend().coreRepository.fetchActiveWorkspaceId() == nil ? .missing : .present
        } catch {
            return .unavailable(.init(error))
        }
    }

    func legacyImportStatus(workspaceId: UUID) async -> LegacyImportStatusResult {
        do {
            guard
                let status = try resolvedBackend().coreRepository.fetchLegacyWorkspaceImportStatus(
                    workspaceId: workspaceId
                )
            else {
                return .missing
            }
            return .found(status)
        } catch {
            return .unavailable(.init(error))
        }
    }

    func localLegacyImportDecision(
        workspaceId: UUID,
        lane: WorkspaceLocalSQLiteLegacyLane
    ) async -> LocalLegacyImportDecisionResult {
        do {
            return .found(try legacyImportDecision(workspaceId: workspaceId, lane: lane))
        } catch {
            return .unavailable(.init(error))
        }
    }

    func loadRepoCacheState(workspaceId: UUID) async -> LocalCacheLoadResult {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceId,
                operation: .repoCacheLoad,
                lane: .repoCache
            )
            let cacheState = try repository.hasCacheState() ? repository.fetchCacheState() : nil
            let recentTargets = try repository.hasRecentTargetsState() ? repository.fetchRecentTargets() : nil
            let cacheDecision = try legacyImportDecision(workspaceId: workspaceId, lane: .cache)
            let recentTargetDecision = try legacyImportDecision(workspaceId: workspaceId, lane: .local)
            return .loaded(
                .init(
                    cacheState: cacheState,
                    recentTargets: recentTargets,
                    cacheLegacyDecision: cacheDecision,
                    recentTargetLegacyDecision: recentTargetDecision,
                    recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
                )
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func saveRepoCacheState(
        cacheState: WorkspaceLocalRepository.CacheStateRecord,
        recentTargets: [RecentWorkspaceTarget],
        workspaceId: UUID
    ) async throws {
        await traceRecorder.recordOperation(
            .repoCacheSave,
            phase: .writeLocal,
            lane: .repoCache,
            outcome: .started,
            workspaceId: workspaceId,
            database: .local
        )
        let repository = try await cachedSaveLocalRepository(
            workspaceId: workspaceId,
            operation: .repoCacheSave,
            lane: .repoCache
        )
        do {
            let updatedAt = Date()
            try repository.replaceCacheState(cacheState: cacheState, updatedAt: updatedAt)
            try repository.replaceRecentTargets(recentTargets, updatedAt: updatedAt)
            await traceRecorder.recordOperation(
                .repoCacheSave,
                phase: .writeLocal,
                lane: .repoCache,
                outcome: .succeeded,
                workspaceId: workspaceId,
                database: .local
            )
        } catch {
            await traceRecorder.recordOperation(
                .repoCacheSave,
                phase: .writeLocal,
                lane: .repoCache,
                outcome: .failed,
                workspaceId: workspaceId,
                database: .local,
                error: error
            )
            throw error
        }
    }

    func loadUIState(workspaceId: UUID) async -> LocalUILoadResult {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceId,
                operation: .uiStateLoad,
                lane: .uiState
            )
            let state = try repository.hasSidebarState() ? repository.fetchSidebarState() : nil
            return .loaded(
                .init(
                    state: state,
                    legacyDecision: try legacyImportDecision(workspaceId: workspaceId, lane: .local),
                    recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
                )
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func saveUIState(_ state: WorkspaceLocalRepository.SidebarStateRecord, workspaceId: UUID) async throws {
        await traceRecorder.recordOperation(
            .uiStateSave,
            phase: .writeLocal,
            lane: .uiState,
            outcome: .started,
            workspaceId: workspaceId,
            database: .local
        )
        let repository = try await cachedSaveLocalRepository(
            workspaceId: workspaceId,
            operation: .uiStateSave,
            lane: .uiState
        )
        do {
            try repository.replaceSidebarState(state, updatedAt: Date())
            await traceRecorder.recordOperation(
                .uiStateSave,
                phase: .writeLocal,
                lane: .uiState,
                outcome: .succeeded,
                workspaceId: workspaceId,
                database: .local
            )
        } catch {
            await traceRecorder.recordOperation(
                .uiStateSave,
                phase: .writeLocal,
                lane: .uiState,
                outcome: .failed,
                workspaceId: workspaceId,
                database: .local,
                error: error
            )
            throw error
        }
    }

    func loadSidebarState(workspaceId: UUID) async -> LocalSidebarLoadResult {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceId,
                operation: .sidebarLoad,
                lane: .sidebar
            )
            let expandedGroups = try repository.hasExpandedGroupsState() ? repository.fetchExpandedGroups() : nil
            return .loaded(
                .init(
                    expandedGroups: expandedGroups,
                    legacyDecision: try legacyImportDecision(workspaceId: workspaceId, lane: .local),
                    recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
                )
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func saveSidebarState(expandedGroups: Set<SidebarGroupKey>, workspaceId: UUID) async throws {
        await traceRecorder.recordOperation(
            .sidebarSave,
            phase: .writeLocal,
            lane: .sidebar,
            outcome: .started,
            workspaceId: workspaceId,
            database: .local
        )
        let repository = try await cachedSaveLocalRepository(
            workspaceId: workspaceId,
            operation: .sidebarSave,
            lane: .sidebar
        )
        do {
            try repository.replaceExpandedGroups(expandedGroups, updatedAt: Date())
            await traceRecorder.recordOperation(
                .sidebarSave,
                phase: .writeLocal,
                lane: .sidebar,
                outcome: .succeeded,
                workspaceId: workspaceId,
                database: .local
            )
        } catch {
            await traceRecorder.recordOperation(
                .sidebarSave,
                phase: .writeLocal,
                lane: .sidebar,
                outcome: .failed,
                workspaceId: workspaceId,
                database: .local,
                error: error
            )
            throw error
        }
    }

    func performLocalRestoreOperation<Output: Sendable>(
        workspaceId: UUID,
        _ operation: @Sendable (WorkspaceLocalRepository) throws -> Output
    ) async -> LocalRepositoryOperationResult<Output> {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceId,
                operation: .inboxLoad,
                lane: .inbox
            )
            return .completed(
                try operation(repository),
                recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func performLocalSaveOperation<Output: Sendable>(
        workspaceId: UUID,
        _ operation: @Sendable (WorkspaceLocalRepository) throws -> Output
    ) async throws -> Output {
        await traceRecorder.recordOperation(
            .inboxSave,
            phase: .writeLocal,
            lane: .inbox,
            outcome: .started,
            workspaceId: workspaceId,
            database: .local
        )
        let repository = try await cachedSaveLocalRepository(
            workspaceId: workspaceId,
            operation: .inboxSave,
            lane: .inbox
        )
        do {
            let output = try operation(repository)
            await traceRecorder.recordOperation(
                .inboxSave,
                phase: .writeLocal,
                lane: .inbox,
                outcome: .succeeded,
                workspaceId: workspaceId,
                database: .local
            )
            return output
        } catch {
            await traceRecorder.recordOperation(
                .inboxSave,
                phase: .writeLocal,
                lane: .inbox,
                outcome: .failed,
                workspaceId: workspaceId,
                database: .local,
                error: error
            )
            throw error
        }
    }

}

extension WorkspaceSQLiteDatastore {
    private func resolvedBackend() throws -> WorkspaceSQLiteStoreBackend {
        if let backend {
            return backend
        }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        do {
            let openedBackend = try openConfiguredBackend(configuration: configuration)
            backend = openedBackend
            return openedBackend
        } catch {
            guard WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(error) else {
                throw error
            }
        }

        let quarantine = SQLiteSidecarQuarantine.quarantine(databaseURL: configuration.coreDatabaseURL)
        appendGlobalRecoveryEvent(
            .init(
                store: .workspace,
                workspaceId: nil,
                recovery: quarantine.succeeded ? .quarantinedAndReset : .quarantineFailed,
                quarantinedFilename: quarantine.recoveryFilename
            )
        )
        guard quarantine.succeeded else {
            throw WorkspaceSQLiteDatastoreError.coreQuarantineFailed
        }
        let openedBackend = try openConfiguredBackend(configuration: configuration)
        backend = openedBackend
        return openedBackend
    }

    private func openConfiguredBackend(configuration: WorkspaceSQLiteDatastoreConfiguration) throws
        -> WorkspaceSQLiteStoreBackend
    {
        let coreDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: configuration.coreDatabaseURL,
            label: "AgentStudio.sqlite.core"
        )
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabasePool)
        try coreRepository.migrate()
        return WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            makeLocalRestoreRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            legacyImportDecision: { workspaceId, lane in
                guard
                    let status = try coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId)
                else {
                    return .allowImport
                }
                switch lane {
                case .local:
                    return status.localImportedAt == nil ? .allowImport : .blockReplayAllowArchive
                case .cache:
                    return status.cacheImportedAt == nil ? .allowImport : .blockReplayAllowArchive
                }
            },
            beforeCoreSnapshotCommit: beforeCoreSnapshotCommit
        )
    }

    private static func openConfiguredLocalRepository(
        workspaceId: UUID,
        configuration: WorkspaceSQLiteDatastoreConfiguration
    ) throws -> WorkspaceLocalRepository {
        let localDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: configuration.localDatabaseURL(workspaceId),
            label: "AgentStudio.sqlite.local.\(workspaceId.uuidString)"
        )
        let localRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localDatabasePool
        )
        try localRepository.migrate()
        return localRepository
    }

    private func cachedSaveLocalRepository(
        workspaceId: UUID,
        operation: WorkspaceSQLiteTraceOperation,
        lane: WorkspaceSQLiteTraceLane
    ) async throws -> WorkspaceLocalRepository {
        if let cachedRepository = saveLocalRepositoryCache[workspaceId] {
            return cachedRepository
        }
        let result = try makeLocalRepositoryForSave(workspaceId)
        if let recoveryEvent = result.recoveryEvent {
            appendRecoveryEvent(recoveryEvent, workspaceId: workspaceId)
            await traceRecorder.recordRecovery(
                .init(
                    recoveryKind: .localQuarantine,
                    operation: operation,
                    phase: .quarantineSidecars,
                    lane: lane,
                    outcome: .quarantined,
                    workspaceId: workspaceId,
                    database: .local,
                    databaseURL: configuration?.localDatabaseURL(workspaceId),
                    error: nil
                )
            )
        }
        saveLocalRepositoryCache[workspaceId] = result.repository
        await traceRecorder.recordOperation(
            operation,
            phase: .openLocalSave,
            lane: lane,
            outcome: .succeeded,
            workspaceId: workspaceId,
            database: .local,
            databaseURL: configuration?.localDatabaseURL(workspaceId)
        )
        await recordProbe(.localRepositoryOpened(workspaceId, .save))
        return result.repository
    }

    private func cachedRestoreLocalRepository(
        workspaceId: UUID,
        operation: WorkspaceSQLiteTraceOperation,
        lane: WorkspaceSQLiteTraceLane
    ) async throws -> WorkspaceLocalRepository {
        if let cachedRepository = restoreLocalRepositoryCache[workspaceId] {
            return cachedRepository
        }
        do {
            let result = try makeLocalRepositoryForRestore(workspaceId)
            if let recoveryEvent = result.recoveryEvent {
                appendRecoveryEvent(recoveryEvent, workspaceId: workspaceId)
                await traceRecorder.recordRecovery(
                    .init(
                        recoveryKind: .localQuarantine,
                        operation: operation,
                        phase: .quarantineSidecars,
                        lane: lane,
                        outcome: .quarantined,
                        workspaceId: workspaceId,
                        database: .local,
                        databaseURL: configuration?.localDatabaseURL(workspaceId),
                        error: nil
                    )
                )
            }
            restoreLocalRepositoryCache[workspaceId] = result.repository
            await traceRecorder.recordOperation(
                operation,
                phase: .openLocalRestore,
                lane: lane,
                outcome: .succeeded,
                workspaceId: workspaceId,
                database: .local,
                databaseURL: configuration?.localDatabaseURL(workspaceId)
            )
            await recordProbe(.localRepositoryOpened(workspaceId, .restore))
            return result.repository
        } catch WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(
            let recoveredWorkspaceId,
            let quarantinedFilename
        ) {
            appendRecoveryEvent(
                .init(
                    store: .workspace,
                    workspaceId: recoveredWorkspaceId,
                    recovery: .quarantinedAndReset,
                    quarantinedFilename: quarantinedFilename
                ),
                workspaceId: recoveredWorkspaceId
            )
            await traceRecorder.recordRecovery(
                .init(
                    recoveryKind: .localQuarantine,
                    operation: operation,
                    phase: .quarantineSidecars,
                    lane: lane,
                    outcome: .quarantined,
                    workspaceId: recoveredWorkspaceId,
                    database: .local,
                    databaseURL: configuration?.localDatabaseURL(recoveredWorkspaceId),
                    error: nil
                )
            )
            throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(
                recoveredWorkspaceId,
                quarantinedFilename: quarantinedFilename
            )
        } catch WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(
            let failedWorkspaceId,
            let quarantinedFilename
        ) {
            appendRecoveryEvent(
                .init(
                    store: .workspace,
                    workspaceId: failedWorkspaceId,
                    recovery: .quarantineFailed,
                    quarantinedFilename: quarantinedFilename
                ),
                workspaceId: failedWorkspaceId
            )
            await traceRecorder.recordRecovery(
                .init(
                    recoveryKind: .quarantineFailed,
                    operation: operation,
                    phase: .quarantineSidecars,
                    lane: lane,
                    outcome: .failed,
                    workspaceId: failedWorkspaceId,
                    database: .local,
                    databaseURL: configuration?.localDatabaseURL(failedWorkspaceId),
                    error: nil
                )
            )
            throw WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(
                failedWorkspaceId,
                quarantinedFilename: quarantinedFilename
            )
        }
    }

    private func makeLocalRepositoryForSave(_ workspaceId: UUID) throws -> LocalRepositoryOpenResult {
        if let makeLocalRepository {
            return .init(repository: try makeLocalRepository(workspaceId), recoveryEvent: nil)
        }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        return try Self.openConfiguredLocalRepositoryWithRecovery(
            workspaceId: workspaceId,
            configuration: configuration
        )
    }

    private func makeLocalRepositoryForRestore(_ workspaceId: UUID) throws -> LocalRepositoryOpenResult {
        if let makeLocalRestoreRepository {
            return .init(repository: try makeLocalRestoreRepository(workspaceId), recoveryEvent: nil)
        }
        guard let configuration else {
            return try makeLocalRepositoryForSave(workspaceId)
        }
        return try Self.openConfiguredLocalRepositoryWithRecovery(
            workspaceId: workspaceId,
            configuration: configuration
        )
    }

    private static func openConfiguredLocalRepositoryWithRecovery(
        workspaceId: UUID,
        configuration: WorkspaceSQLiteDatastoreConfiguration
    ) throws -> LocalRepositoryOpenResult {
        do {
            return .init(
                repository: try Self.openConfiguredLocalRepository(
                    workspaceId: workspaceId,
                    configuration: configuration
                ),
                recoveryEvent: nil
            )
        } catch {
            guard WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(error) else {
                throw error
            }
            let quarantine = SQLiteSidecarQuarantine.quarantine(
                databaseURL: configuration.localDatabaseURL(workspaceId)
            )
            guard quarantine.succeeded else {
                throw WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(
                    workspaceId,
                    quarantinedFilename: quarantine.recoveryFilename
                )
            }
            return .init(
                repository: try Self.openConfiguredLocalRepository(
                    workspaceId: workspaceId,
                    configuration: configuration
                ),
                recoveryEvent: .init(
                    store: .workspace,
                    workspaceId: workspaceId,
                    recovery: .quarantinedAndReset,
                    quarantinedFilename: quarantine.recoveryFilename
                )
            )
        }
    }

    private func appendRecoveryEvent(_ event: PersistenceRecoveryEvent, workspaceId: UUID) {
        pendingRecoveryEventsByWorkspaceId[workspaceId, default: []].append(event)
    }

    private func appendGlobalRecoveryEvent(_ event: PersistenceRecoveryEvent) {
        pendingGlobalRecoveryEvents.append(event)
    }

    private func drainRecoveryEvents(workspaceId: UUID) -> [PersistenceRecoveryEvent] {
        let events = pendingGlobalRecoveryEvents + (pendingRecoveryEventsByWorkspaceId[workspaceId] ?? [])
        pendingGlobalRecoveryEvents = []
        pendingRecoveryEventsByWorkspaceId[workspaceId] = nil
        return events
    }

    private func drainAllRecoveryEvents() -> [PersistenceRecoveryEvent] {
        let events = pendingGlobalRecoveryEvents + pendingRecoveryEventsByWorkspaceId.values.flatMap { $0 }
        pendingGlobalRecoveryEvents = []
        pendingRecoveryEventsByWorkspaceId.removeAll()
        return events
    }

    private func recordProbe(_ event: ProbeEvent) async {
        guard let probe else { return }
        await probe(event)
    }

    private func legacyImportDecision(
        workspaceId: UUID,
        lane: WorkspaceLocalSQLiteLegacyLane
    ) throws -> WorkspaceLocalSQLiteLegacyImportDecision {
        if let makeLocalLegacyImportDecision {
            return try makeLocalLegacyImportDecision(workspaceId, lane)
        }
        let backend = try resolvedBackend()
        return try backend.localBackend.legacyImportDecision(for: workspaceId, lane: lane)
    }
}
