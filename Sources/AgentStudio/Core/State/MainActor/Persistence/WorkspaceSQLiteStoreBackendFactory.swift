import Foundation
import GRDB
import os.log

private let workspaceSQLiteBackendFactoryLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceSQLiteStoreBackendFactory"
)

struct WorkspaceSQLiteStoreBackendFactory {
    var coreDatabaseURL: URL
    var localDatabaseURL: @Sendable (UUID) -> URL
    var recoveryReporter: PersistenceRecoveryReporter?

    init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: @escaping @Sendable (UUID) -> URL = { workspaceId in
            AppDataPaths.workspaceLocalSQLiteURL(workspaceId: workspaceId)
        },
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.coreDatabaseURL = coreDatabaseURL
        self.localDatabaseURL = localDatabaseURL
        self.recoveryReporter = recoveryReporter
    }

    @MainActor
    func makeBackend() -> WorkspaceSQLiteStoreBackend? {
        do {
            return try openBackend()
        } catch {
            workspaceSQLiteBackendFactoryLogger.error(
                "Failed to prepare SQLite workspace backend before quarantine: \(error.localizedDescription)"
            )
            guard WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(error) else {
                return nil
            }
        }

        let quarantine = SQLiteSidecarQuarantine.quarantine(databaseURL: coreDatabaseURL)
        recoveryReporter?(
            .init(
                store: .workspace,
                workspaceId: nil,
                recovery: quarantine.succeeded ? .quarantinedAndReset : .quarantineFailed,
                quarantinedFilename: quarantine.recoveryFilename
            )
        )

        do {
            return try openBackend()
        } catch {
            workspaceSQLiteBackendFactoryLogger.error(
                "Failed to prepare SQLite workspace backend after quarantine: \(error.localizedDescription)"
            )
            recoveryReporter?(
                .init(
                    store: .workspace,
                    workspaceId: nil,
                    recovery: .resetToDefaults
                )
            )
            return nil
        }
    }

    @MainActor
    private func openBackend() throws -> WorkspaceSQLiteStoreBackend {
        let coreDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.core"
        )
        _ = try preparePre009BackupIfNeeded(coreDatabasePool)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabasePool)
        try coreRepository.migrate()
        return WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { workspaceId in
                try makeLocalRepository(workspaceId: workspaceId)
            },
            makeLocalRestoreRepository: { workspaceId in
                do {
                    return try makeLocalRepository(workspaceId: workspaceId)
                } catch {
                    workspaceSQLiteBackendFactoryLogger.error(
                        "Failed to prepare local SQLite workspace backend before quarantine: \(error.localizedDescription)"
                    )
                    guard WorkspaceSQLiteRecoveryClassifier.shouldQuarantine(error) else {
                        throw error
                    }
                    let quarantine = SQLiteSidecarQuarantine.quarantine(
                        databaseURL: localDatabaseURL(workspaceId)
                    )
                    guard quarantine.succeeded else {
                        throw WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(
                            workspaceId,
                            quarantinedFilename: quarantine.recoveryFilename
                        )
                    }
                    do {
                        _ = try makeLocalRepository(workspaceId: workspaceId)
                    } catch {
                        workspaceSQLiteBackendFactoryLogger.error(
                            "Failed to prepare local SQLite workspace backend after quarantine: \(error.localizedDescription)"
                        )
                    }
                    throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(
                        workspaceId,
                        quarantinedFilename: quarantine.recoveryFilename
                    )
                }
            },
            legacyImportDecision: { workspaceId, lane in
                guard
                    let status = try coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId)
                else {
                    return .allowImport
                }
                switch lane {
                case .local:
                    return status.localImportedAt == nil ? .allowImport : .blockReplayAllowArchive
                case .cache:
                    return status.cacheImportedAt == nil ? .allowImport : .blockReplayAllowArchive
                }
            }
        )
    }

    private func preparePre009BackupIfNeeded(_ databasePool: DatabasePool) throws -> Bool {
        let shouldCreateBackup = try databasePool.read { database in
            try WorkspaceCoreMigrations.isDropPaneSourceBindingMigrationPending(database)
        }
        guard shouldCreateBackup else { return false }

        try databasePool.writeWithoutTransaction { database in
            _ = try Row.fetchAll(database, sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
        try Self.createVerifiedPre009Backup(coreDatabaseURL: coreDatabaseURL)
        return true
    }

    static func pre009BackupURL(coreDatabaseURL: URL) -> URL {
        URL(filePath: "\(coreDatabaseURL.path).pre-009-backup")
    }

    static func restorePre009Backup(coreDatabaseURL: URL) throws {
        let fileManager = FileManager.default
        let backupURL = pre009BackupURL(coreDatabaseURL: coreDatabaseURL)
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw WorkspaceSQLiteStoreBackendFactoryError.missingPre009Backup(backupURL)
        }
        try verifySQLiteDatabase(at: backupURL)

        try removeSQLiteSidecars(for: coreDatabaseURL)
        if fileManager.fileExists(atPath: coreDatabaseURL.path) {
            try fileManager.removeItem(at: coreDatabaseURL)
        }
        try fileManager.copyItem(at: backupURL, to: coreDatabaseURL)
        try removeSQLiteSidecars(for: coreDatabaseURL)
        try verifySQLiteDatabase(at: coreDatabaseURL)
        try removeSQLiteSidecars(for: coreDatabaseURL)
    }

    private static func createVerifiedPre009Backup(coreDatabaseURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: coreDatabaseURL.path) else { return }

        let backupURL = pre009BackupURL(coreDatabaseURL: coreDatabaseURL)
        let tempURL =
            backupURL
            .deletingLastPathComponent()
            .appending(path: "\(backupURL.lastPathComponent).tmp-\(UUID().uuidString)")
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }
        try fileManager.copyItem(at: coreDatabaseURL, to: tempURL)
        do {
            try verifySQLiteDatabase(at: tempURL)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: tempURL, to: backupURL)
            try verifySQLiteDatabase(at: backupURL)
            workspaceSQLiteBackendFactoryLogger.info(
                "Created pre-009 core SQLite backup at \(backupURL.path, privacy: .public)"
            )
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private static func verifySQLiteDatabase(at databaseURL: URL) throws {
        let queue = try DatabaseQueue(
            path: databaseURL.path,
            configuration: SQLiteDatabaseFactory.makeConfiguration(
                label: "AgentStudio.sqlite.pre-009-backup.verify"
            )
        )
        let quickCheck = try queue.read { database in
            try String.fetchOne(database, sql: "PRAGMA quick_check")
        }
        guard quickCheck == "ok" else {
            throw WorkspaceSQLiteStoreBackendFactoryError.invalidPre009Backup(databaseURL)
        }
    }

    private static func removeSQLiteSidecars(for databaseURL: URL) throws {
        let fileManager = FileManager.default
        for sidecarURL in [
            URL(filePath: "\(databaseURL.path)-wal"),
            URL(filePath: "\(databaseURL.path)-shm"),
        ] {
            if fileManager.fileExists(atPath: sidecarURL.path) {
                try fileManager.removeItem(at: sidecarURL)
            }
        }
    }

    private func makeLocalRepository(workspaceId: UUID) throws -> WorkspaceLocalRepository {
        let localDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: localDatabaseURL(workspaceId),
            label: "AgentStudio.sqlite.local.\(workspaceId.uuidString)"
        )
        let localRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localDatabasePool
        )
        try localRepository.migrate()
        return localRepository
    }
}

enum WorkspaceSQLiteStoreBackendFactoryError: Error, LocalizedError {
    case missingPre009Backup(URL)
    case invalidPre009Backup(URL)

    var errorDescription: String? {
        switch self {
        case .missingPre009Backup(let url):
            "Missing pre-009 core SQLite backup at \(url.path)"
        case .invalidPre009Backup(let url):
            "Invalid pre-009 core SQLite backup at \(url.path)"
        }
    }
}
