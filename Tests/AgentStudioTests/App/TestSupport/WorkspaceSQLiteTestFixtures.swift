import AgentStudioInfrastructure
import Foundation
import GRDB

@testable import AgentStudioCore

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
func preparedWorkspaceSQLiteDatastore(
    from backend: WorkspaceSQLiteStoreBackend
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
        preparedApplicationLocalRepository: preparedApplicationLocalRepository
    )
}

@MainActor
func preparedWorkspaceSQLiteDatastore(
    coreRepository: WorkspaceCoreRepository,
    preparedApplicationLocalRepository: WorkspaceLocalRepository
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
        )
    )
}

@MainActor
func preparedWorkspaceSQLiteDatastore(
    coreRepository: WorkspaceCoreRepository,
    localUnavailable failure: WorkspaceSQLiteDatastoreFailure
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
        preparedApplicationLocalRepository: nil
    )
}

private let preparedApplicationLocalRepositoryScopeId = UUID(
    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
)

@MainActor
func workspaceSQLiteDatastore(
    from localBackend: WorkspaceLocalSQLiteStoreBackend
) async throws -> WorkspaceSQLiteDatastoreActor {
    let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
    try coreRepository.migrate()
    return try await preparedWorkspaceSQLiteDatastore(
        from: WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            localBackend: localBackend,
            coreDatabaseStartupProvenance: .createdDuringCurrentStartup
        )
    )
}

struct WorkspaceLocalSQLiteStoreFixture {
    let repository: WorkspaceLocalRepository
    let databaseQueue: DatabaseQueue

    @MainActor
    var sqliteBackend: WorkspaceLocalSQLiteStoreBackend {
        WorkspaceLocalSQLiteStoreBackend(makeLocalRepository: { _ in repository })
    }
}

struct WorkspaceSQLiteBridgeFixture {
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let localRepository: WorkspaceLocalRepository
    let backend: WorkspaceSQLiteStoreBackend
}

@MainActor
func makeWorkspaceSQLiteBridgeFixture(workspaceId: UUID) throws -> WorkspaceSQLiteBridgeFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.bridge.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.bridge.local")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        },
        coreDatabaseStartupProvenance: .createdDuringCurrentStartup
    )
    return .init(
        localQueue: localQueue,
        coreRepository: coreRepository,
        localRepository: localRepository,
        backend: backend
    )
}

extension Collection {
    var single: Element? {
        count == 1 ? first : nil
    }
}

extension WorkspaceSQLiteSaveBundle {
    static func emptyTopologyFixture(workspace: WorkspaceSQLiteSnapshot) -> Self {
        Self(workspace: workspace)
    }
}
