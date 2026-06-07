import Foundation
import GRDB
import os.log

private let workspaceSQLiteBackendFactoryLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceSQLiteStoreBackendFactory"
)

@MainActor
struct WorkspaceSQLiteStoreBackendFactory {
    var coreDatabaseURL: URL
    var localDatabaseURL: @MainActor (UUID) -> URL
    var recoveryReporter: PersistenceRecoveryReporter?

    init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: @escaping @MainActor (UUID) -> URL = { workspaceId in
            AppDataPaths.workspaceLocalSQLiteURL(workspaceId: workspaceId)
        },
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.coreDatabaseURL = coreDatabaseURL
        self.localDatabaseURL = localDatabaseURL
        self.recoveryReporter = recoveryReporter
    }

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

    private func openBackend() throws -> WorkspaceSQLiteStoreBackend {
        let coreDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.core"
        )
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
                    recoveryReporter?(
                        .init(
                            store: .workspace,
                            workspaceId: workspaceId,
                            recovery: quarantine.succeeded ? .quarantinedAndReset : .quarantineFailed,
                            quarantinedFilename: quarantine.recoveryFilename
                        )
                    )
                    if quarantine.succeeded {
                        do {
                            _ = try makeLocalRepository(workspaceId: workspaceId)
                        } catch {
                            workspaceSQLiteBackendFactoryLogger.error(
                                "Failed to prepare local SQLite workspace backend after quarantine: \(error.localizedDescription)"
                            )
                        }
                    }
                    throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(workspaceId)
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

private enum WorkspaceSQLiteRecoveryClassifier {
    static func shouldQuarantine(_ error: any Error) -> Bool {
        ResultCode.SQLITE_CORRUPT ~= error || ResultCode.SQLITE_NOTADB ~= error
    }
}
