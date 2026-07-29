import Foundation
import GRDB

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

func makeWorkspaceLocalSQLiteStoreFixture(
    workspaceId: UUID
) throws -> WorkspaceLocalSQLiteStoreFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    return .init(
        repository: WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: databaseQueue),
        databaseQueue: databaseQueue
    )
}

@MainActor
func failingWorkspaceLocalSQLiteBackend() -> WorkspaceLocalSQLiteStoreBackend {
    WorkspaceLocalSQLiteStoreBackend { _ in
        throw CocoaError(.fileNoSuchFile)
    }
}

@MainActor
func preparedWorkspaceSQLiteDatastore(
    from backend: WorkspaceSQLiteStoreBackend,
    traceRuntime: AgentStudioTraceRuntime? = nil,
    probe: (@Sendable (WorkspaceSQLiteDatastore.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastore {
    let preparedCore = try WorkspaceSQLiteDatastore.strictlyPrepareCore(using: backend)
    let preparedApplicationLocalRepository: WorkspaceLocalRepository?
    let preparedLocal: WorkspaceSQLiteDatastore.PreparedLocalDatabase
    do {
        preparedApplicationLocalRepository = try backend.localBackend.restoreRepository(
            for: preparedApplicationLocalRepositoryScopeId
        )
        preparedLocal = .available(recovery: nil)
    } catch {
        preparedApplicationLocalRepository = nil
        preparedLocal = .unavailable(.init(error))
    }
    return WorkspaceSQLiteDatastore(
        preparedCoreRepository: backend.coreRepository,
        preparationReceipt: .init(core: preparedCore, local: preparedLocal),
        preparedApplicationLocalRepository: preparedApplicationLocalRepository,
        traceRuntime: traceRuntime,
        probe: probe
    )
}

@MainActor
func preparedWorkspaceSQLiteDatastore(
    from localBackend: WorkspaceLocalSQLiteStoreBackend,
    traceRuntime: AgentStudioTraceRuntime? = nil,
    probe: (@Sendable (WorkspaceSQLiteDatastore.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastore {
    let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
    try coreRepository.migrate()
    return try await preparedWorkspaceSQLiteDatastore(
        from: WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            localBackend: localBackend,
            coreDatabaseStartupProvenance: .createdDuringCurrentStartup
        ),
        traceRuntime: traceRuntime,
        probe: probe
    )
}

@MainActor
func preparedWorkspaceSQLiteDatastore(
    coreRepository: WorkspaceCoreRepository,
    preparedApplicationLocalRepository: WorkspaceLocalRepository,
    traceRuntime: AgentStudioTraceRuntime? = nil,
    probe: (@Sendable (WorkspaceSQLiteDatastore.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastore {
    try await preparedWorkspaceSQLiteDatastore(
        from: WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(
                    workspaceId: workspaceId,
                    databaseWriter: preparedApplicationLocalRepository.databaseWriter
                )
            },
            coreDatabaseStartupProvenance: .createdDuringCurrentStartup
        ),
        traceRuntime: traceRuntime,
        probe: probe
    )
}

@MainActor
func preparedWorkspaceSQLiteDatastore(
    coreRepository: WorkspaceCoreRepository,
    localUnavailable failure: WorkspaceSQLiteDatastoreFailure,
    traceRuntime: AgentStudioTraceRuntime? = nil,
    probe: (@Sendable (WorkspaceSQLiteDatastore.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastore {
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { _ in
            throw WorkspaceSQLiteDatastoreError.useDatastoreApplicationLocalRepositoryBundle
        },
        coreDatabaseStartupProvenance: .createdDuringCurrentStartup
    )
    let preparedCore = try WorkspaceSQLiteDatastore.strictlyPrepareCore(using: backend)
    return WorkspaceSQLiteDatastore(
        preparedCoreRepository: coreRepository,
        preparationReceipt: .init(core: preparedCore, local: .unavailable(failure)),
        preparedApplicationLocalRepository: nil,
        traceRuntime: traceRuntime,
        probe: probe
    )
}

private let preparedApplicationLocalRepositoryScopeId = UUID(
    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
)

struct WorkspaceLocalSQLiteStoreFixture {
    let repository: WorkspaceLocalRepository
    let databaseQueue: DatabaseQueue

    @MainActor
    var sqliteBackend: WorkspaceLocalSQLiteStoreBackend {
        WorkspaceLocalSQLiteStoreBackend(makeLocalRepository: { _ in repository })
    }
}
