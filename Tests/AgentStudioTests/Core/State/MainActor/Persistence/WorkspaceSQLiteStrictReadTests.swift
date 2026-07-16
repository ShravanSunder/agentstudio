import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace SQLite strict read", .serialized)
struct WorkspaceSQLiteStrictReadTests {
    @Test("newly created empty core database is the only uninitialized startup state")
    func newlyCreatedEmptyCoreDatabaseIsUninitialized() async throws {
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "new-core")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            }
        ).makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .uninitialized(let recoveryEvents) = result else {
            Issue.record("Expected newly created SQLite to be uninitialized, got \(result)")
            return
        }
        #expect(recoveryEvents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: coreDatabaseURL.path))
    }

    @Test("pre-existing current-schema empty core database is rejected without writes")
    func preexistingCurrentSchemaEmptyCoreDatabaseIsRejectedWithoutWrites() async throws {
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "existing-empty-core")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let setupPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.strict-read.existing-empty.setup"
        )
        try WorkspaceCoreMigrations.migrate(setupPool)
        try setupPool.close()
        let bytesBeforeLoad = try Data(contentsOf: coreDatabaseURL)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            }
        ).makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable(let failure, let recoveryEvents) = result else {
            Issue.record("Expected pre-existing empty SQLite to be unavailable, got \(result)")
            return
        }
        #expect(failure.description.contains("preexistingDatabaseHasNoWorkspaceRows"))
        #expect(recoveryEvents.isEmpty)
        #expect(try Data(contentsOf: coreDatabaseURL) == bytesBeforeLoad)
        #expect(try !containsQuarantineArtifact(in: rootDirectory))
    }

    @Test("corrupt core database remains byte-for-byte unchanged after strict startup failure")
    func corruptCoreDatabaseIsUnchangedAfterStrictStartupFailure() async throws {
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "corrupt-core")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let corruptBytes = Data("strict startup must not replace corrupt core SQLite".utf8)
        try corruptBytes.write(to: coreDatabaseURL)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            }
        ).makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable(_, let recoveryEvents) = result else {
            Issue.record("Expected corrupt core SQLite to be unavailable, got \(result)")
            return
        }
        #expect(recoveryEvents.isEmpty)
        #expect(try Data(contentsOf: coreDatabaseURL) == corruptBytes)
        #expect(try !containsQuarantineArtifact(in: rootDirectory))
    }

    @Test("corrupt local database remains byte-for-byte unchanged after strict startup failure")
    func corruptLocalDatabaseIsUnchangedAfterStrictStartupFailure() async throws {
        let workspaceId = UUIDv7.generate()
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "corrupt-local")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let localDatabaseURL = rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: { _ in localDatabaseURL }
        )
        try await seedStrictReadWorkspace(
            workspaceId: workspaceId,
            factory: factory
        )
        try removeSQLiteSidecarsIfPresent(for: localDatabaseURL)
        let corruptBytes = Data("strict startup must not replace corrupt local SQLite".utf8)
        try corruptBytes.write(to: localDatabaseURL)
        let datastore = factory.makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable(_, let recoveryEvents) = result else {
            Issue.record("Expected corrupt local SQLite to be unavailable, got \(result)")
            return
        }
        #expect(recoveryEvents.isEmpty)
        #expect(try Data(contentsOf: localDatabaseURL) == corruptBytes)
        #expect(try !containsQuarantineArtifact(in: rootDirectory))
    }

    @Test("missing active selection is rejected without selecting the preferred workspace")
    func missingActiveSelectionIsRejectedWithoutSelectingPreferredWorkspace() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.missing-selection.core"
        )
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.missing-selection.local"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            }
        )
        try backend.save(
            .emptyTopologyFixture(workspace: .emptyFixture(id: workspaceId, name: "Strict Selection"))
        )
        try await coreQueue.write { database in
            try database.execute(
                sql: "UPDATE app_workspace_selection SET active_workspace_id = NULL WHERE singleton_id = 1"
            )
        }
        let selectionBeforeLoad = try activeWorkspaceSelection(in: coreQueue)
        let datastore = workspaceSQLiteDatastore(from: backend)

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable = result else {
            Issue.record("Expected strict failure for missing active selection, got \(result)")
            return
        }
        #expect(try activeWorkspaceSelection(in: coreQueue) == selectionBeforeLoad)
    }

    @Test("staged core snapshot is rejected without synthesizing local state or completing core")
    func stagedCoreSnapshotIsRejectedWithoutCompletingIt() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.staged.core"
        )
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.staged.local"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let failingDatastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in throw CocoaError(.fileNoSuchFile) }
        )
        do {
            try await failingDatastore.saveWorkspaceSnapshotBundle(
                .emptyTopologyFixture(
                    workspace: .emptyFixture(
                        id: workspaceId,
                        name: "Incomplete Save",
                        updatedAt: Date(timeIntervalSince1970: 20)
                    )
                )
            )
            Issue.record("Expected the arranged local save to fail")
        } catch is CocoaError {
        }
        let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in localRepository }
        )
        #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == nil)
        #expect(try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == nil)

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable = result else {
            Issue.record("Expected strict failure for staged core state, got \(result)")
            return
        }
        #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == nil)
        #expect(try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == nil)
    }

    @Test("completed core snapshot with missing local state is rejected without local synthesis")
    func completedCoreSnapshotWithMissingLocalStateIsRejectedWithoutSynthesis() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.missing-local.core"
        )
        let completedLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.missing-local.completed"
        )
        let emptyLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.missing-local.empty"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(completedLocalQueue)
        try WorkspaceLocalMigrations.migrate(emptyLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let seedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: completedLocalQueue)
            }
        )
        try seedBackend.save(
            .emptyTopologyFixture(workspace: .emptyFixture(id: workspaceId, name: "Missing Local"))
        )
        let emptyLocalRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: emptyLocalQueue
        )
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in emptyLocalRepository }
        )
        #expect(try emptyLocalRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == nil)

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable = result else {
            Issue.record("Expected strict failure for missing local state, got \(result)")
            return
        }
        #expect(try emptyLocalRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == nil)
    }

    @Test("valid completed snapshot loads exactly without changing selection or completion tokens")
    func validCompletedSnapshotLoadsWithoutMutation() async throws {
        let workspaceId = UUIDv7.generate()
        let completedAt = Date(timeIntervalSince1970: 42)
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.valid.core"
        )
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.valid.local"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        let backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in localRepository }
        )
        try backend.save(
            .emptyTopologyFixture(
                workspace: .emptyFixture(id: workspaceId, name: "Exact Snapshot", updatedAt: completedAt)
            )
        )
        let selectionBeforeLoad = try activeWorkspaceSelection(in: coreQueue)
        let coreCompletionBeforeLoad = try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(
            workspaceId: workspaceId
        )
        let localCompletionBeforeLoad = try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt()
        let datastore = workspaceSQLiteDatastore(from: backend)

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot, let recoveryEvents) = result else {
            Issue.record("Expected exact completed snapshot load, got \(result)")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(snapshot.name == "Exact Snapshot")
        #expect(snapshot.updatedAt == completedAt)
        #expect(recoveryEvents.isEmpty)
        #expect(try activeWorkspaceSelection(in: coreQueue) == selectionBeforeLoad)
        #expect(
            try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId)
                == coreCompletionBeforeLoad
        )
        #expect(try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == localCompletionBeforeLoad)
    }
}

