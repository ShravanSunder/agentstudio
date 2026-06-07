import Foundation
import GRDB

@testable import AgentStudio

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
func workspaceLocalSQLiteBackendWithImportedLegacyLanes(
    repository: WorkspaceLocalRepository
) -> WorkspaceLocalSQLiteStoreBackend {
    WorkspaceLocalSQLiteStoreBackend(
        makeLocalRepository: { _ in repository },
        legacyImportDecision: { _, _ in .blockReplayAllowArchive }
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

func workspaceSQLiteDatastore(from localBackend: WorkspaceLocalSQLiteStoreBackend) throws -> WorkspaceSQLiteDatastore {
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
        },
        makeLocalLegacyImportDecision: { workspaceId, lane in
            try localBackend.legacyImportDecision(for: workspaceId, lane: lane)
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
