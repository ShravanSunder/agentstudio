import Foundation

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

func makeEditorChooserWorkspaceLocalSQLiteStoreFixture(
    workspaceId: UUID
) throws -> EditorChooserWorkspaceLocalSQLiteStoreFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    return EditorChooserWorkspaceLocalSQLiteStoreFixture(
        repository: WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: databaseQueue
        )
    )
}

@MainActor
func failingEditorChooserWorkspaceLocalSQLiteBackend() -> WorkspaceLocalSQLiteStoreBackend {
    WorkspaceLocalSQLiteStoreBackend { _ in
        throw CocoaError(.fileNoSuchFile)
    }
}

func editorChooserWorkspaceSQLiteDatastore(
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

struct EditorChooserWorkspaceLocalSQLiteStoreFixture {
    let repository: WorkspaceLocalRepository

    @MainActor
    var sqliteBackend: WorkspaceLocalSQLiteStoreBackend {
        WorkspaceLocalSQLiteStoreBackend(makeLocalRepository: { _ in repository })
    }
}
