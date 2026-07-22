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
            localDatabaseURL: rootDirectory.appending(path: "local.sqlite")
        ).makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .uninitialized = result else {
            Issue.record("Expected newly created SQLite to be uninitialized, got \(result)")
            return
        }
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
            localDatabaseURL: rootDirectory.appending(path: "local.sqlite")
        ).makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable(let failure) = result else {
            Issue.record("Expected pre-existing empty SQLite to be unavailable, got \(result)")
            return
        }
        #expect(failure.description.contains("preexistingDatabaseHasNoWorkspaceRows"))
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
            localDatabaseURL: rootDirectory.appending(path: "local.sqlite")
        ).makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .unavailable = result else {
            Issue.record("Expected corrupt core SQLite to be unavailable, got \(result)")
            return
        }
        #expect(try Data(contentsOf: coreDatabaseURL) == corruptBytes)
        #expect(try !containsQuarantineArtifact(in: rootDirectory))
    }

    @Test("corrupt local database is quarantined while authoritative core loads with local defaults")
    func corruptLocalDatabaseDefaultsWithoutBlockingAuthoritativeCore() async throws {
        let workspaceId = UUIDv7.generate()
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "corrupt-local")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
        let seededSnapshot = makeStrictReadNonemptySnapshot(workspaceId: workspaceId)
        try await seedStrictReadWorkspace(workspace: seededSnapshot, factory: factory)
        try removeSQLiteSidecarsIfPresent(for: localDatabaseURL)
        let corruptBytes = Data("strict startup must not replace corrupt local SQLite".utf8)
        try corruptBytes.write(to: localDatabaseURL)
        let datastore = factory.makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = result else {
            Issue.record("Expected authoritative core with local defaults, got \(result)")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(snapshot.activeTabId == seededSnapshot.tabs.single?.id)
        #expect(snapshot.tabs.single?.activeArrangementId == seededSnapshot.tabs.single?.defaultArrangement.id)
        #expect(snapshot.tabs.single?.activePaneId == seededSnapshot.panes.single?.id)
        #expect(snapshot.panes.single?.drawer?.isExpanded == false)
        #expect(snapshot.sidebarWidth == 250)
        #expect(try containsQuarantineArtifact(in: rootDirectory))

        guard case .loaded(let settings) = await datastore.loadWorkspaceSettings(workspaceId: workspaceId) else {
            Issue.record("Expected the reset local database to remain readable")
            return
        }
        #expect(
            settings.recoveryEvents.contains { event in
                event.workspaceId == workspaceId && event.recovery == .quarantinedAndReset
            }
        )
    }

    @Test("missing local database is recreated while authoritative core loads with local defaults")
    func missingLocalDatabaseDefaultsWithoutBlockingAuthoritativeCore() async throws {
        let workspaceId = UUIDv7.generate()
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "missing-local")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
        let seededSnapshot = makeStrictReadNonemptySnapshot(workspaceId: workspaceId)
        try await seedStrictReadWorkspace(workspace: seededSnapshot, factory: factory)
        try removeSQLiteDatabaseAndSidecars(for: localDatabaseURL)
        let datastore = factory.makeDatastore()

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = result else {
            Issue.record("Expected authoritative core with local defaults, got \(result)")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(snapshot.activeTabId == seededSnapshot.tabs.single?.id)
        #expect(snapshot.tabs.single?.activeArrangementId == seededSnapshot.tabs.single?.defaultArrangement.id)
        #expect(snapshot.tabs.single?.activePaneId == seededSnapshot.panes.single?.id)
        #expect(snapshot.panes.single?.drawer?.isExpanded == false)
        #expect(snapshot.sidebarWidth == 250)
        #expect(FileManager.default.fileExists(atPath: localDatabaseURL.path))
        #expect(try !containsQuarantineArtifact(in: rootDirectory))
    }

    @Test("older core schema migrates then rejection is byte-preserving")
    func olderCoreSchemaMigratesThenRejectionIsBytePreserving() async throws {
        // Arrange
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "older-core")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let migrationPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.strict-read.older-core.setup"
        )
        try WorkspaceCoreMigrations.migrator.migrate(migrationPool, upTo: "009_drop_pane_source_binding")
        try migrationPool.close()
        try WorkspaceSQLiteStartupSchemaPreparer.migratePreexistingDatabaseIfRequired(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.strict-read.older-core.preparer",
            migrator: WorkspaceCoreMigrations.migrator
        )
        let postMigrationBaseline = try strictReadDatabaseFiles(at: coreDatabaseURL)
        let postMigrationInventory = try strictReadDirectoryInventory(rootDirectory)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: rootDirectory.appending(path: "local.sqlite")
        ).makeDatastore()

        // Act
        let result = await datastore.loadWorkspaceSnapshot()

        // Assert
        guard case .unavailable(let failure) = result else {
            Issue.record("Expected migrated empty core SQLite to be rejected, got \(result)")
            return
        }
        #expect(failure.description.contains("preexistingDatabaseHasNoWorkspaceRows"))
        #expect(try strictReadDatabaseFiles(at: coreDatabaseURL) == postMigrationBaseline)
        #expect(try strictReadDirectoryInventory(rootDirectory) == postMigrationInventory)
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

    @Test("core committed before a local open failure remains readable")
    func coreCommittedBeforeLocalOpenFailureRemainsReadable() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.local-open-failure.core"
        )
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.local-open-failure.local"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        let seededSnapshot = makeStrictReadNonemptySnapshot(workspaceId: workspaceId)
        let backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in localRepository }
        )
        try backend.save(.emptyTopologyFixture(workspace: seededSnapshot))
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in localRepository },
            makeLocalRestoreRepository: { _ in throw CocoaError(.fileReadNoPermission) }
        )
        let result = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = result else {
            Issue.record("Expected committed core state to load after local failure, got \(result)")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(snapshot.name == seededSnapshot.name)
        #expect(snapshot.activeTabId == seededSnapshot.tabs.single?.id)
        #expect(snapshot.tabs.single?.activePaneId == seededSnapshot.panes.single?.id)
        #expect(snapshot.panes.single?.drawer?.isExpanded == false)
        #expect(snapshot.sidebarWidth == 250)
    }

    @Test("core load accepts independently updated local rows")
    func coreLoadAcceptsIndependentlyUpdatedLocalRows() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.missing-local.core"
        )
        let seedLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.independent-local.seed"
        )
        let emptyLocalQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
            label: "AgentStudio.sqlite.strict-read.independent-local.current"
        )
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(seedLocalQueue)
        try WorkspaceLocalMigrations.migrate(emptyLocalQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let seedBackend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: seedLocalQueue)
            }
        )
        try seedBackend.save(
            .emptyFixture(id: workspaceId, name: "Authoritative Core", sidebarWidth: 260)
        )
        let independentLocalRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: emptyLocalQueue
        )
        try independentLocalRepository.replaceWindowState(
            .init(sidebarWidth: 420, windowFrame: nil),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in independentLocalRepository }
        )

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = result else {
            Issue.record("Expected core to load with independent local rows, got \(result)")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(snapshot.name == "Authoritative Core")
        #expect(snapshot.sidebarWidth == 420)
    }

    @Test("valid core and local rows load exactly without mutation")
    func validCoreAndLocalRowsLoadWithoutMutation() async throws {
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
        let localCursorBeforeLoad = try localRepository.fetchCursorState()
        let localWindowBeforeLoad = try localRepository.fetchWindowState()
        let datastore = workspaceSQLiteDatastore(from: backend)

        let result = await datastore.loadWorkspaceSnapshot()

        guard case .loaded(let snapshot) = result else {
            Issue.record("Expected exact core and local row load, got \(result)")
            return
        }
        #expect(snapshot.id == workspaceId)
        #expect(snapshot.name == "Exact Snapshot")
        #expect(snapshot.updatedAt == completedAt)
        #expect(try activeWorkspaceSelection(in: coreQueue) == selectionBeforeLoad)
        #expect(try localRepository.fetchCursorState() == localCursorBeforeLoad)
        #expect(try localRepository.fetchWindowState() == localWindowBeforeLoad)
    }

    @Test("preexisting valid snapshot preserves core bytes then opens a writable steady backend")
    func preexistingValidSnapshotLoadsBytePreservingThenSavesThroughWritableBackend() async throws {
        // Arrange
        let workspaceId = UUIDv7.generate()
        let rootDirectory = try makeStrictReadTemporaryDirectory(prefix: "valid-file-backed")
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
        try await seedStrictReadWorkspace(workspaceId: workspaceId, factory: factory)
        let coreFilesBeforeLoad = try strictReadDatabaseFiles(at: coreDatabaseURL)
        let datastore = factory.makeDatastore()

        // Act
        let loadResult = await datastore.loadWorkspaceSnapshot()

        // Assert
        guard case .loaded(let loadedSnapshot) = loadResult else {
            Issue.record("Expected a valid preexisting snapshot, got \(loadResult)")
            return
        }
        #expect(loadedSnapshot.id == workspaceId)
        #expect(try strictReadDatabaseFiles(at: coreDatabaseURL) == coreFilesBeforeLoad)

        let updatedAt = Date()
        let updatedSnapshot = WorkspaceSQLiteSnapshot.emptyFixture(
            id: workspaceId,
            name: "Saved After Byte-Preserving Startup",
            updatedAt: updatedAt
        )
        try await datastore.saveWorkspaceSnapshotBundle(.emptyTopologyFixture(workspace: updatedSnapshot))
        guard case .loaded(let reloadedSnapshot) = await datastore.loadWorkspaceSnapshot() else {
            Issue.record("Expected the steady writable backend to reload its save")
            return
        }
        #expect(reloadedSnapshot.name == "Saved After Byte-Preserving Startup")
        #expect(reloadedSnapshot.updatedAt.timeIntervalSince1970 == updatedAt.timeIntervalSince1970)
    }
}

