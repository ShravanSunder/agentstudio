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
    probe: (@Sendable (WorkspaceSQLiteDatastoreActor.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastoreActor {
    let preparedCore = try WorkspaceSQLiteDatastoreActor.strictlyPrepareCore(using: backend)
    let preparedApplicationLocalRepository: WorkspaceLocalRepository?
    let preparedLocal: WorkspaceSQLiteDatastoreActor.PreparedLocalDatabase
    do {
        preparedApplicationLocalRepository = try backend.localBackend.restoreRepository(
            for: preparedApplicationLocalRepositoryScopeId
        )
        preparedLocal = .available(recovery: nil)
    } catch {
        preparedApplicationLocalRepository = nil
        preparedLocal = .unavailable(.init(error))
    }
    return WorkspaceSQLiteDatastoreActor(
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
    probe: (@Sendable (WorkspaceSQLiteDatastoreActor.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastoreActor {
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
    probe: (@Sendable (WorkspaceSQLiteDatastoreActor.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastoreActor {
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
    probe: (@Sendable (WorkspaceSQLiteDatastoreActor.ProbeEvent) async -> Void)? = nil
) async throws -> WorkspaceSQLiteDatastoreActor {
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { _ in
            throw WorkspaceSQLiteDatastoreError.useDatastoreApplicationLocalRepositoryBundle
        },
        coreDatabaseStartupProvenance: .createdDuringCurrentStartup
    )
    let preparedCore = try WorkspaceSQLiteDatastoreActor.strictlyPrepareCore(using: backend)
    return WorkspaceSQLiteDatastoreActor(
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
