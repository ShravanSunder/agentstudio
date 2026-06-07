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

struct WorkspaceLocalSQLiteStoreFixture {
    let repository: WorkspaceLocalRepository
    let databaseQueue: DatabaseQueue

    @MainActor
    var sqliteBackend: WorkspaceLocalSQLiteStoreBackend {
        WorkspaceLocalSQLiteStoreBackend(makeLocalRepository: { _ in repository })
    }
}
