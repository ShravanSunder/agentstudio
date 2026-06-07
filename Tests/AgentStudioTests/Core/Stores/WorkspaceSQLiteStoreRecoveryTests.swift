import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreRecoveryTests", .serialized)
struct WorkspaceSQLiteStoreRecoveryTests {
    @Test("local snapshot failure prevents core snapshot completion")
    func localSnapshotFailurePreventsCoreSnapshotCompletion() throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_250)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Committed Workspace",
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_260)
            )
        )
        let failingBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: fixture.coreRepository,
            makeLocalRepository: { _ in
                throw CocoaError(.fileNoSuchFile)
            }
        )

        #expect(throws: CocoaError.self) {
            try failingBackend.save(
                .init(
                    id: workspaceId,
                    name: "Staged Core Without Local",
                    createdAt: createdAt,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_270)
                )
            )
        }

        #expect(try !fixture.backend.hasCompletedSnapshot(workspaceId: workspaceId))
        #expect(try fixture.backend.load(preferredWorkspaceId: workspaceId) == nil)
    }

    @Test("failed core replacement does not advance local snapshot token")
    func failedCoreReplacementDoesNotAdvanceLocalSnapshotToken() throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_280)
        let committedUpdatedAt = Date(timeIntervalSince1970: 1_700_000_290)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Committed Workspace",
                activeTabId: nil,
                sidebarWidth: 250,
                createdAt: createdAt,
                updatedAt: committedUpdatedAt
            )
        )
        let committedLocalSnapshotAt = try fixture.localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt()
        let invalidPaneId = UUID()
        let invalidTab = Tab(paneId: invalidPaneId, name: "Invalid Replacement Tab")

        #expect(throws: (any Error).self) {
            try fixture.backend.save(
                .init(
                    id: workspaceId,
                    name: "Invalid Replacement",
                    panes: [],
                    tabs: [invalidTab],
                    activeTabId: invalidTab.id,
                    sidebarWidth: 999,
                    createdAt: createdAt,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
                )
            )
        }

        #expect(try fixture.localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == committedLocalSnapshotAt)
        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: workspaceId))
        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Committed Workspace")
        #expect(loaded.name != "Invalid Replacement")
        #expect(loaded.activeTabId == nil)
        #expect(loaded.sidebarWidth == 250)
    }

    @Test("completed snapshot readiness requires matching local snapshot")
    func completedSnapshotReadinessRequiresMatchingLocalSnapshot() throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        let coreCompletedAt = Date(timeIntervalSince1970: 1_700_000_310)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Archive Candidate",
                sidebarWidth: 315,
                createdAt: Date(timeIntervalSince1970: 1_700_000_300),
                updatedAt: coreCompletedAt
            )
        )
        #expect(try fixture.backend.hasCompletedSnapshot(workspaceId: workspaceId))

        try fixture.localQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE local_workspace_sqlite_snapshot_status
                    SET completed_at = ?
                    WHERE workspace_id = ?
                    """,
                arguments: [
                    coreCompletedAt.addingTimeInterval(60).timeIntervalSince1970,
                    workspaceId.uuidString,
                ]
            )
        }

        #expect(try !fixture.backend.hasCompletedSnapshot(workspaceId: workspaceId))
    }

    @Test("restore repairs stale local completion token after synthesizing local state")
    func restoreRepairsStaleLocalCompletionTokenAfterSynthesizingLocalState() throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        let coreCompletedAt = Date(timeIntervalSince1970: 1_700_000_315)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Repair Local Completion",
                sidebarWidth: 315,
                createdAt: Date(timeIntervalSince1970: 1_700_000_305),
                updatedAt: coreCompletedAt
            )
        )
        try fixture.localQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE local_workspace_sqlite_snapshot_status
                    SET completed_at = ?
                    WHERE workspace_id = ?
                    """,
                arguments: [
                    coreCompletedAt.addingTimeInterval(60).timeIntervalSince1970,
                    workspaceId.uuidString,
                ]
            )
        }
        #expect(try !fixture.backend.hasCompletedSnapshot(workspaceId: workspaceId))

        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: workspaceId))

        #expect(loaded.id == workspaceId)
        #expect(loaded.sidebarWidth == 250)
        #expect(try fixture.backend.hasCompletedSnapshot(workspaceId: workspaceId))
    }

    @Test("non-corruption local restore failure still restores canonical core state")
    func nonCorruptionLocalRestoreFailureStillRestoresCanonicalCoreState() throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Core Survives Local Restore Failure",
                sidebarWidth: 315,
                createdAt: Date(timeIntervalSince1970: 1_700_000_320),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_330)
            )
        )
        let failingRestoreBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: fixture.coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: fixture.localQueue)
            },
            makeLocalRestoreRepository: { _ in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        let loaded = try #require(try failingRestoreBackend.load(preferredWorkspaceId: workspaceId))

        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Core Survives Local Restore Failure")
        #expect(loaded.sidebarWidth == 250)
    }

    @Test("legacy retry imports pending files without stealing active SQLite selection")
    func legacyRetryImportsPendingFilesWithoutStealingActiveSQLiteSelection() throws {
        let importedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let retryWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let fixture = try makeRetryFixture()
        let failingBackend = fixture.backend(failingWorkspaceId: retryWorkspaceId)
        let retryBackend = fixture.backend()
        let persistor = makePersistor()
        try saveLegacyWorkspace(
            importedWorkspaceId,
            name: "Imported First",
            createdAt: Date(timeIntervalSince1970: 1_700_002_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_002_100),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_200),
            persistor: persistor
        )
        try saveLegacyWorkspace(
            retryWorkspaceId,
            name: "Retry Winner",
            createdAt: Date(timeIntervalSince1970: 1_700_002_010),
            updatedAt: Date(timeIntervalSince1970: 1_700_002_020),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_300),
            persistor: persistor
        )

        let firstBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: failingBackend)
        firstBootStore.restore()
        let secondBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: retryBackend)
        secondBootStore.restore()

        #expect(secondBootStore.identityAtom.workspaceId == importedWorkspaceId)
        #expect(secondBootStore.identityAtom.workspaceName == "Imported First")
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == importedWorkspaceId)
        #expect(try fixture.coreRepository.fetchWorkspace(id: importedWorkspaceId) != nil)
        #expect(try fixture.coreRepository.fetchWorkspace(id: retryWorkspaceId) != nil)
    }

    @Test("legacy retry materialization does not rewrite active selection")
    func legacyRetryMaterializationDoesNotRewriteActiveSelection() throws {
        let importedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let retryWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let fixture = try makeRetryFixture()
        let failingBackend = fixture.backend(failingWorkspaceId: retryWorkspaceId)
        let retryBackend = fixture.backend()
        let persistor = makePersistor()
        try saveLegacyWorkspace(
            importedWorkspaceId,
            name: "Imported Stable Selection",
            createdAt: Date(timeIntervalSince1970: 1_700_002_500),
            updatedAt: Date(timeIntervalSince1970: 1_700_002_510),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_600),
            persistor: persistor
        )
        try saveLegacyWorkspace(
            retryWorkspaceId,
            name: "Retried Pending Selection",
            createdAt: Date(timeIntervalSince1970: 1_700_002_520),
            updatedAt: Date(timeIntervalSince1970: 1_700_002_530),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_700),
            persistor: persistor
        )
        let firstBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: failingBackend)
        firstBootStore.restore()
        let activeSelectionUpdatedAtBeforeRetry = try fetchActiveWorkspaceSelectionUpdatedAt(
            in: fixture.coreQueue
        )

        let secondBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: retryBackend)
        secondBootStore.restore()

        #expect(secondBootStore.identityAtom.workspaceId == importedWorkspaceId)
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == importedWorkspaceId)
        #expect(
            try fetchActiveWorkspaceSelectionUpdatedAt(in: fixture.coreQueue) == activeSelectionUpdatedAtBeforeRetry)
        let thirdBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: retryBackend)
        thirdBootStore.restore()
        #expect(thirdBootStore.identityAtom.workspaceId == importedWorkspaceId)
        #expect(
            try fetchActiveWorkspaceSelectionUpdatedAt(in: fixture.coreQueue) == activeSelectionUpdatedAtBeforeRetry)
    }

    @Test("legacy retry does not replay completed workspace files over newer SQLite state")
    func legacyRetryDoesNotReplayCompletedWorkspaceFilesOverNewerSQLiteState() throws {
        let completedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let retryWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
        let fixture = try makeRetryFixture()
        let failingBackend = fixture.backend(failingWorkspaceId: retryWorkspaceId)
        let retryBackend = fixture.backend()
        let persistor = makePersistor()
        let completedCreatedAt = Date(timeIntervalSince1970: 1_700_002_000)
        try saveLegacyWorkspace(
            completedWorkspaceId,
            name: "Completed Legacy Name",
            createdAt: completedCreatedAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_002_100),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_200),
            persistor: persistor
        )
        try saveLegacyWorkspace(
            retryWorkspaceId,
            name: "Retry Legacy Name",
            createdAt: Date(timeIntervalSince1970: 1_700_002_010),
            updatedAt: Date(timeIntervalSince1970: 1_700_002_020),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_300),
            persistor: persistor
        )

        let firstBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: failingBackend)
        firstBootStore.restore()
        try retryBackend.save(
            .init(
                id: completedWorkspaceId,
                name: "SQLite Mutated Name",
                createdAt: completedCreatedAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_002_400)
            )
        )
        let secondBootStore = WorkspaceStore(persistor: persistor, sqliteBackend: retryBackend)
        secondBootStore.restore()

        #expect(secondBootStore.identityAtom.workspaceId == completedWorkspaceId)
        #expect(secondBootStore.identityAtom.workspaceName == "SQLite Mutated Name")
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == completedWorkspaceId)
        #expect(try fixture.coreRepository.fetchWorkspace(id: completedWorkspaceId)?.name == "SQLite Mutated Name")
        #expect(try fixture.coreRepository.fetchWorkspace(id: completedWorkspaceId)?.name != "Completed Legacy Name")
        #expect(try fixture.coreRepository.fetchWorkspace(id: retryWorkspaceId)?.name == "Retry Legacy Name")
    }

    @Test("partial initial legacy import hydrates successfully imported workspace")
    func partialInitialLegacyImportHydratesSuccessfullyImportedWorkspace() throws {
        let importedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000017")!
        let failedWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000018")!
        let fixture = try makeRetryFixture()
        let failingBackend = fixture.backend(failingWorkspaceId: failedWorkspaceId)
        let persistor = makePersistor()
        try saveLegacyWorkspace(
            importedWorkspaceId,
            name: "Imported Visible Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_002_120),
            updatedAt: Date(timeIntervalSince1970: 1_700_002_130),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_200),
            persistor: persistor
        )
        try saveLegacyWorkspace(
            failedWorkspaceId,
            name: "Failed Later Workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_002_140),
            updatedAt: Date(timeIntervalSince1970: 1_700_002_150),
            modificationDate: Date(timeIntervalSince1970: 1_700_002_300),
            persistor: persistor
        )

        let store = WorkspaceStore(persistor: persistor, sqliteBackend: failingBackend)
        store.restore()

        #expect(store.identityAtom.workspaceId == importedWorkspaceId)
        #expect(store.identityAtom.workspaceName == "Imported Visible Workspace")
        #expect(try fixture.coreRepository.fetchActiveWorkspaceId() == importedWorkspaceId)
        #expect(try fixture.coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: importedWorkspaceId))
        #expect(try fixture.coreRepository.fetchWorkspace(id: failedWorkspaceId) != nil)
        #expect(try !fixture.coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: failedWorkspaceId))
    }

    @Test("local read failure still restores canonical core state")
    func localReadFailureStillRestoresCanonicalCoreState() throws {
        let workspaceId = UUID()
        let fixture = try makeRecoveryFixture(workspaceId: workspaceId)
        try fixture.backend.save(
            .init(
                id: workspaceId,
                name: "Core Survives Local Read Failure",
                sidebarWidth: 315,
                createdAt: Date(timeIntervalSince1970: 1_700_000_340),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_350)
            )
        )
        try fixture.localQueue.write { database in
            try database.execute(sql: "DROP TABLE local_workspace_sqlite_snapshot_status")
        }

        let loaded = try #require(try fixture.backend.load(preferredWorkspaceId: workspaceId))

        #expect(loaded.id == workspaceId)
        #expect(loaded.name == "Core Survives Local Read Failure")
        #expect(loaded.sidebarWidth == 250)
    }
}

