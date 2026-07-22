import Foundation
import GRDB

actor WorkspaceSQLiteDatastore {
    private struct LocalRepositoryOpenResult: Sendable {
        var repository: WorkspaceLocalRepository
        var recoveryEvent: PersistenceRecoveryEvent?
    }

    private var backend: WorkspaceSQLiteStoreBackend?
    private var configuredLocalDatabaseWriter: (any DatabaseWriter)?
    private let configuration: WorkspaceSQLiteDatastoreConfiguration?
    private let makeLocalRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let probe: (@Sendable (ProbeEvent) async -> Void)?
    private let traceRecorder: WorkspaceSQLiteTraceRecorder

    private var saveLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var restoreLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var pendingGlobalRecoveryEvents: [PersistenceRecoveryEvent] = []
    private var pendingRecoveryEventsByWorkspaceId: [UUID: [PersistenceRecoveryEvent]] = [:]
    private var workspaceSaveTail: Task<Void, Error>?
    private var workspaceSaveTailGeneration: UInt64 = 0

    init(
        configuration: WorkspaceSQLiteDatastoreConfiguration,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = nil
        self.configuredLocalDatabaseWriter = nil
        self.configuration = configuration
        self.makeLocalRepository = nil
        self.makeLocalRestoreRepository = nil
        self.probe = probe
        self.traceRecorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)
    }

    init(
        coreRepository: WorkspaceCoreRepository,
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil,
        traceRuntime: AgentStudioTraceRuntime? = nil,
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            makeLocalRestoreRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            coreDatabaseStartupProvenance: .preexisting
        )
        self.configuration = nil
        self.configuredLocalDatabaseWriter = nil
        self.makeLocalRepository = makeLocalRepository
        self.makeLocalRestoreRepository = makeLocalRestoreRepository ?? makeLocalRepository
        self.probe = probe
        self.traceRecorder = WorkspaceSQLiteTraceRecorder(traceRuntime: traceRuntime)
    }

    func saveWorkspaceSnapshotBundle(_ bundle: WorkspaceSQLiteSaveBundle) async throws {
        let previousTail = workspaceSaveTail
        workspaceSaveTailGeneration &+= 1
        let tailGeneration = workspaceSaveTailGeneration
        let saveTask = Task { [self] in
            if let previousTail {
                do {
                    try await previousTail.value
                } catch {
                    // Preserve save ordering without letting one failed flush poison the next queued save.
                }
            }
            try await performWorkspaceSnapshotBundleSave(bundle)
        }
        workspaceSaveTail = saveTask
        do {
            try await saveTask.value
            if workspaceSaveTailGeneration == tailGeneration {
                workspaceSaveTail = nil
            }
        } catch {
            if workspaceSaveTailGeneration == tailGeneration {
                workspaceSaveTail = nil
            }
            throw error
        }
    }

    private func performWorkspaceSnapshotBundleSave(_ bundle: WorkspaceSQLiteSaveBundle) async throws {
        let snapshot = bundle.workspace
        await recordProbe(.saveWorkspaceSnapshot)
        var failurePhase = WorkspaceSQLiteTracePhase.openCore
        var failureDatabase: WorkspaceSQLiteTraceDatabase? = .core
        await traceRecorder.recordOperation(
            .workspaceSave,
            phase: .commitCore,
            lane: .workspace,
            outcome: .started,
            workspaceId: snapshot.id,
            database: .core
        )
        await traceRecorder.recordSnapshot(
            .init(
                snapshot: snapshot,
                operation: .workspaceSave,
                phase: .commitCore,
                outcome: .started,
                error: nil
            )
        )
        do {
            let backend = try resolvedBackend()
            failurePhase = .commitCore
            failureDatabase = .core
            try backend.replaceWorkspaceSnapshot(bundle, updatesActiveSelection: true)
            await traceRecorder.recordOperation(
                .workspaceSave,
                phase: .commitCore,
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
            try backend.writeLocalSnapshot(snapshot, localRepository: localRepository)
            await traceRecorder.recordOperation(
                .workspaceSave,
                phase: .writeLocal,
                lane: .workspace,
                outcome: .succeeded,
                workspaceId: snapshot.id,
                database: .local
            )
            await recordProbe(.saveWorkspaceSnapshotSucceeded)
        } catch {
            await recordWorkspaceSaveFailure(
                snapshot: snapshot,
                phase: failurePhase,
                database: failureDatabase,
                error: error
            )
            await recordProbe(.saveWorkspaceSnapshotFailed)
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

    func loadWorkspaceSnapshot() async -> LoadResult {
        switch await loadAuthoritativeCoreSnapshot() {
        case .loaded(let snapshot):
            return .loaded(snapshot.workspace)
        case .uninitialized:
            return .uninitialized
        case .unavailable(let failure):
            return .unavailable(failure)
        }
    }

    func loadAuthoritativeCoreSnapshot() async -> CoreLoadResult {
        await recordProbe(.loadWorkspaceSnapshot)
        await traceRecorder.recordOperation(
            .workspaceLoad,
            phase: .openCore,
            lane: .workspace,
            outcome: .started,
            workspaceId: nil,
            database: .core
        )
        do {
            let backend = try resolvedBackendForWorkspaceStartup()
            let snapshot = try await backend.loadCompletedSnapshot(
                localRepositoryForWorkspaceId: { workspaceId in
                    try await self.cachedRestoreLocalRepository(
                        workspaceId: workspaceId,
                        operation: .workspaceLoad,
                        lane: .workspace
                    )
                }
            )
            await traceRecorder.recordOperation(
                .workspaceLoad,
                phase: .openCore,
                lane: .workspace,
                outcome: .succeeded,
                workspaceId: snapshot.workspace.id,
                database: .core
            )
            return .loaded(snapshot)
        } catch is BackendUninitializedError {
            await traceRecorder.recordOperation(
                .workspaceLoad,
                phase: .openCore,
                lane: .workspace,
                outcome: .skipped,
                workspaceId: nil,
                database: .core
            )
            return .uninitialized
        } catch {
            await traceRecorder.recordOperation(
                .workspaceLoad,
                phase: .openCore,
                lane: .workspace,
                outcome: .failed,
                workspaceId: nil,
                database: .core,
                error: error
            )
            return .unavailable(.init(error))
        }
    }

    func loadRepositoryTopologySnapshot() async -> RepositoryTopologyLoadResult {
        do {
            let backend = try resolvedBackend()
            return .loaded(try backend.fetchRepositoryTopologySnapshot())
        } catch is BackendUninitializedError {
            return .uninitialized
        } catch {
            return .unavailable(.init(error))
        }
    }

    func saveRepositoryTopologySnapshot(_ snapshot: RepositoryTopologySQLiteSnapshot) async throws {
        try resolvedBackend().replaceRepositoryTopologySnapshot(snapshot)
    }

    func selectActiveWorkspace(_ workspaceId: UUID, updatedAt: Date) async throws {
        try resolvedBackend().selectActiveWorkspace(workspaceId, updatedAt: updatedAt)
    }

    func loadRepoCacheState(workspaceId: UUID) async -> LocalCacheLoadResult {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceId,
                operation: .repoCacheLoad,
                lane: .repoCache
            )
            let cacheState = try repository.fetchCacheState()
            let recentTargets = try repository.fetchRecentTargets()
            return .loaded(
                .init(
                    cacheState: cacheState,
                    recentTargets: recentTargets,
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

    func loadUIState(workspaceContextId: UUID) async -> LocalUILoadResult {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceContextId,
                operation: .uiStateLoad,
                lane: .uiState
            )
            let state = try repository.hasSidebarState() ? repository.fetchSidebarState() : nil
            return .loaded(
                .init(
                    state: state,
                    recoveryEvents: drainRecoveryEvents(workspaceId: workspaceContextId)
                )
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainAllRecoveryEvents())
        }
    }

    func saveUIState(
        _ state: WorkspaceLocalRepository.SidebarStateRecord,
        workspaceContextId: UUID
    ) async throws {
        await traceRecorder.recordOperation(
            .uiStateSave,
            phase: .writeLocal,
            lane: .uiState,
            outcome: .started,
            workspaceId: workspaceContextId,
            database: .local
        )
        let repository = try await cachedSaveLocalRepository(
            workspaceId: workspaceContextId,
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
                workspaceId: workspaceContextId,
                database: .local
            )
        } catch {
            await traceRecorder.recordOperation(
                .uiStateSave,
                phase: .writeLocal,
                lane: .uiState,
                outcome: .failed,
                workspaceId: workspaceContextId,
                database: .local,
                error: error
            )
            throw error
        }
    }

    func loadSidebarState(workspaceContextId: UUID) async -> LocalSidebarLoadResult {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceContextId,
                operation: .sidebarLoad,
                lane: .sidebar
            )
            let expandedGroups = try repository.fetchExpandedGroups()
            return .loaded(
                .init(
                    expandedGroups: expandedGroups,
                    recoveryEvents: drainRecoveryEvents(workspaceId: workspaceContextId)
                )
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainAllRecoveryEvents())
        }
    }

    func saveSidebarState(
        expandedGroups: Set<SidebarGroupKey>,
        workspaceContextId: UUID
    ) async throws {
        await traceRecorder.recordOperation(
            .sidebarSave,
            phase: .writeLocal,
            lane: .sidebar,
            outcome: .started,
            workspaceId: workspaceContextId,
            database: .local
        )
        let repository = try await cachedSaveLocalRepository(
            workspaceId: workspaceContextId,
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
                workspaceId: workspaceContextId,
                database: .local
            )
        } catch {
            await traceRecorder.recordOperation(
                .sidebarSave,
                phase: .writeLocal,
                lane: .sidebar,
                outcome: .failed,
                workspaceId: workspaceContextId,
                database: .local,
                error: error
            )
            throw error
        }
    }

    func loadWorkspaceSettings(workspaceId: UUID) async -> LocalSettingsLoadResult {
        do {
            let repository = try await cachedRestoreLocalRepository(
                workspaceId: workspaceId,
                operation: .uiStateLoad,
                lane: .uiState
            )
            return .loaded(
                .init(
                    editor: try repository.fetchEditorPreferences(),
                    repoExplorer: try repository.fetchRepoExplorerPreferences(),
                    inboxNotification: try repository.fetchInboxNotificationPreferences(),
                    recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
                )
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func saveWorkspaceSettings(
        editor: WorkspaceLocalRepository.EditorPreferencesRecord,
        repoExplorer: WorkspaceLocalRepository.RepoExplorerPreferencesRecord,
        inboxNotification: WorkspaceLocalRepository.InboxNotificationPreferencesRecord,
        workspaceId: UUID
    ) async throws {
        let repository = try await cachedSaveLocalRepository(
            workspaceId: workspaceId,
            operation: .uiStateSave,
            lane: .uiState
        )
        let updatedAt = Date()
        try repository.replaceEditorPreferences(editor, updatedAt: updatedAt)
        try repository.replaceRepoExplorerPreferences(repoExplorer, updatedAt: updatedAt)
        try repository.replaceInboxNotificationPreferences(inboxNotification, updatedAt: updatedAt)
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
    private func resolvedBackendForWorkspaceStartup() throws -> WorkspaceSQLiteStoreBackend {
        if let backend {
            return backend
        }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        guard FileManager.default.fileExists(atPath: configuration.coreDatabaseURL.path) else {
            let openedBackend = try openConfiguredBackend(configuration: configuration)
            backend = openedBackend
            return openedBackend
        }

        try WorkspaceSQLiteStartupSchemaPreparer.migratePreexistingDatabaseIfRequired(
            at: configuration.coreDatabaseURL,
            label: "AgentStudio.sqlite.core.startup-schema-check",
            migrator: WorkspaceCoreMigrations.migrator
        )
        let coreStartupReader = try SQLiteDatabaseFactory.makeBytePreservingStartupReader(
            at: configuration.coreDatabaseURL,
            label: "AgentStudio.sqlite.core.startup-read"
        )
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreStartupReader)
        return WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            makeLocalRestoreRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            coreDatabaseStartupProvenance: .preexisting
        )
    }

    private func resolvedBackend() throws -> WorkspaceSQLiteStoreBackend {
        if let backend {
            return backend
        }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        let openedBackend = try openConfiguredBackend(configuration: configuration)
        backend = openedBackend
        return openedBackend
    }

    private func openConfiguredBackend(
        configuration: WorkspaceSQLiteDatastoreConfiguration
    ) throws
        -> WorkspaceSQLiteStoreBackend
    {
        let coreDatabaseStartupProvenance: WorkspaceSQLiteStoreBackend.CoreDatabaseStartupProvenance =
            FileManager.default.fileExists(atPath: configuration.coreDatabaseURL.path)
            ? .preexisting
            : .createdDuringCurrentStartup
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
            coreDatabaseStartupProvenance: coreDatabaseStartupProvenance
        )
    }

    private static func openConfiguredLocalRepository(
        workspaceId: UUID,
        configuration: WorkspaceSQLiteDatastoreConfiguration
    ) throws -> WorkspaceLocalRepository {
        let localDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: configuration.localDatabaseURL,
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
                    databaseURL: configuration?.localDatabaseURL,
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
            databaseURL: configuration?.localDatabaseURL
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
                        databaseURL: configuration?.localDatabaseURL,
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
                databaseURL: configuration?.localDatabaseURL
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
                    databaseURL: configuration?.localDatabaseURL,
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
                    databaseURL: configuration?.localDatabaseURL,
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
        if let configuredLocalDatabaseWriter {
            return .init(
                repository: WorkspaceLocalRepository(
                    workspaceId: workspaceId,
                    databaseWriter: configuredLocalDatabaseWriter
                ),
                recoveryEvent: nil
            )
        }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        let result = try Self.openConfiguredLocalRepositoryWithRecovery(
            workspaceId: workspaceId,
            configuration: configuration
        )
        configuredLocalDatabaseWriter = result.repository.databaseWriter
        return result
    }

    private func makeLocalRepositoryForRestore(_ workspaceId: UUID) throws -> LocalRepositoryOpenResult {
        if let makeLocalRestoreRepository {
            return .init(repository: try makeLocalRestoreRepository(workspaceId), recoveryEvent: nil)
        }
        if let configuredLocalDatabaseWriter {
            return .init(
                repository: WorkspaceLocalRepository(
                    workspaceId: workspaceId,
                    databaseWriter: configuredLocalDatabaseWriter
                ),
                recoveryEvent: nil
            )
        }
        guard let configuration else {
            return try makeLocalRepositoryForSave(workspaceId)
        }
        let result = try Self.openConfiguredLocalRepositoryWithRecovery(
            workspaceId: workspaceId,
            configuration: configuration
        )
        configuredLocalDatabaseWriter = result.repository.databaseWriter
        return result
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
                databaseURL: configuration.localDatabaseURL
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

}
