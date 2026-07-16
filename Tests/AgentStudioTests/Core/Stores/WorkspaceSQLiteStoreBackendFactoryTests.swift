import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreBackendFactoryTests", .serialized)
struct WorkspaceSQLiteStoreBackendFactoryTests {
    @Test("pending migration 009 creates a verified pre-009 core backup")
    func pendingMigration009CreatesVerifiedPre009CoreBackup() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pre009-backup-\(UUID().uuidString)")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        do {
            let setupPool = try SQLiteDatabaseFactory.makeFileBackedPool(
                at: coreSQLiteURL,
                label: "AgentStudio.pre009.setup"
            )
            try WorkspaceCoreMigrations.migrator.migrate(setupPool, upTo: "007_stage_workspace_sqlite_snapshot_status")
            try setupPool.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO workspace(id, name, created_at, updated_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, "Pre-009", 1.0, 1.0]
                )
            }
        }

        let factory = WorkspaceSQLiteStoreBackendFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            }
        )

        _ = try #require(factory.makeBackend())

        let backupURL = WorkspaceSQLiteStoreBackendFactory.pre009BackupURL(coreDatabaseURL: coreSQLiteURL)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        let backupQueue = try DatabaseQueue(
            path: backupURL.path,
            configuration: SQLiteDatabaseFactory.makeConfiguration(label: "AgentStudio.pre009.backup.verify")
        )
        let backupColumns = try backupQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(pane)")
                .map { row in row["name"] as String }
        }
        let backupTerminalColumns = try backupQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(pane_content_terminal)")
                .map { row in row["name"] as String }
        }
        #expect(backupColumns.contains("source_kind"))
        #expect(backupColumns.contains("source_repo_id"))
        #expect(!backupColumns.contains("facet_repo_id"))
        #expect(!backupTerminalColumns.contains("zmx_session_id"))

        let migratedPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreSQLiteURL,
            label: "AgentStudio.pre009.migrated.verify"
        )
        let migratedColumns = try migratedPool.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(pane)")
                .map { row in row["name"] as String }
        }
        let migratedTerminalColumns = try migratedPool.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(pane_content_terminal)")
                .map { row in row["name"] as String }
        }
        #expect(!migratedColumns.contains("source_kind"))
        #expect(migratedColumns.contains("facet_repo_id"))
        #expect(migratedTerminalColumns.contains("zmx_session_id"))
    }

    @Test("pre-009 backup restore replaces core database and removes stale sidecars")
    func pre009BackupRestoreReplacesCoreDatabaseAndRemovesStaleSidecars() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pre009-restore-\(UUID().uuidString)")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let backupURL = WorkspaceSQLiteStoreBackendFactory.pre009BackupURL(coreDatabaseURL: coreSQLiteURL)
        do {
            let backupPool = try SQLiteDatabaseFactory.makeFileBackedPool(
                at: backupURL,
                label: "AgentStudio.pre009.restore.backup"
            )
            try WorkspaceCoreMigrations.migrator.migrate(backupPool, upTo: "008_add_zmx_session_id")
        }

        do {
            let migratedPool = try SQLiteDatabaseFactory.makeFileBackedPool(
                at: coreSQLiteURL,
                label: "AgentStudio.pre009.restore.current"
            )
            try WorkspaceCoreMigrations.migrate(migratedPool)
        }
        try Data("stale wal".utf8).write(to: URL(filePath: "\(coreSQLiteURL.path)-wal"))
        try Data("stale shm".utf8).write(to: URL(filePath: "\(coreSQLiteURL.path)-shm"))

        try WorkspaceSQLiteStoreBackendFactory.restorePre009Backup(coreDatabaseURL: coreSQLiteURL)

        #expect(!FileManager.default.fileExists(atPath: "\(coreSQLiteURL.path)-wal"))
        #expect(!FileManager.default.fileExists(atPath: "\(coreSQLiteURL.path)-shm"))
        let restoredQueue = try DatabaseQueue(
            path: coreSQLiteURL.path,
            configuration: SQLiteDatabaseFactory.makeConfiguration(label: "AgentStudio.pre009.restored.verify")
        )
        let restoredColumns = try restoredQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(pane)")
                .map { row in row["name"] as String }
        }
        #expect(restoredColumns.contains("source_kind"))
        #expect(restoredColumns.contains("source_repo_id"))
        #expect(!restoredColumns.contains("facet_repo_id"))
    }

    @Test("corrupt core SQLite is quarantined and recreated before legacy workspace import")
    func corruptCoreSQLiteIsQuarantinedAndRecreatedBeforeLegacyWorkspaceImport() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-sqlite-factory-\(UUID().uuidString)")
        let workspacesDirectory = rootDirectory.appending(path: "workspaces")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try Data("not a sqlite database".utf8).write(to: coreSQLiteURL)

        let workspaceId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_001_000)
        let pane = Pane(
            content: .terminal(.init(provider: .zmx, lifetime: .persistent)),
            metadata: .init(
                createdAt: createdAt,
                title: "Legacy After Corruption"
            )
        )
        let tab = Tab(paneId: pane.id, name: "Imported Tab")
        let legacyPersistor = WorkspacePersistor(workspacesDir: workspacesDirectory)
        #expect(legacyPersistor.ensureDirectory())
        try legacyPersistor.save(
            .init(
                id: workspaceId,
                name: "Legacy Reimport Workspace",
                panes: [pane],
                tabs: [tab],
                activeTabId: tab.id,
                createdAt: createdAt,
                updatedAt: Date(timeIntervalSince1970: 1_700_001_100)
            )
        )

        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let factory = WorkspaceSQLiteStoreBackendFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { workspaceId in
                rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
            },
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        let backend = try #require(factory.makeBackend())
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            persistor: legacyPersistor,
            sqliteDatastore: workspaceSQLiteDatastore(from: backend),
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        await store.restoreAsync()

        #expect(store.identityAtom.workspaceId == workspaceId)
        #expect(store.identityAtom.workspaceName == "Legacy Reimport Workspace")
        #expect(store.paneAtom.pane(pane.id)?.title == "Legacy After Corruption")
        #expect(try backend.coreRepository.fetchWorkspace(id: workspaceId)?.name == "Legacy Reimport Workspace")
        #expect(
            recoveryEvents.contains { event in
                event.store == .workspace
                    && event.recovery == .quarantinedAndReset
                    && event.quarantinedFilename?.contains("core.sqlite.corrupt-") == true
            }
        )
        #expect(FileManager.default.fileExists(atPath: coreSQLiteURL.path))
    }

    @Test("corrupt local SQLite is quarantined and does not replay stale legacy UI")
    func corruptLocalSQLiteIsQuarantinedAndDoesNotReplayStaleLegacyUI() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-local-sqlite-factory-\(UUID().uuidString)")
        let workspacesDirectory = rootDirectory.appending(path: "workspaces")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let workspaceId = UUID()
        let localSQLiteURL = rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
        try Data("not a sqlite database".utf8).write(to: localSQLiteURL)

        let legacyPersistor = WorkspacePersistor(workspacesDir: workspacesDirectory)
        #expect(legacyPersistor.ensureDirectory())
        try legacyPersistor.saveUI(
            .init(
                workspaceId: workspaceId,
                filterText: "stale legacy",
                isFilterVisible: true,
                sidebarCollapsed: true,
                sidebarSurface: .inbox
            )
        )

        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let factory = WorkspaceSQLiteStoreBackendFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { _ in localSQLiteURL },
            recoveryReporter: { event in recoveryEvents.append(event) }
        )
        let backend = try #require(factory.makeBackend())
        let sidebarState = WorkspaceSidebarState()
        let uiStateStore = UIStateStore(
            atom: sidebarState,
            editorChooserState: EditorChooserState(),
            persistor: legacyPersistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: backend.localBackend),
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        await uiStateStore.restoreAsync(for: workspaceId)

        #expect(sidebarState.filterText.isEmpty)
        #expect(sidebarState.filterText != "stale legacy")
        #expect(sidebarState.sidebarSurface == .repos)
        #expect(!uiStateStore.canArchiveLegacyUIFile)
        let workspaceRecoveryEvent = recoveryEvents.first { event in
            event.store == .workspace
                && event.workspaceId == workspaceId
                && event.recovery == .quarantinedAndReset
        }
        #expect(
            workspaceRecoveryEvent?.quarantinedFilename?.contains(".local.sqlite.corrupt-") == true,
            "Recovery events: \(recoveryEvents)"
        )
        #expect(FileManager.default.fileExists(atPath: localSQLiteURL.path))
        let recoveredRepository = try backend.localBackend.repository(for: workspaceId)
        #expect(try recoveredRepository.fetchSidebarState() == nil)
        let restoredRecoveredRepository = try backend.localBackend.restoreRepository(for: workspaceId)
        #expect(try restoredRecoveredRepository.fetchSidebarState() == nil)
    }

    @Test("workspace store restore reports corrupt local SQLite recovery")
    func workspaceStoreRestoreReportsCorruptLocalSQLiteRecovery() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-workspace-store-local-recovery-\(UUID().uuidString)")
        let workspacesDirectory = rootDirectory.appending(path: "workspaces")
        let coreSQLiteURL = rootDirectory.appending(path: "core.sqlite")
        let workspaceId = UUID()
        let localSQLiteURL = rootDirectory.appending(path: "\(workspaceId.uuidString).local.sqlite")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { _ in localSQLiteURL }
        )
        try await factory.makeDatastore().saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(
                workspace: .emptyFixture(id: workspaceId, name: "Store Recovery Source")
            )
        )
        try Data("not a sqlite database".utf8).write(to: localSQLiteURL)
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.replaceIdentity(
            workspaceId: workspaceId,
            workspaceName: "Before Restore",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(workspacesDir: workspacesDirectory),
            sqliteDatastore: factory.makeDatastore(),
            recoveryReporter: { recoveryEvents.append($0) }
        )

        await store.restoreAsync()

        #expect(store.identityAtom.workspaceId == workspaceId)
        #expect(store.identityAtom.workspaceName == "Store Recovery Source")
        #expect(
            recoveryEvents.contains { event in
                event.store == .workspace
                    && event.workspaceId == workspaceId
                    && event.recovery == .quarantinedAndReset
                    && event.quarantinedFilename?.contains(".local.sqlite.corrupt-") == true
            },
            "Recovery events: \(recoveryEvents)"
        )
    }

    @Test("non-corruption core open failure does not quarantine database sidecars")
    func nonCorruptionCoreOpenFailureDoesNotQuarantineDatabaseSidecars() async throws {
        let parentDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-sqlite-blocked-parent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true
        )
        let blockingRootURL = parentDirectory.appending(path: "blocked-root")
        try Data("not a directory".utf8).write(to: blockingRootURL)
        let coreSQLiteURL = blockingRootURL.appending(path: "core.sqlite")
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let factory = WorkspaceSQLiteStoreBackendFactory(
            coreDatabaseURL: coreSQLiteURL,
            localDatabaseURL: { workspaceId in
                blockingRootURL.appending(path: "\(workspaceId.uuidString).local.sqlite")
            },
            recoveryReporter: { event in recoveryEvents.append(event) }
        )

        let backend = factory.makeBackend()

        #expect(backend == nil)
        #expect(FileManager.default.fileExists(atPath: blockingRootURL.path))
        #expect(
            !recoveryEvents.contains { event in
                event.store == .workspace
                    && (event.recovery == .quarantinedAndReset || event.recovery == .quarantineFailed)
            }
        )
        #expect(!FileManager.default.fileExists(atPath: coreSQLiteURL.path))
        #expect(
            try FileManager.default.contentsOfDirectory(at: parentDirectory, includingPropertiesForKeys: nil)
                .allSatisfy { !$0.lastPathComponent.contains(".corrupt-") }
        )
    }
}
