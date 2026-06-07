import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteDatastoreActorTests", .serialized)
struct WorkspaceSQLiteDatastoreActorTests {
    @Test("workspace save runs through datastore actor probe")
    func workspaceSaveRunsThroughDatastoreActorProbe() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) },
            probe: { event in await recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(
            .emptyFixture(
                id: workspaceId,
                name: "Datastore",
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        )

        #expect(await recorder.events.contains(.saveWorkspaceSnapshot))
        #expect(await recorder.events.contains(.localRepositoryOpened(workspaceId, .save)))
    }

    @Test("local repository is cached by workspace id across production saves")
    func localRepositoryIsCachedByWorkspaceIdAcrossProductionSaves() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.cache.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.cache.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            },
            probe: { event in await recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "One"))
        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Two"))

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
    }

    @Test("local repository is cached by workspace id across production load")
    func localRepositoryIsCachedByWorkspaceIdAcrossProductionLoad() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.load.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.load.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            },
            probe: { event in await recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Loaded"))
        _ = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .restore) }.count == 1)
    }

    @Test("restore repair uses save repository cache")
    func restoreRepairUsesSaveRepositoryCache() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.repair.core")
        let seedLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.repair.seed")
        let staleRestoreLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.repair.restore")
        let repairLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.repair.save")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(seedLocalQueue)
        try WorkspaceLocalMigrations.migrate(staleRestoreLocalQueue)
        try WorkspaceLocalMigrations.migrate(repairLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let seedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: seedLocalQueue) }
        )
        let updatedAt = Date(timeIntervalSince1970: 3)
        try seedBackend.save(.emptyFixture(id: workspaceId, name: "Repair", updatedAt: updatedAt))
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: repairLocalQueue) },
            makeLocalRestoreRepository: {
                WorkspaceLocalRepository(workspaceId: $0, databaseWriter: staleRestoreLocalQueue)
            },
            probe: { event in await recorder.record(event) }
        )

        _ = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .restore) }.count == 1)
        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
        let repairedRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: repairLocalQueue)
        #expect(try repairedRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == updatedAt)
    }

    @Test("workspace load returns first local restore recovery events")
    func workspaceLoadReturnsFirstLocalRestoreRecoveryEvents() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.recovery.core")
        let seedLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.recovery.seed")
        let repairLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.datastore.recovery.repair")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(seedLocalQueue)
        try WorkspaceLocalMigrations.migrate(repairLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let seedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: seedLocalQueue) }
        )
        try seedBackend.save(.emptyFixture(id: workspaceId, name: "Recovered"))
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: repairLocalQueue) },
            makeLocalRestoreRepository: { workspaceId in
                throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(workspaceId)
            }
        )

        let result = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        guard case .loaded(let snapshot, let recoveryEvents) = result else {
            Issue.record("Expected loaded snapshot after local recovery")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(
            recoveryEvents.contains {
                $0.store == .workspace
                    && $0.workspaceId == workspaceId
                    && $0.recovery == .quarantinedAndReset
            }
        )
    }

    @Test("workspace status APIs use datastore boundary")
    func workspaceStatusApisUseDatastoreBoundary() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.status.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.status.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
        )

        #expect(await datastore.inspectWorkspaceRows() == .empty)
        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Status"))
        #expect(await datastore.inspectWorkspaceRows() == .hasWorkspaceRows)
        #expect(try await datastore.hasCompletedSnapshot(workspaceId: workspaceId))
        #expect(await datastore.legacyImportStatus(workspaceId: workspaceId) == .missing)
    }
}

private actor DatastoreProbeRecorder {
    private(set) var events: [WorkspaceSQLiteDatastore.ProbeEvent] = []

    func record(_ event: WorkspaceSQLiteDatastore.ProbeEvent) {
        events.append(event)
    }
}