private struct StrictReadActiveWorkspaceSelection: Equatable {
    let workspaceId: String?
    let updatedAt: Double
}

private func activeWorkspaceSelection(
    in databaseQueue: DatabaseQueue
) throws -> StrictReadActiveWorkspaceSelection {
    try databaseQueue.read { database in
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT active_workspace_id, updated_at FROM app_workspace_selection WHERE singleton_id = 1"
            )
        else {
            throw StrictReadSelectionError.missingSelectionRow
        }
        return StrictReadActiveWorkspaceSelection(
            workspaceId: row["active_workspace_id"],
            updatedAt: row["updated_at"]
        )
    }
}

private enum StrictReadSelectionError: Error {
    case missingSelectionRow
}

private func makeStrictReadTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "agentstudio-strict-read-\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func seedStrictReadWorkspace(
    workspaceId: UUID,
    factory: WorkspaceSQLiteDatastoreFactory
) async throws {
    let datastore = factory.makeDatastore()
    try await datastore.saveWorkspaceSnapshotBundle(
        .emptyTopologyFixture(
            workspace: .emptyFixture(id: workspaceId, name: "Strict Local Corruption")
        )
    )
}

private func removeSQLiteSidecarsIfPresent(for databaseURL: URL) throws {
    for sidecarURL in [
        URL(filePath: "\(databaseURL.path)-wal"),
        URL(filePath: "\(databaseURL.path)-shm"),
    ] where FileManager.default.fileExists(atPath: sidecarURL.path) {
        try FileManager.default.removeItem(at: sidecarURL)
    }
}

private func containsQuarantineArtifact(in directory: URL) throws -> Bool {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).contains { $0.lastPathComponent.contains(".corrupt-") }
}
