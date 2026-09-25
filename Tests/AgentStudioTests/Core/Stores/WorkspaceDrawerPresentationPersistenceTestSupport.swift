import AgentStudioInfrastructure
import Foundation
import GRDB

@testable import AgentStudioCore

/// File-backed databases reopened by each simulated drawer-presentation boot.
@MainActor
struct DrawerPresentationDatabases {
    let directory: URL
    var coreDatabaseURL: URL { directory.appending(path: "core.sqlite") }
    /// Local lives in its own directory so a test can make only local recovery fail.
    var localDirectory: URL { directory.appending(path: "local") }
    var localDatabaseURL: URL { localDirectory.appending(path: "local.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-drawer-presentation-\(UUIDv7.generate().uuidString)"
        )
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeDatastore(legacySource: LegacyDrawerPresentationSource?) -> WorkspaceSQLiteDatastoreActor {
        WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL,
            legacyDrawerPresentationSource: legacySource
        ).makeDatastore()
    }

    func bootStore(legacySource: LegacyDrawerPresentationSource? = nil) async throws -> WorkspaceStore {
        let datastore = makeDatastore(legacySource: legacySource)
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            throw DrawerPresentationTestFailure.databasesNotPrepared
        }
        let store = WorkspaceStore(sqliteDatastore: datastore, startsObserving: false)
        switch await store.loadCanonicalComposition() {
        case .loaded, .initializedDefaultWorkspace:
            return store
        case let other:
            throw DrawerPresentationTestFailure.loadFailed(String(describing: other))
        }
    }

    func storedOwnerPaneIds(workspaceId: UUID) throws -> Set<UUID> {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        let ids = try queue.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT owner_pane_id FROM local_drawer_presentation WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        }
        return Set(ids.compactMap(UUID.init(uuidString:)))
    }

    func coreOwningPaneIds(workspaceId: UUID) throws -> Set<UUID> {
        let coreRepository = WorkspaceCoreRepository(
            databaseWriter: try DatabaseQueue(path: coreDatabaseURL.path)
        )
        return try coreRepository.fetchOwningLayoutPaneIDsByWorkspace()[workspaceId] ?? []
    }

    /// The incomplete local file set a crash can leave: the main file is gone
    /// and only an orphan WAL remains.
    func replaceLocalDatabaseWithOrphanWAL() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: "\(localDatabaseURL.path)\(suffix)")
        }
        try Data("orphan wal".utf8).write(to: URL(fileURLWithPath: "\(localDatabaseURL.path)-wal"))
    }

    /// A read-only local directory makes local quarantine fail while core stays writable.
    func setLocalDirectoryWritable(_ isWritable: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: isWritable ? 0o755 : 0o555],
            ofItemAtPath: localDirectory.path
        )
    }

    func storedRatio(workspaceId: UUID, ownerPaneId: UUID) throws -> Double? {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        return try queue.read { database in
            try Double.fetchOne(
                database,
                sql: """
                    SELECT normal_height_ratio FROM local_drawer_presentation
                    WHERE workspace_id = ? AND owner_pane_id = ?
                    """,
                arguments: [workspaceId.uuidString, ownerPaneId.uuidString]
            )
        }
    }

    /// Returns the local database to its exact pre-upgrade shape: every other
    /// local row stays, only the drawer presentation schema step is undone.
    func rewindLocalSchemaBeforeDrawerPresentation() throws {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        try queue.write { database in
            try database.execute(sql: "DROP TABLE local_drawer_presentation")
            try database.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: [WorkspaceLocalMigrations.drawerPresentationMigrationIdentifier]
            )
        }
    }

    func writeRawPresentationRow(workspaceId: UUID, ownerPaneId: UUID, ratioSQL: String, zoomSide: String) throws {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        try queue.write { database in
            try database.execute(
                sql: """
                    INSERT OR REPLACE INTO local_drawer_presentation(
                        workspace_id, owner_pane_id, normal_height_ratio, zoom_side, updated_at
                    )
                    VALUES (?, ?, \(ratioSQL), ?, 0)
                    """,
                arguments: [workspaceId.uuidString, ownerPaneId.uuidString, zoomSide]
            )
        }
    }
}

private enum DrawerPresentationTestFailure: Error {
    case databasesNotPrepared
    case loadFailed(String)
}

/// Stand-in for the retired defaults key and its import cutoff, so tests never
/// touch a real defaults domain.
final class LegacyHeightValueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Double?
    private var storedImportCutoff: Date?

    init(value: Double?) {
        storedValue = value
    }

    var value: Double? {
        lock.withLock { storedValue }
    }

    var importCutoff: Date? {
        lock.withLock { storedImportCutoff }
    }

    var source: LegacyDrawerPresentationSource {
        LegacyDrawerPresentationSource(
            readHeightRatio: { [self] in lock.withLock { storedValue } },
            readImportCutoff: { [self] in lock.withLock { storedImportCutoff } },
            writeImportCutoff: { [self] importCutoff in lock.withLock { storedImportCutoff = importCutoff } },
            clear: { [self] in
                lock.withLock {
                    storedValue = nil
                    storedImportCutoff = nil
                }
            }
        )
    }
}
