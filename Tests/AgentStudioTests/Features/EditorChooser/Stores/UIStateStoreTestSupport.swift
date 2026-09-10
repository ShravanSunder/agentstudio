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

@MainActor
func editorChooserWorkspaceSQLiteDatastore(
    from localBackend: WorkspaceLocalSQLiteStoreBackend
) async throws -> WorkspaceSQLiteDatastoreActor {
    let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
    try coreRepository.migrate()
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        localBackend: localBackend,
        coreDatabaseStartupProvenance: .createdDuringCurrentStartup
    )
    let preparedCore = try WorkspaceSQLiteDatastoreActor.strictlyPrepareCore(using: backend)
    let preparedApplicationLocalRepository: WorkspaceLocalRepository?
    let preparedLocal: WorkspaceSQLiteDatastoreActor.PreparedLocalDatabase
    do {
        preparedApplicationLocalRepository = try localBackend.restoreRepository(
            for: editorChooserApplicationLocalRepositoryScopeId
        )
        preparedLocal = .available(recovery: nil)
    } catch {
        preparedApplicationLocalRepository = nil
        preparedLocal = .unavailable(.init(error))
    }
    return WorkspaceSQLiteDatastoreActor(
        preparedCoreRepository: coreRepository,
        preparationReceipt: .init(core: preparedCore, local: preparedLocal),
        preparedApplicationLocalRepository: preparedApplicationLocalRepository
    )
}

private let editorChooserApplicationLocalRepositoryScopeId = UUID(
    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
)

struct EditorChooserWorkspaceLocalSQLiteStoreFixture {
    let repository: WorkspaceLocalRepository

    @MainActor
    var sqliteBackend: WorkspaceLocalSQLiteStoreBackend {
        WorkspaceLocalSQLiteStoreBackend(makeLocalRepository: { _ in repository })
    }
}