private struct WorkspaceSQLiteRecoveryFixture {
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let localRepository: WorkspaceLocalRepository
    let backend: WorkspaceSQLiteStoreBackend
}

private struct WorkspaceSQLiteRetryFixture {
    let coreQueue: DatabaseQueue
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository

    @MainActor
    func backend(failingWorkspaceId: UUID? = nil) -> WorkspaceSQLiteStoreBackend {
        WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                if workspaceId == failingWorkspaceId {
                    throw WorkspaceSQLiteRecoveryTestError.injectedLocalRepositoryFailure
                }
                return WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            }
        )
    }
}

private enum WorkspaceSQLiteRecoveryTestError: Error {
    case injectedLocalRepositoryFailure
}

@MainActor
private func makeRecoveryFixture(workspaceId: UUID) throws -> WorkspaceSQLiteRecoveryFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.recovery.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.recovery.local")
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

@MainActor
private func makeRetryFixture() throws -> WorkspaceSQLiteRetryFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.retry.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.retry.local")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    return .init(
        coreQueue: coreQueue,
        localQueue: localQueue,
        coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue)
    )
}

private func makePersistor() -> WorkspacePersistor {
    let workspaceDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let persistor = WorkspacePersistor(workspacesDir: workspaceDirectory)
    #expect(persistor.ensureDirectory())
    return persistor
}

private func saveLegacyWorkspace(
    _ workspaceId: UUID,
    name: String,
    createdAt: Date,
    updatedAt: Date,
    modificationDate: Date,
    persistor: WorkspacePersistor
) throws {
    try persistor.save(
        .init(
            id: workspaceId,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    )
    try FileManager.default.setAttributes(
        [.modificationDate: modificationDate],
        ofItemAtPath: persistor.canonicalWorkspaceStatePath(for: workspaceId)
    )
}

private func fetchActiveWorkspaceSelectionUpdatedAt(in databaseQueue: DatabaseQueue) throws -> Double? {
    try databaseQueue.read { database in
        try Double.fetchOne(
            database,
            sql: "SELECT updated_at FROM app_workspace_selection WHERE singleton_id = 1"
        )
    }
}
