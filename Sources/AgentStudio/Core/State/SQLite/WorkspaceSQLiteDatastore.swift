import Foundation
import GRDB

struct WorkspaceSQLiteDatastoreConfiguration: Sendable {
    var coreDatabaseURL: URL
    var localDatabaseURL: @Sendable (UUID) -> URL
}

actor WorkspaceSQLiteDatastore {
    enum LocalRepositoryOpenMode: Equatable, Sendable {
        case restore
        case save
    }

    enum ProbeEvent: Equatable, Sendable {
        case saveWorkspaceSnapshot
        case loadWorkspaceSnapshot
        case localRepositoryOpened(UUID, LocalRepositoryOpenMode)
    }

    enum LoadResult: Equatable, Sendable {
        case loaded(WorkspaceSQLiteSnapshot, recoveryEvents: [PersistenceRecoveryEvent])
        case uninitialized(recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    enum LegacyImportStatusResult: Equatable, Sendable {
        case found(WorkspaceCoreRepository.LegacyImportStatusRecord)
        case missing
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum WorkspaceRowsInspectionResult: Equatable, Sendable {
        case hasWorkspaceRows
        case empty
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    private var backend: WorkspaceSQLiteStoreBackend?
    private let configuration: WorkspaceSQLiteDatastoreConfiguration?
    private let makeLocalRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let probe: (@Sendable (ProbeEvent) async -> Void)?

    private var saveLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var restoreLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var pendingRecoveryEventsByWorkspaceId: [UUID: [PersistenceRecoveryEvent]] = [:]

    init(
        configuration: WorkspaceSQLiteDatastoreConfiguration,
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = nil
        self.configuration = configuration
        self.makeLocalRepository = nil
        self.makeLocalRestoreRepository = nil
        self.probe = probe
    }

    init(
        coreRepository: WorkspaceCoreRepository,
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil,
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache },
            makeLocalRestoreRepository: { _ in throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache }
        )
        self.configuration = nil
        self.makeLocalRepository = makeLocalRepository
        self.makeLocalRestoreRepository = makeLocalRestoreRepository ?? makeLocalRepository
        self.probe = probe
    }

    func saveWorkspaceSnapshot(_ snapshot: WorkspaceSQLiteSnapshot) async throws {
        await recordProbe(.saveWorkspaceSnapshot)
        let localRepository = try await cachedSaveLocalRepository(workspaceId: snapshot.id)
        try resolvedBackend().save(snapshot, localRepository: localRepository)
    }

    func loadWorkspaceSnapshot(preferredWorkspaceId: UUID) async -> LoadResult {
        await recordProbe(.loadWorkspaceSnapshot)
        do {
            let snapshot = try await resolvedBackend().loadCompletedSnapshot(
                preferredWorkspaceId: preferredWorkspaceId,
                localRepositoryForWorkspaceId: { workspaceId in
                    try await self.cachedRestoreLocalRepository(workspaceId: workspaceId)
                },
                repairLocalRepositoryForWorkspaceId: { workspaceId in
                    try await self.cachedSaveLocalRepository(workspaceId: workspaceId)
                }
            )
            return .loaded(snapshot, recoveryEvents: drainRecoveryEvents(workspaceId: snapshot.id))
        } catch is BackendUninitializedError {
            return .uninitialized(recoveryEvents: drainAllRecoveryEvents())
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainAllRecoveryEvents())
        }
    }

    func hasCompletedSnapshot(workspaceId: UUID) async throws -> Bool {
        let backend = try resolvedBackend()
        let localRepository = try await cachedRestoreLocalRepository(workspaceId: workspaceId)
        return try backend.hasCompletedSnapshot(workspaceId: workspaceId, localRepository: localRepository)
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

    func inspectWorkspaceRows() async -> WorkspaceRowsInspectionResult {
        do {
            return try resolvedBackend().coreRepository.fetchWorkspaces().isEmpty ? .empty : .hasWorkspaceRows
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

    private func resolvedBackend() throws -> WorkspaceSQLiteStoreBackend {
        if let backend {
            return backend
        }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        let coreDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: configuration.coreDatabaseURL,
            label: "AgentStudio.sqlite.core"
        )
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabasePool)
        try coreRepository.migrate()
        let openedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
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
        )
        backend = openedBackend
        return openedBackend
    }

    private func cachedSaveLocalRepository(workspaceId: UUID) async throws -> WorkspaceLocalRepository {
        if let cachedRepository = saveLocalRepositoryCache[workspaceId] {
            return cachedRepository
        }
        let repository = try makeLocalRepositoryForSave(workspaceId)
        saveLocalRepositoryCache[workspaceId] = repository
        await recordProbe(.localRepositoryOpened(workspaceId, .save))
        return repository
    }

    private func cachedRestoreLocalRepository(workspaceId: UUID) async throws -> WorkspaceLocalRepository {
        if let cachedRepository = restoreLocalRepositoryCache[workspaceId] {
            return cachedRepository
        }
        do {
            let repository = try makeLocalRepositoryForRestore(workspaceId)
            restoreLocalRepositoryCache[workspaceId] = repository
            await recordProbe(.localRepositoryOpened(workspaceId, .restore))
            return repository
        } catch WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(let recoveredWorkspaceId) {
            appendRecoveryEvent(
                .init(
                    store: .workspace,
                    workspaceId: recoveredWorkspaceId,
                    recovery: .quarantinedAndReset
                ),
                workspaceId: recoveredWorkspaceId
            )
            throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(recoveredWorkspaceId)
        } catch WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(let failedWorkspaceId) {
            appendRecoveryEvent(
                .init(
                    store: .workspace,
                    workspaceId: failedWorkspaceId,
                    recovery: .quarantineFailed
                ),
                workspaceId: failedWorkspaceId
            )
            throw WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(failedWorkspaceId)
        }
    }

    private func makeLocalRepositoryForSave(_ workspaceId: UUID) throws -> WorkspaceLocalRepository {
        if let makeLocalRepository {
            return try makeLocalRepository(workspaceId)
        }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        let localDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: configuration.localDatabaseURL(workspaceId),
            label: "AgentStudio.sqlite.local.\(workspaceId.uuidString)"
        )
        let repository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localDatabasePool)
        try repository.migrate()
        return repository
    }

    private func makeLocalRepositoryForRestore(_ workspaceId: UUID) throws -> WorkspaceLocalRepository {
        if let makeLocalRestoreRepository {
            return try makeLocalRestoreRepository(workspaceId)
        }
        return try makeLocalRepositoryForSave(workspaceId)
    }

    private func appendRecoveryEvent(_ event: PersistenceRecoveryEvent, workspaceId: UUID) {
        pendingRecoveryEventsByWorkspaceId[workspaceId, default: []].append(event)
    }

    private func drainRecoveryEvents(workspaceId: UUID) -> [PersistenceRecoveryEvent] {
        let events = pendingRecoveryEventsByWorkspaceId[workspaceId] ?? []
        pendingRecoveryEventsByWorkspaceId[workspaceId] = nil
        return events
    }

    private func drainAllRecoveryEvents() -> [PersistenceRecoveryEvent] {
        let events = pendingRecoveryEventsByWorkspaceId.values.flatMap { $0 }
        pendingRecoveryEventsByWorkspaceId.removeAll()
        return events
    }

    private func recordProbe(_ event: ProbeEvent) async {
        guard let probe else { return }
        await probe(event)
    }
}

enum WorkspaceSQLiteDatastoreError: Error, Equatable, Sendable {
    case missingConfiguration
    case useDatastoreLocalRepositoryCache
}

struct WorkspaceSQLiteDatastoreFailure: Error, Equatable, Sendable {
    let description: String

    init(_ error: any Error) {
        self.description = String(describing: error)
    }
}
