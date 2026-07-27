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
func workspaceSQLiteDatastore(from backend: WorkspaceSQLiteStoreBackend) -> WorkspaceSQLiteDatastore {
    WorkspaceSQLiteDatastore(
        coreRepository: backend.coreRepository,
        makeLocalRepository: { workspaceId in
            try backend.localBackend.repository(for: workspaceId)
        },
        makeLocalRestoreRepository: { workspaceId in
            try backend.localBackend.restoreRepository(for: workspaceId)
        }
    )
}

func workspaceSQLiteDatastore(
    from localBackend: WorkspaceLocalSQLiteStoreBackend
) throws -> WorkspaceSQLiteDatastore {
    let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
    try coreRepository.migrate()
    return WorkspaceSQLiteDatastore(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            try localBackend.repository(for: workspaceId)
        },
        makeLocalRestoreRepository: { workspaceId in
            try localBackend.restoreRepository(for: workspaceId)
        }
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
        }
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
