import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteLegacyImportStatusTests", .serialized)
struct WorkspaceSQLiteLegacyImportStatusTests {
    @Test("post-commit import-status failure does not replay stale legacy JSON")
    func postCommitStatusFailureDoesNotReplayStaleLegacyJSON() async throws {
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-00000000AA01")!
        let fixture = try makeLegacyStatusFixture()
        let persistor = makeLegacyStatusPersistor()
        try saveLegacyStatusWorkspace(
            workspaceId,
            name: "Legacy Name",
            updatedAt: Date(timeIntervalSince1970: 1_700_003_000),
            persistor: persistor
        )
        try await fixture.coreQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER fail_success_status
                    BEFORE INSERT ON legacy_workspace_import_status
                    WHEN NEW.last_error IS NULL
                    BEGIN
                        SELECT RAISE(ABORT, 'injected status success failure');
                    END
                    """
            )
        }
        let firstBootStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor, sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend))
        await firstBootStore.restoreAsync()
        try await fixture.coreQueue.write { database in
            try database.execute(sql: "DROP TRIGGER fail_success_status")
        }
        try fixture.backend.save(
            .emptyFixture(
                id: workspaceId,
                name: "SQLite Newer Name",
                createdAt: Date(timeIntervalSince1970: 1_700_003_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_003_500)
            )
        )

        let secondBootStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor, sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend))
        await secondBootStore.restoreAsync()

        #expect(secondBootStore.identityAtom.workspaceName == "SQLite Newer Name")
        #expect(secondBootStore.identityAtom.workspaceName != "Legacy Name")
        #expect(try fixture.coreRepository.fetchWorkspace(id: workspaceId)?.name == "SQLite Newer Name")
    }

    @Test("missing status for incomplete rows retries legacy file")
    func missingStatusForIncompleteRowsRetriesLegacyFile() async throws {
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-00000000AA02")!
        let fixture = try makeLegacyStatusFixture(failingLocalWorkspaceId: workspaceId)
        let persistor = makeLegacyStatusPersistor()
        try saveLegacyStatusWorkspace(
            workspaceId,
            name: "Retryable Legacy",
            updatedAt: Date(timeIntervalSince1970: 1_700_003_600),
            persistor: persistor
        )
        let failedBootStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor, sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend))
        await failedBootStore.restoreAsync()
        try await fixture.coreQueue.write { database in
            try database.execute(
                sql: "DELETE FROM legacy_workspace_import_status WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        }

        let retryFixture = try makeLegacyStatusFixture(coreQueue: fixture.coreQueue)
        let retryBootStore = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: persistor, sqliteDatastore: workspaceSQLiteDatastore(from: retryFixture.backend))
        await retryBootStore.restoreAsync()

        #expect(retryBootStore.identityAtom.workspaceId == workspaceId)
        #expect(retryBootStore.identityAtom.workspaceName == "Retryable Legacy")
        #expect(try retryFixture.coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: workspaceId))
    }
}

private struct LegacyStatusFixture {
    let coreQueue: DatabaseQueue
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let backend: WorkspaceSQLiteStoreBackend
}

@MainActor
private func makeLegacyStatusFixture(
    coreQueue existingCoreQueue: DatabaseQueue? = nil,
    failingLocalWorkspaceId: UUID? = nil
) throws -> LegacyStatusFixture {
    let coreQueue =
        try existingCoreQueue ?? SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.legacy.status.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.legacy.status.local")
    if existingCoreQueue == nil {
        try WorkspaceCoreMigrations.migrate(coreQueue)
    }
    try WorkspaceLocalMigrations.migrate(localQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            if workspaceId == failingLocalWorkspaceId {
                throw CocoaError(.fileNoSuchFile)
            }
            return WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        }
    )
    return .init(
        coreQueue: coreQueue,
        localQueue: localQueue,
        coreRepository: coreRepository,
        backend: backend
    )
}

private func makeLegacyStatusPersistor() -> WorkspacePersistor {
    let workspaceDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let persistor = WorkspacePersistor(workspacesDir: workspaceDirectory)
    #expect(persistor.ensureDirectory())
    return persistor
}

private func saveLegacyStatusWorkspace(
    _ workspaceId: UUID,
    name: String,
    updatedAt: Date,
    persistor: WorkspacePersistor
) throws {
    try persistor.save(
        .init(
            id: workspaceId,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_003_000),
            updatedAt: updatedAt
        )
    )
}