private struct StrictReadDatabaseFiles: Equatable {
    enum FileBytes: Equatable {
        case missing
        case present(Data)
    }

    let database: FileBytes
    let wal: FileBytes
    let sharedMemory: FileBytes
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
    workspace: WorkspaceSQLiteSnapshot,
    factory: WorkspaceSQLiteDatastoreFactory
) async throws {
    let datastore = factory.makeDatastore()
    try await datastore.saveWorkspaceSnapshotBundle(
        .emptyTopologyFixture(workspace: workspace)
    )
}

private func seedStrictReadWorkspace(
    workspaceId: UUID,
    factory: WorkspaceSQLiteDatastoreFactory
) async throws {
    try await seedStrictReadWorkspace(
        workspace: .emptyFixture(id: workspaceId, name: "Strict Local Corruption"),
        factory: factory
    )
}

private func makeStrictReadNonemptySnapshot(workspaceId: UUID) -> WorkspaceSQLiteSnapshot {
    let pane = makePane(id: UUIDv7.generate(), title: "Strict restored pane")
    let tab = Tab(id: UUIDv7.generate(), paneId: pane.id, name: "Strict restored tab")
    return WorkspaceSQLiteSnapshot(
        id: workspaceId,
        name: "Committed Core",
        panes: [pane],
        tabs: [tab],
        activeTabId: tab.id,
        sidebarWidth: 420,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20)
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

private func removeSQLiteDatabaseAndSidecars(for databaseURL: URL) throws {
    try removeSQLiteSidecarsIfPresent(for: databaseURL)
    if FileManager.default.fileExists(atPath: databaseURL.path) {
        try FileManager.default.removeItem(at: databaseURL)
    }
}

private func strictReadDatabaseFiles(at databaseURL: URL) throws -> StrictReadDatabaseFiles {
    func bytes(at fileURL: URL) throws -> StrictReadDatabaseFiles.FileBytes {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        return try .present(Data(contentsOf: fileURL))
    }

    return try StrictReadDatabaseFiles(
        database: bytes(at: databaseURL),
        wal: bytes(at: URL(filePath: databaseURL.path + "-wal")),
        sharedMemory: bytes(at: URL(filePath: databaseURL.path + "-shm"))
    )
}

private func strictReadDirectoryInventory(_ directoryURL: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).sorted()
}

private func containsQuarantineArtifact(in directory: URL) throws -> Bool {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).contains { $0.lastPathComponent.contains(".corrupt-") }
}
